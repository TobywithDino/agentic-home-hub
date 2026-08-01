# 鬼故事：那次部署順手 `rm -rf` 把正式環境的密碼燒了

> 深夜部署系列 #1。技術鬼故事，記錄一次真實發生在 `aiwave-api` 正式環境上的自傷事故：起因、經過、補救、以及事後怎麼防止重演。給後來每一個要手動部署到 EC2 的人看。

---

## TL;DR

在幫 `mms_review_summary_service`/`mms_review_summary_vendor` 新增 `service_name`/`vendor_name` 欄位、要把新版 `api_server` 部署上 EC2 時，為了「確保乾淨解壓、不留舊檔案殘骸」，在 SSM 指令裡加了一行：

```bash
rm -rf api_server database
```

這一行把 EC2 上 `/home/ssm-user/aiwave/api_server/.env` 整個刪掉了——裡面存著 **RDS 資料庫密碼** 和 **PII 欄位的 AES-256-GCM 加密金鑰**，兩者都**沒有任何備份**。`.env` 本來就在 `.gitignore` 裡，不會進 git；本機也沒有這台 EC2 的 `.env` 副本；AWS Secrets Manager / SSM Parameter Store 也沒有存這組值。

結果：`aiwave-api` service 因為讀不到 `.env` 進入開機失敗迴圈（撞上 systemd 的 `StartLimitBurst` 保護機制），整個 API 掛掉。事後花了約 15 分鐘用 `aws rds modify-db-instance` 重設密碼、重新產生一組新的加密金鑰、重建 `.env`，才把服務救回來。

**PII 金鑰遺失是不可逆的**：舊金鑰加密過的 `user_accounts`/`vendor_accounts` 個資欄位（`contact_name`/`contact_mobile`/`contact_email`），新金鑰配不上，變成永久解不開的密文垃圾。所幸受影響範圍只是 7 筆種子測試帳號的假資料（`user01~04`/`vendor01~03`，非真實用戶個資），用 `patch_test_pii.ps1` 重新補寫了一次就恢復demo可視效果。真實用戶個資如果發生同樣事故，這句話後面接的就不是「重新補寫」，而是「聯絡受影響用戶」。

---

## 時間線（2026-08-01 21:30 ~ 21:48 UTC）

| 時間(UTC) | 事件 |
|---|---|
| 21:30 | 打包本機 `database/` + `api_server/` 成 tar.gz，上傳 S3，第一次嘗試解壓部署 |
| 21:32 | 第一次解壓因 Windows `tar.exe` 打包出的檔案本身不完整（本機問題，非傳輸問題）而 `Unexpected EOF`，但 service 意外重啟"成功"（其實是跑舊程式碼） |
| 21:33 | 重新打包（清掉本機殘留的 `__pycache__` 後）、重新上傳、重新解壓，確認 `summaries.py` 有進去 |
| 21:36 | **為求乾淨，在解壓前加了 `rm -rf api_server database`**，導致 `.env` 一併被刪除 |
| 21:36 | `aiwave-api` 開始因缺少 `.env` 反覆重啟失敗，撞上 `systemd` `StartLimitBurst`，`Failed with result 'resources'` |
| 21:38 | 用 `journalctl -u aiwave-api` 查出真正錯誤原因：`Failed to load environment files: No such file or directory` |
| 21:38 | 確認 `.env` 真的沒有任何備份（本機、Secrets Manager、SSM Parameter Store 都搜過） |
| 21:39 | 停手，向使用者說明狀況與風險，等待決策指示 |
| 21:44 | 取得授權：重設 RDS 密碼 + 產生新 PII 金鑰 |
| 21:44 | `aws rds modify-db-instance --master-user-password ... --apply-immediately` |
| 21:45 | RDS 密碼狀態轉為 `resetting-master-credentials` → `available` |
| 21:45 | 在 EC2 用 `cat > .env << 'EOF'` 重建含新密碼與新金鑰的 `.env`，`chmod 600` |
| 21:45 | `systemctl reset-failed` + `systemctl restart aiwave-api`，服務恢復 `active (running)`，`/health` 回 `{"status":"ok"}` |
| 21:48 | 重新執行 `patch_test_pii.ps1`，7 筆種子帳號 PII 明文補寫完成，確認 `contact_name` 非 `null` |

---

## 根因分析

**直接原因**：部署指令裡多了一行不必要的 `rm -rf api_server database`。

**這行指令當時的動機**：前一次解壓因為本機打包的 tar.gz 本身損毀（跟這次事故無關的另一個小插曲），懷疑是 EC2 上殘留的舊檔案／`__pycache__` 造成解壓不完整，所以想「先清空目錄，確保這次是完全乾淨的解壓」。

**為什�麼會出事**：`api_server/` 目錄裡混著兩種東西：
1. **git 追蹤的程式碼**（`.py` 檔案）——這些本機有、S3 tarball 裡也有，刪了會被下一步的 `tar -xzf` 補回來，沒事。
2. **只存在於 EC2 上、從不進版控的機密設定**（`.env`）——這個**只有 EC2 上這一份**，`tar -xzf` 不會把它變回來，因為它從來不在打包範圍內（`.gitignore` 排除，本機也沒有）。

`rm -rf api_server` 對這兩種檔案一視同仁，全部殺光。真正該做的「清乾淨」只需要清掉 `__pycache__`（`.pyc` 快取檔，本來手冊裡就有 `rm -rf api_server/app/__pycache__ ...` 這一行），完全不需要動到整個目錄。

**輔助因素**：
- `.env` 沒有任何形式的備份（不在 git、不在 Secrets Manager、不在任何人的筆記），單點故障，一旦本體被刪就無法恢復。
- SSM 指令是一次性送出多個指令（`rm` → `tar -xzf` → `restart`），中間沒有人工確認的機會，`rm -rf` 一下手就是全部指令排隊執行完才看到結果。

---

## 補救過程

### 1. 停手，不擴大範圍

發現 `.env` 遺失、且沒有備份後，第一件事是**停止任何進一步操作**，向使用者說明：
- 服務目前掛掉的直接原因
- 兩項機密遺失的影響範圍與可逆性（RDS 密碼可逆，PII 金鑰不可逆）
- 提出兩個選項（重設密碼 / 等待金鑰備份），等待明確授權才繼續。

高風險操作（改 RDS 密碼會讓所有既有連線失效）不擅自決定，這一步是為了避免在資訊不完整時做出不可逆的選擇。

### 2. 重設 RDS 密碼（可逆部分先救回來）

```powershell
aws rds modify-db-instance `
  --profile agentic-home-hub --region us-west-2 `
  --db-instance-identifier aiwave-db `
  --master-user-password "<新密碼>" `
  --apply-immediately
```

`--apply-immediately` 讓變更立刻生效，不用等下一次維護窗口。這個操作**不會動到 RDS 裡的任何資料**，純粹換一組登入密碼，大約 1 分鐘內從 `resetting-master-credentials` 變回 `available`。

### 3. 產生新的 PII 加密金鑰

```powershell
python -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())"
```

32 bytes、base64 編碼，符合 `PII_ENCRYPTION_KEY_B64` 要求的 AES-256-GCM 金鑰長度。

### 4. 在 EC2 上重建 `.env`

用 SSM 送指令，`cat > .env << 'EOF' ... EOF` 的 heredoc 方式整份重寫，並補上 `chmod 600` 限制檔案權限（原本的 `.env` 是 `rw-rw-rw-`，這次順手收緊，副作用是之後用 `ssm-user` 身份 `cat` 會變成 `Permission denied`，要加 `sudo`）。

### 5. 恢復服務

```bash
sudo systemctl reset-failed aiwave-api   # 清掉 StartLimitBurst 計數
sudo systemctl restart aiwave-api
```

`reset-failed` 是關鍵一步——單純 `restart` 在短時間內失敗次數過多會被 systemd 拒絕（`Start request repeated too quickly`），要先清掉失敗計數器。

### 6. 補寫種子測試資料

新金鑰生效後，舊資料的加密欄位已經配不上新金鑰。重新跑一次 `Database/patch_test_pii.ps1`，把 7 筆種子帳號的測試個資用新金鑰重新加密寫入，確認 `contact_name` 等欄位恢復明文可讀。

### 7. 驗證

- `GET /health` → `{"status":"ok"}`
- `GET /openapi.json` 端點數量對回 94（跟部署前一致，確認程式碼沒有部分遺漏）
- 抽查 `GET /vendors/1/review-summary` 確認新欄位 `vendor_name` 有值
- 抽查 `GET /users/{id}` 確認補寫後的 `contact_name` 是正確明文（非亂碼、非 `null`）

---

## 影響範圍總結

| 項目 | 影響 | 可逆性 |
|---|---|---|
| RDS 密碼 | 遺失，服務中斷約 15 分鐘 | ✅ 可逆，已重設 |
| PII 加密金鑰 | 遺失 | ❌ 不可逆，舊密文永久解不開 |
| 受影響資料 | 僅 7 筆種子測試帳號的假 PII（非真實用戶個資） | 已用 `patch_test_pii.ps1` 補寫恢復 |
| DB 資料本身（非 PII 欄位） | 無影響，`_hash` 欄位、訂單、評價等資料完好無損 | 不適用 |
| 程式碼 / git repo | 無影響，`.env` 從未進版控 | 不適用 |

---

## 如何避免再次發生

1. **`api_server/.env`（以及任何服務的 `.env`）在 EC2 上永遠只有一份，沒有備份，這件事本身就是風險**。長期應該改用 AWS Secrets Manager 或 SSM Parameter Store（SecureString）存機密設定，`.env` 只留非機密的預設值。`Database/部署手冊.md` 第8章「上線前安全檢查清單」已經列了「RDS 密碼明文放在 `.env`」這項待辦，這次事故是活生生的理由，優先度應該提高。

2. **部署指令禁止對 `api_server/`、`database/`、`bff_server/` 這類目錄整體執行 `rm -rf`**。需要清乾淨時，只精準刪除已知安全的產物（例如 `__pycache__`、`*.pyc`），絕不對「目錄本身」動手，因為目錄裡永遠可能混著沒進版控的機密檔案。`tar -xzf` 本身就會覆蓋同名檔案，正常更新程式碼根本不需要先清空目錄。

3. **改動 `.env` 前先備份一份**（哪怕只是 `cp .env .env.bak.$(date +%s)` 存在 EC2 上另一個路徑），下次無論是誰手滑，還有得救。

4. **高風險指令（`rm -rf`、`DROP TABLE`、改密碼）不要跟其他指令包在同一批 SSM `send-command` 裡一次送出**。這次的教訓是 `rm` 這一行混在「下載→解壓→裝依賴→重啟」的正常部署流程裡，沒有單獨檢視就執行了。之後拆成多個指令批次，危險操作單獨送出、單獨確認結果，再繼續下一步。

5. **`Database/AWS操作手冊.md` 第6節的部署指令範例已經加上警語**（見下方），避免下一個複製貼上這段指令的人重蹈覆轍。

---

## 後續行動（已完成）

- ✅ `Database/AWS操作手冊.md` 第6節加上「不要 `rm -rf` 整個目錄」的警語
- ✅ RDS 密碼已重設，新密碼存於 EC2 `/home/ssm-user/aiwave/api_server/.env`
- ✅ PII 金鑰已重新產生並生效
- ✅ 7 筆種子測試帳號 PII 已用新金鑰補寫恢復

## 待辦（尚未完成，建議排進上線前檢查清單）

- [ ] 把 `PG_PASSWORD` / `PII_ENCRYPTION_KEY_B64` 改用 AWS Secrets Manager 或 SSM Parameter Store 管理，`.env` 不再是唯一存放處
- [ ] 通知所有隊友：舊的 RDS 密碼已失效，需要用新密碼的人請跟保管憑證的人要（不要在群組聊天貼明文）
- [ ] 若之後真的接上正式用戶資料，PII 金鑰管理必須先解決備份問題，不能重演這次「只能靠重新補寫測試資料掩蓋過去」的僥倖結局

---

*僅此紀念那 15 分鐘裡，一整個 API 因為一行手滑的 `rm -rf` 而魂歸離恨天的深夜。願所有看到這篇的人，複製貼上部署指令前，多看一眼裡面有沒有藏著 `rm -rf`。*

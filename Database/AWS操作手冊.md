# AWS 環境連線與操作手冊

給隊友看的：目前 API server 已經部署在 AWS 上跑起來了，這份文件說明怎麼連進去看、怎麼呼叫、怎麼更新程式碼。

> 這是一次性 workshop/demo 帳號（AWS Workshop Studio 的臨時帳號），沒有身分驗證機制，也沒有 HTTPS。**不要把這個 IP 或任何 AWS 憑證分享到帳號外部**，帳號本身也可能在活動結束後被回收，資源會全部消失。

## 目錄

1. [目前部署狀態](#1-目前部署狀態)
2. [取得 AWS 存取權限](#2-取得-aws-存取權限)
3. [直接呼叫 API（不需要進 EC2）](#3-直接呼叫-api不需要進-ec2)
4. [連進 EC2（用 SSM，不需要 SSH key）](#4-連進-ec2用-ssm不需要-ssh-key)
5. [檢查 / 重啟 API service](#5-檢查--重啟-api-service)
5.1. [補寫種子測試帳號的 PII 明文（`patch_test_pii.ps1`）](#51-補寫種子測試帳號的-pii-明文patch_test_piips1)
6. [更新程式碼（重新部署新版本）](#6-更新程式碼重新部署新版本)
7. [連線資料庫（RDS）](#7-連線資料庫rds)
   - [7.1 從 EC2 內部連](#71-從-ec2-內部連先連進-ec2-再操作)
   - [7.2 從本機直接用 GUI 工具連（推薦）](#72-從本機直接用-gui-工具連推薦不用先連進-ec2)
8. [常見問題排解](#8-常見問題排解)
9. [已知限制 / 安全提醒](#9-已知限制--安全提醒)

---

## 1. 目前部署狀態

| 項目 | 值 |
|---|---|
| AWS Region | `us-west-2` |
| EC2 Instance ID | `i-0a2d19c738be6cb09` |
| EC2 公開 IP | `52.10.163.115` |
| API Base URL | `http://52.10.163.115:8000` |
| Swagger UI | `http://52.10.163.115:8000/docs` |
| RDS Endpoint | `aiwave-db.c1m8oq4cswto.us-west-2.rds.amazonaws.com` |
| RDS Port | `5432`（僅限 VPC 內網連線，未對外公開） |
| S3 部署暫存 bucket | `aiwave-deploy-728259505479-uswest2` |
| EC2 上程式碼路徑 | `/home/ssm-user/aiwave/`（`database/` + `api_server/`） |

架構：

```
你的電腦
   │  (呼叫 API，走公開網路 8000 埠)
   ▼
EC2 (52.10.163.115:8000, uvicorn 常駐於 systemd: aiwave-api.service)
   │  (走 VPC 內網 5432 埠，安全群組限制只允許這台 EC2 連入)
   ▼
RDS PostgreSQL 16 (aiwave-db, 非公開存取)
```

## 2. 取得 AWS 存取權限

如果你只是要**呼叫 API**，不需要任何 AWS 帳號權限，公開 IP 直接打就行，跳到第 3 節。

如果你需要**連進 EC2 操作**或**查看 AWS Console**，需要跟目前保管憑證的人要一組 AWS 存取憑證（`aws_access_key_id` / `aws_secret_access_key` / `aws_session_token`，這組是臨時 STS 憑證，過期需要重新要一組）。

拿到憑證後，**不要貼在聊天訊息、Slack、程式碼裡**。在自己的終端機（不要用會截圖分享的環境）建立 profile：

```powershell
notepad $env:USERPROFILE\.aws\credentials
```

貼入（`agentic-home-hub` 這個 profile 名稱可以自己取，記得後面指令要對應改）：

```ini
[agentic-home-hub]
aws_access_key_id = <你的 key>
aws_secret_access_key = <你的 secret>
aws_session_token = <你的 token>
```

存檔後確認能連上：

```powershell
aws sts get-caller-identity --profile agentic-home-hub
```

看到回傳的 `Account` 是 `728259505479` 就代表設定成功。

## 3. 直接呼叫 API（不需要進 EC2）

最快驗證方式：

```powershell
Invoke-RestMethod -Uri "http://52.10.163.115:8000/health" -Method Get
# 預期: {"status":"ok"}
```

瀏覽器打開 Swagger UI 可以直接互動測試每個端點：

```
http://52.10.163.115:8000/docs
```

完整端點清單（78 個，路徑/方法/回傳型別）見 `Database/API_Reference.md`。

範例：登入取得帳號識別碼

```powershell
$body = @{ account = "user01@example.com"; password = "Test@1234" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://52.10.163.115:8000/auth/user/login" -Method Post -Body $body -ContentType "application/json"
```

> 目前 API **沒有任何身分驗證**，任何知道帳號識別碼的人都能查看該身分底下的資料。這是刻意先擱置的限制（見第9節），呼叫時請注意不要把測試流量誤當成正式資料操作。

## 4. 連進 EC2（用 SSM，不需要 SSH key）

這台 EC2 沒有開放 22 埠（SSH），也沒有配 key pair，連線方式是透過 **AWS Systems Manager Session Manager**，只需要 AWS 憑證，不需要任何密鑰檔案。

### 4.1 安裝 Session Manager plugin（第一次使用需要）

```powershell
# 用 winget 安裝（或到 AWS 官方文件下載安裝包）
winget install Amazon.SessionManagerPlugin
```

### 4.2 開互動式 shell

```powershell
aws ssm start-session --profile agentic-home-hub --region us-west-2 --target i-0a2d19c738be6cb09
```

連上後你會進入一個 root shell，程式碼在 `/home/ssm-user/aiwave/`。輸入 `exit` 離開。

### 4.3 不開互動 shell，直接跑單次指令（適合寫腳本/自動化）

```powershell
aws ssm send-command --profile agentic-home-hub --region us-west-2 --instance-ids i-0a2d19c738be6cb09 --document-name "AWS-RunShellScript" --parameters '{"commands":["systemctl status aiwave-api --no-pager"]}' --output json
```

指令是非同步送出的，取得回傳的 `CommandId` 後用這個查結果：

```powershell
aws ssm get-command-invocation --profile agentic-home-hub --region us-west-2 --command-id <上面拿到的CommandId> --instance-id i-0a2d19c738be6cb09
```

## 5. 檢查 / 重啟 API service

API 用 systemd 常駐（service 名稱 `aiwave-api`），連進 EC2（第4節）之後：

```bash
# 看目前狀態（active/failed，最近log）
sudo systemctl status aiwave-api --no-pager

# 看即時 log
sudo journalctl -u aiwave-api -f

# 重啟（改了 .env 或程式碼後需要重啟才生效）
sudo systemctl restart aiwave-api

# 看目前使用的資料庫連線設定
cat /home/ssm-user/aiwave/api_server/.env
```

## 5.1 補寫種子測試帳號的 PII 明文（`patch_test_pii.ps1`）

**背景**：種子資料建置時 `PII_ENCRYPTION_KEY_B64` 是空的，所以 `user_accounts`/`vendor_accounts` 的
`contact_name`/`contact_mobile`/`contact_email` 一律存 `NULL`（`_hash` 欄位不受影響，永遠有值）。
設定好金鑰、重啟 `aiwave-api` 之後，**舊種子資料依然是 `NULL`**——加密金鑰只影響「金鑰設定之後」新寫入的資料，
不會回頭補全歷史資料。`Database/patch_test_pii.ps1` 就是用來一次性補寫這 7 筆種子帳號（`user01`~`04`、
`vendor01`~`03`）的測試用個資明文，讓demo時個人資料頁面有東西可以顯示。

**前置條件**（缺一都會白做）：
1. EC2 上 `/home/ssm-user/aiwave/api_server/.env` 的 `PII_ENCRYPTION_KEY_B64` 已設定非空值（見上方第5節如何連進 EC2 修改）
2. 改完 `.env` 後已執行 `sudo systemctl restart aiwave-api` 讓新金鑰生效
3. 本機能連上 `http://52.10.163.115:8000`（第3節的連線方式）

若金鑰還沒設定就執行此腳本，PATCH 會回 200 成功，但 `contact_name` 等欄位仍會被 `encrypt_pii()` 短路寫成
`NULL`，只有 `_hash` 欄位會被覆蓋更新，等於做了白工還順便弄髒 hash，記得先確認金鑰狀態再跑。

**用法**（在本機 PowerShell，不需要連進 EC2）：

```powershell
powershell -File Database\patch_test_pii.ps1
# 或指定不同的 api_server base url：
powershell -File Database\patch_test_pii.ps1 -BaseUrl "http://52.10.163.115:8000"
```

腳本會依序對以下 7 個帳號呼叫 `PATCH /users/{id}` 或 `PATCH /vendors/{service_vendor_id}/accounts/{id}`，
填入固定的測試用假資料（非真實個資，格式為「測試會員0X」/「測試商家聯絡人0X」+ 假手機號）：

| 帳號 | 對應 API |
|---|---|
| user01~04@example.com | `PATCH /users/{inbr_account_id}` |
| vendor01~03@example.com | `PATCH /vendors/{service_vendor_id}/accounts/{account_id}` |

**驗證**：腳本執行後會印出每筆 PATCH 的回應，檢查 `contact_name` 欄位是否為明文（非 `null`）即可確認金鑰生效。
若終端機顯示中文亂碼（PowerShell 主控台編碼問題，非資料損毀），改用 `curl.exe ... -o out.json` 存檔後
用文字編輯器開啟確認即可。

⚠️ 這是一次性補寫腳本，帳號 id 是寫死對應 `database/帳號與標籤範例資料.json` 裡的既有種子資料，重新
`import_seed_data.py` 建置全新資料庫後 id 不會變，可以重複執行；但若之後種子資料內容有異動（新增/刪除帳號），
腳本內容需要同步更新。

## 6. 更新程式碼（重新部署新版本）

如果 git repo 有新的 commit，要同步到 EC2 上，流程是「打包 → 上傳 S3 → EC2 下載解壓 → 重啟 service」。**在自己電腦上執行**（不是在 EC2 裡）：

```powershell
# 1. 在本機把最新的 database/ + api_server/ 打包成 tar.gz
#    用 tar 而非 zip，避免中文檔名編碼問題
tar -czf "$env:TEMP\aiwave_deploy.tar.gz" -C "d:\NCU\AIWave\workspace\agentic-home-hub\Database" database api_server

# 2. 上傳到 S3
aws s3 cp "$env:TEMP\aiwave_deploy.tar.gz" "s3://aiwave-deploy-728259505479-uswest2/aiwave_deploy.tar.gz" --profile agentic-home-hub --region us-west-2

# 3. 用 SSM 叫 EC2 下載新版、裝相依套件、重啟 service
aws ssm send-command --profile agentic-home-hub --region us-west-2 --instance-ids i-0a2d19c738be6cb09 --document-name "AWS-RunShellScript" --parameters '{"commands":["cd /home/ssm-user/aiwave","aws s3 cp s3://aiwave-deploy-728259505479-uswest2/aiwave_deploy.tar.gz . --region us-west-2","tar -xzf aiwave_deploy.tar.gz","rm -rf api_server/app/__pycache__ api_server/app/routers/__pycache__","source venv/bin/activate","pip install --quiet -r api_server/requirements.txt","sudo systemctl restart aiwave-api","sleep 3","sudo systemctl status aiwave-api --no-pager"]}' --output json
```

拿到 `CommandId` 後用第4.3節的方式查執行結果，看到 `"Status": "Success"` 且 `Active: active (running)` 就代表部署成功。

> ⚠️ **絕對不要對 `api_server/`、`database/`、`bff_server/` 這幾個目錄本身執行 `rm -rf`（例如 `rm -rf api_server database` 想「先清乾淨再解壓」）**。`tar -xzf` 本身就會覆蓋同名檔案，完全不需要先清空目錄；`rm -rf` 整個目錄會連同**只存在 EC2 上、從未進版控、沒有任何備份**的 `api_server/.env`（含 RDS 密碼、PII 加密金鑰）一起刪掉，且刪掉後這些機密**救不回來**（PII 金鑰遺失後，舊加密資料永久解不開）。真正需要清的只有 `.pyc`/`__pycache__` 這類編譯快取，上面指令裡的 `rm -rf api_server/app/__pycache__ api_server/app/routers/__pycache__` 這兩行已經夠用，不要自己加更大範圍的清空指令。曾經真的手滑刪過一次，事故經過見 `Database/鬼故事_誤刪env事件.md`。

⚠️ 這個流程只更新 `database/` 和 `api_server/` 程式碼本身，**不會**重跑 `import_seed_data.py`（資料庫結構/種子資料不會被動到）。如果這次更新有改到 DDL 或需要跑資料庫遷移，要另外處理，不在這個腳本範圍內。

驗證更新後端點數量有沒有變化（目前應該是 78 個）：

```powershell
$openapi = Invoke-RestMethod -Uri "http://52.10.163.115:8000/openapi.json"
($openapi.paths.PSObject.Properties | ForEach-Object { $_.Value.PSObject.Properties.Count } | Measure-Object -Sum).Sum
```

## 7. 連線資料庫（RDS）

RDS **刻意設定為沒有公開存取**（`PubliclyAccessible: false`），這是為了避免帳密外流後資料庫被任意讀寫。有兩種方式可以查看/操作裡面的資料，都不需要修改 RDS 的公開存取設定：

### 7.1 從 EC2 內部連（先連進 EC2 再操作）

先連進 EC2（第4節），再從裡面連：

```bash
source /home/ssm-user/aiwave/venv/bin/activate
python3 -c "
import psycopg2
conn = psycopg2.connect(host='aiwave-db.c1m8oq4cswto.us-west-2.rds.amazonaws.com', port=5432, dbname='aiwave', user='postgres', password=open('/home/ssm-user/aiwave/api_server/.env').read().split('PG_PASSWORD=')[1].split()[0], sslmode='require')
cur = conn.cursor()
cur.execute('SELECT count(*) FROM mms_order_record;')
print(cur.fetchone())
"
```

或者裝 `postgresql` client 直接用 `psql`（AL2023 預設沒裝，需要 `sudo dnf install -y postgresql16`）。

資料庫密碼存在 EC2 上的 `/home/ssm-user/aiwave/api_server/.env`（`PG_PASSWORD`），連進 EC2 後可以直接 `cat` 出來看，不會另外用聊天工具傳送這組密碼。

### 7.2 從本機直接用 GUI 工具連（推薦，不用先連進 EC2）

如果想用 DBeaver / pgAdmin / TablePlus 這類 GUI 工具直接瀏覽資料庫內容（比在終端機打SQL方便很多），可以透過 **SSM Port Forwarding** 在本機開一個通道，把本機某個埠轉發到 RDS，資料庫本身完全不需要改成公開存取，安全群組也不用動。

**這個方法已經實測驗證過**：本機開通道後用 `psycopg2` 連線讀取 `mms_order_record`/`mms_order_review` 都正常。

#### 步驟1：安裝 Session Manager Plugin（第一次使用需要，跟第4.1節是同一個東西）

```powershell
Invoke-WebRequest -Uri "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe" -OutFile "$env:TEMP\SessionManagerPluginSetup.exe"
Start-Process -FilePath "$env:TEMP\SessionManagerPluginSetup.exe" -ArgumentList "/quiet" -Wait
```

裝完後**重新開一個終端機視窗**（讓新裝的 PATH 生效，不然 `aws` 指令會說找不到 plugin）。

#### 步驟2：建立參數檔

存成 `portfwd_params.json`（放哪都可以，指令裡路徑對應改）：

```json
{
    "host": ["aiwave-db.c1m8oq4cswto.us-west-2.rds.amazonaws.com"],
    "portNumber": ["5432"],
    "localPortNumber": ["15432"]
}
```

#### 步驟3：開通道

```powershell
aws ssm start-session --profile agentic-home-hub --region us-west-2 --target i-0a2d19c738be6cb09 --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters file://portfwd_params.json
```

看到這樣的輸出代表通道建立成功：

```
Starting session with SessionId: Participant-xxxxxxxxxxxxxxxxx
Port 15432 opened for sessionId Participant-xxxxxxxxxxxxxxxxx.
Waiting for connections...
```

**這個終端機視窗要保持開著**，通道只在這個process活著的時候有效，關掉視窗或Ctrl+C就斷線（要斷線就直接關視窗，沒有其他步驟）。

#### 步驟4：用任何 PostgreSQL 工具連本機的轉發埠

在 DBeaver / pgAdmin / psql 的連線設定填：

| 欄位 | 值 |
|---|---|
| Host | `localhost` |
| Port | `15432`（對應步驟2設定的 `localPortNumber`） |
| Database | `aiwave` |
| User | `postgres` |
| Password | 跟保管憑證的人要（存在 EC2 的 `/home/ssm-user/aiwave/api_server/.env`） |
| SSL mode | `require` |

連上後看到的是 RDS 上即時、完整的資料，效果跟直接連公開端點一樣，但 RDS 本身從頭到尾沒有改過任何公開存取設定。

> 一個人一次只需要一個通道，多人要同時查看的話，每個人各自在自己電腦上重複步驟1~4即可，不會互相干擾（每個 SSM session 是獨立的）。

## 8. 常見問題排解

**呼叫 API 逾時/連不上**
- 先確認 EC2 是不是還在跑：`aws ec2 describe-instances --profile agentic-home-hub --region us-west-2 --instance-ids i-0a2d19c738be6cb09 --query "Reservations[0].Instances[0].State.Name"`。Workshop 帳號的資源有可能被回收。
- 確認 API service 本身有沒有活著（第5節 `systemctl status`）。
- 確認你自己的網路沒有擋 8000 埠對外連線（部分公司/學校網路會擋非標準埠）。

**`aws ssm start-session` 失敗，說找不到 plugin**
- 代表 Session Manager plugin 沒裝好，重新跑第4.1節的安裝指令，安裝後可能需要重開終端機視窗。

**改了 `.env` 但沒生效**
- 記得要 `sudo systemctl restart aiwave-api`，改環境變數不會自動重啟服務。

**AWS 憑證過期（`ExpiredToken` 錯誤）**
- 這組是臨時 STS 憑證，過一段時間會失效，跟保管憑證的人要一組新的，重新走第2節設定流程。

## 9. 已知限制 / 安全提醒

- **API 完全沒有身分驗證**：任何拿到公開 IP 的人都能呼叫全部端點、讀寫任何資料。這是刻意先擱置的限制，不要把這個 demo 環境當作正式環境使用，也不要對外公開這個 IP。
- **8000 埠對整個網際網路開放**（`0.0.0.0/0`），沒有 HTTPS/TLS。
- **CORS 允許所有來源**（`*`）。
- **RDS 密碼明文放在 EC2 的 `.env` 檔案**，沒有用 AWS Secrets Manager。
- **RDS 刻意維持不公開存取**：即使開發階段想讓隊友方便查看資料庫內容，也不建議把 RDS 改成 `PubliclyAccessible: true` 對外開放5432埠——一旦開放，任何拿到這組明文密碼的人就能直接連線讀寫整個資料庫，且公網上的自動化掃描器通常幾分鐘到幾小時內就會嘗試連線開放的資料庫埠。想讓隊友查看資料庫內容，請用第7.2節的 SSM Port Forwarding 方式，不需要更動RDS或安全群組的任何設定。
- 這是 workshop 臨時帳號，所有資源都有可能被自動回收，重要資料/程式碼請以 git repo 為準，不要依賴這個環境長期存在。

完整的部署原理與本機建置方式見 `Database/部署手冊.md`；API 端點規格見 `Database/API_Reference.md`。

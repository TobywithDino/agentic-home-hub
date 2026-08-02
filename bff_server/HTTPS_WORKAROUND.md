# Mixed Content 問題記錄與 ngrok Workaround

## 問題描述

前端部署在 Amplify（HTTPS），後端 bff_server 跑在 EC2 裸 HTTP（port 8100）。
瀏覽器安全政策禁止 HTTPS 頁面對 HTTP 端點發出請求，導致所有 API 請求被封鎖。

**錯誤訊息：**
```
Mixed Content: The page at 'https://main.d1plar9wj5ck9.amplifyapp.com/dashboard'
was loaded over HTTPS, but requested an insecure resource
'http://52.10.163.115:8100/merchant-api/vendors/1/review-summary'.
This content should also be served over HTTPS.
```

---

## 問題根源

| 項目 | 值 |
|---|---|
| 前端網址 | `https://main.d1plar9wj5ck9.amplifyapp.com` |
| 後端位址 | `http://52.10.163.115:8100`（裸 HTTP，無 TLS） |
| 觸發時機 | 前端任何打向後端的 API 請求（GET/POST/PUT/PATCH） |

瀏覽器的 Mixed Content 規則：
- HTTPS 頁面只能對 HTTPS 資源發請求
- HTTP 資源請求會被瀏覽器直接封鎖，不會送出

---

## Workaround：ngrok HTTPS Tunnel

在 EC2 上用 ngrok 建立一條 HTTPS tunnel，把 EC2 的 HTTP port 包成 HTTPS 對外暴露。
前端改打 ngrok 的 HTTPS URL，瀏覽器不再看到 Mixed Content。

```
前端 (Amplify HTTPS)
    │  HTTPS
    ▼
ngrok HTTPS Tunnel
    │  HTTP (本機內部)
    ▼
bff_server :8100 (EC2)
```

---

## 部署步驟

### 前置條件
- 需要 ngrok 免費帳號：https://dashboard.ngrok.com/signup
- 取得 authtoken：https://dashboard.ngrok.com/tunnels/authtokens
- 需要 AWS SSM Session Manager 連進 EC2

### Step 1：連進 EC2

```bash
aws ssm start-session \
  --target i-0a2d19c738be6cb09 \
  --region us-west-2 \
  --profile agentic-home-hub
```

### Step 2：下載 ngrok binary

```bash
curl -o /tmp/ngrok.zip https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.zip
unzip /tmp/ngrok.zip -d /tmp
sudo mv /tmp/ngrok /usr/local/bin/
```

### Step 3：設定 authtoken

> ⚠️ 不要把 token 貼到任何聊天紀錄、commit 或公開頻道。

```bash
mkdir -p /tmp/ngrok-config
ngrok config add-authtoken <YOUR_AUTHTOKEN> --config /tmp/ngrok-config/ngrok.yml
```

`/home/ssm-user/.config` 沒有寫入權限，所以 config 放在 `/tmp/ngrok-config/`。

### Step 4：背景啟動 ngrok

```bash
nohup ngrok http 8100 --config /tmp/ngrok-config/ngrok.yml > /tmp/ngrok.log 2>&1 &
```

### Step 5：取得 HTTPS URL

```bash
sleep 3 && curl -s http://localhost:4040/api/tunnels | \
  python3 -c "import sys,json; t=json.load(sys.stdin)['tunnels']; print(t[0]['public_url'])"
```

輸出範例：
```
https://peculiar-trickster-agreeable.ngrok-free.dev
```

### Step 6：驗證連通

```bash
curl -s "https://<ngrok-url>/merchant-api/vendors/1/review-summary" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('OK:', d.get('service_vendor_id'))"
```

回傳 `OK: 1` 代表通了。

### Step 7：通知前端更新 base URL

前端把 API base URL 從：
```
http://52.10.163.115:8100
```
改成：
```
https://<ngrok-url>
```

---

## 注意事項

### Lambda BFF_BASE_URL 不需要改

Lambda（`aiwave-review-summary`）是從 AWS 內部打 bff_server，
不經過瀏覽器，沒有 Mixed Content 限制，繼續用 `http://52.10.163.115:8100` 即可。

```
Lambda → http://52.10.163.115:8100   ✅ 不受影響，不需要改
瀏覽器 → https://<ngrok-url>         ✅ 走 ngrok tunnel
```

### 每次 ngrok 啟動 URL 都會改變

免費 tier 每次重啟 ngrok 都會拿到不同的 URL，前端 base URL 就要跟著更新。
如果要固定 URL 需要 ngrok 付費方案（Custom Domain）。

---

## 取消 Workaround

當不再需要 ngrok，或要換回原本 HTTP 存取時，依序完成以下兩件事。

### Step 1：前端改回原本的 base URL

前端把 API base URL 從 ngrok URL 改回：
```
http://52.10.163.115:8100
```

然後 git push 重新部署 Amplify。

> ⚠️ 改回 HTTP 之後，若前端仍在 HTTPS 域名下，Mixed Content 問題會重新出現。
> 確認你們已有替代方案再做這步。

### Step 2：停掉 EC2 上的 ngrok process

連進 EC2：
```bash
aws ssm start-session \
  --target i-0a2d19c738be6cb09 \
  --region us-west-2 \
  --profile agentic-home-hub
```

終止 ngrok：
```bash
pkill ngrok
```

確認已停止：
```bash
pgrep ngrok || echo "ngrok 已停止"
```

> Lambda 的 `BFF_BASE_URL` 環境變數始終是 `http://52.10.163.115:8100`，
> 從頭到尾都不需要動。

---

## 此 Workaround 的缺點

| 缺點 | 說明 |
|---|---|
| URL 不固定 | 免費 tier 每次重啟都會換 URL，前端要重新部署 |
| ngrok session 會過期 | 免費 tier 有連線時間限制，長時間後 tunnel 可能斷掉 |
| 效能損耗 | 所有流量都要繞過 ngrok 伺服器（美國），增加一段額外 latency |
| ngrok 單點故障 | ngrok 服務本身若不穩定，前端就打不到後端 |
| 非生產等級 | 安全性、可靠性、SLA 都不適合正式環境使用 |
| config 放 /tmp | EC2 重啟後 `/tmp/ngrok-config/` 會消失，需要重新設定 authtoken |

---

## 正式環境的正確解法

Demo 階段用 ngrok 夠用，上線前應改為以下任一方案：

1. **加 TLS 憑證到 EC2**：用 Caddy 或 nginx + Let's Encrypt（需要域名）
2. **放到 AWS App Runner**：自動提供 HTTPS，不需要管理憑證
3. **Amplify Rewrites Proxy**：在 Amplify console 設定 proxy rewrite，讓 Amplify 轉發請求到 EC2，前端只打自己的 HTTPS 域名

詳見 `Database/部署手冊.md` 第 8 章「上線前安全檢查清單」。

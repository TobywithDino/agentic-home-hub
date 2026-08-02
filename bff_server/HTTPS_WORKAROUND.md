# Mixed Content 問題記錄與解法（CloudFront）

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

**曾考慮過但不可行的方案**：Amplify Rewrites Proxy（在 Amplify console 設 rewrite 直接轉發到 EC2）。
AWS 官方文件明確寫「HTTPS is the only protocol supported for reverse proxies」——Amplify rewrite 的
`target` 一定要是 HTTPS，指向裸 HTTP 的 EC2 會被忽略，等於沒解決問題只是繞了一圈。

---

## 正式解法：CloudFront 反向代理（目前採用中）

在 EC2 前面加一層 CloudFront distribution，對外提供 HTTPS，內部再用 HTTP 轉發給 `bff_server:8100`。
不需要自訂 domain，直接用 CloudFront 配發的 `*.cloudfront.net` 網址與其預設憑證。

```
前端 (Amplify HTTPS)
    │  HTTPS
    ▼
CloudFront Distribution (https://d2zjm4bnq2dedx.cloudfront.net)
    │  HTTP (CloudFront → origin)
    ▼
bff_server :8100 (EC2)
```

### 目前部署資訊

| 項目 | 值 |
|---|---|
| Distribution ID | `E318AWBAANVM1M` |
| CloudFront 網址 | `https://d2zjm4bnq2dedx.cloudfront.net` |
| Origin | `ec2-52-10-163-115.us-west-2.compute.amazonaws.com:8100`（HTTP） |
| Cache Policy | `CachingDisabled`（managed，id `4135ea2d-6df8-44a3-9df3-4b5a84be39ad`） |
| Origin Request Policy | `AllViewer`（managed，id `216adef6-5c7f-47e4-b989-5492eafa07d3`） |
| Allowed Methods | GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE |
| Viewer Protocol Policy | Redirect HTTP to HTTPS |
| Compress | 關閉（避免 gzip 緩衝干擾 SSE） |

> ⚠️ CloudFront 的 custom origin **不接受純 IP**（`InvalidArgument: The parameter origin name
> cannot be an IP address`），所以 origin domain 用的是 EC2 自動配發的 public DNS name
> `ec2-52-10-163-115.us-west-2.compute.amazonaws.com`，不是 `52.10.163.115`。
> 這台 EC2 若重啟換了新的 public IP，這個 DNS name 也會跟著換，屆時要重新查
> （`aws ec2 describe-instances --instance-ids i-0a2d19c738be6cb09 --query
> "Reservations[0].Instances[0].PublicDnsName"`）並更新 distribution 的 origin 設定。

### 建立步驟（Console）

1. CloudFront console → **Create distribution**
2. **Origin**：手動輸入 EC2 public DNS name（不要填 IP）；Protocol 選 **HTTP only**；port 改 `8100`
3. **Default cache behavior**：
   - Viewer protocol policy：**Redirect HTTP to HTTPS**
   - Allowed HTTP methods：勾滿 **GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE**
   - Cache policy：**CachingDisabled**
   - Origin request policy：**AllViewer**
   - Compress objects automatically：關閉
4. **Enable security**：demo 階段不啟用 WAF
5. **Get TLS certificate**：不設自訂 domain，直接用 CloudFront 預設憑證
6. Review and create，等狀態變成 `Deployed`（通常 5–15 分鐘）

### 建立步驟（CLI，等效做法）

```bash
aws cloudfront create-distribution \
  --profile agentic-home-hub \
  --region us-east-1 \
  --distribution-config '{
    "CallerReference": "bff-server-proxy-<timestamp>",
    "Comment": "bff_server HTTPS proxy for Amplify frontend",
    "Enabled": true,
    "Origins": {
      "Quantity": 1,
      "Items": [{
        "Id": "bff-server-origin",
        "DomainName": "ec2-52-10-163-115.us-west-2.compute.amazonaws.com",
        "CustomOriginConfig": {
          "HTTPPort": 8100,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]},
          "OriginReadTimeout": 60,
          "OriginKeepaliveTimeout": 5
        }
      }]
    },
    "DefaultCacheBehavior": {
      "TargetOriginId": "bff-server-origin",
      "ViewerProtocolPolicy": "redirect-to-https",
      "AllowedMethods": {
        "Quantity": 7,
        "Items": ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"],
        "CachedMethods": {"Quantity": 2, "Items": ["GET","HEAD"]}
      },
      "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
      "OriginRequestPolicyId": "216adef6-5c7f-47e4-b989-5492eafa07d3",
      "Compress": false
    },
    "PriceClass": "PriceClass_100"
  }'
```

查部署狀態：
```bash
aws cloudfront get-distribution --profile agentic-home-hub --id E318AWBAANVM1M \
  --query "Distribution.Status" --output text
```

### 驗證

```bash
# 一般 API
curl -sS -w "\nHTTP_STATUS:%{http_code}\n" \
  https://d2zjm4bnq2dedx.cloudfront.net/merchant-api/vendors/1/review-summary

# CORS preflight
curl -sS -X OPTIONS -w "\nHTTP_STATUS:%{http_code}\n" \
  https://d2zjm4bnq2dedx.cloudfront.net/app-api/butler/chat \
  -H "Origin: https://main.d1plar9wj5ck9.amplifyapp.com" \
  -H "Access-Control-Request-Method: POST"

# SSE 串流（要看到 data: 逐行冒出，不是一次噴完）
curl -sS -N -X POST https://d2zjm4bnq2dedx.cloudfront.net/app-api/butler/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"hi","inbr_account_id":"demo-user-0001"}' --max-time 25
```

**已驗證結果（2026-08-02）**：GET 200、OPTIONS 200、SSE `text_delta` 逐段吐出（非一次性），
三項全部通過，與直連 EC2 的行為一致。

### 前端切換

前端把 API base URL 從：
```
http://52.10.163.115:8100
```
改成：
```
https://d2zjm4bnq2dedx.cloudfront.net
```

已知需要改動的位置（前端/隊友負責）：
- `ai-butler-app/lib/core/config/environment_config.dart` 的 `defaultRemoteUrl`
- Amplify 前端專案裡任何寫死 EC2 IP 的 API base URL 設定

**不受影響、不需要改的呼叫方**（這些是 server-to-server，不經過瀏覽器，沒有 Mixed Content 限制）：
- `ai-summary-lambda` 的 `BFF_BASE_URL`：繼續用 `http://52.10.163.115:8100`
- `agent_service`（AgentCore）的 `BFF_BASE_URL`：繼續用 `http://52.10.163.115:8100`

### 已知限制 / 待辦

| 項目 | 說明 |
|---|---|
| Origin 用 EC2 public DNS name | EC2 重啟換 IP 後這個 DNS name 會跟著變，需要重新查詢並更新 distribution origin |
| 沒有自訂 domain | 目前用 `*.cloudfront.net` 預設網址，前端要接受這個網址（或疊一層 Amplify rewrite 轉發，見下） |
| 沒有 WAF | demo 階段跳過，上線前應評估是否需要 |
| 是否要疊 Amplify rewrite | 如果想讓前端「只打自己網域」，可在 Amplify console 加一條 rewrite：
`source: /bff-api/<*>` → `target: https://d2zjm4bnq2dedx.cloudfront.net/<*>`（target 是 HTTPS，滿足 Amplify 限制）。目前尚未設定，前端直接打 CloudFront 網址即可。 |

---

## 已棄用：ngrok Workaround（歷史記錄，CloudFront 上線後不再使用）

> 此方案已被上面的 CloudFront 反向代理取代。保留此節僅供歷史參考，
> **不要**再依照這裡的步驟操作，除非 CloudFront 方案本身出問題需要臨時應急。

在 EC2 上用 ngrok 建立一條 HTTPS tunnel，把 EC2 的 HTTP port 包成 HTTPS 對外暴露。

```
前端 (Amplify HTTPS)
    │  HTTPS
    ▼
ngrok HTTPS Tunnel
    │  HTTP (本機內部)
    ▼
bff_server :8100 (EC2)
```

### 停用步驟

如果 EC2 上還有 ngrok process 在跑，透過 SSM 連進去停掉：

```bash
aws ssm start-session --target i-0a2d19c738be6cb09 --region us-west-2 --profile agentic-home-hub
```

進去後：
```bash
pkill ngrok
pgrep ngrok || echo "ngrok 已停止"
```

### 此方案原本的缺點（放棄原因）

| 缺點 | 說明 |
|---|---|
| URL 不固定 | 免費 tier 每次重啟都會換 URL，前端要重新部署 |
| ngrok session 會過期 | 免費 tier 有連線時間限制，長時間後 tunnel 可能斷掉 |
| 效能損耗 | 所有流量都要繞過 ngrok 伺服器（美國），增加一段額外 latency |
| ngrok 單點故障 | ngrok 服務本身若不穩定，前端就打不到後端 |
| 非生產等級 | 安全性、可靠性、SLA 都不適合正式環境使用 |
| config 放 /tmp | EC2 重啟後 `/tmp/ngrok-config/` 會消失，需要重新設定 authtoken |

---

## 正式環境的正確解法（上線前）

Demo 階段用 CloudFront 反向代理已經足夠。上線前應視需求再評估：

1. **加自訂 domain + ACM 憑證到 CloudFront**：取代預設的 `*.cloudfront.net` 網址
2. **EC2 直接 TLS terminate**：用 Caddy 或 nginx + Let's Encrypt（需要域名）
3. **放到 AWS App Runner**：自動提供 HTTPS，不需要管理憑證

詳見 `Database/部署手冊.md` 第 8 章「上線前安全檢查清單」。

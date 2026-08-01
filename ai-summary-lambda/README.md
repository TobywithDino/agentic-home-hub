# AI Review Summary Lambda

定期抓取平台評價、呼叫 Bedrock Claude 產生摘要，並將結果 log 到 CloudWatch。

## 目錄結構

```
ai-summary-lambda/
  handler.py          Lambda 入口，BFF 呼叫 + Bedrock 呼叫 + log
  prompts.py          消費者版 / 商家版 prompt template
  requirements.txt    Python 依賴（httpx、boto3）
  deploy_lambda.sh    打包 + 部署腳本
```

## 兩種摘要視角

| 視角 | BFF 端點 | 對象 | 摘要重點 |
|---|---|---|---|
| 消費者 | `GET /app-api/services/{id}/reviews` | 每個服務項目 | 口碑摘要，幫潛在消費者決策 |
| 商家 | `GET /merchant-api/vendors/{id}/reviews` | 每個商家（跨服務） | 經營洞察，找出優劣勢與改善方向 |

## 部署步驟

### 前置條件

```bash
# 同 bff_server 共用同一組 AWS 臨時憑證
aws configure --profile agentic-home-hub
```

### 第一次部署（建立 Lambda + IAM Role + EventBridge + Function URL）

```bash
cd ai-summary-lambda
bash deploy_lambda.sh --create
```

腳本會自動完成：
1. 打包 `handler.py` + `prompts.py` + 依賴 → zip
2. 上傳 S3（`aiwave-deploy-728259505479-uswest2`）
3. 建立 IAM Role（`aiwave-review-summary-role`），附加 CloudWatch Logs + Bedrock 權限
4. 建立 Lambda Function（`aiwave-review-summary`）
5. **建立 Function URL**（auth-type NONE，demo 用）→ 印出網址，記得存起來
6. 建立 EventBridge 每週排程（每週一 UTC 01:00 = 台灣時間週一 09:00）

### 後續更新程式碼

```bash
cd ai-summary-lambda
bash deploy_lambda.sh
```

---

## 手動觸發（Demo 用）

Function URL（已部署）：

```
https://octoney4t6vv6yzf537lxehkju0ekvds.lambda-url.us-west-2.on.aws/
```

### 跑全部（消費者 + 商家）

```bash
curl "https://<id>.lambda-url.us-west-2.on.aws/"
```

### 只跑消費者摘要

```bash
curl "https://<id>.lambda-url.us-west-2.on.aws/?mode=consumer"
```

### 只跑商家摘要

```bash
curl "https://<id>.lambda-url.us-west-2.on.aws/?mode=merchant"
```

### 只跑單一服務（service_id=17）

```bash
curl "https://<id>.lambda-url.us-west-2.on.aws/?mode=consumer&service_id=17"
```

### 只跑單一商家（vendor_id=1）

```bash
curl "https://<id>.lambda-url.us-west-2.on.aws/?mode=merchant&vendor_id=1"
```

也可以直接從 AWS Console 的 Lambda 頁面點「Test」，event body 填：

```json
{ "mode": "merchant", "vendor_id": "1" }
```

---

## 查看 LLM 回覆 log

LLM 摘要結果全部 log 到 CloudWatch Logs（`=` 分隔線清楚標記）：

```
AWS Console → CloudWatch → Log groups → /aws/lambda/aiwave-review-summary
```

或用 CLI：

```bash
aws logs tail /aws/lambda/aiwave-review-summary \
    --follow \
    --profile agentic-home-hub \
    --region us-west-2
```

---

## Lambda 環境變數

| 變數 | 預設值 | 說明 |
|---|---|---|
| `BFF_BASE_URL` | `http://52.10.163.115:8100` | BFF server 位址 |
| `BEDROCK_MODEL_ID` | `anthropic.claude-3-5-haiku-20241022-v1:0` | 使用的 Bedrock model |
| `BEDROCK_REGION` | `us-west-2` | Bedrock 服務 region |
| `MAX_TOKENS` | `1024` | LLM 回覆最大 token 數 |

若要換成品質更好的 Claude Sonnet，改 `BEDROCK_MODEL_ID` 為：

```
anthropic.claude-3-5-sonnet-20241022-v2:0
```

---

## 後續：存回 DB

> 目前階段：LLM 摘要只 log，不寫回 DB。

等隊友在 DB 新增 summary 欄位後，在 `handler.py` 的 `_run_consumer_summaries` /
`_run_merchant_summaries` 末尾加上 POST/PATCH 呼叫即可，例如：

```python
# 消費者摘要存回 service 主檔
httpx.patch(
    f"{BFF_BASE_URL}/...",
    json={"ai_summary_consumer": summary_text},
    timeout=30,
)
```

BFF 端對應的寫回端點等 DB schema 確認後再補。

# AI Review Summary Lambda

定期抓取平台評價、呼叫 Amazon Bedrock Claude 產生摘要，並將結果 log 到 CloudWatch。

---

## 目前部署狀態

| 項目 | 值 |
|---|---|
| Lambda Function | `aiwave-review-summary` |
| Region | `us-west-2` |
| Runtime | Python 3.12 |
| Bedrock Model | `anthropic.claude-sonnet-4-5-20250929-v1:0`（Claude Sonnet 4.5） |
| Function URL | `https://octoney4t6vv6yzf537lxehkju0ekvds.lambda-url.us-west-2.on.aws/`（workshop SCP 封鎖，無法直接 curl，改用 CLI invoke） |
| EventBridge 排程 | `aiwave-review-summary-weekly`，每週一 UTC 01:00（台灣時間 09:00） |

---

## 目錄結構

```
ai-summary-lambda/
  handler.py          Lambda 入口，串接 BFF + Bedrock + log
  prompts.py          消費者版 / 商家版 prompt template
  requirements.txt    Python 依賴（httpx、boto3）
  deploy_lambda.sh    打包 + 部署腳本
  README.md           本文件
```

---

## 整體架構

```
EventBridge Scheduler（每週一 09:00 台灣時間）
        │
        ▼
  Lambda Function
  aiwave-review-summary
        │
        ├── GET /app-api/services/{id}/reviews     ←─── bff_server :8100
        │       (消費者視角，依服務項目)
        │
        ├── GET /merchant-api/vendors/{id}/reviews ←─── bff_server :8100
        │       (商家視角，跨服務項目)
        │
        ├── prompts.py → 組裝 prompt
        │
        ├── Amazon Bedrock（Claude Sonnet 4.5）
        │       呼叫 Converse API
        │
        └── CloudWatch Logs → 印出摘要結果
                （DB 欄位就緒後改為 PATCH 寫回）

手動觸發（Demo 用）：
  aws lambda invoke ... --payload '{"mode":"merchant","vendor_id":"1"}'
```

---

## 兩種摘要視角

| 視角 | BFF 端點 | 對象 | 摘要重點 |
|---|---|---|---|
| 消費者 | `GET /app-api/services/{id}/reviews` | 每個服務項目 | 口碑摘要，幫潛在消費者決策 |
| 商家 | `GET /merchant-api/vendors/{id}/reviews` | 每個商家（跨服務） | 經營洞察，找出優劣勢與改善方向 |

---

## 執行流程

### 1. 觸發與參數解析（`lambda_handler` + `_extract_params`）

Lambda 接受兩種觸發來源，統一解析為 `params` dict：

| 觸發來源 | event 格式 | 用途 |
|---|---|---|
| EventBridge Scheduler | `source="aws.scheduler"` 或空 | 每週定時自動執行 |
| CLI invoke / Console Test | 直接在 event 頂層帶參數 | Demo 手動觸發 |

可傳入的參數：

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `mode` | string | `"all"` | `"consumer"` / `"merchant"` / `"all"` |
| `service_id` | string | 無 | 指定單一服務 ID，`mode=consumer` 時有效 |
| `vendor_id` | string | 無 | 指定單一商家 ID，`mode=merchant` 時有效 |

CLI invoke 觸發時 response body 包含完整摘要結果；EventBridge 觸發時只回傳計數。

---

### 2. 拉取服務/商家清單（`_fetch_all_services` / `_fetch_all_vendors`）

全跑模式（未指定 ID）時，Lambda 向 **bff_server（port 8100）** 拉清單：

- `GET http://52.10.163.115:8100/merchant-api/services` → 服務項目 id + name
- `GET http://52.10.163.115:8100/merchant-api/vendors` → 商家 id + name

---

### 3. 拉取評價（`_fetch_consumer_reviews` / `_fetch_merchant_reviews`）

向 **bff_server（port 8100）** 拉評價：

| 視角 | BFF 端點 | 回傳格式 |
|---|---|---|
| 消費者（單一服務） | `GET /app-api/services/{service_id}/reviews` | ReviewOut 陣列 |
| 商家（跨全部服務） | `GET /merchant-api/vendors/{vendor_id}/reviews` | ReviewOut 陣列 |

每筆 ReviewOut 包含的欄位：

```json
{
  "record_id": 1,
  "service_vendor_id": 1,
  "service_id": 17,
  "inbr_account_id": "...",
  "overall_rating": 5,
  "rating_detail": { "service": 5, "attitude": 4 },
  "review_content": "服務很好，準時到府",
  "media": ["https://.../photo1.jpg"],
  "status": "01",
  "cre_time": "...",
  "upd_time": "..."
}
```

若某服務/商家無評價，直接 skip（不呼叫 Bedrock，節省費用）。

---

### 4. 組裝 Prompt（`prompts.py`）

評價資料先經過 `_format_reviews_for_prompt` 轉成純文字區塊後，套入對應 template：

#### 消費者版（`build_consumer_prompt`）

目標：讓潛在消費者快速了解口碑，幫助決策。

輸出結構：
- **整體評分**：平均分 + 評價筆數
- **服務亮點**：2~4 個正面優點
- **注意事項**：1~3 個缺點（無負評可略）
- **一句話總結**：是否值得嘗試

#### 商家版（`build_merchant_prompt`）

目標：給商家經營者的評價洞察報告。

輸出結構：
- **整體表現**：平均分、評價總數、各服務分佈
- **優勢項目**：評分最高的服務亮點
- **待改善項目**：評分較低的服務，附具體引用
- **顧客聲音關鍵字**：正負面各 3~5 個
- **改善建議**：2~3 個具體可執行的建議

---

### 5. 呼叫 Bedrock（`_call_bedrock`）

使用 **Converse API**（AWS Bedrock 新版統一介面，相容所有 model）。

```python
bedrock.converse(
    modelId=BEDROCK_MODEL_ID,
    messages=[{ "role": "user", "content": [{"text": prompt}] }],
    inferenceConfig={
        "maxTokens": MAX_TOKENS,
        "temperature": 0.3,   # 低溫，摘要輸出穩定
        "topP": 0.9,
    },
)
```

呼叫完成後 log 出 `inputTokens` / `outputTokens`，方便監控費用。

---

### 6. 輸出 Log（CloudWatch Logs）

每次 Bedrock 回覆用 `=` 分隔線包住：

```
[merchant] vendor_id=1 | review_count=8
============================================================
**整體表現**：平均 4.5 / 5.0，共 8 筆評價 ...
============================================================
```

---

## 手動觸發（Demo 用）

> Function URL 受 workshop SCP 封鎖（回傳 403 Forbidden），請改用 AWS CLI 直接 invoke。

### 跑單一商家摘要（demo 推薦）

```bash
aws lambda invoke \
  --function-name aiwave-review-summary \
  --region us-west-2 \
  --profile agentic-home-hub \
  --payload "{\"mode\":\"merchant\",\"vendor_id\":\"1\"}" \
  --cli-binary-format raw-in-base64-out \
  out.json && cat out.json
```

### 跑單一服務消費者摘要

```bash
aws lambda invoke \
  --function-name aiwave-review-summary \
  --region us-west-2 \
  --profile agentic-home-hub \
  --payload "{\"mode\":\"consumer\",\"service_id\":\"1\"}" \
  --cli-binary-format raw-in-base64-out \
  out.json && cat out.json
```

### 只跑消費者所有服務

```bash
aws lambda invoke \
  --function-name aiwave-review-summary \
  --region us-west-2 \
  --profile agentic-home-hub \
  --payload "{\"mode\":\"consumer\"}" \
  --cli-binary-format raw-in-base64-out \
  out.json && cat out.json
```

### 跑全部（消費者 + 商家）

```bash
aws lambda invoke \
  --function-name aiwave-review-summary \
  --region us-west-2 \
  --profile agentic-home-hub \
  --payload "{}" \
  --cli-binary-format raw-in-base64-out \
  out.json && cat out.json
```

也可以從 **AWS Console → Lambda → aiwave-review-summary → Test**，event body 填：

```json
{ "mode": "merchant", "vendor_id": "1" }
```

---

## 查看 LLM 回覆 log

```
AWS Console → CloudWatch → Log groups → /aws/lambda/aiwave-review-summary
```

> CLI 的 `aws logs tail` 在 Windows 環境因路徑格式問題無法使用，請直接用 Console 查看。

---

## 可調整的參數

### Lambda 環境變數

在 AWS Console → Lambda → Configuration → Environment variables 修改，不需重新部署。

| 變數 | 目前值 | 說明 |
|---|---|---|
| `BFF_BASE_URL` | `http://52.10.163.115:8100` | BFF server 位址，EC2 IP 變更時修改 |
| `BEDROCK_MODEL_ID` | `anthropic.claude-sonnet-4-5-20250929-v1:0` | 使用的 Bedrock model |
| `BEDROCK_REGION` | `us-west-2` | Bedrock 服務 region |
| `MAX_TOKENS` | `2048` | LLM 回覆最大 token 數 |

### Model 選擇

| Model ID | 速度 | 品質 | 建議場景 |
|---|---|---|---|
| `anthropic.claude-sonnet-4-5-20250929-v1:0` | 中 | 高 | 目前使用，品質佳 |
| `anthropic.claude-3-5-haiku-20241022-v1:0` | 快 | 普通 | 需要更快速度或降低費用時 |

### Prompt 微調（`prompts.py`）

修改後執行 `bash deploy_lambda.sh` 更新。

| 調整項目 | 位置 | 說明 |
|---|---|---|
| 輸出語言 | `build_consumer_prompt` / `build_merchant_prompt` | 預設繁體中文 |
| 輸出段落結構 | prompt 內 `## 輸出格式要求` 區塊 | 增減輸出欄位 |
| 送給 LLM 的評價欄位 | `_format_reviews_for_prompt` | 可加入 `order_no`、移除 `service_id` 等 |
| 評價資料量不足閾值 | prompt 最後一行 `少於 3 筆` | 可調高/調低 |

### EventBridge 排程

目前：每週一 UTC 01:00（台灣時間 09:00），cron 表達式：`cron(0 1 ? * MON *)`

若要改時間，到 AWS Console → EventBridge → Rules → `aiwave-review-summary-weekly` 修改。

| 頻率 | cron 表達式 | 台灣時間 |
|---|---|---|
| 每週一早上 | `cron(0 1 ? * MON *)` | 週一 09:00 |
| 每天早上 | `cron(0 1 * * ? *)` | 每天 09:00 |
| 每週五下班前 | `cron(0 9 ? * FRI *)` | 週五 17:00 |

### Lambda 執行設定

在 `deploy_lambda.sh` 設定區修改，需重新部署才生效。

| 參數 | 目前值 | 說明 |
|---|---|---|
| `TIMEOUT` | `300` 秒 | 全平台掃一遍約需 1~3 分鐘 |
| `MEMORY` | `256` MB | HTTP 呼叫 + 字串處理，256 MB 足夠 |

---

## 部署

### 前置條件

```bash
aws configure --profile agentic-home-hub
# 輸入 AWS 臨時憑證（向保管人索取）
```

### 第一次部署（已完成，供參考）

```bash
cd ai-summary-lambda
bash deploy_lambda.sh --create
```

腳本自動完成：
1. `pip install` 依賴 → 打包 zip（Python zipfile，相容 Windows）
2. 上傳 S3（`aiwave-deploy-728259505479-uswest2`）
3. 建立 IAM Role（`aiwave-review-summary-role`）
   - 附加 `AWSLambdaBasicExecutionRole`（CloudWatch Logs 寫入）
   - 附加 `AmazonBedrockFullAccess`（呼叫 Bedrock）
4. 建立 Lambda Function（`aiwave-review-summary`）
5. 建立 Function URL（auth-type NONE）
6. 建立 EventBridge 每週排程

### 後續更新程式碼

```bash
cd ai-summary-lambda
bash deploy_lambda.sh
```

---

## 後續：摘要寫回 DB

> 目前：LLM 摘要只 log 到 CloudWatch，不寫回 DB。

等隊友在 DB 新增 summary 欄位後，在 `handler.py` 的 `_run_consumer_summaries` /
`_run_merchant_summaries` loop 末尾補上 PATCH 呼叫即可，其餘邏輯不需要動：

```python
# 消費者摘要存回 service 主檔
httpx.patch(
    f"{BFF_BASE_URL}/app-api/...",
    json={"ai_summary_consumer": summary_text},
    timeout=30,
)

# 商家摘要存回 vendor 主檔
httpx.patch(
    f"{BFF_BASE_URL}/merchant-api/vendors/{vendor_id}",
    json={"vendor_profile": {"ai_summary_merchant": summary_text}},
    timeout=30,
)
```

---

## 已知限制

| 限制 | 說明 |
|---|---|
| Function URL 被 SCP 封鎖 | Workshop 帳號組織層級封鎖公開 Lambda URL，只能用 CLI invoke 或 Console Test 觸發 |
| 無身分驗證 | Lambda 直接打 BFF 端點，無 token，與整體平台現況一致 |
| 無回滾機制 | 中途 Bedrock 呼叫失敗，前面已完成的摘要不會回滾（只影響 log，不影響 DB） |
| 評價資料量不足 | 少於 3 筆仍會產生摘要，但 LLM 會標注「資料量有限，僅供參考」 |
| Windows CLI log 查詢限制 | `aws logs tail` 在 Windows bash 環境路徑格式問題無法使用，改用 Console |

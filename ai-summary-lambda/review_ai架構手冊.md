# Review AI 架構手冊

智慧社區服務平台的 AI 評價摘要服務，使用 AWS Lambda + Amazon Bedrock 定期產生評價摘要。

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
        ├── Amazon Bedrock（Claude 3.5 Haiku）
        │       呼叫 Converse API
        │
        └── CloudWatch Logs → 印出摘要結果
                （DB 欄位就緒後改為 PATCH 寫回）

手動觸發（Demo 用）：
  curl "https://<Function URL>/?mode=merchant&vendor_id=1"
```

---

## 目錄結構

```
ai-summary-lambda/
  handler.py          Lambda 入口，串接 BFF + Bedrock + log
  prompts.py          消費者版 / 商家版 prompt template
  requirements.txt    Python 依賴（httpx、boto3）
  deploy_lambda.sh    打包 + 部署腳本
  README.md           操作說明（curl 範例、CloudWatch 查 log 方式）
```

---

## 執行流程（handler.py）

### 1. 觸發與參數解析（`lambda_handler` + `_extract_params`）

Lambda 接受兩種觸發來源，統一解析為 `params` dict：

| 觸發來源 | event 格式 | 用途 |
|---|---|---|
| EventBridge Scheduler | `source="aws.scheduler"` 或空 | 每週定時自動執行 |
| Function URL / API Gateway | `queryStringParameters` 或 `requestContext` | Demo 手動觸發 |

可傳入的參數：

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `mode` | string | `"all"` | `"consumer"` / `"merchant"` / `"all"` |
| `service_id` | string | 無 | 指定單一服務 ID，`mode=consumer` 時有效 |
| `vendor_id` | string | 無 | 指定單一商家 ID，`mode=merchant` 時有效 |

HTTP 觸發時 response body 包含完整摘要結果；EventBridge 觸發時只回傳計數。

---

### 2. 拉取服務/商家清單（`_fetch_all_services` / `_fetch_all_vendors`）

全跑模式（未指定 ID）時，Lambda 向 **api_server（port 8000）** 拉清單：

- `GET http://52.10.163.115:8000/services?limit=200` → 服務項目 id + name
- `GET http://52.10.163.115:8000/service-vendors?limit=200` → 商家 id + name

> 注意：bff_server 沒有「列出全部服務」的 BFF 端點，所以這裡直接打 api_server port 8000。

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
  "order_no": "...",
  "service_vendor_id": 1,
  "service_id": 17,
  "inbr_account_id": "...",
  "overall_rating": 5,
  "rating_detail": { "service": 5, "attitude": 4 },
  "review_content": "服務很好，準時到府",
  "media": ["https://.../photo1.jpg"],
  "status": "01",
  "is_deleted": false,
  "cre_time": "...",
  "upd_time": "..."
}
```

若某服務/商家無評價，直接 skip（不呼叫 Bedrock，節省費用）。

---

### 4. 組裝 Prompt（`prompts.py`）

評價資料先經過 `_format_reviews_for_prompt` 轉成純文字區塊：

```
1. [服務ID:17] 評分:5/5（細項：service:5, attitude:4） | 2026-07-15
   評價內容：服務很好，準時到府

2. [服務ID:17] 評分:4/5 | 2026-07-20
   評價內容：師傅態度親切，但稍微遲到
```

再套入對應的 prompt template：

#### 消費者版（`build_consumer_prompt`）

目標：讓潛在消費者快速了解口碑，幫助決策。

輸出結構：
- **整體評分**：平均分 + 評價筆數
- **服務亮點**：2~4 個正面優點
- **注意事項**：1~3 個缺點或需注意事項（無負評可略）
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

使用 **Converse API**（AWS Bedrock 新版統一介面，相容所有 model，不需針對不同廠商調整格式）。

```python
bedrock.converse(
    modelId=BEDROCK_MODEL_ID,
    messages=[{ "role": "user", "content": [{"text": prompt}] }],
    inferenceConfig={
        "maxTokens": MAX_TOKENS,
        "temperature": 0.3,
        "topP": 0.9,
    },
)
```

呼叫完成後，log 出 `inputTokens` / `outputTokens` 方便監控費用。

---

### 6. 輸出 Log（CloudWatch Logs）

每次 Bedrock 回覆用 `=` 分隔線包住，清楚標記：

```
[consumer] service_id=17 | review_count=8
============================================================
**整體評分**：4.5 / 5.0，共 8 筆評價
...
============================================================
```

查看方式：
```bash
aws logs tail /aws/lambda/aiwave-review-summary \
    --follow \
    --profile agentic-home-hub \
    --region us-west-2
```

---

## 可調整的參數

### Lambda 環境變數

在 AWS Console → Lambda → Configuration → Environment variables 修改，不需要重新部署程式碼。

| 變數 | 預設值 | 說明 | 建議值 |
|---|---|---|---|
| `BFF_BASE_URL` | `http://52.10.163.115:8100` | BFF server 位址 | EC2 IP 變更時修改 |
| `BEDROCK_MODEL_ID` | `anthropic.claude-3-5-haiku-20241022-v1:0` | 使用的 Bedrock model | 見下方 Model 選擇 |
| `BEDROCK_REGION` | `us-west-2` | Bedrock 服務 region | 與 EC2 同 region |
| `MAX_TOKENS` | `1024` | LLM 回覆最大 token 數 | 摘要 512~1024 足夠 |

### Model 選擇（`BEDROCK_MODEL_ID`）

| Model ID | 速度 | 品質 | 費用 | 建議場景 |
|---|---|---|---|---|
| `anthropic.claude-3-5-haiku-20241022-v1:0` | 快 | 普通 | 低 | Demo、一般摘要 |
| `anthropic.claude-3-5-sonnet-20241022-v2:0` | 中 | 高 | 中 | 評價筆數多、需要更細膩分析時 |

> 全部 model 都部署在 `us-west-2`，與 EC2 同 region，延遲低。

### Prompt 微調（`prompts.py`）

不需要重新部署，只需改 `prompts.py` 再跑一次 `bash deploy_lambda.sh`。

常見調整點：

| 調整項目 | 位置 | 說明 |
|---|---|---|
| 輸出語言 | `build_consumer_prompt` / `build_merchant_prompt` | 預設繁體中文，可改英文或簡體 |
| 輸出段落 | prompt 內 `## 輸出格式要求` 區塊 | 增減輸出欄位、改變重點 |
| 評價格式 | `_format_reviews_for_prompt` | 調整送給 LLM 的評價欄位，例如加入 `order_no`、移除 `service_id` |
| 評價資料量不足的閾值 | prompt 最後一行 `少於 3 筆` | 可調高/調低 |

### Lambda 執行設定

在 `deploy_lambda.sh` 設定區修改，需重新執行 `--create` 或手動在 Console 改：

| 參數 | 目前值 | 說明 |
|---|---|---|
| `TIMEOUT` | `300` 秒 | 全平台掃一遍約需 1~3 分鐘，設 5 分鐘安全 |
| `MEMORY` | `256` MB | 只做 HTTP 呼叫 + 字串處理，256 MB 足夠 |

### EventBridge 排程

目前設定：**每週一 UTC 01:00（台灣時間週一 09:00）**

cron 表達式：`cron(0 1 ? * MON *)`

若要改時間，到 AWS Console → EventBridge → Rules → `aiwave-review-summary-weekly` 修改。

常用 cron 範例：

| 頻率 | cron 表達式 | 台灣時間 |
|---|---|---|
| 每週一早上 | `cron(0 1 ? * MON *)` | 週一 09:00 |
| 每天早上 | `cron(0 1 * * ? *)` | 每天 09:00 |
| 每週五下班前 | `cron(0 9 ? * FRI *)` | 週五 17:00 |

---

## 部署流程

### 前置條件

```bash
aws configure --profile agentic-home-hub
# 輸入 AWS 臨時憑證（向保管人索取）
```

### 第一次部署

```bash
cd ai-summary-lambda
bash deploy_lambda.sh --create
```

腳本自動完成：
1. `pip install` 依賴 → 打包 zip
2. 上傳 S3（`aiwave-deploy-728259505479-uswest2`）
3. 建立 IAM Role（`aiwave-review-summary-role`）
   - 附加 `AWSLambdaBasicExecutionRole`（CloudWatch Logs 寫入）
   - 附加 `AmazonBedrockFullAccess`（呼叫 Bedrock）
4. 建立 Lambda Function（`aiwave-review-summary`）
5. 建立 Function URL（auth-type NONE，無需簽名，方便 demo curl）
6. 建立 EventBridge 每週排程

### 更新程式碼

```bash
cd ai-summary-lambda
bash deploy_lambda.sh
```

---

## 手動觸發方式（Demo）

部署後取得 Function URL（格式：`https://<id>.lambda-url.us-west-2.on.aws/`）。

```bash
# 跑全部（消費者 + 商家）
curl "https://<Function URL>/"

# 只跑消費者摘要
curl "https://<Function URL>/?mode=consumer"

# 只跑商家摘要
curl "https://<Function URL>/?mode=merchant"

# 指定單一服務（service_id=17）
curl "https://<Function URL>/?mode=consumer&service_id=17"

# 指定單一商家（vendor_id=1）
curl "https://<Function URL>/?mode=merchant&vendor_id=1"
```

也可以在 AWS Console → Lambda → Test，event body 填：

```json
{ "mode": "merchant", "vendor_id": "1" }
```

---

## 後續：摘要寫回 DB

目前摘要只 log 到 CloudWatch，等隊友在 DB 新增欄位後接上。

預計接法（在 `_run_consumer_summaries` / `_run_merchant_summaries` 的 loop 末尾加）：

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

BFF 端對應的寫回端點等 DB schema 確認後再補上，handler.py 其餘邏輯不需要動。

---

## 已知限制

| 限制 | 說明 |
|---|---|
| 無身分驗證 | Lambda 直接打 BFF 端點，無 token，與整體平台現況一致 |
| Function URL 公開 | auth-type NONE，知道 URL 就能觸發。Workshop 臨時環境可接受，上線前需改為 `AWS_IAM` |
| 無回滾機制 | 若中途 Bedrock 呼叫失敗，前面已完成的 service 摘要不會被清除（只影響 log，不影響 DB） |
| 評價資料量 | 少於 3 筆的服務/商家，LLM 仍會產生摘要但會標注「資料量有限，僅供參考」 |

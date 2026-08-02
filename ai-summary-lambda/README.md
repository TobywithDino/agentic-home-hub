# AI Review Summary Lambda

定期抓取平台評價、呼叫 Amazon Bedrock Claude 產生摘要，並將結果寫回 DB。

---

## 目前部署狀態

| 項目 | 值 |
|---|---|
| Lambda Function | `aiwave-review-summary` |
| Region | `us-west-2` |
| Runtime | Python 3.12 |
| Bedrock Model | `us.anthropic.claude-sonnet-4-6`（Claude Sonnet 4.6，cross-region inference profile） |
| Function URL | `https://octoney4t6vv6yzf537lxehkju0ekvds.lambda-url.us-west-2.on.aws/`（workshop SCP 封鎖，無法直接 curl，改用 CLI invoke） |
| EventBridge 排程 | `aiwave-review-summary-weekly`，每週一 UTC 01:00（台灣時間 09:00） |

---

## 目錄結構

```
ai-summary-lambda/
  handler.py              Lambda 入口，串接 BFF + Bedrock + 寫回 DB
  prompts.py              消費者版 / 商家版 prompt template
  requirements.txt        Python 依賴（httpx、boto3）
  deploy_lambda.sh        打包 + 部署腳本（從 .deploy.env 讀設定）
  .deploy.env.example     部署設定範本（進版控）
  .deploy.env             部署設定實際值（不進版控，自行複製填寫）
  README.md               本文件
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
        ├── GET /merchant-api/services              ←─── bff_server :8100
        ├── GET /merchant-api/vendors               ←─── bff_server :8100
        │       (拉取全平台服務項目 / 商家清單，含名稱對照表)
        │
        ├── GET /app-api/services/{id}/reviews      ←─── bff_server :8100
        │       (消費者視角：依服務項目拉全部評價)
        │
        ├── GET /merchant-api/vendors/{id}/reviews  ←─── bff_server :8100
        │       (商家視角：跨服務項目拉評價，Lambda 側篩近 7 天)
        │
        ├── prompts.py → 組裝 prompt（服務名稱取代 service_id）
        │
        ├── Amazon Bedrock（Claude Sonnet 4.6）
        │       呼叫 Converse API
        │
        ├── PUT /merchant-api/services/{id}/review-summary  →── bff_server :8100
        │       (消費者摘要寫回 mms_review_summary_service)
        │
        └── PUT /merchant-api/vendors/{id}/review-summary   →── bff_server :8100
                (商家摘要寫回 mms_review_summary_vendor)

手動觸發（Demo 用）：
  aws lambda invoke ... --payload '{"mode":"merchant","vendor_id":"1"}'
```

---

## 兩種摘要視角

| 視角 | 評價來源端點 | 分析對象 | 寫回端點 | DB 資料表 |
|---|---|---|---|---|
| 消費者 | `GET /app-api/services/{id}/reviews` | 每個服務項目，**近一週**評價 | `PUT /merchant-api/services/{id}/review-summary` | `mms_review_summary_service` |
| 商家 | `GET /merchant-api/vendors/{id}/reviews` | 每個商家，**近一週**評價 | `PUT /merchant-api/vendors/{id}/review-summary` | `mms_review_summary_vendor` |

---

## 執行流程

### 1. 觸發與參數解析（`lambda_handler` + `_extract_params`）

| 觸發來源 | event 格式 | 用途 |
|---|---|---|
| EventBridge Scheduler | `source="aws.scheduler"` 或空 | 每週定時自動執行 |
| CLI invoke / Console Test | 直接在 event 頂層帶參數 | Demo 手動觸發 |

可傳入的參數：

| 參數 | 預設 | 說明 |
|---|---|---|
| `mode` | `"all"` | `"consumer"` / `"merchant"` / `"all"` |
| `service_id` | 無 | 指定單一服務 ID，`mode=consumer` 時有效 |
| `vendor_id` | 無 | 指定單一商家 ID，`mode=merchant` 時有效 |

---

### 2. 拉取清單與評價

全跑模式時 Lambda 先向 bff_server 拉清單：

- `GET /merchant-api/services` → 服務項目 id + name + service_vendor_id
- `GET /merchant-api/vendors` → 商家 id + name

再依清單逐筆拉評價：

| 視角 | 端點 | 篩選範圍 |
|---|---|---|
| 消費者 | `GET /app-api/services/{id}/reviews` | 拉回後在 Lambda 側篩近 7 天（`cre_time >= now - 7d`） |
| 商家 | `GET /merchant-api/vendors/{id}/reviews` | 拉回後在 Lambda 側篩近 7 天（`cre_time >= now - 7d`） |

---

### 3. 組裝 Prompt 與呼叫 Bedrock

評價區塊中的服務名稱由 `service_names` dict 對照，LLM 看到的是實際名稱（如「冷氣清洗」）而非 `服務ID:1`。

#### 消費者版（`build_consumer_prompt`）

分析**近一週**評價，輸出一段純文字，對應前端服務詳情頁的「評價摘要」區塊：

- 一段精簡但具體的反饋文字，繁體中文，≤120 字
- 近一週無評價時，自動 fallback 到最近至多 20 則歷史評價，並在摘要開頭說明來源（例如：「以下摘要來自歷史評價，非本週最新資料。」）
- 完全無任何評價資料時輸出：「目前尚無評價資料。」

#### 商家版（`build_merchant_prompt`）

輸出**純 JSON**，對應商家後台「AI 智慧洞察」UI 三個區塊：

```json
{
  "summary": "本週服務整體口碑穩健，顧客普遍對準時性與專業度給予肯定。",
  "suggestions": [
    "「服務態度」平均最低，建議優先改善此環節。",
    "N 筆中立評價最易透過細節優化轉為正面。",
    "第三條建議（≤20 字）"
  ],
  "sentiment_stats": {
    "positive": 3,
    "neutral": 1,
    "negative": 0
  }
}
```

| UI 區塊 | JSON 欄位 | 規格 |
|---|---|---|
| 本週住戶需求 AI 摘要 | `summary` | 一段字串，≤125 字 |
| 廠商營運與服務優化建議 | `suggestions` | 3~4 點陣列，每點 ≤20 字 |
| 客戶情緒/滿意度標籤 | `sentiment_stats` | 依 overall_rating：4~5=正面、3=中立、1~2=負面 |

本週無評價時，consumer 和 merchant 皆自動 fallback 到最近至多 20 則歷史評價，
LLM 摘要開頭會說明資料來源非近期；完全無任何評價時輸出固定字串。

---

### 4. Bedrock 呼叫（`_call_bedrock`）

使用 **Converse API**，`temperature: 0.3`（低溫穩定輸出）。

> Claude Sonnet 4.x 不支援同時指定 `temperature` + `topP`，已移除 `topP`。

---

### 5. 解析與寫回 DB

#### 消費者摘要寫回 `mms_review_summary_service`

| DB 欄位 | 內容 |
|---|---|
| `service_vendor_id` | 所屬商家 ID |
| `service_name` | 服務項目名稱 |
| `summary_content` | LLM 產生的近一週口碑摘要（純文字，≤120 字） |
| `source_review_count` | 全部評價總數（用於 `is_stale` 判斷） |
| `source_avg_rating` | 全部評價平均分 |
| `generate_status` | `"02"`（已完成） |
| `ai_model` | 使用的 model ID |

#### 商家摘要寫回 `mms_review_summary_vendor`

商家版 LLM 輸出經 `_parse_merchant_json` 解析後寫入：

| DB 欄位 | 內容 |
|---|---|
| `summary_content` | `"分析期間：YYYY/MM/DD – YYYY/MM/DD"` |
| `vendor_name` | 商家名稱（頂層欄位） |
| `summary_highlights` | `{"summary": "...(≤125字)", "suggestions": [...]}` |
| `sentiment_stats` | `{"positive": N, "neutral": N, "negative": N}`（近一週統計） |
| `service_breakdown` | 各服務項目的評價數與平均分（全部評價計算） |
| `source_review_count` | 全部評價總數（用於 `is_stale` 判斷） |
| `source_avg_rating` | 全部評價平均分 |
| `generate_status` | `"02"`（已完成） |
| `ai_model` | 使用的 model ID |

---

## 手動觸發（Demo 用）

> Function URL 受 workshop SCP 封鎖（403 Forbidden），使用 AWS CLI invoke。

### 跑單一商家（demo 推薦）

```bash
aws lambda invoke \
  --function-name aiwave-review-summary \
  --region us-west-2 \
  --profile agentic-home-hub \
  --payload "{\"mode\":\"merchant\",\"vendor_id\":\"1\"}" \
  --cli-binary-format raw-in-base64-out \
  out.json && cat out.json
```

### 跑單一服務（消費者摘要）

```bash
aws lambda invoke \
  --function-name aiwave-review-summary \
  --region us-west-2 \
  --profile agentic-home-hub \
  --payload "{\"mode\":\"consumer\",\"service_id\":\"1\"}" \
  --cli-binary-format raw-in-base64-out \
  out.json && cat out.json
```

### 只跑所有商家摘要

```bash
aws lambda invoke \
  --function-name aiwave-review-summary \
  --region us-west-2 \
  --profile agentic-home-hub \
  --payload "{\"mode\":\"merchant\"}" \
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

也可從 **AWS Console → Lambda → aiwave-review-summary → Test**，event body 填：

```json
{ "mode": "merchant", "vendor_id": "1" }
```

### 確認結果寫回 DB

```bash
curl -s "http://52.10.163.115:8100/merchant-api/vendors/1/review-summary"
```

---

## 查看 Log

```
AWS Console → CloudWatch → Log groups → /aws/lambda/aiwave-review-summary
```

> CLI 的 `aws logs tail` 在 Windows bash 因路徑格式問題無法使用，請用 Console 查看。

---

## 可調整的參數

### Lambda 環境變數

在 AWS Console → Lambda → Configuration → Environment variables 修改，不需重新部署。

| 變數 | 目前值 | 說明 |
|---|---|---|
| `BFF_BASE_URL` | `http://52.10.163.115:8100` | BFF server 位址，EC2 IP 變更時修改 |
| `BEDROCK_MODEL_ID` | `us.anthropic.claude-sonnet-4-6` | Bedrock model（需用 cross-region inference profile 格式） |
| `BEDROCK_REGION` | `us-west-2` | Bedrock 服務 region |
| `MAX_TOKENS` | `2048` | LLM 回覆最大 token 數 |

### Model 注意事項

- 新版 Claude（Sonnet 4.x 之後）需使用 **cross-region inference profile**，model ID 需加 `us.` 前綴
- 不可直接使用裸 model ID（會收到 `ValidationException: on-demand throughput isn't supported`）
- 部分新 model 需要 AWS Marketplace 訂閱，workshop 帳號無此權限

### Prompt 微調（`prompts.py`）

修改後執行 `bash deploy_lambda.sh` 更新。詳細相依影響範圍見程式碼內說明。

| 調整項目 | 位置 | 說明 |
|---|---|---|
| 消費者輸出規則 | `build_consumer_prompt` 內 `## 輸出規則` | 修改字數限制、fallback 說明邏輯 |
| 商家 JSON 結構 | `build_merchant_prompt` 內 `## 輸出格式要求` | 增減 JSON 欄位（同步更新 handler.py + docstring） |
| 消費者 summary 字數限制 | prompt 規則區 | 目前 ≤120 字 |
| 商家 summary 字數限制 | prompt 規則區 | 目前 ≤125 字 |
| suggestions 字數限制 | prompt 規則區 | 目前每點 ≤20 字，3~4 點 |
| 評價格式（服務名稱） | `_format_reviews_for_prompt` | 目前顯示服務名稱，可調整欄位 |
| 近一週天數 | `handler.py` `_run_consumer_summaries` 與 `_run_merchant_summaries` 的 `timedelta(days=7)` | 可改為 14 天等（consumer 與 merchant 需分別修改） |
| Fallback 筆數上限 | `handler.py` 兩個 `_run_*_summaries` 內的 `[:20]` | 目前最多取 20 則歷史評價 |

### EventBridge 排程

目前：每週一 UTC 01:00（台灣時間 09:00），cron：`cron(0 1 ? * MON *)`

AWS Console → EventBridge → Rules → `aiwave-review-summary-weekly` 修改。

---

## 部署

### 前置條件

```bash
aws configure --profile agentic-home-hub
cp .deploy.env.example .deploy.env
# 編輯 .deploy.env 填入實際值
```

### 第一次部署（已完成，供參考）

```bash
bash deploy_lambda.sh --create
```

自動完成：建立 IAM Role（含 `AWSLambdaBasicExecutionRole` + `AmazonBedrockFullAccess` + `bedrock:InvokeModel` inline policy）、Lambda Function、Function URL、EventBridge 排程。

### 後續更新程式碼

```bash
bash deploy_lambda.sh
```

---

## 已知限制

| 限制 | 說明 |
|---|---|
| Function URL 被 SCP 封鎖 | Workshop 帳號封鎖公開 Lambda URL，只能用 CLI invoke 或 Console Test |
| 無身分驗證 | Lambda 直接打 BFF 端點，無 token，與整體平台現況一致 |
| 無回滾機制 | 中途失敗不會回滾前面已完成的摘要 |
| 消費者摘要近一週篩選在 Lambda 側 | 拉回全部評價後才過濾（consumer 與 merchant 共用相同邏輯），非在 DB 層篩選，資料量大時效率較低 |
| Windows CLI log 查詢 | `aws logs tail` 路徑格式問題，改用 Console |

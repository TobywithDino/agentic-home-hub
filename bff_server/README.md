# BFF API Server

前端與 `Database/api_server`（隊友維護的 DB Access API）之間的中介層，也是
`agent_service`（AI 管家）對外的唯一出口。前端 / AI 管家只呼叫這一層，這一層
再呼叫 `Database/api_server` 取得原始資料或呼叫 AgentCore Runtime，中間做
排序、label filter、資料組裝等不適合放進純資料存取層的邏輯。

架構：

```
前端 (APP / 商家後台)
   │
   ├── GUI 操作 ──────────────────────────┐
   └── 自然語言對話 ─► agent_service       │
                       (AgentCore Runtime) │
                         │ SigV4           │
                         ▼                 ▼
                     bff_server (本資料夾, port 8100)
                         │  httpx
                         ▼
                     Database/api_server (隊友維護, port 8000)
                         │
                         ▼
                     PostgreSQL (RDS)
```

**AI 管家沒有寫入權限**：`/app-api/butler/chat` 只會產生「草稿」（`draft` 事件），
真正送出訂單/回饋單仍是 APP 帶使用者身分打既有的 `POST /app-api/feedbacks`。
AgentCore Runtime 只接受 SigV4(IAM) 驗證，前端拿不到也不該拿 AWS 憑證，所以
由 `bff_server` 用 EC2 instance role 代為呼叫並轉發 SSE。

## 目前狀態

- `app_api.py`：APP 前端呼叫的 API（含 AI 管家 SSE 端點）
- `merchant_api.py`：商家後台呼叫的 API（含評價 AI 摘要讀寫端點）

完整端點規格與範例見部署後的 Swagger UI (`/docs`)；本文件的端點對應表為快速索引，
細節（欄位型別、範例 payload）以各端點的 docstring 為準。

## 部署

改完程式碼後用 `deploy.sh` 一鍵部署到 EC2：

```bash
cd bff_server
bash deploy.sh
```

流程：打包 → 上傳 S3 → SSM 送指令到 EC2 解壓、裝依賴、重啟 `bff-api` service → 開安全群組 8100 埠 → health check 驗證。

需要先設定好 AWS CLI profile（`aws configure --profile agentic-home-hub`）。

**AI 管家上線前置條件**（三項缺一不可，詳見 `.kiro/steering/project-overview.md`）：
1. 部署含 `agent_client.py` 的新版程式碼，且 `requirements.txt` 已裝 `boto3`
2. EC2 instance role 加 `bedrock-agentcore:InvokeAgentRuntime` 權限
3. EC2 上 `bff_server/.env` 設定 `AGENTCORE_RUNTIME_ARN`

## 本機開發

需要先啟動 `Database/api_server`（見該資料夾的 README），再啟動這一層：

```bash
pip install -r requirements.txt
cp .env.example .env   # 視需要調整 DB_API_BASE_URL；AI 管家相關變數留空則走假資料/回 error 事件
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8100
```

開啟 http://127.0.0.1:8100/docs 查看互動式 API 文件。

## 專案結構

```
app/
  config.py        設定讀取（環境變數，主要是 DB_API_BASE_URL、AGENTCORE_RUNTIME_ARN）
  client.py        封裝對 Database/api_server 的 HTTP 呼叫（httpx）
                   含 get_optional（把 404 當空值）、get_all_items（自動分頁抓全部）
  agent_client.py  呼叫 AgentCore Runtime（SigV4）並把 SSE 串流原樣轉發給前端
  deps.py          FastAPI 依賴注入（取得 DbApiClient）
  main.py          FastAPI 應用程式入口
  review_utils.py  共用邏輯：把 mms_order_review 併入訂單物件的 review 欄位
  routers/
    app_api.py       APP 前端呼叫的 API
    merchant_api.py  商家後台呼叫的 API
```

## 端點對應表

### APP 端（prefix: `/app-api`）

| # | Method | Path | 說明 |
|---|--------|------|------|
| 1 | POST | `/butler/chat` | AI 管家對話（SSE 串流，轉發 AgentCore Runtime） |
| 2 | GET | `/service-types/{service_type}/vendors` | 依服務類型+標籤篩選廠商 |
| 3 | GET | `/labels?service_type=` | 依服務類型精確篩選標籤（帶值=該類型專屬，不帶=通用） |
| 4 | GET | `/vendors/{service_vendor_id}/services` | 廠商的服務項目（可用 service_type 篩選，回傳含 form_id） |
| 5 | GET | `/services/{service_id}/labels` | 某服務項目擁有的標籤（僅實際擁有的，供顯示用） |
| 6 | GET | `/forms/{form_id}/full` | 表單完整內容（題組/題目/選項），供填單頁渲染 |
| 7 | GET | `/services/{service_id}/form/full` | 依 service_id 直接取得對應表單完整內容（給 AI 管家用） |
| 8 | POST | `/feedbacks` | 建立諮詢回饋單 |
| 9 | GET | `/users/{inbr_account_id}/orders-overview` | 會員訂單總覽（未處理 feedback + 全部訂單含 review） |
| 10 | POST | `/orders/{record_id}/review` | 對已完成訂單提交評價 |
| 11 | PATCH | `/users/{inbr_account_id}/orders/{record_id}/review` | 修改自己提交過的評價 |
| 12 | GET | `/services/{service_id}/reviews` | 某服務項目全部評價（完整內容，非公開評價牆） |
| 13 | GET | `/services/{service_id}/review-summary` | 服務項目的評價 AI 摘要（轉發，含 is_stale 計算欄位） |
| 14 | GET | `/users/{inbr_account_id}` | 取得會員個人資訊 |
| 15 | PATCH | `/users/{inbr_account_id}` | 設定（更新）會員個人資訊 |
| 16 | POST | `/auth/login` | APP 會員登入，回傳 inbr_account_id |

### 商家後台（prefix: `/merchant-api`）

| # | Method | Path | 說明 |
|---|--------|------|------|
| 1 | GET | `/services` | 查詢所有服務項目（可用 service_vendor_id, type 篩選） |
| 2 | POST | `/services` | 新增服務項目（不傳 id 則自動分配） |
| 3 | DELETE | `/services/{service_id}` | 刪除服務項目（實體刪除） |
| 4 | GET | `/vendors` | 查詢所有廠商 |
| 5 | GET | `/vendors/{service_vendor_id}/services` | 該商家的服務項目（可用 service_type 篩選） |
| 6 | GET | `/vendors/{service_vendor_id}/feedbacks` | 商家收到的諮詢回饋單清單 |
| 7 | PATCH | `/feedbacks/{feedback_no}/status` | 更新回饋單狀態（已讀/處理進度） |
| 8 | GET | `/services/{service_id}/labels` | 查詢標籤勾選狀態（全部標籤 + checked） |
| 9 | PUT | `/services/{service_id}/labels` | 設定標籤（覆蓋式，自動 diff） |
| 10 | GET | `/vendors/{service_vendor_id}/forms` | 該商家的表單清單（僅主檔） |
| 11 | GET | `/forms/{form_id}/full` | 表單完整內容（題組/題目/選項/圖片/地區關聯） |
| 12 | PATCH | `/forms/{form_id}` | 建立新版本表單取代舊表單（舊表單保留供歷史記錄），必填 service_id |
| 13 | POST | `/forms` | 建立表單及巢狀內容（題組→題目→選項），必填 service_id |
| 14 | POST | `/orders` | 建立新訂單（含 original_amount 估價金額、vendor_data 原始表單內容） |
| 15 | GET | `/vendors/{service_vendor_id}/reviews` | 該商家全部評價（不分頁，一次回傳全部） |
| 16 | PUT | `/services/{service_id}/review-summary` | 寫回服務項目評價 AI 摘要（純轉發，不呼叫 LLM） |
| 17 | GET | `/vendors/{service_vendor_id}/review-summary` | 商家整合評價 AI 摘要（轉發，含 is_stale 計算欄位） |
| 18 | PUT | `/vendors/{service_vendor_id}/review-summary` | 寫回商家整合評價 AI 摘要（純轉發，不呼叫 LLM） |
| 19 | POST | `/vendors/{service_vendor_id}/review-summary/refresh` | 主動觸發重新生成商家 AI 摘要（async invoke Lambda，立即回傳 202） |
| 20 | GET | `/vendors/{service_vendor_id}/orders` | 該商家的訂單清單（含 review 欄位） |
| 21 | PATCH | `/vendors/{service_vendor_id}/orders/{record_id}` | 更新特定訂單（狀態/金額/時間） |
| 22 | GET | `/vendors/{service_vendor_id}` | 取得商家資訊（商家屬性 + 管理帳號清單） |
| 23 | PATCH | `/vendors/{service_vendor_id}` | 設定商家資訊（商家屬性 + 管理帳號聯絡方式） |
| 24 | POST | `/auth/login` | 商家後台登入，回傳 service_vendor_id + account_id |

## 注意事項

- 所有 API 目前**沒有身分驗證機制**（登入只回傳識別碼，沒有 JWT/Session token）
- 表單建立/更新（`POST /forms`、`PATCH /forms/{form_id}`）會自動把 `form_id` 寫回對應 service，前端不需要額外操作
- `PATCH /forms/{form_id}` **不是**就地修改：會建立一張新表單取代舊表單，舊表單保留在資料庫供歷史訂單/回饋單對照，`service.form_id` 改指向新版本
- 所有回傳訂單的端點都會自動附加 `review` 欄位（有評價是完整物件，沒有則是 `null`）
- `POST /merchant-api/orders` 的 `original_amount`（估價金額）、`vendor_data`（原始 feedback 內容）皆為 api_server 既有欄位，原樣轉發不過濾，`GET .../orders` 讀取時也會原樣帶出
- 評價 AI 摘要（`review-summary` 系列）純轉發、不呼叫 LLM；實際生成流程由 `ai-summary-lambda` 呼叫 Bedrock 後再 `PUT` 回來
- 部署細節與已知限制見 `.kiro/steering/project-overview.md`

# DB Access API Server

供主要專案程式使用的資料庫存取 API，基於 FastAPI + uvicorn + SQLAlchemy，
對接 `../database/` 建置的 PostgreSQL schema。共 94 個業務端點，完整規格（路徑/方法/
Request Body/回傳型別）見 `../API_Reference.md`。

> 完整的「建資料庫 → 部署此 server → 上 AWS」步驟，請看根目錄的
> **`../部署手冊.md`**。本檔案只保留最小啟動指引與專案內部結構。

## 最小啟動步驟

```powershell
pip install -r requirements.txt
copy .env.example .env   # 編輯 .env 填入資料庫連線資訊
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

開啟 http://127.0.0.1:8000/docs 查看互動式 API 文件（Swagger UI）。

資料庫需先透過 `../database/import_seed_data.py` 完成建表與種子資料匯入，
詳細步驟見 `../部署手冊.md` 第 3 章。

## 專案結構

```
app/
  config.py      設定讀取（環境變數）
  database.py    SQLAlchemy engine/session
  models.py      ORM models（映射既有 schema，不負責建表）
  schemas.py     Pydantic Create/Update/Out models
  security.py    密碼雜湊（bcrypt）
  crypto.py      PII 欄位 AES-256-GCM 加解密 + SHA-256 hash
  utils.py       共用工具（分頁、UUID v7、時間）
  deps.py        分頁參數依賴
  routers/
    geo.py        縣市/行政區 CRUD
    catalog.py    服務商/服務項目/標籤 CRUD
    accounts.py   會員/服務商後台帳號（含登入）
    forms.py      表單結構完整 CRUD
    feedbacks.py  諮詢單回饋
    orders.py     訂單（含查看訂單拼接邏輯）
    reviews.py    訂單評價
    summaries.py  評價AI摘要（讀取/寫入摘要結果，不呼叫LLM，生成流程由上層服務負責）
  main.py        FastAPI 應用程式入口
```

## 重要安全性提醒（正式串接前必讀）

1. **無身分驗證中介層**：目前所有端點皆可被任意呼叫者存取。`/auth/*/login`
   只做帳密核對後回傳識別碼（`inbr_account_id`/`service_vendor_id`），
   並未簽發 JWT/Session token，也沒有任何端點檢查「呼叫者是否有權操作該資源」。
   正式環境上線前必須加上驗證機制。
2. **CORS 預設全開**：`.env` 未設定 `CORS_ALLOW_ORIGINS` 時允許所有來源，
   僅適合本地開發，正式環境請改白名單。
3. **PII 加密金鑰**：`PII_ENCRYPTION_KEY_B64` 未設定時，`contact_name`/
   `member_phone` 等 bytea 欄位寫入時一律存 NULL，讀取時一律回傳 `null`，
   只有對應 `_hash` 欄位（SHA-256）可用於比對查詢。這是刻意的安全預設值，
   避免產生無法復原的假密文；正式環境要有真實 PII 落地，務必設定金鑰。
4. **管理端 CRUD 無操作者追蹤**：因無登入驗證，`cre_id`/`upd_id` 這類「操作者」
   欄位在管理端 API（縣市/服務商/標籤/表單結構）暫填系統識別碼
   `00000000-0000-7000-8000-000000000000`（見 `app/utils.py` 的
   `SYSTEM_ACTOR_ID`），無法真實追蹤是哪個管理員做的操作。

完整的上線前檢查清單見 `../部署手冊.md` 第 8 章。

## 已知設計限制

- `cms_homepage_service_vendor`、`cms_homepage_service`、`pms_form_group`、
  `pms_form_topic` 這幾張表在既有 DDL 中沒有 `is_deleted` 欄位，其刪除端點
  為實體 DELETE，非軟刪除。
- `pms_topic_county_district_relation` 為複合主鍵（無單一 id），其刪除端點
  以 request body 帶完整 key 組合，而非路徑參數。
- 資料庫本身無實體 FOREIGN KEY 約束（鬆耦合設計），API 層也未做深度跨表
  存在性驗證（例如建立 feedback 時不會檢查 form_id 是否真實存在），這是延續
  既有 schema 設計慣例，非遺漏。
- `summaries.py` 不呼叫 LLM，只負責讀取/寫入 `mms_review_summary_service`、
  `mms_review_summary_vendor` 兩張覆寫式快取表。`PATCH .../status` 在記錄不
  存在時會自動建立殼記錄；服務項目版本會查 `cms_homepage_service` 取得
  `service_vendor_id`（若 `service_id` 不存在則回404），供應商版本則不驗證
  `service_vendor_id` 是否存在於 `cms_homepage_service_vendor`。`is_stale`
  為即時計算欄位，每次 `GET` 都會對 `mms_order_review` 多一次聚合查詢，demo
  規模下無效能問題，若評價量變大可考慮改成生成流程自行維護。

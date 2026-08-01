---
inclusion: always
---

# 專案總覽：智慧社區服務需求理解與媒合平台

黑客松專案。三層架構，兩個 Python/FastAPI 後端服務 + PostgreSQL 資料庫。

## 目錄結構

```
agentic-home-hub/
├── Database/                隊友負責：資料庫 + DB Access API
│   ├── 部署手冊.md            本機建置 + AWS 遷移完整手冊
│   ├── AWS操作手冊.md         目前 AWS 環境連線/操作指南（EC2 IP、SSM 連線方式等）
│   ├── API_Reference.md      api_server 85 個端點完整規格
│   ├── database/             DDL（*.sql）+ 種子資料（*.json）+ 建置腳本
│   └── api_server/           FastAPI，直接操作 PostgreSQL，跑在 EC2 8000 埠
│       └── app/routers/      geo / catalog / accounts / forms / feedbacks / orders / reviews
└── bff_server/               我方負責：BFF（Backend For Frontend）
    ├── README.md             架構說明 + 端點對應表
    ├── deploy.sh             一鍵部署到 EC2 的腳本
    └── app/
        ├── client.py         封裝呼叫 Database/api_server 的 httpx client（含 get_optional 把404當空值、get_all_items 自動分頁抓全部）
        ├── config.py         環境變數設定
        ├── review_utils.py   共用邏輯：把 mms_order_review 併入訂單物件的 review 欄位
        └── routers/
            ├── app_api.py       APP 前端呼叫的 8 支 API
            └── merchant_api.py  商家後台呼叫的 12 支 API
```

## 架構

```
前端 (APP / 商家後台)
   │
   ▼
bff_server (本 repo，這一層負責排序/篩選/組裝等前端邏輯)
   │  透過 httpx 呼叫
   ▼
Database/api_server (隊友維護，直接操作 DB，不要重複實作)
   │
   ▼
PostgreSQL (RDS)
```

**重要原則**：`bff_server` 不直接碰資料庫，所有資料存取都透過呼叫 `Database/api_server` 完成。新增功能前先確認 `Database/api_server` 有沒有現成端點可以組合使用（見 `Database/API_Reference.md`），不要繞過這一層直接連 DB。

## 目前部署狀態（AWS）

一台 EC2 同時跑兩個 service（不是兩台機器），細節見 `Database/AWS操作手冊.md`：

| 項目 | 值 |
|---|---|
| EC2 IP | `52.10.163.115` |
| Region | `us-west-2` |
| Instance ID | `i-0a2d19c738be6cb09` |
| Database/api_server | port 8000，systemd service `aiwave-api` |
| bff_server（本專案） | port 8100，systemd service `bff-api` |
| EC2 連線方式 | AWS SSM Session Manager（無 SSH key），需要跟保管憑證的人要 AWS 臨時憑證 |
| EC2 上程式碼路徑 | `/home/ssm-user/aiwave/`（database/、api_server/、bff_server/、venv/ 都在同一層） |
| systemd service User | 兩個 service 都用 `User=root`（EC2 上沒有 `ssm-user` 這個系統帳號，別再寫 `ssm-user`） |

⚠️ 這是 workshop 臨時帳號（AWS Workshop Studio），沒有身分驗證機制、沒有 HTTPS，資源可能隨時被回收。不要把 IP 或憑證分享到帳號外部。

## 部署 bff_server 更新

改完 `bff_server/` 程式碼後，用 `bff_server/deploy.sh` 部署到 EC2：

```bash
cd bff_server
bash deploy.sh
```

流程：打包 → 上傳 S3（`s3://aiwave-deploy-728259505479-uswest2/`）→ SSM 送指令到 EC2 解壓、裝依賴、重啟 `bff-api` service → 確認安全群組開 8100 埠 → health check 驗證。

需要先設定好 AWS CLI profile（`aws configure --profile agentic-home-hub`）才能執行，憑證跟保管人要。

## 資料庫核心概念（Database/）

- **cms_homepage_service_vendor**：服務商主檔（`id`, `name`, `description`）
- **cms_homepage_service**：服務項目主檔，`type` 欄位代表服務類型：
  1=居家清潔 2=家電清洗 3=包裹寄送 6=餐廳訂位 9=美食外送 10=水電修繕 11=商城購物
- **label / service_label**：標籤主檔 + 服務項目與標籤的多對多關聯表
- **user_accounts / vendor_accounts**：會員 / 商家後台登入帳號（密碼 bcrypt 雜湊，個資 AES-256-GCM 加密存 `bytea`，同時有明文欄位對應的 `_hash` 欄位可查詢比對）
- **mms_order_record**：訂單/訂位統一紀錄表
- **mms_order_review**：訂單評價，`record_id` 直接沿用對應 `mms_order_record.record_id`（1:0..1，無獨立序列），一筆訂單至多一筆評價由 PK 天然保證。新增評價會同步把訂單的 `comment_status` 改成 `02`。`GET /services/{service_id}/reviews` 是全平台唯一不需身分驗證即可呼叫的公開端點（評價牆，回傳精簡過的 `PublicReviewOut`）。bff_server 所有回傳訂單的端點（`view_orders`、`list_orders`、`create_order`、`update_order`）都會用 `review_utils.py` 把對應評價併入訂單物件的 `review` 欄位（沒評價過則為 `null`），前端不需要另外呼叫評價 API。使用者提交評價走 `app_api.py` 的 `POST /orders/{record_id}/review`，修改評價走 `PATCH /users/{inbr_account_id}/orders/{record_id}/review`（皆為轉發 api_server，業務規則如訂單須完成、身分比對、防重複皆由 api_server 驗證）。批次查詢完整評價（回傳未經裁切的 `ReviewOut` 完整欄位，用 `client.py` 的 `get_all_items` 自動處理分頁抓取全部資料）：商家視角在 `merchant_api.py` 的 `GET /vendors/{id}/reviews`，APP 端依服務項目查詢在 `app_api.py` 的 `GET /services/{id}/reviews`（注意跟 api_server 同名的公開評價牆端點不同，這支回傳含身分關聯的完整內容，不適合當公開頁面用）
- **pms_form 系列**：諮詢表單結構（form → group → topic → option/media）。merchant_api.py 的 `POST /forms` 提供一次性建立表單+巢狀題組/題目/選項的組裝端點；`PATCH /forms/{id}` 提供差異比對式的完整表單更新（前端傳整包巢狀結構，帶 `id` 的項目視為更新、不帶 `id` 視為新增、現況有但 payload 沒帶到的視為刪除，依 選項→題目→題組 順序刪除、表單→題組→題目→選項 順序新增/更新）；兩者皆因 api_server 只有單筆 CRUD 端點、無跨資源交易機制，BFF 依序呼叫多支端點組裝，中途失敗不會自動回滾。`GET /vendors/{id}/forms`（清單，僅主檔）、`GET /forms/{id}/full`（單張表單完整巢狀內容，直接轉發 api_server 現成端點）
- **pms_form_feedback**：使用者填寫表單後的回饋記錄

完整規格見 `Database/API_Reference.md` 和 `Database/database/*.sql` 的欄位註解（COMMENT ON COLUMN）。整體16張表的關係圖與逐欄位種子資料覆蓋狀況見 `Database/database/README.md`。

## bff_server 開發慣例

- 每支 API 的 docstring 統一格式：**輸入** / **輸出** / **說明**，用 Markdown 語法寫（`-` 條列、` ```json ` code block），因為 FastAPI 會把 docstring 直接渲染進 Swagger UI（`/docs`），純縮排文字塊在 Markdown 裡不會保留換行。
- 型別標註走簡短風格（`(path, int)`、`(query, string, 可選)`），避免寫完整 Python union type，文件會太長難讀。
- payload 目前先用 `dict` 接收（快速開發），還沒上 Pydantic model 做驗證，之後有空可以補上。
- `TODO` 註解標記之後要補的排序/篩選邏輯，目前多數端點是「轉發 api_server + 少量組裝」的最小可行版本。

## 已知限制（上線前必須處理，demo 階段暫緩）

- 完全沒有身分驗證機制（登入只回傳識別碼，沒有 JWT/Session token）
- CORS 允許所有來源（`*`）
- RDS 密碼明文放在 EC2 的 `.env` 檔案

詳見 `Database/部署手冊.md` 第 8 章「上線前安全檢查清單」。

## Steering 自我維護規則

當你的改動涉及以下任何一項時，**必須**同步更新本 steering 文件（`.kiro/steering/project-overview.md`）：

- 新增、刪除或重新命名 API 端點（`app_api.py` / `merchant_api.py`）
- 調整目錄結構或新增重要檔案
- 架構層級變動（例如新增 service layer、新增 middleware）
- 部署流程或 AWS 環境資訊變更（IP、port、service name）
- 資料庫 table / 欄位結構變更（反映在「資料庫核心概念」段落）
- 開發慣例調整（docstring 格式、型別風格等）

更新時保持文件簡潔，只修改受影響的段落，不要整份重寫。

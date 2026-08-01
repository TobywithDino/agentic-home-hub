# BFF API Server

前端與 `Database/api_server`（隊友維護的 DB Access API）之間的中介層。
前端只呼叫這一層，這一層再呼叫 `Database/api_server` 取得原始資料，
並在中間做排序、label filter、資料組裝等前端需要、但不適合放進純資料存取層的邏輯。

架構：

```
前端 (APP / 商家後台)
   │
   ▼
bff_server (本資料夾, port 8100)
   │  透過 httpx 呼叫
   ▼
Database/api_server (隊友維護, port 8000)
   │
   ▼
PostgreSQL (RDS)
```

## 目前狀態

- `app_api.py`：APP 前端呼叫的 13 支 API
- `merchant_api.py`：商家後台呼叫的 20 支 API

完整端點規格與範例見 `API.md`，或部署後開 Swagger UI (`/docs`) 互動測試。

## 部署

改完程式碼後用 `deploy.sh` 一鍵部署到 EC2：

```bash
cd bff_server
bash deploy.sh
```

流程：打包 → 上傳 S3 → SSM 送指令到 EC2 解壓、裝依賴、重啟 `bff-api` service → 開安全群組 8100 埠 → health check 驗證。

需要先設定好 AWS CLI profile（`aws configure --profile agentic-home-hub`）。

## 本機開發

需要先啟動 `Database/api_server`（見該資料夾的 README），再啟動這一層：

```bash
pip install -r requirements.txt
cp .env.example .env   # 視需要調整 DB_API_BASE_URL
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8100
```

開啟 http://127.0.0.1:8100/docs 查看互動式 API 文件。

## 專案結構

```
app/
  config.py        設定讀取（環境變數，主要是 DB_API_BASE_URL）
  client.py        封裝對 Database/api_server 的 HTTP 呼叫（httpx）
                   含 get_optional（把 404 當空值）、get_all_items（自動分頁抓全部）
  deps.py          FastAPI 依賴注入（取得 DbApiClient）
  main.py          FastAPI 應用程式入口
  review_utils.py  共用邏輯：把 mms_order_review 併入訂單物件的 review 欄位
  routers/
    app_api.py       APP 前端呼叫的 13 支 API
    merchant_api.py  商家後台呼叫的 20 支 API
```

## 端點對應表

### APP 端（prefix: `/app-api`）

| # | Method | Path | 說明 |
|---|--------|------|------|
| 1 | GET | `/service-types/{service_type}/vendors` | 依服務類型+標籤篩選廠商 |
| 2 | GET | `/labels?service_type=` | 依服務類型精確篩選標籤（帶值=該類型專屬，不帶=通用） |
| 3 | GET | `/vendors/{service_vendor_id}/services` | 廠商的服務項目（可用 service_type 篩選，回傳含 form_id） |
| 4 | GET | `/services/{service_id}/labels` | 某服務項目擁有的標籤（僅實際擁有的，供顯示用） |
| 5 | GET | `/forms/{form_id}/full` | 表單完整內容（題組/題目/選項），供填單頁渲染 |
| 6 | POST | `/feedbacks` | 建立諮詢回饋單 |
| 7 | GET | `/users/{inbr_account_id}/orders-overview` | 會員訂單總覽（未處理 feedback + 全部訂單含 review） |
| 8 | POST | `/orders/{record_id}/review` | 對已完成訂單提交評價 |
| 9 | PATCH | `/users/{inbr_account_id}/orders/{record_id}/review` | 修改自己提交過的評價 |
| 10 | GET | `/services/{service_id}/reviews` | 某服務項目全部評價（完整內容，非公開評價牆） |
| 11 | GET | `/users/{inbr_account_id}` | 取得會員個人資訊 |
| 12 | PATCH | `/users/{inbr_account_id}` | 設定（更新）會員個人資訊 |
| 13 | POST | `/auth/login` | APP 會員登入，回傳 inbr_account_id |

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
| 12 | PATCH | `/forms/{form_id}` | 更新表單完整內容（差異比對式），必填 service_id |
| 13 | POST | `/forms` | 建立表單及巢狀內容（題組→題目→選項），必填 service_id |
| 14 | POST | `/orders` | 建立新訂單 |
| 15 | GET | `/vendors/{service_vendor_id}/reviews` | 該商家全部評價（不分頁，一次回傳全部） |
| 16 | GET | `/vendors/{service_vendor_id}/orders` | 該商家的訂單清單（含 review 欄位） |
| 17 | PATCH | `/vendors/{service_vendor_id}/orders/{record_id}` | 更新特定訂單（狀態/金額/時間） |
| 18 | GET | `/vendors/{service_vendor_id}` | 取得商家資訊（商家屬性 + 管理帳號清單） |
| 19 | PATCH | `/vendors/{service_vendor_id}` | 設定商家資訊（商家屬性 + 管理帳號聯絡方式） |
| 20 | POST | `/auth/login` | 商家後台登入，回傳 service_vendor_id + account_id |

## 注意事項

- 所有 API 目前**沒有身分驗證機制**（登入只回傳識別碼，沒有 JWT/Session token）
- 表單建立/更新（`POST /forms`、`PATCH /forms/{form_id}`）會自動把 `form_id` 寫回對應 service，前端不需要額外操作
- 所有回傳訂單的端點都會自動附加 `review` 欄位（有評價是完整物件，沒有則是 `null`）
- `PATCH /forms/{form_id}` 採差異比對式更新：帶 id=更新、不帶 id=新增、現況有但沒帶到=刪除
- 部署細節見 `.kiro/steering/project-overview.md`

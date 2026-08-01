# BFF API Server

前端與 `Database/api_server`（隊友維護的 DB Access API）之間的中介層。
前端只呼叫這一層，這一層再呼叫 `Database/api_server` 取得原始資料，
並在中間做排序、label filter、資料組裝等前端需要、但不適合放進純資料存取層的邏輯。

架構：

```
前端  --->  bff_server (本資料夾)  --->  Database/api_server  --->  PostgreSQL
```

## 目前狀態

`app_api.py`（APP 端，8 支）與 `merchant_api.py`（商家後台，12 支）
對應 `Database/AI指示文件/DB_API_1.jpg` 與 `DB_API_2.jpg` 兩張圖的每一個框框，
另加上 label 管理、表單 CRUD、訂單評價等後續新增功能。

完整端點清單與範例見 `API.md`。

## 最小啟動步驟

需要先啟動 `Database/api_server`（見該資料夾的 README），再啟動這一層：

```powershell
pip install -r requirements.txt
copy .env.example .env   # 視需要調整 DB_API_BASE_URL
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
    app_api.py       APP 前端呼叫的 8 支 API
    merchant_api.py  商家後台呼叫的 12 支 API
```

## 端點對應表

### APP 端（`/app-api`）

| 功能 | 路徑 | 說明 |
|---|---|---|
| 尋找廠商 | `GET /service-types/{service_type}/vendors` | 依服務類型+標籤篩選 |
| 建立 feedback | `POST /feedbacks` | 使用者填完表單後送出 |
| 查看訂單總覽 | `GET /users/{id}/orders-overview` | 未處理 feedback + 全部訂單（含 review） |
| 提交評價 | `POST /orders/{record_id}/review` | 訂單完成後提交評價 |
| 修改評價 | `PATCH /users/{id}/orders/{record_id}/review` | 修改自己提交過的評價 |
| 查看服務評價 | `GET /services/{service_id}/reviews` | 依服務項目查全部評價（完整內容） |
| 設定會員資訊 | `PATCH /users/{id}` | 更新聯絡方式/密碼 |
| 登入 | `POST /auth/login` | 回傳 inbr_account_id |

### 商家後台（`/merchant-api`）

| 功能 | 路徑 | 說明 |
|---|---|---|
| 查看 feedback | `GET /vendors/{id}/feedbacks` | 商家收到的諮詢回饋單 |
| 更新 feedback 狀態 | `PATCH /feedbacks/{feedback_no}/status` | 已讀/處理進度 |
| 查詢標籤勾選狀態 | `GET /services/{service_id}/labels` | 全部標籤 + checked 狀態 |
| 設定標籤（覆蓋式） | `PUT /services/{service_id}/labels` | 整包送、自動 diff |
| 查看全部評價 | `GET /vendors/{id}/reviews` | 一次回傳全部（不分頁） |
| 表單清單 | `GET /vendors/{id}/forms` | 僅主檔 |
| 表單完整內容 | `GET /forms/{form_id}/full` | 含題組/題目/選項 |
| 更新表單（差異比對） | `PATCH /forms/{form_id}` | 帶 id=更新、不帶=新增、沒出現=刪除 |
| 建立表單（巢狀） | `POST /forms` | 一次送完整結構 |
| 建立訂單 | `POST /orders` | 新增訂單 |
| 查看訂單 | `GET /vendors/{id}/orders` | 含 review 欄位 |
| 更新訂單 | `PATCH /vendors/{id}/orders/{record_id}` | 狀態/金額/時間 |
| 設定商家資訊 | `PATCH /vendors/{id}` | 商家屬性 + 管理帳號聯絡方式 |
| 登入 | `POST /auth/login` | 回傳 service_vendor_id + account_id |

# BFF API Server

前端與 `Database/api_server`（隊友維護的 DB Access API）之間的中介層。
前端只呼叫這一層，這一層再呼叫 `Database/api_server` 取得原始資料，
並在中間做排序、label filter、資料組裝等前端需要、但不適合放進純資料存取層的邏輯。

架構：

```
前端  --->  bff_server (本資料夾)  --->  Database/api_server  --->  PostgreSQL
```

## 目前狀態

裡面的 12 支 function 對應 `Database/AI指示文件/DB_API_1.jpg`（APP 端）與
`DB_API_2.jpg`（商家後台）兩張圖的每一個框框，目前先做「轉發 api_server + TODO」的假function，
之後再依前端實際需求逐步補上排序/篩選規則。

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
  config.py      設定讀取（環境變數，主要是 DB_API_BASE_URL）
  client.py       封裝對 Database/api_server 的 HTTP 呼叫（httpx）
  deps.py         FastAPI 依賴注入（取得 DbApiClient）
  main.py         FastAPI 應用程式入口
  routers/
    app_api.py       圖1：APP 前端呼叫的 5 支 function
    merchant_api.py  圖2：商家後台呼叫的 7 支 function
```

## 對應表

| 圖 | Function | 本層路徑 | 對應 api_server |
|---|---|---|---|
| 圖1 | 尋找特定服務的廠商 | `GET /app-api/service-types/{service_type}/vendors` | #16 + #12（依 service_type 找 service 再查 vendor，去重，非直接對應單一 api_server 端點） |
| 圖1 | 建立feedback | `POST /app-api/feedbacks` | #66 |
| 圖1 | 查看訂單 | `GET /app-api/users/{inbr_account_id}/orders-overview` | #70 + #75 |
| 圖1 | 設定會員資訊 | `PATCH /app-api/users/{inbr_account_id}` | #33 |
| 圖1 | 登入 | `POST /app-api/auth/login` | #31 |
| 圖2 | 查看feedback | `GET /merchant-api/vendors/{service_vendor_id}/feedbacks` | #68 |
| 圖2 | 更新feedback status | `PATCH /merchant-api/feedbacks/{feedback_no}/status` | #69 |
| 圖2 | 建立order | `POST /merchant-api/orders` | #71 |
| 圖2 | 查看order | `GET /merchant-api/vendors/{service_vendor_id}/orders` | #73 |
| 圖2 | 更新order | `PATCH /merchant-api/vendors/{service_vendor_id}/orders/{record_id}` | #74 |
| 圖2 | 設定商家資訊 | `PATCH /merchant-api/vendors/{service_vendor_id}` | #14 + #39 |
| 圖2 | 登入 | `POST /merchant-api/auth/login` | #36 |

細節（排序規則、篩選參數、回傳欄位裁切等）之後再慢慢調整。

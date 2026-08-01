# -*- coding: utf-8 -*-
"""
圖1（Database/AI指示文件/DB_API_1.jpg）：APP 前端呼叫的中介層 API。

APP 不直接打隊友的 DB Access API（Database/api_server），而是打這一層；
這一層再去呼叫 api_server 拿資料，中間做排序、label filter、資料組裝等
前端需要、但不適合放在純資料存取層的邏輯。
"""
from fastapi import APIRouter, Depends

from app.client import DbApiClient
from app.deps import get_db_api_client

router = APIRouter(prefix="/app-api", tags=["APP 端"])


@router.get("/service-types/{service_type}/vendors")
async def find_vendors_by_service(
    service_type: str,
    labels: str | None = None,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """尋找特定服務的廠商（可依標籤篩選）

    **輸入**
    - `service_type` (path, string): 服務類型代碼。
      1=居家清潔 2=家電清洗 3=包裹寄送 6=餐廳訂位 9=美食外送 10=水電修繕 11=商城購物
    - `labels` (query, string, 可選): 逗號分隔的標籤 id，例如 `3,5`。
      1=寵物友善 2=24小時營業 3=專業認證 4=免費估價 5=到府服務 6=快速到達

    **輸出**：廠商陣列
    ```json
    [
      {
        "id": 1,
        "name": "服務商名稱",
        "description": "服務商描述",
        "matched_services": [
          { "id": 17, "type": "10", "name": "服務項目名稱", "img_url": "..." }
        ]
      }
    ]
    ```
    `matched_services` 是此廠商符合篩選條件的服務項目清單。

    **說明**

    根據服務類型找出所有提供此類服務的廠商。若有傳入 `labels`，只保留
    「其下有服務項目同時擁有所有指定標籤」的廠商。
    """
    # Step 1: 取得符合 service_type 的所有 service
    services_resp = await db_api.get("/services", params={"type": service_type, "limit": 200})
    services = services_resp.json()["items"]

    # 解析前端傳入的 label 篩選條件
    required_label_ids: set[int] = set()
    if labels:
        required_label_ids = {int(lid.strip()) for lid in labels.split(",") if lid.strip()}

    # Step 2: 若有指定 labels，逐一查 service 的 label，篩選符合的 service
    if required_label_ids:
        filtered_services = []
        for service in services:
            service_id = service["id"]
            labels_resp = await db_api.get(
                f"/services/{service_id}/labels", params={"limit": 200}
            )
            service_label_ids = {item["label_id"] for item in labels_resp.json()["items"]}
            # 該 service 必須同時擁有所有指定的 label
            if required_label_ids.issubset(service_label_ids):
                filtered_services.append(service)
        services = filtered_services

    # Step 3: 取出 vendor_id 並去重
    vendor_ids = list(dict.fromkeys(s["service_vendor_id"] for s in services))

    # Step 4: 查詢每個 vendor 的完整資訊
    vendors = []
    for vendor_id in vendor_ids:
        vendor_resp = await db_api.get(f"/service-vendors/{vendor_id}")
        vendor_data = vendor_resp.json()

        # Step 5: 附加此 vendor 在篩選結果中對應的 service
        vendor_services = [s for s in services if s["service_vendor_id"] == vendor_id]
        vendor_data["matched_services"] = vendor_services
        vendors.append(vendor_data)

    return vendors


@router.post("/feedbacks", status_code=201)
async def create_feedback(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """建立諮詢回饋單（feedback）

    **輸入**（JSON body）
    ```json
    {
      "feedback_no": "FB20260801000001",
      "service_id": 17,
      "platform_code": "01",
      "form_id": 9,
      "form_type": "01",
      "feedback_content": { "...": "結構依表單定義" },
      "contact_name": "王小明",
      "contact_mobile": "0912345678",
      "contact_email": "user@example.com",
      "contact_address_county": "台北市",
      "contact_address_district": "大安區",
      "contact_address_detail": "...",
      "description": "補充說明",
      "inbr_account_id": "019c0464-2d01-73f0-9f9b-d1392fdb941a"
    }
    ```
    `platform_code` 固定 `01`（OP APP）。

    **輸出**：建立後的完整 feedback 物件，額外附帶：
    - `is_read`：`0`=未讀 `1`=已讀（新建一律 `0`）
    - `status`：`0`=未處理 `1`=處理中 `2`=已完成（新建一律 `0`）

    **說明**

    使用者填寫諮詢表單後呼叫此 API 建立一筆 feedback 記錄。
    """
    resp = await db_api.post("/feedbacks", json=payload)
    return resp.json()


@router.get("/users/{inbr_account_id}/orders-overview")
async def view_orders(
    inbr_account_id: str,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """查看會員的訂單總覽（未處理 feedback + 全部訂單）

    **輸入**
    - `inbr_account_id` (path, uuid): 會員 UUID，登入時取得

    **輸出**
    ```json
    {
      "feedbacks": [ { "feedback_no": "...", "status": "0", "...": "..." } ],
      "orders": [ { "record_id": 1, "order_no": "...", "order_status": "12", "...": "..." } ]
    }
    ```
    - `feedbacks`：狀態為未處理（`status="0"`）的諮詢回饋單
    - `orders`：該會員的全部訂單

    **說明**

    取得該會員的未處理諮詢與全部訂單，組裝後一次回傳，
    供前端顯示訂單/諮詢總覽頁面。
    """
    feedbacks_resp = await db_api.get(f"/users/{inbr_account_id}/feedbacks", params={"limit": 200})
    orders_resp = await db_api.get(f"/users/{inbr_account_id}/orders", params={"limit": 200})

    feedbacks = [f for f in feedbacks_resp.json()["items"] if f["status"] == "0"]
    orders = orders_resp.json()["items"]

    return {"feedbacks": feedbacks, "orders": orders}


@router.patch("/users/{inbr_account_id}")
async def update_member_profile(
    inbr_account_id: str,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """設定（更新）會員個人資訊

    **輸入**
    - `inbr_account_id` (path, uuid): 會員 UUID
    - body（只需傳要修改的欄位）：
    ```json
    {
      "password": "新密碼，8~72字元，不改就不傳",
      "contact_name": "會員姓名",
      "contact_mobile": "會員手機",
      "contact_email": "會員Email",
      "is_enable": "0=停用 1=啟用"
    }
    ```

    **輸出**：更新後的完整會員物件（不含密碼原文）

    **說明**

    更新會員聯絡方式或密碼，未傳入的欄位不會被覆蓋。
    密碼自動做 bcrypt 雜湊，聯絡資訊自動做 AES-256-GCM 加密。
    """
    resp = await db_api.patch(f"/users/{inbr_account_id}", json=payload)
    return resp.json()


@router.post("/auth/login")
async def login(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """APP 會員登入

    **輸入**
    ```json
    { "account": "user01@example.com", "password": "Test@1234" }
    ```

    **輸出**
    ```json
    { "inbr_account_id": "019c0464-2d01-73f0-9f9b-d1392fdb941a" }
    ```

    **說明**

    驗證帳密，成功後回傳會員 UUID。前端存起來，之後呼叫其他 API
    時作為路徑參數使用。目前無 token 機制，僅回傳識別碼。
    """
    resp = await db_api.post("/auth/user/login", json=payload)
    return resp.json()

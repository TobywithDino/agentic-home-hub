# -*- coding: utf-8 -*-
"""
圖2（Database/AI指示文件/DB_API_2.jpg）：商家後台呼叫的中介層 API。

商家後台不直接打隊友的 DB Access API（Database/api_server），而是打這一層；
這一層再去呼叫 api_server 拿資料，中間做排序、篩選、資料組裝等
商家後台需要的邏輯。
"""
from fastapi import APIRouter, Depends

from app.client import DbApiClient
from app.deps import get_db_api_client

router = APIRouter(prefix="/merchant-api", tags=["商家後台"])


@router.get("/vendors/{service_vendor_id}/feedbacks")
async def list_feedbacks(
    service_vendor_id: int,
    status: str | None = None,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """查看該商家收到的諮詢回饋單清單

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID
    - `status` (query, string, 可選): `0`=未處理 `1`=處理中 `2`=已完成，不傳則回傳全部

    **輸出**：feedback 物件陣列，每筆包含 `feedback_no`、`service_id`、
    `feedback_content`、`is_read`、`status`、`contact_name` 等聯絡資訊、
    `description`、`inbr_account_id`、`cre_time` 等欄位。

    **說明**

    取得屬於該服務商的所有諮詢回饋單，用於商家後台的回饋清單頁面。
    """
    resp = await db_api.get(
        f"/vendors/{service_vendor_id}/feedbacks",
        params={"status": status} if status is not None else None,
    )
    items = resp.json()

    return items


@router.patch("/feedbacks/{feedback_no}/status")
async def update_feedback_status(
    feedback_no: str,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """更新諮詢回饋單狀態（已讀/處理進度）

    **輸入**
    - `feedback_no` (path, string): 回饋單編號
    - body：
    ```json
    { "is_read": "0=未讀 1=已讀", "status": "0=未處理 1=處理中 2=已完成" }
    ```

    **輸出**：更新後的完整 feedback 物件

    **說明**

    商家閱讀或處理回饋單時呼叫此 API 更新狀態，兩個欄位皆為可選、只傳需要改的。
    """
    resp = await db_api.patch(f"/feedbacks/{feedback_no}/status", json=payload)
    return resp.json()


@router.get("/services/{service_id}/labels")
async def get_service_labels(
    service_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """查詢服務項目目前的標籤勾選狀態（給編輯頁面用）

    **輸入**
    - `service_id` (path, int): 服務項目 ID

    **輸出**：全部標籤清單，並標示此 service 目前是否已勾選
    ```json
    [
      { "id": 1, "name": "寵物友善", "checked": true },
      { "id": 2, "name": "24小時營業", "checked": false }
    ]
    ```

    **說明**

    給商家後台「編輯服務項目」頁面用：一次拿到所有可選標籤，
    並直接標示哪些是此 service 已經有的，前端可以直接渲染成
    已勾選/未勾選的 checkbox，不用自己再做比對。
    """
    labels_resp = await db_api.get("/labels", params={"limit": 200})
    all_labels = labels_resp.json()["items"]

    service_labels_resp = await db_api.get(
        f"/services/{service_id}/labels", params={"limit": 200}
    )
    checked_label_ids = {item["label_id"] for item in service_labels_resp.json()["items"]}

    return [
        {"id": label["id"], "name": label["name"], "checked": label["id"] in checked_label_ids}
        for label in all_labels
    ]


@router.put("/services/{service_id}/labels")
async def set_service_labels(
    service_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """設定服務項目的標籤（覆蓋式）

    **輸入**
    - `service_id` (path, int): 服務項目 ID
    - body：
    ```json
    { "label_ids": [1, 3, 5] }
    ```
    傳入完整的標籤 id 清單，會**取代**該 service 原有的全部標籤
    （不在清單內的既有標籤會被移除，新出現的會被新增）。

    **輸出**：更新後的完整標籤清單，格式同 `GET .../labels`
    ```json
    [
      { "id": 1, "name": "寵物友善", "checked": true },
      { "id": 2, "name": "24小時營業", "checked": false }
    ]
    ```

    **說明**

    給商家後台「編輯服務項目」頁面的儲存按鈕用。前端頁面載入時已用
    `GET .../labels` 勾好現有標籤，使用者調整勾選後，把目前畫面上
    所有「勾選中」的 label_id 整包傳過來即可，不需要自己算差異。
    這裡會自動比對現有關聯，只新增/刪除有變動的部分
    （api_server 本身沒有批次覆蓋的端點，逐筆呼叫組成）。
    """
    target_label_ids = set(payload.get("label_ids", []))

    service_labels_resp = await db_api.get(
        f"/services/{service_id}/labels", params={"limit": 200}
    )
    current_label_ids = {item["label_id"] for item in service_labels_resp.json()["items"]}

    to_add = target_label_ids - current_label_ids
    to_remove = current_label_ids - target_label_ids

    for label_id in to_add:
        await db_api.put(f"/services/{service_id}/labels/{label_id}")
    for label_id in to_remove:
        await db_api.delete(f"/services/{service_id}/labels/{label_id}")

    labels_resp = await db_api.get("/labels", params={"limit": 200})
    all_labels = labels_resp.json()["items"]

    return [
        {"id": label["id"], "name": label["name"], "checked": label["id"] in target_label_ids}
        for label in all_labels
    ]


@router.post("/orders", status_code=201)
async def create_order(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """建立新訂單

    **輸入**（JSON body）
    ```json
    {
      "order_no": "訂單編號",
      "service_vendor_id": 1,
      "service_id": 17,
      "platform_code": "01",
      "inbr_account_id": "會員UUID",
      "member_name": "會員姓名(明文,自動加密)",
      "member_phone": "會員電話(明文,自動加密)",
      "member_email": "會員Email(明文,自動加密)",
      "order_type": "01=服務訂單 02=訂位 03=預約 04=其他 05=商品訂單 06=訂餐",
      "order_status": "初始狀態碼,見下方說明",
      "order_time": "ISO8601時間",
      "deposit_amount": 0, "original_amount": 0, "discount_amount": 0,
      "shipping_fee_amount": 0, "final_amount": 0,
      "vendor_data": {}, "order_items": {},
      "remark": "備註",
      "cre_id": "建立者UUID", "upd_id": "異動者UUID"
    }
    ```
    `order_status` 初始值：服務訂單用 `11`(待訂金)；訂位/預約/商品/訂餐用 `01`(待付款)。

    **輸出**：建立後的完整訂單物件（含系統產生的 `record_id`）

    **說明**

    商家後台建立一筆新訂單。個資欄位傳入明文即可，系統會自動用
    AES-256-GCM 加密存儲。
    """
    resp = await db_api.post("/orders", json=payload)
    return resp.json()


@router.get("/vendors/{service_vendor_id}/orders")
async def list_orders(
    service_vendor_id: int,
    order_status: str | None = None,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """查看該商家的訂單清單

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID
    - `order_status` (query, string, 可選): 篩選訂單狀態碼，不傳則回傳全部。
      服務訂單常用：`11`待訂金 `12`已付訂金待報價 `13`已報價待同意 `80`已完成 `90`已取消
      訂位/預約常用：`01`待付款 `02`待確認 `03`已確認 `80`已完成 `90`已取消

    **輸出**：訂單物件陣列，每筆包含 `record_id`、`order_no`、
    `inbr_account_id`、`order_type`、`order_status`、`order_time`、
    `final_amount`、`order_items` 等欄位。

    **說明**

    取得屬於該服務商的所有訂單，用於商家後台的訂單管理頁面。
    """
    resp = await db_api.get(
        f"/vendors/{service_vendor_id}/orders",
        params={"order_status": order_status} if order_status is not None else None,
    )
    items = resp.json()

    return items


@router.patch("/vendors/{service_vendor_id}/orders/{record_id}")
async def update_order(
    service_vendor_id: int,
    record_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """更新特定訂單（狀態、金額、時間等）

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID
    - `record_id` (path, int): 訂單內部 ID
    - body（只傳需要改的欄位，`upd_id` 必填）：
    ```json
    {
      "order_status": "新狀態碼",
      "deposit_time": "ISO8601", "confirm_time": "ISO8601",
      "service_time": "ISO8601", "complete_time": "ISO8601", "cancel_time": "ISO8601",
      "deposit_amount": 0, "final_amount": 0, "refund_amount": 0,
      "vendor_data": {}, "order_items": {},
      "remark": "備註", "cancel_reason": "取消原因", "refund_reason": "退款原因",
      "quote_no": "報價單編號",
      "comment_status": "00=無須評價 01=未評價 02=已評價",
      "is_deleted": false,
      "upd_id": "異動者UUID"
    }
    ```

    **輸出**：更新後的完整訂單物件

    **說明**

    常見場景：確認訂金（`order_status` 11→12 + `deposit_time`）、
    報價（改 13 + `quote_no`）、完成（改 80 + `complete_time`）、
    取消（改 90 + `cancel_time` + `cancel_reason`）。
    """
    resp = await db_api.patch(f"/vendors/{service_vendor_id}/orders/{record_id}", json=payload)
    return resp.json()


@router.patch("/vendors/{service_vendor_id}")
async def update_merchant_profile(
    service_vendor_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """設定（更新）商家資訊（商家屬性 + 管理帳號聯絡方式）

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID
    - body，兩個區塊皆可選、可只傳其中一個：
    ```json
    {
      "vendor_profile": { "name": "服務商名稱", "description": "服務商描述" },
      "account_id": "要更新聯絡方式的管理帳號UUID",
      "account_contact": {
        "password": "新密碼(8~72字元)",
        "contact_name": "聯絡人姓名",
        "contact_mobile": "聯絡人手機",
        "contact_email": "聯絡人Email",
        "is_enable": "0=停用 1=啟用"
      }
    }
    ```
    `account_contact` 需搭配 `account_id` 才會生效。

    **輸出**
    ```json
    {
      "vendor_profile": { "...": "有更新才回傳" },
      "account_contact": { "...": "有更新才回傳" }
    }
    ```

    **說明**

    商家後台「設定」頁面用的 API，可同時更新商家基本屬性和管理帳號的
    密碼/聯絡資訊，兩個區塊互相獨立。
    """
    result: dict = {}

    vendor_profile = payload.get("vendor_profile")
    if vendor_profile is not None:
        resp = await db_api.patch(f"/service-vendors/{service_vendor_id}", json=vendor_profile)
        result["vendor_profile"] = resp.json()

    account_id = payload.get("account_id")
    account_contact = payload.get("account_contact")
    if account_id is not None and account_contact is not None:
        resp = await db_api.patch(
            f"/vendors/{service_vendor_id}/accounts/{account_id}", json=account_contact
        )
        result["account_contact"] = resp.json()

    return result


@router.post("/auth/login")
async def login(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """商家後台登入

    **輸入**
    ```json
    { "account": "vendor01@example.com", "password": "Test@1234" }
    ```

    **輸出**
    ```json
    { "service_vendor_id": 1, "account_id": "019fb652-df72-7992-989e-f456194edf8c" }
    ```

    **說明**

    驗證商家帳密，成功後回傳 `service_vendor_id` 和 `account_id`，
    前端存起來供後續 API 呼叫使用。目前無 token 機制，僅回傳識別碼。
    """
    resp = await db_api.post("/auth/vendor/login", json=payload)
    return resp.json()

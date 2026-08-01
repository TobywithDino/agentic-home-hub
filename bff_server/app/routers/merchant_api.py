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
    """查看該商家收到的諮詢回饋單（feedback）清單。

    輸入:
        service_vendor_id (int, path): 服務商 ID，登入時取得
        status (str, query, 可選): 篩選回饋單狀態
            "0"=未處理, "1"=處理中, "2"=已完成。不傳則回傳全部。

    輸出: list[Feedback]
        [
            {
                "feedback_no": str,             # 回饋單編號
                "service_id": int,              # 服務項目 ID
                "platform_code": str,           # 平台代號 "01"=OP APP
                "form_id": int,                 # 表單 ID
                "feedback_content": dict | list,# 回饋內容
                "form_type": str,               # 表單類型代碼
                "is_read": str,                 # "0"=未讀, "1"=已讀
                "status": str,                  # "0"=未處理, "1"=處理中, "2"=已完成
                "contact_name": str | null,     # 聯絡人姓名
                "contact_mobile": str | null,   # 聯絡人手機
                "contact_email": str | null,    # 聯絡人 Email
                "preferred_contact_time": str | null,
                "contact_address_county": str | null,
                "contact_address_district": str | null,
                "contact_address_detail": str | null,
                "description": str | null,      # 補充描述
                "inbr_account_id": str,         # 送出此回饋的會員 UUID
                "cre_time": str,                # 建立時間 ISO 8601
                "upd_time": str
            }
        ]

    描述:
        取得屬於該服務商的所有諮詢回饋單。商家後台用此 API 顯示
        待處理/已處理的回饋清單。可透過 status 參數篩選特定狀態。
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
    """更新諮詢回饋單的狀態（已讀/處理進度）。

    輸入:
        feedback_no (str, path): 回饋單編號，例如 "FB20260801000001"
        payload (JSON body): 要更新的狀態欄位（只傳需要改的）
            {
                "is_read": str | null,   # "0"=未讀, "1"=已讀
                "status": str | null     # "0"=未處理, "1"=處理中, "2"=已完成
            }

    輸出: Feedback（更新後的完整回饋單物件，結構同 list_feedbacks 的單筆）

    描述:
        商家閱讀或處理回饋單後，呼叫此 API 更新狀態。
        例如：商家打開回饋單時設 is_read="1"，開始處理時設 status="1"，
        處理完成設 status="2"。
    """
    resp = await db_api.patch(f"/feedbacks/{feedback_no}/status", json=payload)
    return resp.json()


@router.post("/orders", status_code=201)
async def create_order(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """建立新訂單。

    輸入: payload (JSON body)
        {
            "order_no": str,                # 訂單編號（服務商提供，最長 50 字元）
            "service_vendor_id": int,       # 服務商 ID
            "service_id": int,              # 服務項目 ID
            "platform_code": str,           # 平台代號 "01"=OP APP
            "inbr_account_id": str,         # 下單會員 UUID
            "member_name": str | null,      # 會員姓名（明文，會自動加密）
            "member_phone": str | null,     # 會員電話（明文，會自動加密）
            "member_email": str | null,     # 會員 Email（明文，會自動加密）
            "order_type": str,              # 訂單類型: "01"=服務訂單, "02"=訂位,
                                            #   "03"=預約, "04"=其他, "05"=商品訂單, "06"=訂餐
            "order_status": str,            # 初始狀態碼（依 order_type 而異，見下方說明）
            "order_time": str,              # 訂單建立時間 ISO 8601
            "deposit_amount": float,        # 訂金金額（預設 0）
            "original_amount": float,       # 原始金額（預設 0）
            "discount_amount": float,       # 折扣金額（預設 0）
            "shipping_fee_amount": float,   # 運費金額（預設 0）
            "final_amount": float,          # 實付金額（預設 0）
            "vendor_data": dict | null,     # 服務商特定資料（JSON）
            "order_items": dict | list | null,  # 訂單項目明細（JSON）
            "remark": str | null,           # 備註
            "cre_id": str,                  # 建立者 UUID
            "upd_id": str                   # 異動者 UUID
        }

        order_status 常用初始值:
            服務訂單("01"): "11"=待訂金支付
            訂位("02"): "01"=待付款
            預約/商品/訂餐: "01"=待付款

    輸出: Order（建立後的完整訂單物件）
        {
            "record_id": int,           # 系統自動產生的訂單內部 ID
            "order_no": str,
            "service_vendor_id": int,
            "service_id": int,
            "order_type": str,
            "order_status": str,
            "order_time": str,
            "final_amount": float,
            "order_items": dict | list | null,
            "cre_time": str,
            ...
        }

    描述:
        商家後台建立一筆新訂單，寫入 mms_order_record 表。
        個資欄位（姓名、電話、Email）傳入明文，系統自動做 AES-256-GCM 加密存儲。
    """
    resp = await db_api.post("/orders", json=payload)
    return resp.json()


@router.get("/vendors/{service_vendor_id}/orders")
async def list_orders(
    service_vendor_id: int,
    order_status: str | None = None,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """查看該商家的訂單清單。

    輸入:
        service_vendor_id (int, path): 服務商 ID
        order_status (str, query, 可選): 篩選訂單狀態碼。不傳則回傳全部。
            服務訂單常用: "11"=待訂金, "12"=已付訂金待報價, "13"=已報價待同意,
                         "14"=同意報價, "80"=已完成, "90"=已取消
            訂位/預約常用: "01"=待付款, "02"=待確認, "03"=已確認, "80"=已完成, "90"=已取消

    輸出: list[Order]
        [
            {
                "record_id": int,
                "order_no": str,
                "service_vendor_id": int,
                "service_id": int,
                "inbr_account_id": str,         # 下單會員 UUID
                "order_type": str,
                "order_status": str,
                "order_time": str,              # ISO 8601
                "deposit_amount": float,
                "final_amount": float,
                "order_items": dict | list | null,
                "remark": str | null,
                "is_deleted": bool,
                "cre_time": str,
                "upd_time": str,
                ...
            }
        ]

    描述:
        取得屬於該服務商的所有訂單。商家後台用此 API 顯示訂單管理頁面。
        可透過 order_status 參數篩選特定狀態的訂單。
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
    """更新特定訂單（狀態、金額、時間等）。

    輸入:
        service_vendor_id (int, path): 服務商 ID
        record_id (int, path): 訂單內部 ID（record_id）
        payload (JSON body): 要更新的欄位（只傳需要改的）
            {
                "order_status": str | null,         # 新狀態碼
                "deposit_time": str | null,         # 訂金支付時間 ISO 8601
                "confirm_time": str | null,         # 確認時間
                "service_time": str | null,         # 服務時間
                "complete_time": str | null,        # 完成時間
                "cancel_time": str | null,          # 取消時間
                "deposit_amount": float | null,
                "original_amount": float | null,
                "discount_amount": float | null,
                "shipping_fee_amount": float | null,
                "final_amount": float | null,
                "refund_amount": float | null,
                "vendor_data": dict | null,         # 服務商特定資料
                "order_items": dict | list | null,  # 訂單項目明細
                "remark": str | null,
                "cancel_reason": str | null,
                "refund_reason": str | null,
                "quote_approved_by": str | null,    # 報價審核者 UUID
                "quote_approved_time": str | null,
                "quote_no": str | null,             # 報價單編號
                "comment_status": str | null,       # "00"=無須評價, "01"=未評價, "02"=已評價
                "is_deleted": bool | null,          # 軟刪除
                "upd_id": str                       # 異動者 UUID（必填）
            }

    輸出: Order（更新後的完整訂單物件，結構同 list_orders 的單筆）

    描述:
        商家更新訂單狀態或相關資訊。常見場景：
        - 確認收到訂金 → order_status 從 "11" 改 "12"，填 deposit_time
        - 報價 → order_status 改 "13"，填 quote_no
        - 完成訂單 → order_status 改 "80"，填 complete_time
        - 取消訂單 → order_status 改 "90"，填 cancel_time + cancel_reason
    """
    resp = await db_api.patch(f"/vendors/{service_vendor_id}/orders/{record_id}", json=payload)
    return resp.json()


@router.patch("/vendors/{service_vendor_id}")
async def update_merchant_profile(
    service_vendor_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """設定（更新）商家資訊（商家屬性 + 管理帳號聯絡方式）。

    輸入:
        service_vendor_id (int, path): 服務商 ID
        payload (JSON body):
            {
                "vendor_profile": {             # (可選) 更新商家屬性
                    "name": str | null,         # 服務商名稱（最長 50 字元）
                    "description": str | null   # 服務商描述（最長 200 字元）
                },
                "account_id": str,              # (可選) 要更新聯絡方式的管理帳號 UUID
                "account_contact": {            # (可選，需搭配 account_id) 更新聯絡方式
                    "password": str | null,         # 新密碼（8~72 字元）
                    "contact_name": str | null,     # 聯絡人姓名
                    "contact_mobile": str | null,   # 聯絡人手機
                    "contact_email": str | null,    # 聯絡人 Email
                    "is_enable": str | null         # "0"=停用, "1"=啟用
                }
            }

    輸出: MerchantProfileResult
        {
            "vendor_profile": {             # 若有更新商家屬性才回傳
                "id": int,
                "name": str,
                "description": str | null
            },
            "account_contact": {            # 若有更新聯絡方式才回傳
                "id": str,                  # 帳號 UUID
                "service_vendor_id": int,
                "account": str,
                "contact_name": str | null,
                "contact_mobile": str | null,
                "contact_email": str | null,
                "is_enable": str,
                ...
            }
        }

    描述:
        商家後台的「設定」頁面，可同時更新商家基本屬性和管理帳號的聯絡方式。
        兩個區塊獨立，可以只傳其中一個。
        - vendor_profile: 更新服務商名稱/描述
        - account_contact: 更新管理帳號的密碼/聯絡資訊（需一併傳 account_id）
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
    """商家後台登入。

    輸入: payload (JSON body)
        {
            "account": str,    # 登入帳號（Email 格式）
            "password": str    # 密碼
        }

    輸出: LoginResult
        {
            "service_vendor_id": int,   # 服務商 ID，後續 API 都用這個識別商家
            "account_id": str           # 管理帳號 UUID
        }

    描述:
        驗證商家帳密，成功後回傳 service_vendor_id 和 account_id。
        前端拿到後存起來，之後呼叫其他商家 API 時作為路徑參數使用。
        目前無 token 機制，僅回傳識別碼。

    範例:
        POST /merchant-api/auth/login
        {"account": "vendor01@example.com", "password": "Test@1234"}
        → {"service_vendor_id": 1, "account_id": "019fb652-df72-7992-989e-f456194edf8c"}
    """
    resp = await db_api.post("/auth/vendor/login", json=payload)
    return resp.json()

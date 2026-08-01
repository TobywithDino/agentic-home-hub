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
    """尋找特定服務的廠商（可依標籤篩選）。

    輸入:
        service_type (str, path): 服務類型代碼。
            可用值: "1"=一般居家清潔, "2"=家電清洗, "3"=包裹寄送,
                    "6"=餐廳訂位, "9"=美食外送, "10"=水電修繕, "11"=商城購物
        labels (str, query, 可選): 以逗號分隔的 label_id 清單，例如 "3,5"。
            只回傳「其下至少有一個 service 同時擁有所有指定 label」的廠商。
            可用 label: 1=寵物友善, 2=24小時營業, 3=專業認證,
                        4=免費估價, 5=到府服務, 6=快速到達

    輸出: list[Vendor]
        每個 Vendor 物件結構:
        {
            "id": int,                  # 服務商 ID
            "name": str,                # 服務商名稱
            "description": str | null,  # 服務商描述
            "matched_services": [       # 此廠商在篩選結果中符合條件的服務項目
                {
                    "id": int,                  # 服務項目 ID
                    "service_vendor_id": int,   # 所屬服務商 ID
                    "type": str,                # 服務類型代碼
                    "name": str,                # 服務項目名稱
                    "img_url": str | null,      # 服務項目圖片 URL
                    "description": str | null   # 服務項目說明
                }
            ]
        }

    描述:
        根據服務類型找出所有提供此類服務的廠商。若有傳入 labels 參數，
        會進一步篩選：只保留其下有 service 同時擁有「所有」指定標籤的廠商。
        回傳結果會附帶每個廠商符合條件的 service 清單。
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
    """建立諮詢回饋單（feedback）。

    輸入: payload (JSON body)
        {
            "feedback_no": str,              # 回饋單編號，16 字元，例如 "FB20260801000001"
            "service_id": int,               # 服務項目 ID
            "platform_code": str,            # 平台代號，"01"=OP APP
            "form_id": int,                  # 表單 ID
            "feedback_content": dict | list, # 回饋內容（JSON，結構依表單定義）
            "form_type": str,                # 表單類型代碼（2 碼）
            "contact_name": str | null,      # 聯絡人姓名
            "contact_mobile": str | null,    # 聯絡人手機
            "contact_landline": str | null,  # 聯絡人市話
            "contact_email": str | null,     # 聯絡人 Email
            "preferred_contact_time": str | null,  # 方便聯絡時段
            "contact_address_county": str | null,  # 聯絡地址-縣市
            "contact_address_district": str | null,# 聯絡地址-行政區
            "contact_address_detail": str | null,  # 聯絡地址-詳細地址
            "description": str | null,       # 補充描述（最長 1000 字）
            "inbr_account_id": str           # 會員 UUID
        }

    輸出: Feedback
        {
            "feedback_no": str,
            "service_id": int,
            "platform_code": str,
            "form_id": int,
            "feedback_content": dict | list,
            "form_type": str,
            "is_read": str,         # "0"=未讀, "1"=已讀
            "status": str,          # "0"=未處理, "1"=處理中, "2"=已完成
            "contact_name": str | null,
            "contact_mobile": str | null,
            "contact_email": str | null,
            "preferred_contact_time": str | null,
            "contact_address_county": str | null,
            "contact_address_district": str | null,
            "contact_address_detail": str | null,
            "description": str | null,
            "inbr_account_id": str,
            "cre_time": str,        # ISO 8601 時間
            "upd_time": str
        }

    描述:
        使用者填寫諮詢表單後，前端呼叫此 API 建立一筆 feedback 記錄。
        建立後預設 is_read="0"（未讀）、status="0"（未處理）。
    """
    resp = await db_api.post("/feedbacks", json=payload)
    return resp.json()


@router.get("/users/{inbr_account_id}/orders-overview")
async def view_orders(
    inbr_account_id: str,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """查看會員的訂單總覽（未處理的 feedback + 全部訂單）。

    輸入:
        inbr_account_id (str, path): 會員 UUID，登入時取得

    輸出: OrdersOverview
        {
            "feedbacks": [              # 狀態為「未處理」的諮詢回饋單
                {
                    "feedback_no": str,
                    "service_id": int,
                    "form_type": str,
                    "status": str,              # 這裡固定是 "0"（未處理）
                    "feedback_content": dict | list,
                    "contact_name": str | null,
                    "description": str | null,
                    "cre_time": str,
                    ...
                }
            ],
            "orders": [                 # 該會員的全部訂單
                {
                    "record_id": int,           # 訂單系統內部 ID
                    "order_no": str,            # 訂單編號
                    "service_vendor_id": int,
                    "service_id": int,
                    "order_type": str,          # "01"=服務訂單, "02"=訂位, "03"=預約, "05"=商品訂單, "06"=訂餐
                    "order_status": str,        # 訂單狀態碼（依 order_type 不同有不同含義）
                    "order_time": str,          # 訂單建立時間 ISO 8601
                    "final_amount": float,      # 實付金額
                    "order_items": dict | list | null,  # 訂單項目明細
                    ...
                }
            ]
        }

    描述:
        取得該會員的「未處理 feedback」和「全部訂單」，組裝後一次回傳。
        前端用此 API 顯示會員的訂單/諮詢總覽頁面。
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
    """設定（更新）會員個人資訊。

    輸入:
        inbr_account_id (str, path): 會員 UUID
        payload (JSON body): 要更新的欄位（只傳需要改的）
            {
                "password": str | null,        # 新密碼（8~72 字元），不改就不傳
                "contact_name": str | null,    # 會員姓名
                "contact_mobile": str | null,  # 會員手機
                "contact_email": str | null,   # 會員 Email
                "is_enable": str | null        # "0"=停用, "1"=啟用
            }

    輸出: User
        {
            "id": str,                  # 會員 UUID
            "account": str,             # 登入帳號
            "contact_name": str | null,
            "contact_mobile": str | null,
            "contact_email": str | null,
            "is_2fa_enabled": str,      # "0"=未啟用, "1"=已啟用
            "last_login_time": str | null,
            "is_enable": str,
            "is_deleted": str,
            "upd_time": str,
            "cre_time": str
        }

    描述:
        更新會員的聯絡方式或密碼。只需傳入要修改的欄位，
        未傳入的欄位不會被覆蓋。密碼會自動做 bcrypt 雜湊，
        聯絡資訊會自動做 AES-256-GCM 加密。
    """
    resp = await db_api.patch(f"/users/{inbr_account_id}", json=payload)
    return resp.json()


@router.post("/auth/login")
async def login(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """APP 會員登入。

    輸入: payload (JSON body)
        {
            "account": str,    # 登入帳號（Email 格式）
            "password": str    # 密碼
        }

    輸出: LoginResult
        {
            "inbr_account_id": str    # 會員 UUID，後續所有 API 都用這個識別身分
        }

    描述:
        驗證帳密，成功後回傳會員的 UUID (inbr_account_id)。
        前端拿到後存起來，之後呼叫其他 API 時作為路徑參數使用。
        目前無 token 機制，僅回傳識別碼。

    範例:
        POST /app-api/auth/login
        {"account": "user01@example.com", "password": "Test@1234"}
        → {"inbr_account_id": "019c0464-2d01-73f0-9f9b-d1392fdb941a"}
    """
    resp = await db_api.post("/auth/user/login", json=payload)
    return resp.json()

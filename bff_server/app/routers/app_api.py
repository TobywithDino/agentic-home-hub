# -*- coding: utf-8 -*-
"""
圖1（Database/AI指示文件/DB_API_1.jpg）：APP 前端呼叫的中介層 API。

APP 不直接打隊友的 DB Access API（Database/api_server），而是打這一層；
這一層再去呼叫 api_server 拿資料，中間做排序、label filter、資料組裝等
前端需要、但不適合放在純資料存取層的邏輯。

目前先建立「假function」：每支先做「轉發 api_server + TODO 業務邏輯」，
之後再依前端實際需求逐步補上排序/篩選規則。
"""
from fastapi import APIRouter, Depends

from app.client import DbApiClient
from app.deps import get_db_api_client

router = APIRouter(prefix="/app-api", tags=["APP 端"])


@router.get("/service-types/{service_type}/vendors")
async def find_vendors_by_service(
    service_type: str,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """尋找特定服務的廠商：回傳所有提供此服務類型 (service_type) 的廠商。

    對應圖1「尋找特定服務的廠商」。api_server 本身沒有「依服務類型找廠商」的
    現成端點，這裡組合兩支既有端點自己拼出來，沒有改動 Database/：
    1. api_server #16 (`GET /services?type=...`) 找出符合此服務類型的所有 service
    2. 取出這些 service 的 service_vendor_id 並去重
    3. 逐一呼叫 api_server #12 (`GET /service-vendors/{id}`) 組成廠商清單

    注意：#16 單次最多回傳 200 筆 service（api_server 分頁上限），
    若未來某服務類型的 service 數量超過 200，需要改成分頁迴圈抓取。
    """
    services_resp = await db_api.get("/services", params={"type": service_type, "limit": 200})
    services = services_resp.json()["items"]

    vendor_ids = list(dict.fromkeys(s["service_vendor_id"] for s in services))

    vendors = []
    for vendor_id in vendor_ids:
        vendor_resp = await db_api.get(f"/service-vendors/{vendor_id}")
        vendors.append(vendor_resp.json())

    # TODO: label filter（DB 欄位還沒新增，先保留不做）
    # TODO: 排序等前端需要的邏輯放這裡

    return vendors


@router.post("/feedbacks", status_code=201)
async def create_feedback(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """建立 feedback：判斷 feedback 類型內容，更新 DB。

    對應圖1「建立feedback」/ api_server #66 (`POST /feedbacks`)。
    """
    # TODO: 依 payload 中的表單類型 (form_type) 判斷/組裝 feedback_content，
    # 目前先原封不動轉發給 api_server。
    resp = await db_api.post("/feedbacks", json=payload)
    return resp.json()


@router.get("/users/{inbr_account_id}/orders-overview")
async def view_orders(
    inbr_account_id: str,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """查看訂單：
    - 去 feedback_record 抓 status 未處理的 feedbacks
    - 去 order_record 抓 order
    - feedbacks + orders 拼在一起回傳

    對應圖1「查看訂單」。api_server 另有 #76
    (`GET /users/{id}/order-summary`) 已做相同拼接，
    這裡刻意自己各別呼叫、自己組裝，保留之後客製化排序/篩選的彈性
    （例如訂單依時間排序、feedback 依表單類型篩選）。
    """
    feedbacks_resp = await db_api.get(f"/users/{inbr_account_id}/feedbacks", params={"limit": 200})
    orders_resp = await db_api.get(f"/users/{inbr_account_id}/orders", params={"limit": 200})

    feedbacks = [f for f in feedbacks_resp.json()["items"] if f["status"] == "0"]
    orders = orders_resp.json()["items"]

    # TODO: 排序 / 分頁等前端需要的邏輯放這裡

    return {"feedbacks": feedbacks, "orders": orders}


@router.patch("/users/{inbr_account_id}")
async def update_member_profile(
    inbr_account_id: str,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """設定會員資訊：更新 DB 會員資訊（聯絡方式、密碼）。

    對應圖1「設定會員資訊」/ api_server #33 (`PATCH /users/{id}`)。
    """
    resp = await db_api.patch(f"/users/{inbr_account_id}", json=payload)
    return resp.json()


@router.post("/auth/login")
async def login(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """登入：根據帳密，回傳 inbr_account_id 給 APP。

    對應圖1「登入」/ api_server #31 (`POST /auth/user/login`)。
    """
    resp = await db_api.post("/auth/user/login", json=payload)
    return resp.json()

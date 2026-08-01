# -*- coding: utf-8 -*-
"""
圖2（Database/AI指示文件/DB_API_2.jpg）：商家後台呼叫的中介層 API。

商家後台不直接打隊友的 DB Access API（Database/api_server），而是打這一層；
這一層再去呼叫 api_server 拿資料，中間做排序、篩選、資料組裝等
商家後台需要的邏輯。

目前先建立「假function」：每支先做「轉發 api_server + TODO 業務邏輯」，
之後再依實際需求逐步補上排序/篩選規則。
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
    """查看 feedback：根據 service_vendor_id 抓取 feedbacks。

    對應圖2「查看feedback」/ api_server #68
    (`GET /vendors/{id}/feedbacks`)。
    """
    resp = await db_api.get(
        f"/vendors/{service_vendor_id}/feedbacks",
        params={"status": status} if status is not None else None,
    )
    items = resp.json()

    # TODO: 排序 / 篩選等商家後台需要的邏輯放這裡

    return items


@router.patch("/feedbacks/{feedback_no}/status")
async def update_feedback_status(
    feedback_no: str,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """更新 feedback status：改 feedback 的 is_read 或 status。

    對應圖2「更新feedback status」/ api_server #69
    (`PATCH /feedbacks/{feedback_no}/status`)。
    """
    resp = await db_api.patch(f"/feedbacks/{feedback_no}/status", json=payload)
    return resp.json()


@router.post("/orders", status_code=201)
async def create_order(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """建立 order：新增至 mms_order_record。

    對應圖2「建立order」/ api_server #71 (`POST /orders`)。
    """
    resp = await db_api.post("/orders", json=payload)
    return resp.json()


@router.get("/vendors/{service_vendor_id}/orders")
async def list_orders(
    service_vendor_id: int,
    order_status: str | None = None,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """查看 order：根據 service_vendor_id 抓取 orders。

    對應圖2「查看order」/ api_server #73
    (`GET /vendors/{id}/orders`)。
    """
    resp = await db_api.get(
        f"/vendors/{service_vendor_id}/orders",
        params={"order_status": order_status} if order_status is not None else None,
    )
    items = resp.json()

    # TODO: 排序 / 篩選等商家後台需要的邏輯放這裡

    return items


@router.patch("/vendors/{service_vendor_id}/orders/{record_id}")
async def update_order(
    service_vendor_id: int,
    record_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """更新 order：根據 service_vendor_id 更新該筆特定訂單。

    對應圖2「更新order」/ api_server #74
    (`PATCH /vendors/{id}/orders/{record_id}`)。
    """
    resp = await db_api.patch(f"/vendors/{service_vendor_id}/orders/{record_id}", json=payload)
    return resp.json()


@router.patch("/vendors/{service_vendor_id}")
async def update_merchant_profile(
    service_vendor_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """設定商家資訊：更新 DB 商家資訊（聯絡方式、商家屬性...）。

    對應圖2「設定商家資訊」。商家屬性走 api_server #14
    (`PATCH /service-vendors/{id}`)，聯絡方式走 #39
    (`PATCH /vendors/{id}/accounts/{account_id}`)，
    兩張表分開呼叫、合併結果回傳。

    payload 預期格式（細節之後再調整）：
    {
        "vendor_profile": {...},    # 商家屬性，可選 -> 轉給 #14
        "account_id": "...",        # 要更新聯絡方式的帳號 id，可選
        "account_contact": {...}    # 聯絡方式，可選 -> 轉給 #39
    }
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
    """登入：根據帳密，回傳 service_vendor_id 給 APP。

    對應圖2「登入」/ api_server #36 (`POST /auth/vendor/login`)。
    """
    resp = await db_api.post("/auth/vendor/login", json=payload)
    return resp.json()

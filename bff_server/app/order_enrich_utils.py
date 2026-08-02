# -*- coding: utf-8 -*-
"""
共用邏輯：把 service_name / vendor_name 併入訂單物件。

訂單本身只有 service_id / service_vendor_id 這兩個外部識別碼，前端要顯示
「服務項目名稱」、「商家名稱」時得自己另外查兩支 API 對照，體驗不好。
這裡統一在訂單物件上補上 service_name / vendor_name 兩個欄位，查不到（服務
項目或商家已被刪除）時為 null，不影響其他欄位。
"""
from app.client import DbApiClient


async def attach_names_to_orders(orders: list[dict], db_api: DbApiClient) -> list[dict]:
    """依訂單裡的 service_id / service_vendor_id 查出對應名稱並附加。

    先收集這批訂單裡所有不重複的 service_id / service_vendor_id，每個
    id 只查一次，避免同一個服務項目或商家因為出現在多筆訂單裡而重複呼叫
    api_server。
    """
    service_ids = {o["service_id"] for o in orders if o.get("service_id") is not None}
    vendor_ids = {o["service_vendor_id"] for o in orders if o.get("service_vendor_id") is not None}

    service_names: dict[int, str | None] = {}
    for service_id in service_ids:
        resp = await db_api.get_optional(f"/services/{service_id}")
        service_names[service_id] = resp.json().get("name") if resp is not None else None

    vendor_names: dict[int, str | None] = {}
    for vendor_id in vendor_ids:
        resp = await db_api.get_optional(f"/service-vendors/{vendor_id}")
        vendor_names[vendor_id] = resp.json().get("name") if resp is not None else None

    for order in orders:
        order["service_name"] = service_names.get(order.get("service_id"))
        order["vendor_name"] = vendor_names.get(order.get("service_vendor_id"))

    return orders

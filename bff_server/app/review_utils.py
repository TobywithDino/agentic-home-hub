# -*- coding: utf-8 -*-
"""
共用邏輯：把訂單評價（mms_order_review）併入訂單（mms_order_record）物件。

一筆訂單至多一筆評價（record_id 1:0..1 對應），只有 order_status='80'
（已完成）的訂單才可能有評價。這裡統一在訂單物件上加一個 "review" 欄位：
有評價就是完整的 review 物件，沒有則是 null。
"""
from app.client import DbApiClient


async def attach_review_to_order(order: dict, db_api: DbApiClient) -> dict:
    """查詢單筆訂單的評價並附加到 order["review"]（給只回傳單筆訂單的端點用）。"""
    resp = await db_api.get_optional(f"/orders/{order['record_id']}/review")
    order["review"] = resp.json() if resp is not None else None
    return order


def attach_reviews_to_orders(orders: list[dict], reviews: list[dict]) -> list[dict]:
    """把一批評價依 record_id 對應併入一批訂單（給回傳訂單清單的端點用）。

    reviews 建議整批先用 /users/{id}/reviews 或 /vendors/{id}/reviews 抓回來，
    避免對每筆訂單各打一次 API。沒有對應評價的訂單，order["review"] 會是 None。
    """
    review_by_record_id = {r["record_id"]: r for r in reviews}
    for order in orders:
        order["review"] = review_by_record_id.get(order["record_id"])
    return orders

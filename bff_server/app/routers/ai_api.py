# -*- coding: utf-8 -*-
"""
AI 端呼叫的中介層 API。

給部署在 AWS Lambda 上的 AI 服務呼叫（例如評價文字分析、情緒分析等批次任務），
不是給前端 APP/商家後台用。這一層一樣不直接碰資料庫，透過 httpx 呼叫
Database/api_server 取得資料，並在中間做分頁迴圈整批抓取、跨資源查詢組裝
等 AI 端需要的邏輯。
"""
from fastapi import APIRouter, Depends

from app.client import DbApiClient
from app.deps import get_db_api_client

router = APIRouter(prefix="/ai-api", tags=["AI 端"])


@router.get("/vendors/{service_vendor_id}/reviews")
async def get_vendor_reviews(
    service_vendor_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得某商家「所有服務項目」底下全部訂單的評價（完整內容）

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID

    **輸出**：評價物件陣列（不分頁，一次回傳全部）
    ```json
    [
      {
        "record_id": 1, "order_no": "...", "service_vendor_id": 1, "service_id": 17,
        "inbr_account_id": "...", "overall_rating": 5,
        "rating_detail": { "service": 5, "attitude": 4 },
        "review_content": "服務很好，準時到府", "media": ["https://.../photo1.jpg"],
        "status": "01", "is_deleted": false, "cre_time": "...", "upd_time": "..."
      }
    ]
    ```
    每筆欄位對應 `mms_order_review` 完整內容（`ReviewOut`），
    非公開評價牆的精簡格式，包含 `inbr_account_id`、`order_no` 等內部欄位。

    **說明**

    給 Lambda 上的 AI 服務批次抓取某商家全部評價用（例如整理評價摘要、
    情緒分析、關鍵字統計）。內部呼叫 api_server 的
    `GET /vendors/{service_vendor_id}/reviews`，該端點本身涵蓋此商家
    名下**所有服務項目**的評價，並自動處理分頁（`limit`/`offset`）
    迴圈抓取到底，一次回傳完整清單，不需要呼叫端自己處理分頁。
    """
    reviews = await db_api.get_all_items(f"/vendors/{service_vendor_id}/reviews")
    return reviews


@router.get("/services/{service_id}/reviews")
async def get_service_reviews(
    service_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得某個服務項目底下全部訂單的評價（完整內容）

    **輸入**
    - `service_id` (path, int): 服務項目 ID

    **輸出**：評價物件陣列（不分頁，一次回傳全部），格式同
    `GET /ai-api/vendors/{service_vendor_id}/reviews`

    **說明**

    給 Lambda 上的 AI 服務批次抓取某個服務項目全部評價用，範圍比
    `GET /ai-api/vendors/{service_vendor_id}/reviews` 更窄（只限定
    單一服務項目，不含同商家的其他服務）。

    api_server 沒有「直接依 service_id 查完整評價」的端點——現成的
    `GET /services/{service_id}/reviews` 是公開評價牆，回傳精簡過的
    `PublicReviewOut`（刻意排除 `inbr_account_id`/`order_no`/
    `service_vendor_id`/`status` 等欄位，避免對外洩漏身分/內部資訊）。
    AI 端需要完整欄位，因此改用以下組合：
    1. `GET /services/{service_id}` 查出該服務所屬的 `service_vendor_id`
    2. `GET /vendors/{service_vendor_id}/reviews?service_id={service_id}`
       （帶 service_id 篩選）並自動分頁抓取到底
    """
    service_resp = await db_api.get(f"/services/{service_id}")
    service_vendor_id = service_resp.json()["service_vendor_id"]

    reviews = await db_api.get_all_items(
        f"/vendors/{service_vendor_id}/reviews", params={"service_id": service_id}
    )
    return reviews

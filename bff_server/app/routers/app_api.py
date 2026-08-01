# -*- coding: utf-8 -*-
"""
圖1（Database/AI指示文件/DB_API_1.jpg）：APP 前端呼叫的中介層 API。

APP 不直接打隊友的 DB Access API（Database/api_server），而是打這一層；
這一層再去呼叫 api_server 拿資料，中間做排序、label filter、資料組裝等
前端需要、但不適合放在純資料存取層的邏輯。
"""
from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.agent_client import ButlerAgentClient, get_agent_client
from app.client import DbApiClient
from app.deps import get_db_api_client
from app.review_utils import attach_reviews_to_orders

router = APIRouter(prefix="/app-api", tags=["APP 端"])


class ButlerChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    inbr_account_id: str = Field(..., min_length=1, max_length=128)
    session_id: str | None = None


@router.post("/butler/chat")
async def butler_chat(
    payload: ButlerChatRequest,
    agent: ButlerAgentClient = Depends(get_agent_client),
):
    """AI 管家對話（SSE 串流）

    **輸入**（request body）
    - `message` (string): 使用者這次說的話
    - `inbr_account_id` (string): 會員 UUID。跨 session 的長期記憶就是靠這個值區分使用者
    - `session_id` (string, 可選): 同一個聊天室請固定傳同一個值以延續對話。
      未提供或長度不足 33 字元時，本層會自動產生一個並回在 `X-Session-Id` 標頭

    **輸出**：`text/event-stream`，每筆事件為一行 `data: {json}`
    ```json
    {"type": "text_delta", "text": "逐字輸出的片段"}
    {"type": "tool_start", "name": "find_service_vendors"}
    {"type": "ui", "component": "vendor_list", "payload": { "vendors": [] }}
    {"type": "draft", "draft_id": "...", "summary": "...", "payload": {}}
    {"type": "done"}
    {"type": "error", "message": "錯誤說明"}
    ```

    **說明**
    - AgentCore Runtime 只接受 SigV4(IAM) 驗證，前端拿不到憑證，
      所以由本層用 EC2 instance role 代為呼叫再轉發 SSE。
    - AI 管家**沒有寫入權限**。`draft` 事件只是草稿，真正送出仍要由 APP
      呼叫既有的 `POST /app-api/feedbacks`。
    - 需要環境變數 `AGENTCORE_RUNTIME_ARN`；未設定時會回一筆 `error` 事件。
    """
    session_id = agent.normalize_session_id(payload.session_id)

    return StreamingResponse(
        agent.stream(
            message=payload.message,
            actor_id=payload.inbr_account_id,
            session_id=session_id,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            # 前面若有 nginx 之類的反向代理，少了這行 SSE 會被緩衝住，
            # 前端要等整輪結束才一次收到全部文字，逐字輸出的效果就沒了。
            "X-Accel-Buffering": "no",
            "X-Session-Id": session_id,
        },
    )


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


@router.get("/labels")
async def list_labels_by_service_type(
    service_type: str | None = None,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得標籤清單（該服務類型專屬標籤 + 通用標籤）

    **輸入**
    - `service_type` (query, string, 可選): 服務類型代碼。
      1=居家清潔 2=家電清洗 3=包裹寄送 6=餐廳訂位 9=美食外送 10=水電修繕 11=商城購物
      - **有帶值**：回傳該類型專屬標籤 + 通用標籤
      - **不帶（省略或空字串）**：只回傳通用標籤

    **輸出**：標籤陣列（依 `sort` 排序）
    ```json
    [
      { "id": 1, "name": "寵物友善" },
      { "id": 2, "name": "24小時營業" }
    ]
    ```

    **說明**

    `label` 表本身有 `service_type` 欄位：`null` 代表通用標籤（適用所有
    服務類型，例如「寵物友善」、「24小時營業」），有值則是該服務類型
    專屬標籤（例如「中餐廳」、「泰式料理」只屬於餐廳訂位類型 `6`）。

    通用標籤（`service_type` 為 `null`）**不論參數為何一定會回傳**；
    有帶 `service_type` 時，額外加上該類型的專屬標籤。使用者選好服務
    類型後，前端呼叫此端點取得可用標籤渲染成篩選選項，勾選後把 label id
    用逗號串起來傳給
    `GET /app-api/service-types/{service_type}/vendors?labels=3,5` 做篩選。

    這裡呼叫 `GET /labels`（不帶篩選，取全部）後在此層過濾，
    標籤資料量小（demo 種子資料僅 8 筆），全撈回來過濾成本可忽略。
    """
    resp = await db_api.get("/labels", params={"limit": 200})
    all_labels = resp.json()["items"]

    matched = [
        label for label in all_labels
        if label["service_type"] is None or label["service_type"] == service_type
    ]

    return [{"id": label["id"], "name": label["name"]} for label in matched]


@router.get("/vendors/{service_vendor_id}/services")
async def list_vendor_services(
    service_vendor_id: int,
    service_type: str | None = None,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得某個廠商提供的服務項目（可依服務類型篩選）

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID（從 `find_vendors_by_service` 回傳的 `id` 取得）
    - `service_type` (query, string, 可選): 服務類型代碼，只回傳該類型的服務。
      1=居家清潔 2=家電清洗 3=包裹寄送 6=餐廳訂位 9=美食外送 10=水電修繕 11=商城購物。
      不傳則回傳該 vendor 名下全部服務項目。

    **輸出**：服務項目陣列
    ```json
    [
      {
        "id": 17,
        "service_vendor_id": 1,
        "type": "10",
        "name": "水電修繕-一般維修",
        "img_url": "https://...",
        "description": "服務項目描述",
        "form_id": 9
      }
    ]
    ```
    `form_id` 是該服務項目對應的諮詢表單 ID，前端可直接拿此值
    呼叫 `GET /app-api/forms/{form_id}/full` 取得表單完整結構供使用者填寫。

    **說明**

    前端在找到廠商後，點進廠商詳情頁時呼叫此 API 取得該廠商的服務項目。
    可透過 `service_type` 參數篩選特定類型（例如只看水電修繕），
    不傳則回傳全部。每個服務項目帶有 `form_id`，前端可據此導向對應的
    諮詢表單填寫頁面。
    """
    params: dict = {"service_vendor_id": service_vendor_id, "limit": 200}
    if service_type is not None:
        params["type"] = service_type
    resp = await db_api.get("/services", params=params)
    return resp.json()["items"]


@router.get("/services/{service_id}/labels")
async def get_service_labels(
    service_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得某個服務項目擁有的標籤

    **輸入**
    - `service_id` (path, int): 服務項目 ID

    **輸出**：該服務項目擁有的標籤陣列（只含實際擁有的，依 `sort` 排序）
    ```json
    [
      { "id": 3, "name": "專業認證" },
      { "id": 5, "name": "到府服務" }
    ]
    ```
    沒有任何標籤時回傳空陣列 `[]`。

    **說明**

    APP 端顯示服務項目詳情時，用來渲染該服務的標籤（例如卡片上的
    「專業認證」、「到府服務」等標記）。

    `service_label` 關聯表只存 `service_id` + `label_id`，沒有標籤名稱，
    因此這裡組合兩支 api_server 端點取得可顯示的內容：
    1. `GET /services/{service_id}/labels` 取得此服務的 label_id 清單
    2. `GET /labels` 取得標籤主檔，對應出名稱並過濾掉未擁有的標籤

    與商家後台同路徑的端點（`GET /merchant-api/services/{id}/labels`）不同：
    那支回傳「全部標籤 + `checked` 狀態」供編輯頁勾選用，這支只回傳
    該服務實際擁有的標籤，適合直接顯示。
    """
    service_labels_resp = await db_api.get(
        f"/services/{service_id}/labels", params={"limit": 200}
    )
    owned_label_ids = {item["label_id"] for item in service_labels_resp.json()["items"]}

    if not owned_label_ids:
        return []

    labels_resp = await db_api.get("/labels", params={"limit": 200})
    all_labels = labels_resp.json()["items"]

    return [
        {"id": label["id"], "name": label["name"]}
        for label in all_labels
        if label["id"] in owned_label_ids
    ]


@router.get("/forms/{form_id}/full")
async def get_form_full(
    form_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得某張表單的完整內容（含題組/題目/選項/圖片/地區關聯）

    **輸入**
    - `form_id` (path, int): 表單 ID

    **輸出**：完整巢狀表單結構
    ```json
    {
      "form": {
        "id": 10, "service_vendor_id": 1, "type": "1", "sub_type": "1",
        "name": "居家清潔諮詢表", "review_status": "0", "is_enable": "1", "...": "..."
      },
      "groups": [
        { "id": 20, "form_id": 10, "name": "基本資料", "sort": 0, "...": "..." }
      ],
      "topics": [
        {
          "id": 30, "form_id": 10, "form_group_id": 20,
          "type": "3", "title": "您需要哪種清潔服務？", "is_required": "1", "sort": 0,
          "media": [ { "id": 50, "img_url": "https://...", "sort": 0 } ],
          "options": [ { "id": 40, "option_name": "居家清潔", "unit_price": 1000, "...": "..." } ],
          "county_district_relations": []
        }
      ]
    }
    ```

    **說明**

    APP 端使用者要填寫諮詢表單前，呼叫此端點取得表單完整結構
    （所有題組、題目、選項、輔助圖片、地區限制），供前端渲染填單頁面。
    直接轉發 api_server 現成的組裝端點，未做額外處理。
    """
    resp = await db_api.get(f"/forms/{form_id}/full")
    return resp.json()


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
      "orders": [
        {
          "record_id": 1, "order_no": "...", "order_status": "12",
          "review": { "overall_rating": 5, "review_content": "..." },
          "...": "..."
        }
      ]
    }
    ```
    - `feedbacks`：狀態為未處理（`status="0"`）的諮詢回饋單
    - `orders`：該會員的全部訂單，每筆訂單附加 `review` 欄位——
      有評價過的訂單是完整評價物件，沒評價過則是 `null`

    **說明**

    取得該會員的未處理諮詢與全部訂單，組裝後一次回傳，
    供前端顯示訂單/諮詢總覽頁面。訂單評價（`mms_order_review`）
    一併查出並附加到對應訂單上，前端不需要再另外呼叫評價 API。
    """
    feedbacks_resp = await db_api.get(f"/users/{inbr_account_id}/feedbacks", params={"limit": 200})
    orders_resp = await db_api.get(f"/users/{inbr_account_id}/orders", params={"limit": 200})
    reviews_resp = await db_api.get(f"/users/{inbr_account_id}/reviews", params={"limit": 200})

    feedbacks = [f for f in feedbacks_resp.json()["items"] if f["status"] == "0"]
    orders = orders_resp.json()["items"]
    reviews = reviews_resp.json()["items"]

    orders = attach_reviews_to_orders(orders, reviews)

    return {"feedbacks": feedbacks, "orders": orders}


@router.post("/orders/{record_id}/review", status_code=201)
async def create_order_review(
    record_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """對已完成的訂單提交評價

    **輸入**
    - `record_id` (path, int): 訂單內部 ID（`mms_order_record.record_id`）
    - body：
    ```json
    {
      "inbr_account_id": "019c0464-2d01-73f0-9f9b-d1392fdb941a",
      "overall_rating": 5,
      "rating_detail": { "service": 5, "attitude": 4 },
      "review_content": "服務很好，準時到府",
      "media": ["https://.../photo1.jpg"]
    }
    ```
    `overall_rating` 為 1~5 的整數；`rating_detail`、`review_content`、`media` 皆為可選。

    **輸出**：建立後的完整評價物件
    ```json
    {
      "record_id": 1, "order_no": "...", "service_vendor_id": 1, "service_id": 17,
      "inbr_account_id": "...", "overall_rating": 5, "review_content": "...",
      "status": "01", "cre_time": "..."
    }
    ```

    **說明**

    使用者對一筆已完成訂單提交評價（一筆訂單至多一筆評價）。
    api_server 會驗證：訂單狀態須為 `80`（已完成）、`inbr_account_id`
    須與訂單的下單會員一致、且該訂單尚未被評價過（否則回 409）。
    成功後會自動把對應訂單的 `comment_status` 改成 `02`（已評價）。
    """
    resp = await db_api.post(f"/orders/{record_id}/review", json=payload)
    return resp.json()


@router.patch("/users/{inbr_account_id}/orders/{record_id}/review")
async def update_order_review(
    inbr_account_id: str,
    record_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """修改自己對某筆訂單提交過的評價

    **輸入**
    - `inbr_account_id` (path, uuid): 會員 UUID（須為原評價者本人）
    - `record_id` (path, int): 訂單內部 ID
    - body（只需傳要修改的欄位）：
    ```json
    {
      "overall_rating": 4,
      "rating_detail": { "service": 4, "attitude": 5 },
      "review_content": "補充：後續維修也很快",
      "media": ["https://.../photo2.jpg"]
    }
    ```
    `overall_rating` 若有傳必須是 1~5 的整數。

    **輸出**：更新後的完整評價物件

    **說明**

    使用者修改自己先前提交的評價。api_server 會比對 `inbr_account_id`
    是否與該筆評價的原評價者一致，不一致回 403；訂單尚未被評價過則回 404。
    """
    resp = await db_api.patch(f"/users/{inbr_account_id}/orders/{record_id}/review", json=payload)
    return resp.json()


@router.get("/services/{service_id}/reviews")
async def get_service_reviews(
    service_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得某個服務項目底下全部訂單的評價（完整內容）

    **輸入**
    - `service_id` (path, int): 服務項目 ID

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
    每筆欄位對應 `mms_order_review` 完整內容（`ReviewOut`），**不是**
    公開評價牆的精簡格式，包含 `inbr_account_id`、`order_no` 等內部欄位。

    **說明**

    給 APP 端查看某個服務項目全部評價用（範圍限定單一服務項目，
    不含同商家的其他服務）。

    api_server 沒有「直接依 service_id 查完整評價」的端點——現成的
    `GET /services/{service_id}/reviews` 是公開評價牆，回傳精簡過的
    `PublicReviewOut`（刻意排除 `inbr_account_id`/`order_no`/
    `service_vendor_id`/`status` 等欄位，避免對外洩漏身分/內部資訊）。
    這裡改用以下組合取得完整欄位：
    1. `GET /services/{service_id}` 查出該服務所屬的 `service_vendor_id`
    2. `GET /vendors/{service_vendor_id}/reviews?service_id={service_id}`
       （帶 service_id 篩選）並自動分頁抓取到底

    ⚠️ 安全提醒：此端點回傳完整評價內容（含 `inbr_account_id`、
    `order_no`），目前平台無身分驗證機制，任何知道 `service_id` 的人
    都能呼叫並取得評價者身分關聯資訊。若前端只是要做「服務評價瀏覽」
    這種公開頁面，建議改呼叫 api_server 現成的公開評價牆端點
    `GET /services/{service_id}/reviews`（回傳去識別化的 `PublicReviewOut`），
    而不是這支。
    """
    service_resp = await db_api.get(f"/services/{service_id}")
    service_vendor_id = service_resp.json()["service_vendor_id"]

    reviews = await db_api.get_all_items(
        f"/vendors/{service_vendor_id}/reviews", params={"service_id": service_id}
    )
    return reviews


@router.get("/services/{service_id}/review-summary")
async def get_service_review_summary(
    service_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得服務項目的評價 AI 摘要

    **輸入**
    - `service_id` (path, int): 服務項目 ID

    **輸出**（`ServiceReviewSummaryOut`）
    ```json
    {
      "service_id": 17,
      "service_vendor_id": 1,
      "summary_content": "整體評價正向，顧客普遍稱讚服務態度與準時性...",
      "summary_highlights": { "pros": ["態度好", "準時"], "cons": ["價格偏高"] },
      "sentiment_stats": { "positive": 12, "neutral": 3, "negative": 2 },
      "source_review_count": 17,
      "source_avg_rating": 4.5,
      "latest_review_cre_time": "2026-08-01T09:00:00Z",
      "ai_model": "claude-3-5-sonnet",
      "generate_status": "00=待生成 01=生成中 02=已完成 03=失敗",
      "generate_time": "...",
      "error_message": null,
      "is_stale": false
    }
    ```
    `is_stale` 是計算欄位：即時比對 `mms_order_review` 目前的最新聚合值，
    `true` 代表有新評價尚未納入這份摘要（可據此判斷是否要觸發重新生成）。

    **說明**

    給 APP 端顯示服務項目詳情頁的「評價摘要」區塊用（使用者與供應商
    共用同一份內容）。直接轉發 api_server 現成端點，未做額外處理。
    尚未生成過摘要時回 404。
    """
    resp = await db_api.get(f"/services/{service_id}/review-summary")
    return resp.json()


@router.get("/users/{inbr_account_id}")
async def get_member_profile(
    inbr_account_id: str,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得會員個人資訊

    **輸入**
    - `inbr_account_id` (path, uuid): 會員 UUID，登入時取得

    **輸出**
    ```json
    {
      "id": "019c0464-2d01-73f0-9f9b-d1392fdb941a",
      "account": "user01@example.com",
      "contact_name": "王小明",
      "contact_mobile": "0912345678",
      "contact_email": "user01@example.com",
      "is_2fa_enabled": "0",
      "last_login_time": "...",
      "is_enable": "1",
      "is_deleted": "0",
      "upd_time": "...",
      "cre_time": "..."
    }
    ```

    **說明**

    取得會員的帳號與聯絡資訊，供 APP 端「個人資料」頁面顯示。
    個資欄位（姓名、手機、Email）已由 api_server 解密後回傳明文。
    """
    resp = await db_api.get(f"/users/{inbr_account_id}")
    return resp.json()


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

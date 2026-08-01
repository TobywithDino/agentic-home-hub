# -*- coding: utf-8 -*-
"""
圖2（Database/AI指示文件/DB_API_2.jpg）：商家後台呼叫的中介層 API。

商家後台不直接打隊友的 DB Access API（Database/api_server），而是打這一層；
這一層再去呼叫 api_server 拿資料，中間做排序、篩選、資料組裝等
商家後台需要的邏輯。
"""
from fastapi import APIRouter, Depends, HTTPException

from app.client import DbApiClient
from app.deps import get_db_api_client
from app.review_utils import attach_review_to_order, attach_reviews_to_orders

router = APIRouter(prefix="/merchant-api", tags=["商家後台"])


@router.post("/services", status_code=201)
async def create_service(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """商家新增一個服務項目

    **輸入**（JSON body）
    ```json
    {
      "service_vendor_id": 1,
      "type": "10",
      "name": "水電修繕-管線更換",
      "img_url": "https://...(可選)",
      "description": "服務項目描述(可選)",
      "form_id": null
    }
    ```
    - `service_vendor_id`（必填）：所屬服務商 ID
    - `type`（必填）：服務類型代碼。
      1=居家清潔 2=家電清洗 3=包裹寄送 6=餐廳訂位 9=美食外送 10=水電修繕 11=商城購物
    - `name`（必填）：服務項目名稱（最長 100 字元）
    - `img_url`（可選）：服務項目圖片 URL
    - `description`（可選）：服務項目說明
    - `form_id`（可選）：對應的諮詢表單 ID，未設定時可省略或傳 null
    - `id`（可選）：服務項目 ID。**不傳則自動分配**（取全平台目前最大 id + 1）；
      若自行指定且已存在則回 409

    **輸出**：建立後的完整服務項目物件（含實際使用的 `id`）

    **說明**

    商家後台新增一個服務項目。

    `cms_homepage_service.id` 在資料庫是 `int4`（非 `serial4`），沒有自增序列，
    api_server 的 `POST /services` 要求呼叫端自行指定 `id`。這裡在 BFF 層補上
    自動分配：先查詢全平台現有服務項目取最大 id，加 1 作為新 id，前端不需要
    自己想編號也不會撞號。

    ⚠️ 自動分配是「查詢最大值 + 1」，非資料庫層級的序列，高併發同時新增
    有極小機率算出同一個 id 而其中一筆收到 409。demo 階段可接受，
    正式環境應改為資料庫層自增（把欄位改成 `serial4`）。
    """
    body = dict(payload)

    if "id" not in body:
        existing = await db_api.get_all_items("/services")
        body["id"] = max((s["id"] for s in existing), default=0) + 1

    resp = await db_api.post("/services", json=body)
    return resp.json()


@router.delete("/services/{service_id}", status_code=204)
async def delete_service(
    service_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """商家刪除一個服務項目

    **輸入**
    - `service_id` (path, int): 服務項目 ID

    **輸出**：無內容（HTTP 204）

    **說明**

    刪除指定的服務項目（實體刪除，此表無 is_deleted 欄位）。
    刪除後該 service 底下的 label 關聯（`service_label`）不會自動清除
    （資料庫無實體 FK），但已不影響查詢（查不到 service 就不會再被列出）。
    """
    await db_api.delete(f"/services/{service_id}")


@router.get("/services")
async def list_all_services(
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得全平台所有服務項目清單

    **輸入**：無

    **輸出**：服務項目陣列（不分頁，一次回傳全部）
    ```json
    [
      {
        "id": 17,
        "service_vendor_id": 1,
        "type": "10",
        "name": "水電修繕-一般維修",
        "img_url": "https://...",
        "description": "...",
        "form_id": 9
      }
    ]
    ```

    **說明**

    供 AI summary Lambda 等內部服務批次取得全部服務項目 id 與名稱，
    避免直接呼叫 api_server port 8000。
    自動處理分頁，一次回傳完整清單。
    """
    items = await db_api.get_all_items("/services")
    return items


@router.get("/vendors")
async def list_all_vendors(
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得全平台所有服務商清單

    **輸入**：無

    **輸出**：服務商陣列（不分頁，一次回傳全部）
    ```json
    [
      {
        "id": 1,
        "name": "服務商名稱",
        "description": "服務商描述"
      }
    ]
    ```

    **說明**

    供 AI summary Lambda 等內部服務批次取得全部商家 id 與名稱，
    避免直接呼叫 api_server port 8000。
    自動處理分頁，一次回傳完整清單。
    """
    items = await db_api.get_all_items("/service-vendors")
    return items


@router.get("/vendors/{service_vendor_id}/services")
async def list_vendor_services(
    service_vendor_id: int,
    service_type: str | None = None,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得該商家提供的服務項目清單（可依服務類型篩選）

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID
    - `service_type` (query, string, 可選): 服務類型代碼。
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
    `form_id` 是該服務項目對應的諮詢表單 ID。

    **說明**

    商家後台用來查看/管理自己名下的服務項目清單。
    可透過 `service_type` 參數篩選特定類型，不傳則回傳全部。
    """
    params: dict = {"service_vendor_id": service_vendor_id, "limit": 200}
    if service_type is not None:
        params["type"] = service_type
    resp = await db_api.get("/services", params=params)
    return resp.json()["items"]


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
    { "is_read": "0=未讀 1=已讀", "status": "0=未處理 1=已完成 2=拒絕" }
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

    **輸出**：此服務類型的可選標籤清單（該類型專屬 + 通用標籤），
    並標示此 service 目前是否已勾選
    ```json
    [
      { "id": 1, "name": "寵物友善", "checked": true },
      { "id": 2, "name": "24小時營業", "checked": false }
    ]
    ```

    **說明**

    給商家後台「編輯服務項目」頁面用。流程：
    1. 先查此 `service_id` 對應的 `cms_homepage_service.type`（服務類型）
    2. 取得可選標籤範圍：`label.service_type` 等於該類型的專屬標籤，
       加上 `label.service_type` 為 `null` 的通用標籤（不會列出其他
       服務類型專屬、跟此服務無關的標籤）
    3. 對照此 service 現有的 `service_label` 關聯，標示 `checked`

    前端可以直接渲染成已勾選/未勾選的 checkbox，不用自己再做比對，
    也不會出現跟此服務類型無關的標籤選項。
    """
    service_resp = await db_api.get(f"/services/{service_id}")
    service_type = service_resp.json()["type"]

    labels_resp = await db_api.get("/labels", params={"limit": 200})
    all_labels = labels_resp.json()["items"]
    applicable_labels = [
        label for label in all_labels
        if label["service_type"] == service_type or label["service_type"] is None
    ]

    service_labels_resp = await db_api.get(
        f"/services/{service_id}/labels", params={"limit": 200}
    )
    checked_label_ids = {item["label_id"] for item in service_labels_resp.json()["items"]}

    return [
        {"id": label["id"], "name": label["name"], "checked": label["id"] in checked_label_ids}
        for label in applicable_labels
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


@router.get("/vendors/{service_vendor_id}/forms")
async def list_vendor_forms(
    service_vendor_id: int,
    type: str | None = None,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得該商家的所有表單清單（不含巢狀題組/題目內容）

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID
    - `type` (query, string, 可選): 篩選表單類型代碼。
      1=C端(無需評估) 2=C端(需評估) 3=B端 4=轉訂單流程 5=客服。不傳則回傳全部類型。

    **輸出**：表單物件陣列（僅表單主檔欄位，不含題組/題目/選項）
    ```json
    [
      {
        "id": 10, "service_vendor_id": 1, "type": "1", "sub_type": "1",
        "name": "居家清潔諮詢表", "review_status": "0=未審核 1=已審核",
        "is_enable": "0=禁用 1=啟用", "cre_time": "...", "...": "..."
      }
    ]
    ```

    **說明**

    列出該商家名下建立過的所有表單（不論審核狀態、啟用狀態），
    用於商家後台「表單管理」頁面顯示表單清單。這裡只回傳每張表單的
    主檔資訊，不含底下的題組/題目/選項；若要看某張表單的完整內容，
    請改用建立表單時回傳的巢狀結構，或請隊友的 api_server 開放
    `GET /forms/{form_id}/full`（目前 BFF 尚未包裝此端點）。
    """
    resp = await db_api.get(
        "/forms",
        params={"service_vendor_id": service_vendor_id, "type": type, "limit": 200},
    )
    return resp.json()["items"]


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
    `topics` 是平面陣列（非巢狀在 groups 底下），每個 topic 帶自己的
    `form_group_id` 可對應回所屬題組；每個 topic 已內嵌好自己的
    `media`、`options`、`county_district_relations`。

    **說明**

    商家後台「表單管理」頁面中，商家從 `GET /vendors/{id}/forms`
    清單點擊某張表單後，呼叫此端點取得該表單的完整內容用於編輯頁面
    渲染（顯示所有題組、題目、選項、輔助圖片、地區限制）。
    直接轉發 api_server 現成的組裝端點，未做額外處理。
    """
    resp = await db_api.get(f"/forms/{form_id}/full")
    return resp.json()


@router.patch("/forms/{form_id}")
async def update_form(
    form_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """建立新版本表單取代舊表單（舊表單保留供歷史記錄使用）

    **輸入**
    - `form_id` (path, int): 目前綁定在該服務上的表單 ID。僅用於驗證
      「使用者正在編輯的是目前生效的版本」，此表單本身**不會被異動**。
    - body：跟 `POST /forms` 相同的巢狀結構，外加必填的 `service_id`
    ```json
    {
      "service_id": 17,
      "form": {
        "name": "表單名稱(可依需要修改)",
        "intro_content": "服務介紹(html)",
        "notice_content": "注意事項(html)",
        "terms_content": "服務條款(html)",
        "is_enable": "0=禁用 1=啟用"
      },
      "groups": [
        {
          "name": "基本資料",
          "sort": 0,
          "topics": [
            {
              "type": "3", "title": "您需要哪種清潔服務？",
              "is_required": "1", "sort": 0,
              "options": [ { "option_name": "居家清潔", "unit_price": 1000, "sort": 0 } ]
            }
          ]
        }
      ]
    }
    ```
    前端通常先呼叫 `GET /forms/{form_id}/full` 載入舊表單內容（含各層
    `id`）供使用者編輯，改完後把整包（結構跟畫面上一致，格式跟表單一樣，
    內容可能已修改）送回這支 API 即可——**不需要移除舊的 `id` 欄位**，
    這裡會忽略 payload 中任何層級的 `id`（一律視為新增到新表單）。

    **輸出**：新建立的完整巢狀表單物件（**新的 `form_id`**），格式同 `POST /forms`

    **說明**

    ⚠️ 重要行為：此端點**不是**就地修改 `form_id` 對應的表單，而是用
    payload 內容**建立一張全新的表單**（產生新的 `form_id`），並把
    `service.form_id` 改指向這張新表單。路徑上的 `form_id`（舊表單）
    **不會被刪除、也不會被修改**，繼續完整保留在資料庫中。

    這是刻意的設計：已完成的訂單（`mms_order_record`）與回饋單
    （`pms_form_feedback`）是透過填寫當下的 `form_id` 對應到當時的表單
    結構，若舊表單被覆蓋或刪除，使用者事後查看歷史訂單/回饋單時看到的
    表單內容會失真、對不上原本填的東西。改為「每次編輯都產生新版本」，
    歷史記錄永遠對應到當時填寫的那個版本；新訂單/新填單則透過
    `service.form_id` 使用最新版本。

    驗證規則：路徑上的 `form_id` 必須是該 `service_id` **目前生效**的
    `form_id`，否則回 409（避免編輯到已經被別的請求取代掉的過期版本）。

    ⚠️ api_server 沒有跨資源的交易機制，若中途某一層建立失敗，前面已成功
    建立的表單/題組不會自動回滾，需要另外刪除清理（與 `POST /forms` 相同限制）。
    """
    service_id = payload["service_id"]

    # 確認路徑上的 form_id 是此 service 目前生效的版本，避免編輯到過期版本
    service_resp = await db_api.get(f"/services/{service_id}")
    current_form_id = service_resp.json().get("form_id")
    if current_form_id != form_id:
        raise HTTPException(
            status_code=409,
            detail=(
                f"form_id={form_id} 已不是 service_id={service_id} 目前生效的表單"
                f"（目前為 form_id={current_form_id}），請重新載入最新表單內容"
            ),
        )

    def _strip_id(d: dict) -> dict:
        return {k: v for k, v in d.items() if k != "id"}

    # 建立新版本表單（流程同 create_form_with_content，payload 中任何 id 皆忽略）
    form_resp = await db_api.post("/forms", json=_strip_id(payload.get("form", {})))
    new_form = form_resp.json()
    new_form_id = new_form["id"]

    groups_out = []
    for group_payload in payload.get("groups", []):
        topics_payload = group_payload.get("topics", [])
        group_body = _strip_id({k: v for k, v in group_payload.items() if k != "topics"})

        group_resp = await db_api.post(f"/forms/{new_form_id}/groups", json=group_body)
        group = group_resp.json()
        group_id = group["id"]

        topics_out = []
        for topic_payload in topics_payload:
            options_payload = topic_payload.get("options", [])
            topic_body = _strip_id({k: v for k, v in topic_payload.items() if k != "options"})
            topic_body["form_group_id"] = group_id

            topic_resp = await db_api.post(f"/forms/{new_form_id}/topics", json=topic_body)
            topic = topic_resp.json()
            topic_id = topic["id"]

            options_out = []
            for option_payload in options_payload:
                option_body = _strip_id(option_payload)
                option_resp = await db_api.post(f"/form-topics/{topic_id}/options", json=option_body)
                options_out.append(option_resp.json())

            topic["options"] = options_out
            topics_out.append(topic)

        group["topics"] = topics_out
        groups_out.append(group)

    new_form["groups"] = groups_out

    # 把 service 的 form_id 改指向新表單；舊表單（路徑上的 form_id）保留不動
    await db_api.patch(f"/services/{service_id}", json={"form_id": new_form_id})

    return new_form


@router.post("/forms", status_code=201)
async def create_form_with_content(
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """一次性建立表單及其巢狀內容（題組 → 題目 → 選項）

    **輸入**（JSON body）
    ```json
    {
      "form": {
        "service_vendor_id": 1,
        "type": "1=C端(無需評估) 2=C端(需評估) 3=B端 4=轉訂單流程 5=客服",
        "sub_type": "1=一般表單 2=估價表單",
        "name": "居家清潔諮詢表",
        "intro_content": "服務介紹(html,可選)",
        "notice_content": "注意事項(html,可選)",
        "terms_content": "服務條款(html,可選)",
        "is_enable": "1"
      },
      "groups": [
        {
          "name": "基本資料",
          "sort": 0,
          "topics": [
            {
              "type": "3=單選題 4=複選題 1=簡答題 2=詳答題 5=地區選單 6=照片 7=備註 8=聯絡資料 9=日期 10=聯絡資料(不含地址)",
              "title": "您需要哪種清潔服務？",
              "remark": "題目說明(可選)",
              "is_required": "1=必填 0=非必填",
              "sort": 0,
              "options": [
                { "option_name": "居家清潔", "unit_price": 1000, "sort": 0 },
                { "option_name": "家電清洗", "unit_price": 1500, "sort": 1 }
              ]
            }
          ]
        }
      ],
      "service_id": 17
    }
    ```
    `groups`、`groups[].topics`、`topics[].options` 皆為陣列，可依需要放多個。
    題目若非單選/複選題（例如簡答、備註類型）可省略 `options`。
    `service_id`（必填）：此表單要綁定到哪個服務項目，建立成功後會自動
    把該 service 的 `form_id` 欄位更新為此表單的 id。

    ⚠️ 一個 service 只能對應一張表單：若該 `service_id` 現有的
    `form_id` 已不是 `null`（代表已經有表單），會直接回 409，
    不會建立新表單。若要換表單，請先用 `PATCH /forms/{form_id}`
    更新既有表單內容，而不是呼叫這支重新建立。

    **輸出**：建立後的完整巢狀表單物件
    ```json
    {
      "id": 10, "service_vendor_id": 1, "name": "居家清潔諮詢表", "review_status": "0", "...": "...",
      "groups": [
        {
          "id": 20, "name": "基本資料", "...": "...",
          "topics": [
            {
              "id": 30, "title": "您需要哪種清潔服務？", "...": "...",
              "options": [ { "id": 40, "option_name": "居家清潔", "...": "..." } ]
            }
          ]
        }
      ]
    }
    ```

    **說明**

    給商家後台「建立新表單」頁面用，一次送出完整表單結構（題組、題目、選項），
    不需要前端自己依序呼叫 4 層 API。內部依序呼叫 api_server 的
    `POST /forms` → `POST /forms/{id}/groups` → `POST /forms/{id}/topics`
    （自動帶入所屬 `form_group_id`）→ `POST /form-topics/{id}/options`，
    再把各層回傳結果組裝成巢狀結構回傳。新建表單的 `review_status` 一律為
    `0`（未審核），需另外呼叫審核端點才能上線。

    ⚠️ api_server 沒有跨資源的交易機制，若中途某一層建立失敗（例如某個
    題目建立失敗），前面已成功建立的表單/題組不會自動回滾，需要另外
    刪除清理。這是巢狀組裝 API 目前的已知限制。
    """
    service_id = payload["service_id"]

    # 檢查此 service 是否已經有表單，不允許一個 service 對應多張表單
    service_resp = await db_api.get(f"/services/{service_id}")
    if service_resp.json().get("form_id") is not None:
        raise HTTPException(
            status_code=409,
            detail=f"service_id={service_id} 已經有對應的表單，一個服務項目不能建立多張表單",
        )

    form_resp = await db_api.post("/forms", json=payload.get("form", {}))
    form = form_resp.json()
    form_id = form["id"]

    groups_out = []
    for group_payload in payload.get("groups", []):
        topics_payload = group_payload.get("topics", [])
        group_body = {k: v for k, v in group_payload.items() if k != "topics"}

        group_resp = await db_api.post(f"/forms/{form_id}/groups", json=group_body)
        group = group_resp.json()
        group_id = group["id"]

        topics_out = []
        for topic_payload in topics_payload:
            options_payload = topic_payload.get("options", [])
            topic_body = {k: v for k, v in topic_payload.items() if k != "options"}
            topic_body["form_group_id"] = group_id

            topic_resp = await db_api.post(f"/forms/{form_id}/topics", json=topic_body)
            topic = topic_resp.json()
            topic_id = topic["id"]

            options_out = []
            for option_payload in options_payload:
                option_resp = await db_api.post(f"/form-topics/{topic_id}/options", json=option_payload)
                options_out.append(option_resp.json())

            topic["options"] = options_out
            topics_out.append(topic)

        group["topics"] = topics_out
        groups_out.append(group)

    form["groups"] = groups_out

    # 把此表單的 form_id 寫回對應的 service
    await db_api.patch(f"/services/{service_id}", json={"form_id": form_id})

    return form


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

    **輸出**：建立後的完整訂單物件（含系統產生的 `record_id`），
    附加 `review: null`（新建訂單不可能已有評價）

    **說明**

    商家後台建立一筆新訂單。個資欄位傳入明文即可，系統會自動用
    AES-256-GCM 加密存儲。
    """
    resp = await db_api.post("/orders", json=payload)
    order = resp.json()
    order["review"] = None
    return order


@router.get("/vendors/{service_vendor_id}/reviews")
async def get_vendor_reviews(
    service_vendor_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得該商家「所有服務項目」底下全部訂單的評價（完整內容）

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

    給商家後台批次查看自己名下全部評價用（例如彙整評分、篩選負評、
    統計關鍵字）。內部呼叫 api_server 的
    `GET /vendors/{service_vendor_id}/reviews`，該端點本身涵蓋此商家
    名下**所有服務項目**的評價，並自動處理分頁（`limit`/`offset`）
    迴圈抓取到底，一次回傳完整清單，不需要呼叫端自己處理分頁。
    """
    reviews = await db_api.get_all_items(f"/vendors/{service_vendor_id}/reviews")
    return reviews


@router.put("/services/{service_id}/review-summary")
async def upsert_service_review_summary(
    service_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """寫回服務項目的評價 AI 摘要（完整覆寫）

    **輸入**
    - `service_id` (path, int): 服務項目 ID
    - body（`ServiceReviewSummaryUpsert`）：
    ```json
    {
      "service_vendor_id": 1,
      "summary_content": "整體評價正向，顧客普遍稱讚服務態度與準時性...",
      "summary_highlights": { "pros": ["態度好", "準時"], "cons": ["價格偏高"] },
      "sentiment_stats": { "positive": 12, "neutral": 3, "negative": 2 },
      "source_review_count": 17,
      "source_avg_rating": 4.5,
      "latest_review_cre_time": "2026-08-01T09:00:00Z",
      "ai_model": "claude-3-5-sonnet",
      "generate_status": "00=待生成 01=生成中 02=已完成 03=失敗",
      "error_message": null
    }
    ```
    `source_review_count`、`source_avg_rating`、`latest_review_cre_time`
    應為呼叫端（AI 生成流程）當下查詢到的最新評價聚合值，與生成結果
    一起送出；`generate_time` 由 api_server 端自動填入當前時間。

    **輸出**：寫入後的完整摘要物件（`ServiceReviewSummaryOut`，含計算欄位
    `is_stale`）。該 `service_id` 尚無摘要記錄時回 201（新建），已有記錄
    時回 200（整包覆蓋）。

    **說明**

    給上層 AI 摘要生成流程（例如 Lambda）呼叫 Bedrock 等模型產生摘要後，
    把結果寫回 `mms_review_summary_service`。此端點**不呼叫 LLM**，
    純粹轉發到 api_server 對應端點做資料存取，覆寫式快取設計（同一
    `service_id` 只保留最新 1 筆，不留歷史版本）。
    """
    resp = await db_api.put(f"/services/{service_id}/review-summary", json=payload)
    return resp.json()


@router.get("/vendors/{service_vendor_id}/review-summary")
async def get_vendor_review_summary(
    service_vendor_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得商家的整合評價 AI 摘要

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID

    **輸出**（`VendorReviewSummaryOut`）
    ```json
    {
      "service_vendor_id": 1,
      "summary_content": "整體來看，該商家名下服務普遍獲得好評...",
      "summary_highlights": { "pros": ["服務多樣", "口碑穩定"], "cons": [] },
      "sentiment_stats": { "positive": 30, "neutral": 5, "negative": 3 },
      "service_breakdown": [
        { "service_id": 17, "review_count": 10, "avg_rating": 4.5 },
        { "service_id": 18, "review_count": 8, "avg_rating": 4.2 }
      ],
      "source_review_count": 38,
      "source_avg_rating": 4.4,
      "latest_review_cre_time": "2026-08-01T09:00:00Z",
      "ai_model": "claude-3-5-sonnet",
      "generate_status": "00=待生成 01=生成中 02=已完成 03=失敗",
      "generate_time": "...",
      "error_message": null,
      "is_stale": false
    }
    ```
    `service_breakdown` 是橫跨該商家名下所有服務項目的評價數/平均分快取
    陣列；`is_stale` 是計算欄位，即時比對 `mms_order_review` 目前的最新
    聚合值，`true` 代表有新評價尚未納入這份摘要。

    **說明**

    給商家後台顯示「整合評價摘要」頁面用（僅供商家後台使用，橫跨其
    名下所有服務彙整）。直接轉發 api_server 現成端點，未做額外處理。
    尚未生成過摘要時回 404。
    """
    resp = await db_api.get(f"/vendors/{service_vendor_id}/review-summary")
    return resp.json()


@router.put("/vendors/{service_vendor_id}/review-summary")
async def upsert_vendor_review_summary(
    service_vendor_id: int,
    payload: dict,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """寫回商家的整合評價 AI 摘要（完整覆寫）

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID
    - body（`VendorReviewSummaryUpsert`）：
    ```json
    {
      "summary_content": "整體來看，該商家名下服務普遍獲得好評...",
      "summary_highlights": { "pros": ["服務多樣", "口碑穩定"], "cons": [] },
      "sentiment_stats": { "positive": 30, "neutral": 5, "negative": 3 },
      "service_breakdown": [
        { "service_id": 17, "review_count": 10, "avg_rating": 4.5 },
        { "service_id": 18, "review_count": 8, "avg_rating": 4.2 }
      ],
      "source_review_count": 38,
      "source_avg_rating": 4.4,
      "latest_review_cre_time": "2026-08-01T09:00:00Z",
      "ai_model": "claude-3-5-sonnet",
      "generate_status": "00=待生成 01=生成中 02=已完成 03=失敗",
      "error_message": null
    }
    ```
    `service_breakdown` 是橫跨該商家名下所有服務項目的評價數/平均分快取
    陣列；其餘欄位語意同服務項目版本，`generate_time` 由 api_server 端
    自動填入。

    **輸出**：寫入後的完整摘要物件（`VendorReviewSummaryOut`，含計算欄位
    `is_stale`）。該 `service_vendor_id` 尚無摘要記錄時回 201，已有記錄
    時回 200（整包覆蓋）。

    **說明**

    給上層 AI 摘要生成流程呼叫 Bedrock 等模型彙整該商家名下所有服務的
    評價後，把結果寫回 `mms_review_summary_vendor`（僅供商家後台使用，
    橫跨其名下所有服務彙整）。此端點**不呼叫 LLM**，純粹轉發到 api_server
    對應端點，覆寫式快取設計（同一 `service_vendor_id` 只保留最新 1 筆）。
    """
    resp = await db_api.put(f"/vendors/{service_vendor_id}/review-summary", json=payload)
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
    `final_amount`、`order_items` 等欄位，並附加 `review` 欄位——
    有評價過的訂單是完整評價物件，沒評價過則是 `null`

    **說明**

    取得屬於該服務商的所有訂單，用於商家後台的訂單管理頁面。
    訂單評價（`mms_order_review`）一併查出並附加到對應訂單上，
    前端不需要再另外呼叫評價 API。
    """
    orders_resp = await db_api.get(
        f"/vendors/{service_vendor_id}/orders",
        params={"order_status": order_status} if order_status is not None else None,
    )
    orders = orders_resp.json()["items"]

    reviews = await db_api.get_all_items(f"/vendors/{service_vendor_id}/reviews")

    return attach_reviews_to_orders(orders, reviews)


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

    **輸出**：更新後的完整訂單物件，附加 `review` 欄位——
    有評價過則是完整評價物件，沒評價過則是 `null`

    **說明**

    常見場景：確認訂金（`order_status` 11→12 + `deposit_time`）、
    報價（改 13 + `quote_no`）、完成（改 80 + `complete_time`）、
    取消（改 90 + `cancel_time` + `cancel_reason`）。訂單完成後可能已有評價
    （`mms_order_review`），這裡會一併查出並附加到回傳的訂單物件上。
    """
    resp = await db_api.patch(f"/vendors/{service_vendor_id}/orders/{record_id}", json=payload)
    order = resp.json()
    return await attach_review_to_order(order, db_api)


@router.get("/vendors/{service_vendor_id}")
async def get_merchant_profile(
    service_vendor_id: int,
    db_api: DbApiClient = Depends(get_db_api_client),
):
    """取得商家資訊（商家屬性 + 管理帳號清單）

    **輸入**
    - `service_vendor_id` (path, int): 服務商 ID，登入時取得

    **輸出**
    ```json
    {
      "vendor_profile": {
        "id": 1,
        "name": "服務商名稱",
        "description": "服務商描述"
      },
      "accounts": [
        {
          "id": "019fb652-df72-7992-989e-f456194edf8c",
          "service_vendor_id": 1,
          "account": "vendor01@example.com",
          "contact_name": "王小明",
          "contact_mobile": "0912345678",
          "contact_email": "vendor01@example.com",
          "is_2fa_enabled": "0",
          "last_login_time": "...",
          "is_enable": "1",
          "cre_time": "...", "upd_time": "..."
        }
      ]
    }
    ```
    - `vendor_profile`：商家基本屬性
    - `accounts`：該商家底下的管理帳號清單（不含密碼）。帳號的 `id` 即為
      呼叫 `PATCH /vendors/{id}` 更新聯絡方式時要帶的 `account_id`

    **說明**

    商家後台「設定」頁面載入時呼叫，取得目前的商家屬性與管理帳號資訊
    供畫面顯示，使用者修改後再呼叫 `PATCH /vendors/{service_vendor_id}` 儲存。

    對應 `update_merchant_profile` 的讀取版本，組合兩支 api_server 端點：
    `GET /service-vendors/{id}`（商家屬性）+ `GET /vendors/{id}/accounts`（管理帳號）。
    個資欄位（聯絡人姓名/手機/Email）已由 api_server 解密後回傳明文。

    ⚠️ 安全提醒：回傳內容包含管理帳號的個資明文，目前平台無身分驗證機制，
    任何知道 `service_vendor_id` 的人都能呼叫並取得這些資訊。
    """
    vendor_resp = await db_api.get(f"/service-vendors/{service_vendor_id}")
    accounts = await db_api.get_all_items(f"/vendors/{service_vendor_id}/accounts")

    return {"vendor_profile": vendor_resp.json(), "accounts": accounts}


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

# bff_server API 文件

本文件整理 `app_api.py`（APP 端）與 `merchant_api.py`（商家後台）目前提供的所有端點。
每支 API 皆為 BFF 層，實際資料存取透過 `Database/api_server` 完成（見 `README.md` 架構說明）。

> Swagger UI 互動文件：`http://<host>:8100/docs`（含完整範例，內容與本文件同步維護）

## 目錄

- [APP 端（app_api.py，prefix: `/app-api`）](#app-端-app_apipy-prefix-app-api)
  - [尋找特定服務的廠商](#get-app-apiservice-typesservice_typevendors)
  - [建立諮詢回饋單](#post-app-apifeedbacks)
  - [查看會員的訂單總覽](#get-app-apiusersinbr_account_idorders-overview)
  - [對已完成訂單提交評價](#post-app-apiordersrecord_idreview)
  - [修改自己提交過的評價](#patch-app-apiusersinbr_account_idordersrecord_idreview)
  - [設定會員個人資訊](#patch-app-apiusersinbr_account_id)
  - [APP 會員登入](#post-app-apiauthlogin)
- [商家後台（merchant_api.py，prefix: `/merchant-api`）](#商家後台-merchant_apipy-prefix-merchant-api)
  - [查看該商家收到的諮詢回饋單清單](#get-merchant-apivendorsservice_vendor_idfeedbacks)
  - [更新諮詢回饋單狀態](#patch-merchant-apifeedbacksfeedback_nostatus)
  - [查詢服務項目的標籤勾選狀態](#get-merchant-apiservicesservice_idlabels)
  - [設定服務項目的標籤（覆蓋式）](#put-merchant-apiservicesservice_idlabels)
  - [取得該商家所有表單清單](#get-merchant-apivendorsservice_vendor_idforms)
  - [取得某張表單的完整內容](#get-merchant-apiformsform_idfull)
  - [更新表單完整內容（差異比對式）](#patch-merchant-apiformsform_id)
  - [建立表單及其巢狀內容](#post-merchant-apiforms)
  - [建立新訂單](#post-merchant-apiorders)
  - [查看該商家的訂單清單](#get-merchant-apivendorsservice_vendor_idorders)
  - [更新特定訂單](#patch-merchant-apivendorsservice_vendor_idordersrecord_id)
  - [設定商家資訊](#patch-merchant-apivendorsservice_vendor_id)
  - [商家後台登入](#post-merchant-apiauthlogin)

---

## APP 端（app_api.py，prefix: `/app-api`）

### `GET /app-api/service-types/{service_type}/vendors`

尋找特定服務的廠商（可依標籤篩選）

**輸入**
- `service_type` (path, string)：服務類型代碼。
  `1`=居家清潔 `2`=家電清洗 `3`=包裹寄送 `6`=餐廳訂位 `9`=美食外送 `10`=水電修繕 `11`=商城購物
- `labels` (query, string, 可選)：逗號分隔的標籤 id，例如 `3,5`。
  `1`=寵物友善 `2`=24小時營業 `3`=專業認證 `4`=免費估價 `5`=到府服務 `6`=快速到達

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

**說明**：根據服務類型找出所有提供此類服務的廠商。若有傳入 `labels`，只保留「其下有服務項目同時擁有所有指定標籤」的廠商。

---

### `POST /app-api/feedbacks`

建立諮詢回饋單（feedback）

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

**說明**：使用者填寫諮詢表單後呼叫此 API 建立一筆 feedback 記錄。

---

### `GET /app-api/users/{inbr_account_id}/orders-overview`

查看會員的訂單總覽（未處理 feedback + 全部訂單）

**輸入**
- `inbr_account_id` (path, uuid)：會員 UUID，登入時取得

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
- `orders`：該會員的全部訂單，每筆訂單附加 `review` 欄位——有評價過的訂單是完整評價物件，沒評價過則是 `null`

**說明**：取得該會員的未處理諮詢與全部訂單，組裝後一次回傳，供前端顯示訂單/諮詢總覽頁面。訂單評價（`mms_order_review`）一併查出並附加到對應訂單上，前端不需要再另外呼叫評價 API。

---

### `POST /app-api/orders/{record_id}/review`

對已完成的訂單提交評價

**輸入**
- `record_id` (path, int)：訂單內部 ID（`mms_order_record.record_id`）
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

**說明**：使用者對一筆已完成訂單提交評價（一筆訂單至多一筆評價）。api_server 會驗證：訂單狀態須為 `80`（已完成）、`inbr_account_id` 須與訂單的下單會員一致、且該訂單尚未被評價過（否則回 409）。成功後會自動把對應訂單的 `comment_status` 改成 `02`（已評價）。

---

### `PATCH /app-api/users/{inbr_account_id}/orders/{record_id}/review`

修改自己對某筆訂單提交過的評價

**輸入**
- `inbr_account_id` (path, uuid)：會員 UUID（須為原評價者本人）
- `record_id` (path, int)：訂單內部 ID
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

**說明**：使用者修改自己先前提交的評價。api_server 會比對 `inbr_account_id` 是否與該筆評價的原評價者一致，不一致回 403；訂單尚未被評價過則回 404。

---

### `PATCH /app-api/users/{inbr_account_id}`

設定（更新）會員個人資訊

**輸入**
- `inbr_account_id` (path, uuid)：會員 UUID
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

**說明**：更新會員聯絡方式或密碼，未傳入的欄位不會被覆蓋。密碼自動做 bcrypt 雜湊，聯絡資訊自動做 AES-256-GCM 加密。

---

### `POST /app-api/auth/login`

APP 會員登入

**輸入**
```json
{ "account": "user01@example.com", "password": "Test@1234" }
```

**輸出**
```json
{ "inbr_account_id": "019c0464-2d01-73f0-9f9b-d1392fdb941a" }
```

**說明**：驗證帳密，成功後回傳會員 UUID。前端存起來，之後呼叫其他 API 時作為路徑參數使用。目前無 token 機制，僅回傳識別碼。

---

## 商家後台（merchant_api.py，prefix: `/merchant-api`）

### `GET /merchant-api/vendors/{service_vendor_id}/feedbacks`

查看該商家收到的諮詢回饋單清單

**輸入**
- `service_vendor_id` (path, int)：服務商 ID
- `status` (query, string, 可選)：`0`=未處理 `1`=處理中 `2`=已完成，不傳則回傳全部

**輸出**：feedback 物件陣列，每筆包含 `feedback_no`、`service_id`、`feedback_content`、`is_read`、`status`、`contact_name` 等聯絡資訊、`description`、`inbr_account_id`、`cre_time` 等欄位。

**說明**：取得屬於該服務商的所有諮詢回饋單，用於商家後台的回饋清單頁面。

---

### `PATCH /merchant-api/feedbacks/{feedback_no}/status`

更新諮詢回饋單狀態（已讀/處理進度）

**輸入**
- `feedback_no` (path, string)：回饋單編號
- body：
```json
{ "is_read": "0=未讀 1=已讀", "status": "0=未處理 1=處理中 2=已完成" }
```

**輸出**：更新後的完整 feedback 物件

**說明**：商家閱讀或處理回饋單時呼叫此 API 更新狀態，兩個欄位皆為可選、只傳需要改的。

---

### `GET /merchant-api/services/{service_id}/labels`

查詢服務項目目前的標籤勾選狀態（給編輯頁面用）

**輸入**
- `service_id` (path, int)：服務項目 ID

**輸出**：全部標籤清單，並標示此 service 目前是否已勾選
```json
[
  { "id": 1, "name": "寵物友善", "checked": true },
  { "id": 2, "name": "24小時營業", "checked": false }
]
```

**說明**：給商家後台「編輯服務項目」頁面用：一次拿到所有可選標籤，並直接標示哪些是此 service 已經有的，前端可以直接渲染成已勾選/未勾選的 checkbox，不用自己再做比對。

---

### `PUT /merchant-api/services/{service_id}/labels`

設定服務項目的標籤（覆蓋式）

**輸入**
- `service_id` (path, int)：服務項目 ID
- body：
```json
{ "label_ids": [1, 3, 5] }
```
傳入完整的標籤 id 清單，會**取代**該 service 原有的全部標籤（不在清單內的既有標籤會被移除，新出現的會被新增）。

**輸出**：更新後的完整標籤清單，格式同 `GET .../labels`

**說明**：給商家後台「編輯服務項目」頁面的儲存按鈕用。前端頁面載入時已用 `GET .../labels` 勾好現有標籤，使用者調整勾選後，把目前畫面上所有「勾選中」的 label_id 整包傳過來即可，不需要自己算差異。這裡會自動比對現有關聯，只新增/刪除有變動的部分（api_server 本身沒有批次覆蓋的端點，逐筆呼叫組成）。

---

### `GET /merchant-api/vendors/{service_vendor_id}/forms`

取得該商家的所有表單清單（不含巢狀題組/題目內容）

**輸入**
- `service_vendor_id` (path, int)：服務商 ID
- `type` (query, string, 可選)：篩選表單類型代碼。
  `1`=C端(無需評估) `2`=C端(需評估) `3`=B端 `4`=轉訂單流程 `5`=客服。不傳則回傳全部類型。

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

**說明**：列出該商家名下建立過的所有表單（不論審核狀態、啟用狀態），用於商家後台「表單管理」頁面顯示表單清單。這裡只回傳每張表單的主檔資訊，不含底下的題組/題目/選項；若要看某張表單的完整內容，改用下方的 `GET /forms/{form_id}/full`。

---

### `GET /merchant-api/forms/{form_id}/full`

取得某張表單的完整內容（含題組/題目/選項/圖片/地區關聯）

**輸入**
- `form_id` (path, int)：表單 ID

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
`topics` 是平面陣列（非巢狀在 groups 底下），每個 topic 帶自己的 `form_group_id` 可對應回所屬題組；每個 topic 已內嵌好自己的 `media`、`options`、`county_district_relations`。

**說明**：商家後台「表單管理」頁面中，商家從 `GET /vendors/{id}/forms` 清單點擊某張表單後，呼叫此端點取得該表單的完整內容用於編輯頁面渲染（顯示所有題組、題目、選項、輔助圖片、地區限制）。直接轉發 api_server 現成的組裝端點，未做額外處理。

---

### `PATCH /merchant-api/forms/{form_id}`

更新表單完整內容（表單主檔 + 題組 + 題目 + 選項，差異比對式）

**輸入**
- `form_id` (path, int)：表單 ID
- body：與 `GET /forms/{form_id}/full` 相同的巢狀結構，前端載入後直接在畫面上編輯、改完整包送回即可
```json
{
  "form": {
    "name": "表單名稱",
    "intro_content": "服務介紹(html)",
    "notice_content": "注意事項(html)",
    "terms_content": "服務條款(html)",
    "is_enable": "0=禁用 1=啟用"
  },
  "groups": [
    {
      "id": 20,
      "name": "基本資料(既有題組,帶id=更新)",
      "sort": 0,
      "topics": [
        {
          "id": 30,
          "title": "既有題目,帶id=更新",
          "is_required": "1",
          "sort": 0,
          "options": [
            { "id": 40, "option_name": "既有選項,帶id=更新", "unit_price": 1200 },
            { "option_name": "新選項,不帶id=新增", "unit_price": 800 }
          ]
        },
        { "title": "新題目,不帶id=新增", "type": "1", "is_required": "0", "sort": 1 }
      ]
    },
    { "name": "新題組,不帶id=新增", "sort": 1, "topics": [] }
  ]
}
```
- `form` 可省略（不需要改表單主檔欄位時）
- 每個 group/topic/option **有 `id`** = 更新既有項目；**沒有 `id`** = 新增
- 目前資料庫中存在、但這次 payload 沒帶到的 group/topic/option 會被**刪除**（差異比對，比照 `PUT /services/{id}/labels` 的覆蓋式邏輯）
- 題目可透過放到不同的 `groups[].topics[]` 底下搬到別的題組（後端會更新該題目的 `form_group_id`）；選項目前**不支援**搬到別的題目（若要搬，等同刪除原選項 + 在新題目下新增一筆）
- 本端點不處理題目輔助圖片（`pms_topic_media`），既有圖片不會被異動

**輸出**：更新後的完整巢狀表單結構，格式同 `GET /forms/{form_id}/full`

**說明**：給商家後台「編輯表單」頁面用：頁面用 `GET /forms/{form_id}/full` 載入表單後，商家編輯表單名稱/題組/題目/選項，改完整包送回這支 API，不需要前端自己算差異、分別呼叫多支底層端點。

實作流程：
1. 先呼叫 `GET /forms/{form_id}/full` 取得資料庫目前的實際狀態
2. 比對 payload 與現況，算出現況存在但 payload 沒帶到的 group/topic/option（代表要刪除）
3. 依 選項 → 題目 → 題組 的順序刪除
4. 依 表單 → 題組 → 題目 → 選項 的順序，對有 `id` 的項目呼叫 PATCH 更新，對沒有 `id` 的項目呼叫 POST 新增
5. 重新呼叫 `GET /forms/{form_id}/full` 回傳最新完整結構

⚠️ api_server 沒有跨資源的交易機制，若中途某一步失敗，前面已完成的刪除/新增/更新不會自動回滾，可能造成部分內容不一致，需要另外檢查修正。

---

### `POST /merchant-api/forms`

一次性建立表單及其巢狀內容（題組 → 題目 → 選項）

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
  ]
}
```
`groups`、`groups[].topics`、`topics[].options` 皆為陣列，可依需要放多個。題目若非單選/複選題（例如簡答、備註類型）可省略 `options`。

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

**說明**：給商家後台「建立新表單」頁面用，一次送出完整表單結構（題組、題目、選項），不需要前端自己依序呼叫 4 層 API。內部依序呼叫 api_server 的 `POST /forms` → `POST /forms/{id}/groups` → `POST /forms/{id}/topics`（自動帶入所屬 `form_group_id`）→ `POST /form-topics/{id}/options`，再把各層回傳結果組裝成巢狀結構回傳。新建表單的 `review_status` 一律為 `0`（未審核），需另外呼叫審核端點才能上線。

⚠️ api_server 沒有跨資源的交易機制，若中途某一層建立失敗（例如某個題目建立失敗），前面已成功建立的表單/題組不會自動回滾，需要另外刪除清理。這是巢狀組裝 API 目前的已知限制。

---

### `POST /merchant-api/orders`

建立新訂單

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

**輸出**：建立後的完整訂單物件（含系統產生的 `record_id`），附加 `review: null`（新建訂單不可能已有評價）

**說明**：商家後台建立一筆新訂單。個資欄位傳入明文即可，系統會自動用 AES-256-GCM 加密存儲。

---

### `GET /merchant-api/vendors/{service_vendor_id}/orders`

查看該商家的訂單清單

**輸入**
- `service_vendor_id` (path, int)：服務商 ID
- `order_status` (query, string, 可選)：篩選訂單狀態碼，不傳則回傳全部。
  服務訂單常用：`11`待訂金 `12`已付訂金待報價 `13`已報價待同意 `80`已完成 `90`已取消
  訂位/預約常用：`01`待付款 `02`待確認 `03`已確認 `80`已完成 `90`已取消

**輸出**：訂單物件陣列，每筆包含 `record_id`、`order_no`、`inbr_account_id`、`order_type`、`order_status`、`order_time`、`final_amount`、`order_items` 等欄位，並附加 `review` 欄位——有評價過的訂單是完整評價物件，沒評價過則是 `null`

**說明**：取得屬於該服務商的所有訂單，用於商家後台的訂單管理頁面。訂單評價（`mms_order_review`）一併查出並附加到對應訂單上，前端不需要再另外呼叫評價 API。

---

### `PATCH /merchant-api/vendors/{service_vendor_id}/orders/{record_id}`

更新特定訂單（狀態、金額、時間等）

**輸入**
- `service_vendor_id` (path, int)：服務商 ID
- `record_id` (path, int)：訂單內部 ID
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

**輸出**：更新後的完整訂單物件，附加 `review` 欄位——有評價過則是完整評價物件，沒評價過則是 `null`

**說明**：常見場景：確認訂金（`order_status` 11→12 + `deposit_time`）、報價（改 13 + `quote_no`）、完成（改 80 + `complete_time`）、取消（改 90 + `cancel_time` + `cancel_reason`）。訂單完成後可能已有評價（`mms_order_review`），這裡會一併查出並附加到回傳的訂單物件上。

---

### `PATCH /merchant-api/vendors/{service_vendor_id}`

設定（更新）商家資訊（商家屬性 + 管理帳號聯絡方式）

**輸入**
- `service_vendor_id` (path, int)：服務商 ID
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

**說明**：商家後台「設定」頁面用的 API，可同時更新商家基本屬性和管理帳號的密碼/聯絡資訊，兩個區塊互相獨立。

---

### `POST /merchant-api/auth/login`

商家後台登入

**輸入**
```json
{ "account": "vendor01@example.com", "password": "Test@1234" }
```

**輸出**
```json
{ "service_vendor_id": 1, "account_id": "019fb652-df72-7992-989e-f456194edf8c" }
```

**說明**：驗證商家帳密，成功後回傳 `service_vendor_id` 和 `account_id`，前端存起來供後續 API 呼叫使用。目前無 token 機制，僅回傳識別碼。

---

## 已知限制（demo 階段暫緩）

- 完全沒有身分驗證機制（登入只回傳識別碼，沒有 JWT/Session token），呼叫端須自行妥善保管 `inbr_account_id` / `service_vendor_id`
- 部分巢狀組裝端點（`POST /merchant-api/forms`、`PATCH /merchant-api/forms/{form_id}`）依序呼叫多支底層 API，無跨資源交易機制，中途失敗不會自動回滾
- payload 目前皆用 `dict` 接收，尚未上 Pydantic model 做輸入驗證

詳見 `.kiro/steering/project-overview.md` 與 `Database/部署手冊.md` 第 8 章「上線前安全檢查清單」。

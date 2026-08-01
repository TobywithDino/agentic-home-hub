# API Reference — DB Access API Server

本文件是 `api_server/` 的完整 API 規格參考，記錄全部 94 個業務端點的路徑、方法、請求/回應型別，並標註每個端點對應圖面需求（`AI指示文件/DB_API_1.jpg`、`DB_API_2.jpg`）或設計來源。

> **本文件已於 2026-08-01 對照實際程式碼（`api_server/app/routers/*.py` 的路由定義，含新增的 `routers/summaries.py`）逐條核對，路徑與方法 100% 一致，無遺漏或錯誤。**

- 所有查詢類（GET 列表）端點皆支援 `limit`（預設 20，1~200）/ `offset`（預設 0）分頁查詢參數，回應包裝在 `PagedResponse` 中。
- 所有刪除皆為軟刪除（更新 `is_deleted` 欄位），例外：`cms_homepage_service_vendor`、`cms_homepage_service`、`pms_form_group`、`pms_form_topic` 這 4 張表在 DDL 中沒有 `is_deleted` 欄位，其刪除為實體 DELETE（詳見各節註記）。
- 型別標記慣例：`str?` 表示可為 `null`；`uuid` 對應 Python `uuid.UUID` / JSON 字串；`datetime` 為 ISO 8601 字串（如 `2026-07-31T00:00:00Z`）；`json` 表示 `dict` 或 `list` 皆可（PostgreSQL JSONB 欄位）。

## 目錄

- [共用回應格式](#共用回應格式)
- [A. 縣市/行政區參考資料](#a-縣市行政區參考資料-sys_county-sys_district)
- [B. 服務商/服務項目主檔](#b-服務商服務項目主檔-cms_homepage_service_vendor-cms_homepage_service)
- [C. 標籤](#c-標籤-label-service_label)
- [D. 會員帳號](#d-會員帳號-user_accounts)
- [E. 服務商後台帳號](#e-服務商後台帳號-vendor_accounts)
- [F. 表單結構](#f-表單結構-pms_form-系列)
- [G. 諮詢單回饋](#g-諮詢單回饋-pms_form_feedback)
- [H. 訂單](#h-訂單-mms_order_record)
- [I. 訂單評價](#i-訂單評價-mms_order_review)
- [I2. 評價AI摘要](#i2-評價ai摘要-mms_review_summary_service-mms_review_summary_vendor)
- [J. 系統](#j-系統)
- [圖面功能覆蓋檢查](#圖面功能覆蓋檢查12項全部可實現)

---

## 共用回應格式

### `PagedResponse`（所有列表端點的外層包裝）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `total` | `int` | 符合條件的總筆數（未受 limit/offset 影響） |
| `limit` | `int` | 本次請求的分頁大小 |
| `offset` | `int` | 本次請求的分頁位移 |
| `items` | `array` | 實際資料列表，元素型別依端點不同，見各節說明 |

### 通用錯誤格式

| Status Code | 情境 |
|---|---|
| `404` | 指定資源不存在 |
| `409` | 唯一性衝突（如帳號已存在、主鍵重複） |
| `401` | 登入帳密錯誤或帳號已停用/刪除 |
| `422` | 請求 body 未通過 Pydantic 驗證（型別錯誤、必填缺漏） |

錯誤回應格式：`{"detail": "錯誤說明文字"}`

---

## A. 縣市/行政區參考資料（sys_county, sys_district）

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 1 | `GET /counties` | 列表(分頁) | - | `PagedResponse<CountyOut>` | 支援表單「地區選單」題型 |
| 2 | `GET /counties/{county_code}` | 單筆 | - | `CountyOut` | 同上 |
| 3 | `POST /counties` | 新增縣市 | `CountyCreate` | `CountyOut`（201） | 管理端CRUD |
| 4 | `PATCH /counties/{county_code}` | 更新縣市 | `CountyUpdate` | `CountyOut` | 管理端CRUD |
| 5 | `DELETE /counties/{county_code}` | 軟刪除 | - | 無內容（204） | 管理端CRUD |
| 6 | `GET /counties/{county_code}/districts` | 該縣市所有行政區(分頁) | - | `PagedResponse<DistrictOut>` | 支援地區選單題型 |
| 7 | `GET /districts/{district_code}` | 單筆 | - | `DistrictOut` | 同上 |
| 8 | `POST /districts` | 新增行政區 | `DistrictCreate` | `DistrictOut`（201） | 管理端CRUD |
| 9 | `PATCH /districts/{district_code}` | 更新行政區 | `DistrictUpdate` | `DistrictOut` | 管理端CRUD |
| 10 | `DELETE /districts/{district_code}` | 軟刪除 | - | 無內容（204） | 管理端CRUD |

**`CountyOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `code` | `str` | 縣市代碼（PK，2字元） |
| `name` | `str` | 縣市名稱 |
| `sort` | `int` | 排序 |
| `is_deleted` | `str` | `'0'` 正常 / `'1'` 已刪除 |
| `upd_time` | `datetime` | 異動時間 |
| `cre_time` | `datetime` | 新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |

**`CountyCreate`**：`code: str`（必填,≤2字元）、`name: str`（必填,≤10字元）、`sort: int`（預設0）

**`CountyUpdate`**：`name: str?`、`sort: int?`（皆為可選,只更新有提供的欄位）

**`DistrictOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `code` | `str` | 行政區代碼（PK，3字元） |
| `county_code` | `str` | 所屬縣市代碼 |
| `name` | `str` | 行政區名稱 |
| `name_with_county` | `str` | 行政區名稱＋縣市名稱 |
| `zip` | `str` | 郵遞區號 |
| `sort` | `int` | 排序 |
| `is_deleted` | `str` | `'0'`/`'1'` |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |

**`DistrictCreate`**：`code`、`county_code`、`name`、`name_with_county`、`zip`（皆必填）、`sort: int`（預設0）

**`DistrictUpdate`**：`name`/`name_with_county`/`zip`/`sort` 皆為可選

---

## B. 服務商/服務項目主檔（cms_homepage_service_vendor, cms_homepage_service）

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 11 | `GET /service-vendors` | 列表(分頁) | - | `PagedResponse<ServiceVendorOut>` | 管理端CRUD |
| 12 | `GET /service-vendors/{service_vendor_id}` | 查看商家資訊 | - | `ServiceVendorOut` | 慣例 |
| 13 | `POST /service-vendors` | 新增服務商 | `ServiceVendorCreate` | `ServiceVendorOut`（201） | 管理端CRUD |
| 14 | `PATCH /service-vendors/{service_vendor_id}` | 更新商家屬性 | `ServiceVendorUpdate` | `ServiceVendorOut` | **【圖2：設定商家資訊-商家屬性部分】** |
| 15 | `DELETE /service-vendors/{service_vendor_id}` | 刪除商家 | - | 無內容（204） | 管理端CRUD（⚠️實體刪除，無is_deleted欄位） |
| 16 | `GET /services` | 列表(分頁,可用`service_vendor_id`/`type` query參數篩選) | - | `PagedResponse<ServiceOut>` | 管理端CRUD |
| 17 | `GET /services/{service_id}` | 單筆 | - | `ServiceOut` | 慣例 |
| 18 | `GET /services/{service_id}/vendors` | 回傳所有符合service_id的廠商 | - | `ServiceVendorOut[]`（純陣列,非分頁） | **【圖1：尋找特定服務的廠商】** |
| 19 | `POST /services` | 新增服務項目 | `ServiceCreate` | `ServiceOut`（201） | 管理端CRUD |
| 20 | `PATCH /services/{service_id}` | 更新服務項目 | `ServiceUpdate` | `ServiceOut` | 管理端CRUD |
| 21 | `DELETE /services/{service_id}` | 刪除服務項目 | - | 無內容（204） | 管理端CRUD（⚠️實體刪除，無is_deleted欄位） |

**`ServiceVendorOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `int` | 服務商ID（PK） |
| `name` | `str` | 服務商名稱 |
| `description` | `str?` | 服務商描述 |

**`ServiceVendorCreate`**：`id: int`（必填,需手動指定,此表非自增）、`name: str`、`description: str?`

**`ServiceVendorUpdate`**：`name: str?`、`description: str?`

**`ServiceOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `int` | 服務項目ID（PK） |
| `service_vendor_id` | `int` | 所屬服務商ID |
| `type` | `str` | 服務類型代碼（見下方對照表） |
| `name` | `str` | 服務項目名稱 |
| `img_url` | `str?` | 圖片網址 |
| `description` | `str?` | 說明（可含HTML） |
| `form_id` | `int?` | 此服務項目對應的諮詢表單ID（對應`pms_form.id`，新增功能）。`null`代表尚未設定專屬表單。一個表單可被多個服務項目共用（多個service的`form_id`可指向同一張表單） |

`type` 代碼對照：`1`一般居家清潔 / `2`家電清洗 / `3`包裹寄送 / `6`餐廳訂位 / `9`美食外送 / `10`水電修繕 / `11`商城購物

**`ServiceCreate`**：`id`、`service_vendor_id`、`type`、`name`（皆必填）、`img_url`/`description`/`form_id`（可選）

**`ServiceUpdate`**：全部欄位皆可選（含`form_id`）

**`form_id` 補充說明**：此欄位是為了解決「一個服務項目要對應到哪張諮詢表單」的查詢需求而新增（原設計只有`pms_form.service_vendor_id`，無法從單一service_id直接查到對應表單）。與`pms_form`本身的B端/客服/轉訂單流程等通用表單（透過`service_vendor_id` + `GET /vendors/{id}/forms`查詢）互不影響，那些表單不需要、也不會被指定到某個`service_id`。api_server不驗證`form_id`是否真實存在於`pms_form`（延續全庫鬆耦合、無實體FK的設計慣例）。

---

## C. 標籤（label, service_label）

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 22 | `GET /labels` | 列表(分頁,可用`service_type` query參數篩選) | - | `PagedResponse<LabelOut>` | 管理端CRUD |
| 23 | `GET /labels/{label_id}` | 單筆 | - | `LabelOut` | 慣例 |
| 24 | `POST /labels` | 建立標籤 | `LabelCreate` | `LabelOut`（201） | 管理端CRUD |
| 25 | `PATCH /labels/{label_id}` | 更新標籤 | `LabelUpdate` | `LabelOut` | 管理端CRUD |
| 26 | `DELETE /labels/{label_id}` | 軟刪除標籤 | - | 無內容（204） | 管理端CRUD |
| 27 | `GET /services/{service_id}/labels` | 該服務項目的標籤(分頁) | - | `PagedResponse<ServiceLabelOut>` | 慣例 |
| 28 | `PUT /services/{service_id}/labels/{label_id}` | 建立服務-標籤關聯 | - | `ServiceLabelOut`（201） | 管理端CRUD |
| 29 | `DELETE /services/{service_id}/labels/{label_id}` | 移除服務-標籤關聯 | - | 無內容（204） | 管理端CRUD |

**`LabelOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `int` | 標籤ID（PK，自增） |
| `name` | `str` | 標籤名稱 |
| `sort` | `int` | 排序 |
| `is_enable` | `str` | `'0'`禁用 / `'1'`啟用 |
| `is_deleted` | `str` | `'0'`/`'1'` |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |
| `service_type` | `str?` | 所屬服務類型代碼（對應`cms_homepage_service.type`，新增功能）。`null`代表通用標籤（適用所有服務類型，例如「寵物友善」「24小時營業」）；有值代表該服務類型專屬標籤（例如`type=6`餐廳訂位專屬的「中餐廳」「泰式料理」）。各`service_type`各自維護自己的專屬標籤，不要求跨類型共用 |

**`LabelCreate`**：`name: str`（必填）、`sort: int`（預設0）、`is_enable: str`（預設`"1"`）、`service_type: str?`（可選，不填即為通用標籤）

**`LabelUpdate`**：`name`/`sort`/`is_enable`/`service_type` 皆可選

**`GET /labels` 的 `service_type` query 參數說明**：不帶此參數回傳全部啟用中標籤（不分類型）；帶入時回傳「通用標籤（`service_type IS NULL`） + 該類型專屬標籤」的聯集，供商家後台編輯服務項目時只顯示跟該服務類型相關的標籤可勾選，不會看到其他類型的專屬標籤（例如編輯水電修繕服務時不會看到「中餐廳」）。

**唯一性規則**：標籤名稱唯一性範圍是「同一個`service_type`內」（`UNIQUE(service_type, name)`），不同`service_type`可以有相同名稱的專屬標籤（例如`type=6`跟`type=9`都可以各自有「中餐廳」標籤）；通用標籤（`service_type IS NULL`）額外用 partial unique index 保證全域名稱唯一（PostgreSQL 的`UNIQUE`約束對多筆 NULL 值不視為衝突，故需此額外限制）。

**`POST /labels`/`PATCH /labels/{label_id}` 的重複性檢查**：建立/更新前會依上述唯一性規則主動查詢是否已存在同名標籤（`service_type`有值時查同類型內、為`null`時查全域通用標籤），若衝突回 409（`detail`為「此服務類型下已存在同名標籤」或「標籤名稱已存在」），不會讓資料庫層的唯一約束例外直接外洩成 500。`PATCH`僅在 payload 有帶`name`或`service_type`時才觸發此檢查，且會排除自身這筆（改回原名稱不會誤判為衝突）。

**`ServiceLabelOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `service_id` | `int` | 服務項目ID（複合PK之一） |
| `label_id` | `int` | 標籤ID（複合PK之一） |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |

---

## D. 會員帳號（user_accounts）

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 30 | `POST /auth/user/register` | 建立會員帳號 | `UserRegister` | `UserOut`（201） | 登入前必要前置 |
| 31 | `POST /auth/user/login` | 帳密登入 | `UserLogin` | `UserLoginOut` | **【圖1：登入】** |
| 32 | `GET /users/{inbr_account_id}` | 查看會員資料 | - | `UserOut` | 慣例 |
| 33 | `PATCH /users/{inbr_account_id}` | 更新聯絡方式/密碼 | `UserUpdate` | `UserOut` | **【圖1：設定會員資訊】** |
| 34 | `DELETE /users/{inbr_account_id}` | 軟刪除 | - | 無內容（204） | 慣例 |

> `is_2fa_enabled`/`totp_secret` 欄位保留於DB schema供未來擴充，本階段不提供對應API；`last_login_time` 由 `/login` 內部邏輯自動更新，不需獨立端點。

**`UserRegister`**：`account: str`（必填,≤100字元）、`password: str`（必填,8~72字元,將以bcrypt雜湊）、`contact_name`/`contact_mobile`/`contact_email`（皆可選,明文傳入,伺服器端加密後存儲）

**`UserLogin`**：`account: str`、`password: str`（皆必填）

**`UserLoginOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `inbr_account_id` | `uuid` | 會員編號，登入成功後 APP 應保存供後續請求使用 |

**`UserUpdate`**：`password`/`contact_name`/`contact_mobile`/`contact_email`/`is_enable` 皆可選,只更新有提供的欄位

**`UserOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `uuid` | 會員編號（PK） |
| `account` | `str` | 登入帳號 |
| `contact_name` | `str?` | 姓名明文。**未設定 `PII_ENCRYPTION_KEY_B64` 環境變數時一律為 `null`**（見下方PII欄位說明） |
| `contact_name_hash` | `str?` | 姓名SHA-256 hash（Base64），可用於比對查詢，不受加密金鑰是否設定影響 |
| `contact_mobile` / `contact_mobile_hash` | `str?` / `str?` | 同上，手機 |
| `contact_email` / `contact_email_hash` | `str?` / `str?` | 同上，Email |
| `is_2fa_enabled` | `str` | `'0'`/`'1'`（欄位保留，本階段無對應功能） |
| `last_login_time` | `datetime?` | 最後登入時間 |
| `is_enable` | `str` | `'0'`禁用 / `'1'`啟用 |
| `is_deleted` | `str` | `'0'`/`'1'` |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |

**PII 加密欄位說明**：`contact_name`/`contact_mobile`/`contact_email` 對應資料庫的 `bytea` 加密欄位（AES-256-GCM）。若環境變數 `PII_ENCRYPTION_KEY_B64` 未設定，寫入時這些欄位存 `NULL`，讀取時一律回傳 `null`；只有 `_hash` 欄位（SHA-256）永遠可用於查詢比對。此為刻意的安全預設值，詳見 `api_server/README.md`。

---

## E. 服務商後台帳號（vendor_accounts）

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 35 | `POST /auth/vendor/register` | 建立後台帳號 | `VendorAccountRegister` | `VendorAccountOut`（201） | 登入前必要前置 |
| 36 | `POST /auth/vendor/login` | 帳密登入 | `VendorLogin` | `VendorLoginOut` | **【圖2：登入】** |
| 37 | `GET /vendors/{service_vendor_id}/accounts` | 該服務商下所有管理帳號(分頁) | - | `PagedResponse<VendorAccountOut>` | 慣例（一個服務商可有多個管理帳號） |
| 38 | `GET /vendors/{service_vendor_id}/accounts/{account_id}` | 單一帳號詳細 | - | `VendorAccountOut` | 慣例 |
| 39 | `PATCH /vendors/{service_vendor_id}/accounts/{account_id}` | 更新聯絡方式/密碼 | `VendorAccountUpdate` | `VendorAccountOut` | **【圖2：設定商家資訊-聯絡方式部分】** |
| 40 | `DELETE /vendors/{service_vendor_id}/accounts/{account_id}` | 軟刪除帳號 | - | 無內容（204） | 慣例 |

> 同D表，2FA欄位保留不提供API。

**`VendorAccountRegister`**：`service_vendor_id: int`（必填）、`account`/`password`（必填,規則同UserRegister）、`contact_name`/`contact_mobile`/`contact_email`（可選）

**`VendorLogin`**：`account: str`、`password: str`

**`VendorLoginOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `service_vendor_id` | `int` | 該帳號所屬服務商ID |
| `account_id` | `uuid` | 帳號本身的識別碼 |

**`VendorAccountUpdate`**：欄位同 `UserUpdate`（password/contact_name/contact_mobile/contact_email/is_enable，皆可選）

**`VendorAccountOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `uuid` | 帳號ID（PK） |
| `service_vendor_id` | `int` | 所屬服務商ID |
| `account` | `str` | 登入帳號 |
| `contact_name` / `contact_name_hash` | `str?` / `str?` | 同UserOut的PII欄位規則 |
| `contact_mobile` / `contact_mobile_hash` | `str?` / `str?` | 同上 |
| `contact_email` / `contact_email_hash` | `str?` / `str?` | 同上 |
| `is_2fa_enabled` | `str` | 欄位保留 |
| `last_login_time` | `datetime?` | 最後登入時間 |
| `is_enable` / `is_deleted` | `str` / `str` | 啟用/刪除狀態 |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |

---

## F. 表單結構（pms_form 系列）

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 41 | `GET /forms` | 列表(分頁,可篩`service_vendor_id`/`type`) | - | `PagedResponse<FormOut>` | 管理端CRUD |
| 42 | `GET /forms/{form_id}` | 表單主檔基本資訊 | - | `FormOut` | 慣例，也是APP填單前置 |
| 43 | `GET /forms/{form_id}/full` | 組裝完整結構 | - | `FormFullOut`（見下方，**非Pydantic model，直接組裝dict**） | APP建立feedback前必須 |
| 44 | `POST /forms` | 建立表單 | `FormCreate` | `FormOut`（201） | 管理端CRUD |
| 45 | `PATCH /forms/{form_id}` | 更新表單內容 | `FormUpdate` | `FormOut` | 管理端CRUD |
| 46 | `DELETE /forms/{form_id}` | 軟刪除表單 | - | 無內容（204） | 管理端CRUD |
| 47 | `PATCH /forms/{form_id}/review` | 更新審核狀態 | `FormReviewUpdate` | `FormOut` | 管理端CRUD(窄範圍) |
| 48 | `GET /forms/{form_id}/groups` | 題組列表(分頁) | - | `PagedResponse<FormGroupOut>` | 管理端CRUD |
| 49 | `POST /forms/{form_id}/groups` | 建立題組 | `FormGroupCreate` | `FormGroupOut`（201） | 管理端CRUD |
| 50 | `PATCH /form-groups/{form_group_id}` | 更新題組 | `FormGroupUpdate` | `FormGroupOut` | 管理端CRUD |
| 51 | `DELETE /form-groups/{form_group_id}` | 刪除題組 | - | 無內容（204） | 管理端CRUD（⚠️實體刪除，無is_deleted欄位） |
| 52 | `GET /forms/{form_id}/topics` | 題目列表(分頁) | - | `PagedResponse<FormTopicOut>` | 管理端CRUD |
| 53 | `POST /forms/{form_id}/topics` | 建立題目 | `FormTopicCreate` | `FormTopicOut`（201） | 管理端CRUD |
| 54 | `PATCH /form-topics/{topic_id}` | 更新題目 | `FormTopicUpdate` | `FormTopicOut` | 管理端CRUD |
| 55 | `DELETE /form-topics/{topic_id}` | 刪除題目 | - | 無內容（204） | 管理端CRUD（⚠️實體刪除，無is_deleted欄位） |
| 56 | `GET /form-topics/{topic_id}/media` | 題目輔助圖片列表(分頁) | - | `PagedResponse<TopicMediaOut>` | 管理端CRUD |
| 57 | `POST /form-topics/{topic_id}/media` | 新增輔助圖片 | `TopicMediaCreate` | `TopicMediaOut`（201） | 管理端CRUD |
| 58 | `DELETE /topic-media/{media_id}` | 刪除輔助圖片 | - | 無內容（204） | 管理端CRUD |
| 59 | `GET /form-topics/{topic_id}/options` | 題目選項列表(分頁) | - | `PagedResponse<TopicOptionOut>` | 管理端CRUD |
| 60 | `POST /form-topics/{topic_id}/options` | 新增選項 | `TopicOptionCreate` | `TopicOptionOut`（201） | 管理端CRUD |
| 61 | `PATCH /topic-options/{option_id}` | 更新選項 | `TopicOptionUpdate` | `TopicOptionOut` | 管理端CRUD |
| 62 | `DELETE /topic-options/{option_id}` | 刪除選項 | - | 無內容（204） | 管理端CRUD |
| 63 | `GET /form-topics/{topic_id}/county-district-relations` | 題目縣市行政區對應列表(分頁) | - | `PagedResponse<CountyDistrictRelationOut>` | 管理端CRUD |
| 64 | `POST /form-topics/{topic_id}/county-district-relations` | 新增對應關係 | `CountyDistrictRelationCreate` | `CountyDistrictRelationOut`（201） | 管理端CRUD |
| 65 | `DELETE /form-topics/{topic_id}/county-district-relations` | 刪除對應關係 | `CountyDistrictRelationDelete`（⚠️用body帶完整複合主鍵,非路徑參數） | 無內容（204） | 管理端CRUD |
| 78 | `GET /vendors/{service_vendor_id}/forms/full` | 獲取廠商表單內容：該廠商所有已審核且啟用表單的完整結構 | - | 見下方（非分頁,純陣列） | 新增功能，圖面未涵蓋 |

**`FormOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `int` | 表單ID（PK，自增） |
| `service_vendor_id` | `int` | 服務提供商ID |
| `type` | `str` | 表單類型：`1`C端(無評估) / `2`C端(需評估) / `3`B端 / `4`轉訂單流程 / `5`客服 |
| `sub_type` | `str` | `1`一般表單 / `2`估價表單 |
| `name` | `str` | 表單名稱 |
| `intro_content` / `notice_content` / `terms_content` | `str?` | 介紹/注意事項/條款內容（HTML） |
| `review_status` | `str` | `0`未審核 / `1`已審核 |
| `reviewed_id` | `uuid?` | 審核人員ID |
| `reviewed_time` | `datetime?` | 審核時間 |
| `is_enable` / `is_deleted` | `str` / `str` | 啟用/刪除狀態 |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |
| `feature` | `json?` | 擴充屬性（自訂JSON結構） |

**`FormCreate`**：`service_vendor_id`/`type`/`sub_type`/`name`（皆必填）、`intro_content`/`notice_content`/`terms_content`/`feature`（可選）、`is_enable`（預設`"1"`）。註：`review_status` 由伺服器固定設為 `"0"`，不接受從此端點指定。

**`FormUpdate`**：以上除`review_status`外欄位皆可選（審核狀態需走 #47 `PATCH /forms/{form_id}/review`）

**`FormReviewUpdate`**：`review_status: str`（必填）、`reviewed_id: uuid`（必填）。`reviewed_time` 由伺服器自動填入當前時間，不接受從請求指定。

**`GET /forms/{form_id}/full` 回傳結構**（非獨立命名的Pydantic model，程式內直接組裝dict，結構如下）：

```json
{
  "form": { /* FormOut */ },
  "groups": [ /* FormGroupOut[] */ ],
  "topics": [
    {
      /* FormTopicOut 全部欄位 */
      "media": [ /* TopicMediaOut[] */ ],
      "options": [ /* TopicOptionOut[] */ ],
      "county_district_relations": [ /* CountyDistrictRelationOut[] */ ]
    }
  ]
}
```

**`GET /vendors/{service_vendor_id}/forms/full` 回傳結構**：`FormFullOut[]`（陣列，每個元素結構與上方 `GET /forms/{form_id}/full` 完全相同），只包含 `is_deleted='0'` 且 `is_enable='1'` 且 `review_status='1'`（已審核）的表單。

**`FormGroupOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `int` | 題組ID（PK） |
| `form_id` | `int` | 所屬表單ID |
| `name` | `str` | 題組名稱 |
| `sort` | `int` | 排序 |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |
| `feature` | `json?` | 擴充屬性 |

**`FormGroupCreate`**：`name: str`（必填）、`sort: int`（預設0）、`feature: json?`

**`FormTopicOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `int` | 題目ID（PK） |
| `form_id` | `int` | 所屬表單ID |
| `form_group_id` | `int` | 所屬題組ID |
| `type` | `str` | 題目類型：`1`簡答/`2`詳答/`3`單選/`4`複選/`5`地區選單/`6`上傳照片/`7`備註/`8`聯絡資料/`9`日期題/`10`聯絡資料(不含地址) |
| `title` | `str` | 題目名稱 |
| `remark` | `str?` | 題目說明 |
| `is_required` | `str` | `0`非必填 / `1`必填 |
| `sort` | `int` | 排序 |
| `is_number_only` | `str?` | (簡答題用)是否只能輸入數字 |
| `minimum_medias_upload` / `maximum_medias_upload` / `specified_medias_upload` | `int?` | (照片題)最少/最多/指定上傳數 |
| `start_date_offset_days` / `end_date_offset_days` | `int?` | (日期題)可選起訖日相對偏移天數 |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |
| `feature` | `json?` | 擴充屬性 |

**`FormTopicCreate`**：`form_group_id`/`type`/`title`（必填）、其餘欄位可選（`is_required`預設`"0"`、`sort`預設0）

**`TopicMediaOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `int` | 圖片ID（PK） |
| `form_id` | `int` | 所屬表單ID（由伺服器依topic自動帶入） |
| `topic_id` | `int` | 所屬題目ID |
| `img_url` | `str` | 圖片網址 |
| `sort` | `int` | 排序 |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |

**`TopicMediaCreate`**：`img_url: str`（必填）、`sort: int`（預設0）

**`TopicOptionOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | `int` | 選項ID（PK） |
| `form_id` / `topic_id` | `int` / `int` | 所屬表單/題目ID |
| `option_name` | `str` | 選項名稱 |
| `unit_price` | `int?` | 單價 |
| `unit` | `str?` | 單位 |
| `is_quantity` | `str?` | 數量可選：`0`不可選/`1`可選 |
| `min_quantity` / `max_quantity` | `int?` / `int?` | 最小/最大可選數量 |
| `is_quoted_separately` | `str?` | 是否另行報價：`0`否/`1`是 |
| `remark` | `str?` | 選項說明 |
| `sort` | `int` | 排序 |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |
| `feature` | `json?` | 擴充屬性 |

**`TopicOptionCreate`**：`option_name: str`（必填）、其餘欄位皆可選（`sort`預設0）

**`CountyDistrictRelationOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `form_id` / `topic_id` | `int` / `int` | 複合主鍵之一 |
| `eff_ts_from` / `eff_ts_to` | `datetime` / `datetime` | 適用起訖時間（複合主鍵之一） |
| `county_code` / `district_code` | `str` / `str` | 縣市/行政區代碼（複合主鍵之一） |
| `upd_time` / `cre_time` | `datetime` | 異動/新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `cre_id` | `uuid` | 新增者編號 |

**`CountyDistrictRelationCreate`**：`eff_ts_from`/`eff_ts_to`/`county_code`/`district_code`（皆必填）

**`CountyDistrictRelationDelete`**：`eff_ts_from`/`county_code`/`district_code`（皆必填，`form_id`/`topic_id`從路徑帶入，`eff_ts_to`不需提供）

---

## G. 諮詢單回饋（pms_form_feedback）

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 66 | `POST /feedbacks` | 建立諮詢單 | `FeedbackCreate` | `FeedbackOut`（201） | **【圖1：建立feedback】** |
| 67 | `GET /feedbacks/{feedback_no}` | 單筆詳細 | - | `FeedbackOut` | 慣例 |
| 68 | `GET /vendors/{service_vendor_id}/feedbacks` | 依service_vendor_id抓取feedbacks(分頁,可用`status` query參數篩選) | - | `PagedResponse<FeedbackOut>` | **【圖2：查看feedback】** |
| 69 | `PATCH /feedbacks/{feedback_no}/status` | 更新已讀/處理狀態 | `FeedbackStatusUpdate` | `FeedbackOut` | **【圖2：更新feedback status】** |
| 70 | `GET /users/{inbr_account_id}/feedbacks` | 會員查自己的諮詢單(分頁) | - | `PagedResponse<FeedbackOut>` | 慣例 |

**`FeedbackCreate`**：`feedback_no`（必填,≤16字元,需自行產生唯一單號）、`service_id`/`platform_code`/`form_id`/`feedback_content`/`form_type`/`inbr_account_id`（皆必填）、`contact_name`/`contact_mobile`/`contact_landline`/`contact_email`/`preferred_contact_time`/`contact_address_county`/`contact_address_district`/`contact_address_detail`/`description`（皆可選）。註：`is_read`、`status` 由伺服器固定初始化為 `"0"`。

**`FeedbackStatusUpdate`**：`is_read: str?`、`status: str?`（皆可選,只更新有提供的欄位）

**`FeedbackOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `feedback_no` | `str` | 回饋單號（PK） |
| `service_id` | `int` | 服務ID |
| `platform_code` | `str` | 平台代號 |
| `form_id` | `int` | 表單ID |
| `feedback_content` | `json` | 表單回饋內容（結構依表單題目動態組成） |
| `form_type` | `str` | 表單類型 |
| `is_read` | `str` | `0`未讀 / `1`已讀 |
| `status` | `str` | 回饋狀態（`0`為建立時預設值，語意為未處理；其餘代碼由業務邏輯自訂） |
| `contact_name` / `contact_name_hash` | `str?` / `str?` | 聯絡人姓名（PII，規則同D表說明）/ hash |
| `contact_mobile` / `contact_mobile_hash` | `str?` / `str?` | 聯絡人手機（PII）/ hash |
| `contact_landline` / `contact_landline_hash` | `str?` / `str?` | 聯絡人市話（PII）/ hash |
| `contact_email` / `contact_email_hash` | `str?` / `str?` | 聯絡人Email（PII）/ hash |
| `preferred_contact_time` | `str?` | 方便聯絡時間：`1`上午/`2`下午/`3`皆可 |
| `contact_address_county` / `contact_address_district` | `str?` / `str?` | 聯絡地址縣市/行政區代碼（明文，非PII加密欄位） |
| `contact_address_detail` / `contact_address_detail_hash` | `str?` / `str?` | 聯絡地址詳細（PII）/ hash |
| `description` | `str?` | 備註 |
| `inbr_account_id` | `uuid` | 會員編號 |
| `cre_time` | `datetime` | 新增時間 |
| `upd_id` | `uuid?` | 異動者編號 |
| `upd_time` | `datetime` | 異動時間 |

---

## H. 訂單（mms_order_record）

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 71 | `POST /orders` | 建立訂單 | `OrderCreate` | `OrderOut`（201） | **【圖2：建立order】** |
| 72 | `GET /orders/{record_id}` | 單筆訂單詳細 | - | `OrderOut` | 慣例 |
| 73 | `GET /vendors/{service_vendor_id}/orders` | 依service_vendor_id抓取orders(分頁,可用`order_status` query參數篩選) | - | `PagedResponse<OrderOut>` | **【圖2：查看order】** |
| 74 | `PATCH /vendors/{service_vendor_id}/orders/{record_id}` | 依service_vendor_id更新該筆特定訂單 | `OrderUpdate` | `OrderOut` | **【圖2：更新order】** |
| 75 | `GET /users/{inbr_account_id}/orders` | 會員查自己的訂單(不含feedback,分頁) | - | `PagedResponse<OrderOut>` | 慣例 |
| 76 | `GET /users/{inbr_account_id}/order-summary` | 未處理feedback+order拼接回傳 | - | `OrderSummaryOut`（**非分頁**） | **【圖1：查看訂單】** |

**`OrderCreate`**：`order_no`/`service_vendor_id`/`service_id`/`platform_code`/`inbr_account_id`/`order_type`/`order_status`/`order_time`/`cre_id`/`upd_id`（皆必填）、`member_name`/`member_phone`/`member_email`/`vendor_data`/`order_items`/`remark`/`source_file`/`import_batch`（可選）、`deposit_amount`/`original_amount`/`discount_amount`/`shipping_fee_amount`/`final_amount`（皆為`float`,預設0）。註：`order_no`+`service_id` 組合須唯一（DB層UNIQUE KEY），重複會回409。

**`OrderUpdate`**：`upd_id: uuid`（必填）；`order_status`/各時間戳欄位（`deposit_time`/`confirm_time`/`service_time`/`complete_time`/`cancel_time`/`point_grant_time`/`quote_approved_time`）/各金額欄位（`deposit_amount`/`original_amount`/`discount_amount`/`shipping_fee_amount`/`final_amount`/`refund_amount`/`order_points`/`used_points`/`refund_points`/`earn_points`,皆`float?`）/`point_status`/`vendor_data`/`order_items`/`remark`/`cancel_reason`/`refund_reason`/`quote_approved_by`/`quote_no`/`comment_status`/`is_deleted`（皆可選）

**`OrderOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `record_id` | `int` | 系統內部ID（PK，自增） |
| `order_no` | `str` | 訂單/訂位編號 |
| `service_vendor_id` / `service_id` | `int` / `int` | 服務提供商/服務ID |
| `platform_code` | `str` | 平台代號，`01`=OP APP |
| `inbr_account_id` | `uuid` | 會員編號 |
| `member_name` / `member_name_hash` | `str?` / `str?` | 會員姓名（PII）/ hash |
| `member_phone` / `member_phone_hash` | `str?` / `str?` | 會員電話（PII）/ hash |
| `member_email` / `member_email_hash` | `str?` / `str?` | 會員Email（PII）/ hash |
| `order_type` | `str` | `01`服務訂單/`02`訂位/`03`預約/`04`其他/`05`商品訂單/`06`訂餐 |
| `order_status` | `str` | 狀態代碼依`order_type`而異（詳見`api_server`原始schema註解） |
| `order_time` | `datetime` | 訂單建立時間 |
| `deposit_time` / `confirm_time` / `service_time` / `complete_time` / `cancel_time` | `datetime?` | 各階段時間戳 |
| `deposit_amount` / `original_amount` / `discount_amount` / `shipping_fee_amount` / `final_amount` / `refund_amount` | `float` | 各項金額 |
| `order_points` / `used_points` / `refund_points` / `earn_points` | `float` | 各項點數 |
| `point_status` | `str` | `01`待發放/`02`已發放/`03`不發放/`04`已取消 |
| `point_grant_time` | `datetime?` | 點數發放時間 |
| `vendor_data` | `json?` | 服務商自定義資料 |
| `order_items` | `json?` | 訂單品項明細（可為object或array結構） |
| `remark` / `cancel_reason` / `refund_reason` | `str?` | 備註/取消原因/退款原因 |
| `source_file` | `str?` | 來源檔案名稱 |
| `import_batch` | `str?` | 匯入批次號 |
| `quote_approved_by` | `uuid?` | 報價審核者編號 |
| `quote_approved_time` | `datetime?` | 報價審核時間 |
| `quote_no` | `str?` | 報價單號 |
| `comment_status` | `str` | `00`無須評價/`01`未評價/`02`已評價 |
| `is_deleted` | `bool` | 是否刪除（注意：此表為`bool`型別，非其他表常見的`'0'`/`'1'`字串） |
| `cre_id` / `upd_id` | `uuid` / `uuid` | 新增/異動者編號 |
| `cre_time` / `upd_time` | `datetime` / `datetime` | 新增/異動時間 |

**`OrderSummaryOut`**（`GET /users/{inbr_account_id}/order-summary` 專用，非分頁）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `feedbacks` | `FeedbackOut[]` | 該會員 `status='0'`（未處理）的諮詢單列表 |
| `orders` | `OrderOut[]` | 該會員全部訂單列表（`is_deleted=false`） |

---

## I. 訂單評價（mms_order_review）

新增功能，圖面未涵蓋。每筆訂單至多一筆評價：`mms_order_review.record_id` 直接沿用對應 `mms_order_record.record_id` 的值（1:0..1對應，本表無獨立序列），資料庫層面天然保證「一筆訂單最多一筆評價」，重複提交會因 PK 衝突被路由層轉為 409。詳細設計討論見 `部署手冊.md`。

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 79 | `POST /orders/{record_id}/review` | 提交訂單評價 | `ReviewCreate` | `ReviewOut`（201） | 新增功能 |
| 80 | `GET /orders/{record_id}/review` | 查看單筆訂單的評價（404代表尚未評價） | - | `ReviewOut` | 新增功能 |
| 81 | `PATCH /users/{inbr_account_id}/orders/{record_id}/review` | 評價者本人修改評價內容 | `ReviewUpdate` | `ReviewOut` | 新增功能 |
| 82 | `GET /users/{inbr_account_id}/reviews` | 會員查看自己送出過的所有評價(分頁) | - | `PagedResponse<ReviewOut>` | 新增功能 |
| 83 | `GET /vendors/{service_vendor_id}/reviews` | 供應商查看自己收到的所有評價(分頁,可用`service_id` query參數篩選) | - | `PagedResponse<ReviewOut>` | 新增功能 |
| 84 | `GET /vendors/{service_vendor_id}/rating-summary` | 評分聚合：評價數與平均分(可用`service_id` query參數細分) | - | `RatingSummaryOut` | 新增功能 |
| 85 | `GET /services/{service_id}/reviews` | **公開評價牆，無需身分驗證即可呼叫**，給潛在顧客看該服務項目的評價 | - | `PagedResponse<PublicReviewOut>` | 新增功能 |

**業務規則**：

- `POST /orders/{record_id}/review`：要求該訂單 `order_status='80'`（已完成），否則回409；`payload.inbr_account_id` 須與訂單的 `inbr_account_id` 一致，否則回403（此比對方式依現有架構的信任模型，因整個API目前無身分驗證中介層，非本功能新增的安全坑）；成功後同步將對應訂單的 `comment_status` 更新為 `'02'`（已評價）。
- `PATCH /users/{inbr_account_id}/orders/{record_id}/review`：路徑中的 `inbr_account_id` 須與該筆評價的 `inbr_account_id` 一致，否則回403。
- `GET /services/{service_id}/reviews`：是全部端點中**唯一不需身分驗證即可呼叫**的端點，語意上開放給未登入的訪客/潛在顧客瀏覽。回傳的 `PublicReviewOut` 刻意排除 `inbr_account_id`/`order_no`/`service_vendor_id`/`status`/`is_deleted` 等身分或內部狀態欄位。

**`ReviewCreate`**：`inbr_account_id: uuid`（必填）、`overall_rating: int`（必填,1~5,超出範圍回422）、`rating_detail: json?`、`review_content: str?`、`media: json?`（皆可選）

**`ReviewUpdate`**：`overall_rating`/`rating_detail`/`review_content`/`media` 皆可選,只更新有提供的欄位（`overall_rating`若提供仍受1~5範圍驗證）

**`ReviewOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `record_id` | `int` | 對應訂單ID（PK，與`mms_order_record.record_id`共用值，非自增） |
| `order_no` | `str` | 訂單編號（冗餘自mms_order_record） |
| `service_vendor_id` / `service_id` | `int` / `int` | 服務提供商/服務ID（冗餘欄位） |
| `inbr_account_id` | `uuid` | 提交評價的會員編號 |
| `overall_rating` | `int` | 整體評分，1~5星 |
| `rating_detail` | `json?` | 多維度評分，例如`{"attitude":5,"cleanliness":5}` |
| `review_content` | `str?` | 文字評價內容 |
| `media` | `json?` | 附加照片/影片網址，JSON陣列格式 |
| `status` | `str` | 評價狀態，`01`已送出（建立時預設值） |
| `is_deleted` | `bool` | 是否刪除 |
| `cre_id` | `uuid` | 新增者編號（通常等於`inbr_account_id`） |
| `cre_time` / `upd_time` | `datetime` / `datetime` | 新增/異動時間 |
| `upd_id` | `uuid?` | 異動者編號 |

**`PublicReviewOut`**（`GET /services/{service_id}/reviews` 專用，公開評價牆縮減欄位版本）

| 欄位 | 型別 | 說明 |
|---|---|---|
| `record_id` | `int` | 對應訂單ID |
| `overall_rating` | `int` | 整體評分 |
| `rating_detail` | `json?` | 多維度評分 |
| `review_content` | `str?` | 文字評價內容 |
| `media` | `json?` | 附加照片/影片網址 |
| `cre_time` | `datetime` | 評價時間 |

> 註：不含 `inbr_account_id`/`order_no`/`service_vendor_id`/`service_id`/`status`/`is_deleted`，刻意排除評價者身分與訂單/內部狀態資訊。

**`RatingSummaryOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `service_vendor_id` | `int` | 服務提供商ID |
| `service_id` | `int?` | 服務ID（未帶`service_id` query參數時為`null`，代表統計該廠商全部服務） |
| `review_count` | `int` | 符合條件的評價總數（`is_deleted=false`） |
| `average_rating` | `float?` | 平均評分，四捨五入至小數點後2位；無任何評價時為`null` |

---

## I2. 評價AI摘要（mms_review_summary_service / mms_review_summary_vendor）

新增功能，圖面未涵蓋。彙整 `mms_order_review` 的內容生成AI摘要，供使用者/供應商在不同顆粒度查看。本 server 只負責「讀取摘要」與「寫入/更新摘要結果」，**不呼叫 LLM**——實際呼叫 AI 模型產生摘要內容的流程屬於更上層服務（例如 bff_server 或獨立排程），這裡的 `PUT` 端點是給該流程寫回生成結果用。

兩張表皆為**覆寫式快取**設計：同一個 `service_id` / `service_vendor_id` 只保留最新1筆摘要，重新生成時直接覆蓋，不留歷史版本。

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 86 | `GET /services/{service_id}/review-summary` | 查看服務項目的評價AI摘要（使用者/供應商共用） | - | `ServiceReviewSummaryOut` | 新增功能 |
| 87 | `PUT /services/{service_id}/review-summary` | 寫入/覆蓋服務項目摘要（供AI生成流程呼叫） | `ServiceReviewSummaryUpsert` | `ServiceReviewSummaryOut`（200更新/201新建） | 新增功能 |
| 88 | `PATCH /services/{service_id}/review-summary/status` | 僅更新生成狀態（標記生成中/失敗，不需整包內容） | `ReviewSummaryStatusUpdate` | `ServiceReviewSummaryOut` | 新增功能 |
| 89 | `DELETE /services/{service_id}/review-summary` | 軟刪除摘要 | - | 無內容（204） | 新增功能 |
| 90 | `GET /vendors/{service_vendor_id}/review-summaries` | 供應商查看名下所有服務的摘要清單(分頁) | - | `PagedResponse<ServiceReviewSummaryOut>` | 新增功能 |
| 91 | `GET /vendors/{service_vendor_id}/review-summary` | 查看供應商整合總摘要 | - | `VendorReviewSummaryOut` | 新增功能 |
| 92 | `PUT /vendors/{service_vendor_id}/review-summary` | 寫入/覆蓋供應商總摘要 | `VendorReviewSummaryUpsert` | `VendorReviewSummaryOut`（200更新/201新建） | 新增功能 |
| 93 | `PATCH /vendors/{service_vendor_id}/review-summary/status` | 僅更新生成狀態 | `ReviewSummaryStatusUpdate` | `VendorReviewSummaryOut` | 新增功能 |
| 94 | `DELETE /vendors/{service_vendor_id}/review-summary` | 軟刪除摘要 | - | 無內容（204） | 新增功能 |

**業務規則**：

- `GET .../review-summary`：找不到資料（尚未生成過，或已被軟刪除）回 404，語意同 `GET /orders/{record_id}/review` 的「尚未評價」模式。
- `PUT .../review-summary`：完整覆寫語意。若 key 不存在則新建（回201），存在則整包覆蓋（回200），並將 `is_deleted` 重設為 `false`。呼叫端（生成流程）應在呼叫前自行查詢當下最新的評價聚合值（筆數/平均分/最新時間），連同 AI 生成結果一起送出；`generate_time` 由伺服器端填入當前時間，不接受呼叫端指定。
- `PATCH .../review-summary/status`：只更新 `generate_status`/`error_message`。若目標 key 尚無記錄，會自動建立一筆殼記錄（其餘欄位皆為 `null`），讓生成流程可以「先標記01生成中」再非同步寫入完整內容，不用等 LLM 回應才第一次寫資料。建立服務項目摘要的殼記錄時，`service_vendor_id` 由 `cms_homepage_service` 查得（值相等關聯，非FK）；若 `service_id` 本身不存在於 `cms_homepage_service`，回 404。供應商摘要的殼記錄無此限制（`service_vendor_id` 本身即為路徑參數，不驗證是否存在於 `cms_homepage_service_vendor`）。
- `DELETE`：軟刪除（`is_deleted=true`），之後 `GET` 視為 404，但不清空欄位內容，方便日後除錯或恢復。
- 因無身分驗證中介層，`PUT`/`PATCH` 的 `cre_id`/`upd_id` 皆填入系統識別碼 `SYSTEM_ACTOR_ID`（`00000000-0000-7000-8000-000000000000`），無法追蹤是哪個服務觸發的生成，比照 `catalog.py` 管理端 CRUD 的既有慣例。

**`ServiceReviewSummaryUpsert`**：`service_vendor_id: int`（必填）、`summary_content: str?`、`summary_highlights: json?`、`sentiment_stats: json?`、`source_review_count: int`（必填，預設0）、`source_avg_rating: float?`、`latest_review_cre_time: datetime?`、`ai_model: str?`、`generate_status: str`（必填，`00`/`01`/`02`/`03`）、`error_message: str?`

**`ServiceReviewSummaryOut`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `service_id` | `int` | 服務項目ID（PK，與`cms_homepage_service.id`共用值） |
| `service_vendor_id` | `int` | 服務提供商ID，冗餘欄位 |
| `summary_content` | `str?` | AI生成的摘要文字 |
| `summary_highlights` | `json?` | 結構化重點，例如`{"pros":[...],"cons":[...]}` |
| `sentiment_stats` | `json?` | 情感分布統計，例如`{"positive":12,"neutral":3,"negative":2}` |
| `source_review_count` | `int` | 本次摘要納入計算的評價筆數 |
| `source_avg_rating` | `float?` | 納入計算的評價平均分數快取 |
| `latest_review_cre_time` | `datetime?` | 納入計算的最新一筆評價建立時間 |
| `ai_model` | `str?` | 生成本筆摘要所用的AI模型名稱/版本 |
| `generate_status` | `str` | 生成狀態，`00`待生成/`01`生成中/`02`已完成/`03`失敗 |
| `generate_time` | `datetime?` | 本次摘要生成完成時間 |
| `error_message` | `str?` | 生成失敗時的錯誤訊息 |
| `is_deleted` | `bool` | 是否刪除 |
| `cre_id` / `cre_time` | `uuid` / `datetime` | 新增者/新增時間 |
| `upd_id` / `upd_time` | `uuid?` / `datetime` | 異動者/異動時間 |
| `is_stale` | `bool` | **計算欄位（非資料庫欄位）**：即時比對 `mms_order_review` 目前的 `COUNT(*)`/`MAX(cre_time)` 是否超過本筆記錄的 `source_review_count`/`latest_review_cre_time`，`true` 代表有新評價尚未納入摘要，建議觸發重新生成 |

**`VendorReviewSummaryUpsert`** / **`VendorReviewSummaryOut`**：結構同上，差異：無 `service_vendor_id` 冗餘欄位（PK本身即為 `service_vendor_id`）；多一個 `service_breakdown: json?` 欄位（各服務項目的簡易統計快取，JSON陣列，例如`[{"service_id":1,"review_count":10,"avg_rating":4.5}]`，避免前端需另外逐一查詢 `ServiceReviewSummaryOut`）；`source_review_count`/`source_avg_rating` 為跨全部服務項目的加總/平均；`is_stale` 比對範圍是該供應商名下全部服務的 `mms_order_review`。

**`ReviewSummaryStatusUpdate`**：`generate_status: str`（必填，`00`/`01`/`02`/`03`）、`error_message: str?`（可選，通常搭配`generate_status='03'`失敗時填寫）

---

## J. 系統

| # | Method / Path | 說明 | 回傳型別 |
|---|---|---|---|
| 77 | `GET /health` | 健康檢查 | `{"status": "ok"}`（無獨立model） |
| - | `GET /docs` | Swagger UI（互動式文件） | HTML |
| - | `GET /openapi.json` | OpenAPI 3.1 規格檔（本文件的權威資料來源） | JSON |

---

## 圖面功能覆蓋檢查（12項全部可實現）

| 圖 | Function | 對應 API |
|---|---|---|
| 圖1 | 尋找特定服務的廠商 | #18 |
| 圖1 | 建立feedback | #66（前置需 #42/#43 讀取表單結構） |
| 圖1 | 查看訂單 | #76 |
| 圖1 | 設定會員資訊 | #33 |
| 圖1 | 登入 | #31 |
| 圖2 | 查看feedback | #68 |
| 圖2 | 更新feedback status | #69 |
| 圖2 | 建立order | #71 |
| 圖2 | 查看order | #73 |
| 圖2 | 更新order | #74 |
| 圖2 | 設定商家資訊 | #14（商家屬性）+ #39（聯絡方式） |
| 圖2 | 登入 | #36 |
| - | 獲取廠商表單內容（新增功能，圖面未涵蓋） | #78 |
| - | 訂單評價（新增功能，圖面未涵蓋） | #79~#85 |
| - | 評價AI摘要（新增功能，圖面未涵蓋） | #86~#94 |

---

## 附錄：型別標記與資料庫層對照

| 文件標記 | Python/Pydantic 型別 | PostgreSQL 型別 | 備註 |
|---|---|---|---|
| `str` | `str` | `varchar`/`text` | - |
| `str?` | `str \| None` | 可為`NULL`的`varchar`/`text` | - |
| `int` | `int` | `int4`/`serial4` | - |
| `float` | `float` | `numeric(10,2)` | 金額/點數欄位 |
| `bool` | `bool` | `bool` | 目前僅`mms_order_record.is_deleted`用此型別，其餘表用`'0'`/`'1'`字串 |
| `uuid` | `uuid.UUID` | `uuid` | JSON中序列化為字串 |
| `uuid?` | `uuid.UUID \| None` | 可為`NULL`的`uuid` | - |
| `datetime` | `datetime.datetime` | `timestamptz` | JSON中序列化為ISO 8601字串 |
| `json` | `dict \| list` | `jsonb` | 可能是物件或陣列，依實際儲存內容而定 |

## 版本紀錄

- **2026-07-31**：由 `DB_API_table.md` 重新命名為 `API_Reference.md`，並對照實際 `api_server` 程式碼與 `/openapi.json` 逐條核對（77個端點路徑/方法100%一致），新增所有端點的 Request Body / 回傳型別完整說明。
- **2026-07-31**：新增 `GET /vendors/{service_vendor_id}/forms/full`（#78，見 `forms.py`），補上圖面未涵蓋的「獲取廠商表單內容」功能：輸入 service_vendor_id，回傳該廠商所有已審核且啟用表單的完整結構，避免前端需自行迴圈呼叫 #41+#43。
- **2026-08-01**：新增第 I 章「訂單評價」（`mms_order_review`，#79~#85，見 `routers/reviews.py`），支援「每筆訂單使用者可提交一份評價」的需求。新增評價會同步更新對應訂單的 `comment_status`。新增 `GET /services/{service_id}/reviews`（#85）作為公開評價牆，是全部端點中唯一不需身分驗證即可呼叫的端點，回傳縮減欄位的 `PublicReviewOut`。原第I章「系統」順延為第J章。端點總數由78增至85，已對照實際 `/openapi.json` 核對一致。
- **2026-08-01**：新增第 I2 章「評價AI摘要」（`mms_review_summary_service`/`mms_review_summary_vendor`，#86~#94，見 `routers/summaries.py`），支援使用者查看單一服務項目的評價AI摘要、供應商查看各服務摘要與整合總摘要的需求。本 server 只負責讀寫這兩張覆寫式快取表，不呼叫LLM。`PATCH .../status` 會在記錄不存在時自動建立殼記錄；`GET` 回應含即時計算欄位 `is_stale` 判斷摘要是否過期。端點總數由85增至94，已用本機 Docker PostgreSQL + uvicorn 實測全部9個端點行為正確。
- **2026-08-01**：`cms_homepage_service` 新增 `form_id: int?` 欄位（`ServiceCreate`/`ServiceUpdate`/`ServiceOut`），解決「一個服務項目要對應到哪張諮詢表單」查詢缺口（原設計只能反向查`pms_form.service_vendor_id`，無法從單一`service_id`直接取得對應表單）。不影響既有端點路徑，端點數量不變（仍94個），已用本機 Docker PostgreSQL + uvicorn 實測 GET/POST/PATCH/DELETE 皆正確讀寫此欄位。種子資料同步更新：`service_vendor_id=1`名下4個服務項目（洗衣機清洗/冷氣清洗/專業清潔/計時家事服務）皆設為`form_id=9`（既有測試表單），示範多個服務項目共用同一張表單，其餘4個服務項目維持`NULL`。
- **2026-08-01**：`label` 新增 `service_type: str?` 欄位（`LabelCreate`/`LabelUpdate`/`LabelOut`），支援「各服務類型自行維護專屬標籤」的需求（例如`type=6`餐廳訂位的「中餐廳」「泰式料理」）。名稱唯一性範圍由全域改為「同一`service_type`內」，通用標籤（`NULL`）另用 partial unique index 維持全域唯一。`GET /labels` 新增`service_type` query 參數，帶入時回傳「通用+該類型專屬」標籤聯集。端點數量不變（仍94個），已用本機 Docker PostgreSQL + uvicorn 實測唯一約束行為（同類型內重複名稱擋下、跨類型可同名、通用標籤全域唯一）與 CRUD 讀寫皆正確。種子資料新增2筆專屬標籤（中餐廳/泰式料理，`service_type="6"`）並示範關聯到既有的餐廳訂位服務項目。
- **2026-08-01**：修復 `POST /labels`/`PATCH /labels/{label_id}` 遇到唯一約束衝突時回傳裸 500（`IntegrityError`未被攔截）的既有問題（非本次`service_type`欄位新增造成，是`create_label`/`update_label`原本就缺少`accounts.py`/`geo.py`/`catalog.py`其他`create_*`端點皆有的「先查重複再建立」慣例，這次新增分區唯一約束後才被實測發現）。改為主動查詢並回 409，`PATCH`會排除自身這筆避免誤判。已用本機 Docker PostgreSQL + uvicorn 實測9種情境（同類型重複/跨類型同名/通用標籤全域唯一/PATCH改名衝突/排除自己邏輯）皆正確，不影響既有端點路徑與數量。

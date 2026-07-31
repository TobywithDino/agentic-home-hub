# API Reference — DB Access API Server

本文件是 `api_server/` 的完整 API 規格參考，記錄全部 78 個業務端點的路徑、方法、請求/回應型別，並標註每個端點對應圖面需求（`AI指示文件/DB_API_1.jpg`、`DB_API_2.jpg`）或設計來源。

> **本文件已於 2026-07-31 對照實際程式碼（`api_server/app/routers/*.py` 的路由定義 + FastAPI 自動生成的 `/openapi.json`）逐條核對，路徑與方法 100% 一致，無遺漏或錯誤。**

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
- [I. 系統](#i-系統)
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

`type` 代碼對照：`1`一般居家清潔 / `2`家電清洗 / `3`包裹寄送 / `6`餐廳訂位 / `9`美食外送 / `10`水電修繕 / `11`商城購物

**`ServiceCreate`**：`id`、`service_vendor_id`、`type`、`name`（皆必填）、`img_url`/`description`（可選）

**`ServiceUpdate`**：全部欄位皆可選

---

## C. 標籤（label, service_label）

| # | Method / Path | 說明 | Request Body | 回傳型別 | 來源 |
|---|---|---|---|---|---|
| 22 | `GET /labels` | 列表(分頁) | - | `PagedResponse<LabelOut>` | 管理端CRUD |
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

**`LabelCreate`**：`name: str`（必填）、`sort: int`（預設0）、`is_enable: str`（預設`"1"`）

**`LabelUpdate`**：`name`/`sort`/`is_enable` 皆可選

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

## I. 系統

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

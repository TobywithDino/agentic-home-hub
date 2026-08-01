# API 完整清單（最終版 v2，待檢查）

依據使用者最新確認事項調整：
1. **重新加回**縣市區域/服務商/服務項目/標籤的管理端 CRUD、表單結構建立修改 CRUD
2. `vendor_accounts`/`user_accounts`（登入帳號層級）與 `cms_homepage_service_vendor`/`cms_homepage_service`（商家/服務本身資訊層級）為不同層級，分開設計
3. **登入採最簡帳密驗證**，不做2FA流程。`is_2fa_enabled`/`totp_secret` 欄位保留在DB供未來擴充，但本階段**不提供2FA相關API**（enable/confirm/disable/兩階段登入皆移除）

所有查詢類（GET 列表）皆支援 `limit`/`offset` 分頁。所有刪除皆為軟刪除（更新 `is_deleted`），不做實體 DELETE。

---

## A. 縣市/行政區參考資料（sys_county, sys_district）

| # | Method / Path | 說明 | 來源 |
|---|---|---|---|
| 1 | `GET /counties` | 列表(分頁) | 支援表單「地區選單」題型 |
| 2 | `GET /counties/{county_code}` | 單筆 | 同上 |
| 3 | `POST /counties` | 新增縣市 | 管理端CRUD |
| 4 | `PATCH /counties/{county_code}` | 更新縣市(name/sort) | 管理端CRUD |
| 5 | `DELETE /counties/{county_code}` | 軟刪除 | 管理端CRUD |
| 6 | `GET /counties/{county_code}/districts` | 該縣市所有行政區(分頁) | 支援地區選單題型 |
| 7 | `GET /districts/{district_code}` | 單筆 | 同上 |
| 8 | `POST /districts` | 新增行政區 | 管理端CRUD |
| 9 | `PATCH /districts/{district_code}` | 更新行政區(name/zip/sort等) | 管理端CRUD |
| 10 | `DELETE /districts/{district_code}` | 軟刪除 | 管理端CRUD |

## B. 服務商/服務項目主檔（cms_homepage_service_vendor, cms_homepage_service）

| # | Method / Path | 說明 | 來源 |
|---|---|---|---|
| 11 | `GET /service-vendors` | 列表(分頁) | 管理端CRUD |
| 12 | `GET /service-vendors/{service_vendor_id}` | 查看商家資訊(name/description) | 慣例 |
| 13 | `POST /service-vendors` | 新增服務商 | 管理端CRUD |
| 14 | `PATCH /service-vendors/{service_vendor_id}` | 更新商家屬性(name/description) | **【圖2：設定商家資訊-商家屬性部分】** |
| 15 | `DELETE /service-vendors/{service_vendor_id}` | 軟刪除商家 | 管理端CRUD |
| 16 | `GET /services` | 列表(分頁，可用service_vendor_id/type篩選) | 管理端CRUD |
| 17 | `GET /services/{service_id}` | 單筆 | 慣例 |
| 18 | `GET /services/{service_id}/vendors` | 回傳所有符合service_id的service_vendor_id | **【圖1：尋找特定服務的廠商】** |
| 19 | `POST /services` | 新增服務項目 | 管理端CRUD |
| 20 | `PATCH /services/{service_id}` | 更新服務項目 | 管理端CRUD |
| 21 | `DELETE /services/{service_id}` | 軟刪除服務項目 | 管理端CRUD |

## C. 標籤（label, service_label）

| # | Method / Path | 說明 | 來源 |
|---|---|---|---|
| 22 | `GET /labels` | 列表(分頁) | 管理端CRUD |
| 23 | `GET /labels/{label_id}` | 單筆 | 慣例 |
| 24 | `POST /labels` | 建立標籤 | 管理端CRUD |
| 25 | `PATCH /labels/{label_id}` | 更新標籤(name/sort/is_enable) | 管理端CRUD |
| 26 | `DELETE /labels/{label_id}` | 軟刪除標籤 | 管理端CRUD |
| 27 | `GET /services/{service_id}/labels` | 該服務項目的標籤(分頁) | 慣例 |
| 28 | `PUT /services/{service_id}/labels/{label_id}` | 建立服務-標籤關聯 | 管理端CRUD |
| 29 | `DELETE /services/{service_id}/labels/{label_id}` | 移除服務-標籤關聯 | 管理端CRUD |

## D. 會員帳號（user_accounts）

| # | Method / Path | 說明 | 來源 |
|---|---|---|---|
| 30 | `POST /auth/user/register` | 建立會員帳號 | 登入前必要前置 |
| 31 | `POST /auth/user/login` | 帳密登入，回傳 `inbr_account_id`（最簡驗證，不含2FA分支） | **【圖1：登入】** |
| 32 | `GET /users/{inbr_account_id}` | 查看會員資料 | 慣例 |
| 33 | `PATCH /users/{inbr_account_id}` | 更新聯絡方式(姓名/手機/Email)/密碼 | **【圖1：設定會員資訊】** |
| 34 | `DELETE /users/{inbr_account_id}` | 軟刪除(is_deleted='1') | 慣例 |

> `is_2fa_enabled`/`totp_secret`/`last_login_time` 欄位保留於DB schema供未來擴充，本階段不提供對應API，`last_login_time` 由 `/login` 內部邏輯更新即可，不需獨立端點。

## E. 服務商後台帳號（vendor_accounts）

| # | Method / Path | 說明 | 來源 |
|---|---|---|---|
| 35 | `POST /auth/vendor/register` | 建立後台帳號 | 登入前必要前置 |
| 36 | `POST /auth/vendor/login` | 帳密登入，回傳 `service_vendor_id`（最簡驗證） | **【圖2：登入】** |
| 37 | `GET /vendors/{service_vendor_id}/accounts` | 該服務商下所有管理帳號(分頁)，對應schema註解「一個服務商可有多個管理帳號」 | 慣例 |
| 38 | `GET /vendors/{service_vendor_id}/accounts/{account_id}` | 單一帳號詳細 | 慣例 |
| 39 | `PATCH /vendors/{service_vendor_id}/accounts/{account_id}` | 更新該帳號聯絡方式(姓名/手機/Email)/密碼 | **【圖2：設定商家資訊-聯絡方式部分】** |
| 40 | `DELETE /vendors/{service_vendor_id}/accounts/{account_id}` | 軟刪除帳號 | 慣例 |

> 同D表，2FA欄位保留不提供API。

## F. 表單結構（pms_form 系列）

| # | Method / Path | 說明 | 來源 |
|---|---|---|---|
| 41 | `GET /forms` | 列表(分頁，可篩service_vendor_id/type) | 管理端CRUD |
| 42 | `GET /forms/{form_id}` | 表單主檔基本資訊 | 慣例，也是APP填單前置 |
| 43 | `GET /forms/{form_id}/full` | 組裝完整結構(group+topic+option+media+county關聯)，供填單頁渲染 | APP建立feedback前必須 |
| 44 | `POST /forms` | 建立表單 | 管理端CRUD |
| 45 | `PATCH /forms/{form_id}` | 更新表單內容(name/intro_content/notice_content/terms_content/is_enable等) | 管理端CRUD |
| 46 | `DELETE /forms/{form_id}` | 軟刪除表單 | 管理端CRUD |
| 47 | `PATCH /forms/{form_id}/review` | 更新審核狀態(review_status/reviewed_id/reviewed_time) | 管理端CRUD(窄範圍) |
| 48 | `GET /forms/{form_id}/groups` | 題組列表(分頁) | 管理端CRUD |
| 49 | `POST /forms/{form_id}/groups` | 建立題組 | 管理端CRUD |
| 50 | `PATCH /form-groups/{form_group_id}` | 更新題組 | 管理端CRUD |
| 51 | `DELETE /form-groups/{form_group_id}` | 刪除題組 | 管理端CRUD |
| 52 | `GET /forms/{form_id}/topics` | 題目列表(分頁) | 管理端CRUD |
| 53 | `POST /forms/{form_id}/topics` | 建立題目 | 管理端CRUD |
| 54 | `PATCH /form-topics/{topic_id}` | 更新題目 | 管理端CRUD |
| 55 | `DELETE /form-topics/{topic_id}` | 刪除題目 | 管理端CRUD |
| 56 | `GET /form-topics/{topic_id}/media` | 題目輔助圖片列表 | 管理端CRUD |
| 57 | `POST /form-topics/{topic_id}/media` | 新增輔助圖片 | 管理端CRUD |
| 58 | `DELETE /topic-media/{media_id}` | 刪除輔助圖片 | 管理端CRUD |
| 59 | `GET /form-topics/{topic_id}/options` | 題目選項列表 | 管理端CRUD |
| 60 | `POST /form-topics/{topic_id}/options` | 新增選項 | 管理端CRUD |
| 61 | `PATCH /topic-options/{option_id}` | 更新選項 | 管理端CRUD |
| 62 | `DELETE /topic-options/{option_id}` | 刪除選項 | 管理端CRUD |
| 63 | `GET /form-topics/{topic_id}/county-district-relations` | 題目縣市行政區對應列表 | 管理端CRUD |
| 64 | `POST /form-topics/{topic_id}/county-district-relations` | 新增對應關係 | 管理端CRUD |
| 65 | `DELETE /form-topics/{topic_id}/county-district-relations` | 刪除對應關係(依複合主鍵) | 管理端CRUD |

## G. 諮詢單回饋（pms_form_feedback）

| # | Method / Path | 說明 | 來源 |
|---|---|---|---|
| 66 | `POST /feedbacks` | 判斷feedback類型內容，建立諮詢單 | **【圖1：建立feedback】** |
| 67 | `GET /feedbacks/{feedback_no}` | 單筆詳細 | 慣例 |
| 68 | `GET /vendors/{service_vendor_id}/feedbacks` | 依service_vendor_id抓取feedbacks(分頁) | **【圖2：查看feedback】** |
| 69 | `PATCH /feedbacks/{feedback_no}/status` | 更新 is_read 或 status | **【圖2：更新feedback status】** |
| 70 | `GET /users/{inbr_account_id}/feedbacks` | 會員查自己的諮詢單(分頁) | 慣例 |

## H. 訂單（mms_order_record）

| # | Method / Path | 說明 | 來源 |
|---|---|---|---|
| 71 | `POST /orders` | 建立訂單，寫入mms_order_record | **【圖2：建立order】** |
| 72 | `GET /orders/{record_id}` | 單筆訂單詳細 | 慣例 |
| 73 | `GET /vendors/{service_vendor_id}/orders` | 依service_vendor_id抓取orders(分頁) | **【圖2：查看order】** |
| 74 | `PATCH /vendors/{service_vendor_id}/orders/{record_id}` | 依service_vendor_id更新該筆特定訂單 | **【圖2：更新order】** |
| 75 | `GET /users/{inbr_account_id}/orders` | 會員查自己的訂單(不含feedback，分頁) | 慣例 |
| 76 | `GET /users/{inbr_account_id}/order-summary` | 抓該會員未處理feedback + 對應order，兩者拼接回傳(分頁) | **【圖1：查看訂單】** |

## I. 系統

| # | Method / Path | 說明 |
|---|---|---|
| 77 | `GET /health` | 健康檢查 |
| - | `/docs`、`/openapi.json` | FastAPI 自動產生 |

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

---

## 與前版差異摘要

- **加回**：A表縣市/行政區CRUD(#3-5,8-10)、B表服務商/服務項目CRUD(#11,13,15,16,19-21)、C表整組標籤功能(#22-29)、F表表單結構完整CRUD(#44-65)
- **移除**：D/E表2FA相關端點（enable/confirm/disable/兩階段登入），登入恢復為單一階段帳密驗證
- **保留不變**：訂單/feedback相關業務端點(G、H表)與圖面對照關係

共 **77 個業務端點 + 1 個健康檢查**，涵蓋所有資料表的CRUD需求，且圖1、圖2共12項function逐一對照皆可實現。

請檢查以上清單，確認後我會開始搭建 FastAPI 專案骨架（router分層 + Pydantic schema + DB連線層）並用本地環境實測。

# database/ — DB 架構與種子資料說明

本資料夾是資料庫 DDL、種子資料、建置腳本的唯一權威來源。此文件說明整體架構（16張表、彼此關係）以及每張表的欄位有沒有對應的種子資料值，方便開發時知道哪些欄位可以直接拿現成資料測試、哪些欄位是空的需要自己補。

> 完整的建置步驟（Docker啟動、跑腳本、預期輸出）見 `../部署手冊.md` 第3章。API 端點與這些表的對應關係見 `../API_Reference.md`。

## 目錄

- [1. 整體架構](#1-整體架構)
- [2. 各表詳細說明與種子資料覆蓋率](#2-各表詳細說明與種子資料覆蓋率)
- [3. 種子資料檔案對照](#3-種子資料檔案對照)
- [4. 已知的資料完整性限制](#4-已知的資料完整性限制)

---

## 1. 整體架構

16 張表分成 7 個功能群組，彼此用「值相等」關聯（**沒有實體 FOREIGN KEY 約束**，是刻意的鬆耦合設計，跨表一致性由應用層負責）：

```
sys_county ──county_code── sys_district
   （縣市/行政區代碼參考資料，供表單「地區選單」題型與地址欄位使用）

cms_homepage_service_vendor ──service_vendor_id── cms_homepage_service
   （服務商 / 服務商底下的服務項目）
        │                                    │
        │                              service_id
        │                                    │
        │                              service_label ──label_id── label
        │                              （服務項目與標籤的多對多橋接表）
        │
   vendor_accounts（服務商後台登入帳號，多個帳號可屬於同一service_vendor_id）

user_accounts（會員登入帳號，id 即為 inbr_account_id，串接訂單與諮詢單）

pms_form（表單主檔）──form_id──┬── pms_form_group（題組）
                                ├── pms_form_topic（題目）──topic_id──┬── pms_topic_media（輔助圖片）
                                │                                      ├── pms_topic_option（選項）
                                │                                      └── pms_topic_county_district_relation（縣市行政區對應）
                                └── pms_form_feedback（表單回饋，使用者填單後的紀錄）

mms_order_record（訂單主檔）──record_id── mms_order_review（訂單評價，1:0..1，PK共用）
```

**跨群組關聯**（皆為值相等，非FK）：
- `user_accounts.id` == `mms_order_record.inbr_account_id` == `pms_form_feedback.inbr_account_id` == `mms_order_review.inbr_account_id`
- `cms_homepage_service_vendor.id` == `cms_homepage_service.service_vendor_id` == `vendor_accounts.service_vendor_id` == `pms_form.service_vendor_id` == `mms_order_record.service_vendor_id` == `mms_order_review.service_vendor_id`
- `cms_homepage_service.id` == `service_label.service_id` == `mms_order_record.service_id` == `pms_form_feedback.service_id` == `mms_order_review.service_id`

## 2. 各表詳細說明與種子資料覆蓋率

以下「種子資料覆蓋率」欄位標記方式：
- ✅ 全部種子資料筆數都有值
- ⚠️ 部分筆數有值（標註實際筆數，例如`33/99`）
- ❌ 種子資料裡全部是`NULL`/空值（不代表欄位設計錯誤，只是目前範例資料沒填）

### A. 縣市/行政區（`縣市區域檔.sql`）

**`sys_county`**（22筆，PK: `code`）— 縣市代碼參考資料

| 欄位 | 說明 | 種子資料 |
|---|---|---|
| `code` | 縣市代碼（2字元） | ✅ 22/22 |
| `name` | 縣市名稱 | ✅ 22/22 |
| `sort` | 排序 | ✅ 22/22 |
| `is_deleted` | `0`正常/`1`刪除 | ✅ 22/22（皆為`0`） |
| `upd_time`/`cre_time` | 異動/新增時間 | ✅ 22/22 |
| `upd_id` | 異動者編號 | ❌ 0/22 |
| `cre_id` | 新增者編號 | ✅ 22/22 |

**`sys_district`**（200筆，PK: `code`）— 行政區代碼參考資料，欄位覆蓋狀況與`sys_county`相同模式（`upd_id`全空，其餘全滿）。額外欄位：`county_code`（所屬縣市）、`name_with_county`（行政區+縣市名稱組合）、`zip`（郵遞區號）皆為 ✅ 200/200。

### B. 服務商/服務項目主檔（`cms_homepage_service.sql`）

**`cms_homepage_service_vendor`**（6筆，PK: `id`）— 首頁服務商主檔（無時間戳/操作者欄位，是這16張表中結構最簡單的）

| 欄位 | 說明 | 種子資料 |
|---|---|---|
| `id` | 服務商ID（需手動指定，非自增） | ✅ 6/6（值：1,2,5,10,11,14，非連續） |
| `name` | 服務商名稱 | ✅ 6/6 |
| `description` | 服務商描述 | ✅ 6/6 |

**`cms_homepage_service`**（8筆，PK: `id`）— 首頁服務項目主檔

| 欄位 | 說明 | 種子資料 |
|---|---|---|
| `id` | 服務項目ID（手動指定） | ✅ 8/8（值：1,2,3,4,5,9,16,17，非連續） |
| `service_vendor_id` | 所屬服務商ID | ✅ 8/8 |
| `type` | 服務類型代碼 | ✅ 8/8（涵蓋`1`/`2`/`3`/`6`/`9`/`10`） |
| `name` | 服務項目名稱 | ✅ 8/8 |
| `img_url` | 圖片網址 | ✅ 8/8 |
| `description` | 說明（可含HTML） | ⚠️ 5/8（3筆為空字串） |

### C. 標籤（`account_and_label.sql`）

**`label`**（6筆，PK: `id`自增）— 服務特徵標籤主檔（`name`有UNIQUE約束）

全部欄位 ✅ 滿，除了 `upd_id` ❌ 0/6（新增時尚無異動者）。6筆標籤內容：寵物友善、24小時營業、專業認證、免費估價、到府服務、快速到達。

**`service_label`**（10筆，PK: 複合`service_id`+`label_id`）— 服務與標籤多對多橋接表

全部欄位 ✅ 滿（`service_id`/`label_id`/時間戳/`cre_id`），`upd_id` ❌ 0/10。涵蓋 service_id：1,4,5,9,16,17。

**`vendor_accounts`**（3筆，PK: `id` uuid）— 服務商後台登入帳號

| 欄位 | 說明 | 種子資料 |
|---|---|---|
| `id`/`service_vendor_id`/`account`/`password_hash` | 帳號基本資訊 | ✅ 3/3 |
| `contact_name`/`contact_mobile`/`contact_email` | PII加密欄位（bytea） | ❌ 0/3（明文皆為`null`，見下方PII說明） |
| `contact_name_hash`/`contact_mobile_hash`/`contact_email_hash` | 對應hash | ✅ 3/3 |
| `is_2fa_enabled`/`is_enable`/`is_deleted` | 狀態旗標 | ✅ 3/3（皆為`0`/`1`預設值） |
| `totp_secret`/`last_login_time` | 2FA密鑰/最後登入 | ❌ 0/3（功能保留未使用） |
| `upd_time`/`cre_time`/`cre_id` | 時間戳/新增者 | ✅ 3/3 |
| `upd_id` | 異動者編號 | ❌ 0/3 |

測試帳號：`vendor01@example.com`（service_vendor_id=1）、`vendor02@example.com`（=2）、`vendor03@example.com`（=5），密碼皆為 `Test@1234`（bcrypt雜湊儲存）。

**`user_accounts`**（4筆，PK: `id` uuid）— 會員登入帳號，欄位覆蓋狀況與`vendor_accounts`完全相同模式（PII明文❌全空、hash✅全滿、2FA相關❌全空）。

測試帳號：`user01@example.com`~`user04@example.com`，密碼皆為 `Test@1234`。其中 `user01`（`019c0464-2d01-73f0-9f9b-d1392fdb941a`）與 `user02`（`019eee3f-841e-7048-ae67-0955b144f4f8`）是訂單/評價種子資料中最常出現的帳號。

### D/E. PII 加密欄位為何全是空的

`vendor_accounts`/`user_accounts`/`pms_form_feedback`/`mms_order_record` 這幾張表的 `contact_name`/`member_name`/`contact_mobile` 等 `bytea` 欄位，種子資料 JSON 裡實際存的是**別的環境用不同金鑰加密過的密文位元組**，本地或任何新環境沒有對應的 `PII_ENCRYPTION_KEY_B64` 金鑰可以解密，這是預期行為（見 `api_server/README.md` 的PII加密欄位說明），不是資料遺漏。`import_seed_data.py` 匯入時會嘗試把這些密文字串還原成bytes寫入，寫入本身會成功，只是任何環境都無法解密還原成原始明文——`_hash`欄位（SHA-256）才是這幾張表裡真正「可比對查詢」的PII相關欄位。

### F. 表單結構（`諮詢單相關table.sql`）

**`pms_form`**（1筆，PK: `id`自增）— 表單主檔，僅有 `form_id=9`（測試表單）一筆。

| 欄位 | 種子資料 |
|---|---|
| `id`/`service_vendor_id`/`type`/`sub_type`/`name`/`intro_content`/`notice_content`/`terms_content`/`review_status`/`is_enable`/`is_deleted`/時間戳/`upd_id`/`cre_id` | ✅ 1/1 |
| `reviewed_id`/`reviewed_time` | ❌ 0/1（尚未被審核過） |
| `feature` | ❌ 0/1 |

**`pms_form_group`**（3筆，PK: `id`自增）— 題組，全屬於`form_id=9`。欄位除`feature` ❌ 0/3外皆 ✅ 滿。3個題組：「服務項目與現場資訊」、「聯絡資料」、「聯絡方式與服務地址」。

**`pms_form_topic`**（7筆，PK: `id`自增）— 題目，全屬於`form_id=9`。

| 欄位 | 種子資料 |
|---|---|
| `id`/`form_id`/`form_group_id`/`type`/`is_required`/`sort`/時間戳/`upd_id`/`cre_id` | ✅ 7/7 |
| `remark` | ⚠️ 2/7 |
| `feature` | ⚠️ 4/7（單選/複選/地區選單類題目才有設定JSON） |
| `is_number_only`/`minimum_medias_upload`/`maximum_medias_upload`/`specified_medias_upload`/`start_date_offset_days`/`end_date_offset_days` | ❌ 0/7（這些是特定題型才用到的欄位，種子資料涵蓋的7個題目皆未使用到） |

7個題目涵蓋類型：`4`複選(x2)、`6`上傳照片、`10`聯絡資料不含地址、`1`簡答、`3`單選、`5`地區選單。

**`pms_topic_media`**（1筆，PK: `id`自增）— 題目輔助圖片，全部欄位 ✅ 1/1（僅`topic_id=108`一筆，注意這個`topic_id`不在上方7筆`pms_form_topic`種子資料範圍內，屬於孤兒資料，見第4節說明）。

**`pms_topic_option`**（6筆，PK: `id`自增）— 題目選項

| 欄位 | 種子資料 |
|---|---|
| `id`/`form_id`/`topic_id`/`option_name`/`is_quantity`/`min_quantity`/`max_quantity`/`is_quoted_separately`/`sort`/時間戳/`upd_id`/`cre_id` | ✅ 6/6 |
| `feature` | ⚠️ 4/6 |
| `unit_price`/`unit`/`remark` | ❌ 0/6 |

**`pms_topic_county_district_relation`**（1筆，PK: 複合`form_id`+`topic_id`+`eff_ts_from`+`county_code`+`district_code`）— 全部欄位 ✅ 1/1，除`upd_id` ❌ 0/1。

**`pms_form_feedback`**（1筆，PK: `feedback_no`）— 表單回饋，模擬使用者實際填單後的結果

| 欄位 | 種子資料 |
|---|---|
| `feedback_no`/`service_id`/`platform_code`/`form_id`/`feedback_content`/`form_type`/`is_read`/`status`/`preferred_contact_time`/`contact_address_county`/`contact_address_district`/`inbr_account_id`/時間戳/`upd_id` | ✅ 1/1 |
| `contact_name`/`contact_mobile`/`contact_email`/`contact_address_detail`（PII明文） | ✅ 1/1（**注意**：這張表的PII欄位種子資料裡確實有值，跟D/E章節說明的`vendor_accounts`/`user_accounts`不同，但同樣是別的環境加密的密文，本地無法解密還原） |
| `contact_name_hash`/`contact_mobile_hash`/`contact_email_hash`/`contact_address_detail_hash` | ✅ 1/1 |
| `contact_landline`/`contact_landline_hash` | ❌ 0/1 |
| `description` | ❌ 0/1 |

### G. 訂單（`mms_order_record.sql`）

**`mms_order_record`**（99筆，PK: `record_id` bigserial）— 目前種子資料量最大的表，欄位種類也最多，適合拿來測試分頁/篩選類端點

| 欄位 | 種子資料 |
|---|---|
| `record_id`/`order_no`/`service_vendor_id`/`service_id`/`platform_code`/`inbr_account_id`/`order_type`/`order_status`/`order_time`/各金額欄位（6個,含`deposit_amount`~`refund_amount`）/各點數欄位（4個）/`point_status`/`order_items`/`comment_status`/`is_deleted`/`cre_id`/`cre_time`/`upd_id`/`upd_time` | ✅ 99/99 |
| `member_name`/`member_phone`/`member_email`(+對應hash) | ⚠️ 33/99（PII明文為別環境密文,同前述說明） |
| `complete_time` | ⚠️ 82/99 |
| `cancel_time` | ⚠️ 31/99 |
| `vendor_data` | ⚠️ 41/99 |
| `confirm_time` | ⚠️ 15/99 |
| `deposit_time` | ⚠️ 14/99 |
| `remark` | ⚠️ 9/99 |
| `service_time` | ⚠️ 9/99 |
| `source_file`/`import_batch` | ⚠️ 6/99 |
| `quote_approved_by`/`quote_approved_time`/`quote_no` | ⚠️ 5/99（僅走過報價流程的訂單才有） |
| `cancel_reason`/`refund_reason` | ⚠️ 2/99 |
| `point_grant_time` | ⚠️ 2/99 |

`order_status`分布：`80`已完成(54筆)、`99`已退款(26筆)、`12`已支付訂金待報價(9筆)、`98`部分退款(3筆)、`70`已完成待核銷(3筆)、`03`已確認(2筆)、`90`已取消(1筆)、`11`待訂金支付(1筆)。`comment_status`分布：`00`無須評價(78筆)、`01`未評價(16筆)、`02`已評價(5筆，對應下方`mms_order_review`)。

### H. 訂單評價（`mms_order_review.sql`，新增功能）

**`mms_order_review`**（5筆，PK: `record_id`，**與`mms_order_record.record_id`共用值，非獨立序列**）

| 欄位 | 種子資料 |
|---|---|
| `record_id`/`order_no`/`service_vendor_id`/`service_id`/`inbr_account_id`/`overall_rating`/`rating_detail`/`status`/`is_deleted`/`cre_id`/`cre_time`/`upd_time` | ✅ 5/5 |
| `review_content` | ⚠️ 4/5（刻意留1筆`null`，用於測試「只評分不寫評語」情境） |
| `media` | ⚠️ 1/5（刻意只留1筆有附圖，測試`media`欄位的JSON陣列格式） |
| `upd_id` | ❌ 0/5（尚未被修改過） |

5筆評價對應的訂單：`record_id` 2010/2023/2025/2026/2027，皆為`order_status='80'`（已完成）且插入評價後`comment_status`已同步改為`'02'`。評分分布：3~5星（vendor_id=1有4筆，平均4.0分；vendor_id=11有1筆，5.0分），刻意涵蓋不同分數區間方便測試`AVG()`聚合查詢。

## 3. 種子資料檔案對照

| 檔案 | 對應表 | 筆數 |
|---|---|---|
| `縣市區域範例資料.json` | `sys_county`, `sys_district` | 22 + 200 |
| `相關主檔設定.json` | `cms_homepage_service_vendor`, `cms_homepage_service` | 6 + 8 |
| `帳號與標籤範例資料.json` | `label`, `service_label`, `vendor_accounts`, `user_accounts` | 6 + 10 + 3 + 4 |
| `諮詢單相關範例資料.json` | `pms_form`, `pms_form_group`, `pms_form_topic`, `pms_topic_media`, `pms_topic_option`, `pms_topic_county_district_relation`, `pms_form_feedback` | 1+3+7+1+6+1+1 |
| `order_record範例資料.json`（`.csv`為同內容備用格式） | `mms_order_record` | 99 |
| `order_review範例資料.json` | `mms_order_review` | 5 |

**匯入順序**（`import_seed_data.py`自動處理，見`../部署手冊.md`第3.3節）：DDL建表 → 主檔種子資料（縣市/服務商/帳號/表單） → 交易資料（訂單/評價，依賴主檔先存在） → 校正serial主鍵序列。

## 4. 已知的資料完整性限制

以下是種子資料本身既有的不一致之處，供開發時留意，非本次文件撰寫新發現的bug：

1. **`pms_topic_media`的`topic_id=108`不存在於`pms_form_topic`種子資料的7筆範圍內**（該7筆id為89/54/88/94/102/95/103）。這是孤兒資料，可能是原始資料集匯出時的不完整片段。因為表之間沒有FK約束，這不會導致匯入失敗，但用`topic_id=108`查詢`pms_form_topic`會查不到對應題目。
2. **`pms_form_feedback`裡的`feedback_content` JSON內容引用了`topicId: 97/98/100/55`等題目ID**，同樣不在種子的7筆`pms_form_topic`範圍內，屬於同一批不完整片段的資料。
3. **PII加密欄位（`bytea`）在任何本地/新環境都無法解密**：這些欄位種子資料裡的內容是原始資料來源環境用特定金鑰加密的結果，沒有人手上有對應金鑰。若要測試PII加解密功能完整流程，建議另外用`api_server`自己的加密函式產生一筆新資料寫入測試，而不是依賴既有種子資料。
4. **`cms_homepage_service_vendor`/`cms_homepage_service`的`id`需手動指定**：這兩張表沒有`serial`/`bigserial`，種子資料用不連續的id值（如1,2,5,10,11,14），新增資料時務必先確認id沒有衝突，`import_seed_data.py`也不會幫這兩張表校正序列（因為它們本來就不是序列類型）。

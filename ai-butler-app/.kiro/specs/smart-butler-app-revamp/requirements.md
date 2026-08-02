# Requirements Document

## Introduction

本文件定義「AI 生活管家」消費者端 Flutter App（以下稱 Butler_App）的改版需求。專案為 2026 雲湧智生：臺灣生成式 AI 應用黑客松競賽參賽作品，命題單位為統一資訊，命題主題為「AI 生活管家：智慧社區服務需求理解與媒合平台」，命題類別為智慧零售。比賽於 2026/8/1 現場進行，現場提供 AWS 服務額度。

改版目標由使用者實際痛點驅動：

1. 畫面轉場缺乏一致的動畫設計，操作手感不流暢。
2. 缺少登入畫面與個人帳戶資訊頁。
3. AI 對話介面過於簡陋，缺乏「AI 智能管家」的產品質感。
4. 服務流程錯誤：目前由首頁服務類別直接跳到填單，應改為「服務類別 → 服務商列表（可篩選查詢）→ 服務商詳情 → 填寫諮詢單」。
5. 移除台語語音辨識，保留一般語音輸入（zh-TW）。

現有 Flutter 專案已具備 `lib/screens`、`lib/widgets`、`lib/models`、`lib/services/api_service.dart`、`lib/router/app_router.dart`、`lib/constants` 的雛形，本次改版在此基礎上重構。

### 職責界線

| 項目 | 負責方 | 本 spec 是否涵蓋 |
| --- | --- | --- |
| 消費者端 Flutter App（GUI、狀態管理、mock 資料層） | 本使用者 | 涵蓋 |
| 後端 Server、API 格式設計、AI 服務代理 | 隊友 A | 不涵蓋（僅定義 App 端接點期望與 TODO 標註） |
| 資料庫（PostgreSQL schema、個資加密與 hash） | 隊友 A | 不涵蓋 |
| 廠商後台網頁（B 端） | 隊友 B | 不涵蓋 |

因後端與 App 並行開發，Butler_App 的所有資料存取必須經過可抽換的 Repository_Layer，
比賽現場只需切換設定即可從 mock 換成真實 API。

### 優先級定義

| 標記 | 說明 |
| --- | --- |
| P0 | 比賽 demo 必備，現場流程缺一不可 |
| P1 | 加分項，評審可見的體驗與完整度提升 |
| P2 | Optional，時間充裕才實作 |

## Glossary

### 系統與元件（EARS 主詞）

- **Butler_App**：消費者端 Flutter 應用程式整體。
- **App_Shell**：包住底部導覽的外框 Widget，管理分頁切換與狀態保留。
- **Login_Screen**：帳號密碼登入畫面。
- **Auth_Repository**：登入／登出能力的抽象介面與其實作。
- **Session_Store**：保存 inbr_account_id 與存取憑證的本機安全儲存元件。
- **Route_Guard**：依登入狀態決定可進入頁面的導覽守衛。
- **Account_Screen**：個人帳戶資訊頁（檢視／編輯會員資訊、設定、登出）。
- **Account_Repository**：會員資訊讀取與更新的抽象介面。
- **Home_Screen**：AI 生活管家首頁。
- **Service_Catalog**：服務類別清單與其 service_id 對應關係的資料來源。
- **Service_Catalog_Screen**：底部導覽「服務」分頁的內容畫面，呈現全部服務類別清單與跨類別搜尋入口。
- **Vendor_List_Screen**：某服務類別下的服務商列表頁。
- **Vendor_Filter_Panel**：服務商列表的篩選與排序面板。
- **Vendor_Detail_Screen**：服務商詳情頁。
- **Vendor_Repository**：服務商查詢的抽象介面。
- **Html_Content_Renderer**：將後端 HTML 內容轉為原生排版的渲染元件。
- **Form_Screen**：彈性諮詢單填寫畫面。
- **Form_Repository**：表單定義讀取的抽象介面。
- **Dynamic_Form_Renderer**：依表單定義動態產生題目 Widget 的元件。
- **Form_Validator**：表單必填與格式驗證元件。
- **Quotation_Calculator**：估價表單金額試算元件。
- **Draft_Store**：表單草稿的本機暫存元件。
- **Feedback_Submitter**：組出並送出回饋單（諮詢單）請求的元件。
- **Media_Uploader**：照片壓縮與上傳元件。
- **Butler_Chat_Screen**：AI 智能管家對話畫面。
- **Ai_Butler_Service**：AI 能力（需求理解、服務分類、表單預填、追問）的抽象介面。
- **Voice_Input_Module**：語音轉文字輸入元件。
- **Order_List_Screen**：我的諮詢單與我的訂單清單頁。
- **Order_Detail_Screen**：單筆諮詢單或訂單的詳情頁。
- **Order_Repository**：訂單與諮詢單查詢的抽象介面。
- **Order_Status_Mapper**：將 order_type 與 order_status 轉為顯示文字與顏色的對應元件。
- **Notification_Handler**：推播通知註冊、接收與深層連結處理元件。
- **Design_System**：色票、字體階層、圓角、陰影、間距與元件樣式的集中定義。
- **Motion_System**：轉場、動畫時長與曲線的集中定義。
- **Theme_Manager**：淺色／深色主題切換元件。
- **Repository_Layer**：所有資料存取抽象介面與其 mock／HTTP 實作的集合。
- **Api_Client**：HTTP 請求發送、逾時、重試與錯誤轉換的統一入口。
- **Environment_Config**：環境設定，含 dataSource、aiSource、baseUrl 與 guestBrowsing 四個設定值。
- **guestBrowsing**：訪客瀏覽開關。為 false 時未登入使用者只能停留在 Login_Screen；為 true 時未登入使用者可瀏覽首頁、服務商列表、服務商詳情與對話畫面，但填單與訂單相關畫面仍需登入。預設為 false。

### 領域名詞

- **inbr_account_id**：會員唯一識別碼，UUID v7 格式，登入成功後由後端回傳，後續請求需帶上。
- **service_id**：服務類別識別碼，對應 `cms_homepage_service.type`（見附錄 A）。
- **service_vendor_id**：服務商（廠商）識別碼，同一 service_id 下可有多個 service_vendor_id。
- **諮詢單 / feedback**：使用者填寫彈性表單後於後端建立的 `pms_form_feedback` 紀錄，尚未轉為訂單。
- **feedback_no**：回饋單編號，建立成功後回傳給使用者查詢。
- **pms_form**：表單主檔，含 type（1 C 端無現場評估 / 2 C 端需評估 / 3 B 端 / 4 轉訂單流程 / 5 客服）、sub_type（1 一般表單 / 2 估價表單）、intro_content、notice_content、terms_content。
- **pms_form_group**：表單題組，依 sort 排序。
- **pms_form_topic**：表單題目，含 title、remark、is_required、sort 與題型代碼（見 Requirement 7）。
- **pms_topic_option**：題目選項，含 option_name、unit_price、unit、is_quantity、min_quantity、max_quantity、is_quoted_separately、remark。
- **pms_topic_media**：題目輔助圖片。
- **mms_order_record**：訂單紀錄，含 order_no、order_type、order_status（見附錄 B）。
- **platform_code**：來源平台代碼，OP APP 固定為 `01`。
- **preferred_contact_time**：希望聯絡時段，1 上午 / 2 下午 / 3 皆可。
- **sys_county / sys_district**：縣市與行政區代碼表。
- **D 日偏移**：日期題可選範圍以「今日」為基準，加上 start_date_offset_days 與 end_date_offset_days。
- **MCP Server**：Model Context Protocol 伺服器，命題要求將服務能力包裝成 MCP Server 供外部 Agent 調用；由後端提供，Butler_App 為其消費端之一。
- **骨架載入 / skeleton**：資料未就緒時顯示的版面佔位動畫。
- **共享軸轉場**：Material Design shared axis transition，同層或父子層導覽的位移＋淡入組合。

## Requirements

### Requirement 1: 帳號登入（P0）

**User Story:** 作為社區住戶，我想以帳號密碼登入 App，以便系統辨識我的會員身分並保存我的諮詢單與訂單。

#### Acceptance Criteria

1. WHERE Environment_Config 的 guestBrowsing 為 false, WHEN Butler_App 啟動且 Session_Store 中沒有有效憑證, THE Butler_App SHALL 顯示 Login_Screen。
2. WHERE Environment_Config 的 guestBrowsing 為 true, WHEN Butler_App 啟動且 Session_Store 中沒有有效憑證, THE Butler_App SHALL 顯示 Home_Screen 並在右上角顯示「登入」按鈕以取代會員頭像按鈕。
3. THE Login_Screen SHALL 顯示帳號輸入欄、密碼輸入欄、密碼顯示切換鍵與登入按鈕。
4. IF 使用者在帳號欄或密碼欄為空的情況下按下登入按鈕, THEN THE Login_Screen SHALL 在對應欄位下方顯示欄位必填錯誤文字並保留已輸入內容。
5. WHEN 使用者在帳號欄與密碼欄皆非空的情況下按下登入按鈕, THE Auth_Repository SHALL 呼叫登入接點並取得包含 inbr_account_id 的回應。
6. WHILE 登入請求進行中, THE Login_Screen SHALL 顯示載入指示器並停用登入按鈕。
7. WHEN 登入回應成功, THE Butler_App SHALL 以淡入轉場導向 Home_Screen 並清除導覽堆疊中的 Login_Screen。
8. IF 登入接點回傳帳號或密碼錯誤, THEN THE Login_Screen SHALL 顯示「帳號或密碼錯誤」訊息並保留帳號欄內容。
9. IF 登入接點回傳網路錯誤或逾時, THEN THE Login_Screen SHALL 顯示連線失敗訊息與重試按鈕。
10. WHERE Environment_Config 的 dataSource 設定為 mock, THE Auth_Repository SHALL 接受預設 demo 帳號並回傳固定的 UUID v7 格式 inbr_account_id。
11. THE Login_Screen SHALL 顯示「demo 快速登入」按鈕，按下後以預設 demo 帳號完成登入流程。
12. THE Login_Screen SHALL 以 Design_System 定義的品牌視覺呈現管家角色圖像與品牌標語。

### Requirement 2: 登入狀態持久化、登出與導向規則（P0）

**User Story:** 作為使用者，我想在重啟 App 後維持登入狀態，並能主動登出，以便安全且方便地使用服務。

#### Acceptance Criteria

1. WHEN 登入成功, THE Session_Store SHALL 將 inbr_account_id 與存取憑證寫入裝置的安全儲存區。
2. WHEN Butler_App 重新啟動且 Session_Store 中存在有效憑證, THE Butler_App SHALL 直接顯示 Home_Screen。
3. THE Api_Client SHALL 在每個需要身分的請求中帶入 Session_Store 保存的存取憑證與 inbr_account_id。
4. THE Route_Guard SHALL 允許未登入使用者進入 Login_Screen。
5. THE Route_Guard SHALL 將 Form_Screen、Order_List_Screen、Order_Detail_Screen 與 Account_Screen 歸類為需登入路徑，並將 Home_Screen、Vendor_List_Screen、Vendor_Detail_Screen 與 Butler_Chat_Screen 歸類為可訪客瀏覽路徑。
6. WHERE Environment_Config 的 guestBrowsing 為 false, WHEN 未登入使用者嘗試進入需登入路徑或可訪客瀏覽路徑, THE Route_Guard SHALL 導向 Login_Screen 並記錄原目標路徑。
7. WHERE Environment_Config 的 guestBrowsing 為 true, WHEN 未登入使用者嘗試進入可訪客瀏覽路徑, THE Route_Guard SHALL 允許該次導覽。
8. WHERE Environment_Config 的 guestBrowsing 為 true, WHEN 未登入使用者嘗試進入需登入路徑, THE Route_Guard SHALL 導向 Login_Screen 並記錄原目標路徑。
9. WHEN 使用者由 Route_Guard 導向 Login_Screen 後完成登入, THE Butler_App SHALL 導向先前記錄的原目標路徑。
10. THE Environment_Config SHALL 將 guestBrowsing 的預設值設為 false。（訪客瀏覽為 P2）
11. WHEN 使用者在 Account_Screen 按下登出並於確認對話框選擇確定, THE Session_Store SHALL 清除所有已保存的身分資料。
12. WHEN 登出完成, THE Butler_App SHALL 導向 Login_Screen 並清除導覽堆疊。
13. IF 任一後端接點回傳 HTTP 401, THEN THE Api_Client SHALL 清除 Session_Store 並使 Butler_App 導向 Login_Screen 並顯示「登入已逾期，請重新登入」訊息。

### Requirement 3: 個人帳戶資訊（P0）

**User Story:** 作為會員，我想從右上角頭像進入帳戶頁檢視與修改我的聯絡方式與密碼，以便廠商能正確聯繫我。

#### Acceptance Criteria

1. THE Home_Screen SHALL 在右上角顯示會員頭像按鈕，觸控區域不小於 48 × 48 邏輯像素。
2. WHEN 使用者點選頭像按鈕, THE Butler_App SHALL 以共享軸轉場開啟 Account_Screen。
3. THE Account_Screen SHALL 顯示會員名稱、遮罩後的手機號碼、遮罩後的 Email 與 inbr_account_id 的末 6 碼。
4. THE Account_Screen SHALL 顯示「編輯聯絡資訊」、「變更密碼」、「主題設定」與「登出」四個項目。
5. WHEN 使用者在編輯聯絡資訊頁按下儲存, THE Account_Repository SHALL 呼叫設定會員資訊接點送出更新後的聯絡資料。
6. IF 手機號碼欄位內容不符合台灣手機格式（09 開頭、共 10 位數字）, THEN THE Form_Validator SHALL 在該欄位下方顯示格式錯誤訊息並維持在編輯頁。
7. IF Email 欄位內容缺少 `@` 或缺少網域部分, THEN THE Form_Validator SHALL 在該欄位下方顯示格式錯誤訊息並維持在編輯頁。
8. IF 變更密碼頁的新密碼與確認密碼內容不一致, THEN THE Form_Validator SHALL 顯示「兩次輸入的密碼不一致」訊息。
9. THE Form_Validator SHALL 要求新密碼長度至少 8 個字元且包含英文字母與數字。
10. WHEN 會員資訊更新成功, THE Account_Screen SHALL 顯示成功提示並以更新後的資料重繪畫面。
11. IF 會員資訊更新失敗, THEN THE Account_Screen SHALL 顯示錯誤訊息與重試按鈕並保留使用者輸入內容。

### Requirement 4: 首頁 AI 生活管家主畫面（P0）

**User Story:** 作為使用者，我想在首頁一眼看到管家角色、對話入口與各類生活服務，以便用最少步驟表達需求。

#### Acceptance Criteria

1. THE Home_Screen SHALL 由上而下顯示品牌標題區、管家角色視覺、對話式輸入框、我的常用功能、服務類別磁磚與活動輪播六個區塊。
2. THE Home_Screen SHALL 以 Design_System 的暖色米白背景色票作為畫面底色。
3. THE Home_Screen SHALL 在管家角色視覺旁顯示情境化問候文字，內容包含使用者名稱。
4. THE Home_Screen SHALL 顯示對話式輸入框，框內含提示文字、語音輸入按鈕與送出按鈕。
5. WHEN 使用者點選對話式輸入框, THE Butler_App SHALL 以共享軸轉場開啟 Butler_Chat_Screen 並將輸入焦點置於對話輸入框。
6. WHEN 使用者在首頁對話式輸入框輸入文字並按下送出, THE Butler_Chat_Screen SHALL 以該文字作為對話的第一則使用者訊息。
7. THE Home_Screen SHALL 顯示附錄 A 所列 7 個服務類別磁磚，每個磁磚包含線性圖示、類別名稱與 Design_System 指定的類別色票。
8. WHEN 使用者點選服務類別磁磚, THE Butler_App SHALL 以該磁磚的 service_id 開啟 Vendor_List_Screen。
9. THE Home_Screen SHALL 顯示「我的常用功能」區塊，最多顯示 8 項且可橫向滑動。
10. WHERE 常用功能清單為空, THE Home_Screen SHALL 在該區塊顯示新增常用功能的引導按鈕。
11. WHEN 使用者長按服務類別磁磚, THE Home_Screen SHALL 顯示加入或移除常用功能的動作選單。
12. THE Home_Screen SHALL 顯示活動輪播區塊，輪播間隔 4 秒並顯示頁面指示點。（P1）
13. WHEN 使用者下拉 Home_Screen, THE Home_Screen SHALL 重新載入服務類別、常用功能與活動資料並顯示下拉刷新指示器。
14. THE App_Shell SHALL 顯示 4 個底部導覽項目：首頁、服務、訂單紀錄、個人。
15. WHEN 使用者切換底部導覽項目, THE App_Shell SHALL 保留各分頁的滑動位置與已載入資料。
16. THE Service_Catalog_Screen SHALL 作為「服務」分頁內容，顯示附錄 A 所列 7 個服務類別的完整清單，每列包含類別名稱、類別圖示、類別色票與該類別的服務商筆數。
17. WHEN 使用者點選 Service_Catalog_Screen 的任一類別列, THE Butler_App SHALL 以該類別的 service_id 開啟 Vendor_List_Screen。
18. THE Service_Catalog_Screen SHALL 在頂部顯示跨類別的服務商關鍵字搜尋欄。
19. WHEN 使用者在 Service_Catalog_Screen 的搜尋欄送出關鍵字, THE Butler_App SHALL 開啟不限 service_id 且套用該關鍵字的 Vendor_List_Screen。

### Requirement 5: 服務商列表與篩選查詢（P0）

**User Story:** 作為使用者，我想在選定服務類別後先看到所有可服務的廠商並自行篩選，以便挑選合適的廠商再填單。

#### Acceptance Criteria

1. WHEN Vendor_List_Screen 開啟, THE Vendor_Repository SHALL 以 service_id 查詢並回傳該類別下所有 service_vendor_id 的服務商摘要清單。
2. THE Vendor_List_Screen SHALL 為每個服務商顯示名稱、簡述、服務項目標籤與 `cms_homepage_service.img_url` 圖片。
3. THE Vendor_List_Screen SHALL 在標題區顯示服務類別名稱與符合條件的服務商筆數。
4. WHILE 服務商清單載入中, THE Vendor_List_Screen SHALL 顯示至少 3 張骨架卡片。
5. IF 查詢結果為 0 筆, THEN THE Vendor_List_Screen SHALL 顯示空狀態插圖、說明文字與「清除篩選條件」按鈕。
6. IF 服務商查詢失敗, THEN THE Vendor_List_Screen SHALL 顯示錯誤說明與重新載入按鈕。
7. THE Vendor_Filter_Panel SHALL 提供關鍵字、縣市（sys_county.code）、行政區（sys_district.code）與服務項目共 4 項基本篩選條件。
8. WHERE 服務商摘要資料包含評分欄位, THE Vendor_Filter_Panel SHALL 額外提供評分下限篩選條件與「評分由高至低」排序選項。
9. WHERE 服務商摘要資料包含價格區間欄位, THE Vendor_Filter_Panel SHALL 額外提供價格區間篩選條件與「價格由低至高」排序選項。
10. WHERE 服務商摘要資料包含可服務狀態欄位, THE Vendor_Filter_Panel SHALL 額外提供「僅顯示目前可服務」篩選條件。
11. WHERE 服務商摘要資料缺少評分、價格區間或可服務狀態欄位, THE Vendor_Filter_Panel SHALL 隱藏該欄位對應的篩選條件與排序選項。
12. WHEN 使用者選定縣市, THE Vendor_Filter_Panel SHALL 只顯示屬於該縣市的行政區選項。
13. WHEN 使用者變更縣市, THE Vendor_Filter_Panel SHALL 清除已選的行政區。
14. WHEN 使用者按下套用篩選, THE Vendor_List_Screen SHALL 依生效條件重新查詢並將清單捲動至頂端。
15. THE Vendor_List_Screen SHALL 在篩選按鈕上顯示目前生效的篩選條件數量。
16. THE Vendor_Filter_Panel SHALL 提供「推薦」排序選項作為預設排序。
17. WHEN 使用者在關鍵字欄輸入文字, THE Vendor_List_Screen SHALL 在最後一次輸入後 300 毫秒觸發查詢。
18. WHILE 符合條件的服務商筆數超過 20, THE Vendor_List_Screen SHALL 以每頁 20 筆分頁載入，並在使用者捲動至距清單底部 200 邏輯像素內時載入下一頁。
19. WHILE 下一頁載入中, THE Vendor_List_Screen SHALL 在清單底部顯示載入指示器。
20. WHERE Vendor_List_Screen 以不限 service_id 的方式開啟, THE Vendor_List_Screen SHALL 顯示所有類別的服務商並在標題區顯示「全部服務」。

### Requirement 6: 服務商詳情（P0）

**User Story:** 作為使用者，我想在填單前看到廠商的服務介紹、注意事項與服務條款，以便判斷是否要委託。

#### Acceptance Criteria

1. WHEN 使用者點選服務商卡片, THE Butler_App SHALL 以 Hero 轉場開啟 Vendor_Detail_Screen 並沿用卡片圖片作為 Hero 元素。
2. THE Vendor_Detail_Screen SHALL 顯示服務商名稱、主圖、可服務地區與服務項目標籤。
3. WHERE 服務商資料包含評分欄位, THE Vendor_Detail_Screen SHALL 在服務商名稱下方顯示評分數值與評分筆數。
4. THE Html_Content_Renderer SHALL 將 `pms_form.intro_content`、`notice_content` 與 `terms_content` 的 HTML 內容轉為原生排版並套用 Design_System 字體階層。
5. THE Vendor_Detail_Screen SHALL 以可折疊區塊呈現服務介紹、注意事項與服務條款，且預設展開服務介紹。
6. WHERE HTML 內容為空字串或缺值, THE Vendor_Detail_Screen SHALL 隱藏對應的折疊區塊。
7. THE Html_Content_Renderer SHALL 略過 HTML 內容中的 script 與 iframe 標籤。
8. WHEN 使用者點選 HTML 內容中的外部連結, THE Butler_App SHALL 顯示確認對話框後才開啟系統瀏覽器。
9. THE Vendor_Detail_Screen SHALL 在畫面底部固定顯示「填寫諮詢單」按鈕。
10. WHEN 使用者按下「填寫諮詢單」, THE Butler_App SHALL 以該服務商對應的 form_id 與 service_id 開啟 Form_Screen。

### Requirement 7: 彈性諮詢單動態渲染（P0）

**User Story:** 作為使用者，我想填寫廠商設計的諮詢單，以便一次把需求說清楚。

#### Acceptance Criteria

1. WHEN Form_Screen 開啟, THE Form_Repository SHALL 依 form_id 回傳由 pms_form、pms_form_group、pms_form_topic、pms_topic_option 與 pms_topic_media 組成的表單定義。
2. THE Dynamic_Form_Renderer SHALL 依 pms_form_group.sort 由小到大排列題組，並依 pms_form_topic.sort 由小到大排列題目。
3. THE Dynamic_Form_Renderer SHALL 為每個題目顯示 title，並在 remark 非空時於 title 下方以次要文字樣式顯示 remark。
4. WHERE 題目的 is_required 為 true, THE Dynamic_Form_Renderer SHALL 在 title 後顯示必填標記與必填語意標籤。
5. WHEN 題型代碼為 1, THE Dynamic_Form_Renderer SHALL 顯示單行文字輸入欄。
6. WHERE 題型代碼為 1 且 is_number_only 為 true, THE Dynamic_Form_Renderer SHALL 使用數字鍵盤並只接受數字字元輸入。
7. WHEN 題型代碼為 2, THE Dynamic_Form_Renderer SHALL 顯示可自動增高的多行文字輸入欄，初始高度為 4 行。
8. WHEN 題型代碼為 3, THE Dynamic_Form_Renderer SHALL 顯示單選選項清單，且同一時間僅一個選項處於選取狀態。
9. WHEN 題型代碼為 4, THE Dynamic_Form_Renderer SHALL 顯示複選選項清單，允許同時選取多個選項。
10. WHEN 題型代碼為 5, THE Dynamic_Form_Renderer SHALL 顯示縣市與行政區兩層連動選單，行政區選項依所選 sys_county.code 過濾。
11. WHEN 題型代碼為 6, THE Dynamic_Form_Renderer SHALL 顯示照片選擇器與已選照片縮圖列，並顯示 minimum_medias_upload 與 maximum_medias_upload 的張數要求文字。
12. WHERE 題型代碼為 6 且 specified_medias_upload 非空, THE Dynamic_Form_Renderer SHALL 為每個指定拍攝項目顯示獨立的上傳格位與項目名稱。
13. WHEN 題型代碼為 7, THE Dynamic_Form_Renderer SHALL 顯示唯讀說明區塊並不收集作答值。
14. WHEN 題型代碼為 8, THE Dynamic_Form_Renderer SHALL 顯示姓名、手機、市話、Email、縣市、行政區與詳細地址七個欄位。
15. WHEN 題型代碼為 10, THE Dynamic_Form_Renderer SHALL 顯示姓名、手機、市話與 Email 四個欄位。
16. WHEN 題型代碼為 9, THE Dynamic_Form_Renderer SHALL 顯示日期選擇器，可選範圍為今日加上 start_date_offset_days 至今日加上 end_date_offset_days。
17. WHERE 題目存在 pms_topic_media, THE Dynamic_Form_Renderer SHALL 顯示輔助圖片縮圖，並於使用者點選後以全螢幕檢視器顯示原圖。
18. IF 表單定義包含未列於本需求的題型代碼, THEN THE Dynamic_Form_Renderer SHALL 顯示「此題型尚未支援」提示卡並繼續渲染其餘題目。
19. THE Dynamic_Form_Renderer SHALL 為每個選項顯示 option_name，並在 unit_price 大於 0 時顯示單價與 unit 文字。
20. WHERE 選項的 is_quantity 為 true, THE Dynamic_Form_Renderer SHALL 顯示數量調整控制項，並將可調整範圍限制在 min_quantity 至 max_quantity。
21. WHERE 選項的 remark 非空, THE Dynamic_Form_Renderer SHALL 在該選項下方顯示 remark 文字。
22. THE Form_Screen SHALL 在頂部顯示題組進度指示（目前題組序號與題組總數）。
23. WHEN 使用者填寫聯絡資料題型且 Session_Store 存在會員聯絡資料, THE Form_Screen SHALL 提供「帶入會員資料」按鈕以一次填入姓名、手機與 Email。
24. THE Dynamic_Form_Renderer SHALL 使題型 5 與題型 8 各自維持獨立的縣市與行政區作答值，且一題的變更不改動另一題的作答值。
25. WHERE 表單同時包含題型 5 與題型 8, THE Feedback_Submitter SHALL 以題型 8 的縣市與行政區作答值填入 contact_address_county 與 contact_address_district。
26. WHERE 表單包含題型 5 且不包含題型 8, THE Feedback_Submitter SHALL 以 sort 值最小的題型 5 作答值填入 contact_address_county 與 contact_address_district。
27. WHERE 表單同時包含題型 5 與題型 8, THE Form_Screen SHALL 在題型 5 下方顯示「此地區用於服務範圍判斷，聯絡地址請填於聯絡資料題」說明文字。
28. WHERE 表單同時包含題型 5 與題型 8 且兩題的縣市作答值不同, THE Form_Screen SHALL 在題型 8 下方顯示兩者不一致的提示文字並允許送出。

### Requirement 8: 表單驗證、金額試算與草稿暫存（P0）

**User Story:** 作為使用者，我想在填單過程中得到清楚的錯誤提示與金額預估，並且中斷後能接續填寫。

#### Acceptance Criteria

1. WHEN 使用者按下送出諮詢單且存在未填的必填題目, THE Form_Validator SHALL 在每個未通過的題目下方顯示錯誤訊息並將畫面捲動至第一個未通過的題目。
2. WHEN 使用者修正未通過的題目, THE Form_Validator SHALL 移除該題目的錯誤訊息。
3. IF 上傳照片題已選張數少於 minimum_medias_upload, THEN THE Form_Validator SHALL 顯示最少上傳張數的錯誤訊息。
4. WHEN 上傳照片題已選張數達到 maximum_medias_upload, THE Dynamic_Form_Renderer SHALL 停用該題的新增照片按鈕。
5. WHERE 表單的 sub_type 為 2, THE Quotation_Calculator SHALL 顯示已選項目的金額小計清單與總計金額。
6. WHEN 使用者變更含 unit_price 的選項或其數量, THE Quotation_Calculator SHALL 在同一畫面更新總計金額。
7. WHERE 已選項目中存在 is_quoted_separately 為 true 的選項, THE Quotation_Calculator SHALL 將該選項金額以 0 計入總計並在總計旁顯示「部分項目由廠商另行報價」說明。
8. WHERE 表單的 sub_type 為 2, THE Form_Screen SHALL 在總計金額旁顯示「金額為系統試算，實際費用以廠商報價為準」說明文字。
9. THE Draft_Store SHALL 在使用者變更表單內容後 1 秒內，將該表單內容以 form_id 為索引寫入本機儲存。
10. WHEN 使用者開啟已存在草稿的 form_id 對應的 Form_Screen, THE Form_Screen SHALL 顯示「繼續填寫上次內容」與「重新填寫」兩個選項。
11. WHEN 使用者選擇重新填寫, THE Draft_Store SHALL 刪除該 form_id 的草稿並以空白表單呈現。
12. WHEN 諮詢單送出成功, THE Draft_Store SHALL 刪除該 form_id 的草稿。
13. WHEN 使用者在表單有未送出內容的情況下按下返回, THE Form_Screen SHALL 顯示「已保存為草稿」提示後才關閉畫面。

### Requirement 9: 諮詢單送出與回饋單建立（P0）

**User Story:** 作為使用者，我想送出諮詢單並取得單號，以便後續追蹤廠商回覆。

#### Acceptance Criteria

1. WHEN 使用者確認送出諮詢單, THE Feedback_Submitter SHALL 組出包含 service_id、form_id、form_type、feedback_content、contact_name、contact_mobile、contact_landline、contact_email、preferred_contact_time、contact_address_county、contact_address_district、contact_address_detail、description 與 inbr_account_id 的請求並呼叫建立 feedback 接點。
2. THE Feedback_Submitter SHALL 在每次建立 feedback 的請求中帶入 platform_code 值 `01`。
3. THE Feedback_Submitter SHALL 將 feedback_content 序列化為 JSON 物件，其 `answers` 鍵為陣列，陣列每個元素包含 `topic_id`（整數）、`type`（兩位數字字串）與 `value` 三個鍵。
4. THE Feedback_Submitter SHALL 依附錄 C 的作答值序列化契約決定每個題型的 `value` 型別。
5. THE Feedback_Submitter SHALL 使未作答且非必填的題目在 `answers` 陣列中以 `value` 為 null 的元素表示。
6. THE Feedback_Submitter SHALL 使題型 7 的題目不產生 `answers` 陣列元素。
7. THE Form_Screen SHALL 提供 preferred_contact_time 的三個選項：1 上午、2 下午、3 皆可。
8. WHILE 建立 feedback 請求進行中, THE Form_Screen SHALL 顯示送出中遮罩並停用送出按鈕。
9. THE Feedback_Submitter SHALL 對一次送出動作僅發出一個建立 feedback 請求，直到收到回應或逾時。
10. WHEN 建立 feedback 成功, THE Form_Screen SHALL 顯示含 feedback_no 的成功頁面與「查看我的諮詢單」及「回首頁」兩個按鈕。
11. IF 建立 feedback 因網路錯誤或伺服器錯誤失敗, THEN THE Form_Screen SHALL 保留使用者已填內容並顯示重試按鈕。
12. IF 建立 feedback 回傳欄位驗證錯誤, THEN THE Form_Screen SHALL 將後端回傳的錯誤訊息顯示在對應題目下方。
13. WHEN 諮詢單送出成功, THE Order_List_Screen SHALL 在下次開啟時包含該筆 feedback_no。

### Requirement 10: 照片上傳（P1）

**User Story:** 作為使用者，我想上傳現場照片，以便廠商在報價前先了解狀況。

#### Acceptance Criteria

1. WHEN 使用者在上傳照片題選擇照片, THE Media_Uploader SHALL 顯示該照片縮圖與上傳進度百分比。
2. THE Media_Uploader SHALL 先向後端取得預簽章上傳網址，再將照片直接上傳至物件儲存服務。
3. THE Media_Uploader SHALL 在上傳前將照片長邊縮至 1600 像素以內並以 JPEG 85% 品質重新編碼。
4. WHEN 照片上傳完成, THE Media_Uploader SHALL 將後端回傳的檔案識別碼寫入該題的作答值。
5. IF 單張照片上傳失敗, THEN THE Media_Uploader SHALL 在該縮圖上顯示重試圖示並允許使用者單張重試。
6. IF 使用者拒絕相機或相簿權限, THEN THE Media_Uploader SHALL 顯示權限說明文字與「前往系統設定」按鈕。
7. WHEN 使用者點選已上傳照片的刪除鍵, THE Media_Uploader SHALL 移除該縮圖並更新該題的作答值。
8. WHERE Environment_Config 的 dataSource 設定為 mock, THE Media_Uploader SHALL 以本機路徑模擬上傳成功並回傳模擬檔案識別碼。

### Requirement 11: 個資保護與顯示遮罩（P0）

**User Story:** 作為使用者，我想確信我的個資受到保護，以便安心提供聯絡方式。

#### Acceptance Criteria

1. THE Api_Client SHALL 僅以 HTTPS 協定與後端接點通訊。
2. THE Butler_App SHALL 將姓名、手機、市話、Email 與詳細地址以明文欄位透過 HTTPS 傳送至後端接點，並由後端執行 AES-256-GCM 加密與 SHA-256 hash 計算。
3. THE Butler_App SHALL 在原始碼與打包產物中僅保存非機密組態值：環境名稱、baseUrl 與功能開關。
4. THE Account_Screen SHALL 以遮罩形式顯示手機號碼（保留末 3 碼）與 Email（保留 @ 前 2 個字元）。
5. THE Order_List_Screen SHALL 以遮罩形式顯示聯絡人手機號碼（保留末 3 碼）。
6. WHEN 使用者點選遮罩欄位旁的顯示按鈕, THE Account_Screen SHALL 顯示完整內容並在 10 秒後恢復遮罩。
7. THE Butler_App SHALL 將姓名、手機、市話、Email 與詳細地址欄位排除於偵錯日誌輸出之外。
8. WHILE Butler_App 位於系統背景, THE Butler_App SHALL 對 Account_Screen 與 Form_Screen 套用系統截圖遮蔽。（P2）

### Requirement 12: AI 智能管家對話介面（P0）

**User Story:** 作為使用者，我想用自然語言跟管家說明需求，並感受到專業智慧的互動質感。

#### Acceptance Criteria

1. THE Butler_Chat_Screen SHALL 顯示管家頭像、管家名稱與狀態文字，狀態文字為待命中、聆聽中或思考中三者之一。
2. WHEN 使用者送出訊息, THE Butler_Chat_Screen SHALL 立即以使用者氣泡顯示該訊息並將對話清單捲動至底部。
3. WHILE Ai_Butler_Service 尚未回傳第一個字元, THE Butler_Chat_Screen SHALL 顯示三點跳動的思考中指示器。
4. WHEN Ai_Butler_Service 開始回傳回覆內容, THE Butler_Chat_Screen SHALL 以不超過 50 毫秒的更新間隔逐段顯示文字。
5. THE Butler_Chat_Screen SHALL 在每則管家回覆下方顯示最多 4 個建議快捷選項。
6. WHEN 使用者點選建議快捷選項, THE Butler_Chat_Screen SHALL 以該選項文字作為下一則使用者訊息送出。
7. THE Butler_Chat_Screen SHALL 支援服務類別建議卡、服務商推薦卡與表單預填確認卡三種結構化卡片。
8. WHEN 使用者點選服務類別建議卡, THE Butler_App SHALL 以該卡片的 service_id 開啟 Vendor_List_Screen。
9. WHEN 使用者點選服務商推薦卡, THE Butler_App SHALL 以該卡片的 service_vendor_id 開啟 Vendor_Detail_Screen。
10. WHILE 對話清單的捲動位置距底部超過一個螢幕高度, THE Butler_Chat_Screen SHALL 顯示「回到最新訊息」浮動按鈕。
11. THE Butler_Chat_Screen SHALL 在對話為空時顯示至少 3 個情境範例提示，供使用者直接點選送出。
12. THE Butler_Chat_Screen SHALL 提供「開始新對話」動作，執行後清空當前對話並保留歷史對話清單。（P1）
13. IF Ai_Butler_Service 回應失敗或逾時, THEN THE Butler_Chat_Screen SHALL 在該則訊息位置顯示錯誤氣泡與「重新產生」按鈕。
14. WHERE Environment_Config 的 aiSource 設定為 mock, THE Ai_Butler_Service SHALL 依關鍵字比對回傳腳本化的回覆文字與結構化卡片。
15. THE Butler_Chat_Screen SHALL 以 Design_System 定義的管家配色與圓角樣式呈現訊息氣泡，並區分使用者與管家的視覺樣式。

### Requirement 13: AI 需求理解與表單預填（P0）

**User Story:** 作為使用者，我想讓 AI 聽懂我的需求並幫我把諮詢單填好，以便省下逐題填寫的時間。

#### Acceptance Criteria

1. WHEN 使用者以自然語言描述生活需求, THE Ai_Butler_Service SHALL 回傳判定的 service_id 清單與每項的信心程度數值。
2. WHERE Ai_Butler_Service 回傳多個 service_id, THE Butler_Chat_Screen SHALL 為每個 service_id 顯示一張服務類別建議卡。
3. IF Ai_Butler_Service 回傳的 service_id 清單為空, THEN THE Butler_Chat_Screen SHALL 顯示釐清問題文字與 7 個服務類別的選單。
4. WHEN 使用者確認服務類別, THE Ai_Butler_Service SHALL 依該類別的表單定義回傳可對應的題目作答值作為預填內容。
5. THE Butler_Chat_Screen SHALL 以表單預填確認卡顯示 AI 已填欄位摘要、尚未填寫的必填題目數量與「檢視並編輯」按鈕。
6. WHEN 使用者點選「檢視並編輯」, THE Butler_App SHALL 開啟帶入預填內容的 Form_Screen 並標示由 AI 填入的題目。
7. THE Butler_App SHALL 在使用者於 Form_Screen 按下送出諮詢單後才呼叫建立 feedback 接點。
8. WHILE 預填內容中仍有未填的必填題目, THE Butler_Chat_Screen SHALL 每則回覆追問一個缺漏題目並提供對應的輸入輔助元件。
9. WHEN 使用者詢問某題目的填寫方式, THE Ai_Butler_Service SHALL 回傳該題目的說明文字與一組範例作答。
10. THE Ai_Butler_Service SHALL 以抽象介面定義，並支援 mock 實作、後端代理實作與 AWS 直接呼叫實作三種替換方式而不修改畫面程式碼。
11. WHEN 使用者在 Form_Screen 修改由 AI 填入的題目, THE Form_Screen SHALL 移除該題目的 AI 填入標示。
12. THE Butler_Chat_Screen SHALL 在送出前顯示需求摘要文字，內容包含服務類別、時間、地點與數量四類資訊中已取得的項目。

### Requirement 14: 語音輸入（P0）

**User Story:** 作為不方便打字的使用者，我想用說話的方式描述需求，以便快速表達。

#### Acceptance Criteria

1. THE Voice_Input_Module SHALL 在 Home_Screen 與 Butler_Chat_Screen 的輸入框中顯示語音輸入按鈕。
2. WHEN 使用者首次按下語音輸入按鈕, THE Voice_Input_Module SHALL 請求麥克風權限。
3. THE Voice_Input_Module SHALL 使用 zh-TW 作為語音辨識語系。
4. WHILE 語音辨識進行中, THE Voice_Input_Module SHALL 顯示音量波形動畫與即時辨識中的文字。
5. WHEN 使用者停止說話持續超過 2 秒, THE Voice_Input_Module SHALL 結束辨識並將辨識結果文字填入輸入框。
6. WHEN 語音辨識結果填入輸入框, THE Butler_Chat_Screen SHALL 允許使用者在送出前編輯該文字。
7. WHEN 使用者在辨識進行中按下停止按鈕, THE Voice_Input_Module SHALL 結束辨識並保留已辨識文字。
8. IF 使用者拒絕麥克風權限, THEN THE Voice_Input_Module SHALL 停用語音輸入按鈕並顯示「請改用文字輸入」提示與「前往系統設定」按鈕。
9. IF 語音辨識結果為空字串, THEN THE Voice_Input_Module SHALL 顯示「沒有聽清楚，請再說一次或改用文字輸入」提示。
10. WHERE 裝置不支援語音辨識, THE Voice_Input_Module SHALL 停用語音輸入按鈕並顯示不支援原因。
11. WHERE 管家語音回覆功能啟用, THE Butler_Chat_Screen SHALL 為每則管家回覆提供朗讀播放按鈕。（P2）

### Requirement 15: 諮詢單與訂單追蹤（P0）

**User Story:** 作為使用者，我想查看我送出的諮詢單與後續訂單的狀態，以便掌握進度。

#### Acceptance Criteria

1. WHEN Order_List_Screen 開啟, THE Order_Repository SHALL 呼叫查看訂單接點取得未處理的 feedbacks 與 orders 的合併結果。
2. THE Order_List_Screen SHALL 以「我的諮詢單」與「我的訂單」兩個分頁呈現查詢結果。
3. THE Order_List_Screen SHALL 為每筆諮詢單顯示 feedback_no、服務類別名稱、送出時間與處理狀態。
4. THE Order_List_Screen SHALL 為每筆訂單顯示 order_no、order_type 名稱、金額、建立時間與狀態標籤。
5. THE Order_Status_Mapper SHALL 依附錄 B 的對照表將 order_type 與 order_status 的組合轉為狀態名稱與狀態顏色。
6. IF order_status 未列於附錄 B 的對照表, THEN THE Order_Status_Mapper SHALL 回傳狀態名稱「處理中」與中性灰色，並將原始狀態碼寫入偵錯日誌。
7. IF order_type 未列於附錄 B 的對照表, THEN THE Order_Status_Mapper SHALL 回傳類別名稱「其他服務」。
8. WHEN 使用者點選任一筆諮詢單或訂單, THE Butler_App SHALL 以共享軸轉場開啟 Order_Detail_Screen 並顯示該筆的完整欄位。
9. THE Order_Detail_Screen SHALL 以時間軸呈現該 order_type 的完整狀態流程並標示目前所在狀態。（P1）
10. WHILE 清單載入中, THE Order_List_Screen SHALL 顯示至少 3 列骨架列表項目。
11. IF 查詢結果為 0 筆, THEN THE Order_List_Screen SHALL 顯示空狀態插圖與「立即諮詢」按鈕。
12. WHEN 使用者下拉 Order_List_Screen, THE Order_Repository SHALL 重新查詢諮詢單與訂單資料。
13. THE Order_List_Screen SHALL 提供狀態篩選：進行中、已完成、已取消。（P1）
14. THE Order_List_Screen SHALL 依建立時間由新到舊排列清單項目。

### Requirement 16: 推播通知與深層連結（P1，後端依賴）

**User Story:** 作為使用者，我想在訂單狀態變更時收到通知並直接跳到該筆訂單，以便及時處理。

#### Acceptance Criteria

1. WHEN 使用者首次登入成功, THE Notification_Handler SHALL 請求推播通知權限。
2. WHEN 取得推播通知權限, THE Notification_Handler SHALL 將裝置推播 token 送至後端註冊接點。
3. WHEN Butler_App 位於前景並收到訂單狀態通知, THE Notification_Handler SHALL 以應用內橫幅顯示通知標題與內容。
4. WHEN 使用者點選訂單狀態通知, THE Butler_App SHALL 以通知內的 order_no 開啟對應的 Order_Detail_Screen。
5. IF 通知內容缺少 order_no, THEN THE Butler_App SHALL 開啟 Order_List_Screen。
6. WHERE 推播後端尚未就緒, THE Notification_Handler SHALL 提供本地模擬通知的觸發入口供現場 demo 使用。
7. IF 使用者拒絕推播通知權限, THEN THE Order_List_Screen SHALL 以下拉刷新作為狀態更新方式並顯示說明文字。

### Requirement 17: 設計系統（P0）

**User Story:** 作為使用者，我想看到一致而溫暖的智慧管家介面，以便信任這個服務。

#### Acceptance Criteria

1. THE Design_System SHALL 定義 11 組語意色票：主色、輔色、強調色、背景色、表面色、文字主色、文字次色、邊框色、成功色、警示色與錯誤色。
2. THE Design_System SHALL 以暖色米白作為背景色票，明度不低於 95% 且色相位於暖色區間。
3. THE Design_System SHALL 定義 7 級字體階層：display、headline、title、body-large、body、label 與 caption，每級指定字級、字重與行高。
4. THE Design_System SHALL 定義 4 級圓角值：8、12、16 與 24 邏輯像素。
5. THE Design_System SHALL 定義 3 級陰影樣式：卡片、浮動元件與對話框。
6. THE Design_System SHALL 定義間距刻度：4、8、12、16、24 與 32 邏輯像素。
7. THE Design_System SHALL 為 7 個服務類別各定義一組圖示色票，且每組色票與背景色的對比度不低於 3:1。
8. THE Butler_App SHALL 透過 ThemeData 與 ThemeExtension 集中提供 Design_System 的色票、間距、圓角與動畫時長。
9. THE Butler_App SHALL 使各畫面自 ThemeData 或 ThemeExtension 取得樣式值。
10. THE Design_System SHALL 定義按鈕、輸入框、卡片、標籤與對話框五類元件的預設樣式。

### Requirement 18: 轉場與流暢度（P0）

**User Story:** 作為使用者，我想在切換畫面時感受到順暢連貫的動態，以便操作起來不卡頓。

#### Acceptance Criteria

1. THE Motion_System SHALL 定義三種頁面轉場：共享軸水平轉場、淡入向上位移轉場與 Hero 轉場。
2. THE Motion_System SHALL 將頁面轉場時長設定於 250 至 350 毫秒之間並使用強調緩動曲線。
3. WHEN 使用者在同層畫面之間導覽, THE Motion_System SHALL 套用共享軸水平轉場。
4. WHEN 使用者從卡片開啟詳情頁, THE Motion_System SHALL 套用 Hero 轉場。
5. WHEN 使用者切換底部導覽分頁, THE App_Shell SHALL 保留各分頁已建構的 Widget 子樹與其狀態。
6. WHEN 使用者切換底部導覽分頁, THE Motion_System SHALL 以 200 毫秒淡入淡出呈現分頁切換。
7. WHEN 清單首次載入完成, THE Motion_System SHALL 以每項延遲不超過 40 毫秒、總時長不超過 400 毫秒的漸進動畫顯示列表項目。
8. WHILE 資料載入時間超過 200 毫秒, THE Butler_App SHALL 顯示與該畫面版面相符的骨架載入元件。
9. WHEN 使用者按下可點擊元件, THE Motion_System SHALL 在 100 毫秒內顯示按壓回饋。
10. THE Butler_App SHALL 對項目數超過 20 的清單使用延遲建構的 builder 形式。
11. THE Butler_App SHALL 在 build 方法之外執行資料排序、篩選與格式化運算。
12. WHEN 以 `flutter run --profile` 在實機執行整合測試，於 Vendor_List_Screen 對 60 筆服務商清單連續執行 3 次全程滑動並以 `TimelineSummary` 收集結果, THE Butler_App SHALL 使 build 階段超過 16 毫秒的幀數佔總幀數的比例不高於 5%，且第 99 百分位的 build 時間不高於 32 毫秒。
13. THE Butler_App SHALL 為遠端圖片指定解碼寬度上限並以淡入方式顯示。
14. WHERE 系統啟用減少動態效果設定, THE Motion_System SHALL 將動畫時長設為 0 並直接呈現最終狀態。

### Requirement 19: 無障礙與高齡友善（P1）

**User Story:** 作為高齡使用者，我想用大字與清楚的提示操作 App，以便自己完成服務預約。

#### Acceptance Criteria

1. THE Butler_App SHALL 為每個圖示按鈕提供語意標籤。
2. THE Butler_App SHALL 使每個可點擊目標的觸控區域不小於 48 × 48 邏輯像素。
3. THE Butler_App SHALL 使正文文字與其背景色的對比度不低於 4.5:1。
4. WHEN 系統字級縮放設定為 1.3 倍, THE Butler_App SHALL 完整顯示畫面文字內容且不截斷。
5. THE Butler_App SHALL 為每個表單錯誤提供文字說明，並在錯誤欄位加上錯誤語意標記。
6. THE Butler_Chat_Screen SHALL 提供情境範例提示，供不熟悉輸入的使用者直接點選。
7. THE Account_Screen SHALL 提供大字模式開關，開啟後將正文字級放大 1.2 倍。（P2）
8. THE Butler_App SHALL 為每個畫面提供可朗讀的畫面標題語意節點。

### Requirement 20: 主題切換（P2）

**User Story:** 作為使用者，我想在夜間使用深色介面，以便減少眼睛負擔。

#### Acceptance Criteria

1. WHERE 深色模式啟用, THE Theme_Manager SHALL 套用與淺色主題語意對應的深色色票。
2. WHEN 系統主題設定變更, THE Theme_Manager SHALL 在不重啟 Butler_App 的情況下套用對應主題。
3. THE Account_Screen SHALL 提供主題設定選項：跟隨系統、淺色與深色。
4. WHEN 使用者變更主題設定, THE Theme_Manager SHALL 將選擇結果寫入本機儲存並於下次啟動時沿用。

### Requirement 21: 可抽換資料來源與後端串接預留（P0）

**User Story:** 作為 App 開發者，我想讓所有資料存取都走可抽換介面並標註待串接位置，以便比賽現場快速換成隊友的真實 API。

#### Acceptance Criteria

1. THE Repository_Layer SHALL 為登入、會員資訊、服務類別、服務商查詢、表單定義、建立 feedback 與查看訂單共 7 組能力各定義一個抽象介面。
2. THE Repository_Layer SHALL 為每個抽象介面各提供一份 mock 實作與一份 HTTP 實作。
3. THE Environment_Config SHALL 提供 dataSource 設定值（mock 或 remote）、aiSource 設定值（mock 或 remote）、baseUrl 設定值與 guestBrowsing 設定值（true 或 false）。
4. WHEN Butler_App 啟動, THE Butler_App SHALL 依 Environment_Config 的設定值決定注入 mock 實作或 HTTP 實作。
5. WHERE Environment_Config 的 dataSource 設定為 mock, THE Butler_App SHALL 在無網路連線的情況下完成登入、瀏覽服務商、填寫諮詢單、送出與查看訂單的完整流程。
6. THE Butler_App SHALL 以 `// TODO(backend):` 前綴標註每一個尚未串接真實後端的位置。
7. THE Repository_Layer SHALL 將所有後端接點路徑集中定義於單一 API 路徑常數檔。
8. THE Butler_App SHALL 提供一份後端接點清單文件，逐項列出接點名稱、對應抽象介面、TODO 標註位置與預期的請求與回應欄位。
9. THE Api_Client SHALL 將後端回應解析為 DTO 類別，並由對應的 mapper 轉換為畫面使用的領域模型。
10. WHERE 後端回應缺少非必填欄位, THE Api_Client SHALL 以該欄位的預設值完成 DTO 解析。
11. IF 後端回應的必填欄位缺失或型別不符, THEN THE Api_Client SHALL 拋出可辨識的解析錯誤並將接點名稱寫入偵錯日誌。
12. THE Butler_App SHALL 使畫面層僅依賴抽象介面與領域模型，並使 HTTP 與 mock 細節限縮在 Repository_Layer 內。
13. THE Butler_App SHALL 使 `pubspec.yaml` 的相依項目僅包含在 `lib` 目錄下有 import 引用的套件。
14. THE Butler_App SHALL 以 `pms_form_topic.type` 的兩位數字字串代碼作為表單題型模型的識別欄位型別。
15. THE Butler_App SHALL 使表單題型模型不包含以自然語言字串描述題型的欄位。

### Requirement 22: 統一錯誤處理、逾時與載入狀態（P0）

**User Story:** 作為使用者，我想在網路異常時看到清楚一致的提示與重試方式，以便知道下一步該做什麼。

#### Acceptance Criteria

1. THE Api_Client SHALL 將連線逾時設為 10 秒並將回應逾時設為 20 秒。
2. WHEN 讀取類請求因網路錯誤或 5xx 回應失敗, THE Api_Client SHALL 以 500 毫秒與 1500 毫秒的間隔重試最多 2 次。
3. THE Api_Client SHALL 使寫入類請求僅在使用者按下重試按鈕時重新送出。
4. THE Api_Client SHALL 將所有失敗結果轉換為 4 種錯誤類型：網路錯誤、認證錯誤、驗證錯誤與伺服器錯誤。
5. THE Butler_App SHALL 為 4 種錯誤類型各提供一致的呈現樣式與文案。
6. WHILE 任一畫面等待資料, THE Butler_App SHALL 顯示該畫面對應的骨架元件或載入指示器。
7. IF 裝置無網路連線, THEN THE Butler_App SHALL 在畫面頂部顯示離線提示條。
8. WHEN 網路連線恢復, THE Butler_App SHALL 隱藏離線提示條並重新載入當前畫面資料。
9. THE Api_Client SHALL 將每次請求的接點名稱、耗時與結果狀態寫入偵錯日誌。

## 附錄 A：服務類別對照（cms_homepage_service.type）

| service_id | 類別名稱 | 建議圖示 | demo 必備 |
| --- | --- | --- | --- |
| 1 | 一般居家清潔 | 清潔用具 | P0 |
| 2 | 家電清洗 | 冷氣／家電 | P0 |
| 3 | 包裹寄送 | 包裹宅配 | P1 |
| 6 | 餐廳訂位 | 餐具／座位 | P0 |
| 9 | 美食外送 | 外送機車 | P0 |
| 10 | 水電修繕 | 工具扳手 | P0 |
| 11 | 商城購物 | 購物袋 | P1 |

首頁磁磚以九宮格排列時，第 8 與第 9 格位放置「更多服務」與「活動專區」入口。

## 附錄 B：訂單狀態對照（mms_order_record）

order_type 對照：

| order_type | 名稱 |
| --- | --- |
| 01 | 服務訂單 |
| 02 | 訂位 |
| 03 | 預約 |
| 04 | 其他 |
| 05 | 商品訂單 |
| 06 | 訂餐 |

order_status 對照（依 order_type 分流）：

| order_type | order_status | 顯示名稱 | 分組 |
| --- | --- | --- | --- |
| 01 | 11 | 待訂金支付 | 進行中 |
| 01 | 12 | 已支付訂金，待報價 | 進行中 |
| 01 | 13 | 已報價，待客戶同意 | 進行中 |
| 01 | 14 | 客戶已同意報價 | 進行中 |
| 01 | 15 | 已驗收，待尾款支付 | 進行中 |
| 01 | 80 | 已完成 | 已完成 |
| 01 | 90 | 已取消 | 已取消 |
| 01 | 98 | 部分退款 | 已完成 |
| 01 | 99 | 已退款 | 已取消 |
| 02 | 01 | 待付款 | 進行中 |
| 02 | 02 | 待確認 | 進行中 |
| 02 | 03 | 已確認 | 進行中 |
| 02 | 04 | 進行中 | 進行中 |
| 02 | 70 | 已完成（預定時間後 3 小時） | 已完成 |
| 02 | 80 | 已完成（7 天後核銷） | 已完成 |
| 02 | 90 | 已取消 | 已取消 |
| 02 | 99 | 已退款 | 已取消 |
| 03 / 04 / 05 / 06 | 01 | 待付款 | 進行中 |
| 03 / 04 / 05 / 06 | 02 | 待確認 | 進行中 |
| 03 / 04 / 05 / 06 | 03 | 已確認 | 進行中 |
| 03 / 04 / 05 / 06 | 04 | 進行中 | 進行中 |
| 03 / 04 / 05 / 06 | 80 | 已完成 | 已完成 |
| 03 / 04 / 05 / 06 | 90 | 已取消 | 已取消 |
| 03 / 04 / 05 / 06 | 99 | 已退款 | 已取消 |

未列於上表的組合依 Requirement 15 第 6 與第 7 條處理。

## 附錄 C：feedback_content 作答值序列化契約

`feedback_content` 為 JSON 物件，結構如下：

```json
{
  "form_id": 12,
  "answers": [
    { "topic_id": 101, "type": "01", "value": "3" },
    { "topic_id": 104, "type": "04", "value": [ { "option_id": 51, "quantity": 2 } ] }
  ]
}
```

各題型的 `value` 型別：

| type | 題型 | value 型別 | 範例 |
| --- | --- | --- | --- |
| 01 | 簡答題 | 字串（is_number_only 為 true 時仍以字串承載數字） | `"3"` |
| 02 | 詳答題 | 字串 | `"廚房抽油煙機滴油"` |
| 03 | 單選題 | 物件：`option_id` 整數，`quantity` 整數（is_quantity 為 false 時 quantity 為 1） | `{ "option_id": 51, "quantity": 1 }` |
| 04 | 複選題 | 物件陣列，元素同題型 03 | `[ { "option_id": 51, "quantity": 2 } ]` |
| 05 | 地區選單 | 物件：`county_code` 字串，`district_code` 字串 | `{ "county_code": "01", "district_code": "001" }` |
| 06 | 上傳照片 | 字串陣列，元素為後端回傳的檔案識別碼 | `[ "media/9f2a.jpg" ]` |
| 07 | 備註說明 | 不產生 answers 元素 | 無 |
| 08 | 聯絡資料（含地址） | 物件：`name`、`mobile`、`landline`、`email`、`county_code`、`district_code`、`address_detail`，皆為字串 | 見下方說明 |
| 09 | 日期題 | 字串，格式為 `YYYY-MM-DD` | `"2026-08-05"` |
| 10 | 聯絡資料（不含地址） | 物件：`name`、`mobile`、`landline`、`email`，皆為字串 | 見下方說明 |

補充規則：

1. 未作答且非必填的題目，其 `value` 為 `null`。
2. 題型 08 與 10 的物件中，使用者未填寫的鍵其值為空字串。
3. 題型 08 與 10 的內容同時另外平鋪至 `pms_form_feedback` 的 contact_* 欄位，供後端加密與 hash 處理。
4. 選項的 `is_quoted_separately` 為 true 時，`value` 仍只記錄 option_id 與 quantity，金額由後端報價階段決定。

## 假設與待確認事項

### A. 技術前提與 AWS 服務假設

以下為架構假設，Butler_App 以可抽換介面對接，實際串接方式由現場決定：

| AWS 服務 | 用途 | App 端對接方式 | 優先級 |
| --- | --- | --- | --- |
| Amazon Bedrock（Claude 等模型） | 需求理解、服務分類、表單預填與追問、需求摘要 | 經隊友後端代理，Ai_Butler_Service 的 remote 實作 | P0 |
| Amazon Bedrock Agents / AgentCore + MCP Server | 命題要求將服務包裝為 MCP Server 供外部 Agent 調用 | 後端提供，App 為消費端 | P1 |
| Amazon Transcribe（streaming, zh-TW） | 語音轉文字 | 裝置端 STT 為預設，Transcribe 為替代實作 | P0 |
| Amazon Polly（Neural, 中文） | 管家語音回覆 | Butler_Chat_Screen 的朗讀按鈕 | P2 |
| Amazon Cognito | 帳號與登入 | 若後端採自建帳密登入則 Cognito 為替代方案 | 替代 |
| API Gateway + Lambda | 後端 API 入口 | Api_Client 的 baseUrl | P0（隊友） |
| Amazon RDS for PostgreSQL | 資料庫，附件 DDL 含 jsonb/bytea，較貼近 schema | App 不直連 | P0（隊友） |
| Amazon S3 | 諮詢單照片儲存 | 取得預簽章網址後直傳 | P1 |
| Amazon Location Service | 地區與距離篩選 | Vendor_Filter_Panel 進階條件 | P2 |
| Bedrock Knowledge Bases / OpenSearch | 服務商與 FAQ 檢索 | 經後端代理 | P2 |
| AWS KMS | AES-256-GCM 金鑰管理 | 由後端管理，App 不持有金鑰 | P0（隊友） |
| Amazon Pinpoint / SNS + FCM/APNs | 訂單通知推播 | Notification_Handler 註冊 token | P1 |

其他技術前提：

1. Butler_App 不直接連線資料庫，所有資料經隊友後端 API 取得。
2. 個資加密（AES-256-GCM）與 hash（SHA-256）由後端執行，App 端不實作加密演算法、不持有金鑰。
3. 語音辨識語系僅 zh-TW，台語辨識已自本次範圍移除。
4. 表單定義由後端依 `pms_form` 系列資料表組合後回傳，App 端不硬編題目結構。

### B. 對隊友後端與 DB 設計的觀察與風險提醒

以下為觀察與提醒，非 Butler_App 的功能需求，需與隊友確認：

1. ER 圖中的 `vendor_accounts`、`service_label`、`label` 三張表屬於自建設計（非命題官方附件），欄位與關聯需再確認，否則 App 端的服務項目標籤與評分篩選缺乏資料來源。
2. `mms_order_record` 的 `(order_no, service_id)` 為 UNIQUE KEY，重複寫入會直接報錯，建議後端在寫入前先做存在性檢查並回傳可辨識的錯誤碼，供 App 呈現正確訊息。
3. 後端架構圖「更新 order」的描述寫為「根據 service_vendor_id 抓取 orders」，與更新語意不符，推測為筆誤，需確認實際行為。
4. 「查看訂單」回傳的是 feedbacks 與 orders 的合併結果，需確認兩者的欄位命名是否統一（例如是否都提供 `created_at`、`status`、`service_id`），否則 App 端需為兩種結構各寫一套 mapper。
5. 個資欄位以 bytea 儲存加密結果並另存 hash，需確認 API 回傳給 App 時是解密後明文或遮罩字串，這會影響 Requirement 11 的遮罩實作位置。
6. `inbr_account_id` 為 UUID v7，需確認登入回應的欄位名稱與型別（字串或物件）。
7. `platform_code` 需確認除 `01`（OP APP）外是否另有 App 版本或渠道細分。
8. 需確認表單定義是否提供單一「取得完整表單」接點，或需 App 端分多次請求再自行組裝（後者會拖慢首屏，建議由後端一次回傳）。
9. 服務商列表的評分、價格區間與可服務狀態欄位尚未見於官方附件，需確認資料來源。App 端已依 Requirement 5 第 8 至 11 條以「欄位存在才顯示該篩選條件」處理，後端補上欄位即自動生效。
10. `feedback_content` 的結構由 App 端依附錄 C 定義，需與後端確認一致；若後端已有既定格式，以後端格式為準並同步更新附錄 C。
11. 附錄 C 第 3 點假設聯絡資料同時平鋪至 contact_* 欄位，需確認後端是否改為只讀 feedback_content 內的聯絡資料物件。

原第 10 與第 11 項（移除未使用的 `supabase_flutter` 相依、將 `form_field_model.dart` 的字串題型改為數字題型代碼）已提升為 Requirement 21 第 13 至 15 條。

### C. 待確認問題清單

1. demo 帳號的帳號密碼與對應會員資料由誰準備。
2. 現場是否有可用的後端環境，或全程以 mock 展示。
3. 服務商圖片與活動輪播素材的來源與尺寸規格。
4. AI 對話是否需要保存歷史對話至後端，或僅存在裝置本機。
5. 諮詢單送出後的通知管道（推播、簡訊或 Email）由後端決定哪一種可於現場演示。

## 範圍外（本次不做）

1. 台語語音辨識。
2. 廠商後台網頁（B 端）的任何畫面。
3. 後端 API 實作、資料庫 schema 建置與個資加密實作。
4. 金流串接與實際付款流程（訂單狀態僅顯示，不執行支付）。
5. 會員註冊與忘記密碼流程（現場以既有 demo 帳號登入）。
6. 多語系（英文、日文）介面。

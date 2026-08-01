---
inclusion: always
---

# 專案總覽：智慧社區服務需求理解與媒合平台

黑客松專案。Python/FastAPI 後端 + PostgreSQL + Flutter APP，另有一個跑在 AWS Bedrock AgentCore 上的 AI 管家服務。

## 目錄結構

```
agentic-home-hub/
├── Database/                隊友負責：資料庫 + DB Access API
│   ├── 部署手冊.md            本機建置 + AWS 遷移完整手冊
│   ├── AWS操作手冊.md         目前 AWS 環境連線/操作指南（EC2 IP、SSM 連線方式等）
│   ├── API_Reference.md      api_server 端點完整規格
│   ├── patch_test_pii.ps1    一次性腳本：補寫種子測試帳號（user01~04/vendor01~03）的PII明文，
│   │                         用法見AWS操作手冊.md「5.1」（需先設定PII_ENCRYPTION_KEY_B64並重啟aiwave-api）
│   ├── database/             DDL（*.sql）+ 種子資料（*.json）+ 建置腳本
│   │   └── schema.mmd        資料庫ER圖原始碼（Mermaid erDiagram），配套schema_mermaid.svg/.png
│   │                         取代舊newDBstruct.jpg；可直接貼進支援Mermaid的Markdown原生渲染
│   │                         重新產圖用 `npx @mermaid-js/mermaid-cli -i schema.mmd -o schema_mermaid.svg`
│   └── api_server/           FastAPI，直接操作 PostgreSQL，跑在 EC2 8000 埠
│       └── app/routers/      geo / catalog / accounts / forms / feedbacks / orders / reviews / summaries
├── bff_server/               我方負責：BFF（Backend For Frontend）
│   ├── README.md             架構說明 + 端點對應表
│   ├── API.md                端點規格
│   └── app/
│       ├── client.py         封裝呼叫 Database/api_server 的 httpx client
│       │                     （會自動濾掉 params 裡值為 None 的 key，見下方「開發慣例」）
│       │                     （含 get_optional 把 404 當空值、get_all_items 自動分頁抓全部）
│       ├── config.py         環境變數設定
│       ├── review_utils.py   共用邏輯：把 mms_order_review 併入訂單物件的 review 欄位
│       ├── agent_client.py   呼叫 AgentCore Runtime 並轉發 SSE（用 EC2 role 做 SigV4）
│       └── routers/
│           ├── app_api.py       APP 前端呼叫的 API（含 AI 管家 SSE）
│           └── merchant_api.py  商家後台呼叫的 API
├── agent_service/            我方負責：AI 管家（AgentCore Runtime，CodeZip 部署，不用 Docker）
│   ├── agentcore/
│   │   ├── agentcore.json    宣告式設定：runtime + memory（源頭真相，別改生成的 CDK）
│   │   ├── aws-targets.json  部署目標（account + region）**不進版控**，複製 .example 版本自己填
│   │   └── cdk/              agentcore deploy 用的 CDK 專案（由 CLI scaffold，通用模板）
│   ├── invoke_test.py        測 agent 對話（繞開 agentcore invoke 的 payload 包裝限制）
│   ├── check_memory.py       直接查 Memory 有沒有萃取出偏好
│   ├── load-creds.ps1        把 .env 憑證載進當前 shell（用 `. .\load-creds.ps1` dot-source）
│   └── app/AiButler/         codeLocation，agentcore.json 指向這裡
│       ├── main.py           BedrockAgentCoreApp 入口（@app.entrypoint）
│       ├── pyproject.toml    依賴（uv 管理）
│       ├── loop.py           async Bedrock Converse tool-use 迴圈
│       ├── tools.py          5 個 async tool（動態表單驅動，見下）
│       ├── prompts.py        系統提示，注入台北時間 + 長期偏好 + session 工作集
│       ├── memory.py         AgentCore Memory 封裝（跨 session 記憶）
│       ├── session_state.py  跨輪帶著走的已解析 id，避免模型猜 vendor_id
│       ├── backend.py        呼叫 bff_server 的 client（可切內建假資料）
│       ├── schemas.py        事件協定 + 草稿模型
│       ├── config.py         環境變數設定
│       └── Dockerfile        備用：想切換成 Container build 才需要
├── ai-butler-app/            隊友負責：Flutter APP 本體（含 AI 管家聊天畫面）
│   └── lib/
│       ├── data/remote/http_butler_ai_service.dart  打 bff_server 的 SSE，映射成 ButlerChunk
│       └── providers/ai_providers.dart              AI_SOURCE=remote 時切換到上面那支
├── ai-summary-lambda/        隊友負責：評論摘要 Lambda（Bedrock 產生 mms_review_summary）
├── vendor-admin-web/         隊友負責：商家後台前端（React + Vite + Tailwind）
└── flutter_ai_script/        我方負責：AI 管家的 Flutter 參考實作（教學導覽，待併入 ai-butler-app）
    └── lib/agent/
        ├── agent_client.dart      SSE 客戶端
        ├── agent_event.dart       SSE 事件模型（要跟 schemas.py 同步）
        ├── draft_action_card.dart 「直接送出 / 帶我操作」分叉點
        ├── tour.dart              錨點註冊表 + 服務→導覽藍圖對應
        └── tour_runner.dart       光圈導覽執行（tutorial_coach_mark 1.3.3）
```

## 架構

```
前端 (APP / 商家後台)
   │
   ├──── GUI 操作 ────────────────────────┐
   │                                      │
   └──── 自然語言對話 ──► agent_service    │
                          (AgentCore       │
                           Runtime)        │
                            │ httpx        │
                            ▼              ▼
                        bff_server (排序/篩選/組裝等前端邏輯)
                            │  透過 httpx 呼叫
                            ▼
                        Database/api_server (隊友維護，直接操作 DB，不要重複實作)
                            │
                            ▼
                        PostgreSQL (RDS)
```

**重要原則**：

1. `bff_server` 不直接碰資料庫，所有資料存取都透過呼叫 `Database/api_server` 完成。新增功能前先確認 `Database/api_server` 有沒有現成端點可以組合使用（見 `Database/API_Reference.md`），不要繞過這一層直接連 DB。
2. `agent_service` 只打 `bff_server`，不直接打 `Database/api_server`，也不碰 DB。
3. **AI 管家沒有寫入權限**。它只產生「草稿」，真正送出一定是 App 帶使用者身分打 `bff_server` 的既有端點。這讓模型幻覺無法造成錯誤訂單，也不用維護第二套 business rule。
4. **前端不直接呼叫 AgentCore**。AgentCore Runtime 只接受 SigV4(IAM) 驗證，前端拿不到也不該拿 AWS 憑證，所以由 `bff_server` 的 `/app-api/butler/chat` 用 EC2 instance role 代為呼叫並轉發 SSE。

## 目前部署狀態（AWS）

一台 EC2 同時跑兩個 service（不是兩台機器），細節見 `Database/AWS操作手冊.md`：

| 項目 | 值 |
|---|---|
| EC2 IP | `52.10.163.115` |
| Region | `us-west-2` |
| Instance ID | `i-0a2d19c738be6cb09` |
| Database/api_server | port 8000，systemd service `aiwave-api` |
| bff_server（本專案） | port 8100，systemd service `bff-api` |
| EC2 連線方式 | AWS SSM Session Manager（無 SSH key），需要跟保管憑證的人要 AWS 臨時憑證 |
| EC2 上程式碼路徑 | `/home/ssm-user/aiwave/`（database/、api_server/、bff_server/、venv/ 都在同一層） |
| systemd service User | 兩個 service 都用 `User=root`（EC2 上沒有 `ssm-user` 這個系統帳號，別再寫 `ssm-user`） |

⚠️ 這是 workshop 臨時帳號（AWS Workshop Studio），沒有身分驗證機制、沒有 HTTPS，資源可能隨時被回收。不要把 IP 或憑證分享到帳號外部。

## 部署 bff_server 更新

⚠️ `bff_server/deploy.sh` 已被移出版控（commit `4f453dc chore: untrack`，推測因含 EC2 IP / instance id / S3 bucket 而 repo 要公開）。
目前流程：打包 → 上傳 S3 → SSM 送指令到 EC2 解壓、`pip install -r requirements.txt`、重啟 `bff-api` service → health check。
需要 AWS 臨時憑證（跟保管人要）。腳本內容問當初移除的隊友。

**AI 管家（`/app-api/butler/chat`）上線前置條件**，三項缺一不可：

1. **部署新程式碼**。`app/agent_client.py` 是新檔案、`requirements.txt` 多了 `boto3`，光複製程式碼不裝依賴會 ImportError 起不來。
2. **EC2 instance role（`aiwave-ec2-ssm-role`）加權限**：
   `bedrock-agentcore:InvokeAgentRuntime`，Resource 指向 `.../runtime/AgenticHomeHubButler_AiButler-*`。
3. **EC2 上 `bff_server/.env` 加 `AGENTCORE_RUNTIME_ARN`**（用 `agentcore status --json` 取 `resourceType=agent` 的 `identifier`）。
   程式碼刻意不寫死預設值：它含 AWS account id 而 repo 會公開。未設定時端點會回一筆 `error` 事件而不是崩掉。

驗證（PowerShell 要用 `curl.exe`，`curl` 是 `Invoke-WebRequest` 的別名，不吃 `-H`/`-d`）：

```powershell
curl.exe -sS -N -X POST http://<EC2_IP>:8100/app-api/butler/chat `
  -H "Content-Type: application/json" --data-binary @payload.json
```

該看到 `data: {"type":"text_delta",...}` 逐行冒出。若一次噴完就是有反向代理在緩衝
（程式已送 `X-Accel-Buffering: no`，nginx 可能還要 `proxy_buffering off`）。

## 部署 agent_service（AI 管家）

不跑在 EC2 上，跑在 AWS Bedrock AgentCore Runtime，全部透過 AgentCore CLI 操作。
**不需要 Docker** —— 用 CodeZip build，CLI 打包 zip 上傳，AWS 管語言執行環境。

第一次 clone 下來要先建 `agentcore/aws-targets.json`（它含 AWS account id，不進版控）：
複製 `agentcore/aws-targets.example.json` 改名後填入自己的 account id。

```bash
cd agent_service
. .\load-creds.ps1           # 先把 .env 憑證載進當前 shell（注意前面的點）
agentcore validate           # 檢查 agentcore.json
agentcore dev --no-browser   # 本機起服務（port 8080，hot reload）
agentcore deploy             # 合成 CDK 並部署（第一次含建 Memory 與 IAM）
agentcore status             # 看部署狀態
agentcore invoke --session-id "$(uuidgen)" '{"message":"我想吃晚餐","actor_id":"demo-user-0001"}'
agentcore logs               # 看 runtime 日誌
```

| 項目 | 值 |
|---|---|
| Region | `us-west-2`（workshop 帳號只允許 us-east-1 / us-west-2） |
| Account | `728259505479` |
| 模型 | `us.anthropic.claude-sonnet-4-5-20250929-v1:0`（cross-region inference profile） |
| Runtime 名稱 | `AiButler`，協定 HTTP，`PYTHON_3_13`，networkMode PUBLIC |
| Memory 名稱 | `ButlerMemory`，策略 USER_PREFERENCE + SUMMARIZATION，事件保留 30 天 |
| 前置工具 | Node 20+、`uv`、`npm i -g @aws/agentcore` |
| 觀測 | `instrumentation.enableOtel: true`，所以 `pyproject.toml` **必須**有 `aws-opentelemetry-distro`（它會用 `opentelemetry-instrument` 包住 entrypoint，少了套件啟動會失敗） |

注意事項：

- `agentcore.json` 是**源頭真相**。不要改 `agentcore/cdk/` 裡生成的程式碼，改了會被下次 deploy 覆蓋。
- 資源的 `name` 決定 CloudFormation Logical ID。**改名等於刪掉重建**，改其他欄位是原地更新。
- Memory ID 由 CDK 自動注入成環境變數 `MEMORY_BUTLERMEMORY_ID`（規則是 `MEMORY_<名稱大寫>_ID`），程式不要寫死。
- `runtimeSessionId` 必須 ≥33 字元。標準 UUID（36 字元含連字號）剛好符合，去掉連字號的 32 字元版本會被拒絕。
- 偏好萃取是 AWS 非同步做的，所以剛講完的偏好不會立刻出現在 `RetrieveMemoryRecords`。同一 session 內靠 `ListEvents` 的原始歷史看得到，不影響對話。
- 依賴超過 250MB 或需要特殊編譯套件時才改用 Container build（`build: "Container"`，`Dockerfile` 已備在 codeLocation）。

## 資料庫核心概念（Database/）

- **cms_homepage_service_vendor**：服務商主檔（`id`, `name`, `description`）
- **cms_homepage_service**：服務項目主檔，`type` 欄位代表服務類型：
  1=居家清潔 2=家電清洗 3=包裹寄送 6=餐廳訂位 9=美食外送 10=水電修繕 11=商城購物。`form_id`（新增，nullable，對應`pms_form.id`）指定該服務項目對應哪張諮詢表單，解決「查某個service要對應到哪張form」的查詢缺口（原設計只有`pms_form.service_vendor_id`反向關聯，無法從單一service_id直接查到表單）。多個service可共用同一`form_id`；`NULL`代表尚未設定專屬表單；跟`pms_form`本身供B端/客服/轉訂單流程使用的通用表單無關，那些表單不透過此欄位查詢。
- **label / service_label**：標籤主檔 + 服務項目與標籤的多對多關聯表。`label.service_type`（新增，nullable，對應`cms_homepage_service.type`）：`NULL`=通用標籤（適用所有服務類型，例如寵物友善/24小時營業）；有值=該服務類型專屬標籤（例如`type=6`餐廳訂位專屬的中餐廳/泰式料理），各service type自行維護自己的標籤，不要求跨type共用。名稱唯一性範圍縮小為同一`service_type`內（`UNIQUE(service_type, name)`），通用標籤另用partial unique index保證全域唯一。`GET /labels`可用`service_type` query參數篩選，回傳「通用+該類型專屬」標籤聯集。
- **user_accounts / vendor_accounts**：會員 / 商家後台登入帳號（密碼 bcrypt 雜湊，個資 AES-256-GCM 加密存 `bytea`，同時有明文欄位對應的 `_hash` 欄位可查詢比對）
- **mms_order_record**：訂單/訂位統一紀錄表
- **mms_order_review**：訂單評價，`record_id` 直接沿用對應 `mms_order_record.record_id`（1:0..1，無獨立序列），一筆訂單至多一筆評價由 PK 天然保證。新增評價會同步把訂單的 `comment_status` 改成 `02`。`GET /services/{service_id}/reviews` 是全平台唯一不需身分驗證即可呼叫的公開端點（評價牆，回傳精簡過的 `PublicReviewOut`）。bff_server 所有回傳訂單的端點（`view_orders`、`list_orders`、`create_order`、`update_order`）都會用 `review_utils.py` 把對應評價併入訂單物件的 `review` 欄位（沒評價過則為 `null`），前端不需要另外呼叫評價 API。使用者提交評價走 `app_api.py` 的 `POST /orders/{record_id}/review`，修改評價走 `PATCH /users/{inbr_account_id}/orders/{record_id}/review`（皆為轉發 api_server，業務規則如訂單須完成、身分比對、防重複皆由 api_server 驗證）。批次查詢完整評價（回傳未經裁切的 `ReviewOut` 完整欄位，用 `client.py` 的 `get_all_items` 自動處理分頁抓取全部資料）：商家視角在 `merchant_api.py` 的 `GET /vendors/{id}/reviews`，APP 端依服務項目查詢在 `app_api.py` 的 `GET /services/{id}/reviews`（注意跟 api_server 同名的公開評價牆端點不同，這支回傳含身分關聯的完整內容，不適合當公開頁面用）
- **pms_form 系列**：諮詢表單結構（form → group → topic → option/media）。merchant_api.py 的 `POST /forms` 提供一次性建立表單+巢狀題組/題目/選項的組裝端點；`PATCH /forms/{id}` 提供差異比對式的完整表單更新（前端傳整包巢狀結構，帶 `id` 的項目視為更新、不帶 `id` 視為新增、現況有但 payload 沒帶到的視為刪除，依 選項→題目→題組 順序刪除、表單→題組→題目→選項 順序新增/更新）；兩者皆因 api_server 只有單筆 CRUD 端點、無跨資源交易機制，BFF 依序呼叫多支端點組裝，中途失敗不會自動回滾。`GET /vendors/{id}/forms`（清單，僅主檔）、`GET /forms/{id}/full`（單張表單完整巢狀內容，直接轉發 api_server 現成端點）。`app_api.py` 的 `GET /services/{service_id}/form/full` 給 AI 管家用：走 `cms_homepage_service.form_id` 取該服務項目對應表單的完整內容（組合 `GET /services/{id}` 取 form_id + `GET /forms/{form_id}/full`），`form_id` 為 NULL 時回 404 並在 detail 說明「尚未設定對應表單」。**不要改用 `pms_form.service_vendor_id` 反查商家表單**：實際資料裡單一商家名下有十幾張表單（含測試用、給別的服務用的），沒有可靠依據挑出正確那張，`form_id` 就是為補這個查詢缺口而加的。
- **pms_form_feedback**：使用者填寫表單後的回饋記錄
- **mms_review_summary_service / mms_review_summary_vendor**：評價AI摘要表（`Database/database/mms_review_summary.sql`，新增功能，目前無種子資料）。皆為「覆寫式快取」設計，同一個key只保留最新1筆，重新生成時直接覆蓋，不留歷史版本：
  - `mms_review_summary_service`：PK為`service_id`（與`cms_homepage_service.id`共用值），彙整單一服務項目底下所有`mms_order_review`的AI摘要，面向使用者與供應商共用同一份內容。
  - `mms_review_summary_vendor`：PK為`service_vendor_id`，彙整供應商名下所有服務的評價，多一個`service_breakdown`欄位（JSON陣列快取各服務的評價數/平均分），僅供供應商後台使用。
  - 兩張表都有`generate_status`（`00`待生成/`01`生成中/`02`已完成/`03`失敗）與`latest_review_cre_time`欄位，用於支援非同步生成流程與判斷摘要是否過期需重新生成。
  - `api_server/app/routers/summaries.py` 已實作對應端點（`GET`/`PUT`/`PATCH .../status`/`DELETE`，服務項目與供應商各一組，供應商多一支清單端點），**只負責讀寫這兩張表，不呼叫LLM**，實際生成AI摘要內容的流程（呼叫Bedrock等模型）由上層服務負責再把結果`PUT`回來。`GET`回應含計算欄位`is_stale`（即時比對`mms_order_review`最新聚合值判斷摘要是否過期）。`bff_server`尚未有對應轉發端點。詳細規格見`Database/API_Reference.md`「I2. 評價AI摘要」章節。

完整規格見 `Database/API_Reference.md` 和 `Database/database/*.sql` 的欄位註解（COMMENT ON COLUMN）。整體18張表的關係圖與逐欄位種子資料覆蓋狀況見 `Database/database/README.md`。

## bff_server 開發慣例

- 每支 API 的 docstring 統一格式：**輸入** / **輸出** / **說明**，用 Markdown 語法寫（`-` 條列、` ```json ` code block），因為 FastAPI 會把 docstring 直接渲染進 Swagger UI（`/docs`），純縮排文字塊在 Markdown 裡不會保留換行。
- 型別標註走簡短風格（`(path, int)`、`(query, string, 可選)`），避免寫完整 Python union type，文件會太長難讀。
- payload 目前先用 `dict` 接收（快速開發），還沒上 Pydantic model 做驗證，之後有空可以補上。
- `TODO` 註解標記之後要補的排序/篩選邏輯，目前多數端點是「轉發 api_server + 少量組裝」的最小可行版本。
- **可選 query 參數不用怕傳 None**：`client.py` 的 `request` / `get_optional` 會統一把 `params` 裡值為 None 的 key 濾掉。這不是潔癖 —— httpx 會把 `{"type": None}` 序列化成 `type=`（空字串），api_server 收到空字串會當成「篩選 type 等於空字串」而回 0 筆。實際踩過：`GET /forms?service_vendor_id=1` 有 14 筆，多帶一個空的 `type=` 就變 0 筆，導致商家後台表單清單整頁是空的。

## agent_service 開發慣例

- **tool 設計是資料驅動的，不寫死服務流程**。`get_service_form` 把 `pms_form` 的題目結構交給模型，模型自己決定怎麼問，所以一套 tool 就能處理全部 7 種服務類型。新增服務類型時通常只要加 `ServiceType` member，不用加 tool。
- **模型輸出一律當不可信輸入**。`propose_submission` 會拿真實表單結構逐項驗證（form_id、service_id 歸屬、topic_id 存在、必填題齊全、單複選答案在 options 內）。實測模型會把序號當 id 傳（`vendor_id=2`、`form_id=1`），沒驗證就會產生錯誤草稿。
- **tool 的 error 訊息要能教模型自我修正**，寫清楚「你可能傳錯什麼、正確值去哪裡拿」，不要只回「參數錯誤」。實測模型收到具體錯誤後會自己重抓正確 id 再試。
- **跨輪的 id 靠 `session_state.py` 帶**，不靠模型記憶。`memory.load_history` 只還原純文字不還原 toolResult（Converse API 要求 toolResult 必須配對同一輪的 toolUse），所以已解析的 `vendor_id` / `form_id` / `topic_id` 要另外渲染進系統提示。
- **`_consume` 的 toolUse input 是分片抵達的 JSON 字串**，必須累積到 `contentBlockStop` 才能 parse，對單一 delta 做 `json.loads` 會隨機失敗。
- **entrypoint 要 yield dict，不要自己格式化 SSE**。`BedrockAgentCoreApp._convert_to_sse` 會把每個 yield 的值包成 `data: {json}\n\n`；自己先包一次會變成雙重包裝，前端解不出來。這就是 `schemas.event()` 回傳 dict 而不是字串的原因。
- 事件型別（`text_delta` / `tool_start` / `ui` / `draft` / `done` / `error`）改動時，這三處必須一起改：
  `agent_service/.../schemas.py`、`ai-butler-app/lib/data/remote/http_butler_ai_service.dart`、
  `flutter_ai_script/lib/agent/agent_event.dart`。
- **bff_server 是原樣轉發 SSE，不重新組裝**。agent 端已經是 `data: {...}\n\n` 格式，重組只會讓兩邊協定不同步。
- **前端切 SSE 不能靠 chunk 邊界**。TCP 會任意切割位元組，`http_butler_ai_service.dart` 的 `_sseLines` 用緩衝區累積到換行才算一行；把每個 chunk 當一筆事件會隨機解析失敗。
- AI 管家的 `receiveTimeout` 要放寬到分鐘級（目前 3 分鐘）。`ApiClient` 預設 20 秒，但模型思考加多次 tool 往返很容易超過，所以那支 service 用自己的 Dio 實例。
- `app/AiButler/` 內部是**平坦 import**（`from config import ...`），因為 codeLocation 目錄本身就是 package 根。不要寫成 `from app.config import ...`。
- 本機開發時 `BFF_BASE_URL` 留空就走 `backend.py` 的內建假資料，不需要等後端就緒。**部署時務必確認 `agentcore.json` 的 `BFF_BASE_URL` 有值** —— 留空的話 agent 會安靜地回假資料（`鳥花枝居酒屋`／`初魚鐵板燒`／vendor id 101/102），看起來一切正常但完全沒碰 DB。假資料的 topic_id 是 1~5 與 11~14，真實資料是三位數，用這個可以快速判斷。
- **表單是掛在服務項目上，不是商家上**。`get_service_form` 收 `service_id` 而非 `vendor_id`，走 `cms_homepage_service.form_id`。`find_service_vendors` 回傳的每個服務項目帶 `has_form`，讓模型先知道哪些能線上填單，不會挑了之後才撞牆。

## 已知限制（上線前必須處理，demo 階段暫緩）

- 完全沒有身分驗證機制（登入只回傳識別碼，沒有 JWT/Session token）。`agent_service` 的 `actor_id` 是呼叫端聲明的，不是驗證過的身分 —— 草稿的 owner 檢查只能防手誤，不是安全機制。
- CORS 允許所有來源（`*`）
- RDS 密碼明文放在 EC2 的 `.env` 檔案
- `agent_service` 的草稿與 session 工作集存在 process 記憶體，Runtime 實例回收就沒了。要跨實例存活得換 DynamoDB。
- `agent_service` 的 runtime `networkMode` 是 `PUBLIC` 且沒設 `authorizerType`，等於用 SigV4（IAM）驗證、沒有使用者層級授權。要接 Flutter 前端時得補 Cognito JWT authorizer（範例見 `CustomerSupport/agentcore/agentcore.json` 的 `customJwtAuthorizer`）。

詳見 `Database/部署手冊.md` 第 8 章「上線前安全檢查清單」。

## Steering 自我維護規則

當你的改動涉及以下任何一項時，**必須**同步更新本 steering 文件（`.kiro/steering/project-overview.md`）：

- 新增、刪除或重新命名 API 端點（`app_api.py` / `merchant_api.py`）
- 調整目錄結構或新增重要檔案
- 架構層級變動（例如新增 service layer、新增 middleware）
- 部署流程或 AWS 環境資訊變更（IP、port、service name、AgentCore Runtime 設定）
- 資料庫 table / 欄位結構變更（反映在「資料庫核心概念」段落）
- 開發慣例調整（docstring 格式、型別風格等）
- 新增/修改 agent tool，或改動 SSE 事件協定

更新時保持文件簡潔，只修改受影響的段落，不要整份重寫。

**不要在本文件寫「幾支 API」「幾個端點」這類會隨時變動的計數。**
實測這些數字在四次合併裡每次都跟實際不符，而且是 merge conflict 的主要來源。
端點清單看 `bff_server/API.md` 與 `Database/API_Reference.md`，或直接數
`@router` 裝飾器 / 打 `/openapi.json`。

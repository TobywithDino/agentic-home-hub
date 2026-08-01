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
│   ├── API_Reference.md      api_server 78 個端點完整規格
│   ├── database/             DDL（*.sql）+ 種子資料（*.json）+ 建置腳本
│   └── api_server/           FastAPI，直接操作 PostgreSQL，跑在 EC2 8000 埠
│       └── app/routers/      geo / catalog / accounts / forms / feedbacks / orders
├── bff_server/               我方負責：BFF（Backend For Frontend）
│   ├── README.md             架構說明 + 端點對應表
│   ├── deploy.sh             一鍵部署到 EC2 的腳本
│   └── app/
│       ├── client.py         封裝呼叫 Database/api_server 的 httpx client
│       ├── config.py         環境變數設定
│       └── routers/
│           ├── app_api.py       APP 前端呼叫的 5 支 API
│           └── merchant_api.py  商家後台呼叫的 7 支 API
├── agent_service/            我方負責：AI 管家（AgentCore Runtime，CodeZip 部署，不用 Docker）
│   ├── agentcore/
│   │   ├── agentcore.json    宣告式設定：runtime + memory（源頭真相，別改生成的 CDK）
│   │   └── aws-targets.json  部署目標（account + region）
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
└── flutter_ai_script/        我方負責：Flutter 端 AI 管家相關程式碼
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

改完 `bff_server/` 程式碼後，用 `bff_server/deploy.sh` 部署到 EC2：

```bash
cd bff_server
bash deploy.sh
```

流程：打包 → 上傳 S3（`s3://aiwave-deploy-728259505479-uswest2/`）→ SSM 送指令到 EC2 解壓、裝依賴、重啟 `bff-api` service → 確認安全群組開 8100 埠 → health check 驗證。

需要先設定好 AWS CLI profile（`aws configure --profile agentic-home-hub`）才能執行，憑證跟保管人要。

## 部署 agent_service（AI 管家）

不跑在 EC2 上，跑在 AWS Bedrock AgentCore Runtime，全部透過 AgentCore CLI 操作。
**不需要 Docker** —— 用 CodeZip build，CLI 打包 zip 上傳，AWS 管語言執行環境。

```bash
cd agent_service
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
  1=居家清潔 2=家電清洗 3=包裹寄送 6=餐廳訂位 9=美食外送 10=水電修繕 11=商城購物
- **label / service_label**：標籤主檔 + 服務項目與標籤的多對多關聯表
- **user_accounts / vendor_accounts**：會員 / 商家後台登入帳號（密碼 bcrypt 雜湊，個資 AES-256-GCM 加密存 `bytea`，同時有明文欄位對應的 `_hash` 欄位可查詢比對）
- **mms_order_record**：訂單/訂位統一紀錄表
- **pms_form 系列**：諮詢表單結構（group → topic → option/media）
- **pms_form_feedback**：使用者填寫表單後的回饋記錄

完整規格見 `Database/API_Reference.md` 和 `Database/database/*.sql` 的欄位註解（COMMENT ON COLUMN）。

## bff_server 開發慣例

- 每支 API 的 docstring 統一格式：**輸入** / **輸出** / **說明**，用 Markdown 語法寫（`-` 條列、` ```json ` code block），因為 FastAPI 會把 docstring 直接渲染進 Swagger UI（`/docs`），純縮排文字塊在 Markdown 裡不會保留換行。
- 型別標註走簡短風格（`(path, int)`、`(query, string, 可選)`），避免寫完整 Python union type，文件會太長難讀。
- payload 目前先用 `dict` 接收（快速開發），還沒上 Pydantic model 做驗證，之後有空可以補上。
- `TODO` 註解標記之後要補的排序/篩選邏輯，目前多數端點是「轉發 api_server + 少量組裝」的最小可行版本。

## agent_service 開發慣例

- **tool 設計是資料驅動的，不寫死服務流程**。`get_service_form` 把 `pms_form` 的題目結構交給模型，模型自己決定怎麼問，所以一套 tool 就能處理全部 7 種服務類型。新增服務類型時通常只要加 `ServiceType` member，不用加 tool。
- **模型輸出一律當不可信輸入**。`propose_submission` 會拿真實表單結構逐項驗證（form_id、service_id 歸屬、topic_id 存在、必填題齊全、單複選答案在 options 內）。實測模型會把序號當 id 傳（`vendor_id=2`、`form_id=1`），沒驗證就會產生錯誤草稿。
- **tool 的 error 訊息要能教模型自我修正**，寫清楚「你可能傳錯什麼、正確值去哪裡拿」，不要只回「參數錯誤」。實測模型收到具體錯誤後會自己重抓正確 id 再試。
- **跨輪的 id 靠 `session_state.py` 帶**，不靠模型記憶。`memory.load_history` 只還原純文字不還原 toolResult（Converse API 要求 toolResult 必須配對同一輪的 toolUse），所以已解析的 `vendor_id` / `form_id` / `topic_id` 要另外渲染進系統提示。
- **`_consume` 的 toolUse input 是分片抵達的 JSON 字串**，必須累積到 `contentBlockStop` 才能 parse，對單一 delta 做 `json.loads` 會隨機失敗。
- **entrypoint 要 yield dict，不要自己格式化 SSE**。`BedrockAgentCoreApp._convert_to_sse` 會把每個 yield 的值包成 `data: {json}\n\n`；自己先包一次會變成雙重包裝，前端解不出來。這就是 `schemas.event()` 回傳 dict 而不是字串的原因。
- 事件型別（`text_delta` / `tool_start` / `ui` / `draft` / `done` / `error`）改動時，`schemas.py` 和 `flutter_ai_script/lib/agent/agent_event.dart` 必須一起改。
- `app/AiButler/` 內部是**平坦 import**（`from config import ...`），因為 codeLocation 目錄本身就是 package 根。不要寫成 `from app.config import ...`。
- 本機開發時 `BFF_BASE_URL` 留空就走 `backend.py` 的內建假資料，不需要等後端就緒。

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

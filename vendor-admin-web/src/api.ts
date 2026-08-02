// ============================================================
// API Module - 智慧社區服務媒合平台 廠商端管理後台
// ============================================================
//
// 對接 BFF API Server 商家後台全部 14 支 merchant-api 端點：
//
//  認證與商家設定
//   1. POST  /merchant-api/auth/login                                      登入
//   2. PATCH /merchant-api/vendors/{service_vendor_id}                      更新商家簡介與設定
//  諮詢單
//   3. GET   /merchant-api/vendors/{service_vendor_id}/feedbacks            取得諮詢單清單
//   4. PATCH /merchant-api/feedbacks/{feedback_no}/status                   更新狀態(接單/婉拒)
//  訂單
//   5. POST  /merchant-api/orders                                          建立訂單
//   6. GET   /merchant-api/vendors/{service_vendor_id}/orders               取得訂單清單
//   7. PATCH /merchant-api/vendors/{service_vendor_id}/orders/{record_id}   更新訂單狀態
//  服務標籤
//   8. GET   /merchant-api/services/{service_id}/labels                     標籤與勾選狀態
//   9. PUT   /merchant-api/services/{service_id}/labels                     批次設定標籤
//  表單
//  10. GET   /merchant-api/vendors/{service_vendor_id}/forms                表單清單
//  11. GET   /merchant-api/forms/{form_id}/full                             單一表單完整內容
//  12. POST  /merchant-api/forms                                           一鍵建立完整表單
//  13. PATCH /merchant-api/forms/{form_id}                                  更新表單與結構
//  評價
//  14. GET   /merchant-api/vendors/{service_vendor_id}/reviews              顧客評價
//
// 全域規範：
//   - 所有 POST / PATCH / PUT 皆帶 Content-Type: application/json 與 upd_id (UUID)
//   - 所有請求包 try-catch；遇 404 / 500 或後端無資料時退回非空 Mock 保底
//     （Mock 具 vendorId=1 保底機制，確保不回空陣列造成頁面空白）
// ============================================================

import * as mock from './mockApi'

/** BFF 統一入口。merchant-api / app-api 皆掛在同一個 port。 */
export const BASE_URL = 'http://52.10.163.115:8100'

// ─── 登入狀態 ───

/** 預設 vendor_id（登入成功後更新）。同時作為 Mock 保底資料的來源 vendor */
let currentVendorId = 1

/** account_id 為 UUID 字串格式，後端 Pydantic 要求必須是 UUID，不可傳 number */
let currentAccountId: string = '00000000-0000-0000-0000-000000000000'

export function setVendorId(id: number) {
  currentVendorId = id
}

export function getVendorId() {
  return currentVendorId
}

export function setAccountId(id: string) {
  currentAccountId = id
}

export function getAccountId() {
  return currentAccountId
}

/** 取得 upd_id，永遠回傳 UUID 字串（後端 Pydantic 要求） */
function getUpdId(): string {
  return currentAccountId
}

// ─── HTTP Helper ───

/** 帶 HTTP 狀態碼的錯誤，讓呼叫端能區分「認證失敗」與「連線失敗」 */
class ApiError extends Error {
  status: number
  body: string
  constructor(status: number, body: string) {
    super(`API Error ${status}: ${body}`)
    this.name = 'ApiError'
    this.status = status
    this.body = body
  }
}

const defaultHeaders: HeadersInit = {
  'Content-Type': 'application/json',
}

async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const url = `${BASE_URL}${path}`
  const res = await fetch(url, {
    ...options,
    headers: {
      ...defaultHeaders,
      ...options.headers,
    },
  })

  if (!res.ok) {
    const errorBody = await res.text().catch(() => '')
    throw new ApiError(res.status, errorBody || res.statusText)
  }

  // 部分 PATCH 可能回 204 或空 body，避免 res.json() 拋錯
  const text = await res.text()
  return (text ? JSON.parse(text) : {}) as T
}

/**
 * 組裝寫入類請求的 body，統一附加 upd_id（UUID）。
 * 所有 POST / PATCH / PUT 一律透過此函式序列化，確保規範不遺漏。
 */
function jsonBody(payload: Record<string, unknown>): string {
  return JSON.stringify({ ...payload, upd_id: getUpdId() })
}

/** 後端分頁回應格式 */
interface ApiListResponse<T> {
  total: number
  limit: number
  offset: number
  items: T[]
}

/**
 * 正規化列表回應：部分端點回 { items: [...] } 分頁物件（如 feedbacks），
 * 部分直接回陣列（如 orders / forms / labels / reviews），兩者都能安全取出。
 */
function extractItems<T>(data: ApiListResponse<T> | T[] | null | undefined): T[] {
  if (!data) return []
  if (Array.isArray(data)) return data
  return data.items ?? []
}

const bySort = (a: { sort?: number | null }, b: { sort?: number | null }) =>
  (a.sort ?? 0) - (b.sort ?? 0)

const pad2 = (n: number) => String(n).padStart(2, '0')

/**
 * 取本地時區的 yyyy-MM-dd。
 *
 * 不使用 toISOString()，因為它會轉成 UTC —— 台灣是 UTC+8，
 * 直接用 UTC 日期比對會讓當日凌晨 8 點前的訂單被算到前一天。
 */
function toLocalDateKey(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
}

/** 取本地時區的 yyyy-MM */
function toLocalMonthKey(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`
}

/** 將後端時間字串轉為 Date，無效則回 null */
function parseTime(raw: string | null | undefined): Date | null {
  if (!raw) return null
  const d = new Date(raw)
  return Number.isNaN(d.getTime()) ? null : d
}

/**
 * 取訂單的代表時間：優先用訂單成立時間，退而用建檔時間。
 * 用於「近七天趨勢」的分桶依據。
 */
function orderPlacedAt(o: ApiOrderItem): Date | null {
  return parseTime(o.order_time) ?? parseTime(o.cre_time)
}

// ─── Error callback (Toast 顯示用) ───

type ErrorCallback = (message: string) => void
let onApiError: ErrorCallback | null = null

/** 註冊全域 API 錯誤回呼，頁面可透過此函式接收錯誤訊息並顯示 Toast */
export function registerApiErrorHandler(cb: ErrorCallback) {
  onApiError = cb
}

function notifyError(message: string) {
  console.warn('[API Error]', message)
  if (onApiError) onApiError(message)
}

// ════════════════════════════════════════════════════════════
// 1. 登入：POST /merchant-api/auth/login
// ════════════════════════════════════════════════════════════

interface LoginResponse {
  service_vendor_id?: number
  account_id?: string // UUID 字串
  detail?: string
}

/**
 * 登入
 *
 * 錯誤處理刻意區分兩種情況，但兩種都**不**放行進入系統：
 *   - 401 / 403：帳密錯誤 → 回傳後端的錯誤訊息
 *   - 連線失敗 / 5xx：碰不到伺服器 → 回傳連線失敗訊息
 * 沒有離線登入。過去以 Mock 放行會讓使用者在「後端全掛」時仍看到
 * 一整套假資料，誤判系統正常。
 */
export async function login(
  account: string,
  password: string
): Promise<{ success: boolean; vendorId?: number; message?: string }> {
  try {
    const data = await apiFetch<LoginResponse>('/merchant-api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ account, password }),
    })

    if (data.service_vendor_id) {
      currentVendorId = data.service_vendor_id
      if (data.account_id) {
        currentAccountId = data.account_id // 存 UUID 字串
      }
      return { success: true, vendorId: data.service_vendor_id }
    }

    return { success: false, message: data.detail || '登入失敗' }
  } catch (err) {
    // 認證失敗不降級：讓使用者知道是帳密問題，而不是誤導成離線模式
    if (err instanceof ApiError && (err.status === 401 || err.status === 403)) {
      let message = '帳號或密碼錯誤'
      try {
        const parsed = JSON.parse(err.body)
        if (parsed?.detail) message = String(parsed.detail)
      } catch {
        /* body 非 JSON，沿用預設訊息 */
      }
      return { success: false, message }
    }

    console.warn('[Login] Real API unreachable:', err)
    return {
      success: false,
      message: '無法連線至伺服器，請確認後端服務是否正常後再試',
    }
  }
}

// ════════════════════════════════════════════════════════════
// 2. 設定商家資訊：PATCH /merchant-api/vendors/{service_vendor_id}
// ════════════════════════════════════════════════════════════

/** GET /merchant-api/vendors/{service_vendor_id} 回應中的管理帳號 */
interface ApiVendorAccount {
  id: string // UUID，即 PATCH 時要帶的 account_id
  service_vendor_id?: number
  account?: string | null
  contact_name?: string | null
  contact_mobile?: string | null
  contact_email?: string | null
  is_2fa_enabled?: string | null
  last_login_time?: string | null
  is_enable?: string | null
  cre_time?: string | null
  upd_time?: string | null
  [key: string]: unknown
}

/** GET /merchant-api/vendors/{service_vendor_id} 回應 */
interface ApiVendorProfileResponse {
  vendor_profile?: {
    id?: number
    name?: string | null
    description?: string | null
  } | null
  accounts?: ApiVendorAccount[] | null
}

/**
 * getVendorProfile - 讀取商家資訊
 * GET /merchant-api/vendors/{service_vendor_id}
 *
 * 回傳 { vendor_profile, accounts }。accounts 是該商家底下的管理帳號清單，
 * 其中每筆的 `id` 就是 PATCH 更新聯絡方式時要帶的 `account_id`。
 *
 * 多帳號時優先取「登入時的 account_id」對應的那筆，找不到才退回第一筆；
 * 同時把解析結果寫回 currentAccountId，讓後續 PATCH 帶到正確的帳號。
 */
export async function getVendorProfile(): Promise<mock.VendorProfile | null> {
  try {
    const data = await apiFetch<ApiVendorProfileResponse>(
      `/merchant-api/vendors/${currentVendorId}`
    )

    const accounts = data.accounts ?? []
    const account =
      accounts.find((a) => a.id === currentAccountId) ?? accounts[0] ?? undefined

    // 以後端實際帳號校正 currentAccountId，讓後續 PATCH 帶到正確的 account_id
    if (account?.id) currentAccountId = account.id

    // 後端沒給的欄位就留空，不用假資料補
    return {
      name: data.vendor_profile?.name ?? '',
      description: data.vendor_profile?.description ?? '',
      adminName: account?.contact_name ?? '',
      adminPhone: account?.contact_mobile ?? '',
      adminEmail: account?.contact_email ?? account?.account ?? '',
    }
  } catch (err) {
    console.warn('[VendorProfile] Real API failed:', err)
    notifyError('無法載入商家資料，請稍後再試')
    return null
  }
}

/**
 * updateVendorProfile
 *
 * Body 分兩個互相獨立的區塊，皆可選：
 *   vendor_profile   → 商家屬性（name / description）
 *   account_contact  → 管理帳號聯絡方式與密碼，需搭配 account_id 才生效
 */
export async function updateVendorProfile(
  data: Partial<mock.VendorProfile> & { newPassword?: string }
): Promise<{ success: boolean; profile: mock.VendorProfile | null }> {
  try {
    const accountContact: Record<string, unknown> = {}
    if (data.adminName !== undefined) accountContact.contact_name = data.adminName
    if (data.adminPhone !== undefined) accountContact.contact_mobile = data.adminPhone
    if (data.adminEmail !== undefined) accountContact.contact_email = data.adminEmail
    if (data.newPassword) accountContact.password = data.newPassword

    const payload: Record<string, unknown> = {}
    if (data.name !== undefined || data.description !== undefined) {
      payload.vendor_profile = { name: data.name, description: data.description }
    }
    // account_contact 需搭配 account_id 才會生效
    if (Object.keys(accountContact).length > 0) {
      payload.account_id = getAccountId()
      payload.account_contact = accountContact
    }

    await apiFetch(`/merchant-api/vendors/${currentVendorId}`, {
      method: 'PATCH',
      body: jsonBody(payload),
    })

    // 後端僅回傳「有更新的區塊」，改以 GET 回讀完整資料，確保畫面與 DB 一致
    const profile = await getVendorProfile()
    return { success: true, profile }
  } catch (err) {
    // ⚠️ 不退回 Mock：假的 success 會讓畫面顯示已儲存，但後端什麼都沒寫入
    console.warn('[UpdateVendorProfile] Real API failed:', err)
    throw err
  }
}

// ════════════════════════════════════════════════════════════
// 3 & 4. 諮詢單 (Feedbacks)
// ════════════════════════════════════════════════════════════

/**
 * 後端 feedback 原始結構（欄位名以 Swagger 為準）
 *
 * 容易搞錯的地方：
 *   - 電話是 contact_mobile，不是 contact_phone
 *   - 地址拆成 county / district / detail 三段，沒有單一 address
 *   - 補充說明是 description，不是 remark
 *   - feedback_content 是「結構依表單定義」的物件，不是字串
 *   - status / is_read 是代碼字串
 */
interface ApiFeedbackItem {
  feedback_no: string
  service_id?: number | null
  service_vendor_id?: number
  platform_code?: string | null
  form_id?: number | null
  form_type?: string | null
  feedback_content?: Record<string, unknown> | string | null
  contact_name?: string | null
  contact_mobile?: string | null
  contact_email?: string | null
  contact_address_county?: string | null
  contact_address_district?: string | null
  contact_address_detail?: string | null
  description?: string | null
  inbr_account_id?: string
  /** 偏好聯絡時間，實測為代碼字串（如 "1"），非可讀文字 */
  preferred_contact_time?: string | null
  is_read?: string | boolean | null // "0"=未讀 "1"=已讀
  status?: string | null // "0"=未處理 "1"=處理中 "2"=已完成
  cre_time?: string | null
  upd_time?: string | null
  [key: string]: unknown
}

/** preferred_contact_time 代碼對應。未知代碼原樣顯示 */
const PREFERRED_TIME_LABELS: Record<string, string> = {
  '1': '上午',
  '2': '下午',
  '3': '晚上',
  '0': '不限',
}

// 後端只有三段處理進度： "0"=未處理  "1"=處理中  "2"=已完成
// 前端語意有三種結果：    待處理 / 已接單 / 已拒絕
//
// ⚠️ 兩者非一對一：後端沒有「已拒絕」狀態，婉拒與正常完成都落在 "2"，
// 也沒有欄位存放婉拒原因。因此「已拒絕」無法從後端還原 —— 重新載入後
// 被婉拒的諮詢單會顯示為「已接單」。若要正確支援，需請後端在
// pms_form_feedback 增加拒絕狀態碼與原因欄位。

const FEEDBACK_STATUS_TO_LOCAL: Record<string, mock.FeedbackStatus> = {
  '0': '待處理',
  '1': '已接單',
  '2': '已接單', // 已完成：代表曾經受理過
}

const FEEDBACK_STATUS_ACCEPTED = '1' // 處理中
const FEEDBACK_STATUS_CLOSED = '2' // 已完成（後端無專屬拒絕狀態）

/**
 * 組合外層的三段式地址欄位
 *
 * ⚠️ 實測 contact_address_county / _district 存的是**代碼**（如 "01" / "002"），
 * 不是可讀名稱，直接拼接會得到「01002」。可讀地址其實在 feedback_content
 * 的地區選單答案裡（countyName / districtName / addressDetail），
 * 因此 mapper 會優先採用那份，此函式僅作為最後的退路。
 */
function joinAddressFromCodes(item: ApiFeedbackItem): string {
  const parts = [
    item.contact_address_county,
    item.contact_address_district,
    item.contact_address_detail,
  ].filter((p): p is string => !!p && p.trim() !== '')
  return parts.length > 0 ? `（代碼）${parts.join('-')}` : '未提供'
}

// ─── feedback_content 解析 ───
//
// 實際結構為三層巢狀（非扁平的「題目→答案」對應表）：
//   { data: [ { topicId, type, answerList: [ {...} ] } ], formId, calculations }
//
// ⚠️ 刻意**不依賴表單結構**來取題目標題。原因：表單的 PATCH 是差異比對式，
// 編輯表單時未帶 id 的題目會被刪除重建並取得新 id，導致舊 feedback 的
// topicId 指向已不存在的題目（實測 form 9 的 topics 已從 95/97/98... 變成
// 136/146/147）。因此僅使用 feedback 自身攜帶的可讀欄位。

/** answerList 中的單一答案 */
interface ApiFeedbackAnswer {
  answer?: string | null
  /** 選項題的選項名稱，比 answer 更精簡 */
  title?: string | null
  remark?: string | null
  imgUrl?: string[] | null
  /** type 5 地區選單專用 */
  countyName?: string | null
  districtName?: string | null
  addressDetail?: string | null
  sort?: number | null
  [key: string]: unknown
}

/** data 陣列中的單一題目作答 */
interface ApiFeedbackTopicAnswer {
  topicId?: number
  type?: string | null
  answerList?: ApiFeedbackAnswer[] | null
}

/**
 * 新版（App 現行）作答結構中的單一答案
 *
 * 實測 feedback_content 已改為 `{ answers: [...], form_id }`，與舊版差異：
 *   - `answers` 取代 `data`、`topic_id` 取代 `topicId`、`value` 取代 `answerList`
 *   - `type` 改為兩位補零字串（"03"），舊版是 "3"
 *   - **不再夾帶任何可讀文字**：選項只有 option_id、地區只有代碼
 * 因此必須搭配 FormLookup 才還原得出「題目：答案」。
 */
interface ApiFeedbackNewAnswer {
  topic_id?: number
  type?: string | null
  value?: unknown
}

interface ApiFeedbackContentObject {
  /** 新版格式 */
  answers?: ApiFeedbackNewAnswer[] | null
  /** 舊版格式 */
  data?: ApiFeedbackTopicAnswer[] | null
  formId?: number
  form_id?: number
  calculations?: unknown
  [key: string]: unknown
}

/** 選擇題型別（其答案適合作為 Badge 顯示） */
const CHOICE_TOPIC_TYPES = ['3', '4']

/** parseFeedbackContent 的產出（新舊格式共用） */
interface ParsedFeedbackContent {
  content: string
  selectedOptions: string[]
  detectedName?: string
  detectedPhone?: string
  detectedEmail?: string
  detectedAddress?: string
}

/**
 * 題目型別代碼正規化："03" → "3"
 * 表單結構用未補零、feedback 用補零，兩邊要先對齊才能查表。
 */
function normalizeTopicType(raw: unknown): string {
  const s = String(raw ?? '').trim()
  if (s === '') return ''
  return s.replace(/^0+/, '') || '0'
}

/** 純量答案（簡答/詳答/備註/日期）轉可讀字串 */
function scalarValueToText(value: unknown): string {
  if (value == null) return ''
  if (typeof value === 'string') return value.trim()
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  if (Array.isArray(value)) {
    return value.map(scalarValueToText).filter(Boolean).join('、')
  }
  if (typeof value === 'object') {
    // 未知物件：只取字串／數字葉節點，不倒 JSON 進畫面
    return Object.values(value as Record<string, unknown>)
      .filter(
        (v): v is string | number =>
          (typeof v === 'string' && v.trim() !== '') || typeof v === 'number'
      )
      .map((v) => String(v).trim())
      .join(' / ')
  }
  return ''
}

/**
 * 單選／複選答案：把 option_id 還原成選項名稱
 *
 * value 實測為 `{ quantity, option_id }`，複選時為其陣列。
 * 查不到選項名稱時顯示 `選項 #id`，不靜默丟棄（避免答案整題消失）。
 */
function choiceValueToTexts(value: unknown, optionNames?: Map<number, string>): string[] {
  const entries = Array.isArray(value) ? value : [value]
  const texts: string[] = []

  for (const entry of entries) {
    if (entry == null) continue
    let optionId: number | undefined
    let quantity: number | undefined

    if (typeof entry === 'object') {
      const o = entry as Record<string, unknown>
      const rawId = o.option_id ?? o.optionId ?? o.answerId ?? o.id
      if (typeof rawId === 'number') optionId = rawId
      else if (typeof rawId === 'string' && /^\d+$/.test(rawId.trim())) {
        optionId = Number(rawId.trim())
      }
      if (typeof o.quantity === 'number') quantity = o.quantity

      // 部分來源仍會夾帶文字答案，有就直接用
      const rawText = o.answer ?? o.title ?? o.option_name
      if (typeof rawText === 'string' && rawText.trim() !== '') {
        const t = rawText.trim()
        texts.push(quantity != null && quantity > 1 ? `${t} ×${quantity}` : t)
        continue
      }
    } else if (typeof entry === 'number') {
      optionId = entry
    } else if (typeof entry === 'string') {
      const t = entry.trim()
      if (t === '') continue
      if (/^\d+$/.test(t)) optionId = Number(t)
      else {
        texts.push(t)
        continue
      }
    }

    if (optionId == null || Number.isNaN(optionId)) continue
    const label = optionNames?.get(optionId) ?? `選項 #${optionId}`
    texts.push(quantity != null && quantity > 1 ? `${label} ×${quantity}` : label)
  }

  return texts
}

/**
 * 地區答案轉可讀字串
 *
 * ⚠️ 新版只給 county_code / district_code，而 BFF（:8100）目前沒有
 * 縣市／行政區名稱查詢端點，表單的 county_district_relations 實測也是空陣列，
 * 因此無法還原可讀地名 —— 標明「（代碼）」以免商家誤讀為地址。
 */
function regionValueToText(value: unknown): string {
  if (value == null) return ''
  if (typeof value === 'string') return value.trim()
  if (typeof value !== 'object') return String(value)

  const o = value as Record<string, unknown>
  const pick = (...keys: string[]) => {
    for (const k of keys) {
      const v = o[k]
      if (typeof v === 'string' && v.trim() !== '') return v.trim()
    }
    return undefined
  }

  const detail = pick('address_detail', 'addressDetail')
  // 舊版會夾帶名稱，有就優先使用
  const named = [pick('countyName'), pick('districtName'), detail].filter(Boolean)
  if (named.length > 0) return named.join('')

  const codes = [
    pick('county_code', 'countyCode'),
    pick('district_code', 'districtCode'),
  ].filter(Boolean)
  if (codes.length === 0) return detail ?? ''
  return `（代碼）${codes.join('-')}${detail ? ` ${detail}` : ''}`
}

/** 聯絡資料答案（type 8 聯絡資料 / type 10 不含地址）轉可讀字串與辨識欄位 */
function contactValueToParts(value: unknown): {
  text: string
  name?: string
  phone?: string
  email?: string
  address?: string
} {
  if (value == null) return { text: '' }
  if (typeof value !== 'object') return { text: String(value).trim() }

  const o = value as Record<string, unknown>
  const pick = (...keys: string[]) => {
    for (const k of keys) {
      const v = o[k]
      if (typeof v === 'string' && v.trim() !== '') return v.trim()
    }
    return undefined
  }

  const name = pick('name', 'contact_name', 'contactName')
  const mobile = pick('mobile', 'phone', 'contact_mobile', 'contactMobile')
  const landline = pick('landline', 'tel', 'contact_landline')
  const email = pick('email', 'contact_email', 'contactEmail')
  const address = pick('address', 'address_detail', 'addressDetail')

  return {
    text: [name, mobile, landline, email, address].filter(Boolean).join(' / '),
    name,
    phone: mobile ?? landline,
    email,
    address,
  }
}

/**
 * 解析新版 answers 陣列
 *
 * 標籤優先序與舊版一致：真實題目標題 → 型別名稱 → 無標籤。
 */
function parseNewFormatAnswers(
  answers: ApiFeedbackNewAnswer[],
  lookup?: FormLookup
): ParsedFeedbackContent {
  const lines: string[] = []
  const options: string[] = []
  let detectedName: string | undefined
  let detectedPhone: string | undefined
  let detectedEmail: string | undefined
  let detectedAddress: string | undefined

  for (const a of answers) {
    const type = normalizeTopicType(a.type)
    const realTitle = a.topic_id != null ? lookup?.topicTitles.get(a.topic_id) : undefined
    const typeLabel = type ? mock.FIELD_INPUT_TYPE_LABELS[mapTopicType(type)] : undefined
    const label = realTitle ?? typeLabel

    // 照片：value 是檔名／路徑陣列，對商家沒有閱讀價值，以張數表示
    if (type === '6') {
      const count = Array.isArray(a.value) ? a.value.length : a.value ? 1 : 0
      if (count > 0) lines.push(`${label ?? '照片'}：${count} 張`)
      continue
    }

    // 選擇題：還原選項名稱，同時供 Badge 使用
    if (CHOICE_TOPIC_TYPES.includes(type)) {
      const texts = choiceValueToTexts(a.value, lookup?.optionNames)
      if (texts.length === 0) continue
      const joined = texts.join('、')
      lines.push(label ? `${label}：${joined}` : joined)
      options.push(...texts)
      continue
    }

    // 地區選單
    if (type === '5') {
      const text = regionValueToText(a.value)
      if (!text) continue
      lines.push(label ? `${label}：${text}` : text)
      if (!detectedAddress) detectedAddress = text
      continue
    }

    // 聯絡資料：結構化欄位，直接餵給聯絡人辨識
    if (type === '8' || type === '10') {
      const parts = contactValueToParts(a.value)
      if (parts.text) lines.push(label ? `${label}：${parts.text}` : parts.text)
      if (!detectedName && parts.name) detectedName = parts.name
      if (!detectedPhone && parts.phone) detectedPhone = parts.phone
      if (!detectedEmail && parts.email) detectedEmail = parts.email
      if (!detectedAddress && parts.address) detectedAddress = parts.address
      continue
    }

    // 其餘型別（簡答／詳答／備註／日期）value 為純量
    const text = scalarValueToText(a.value)
    if (!text) continue
    lines.push(label ? `${label}：${text}` : text)

    // 沒有聯絡型題目時，退回以題目標題／格式判斷
    const byTitle = realTitle ?? ''
    if (!detectedName && /姓名|聯絡人|稱謂/.test(byTitle)) detectedName = text
    else if (!detectedPhone && /電話|手機|行動/.test(byTitle)) detectedPhone = text
    else if (!detectedEmail && /email|信箱|郵件/i.test(byTitle)) detectedEmail = text
    else if (!detectedAddress && /地址|地區|縣市/.test(byTitle)) detectedAddress = text
    else if (!detectedEmail && text.includes('@')) detectedEmail = text
    else if (!detectedPhone && /^0\d[\d-]{7,}$/.test(text)) detectedPhone = text
  }

  return {
    content: lines.join('\n'),
    selectedOptions: options,
    detectedName,
    detectedPhone,
    detectedEmail,
    detectedAddress,
  }
}

// ─── 題目標題還原（Topic Title Lookup）───
//
// feedback_content 只帶 topicId，不含題目標題。要還原「題目：答案」
// 必須用該筆 feedback 自己的 form_id 去取當時的表單結構。
//
// ✅ 快取是安全的：後端表單為**版本化（copy-on-write）**設計 ——
// 修改表單會產生新的 form_id，既有 form_id 的內容永不變動，
// 因此同一個 form_id 只需請求一次，快取不會失效。

/**
 * 表單版本查詢表
 *
 * ⚠️ 新版 feedback_content 幾乎不帶可讀文字：選擇題只給 option_id、
 * 地區只給 county_code/district_code，因此除了題目標題，
 * 也必須一併備好「選項 id → 選項名稱」才還原得出答案。
 */
interface FormLookup {
  /** topic_id → 題目標題 */
  topicTitles: Map<number, string>
  /** option_id → 選項名稱 */
  optionNames: Map<number, string>
}

const EMPTY_FORM_LOOKUP: FormLookup = {
  topicTitles: new Map<number, string>(),
  optionNames: new Map<number, string>(),
}

/** form_id → 該版本表單的查詢表 */
const formLookupCache = new Map<number, FormLookup>()

/**
 * 取得指定表單版本的題目標題與選項名稱對照表
 *
 * 已快取則直接回傳；失敗時回空表但**不快取**，
 * 讓下次載入諮詢單清單時仍有機會重試（避免暫時性網路問題永久降級）。
 */
async function loadFormLookup(formId: number): Promise<FormLookup> {
  const cached = formLookupCache.get(formId)
  if (cached) return cached

  try {
    const full = await apiFetch<ApiFormFull>(`/merchant-api/forms/${formId}/full`)
    const lookup: FormLookup = {
      topicTitles: new Map<number, string>(),
      optionNames: new Map<number, string>(),
    }
    for (const t of full.topics ?? []) {
      const title = (t.title ?? '').trim()
      if (title) lookup.topicTitles.set(t.id, title)
      for (const o of t.options ?? []) {
        const name = (o.option_name ?? '').trim()
        if (name) lookup.optionNames.set(o.id, name)
      }
    }
    formLookupCache.set(formId, lookup)
    return lookup
  } catch (err) {
    console.warn(`[FormTopics] form ${formId} 題目結構載入失敗，將以型別名稱替代:`, err)
    return EMPTY_FORM_LOOKUP
  }
}

/** 批次載入多張表單的查詢表（同一 form_id 只請求一次） */
async function loadLookupsForForms(formIds: number[]): Promise<Map<number, FormLookup>> {
  const unique = [...new Set(formIds)]
  const result = new Map<number, FormLookup>()
  await Promise.all(
    unique.map(async (fid) => {
      result.set(fid, await loadFormLookup(fid))
    })
  )
  return result
}

/** 把單一答案轉為可讀字串；無可讀內容則回空字串 */
function answerToText(a: ApiFeedbackAnswer, topicType?: string | null): string {
  // 地區選單：組合縣市 + 行政區 + 詳細地址
  if (topicType === '5' || a.countyName || a.districtName) {
    const parts = [a.countyName, a.districtName, a.addressDetail].filter(
      (p): p is string => !!p && p.trim() !== ''
    )
    if (parts.length > 0) return parts.join('')
  }
  // 照片：answer 是儲存路徑，對商家沒有閱讀價值，另行以張數表示
  if (topicType === '6') return ''
  return (a.title || a.answer || '').trim()
}

/**
 * 解析 feedback_content
 *
 * 產出兩份資料：
 *   content         → 多行可讀文字，供「客戶描述」區塊顯示
 *   selectedOptions → 僅選擇題（單選/複選）的答案，供 Badge 顯示
 * 另外回傳從答案中辨識出的聯絡資訊與地址，因為外層 contact_* 欄位
 * 只有 hash、沒有明文（實測 contact_name/mobile/email 皆為空字串）。
 */
function parseFeedbackContent(
  raw: ApiFeedbackItem['feedback_content'],
  /** 該筆 feedback 所屬表單版本的題目標題／選項名稱對照表 */
  lookup?: FormLookup
): ParsedFeedbackContent {
  if (!raw) return { content: '', selectedOptions: [] }
  if (typeof raw === 'string') return { content: raw, selectedOptions: [] }

  const obj = raw as ApiFeedbackContentObject

  // 新版格式（App 現行）：{ answers: [...], form_id }
  if (Array.isArray(obj.answers)) {
    return parseNewFormatAnswers(obj.answers, lookup)
  }

  const topics = Array.isArray(obj.data) ? obj.data : []

  // 最後退路：兩種已知格式都不符時逐鍵展平，僅保留可讀的純量值
  if (topics.length === 0) {
    const lines: string[] = []
    for (const [key, value] of Object.entries(obj)) {
      if (value == null || value === '') continue
      if (key === 'calculations' || key === 'formId' || key === 'form_id') continue
      const text = scalarValueToText(value)
      if (text) lines.push(`${key}：${text}`)
    }
    return { content: lines.join('\n'), selectedOptions: [] }
  }

  const lines: string[] = []
  const options: string[] = []
  let detectedName: string | undefined
  let detectedPhone: string | undefined
  let detectedEmail: string | undefined
  let detectedAddress: string | undefined

  for (const t of topics) {
    const answers = [...(t.answerList ?? [])].sort(
      (a, b) => (a.sort ?? 0) - (b.sort ?? 0)
    )
    const photoCount = t.type === '6' ? answers.length : 0
    const texts = answers.map((a) => answerToText(a, t.type)).filter(Boolean)

    // 標籤優先序：真實題目標題 → 型別名稱 → 無標籤
    const realTitle = t.topicId != null ? lookup?.topicTitles.get(t.topicId) : undefined
    const typeLabel = t.type
      ? mock.FIELD_INPUT_TYPE_LABELS[mapTopicType(t.type)]
      : undefined
    const label = realTitle ?? typeLabel

    if (photoCount > 0) {
      lines.push(`${label ?? '照片'}：${photoCount} 張`)
      continue
    }
    if (texts.length === 0) continue

    const joined = texts.join('、')
    lines.push(label ? `${label}：${joined}` : joined)

    // 選擇題答案供 Badge 使用
    if (t.type && CHOICE_TOPIC_TYPES.includes(t.type)) {
      options.push(...texts)
    }

    // 辨識聯絡資訊（外層 contact_* 欄位僅有 hash，無明文可用）。
    // 有真實題目標題時以標題為準，否則退回格式判斷。
    for (const text of texts) {
      const byTitle = realTitle ?? ''
      if (!detectedName && /姓名|聯絡人|稱謂/.test(byTitle)) detectedName = text
      else if (!detectedPhone && /電話|手機|行動/.test(byTitle)) detectedPhone = text
      else if (!detectedEmail && /email|信箱|郵件/i.test(byTitle)) detectedEmail = text
      else if (!detectedAddress && /地址|地區|縣市/.test(byTitle)) detectedAddress = text
      else if (!detectedEmail && text.includes('@')) detectedEmail = text
      else if (!detectedPhone && /^0\d[\d-]{7,}$/.test(text)) detectedPhone = text
      else if (
        !detectedAddress &&
        (t.type === '5' || text.length > 6) &&
        /[縣市區鄉鎮路街]/.test(text)
      )
        detectedAddress = text
      else if (!detectedName && !t.type && text.length <= 10 && !/\d/.test(text))
        detectedName = text
    }
  }

  return {
    content: lines.join('\n'),
    selectedOptions: options,
    detectedName,
    detectedPhone,
    detectedEmail,
    detectedAddress,
  }
}

function mapApiFeedbackToLocal(
  item: ApiFeedbackItem,
  lookup?: FormLookup
): mock.FormFeedback {
  const status = FEEDBACK_STATUS_TO_LOCAL[String(item.status ?? '0')] ?? '待處理'
  const parsed = parseFeedbackContent(item.feedback_content, lookup)

  // 外層 contact_* 欄位實測只有 hash、明文為空字串，
  // 因此優先採用從表單答案中辨識出的可讀值。
  const contactName = item.contact_name || parsed.detectedName || '未提供'
  const phone = item.contact_mobile || parsed.detectedPhone || '未提供'
  const email = item.contact_email || parsed.detectedEmail || '未提供'
  const address = parsed.detectedAddress || joinAddressFromCodes(item)

  const rawPreferred = item.preferred_contact_time
  const preferredContactTime = rawPreferred
    ? (PREFERRED_TIME_LABELS[String(rawPreferred)] ?? String(rawPreferred))
    : '未指定'

  return {
    id: item.feedback_no,
    contactName,
    serviceType: item.form_type || '一般諮詢',
    preferredContactTime,
    status,
    phone,
    email,
    address,
    specialRequirements: item.description || '',
    selectedOptions: parsed.selectedOptions,
    content: parsed.content,
    createdAt: item.cre_time ? new Date(item.cre_time).toLocaleString('zh-TW') : '',
    serviceId: item.service_id ?? undefined,
  }
}

/** 載入單筆 feedback 所屬表單版本的題目／選項對照表後再映射 */
async function mapFeedbackWithTitles(item: ApiFeedbackItem): Promise<mock.FormFeedback> {
  const lookup = item.form_id != null ? await loadFormLookup(item.form_id) : undefined
  return mapApiFeedbackToLocal(item, lookup)
}

/** 3. 取得原始諮詢單清單 */
async function fetchRawFeedbacks(): Promise<ApiFeedbackItem[]> {
  const data = await apiFetch<ApiListResponse<ApiFeedbackItem> | ApiFeedbackItem[]>(
    `/merchant-api/vendors/${currentVendorId}/feedbacks`
  )
  return extractItems(data)
}

/**
 * 3. 取得諮詢單清單
 * GET /merchant-api/vendors/{service_vendor_id}/feedbacks
 *
 * ⚠️ 此函式刻意**不使用 Mock 保底**，一律回傳後端的真實結果：
 *   - 後端回 0 筆 → 回空陣列，頁面顯示「目前沒有諮詢單」
 *   - 請求失敗     → 回空陣列並以 Toast 提示，不以假資料誤導
 * 諮詢單是商家實際待辦事項，顯示範例資料會造成誤判。
 */
export async function fetchFeedbacks(): Promise<mock.FormFeedback[]> {
  try {
    const items = await fetchRawFeedbacks()

    // 先批次載入各筆所屬表單版本的題目標題與選項名稱（同一 form_id 只請求一次），
    // 才能把答案還原成「題目標題：答案內容」
    const lookups = await loadLookupsForForms(
      items
        .map((i) => i.form_id)
        .filter((v): v is number => typeof v === 'number')
    )

    return items.map((i) =>
      mapApiFeedbackToLocal(
        i,
        typeof i.form_id === 'number' ? lookups.get(i.form_id) : undefined
      )
    )
  } catch (err) {
    console.warn('[Feedbacks] Real API failed:', err)
    notifyError('無法載入諮詢單資料，請稍後再試')
    // 不退回 Mock：避免以假資料誤導，讓頁面顯示空清單
    return []
  }
}

/** 產生訂單編號：ORD + yyyyMMddHHmmss + 3 碼隨機 */
function generateOrderNo(): string {
  const d = new Date()
  const p = (n: number, len = 2) => String(n).padStart(len, '0')
  const ts = `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
  return `ORD${ts}${p(Math.floor(Math.random() * 1000), 3)}`
}

const EMPTY_FEEDBACK = (
  feedbackNo: string,
  status: mock.FeedbackStatus
): mock.FormFeedback => ({
  id: feedbackNo,
  contactName: '',
  serviceType: '',
  preferredContactTime: '',
  status,
  phone: '',
  email: '',
  address: '',
  specialRequirements: '',
  selectedOptions: [],
  content: '',
  createdAt: '',
})

/** 將諮詢單內容打包為訂單的 vendor_data（後端 snake_case） */
function buildOrderVendorData(
  feedback: mock.FormFeedback,
  raw?: ApiFeedbackItem
): Record<string, unknown> {
  return {
    feedback_no: feedback.id,
    form_id: raw?.form_id ?? null,
    // 已由 parseFeedbackContent 還原成「題目標題：答案」的多行文字
    content: feedback.content,
    selected_options: feedback.selectedOptions,
    contact: {
      name: feedback.contactName,
      phone: feedback.phone,
      email: feedback.email,
      address: feedback.address,
    },
    special_requirements: feedback.specialRequirements,
    preferred_contact_time: feedback.preferredContactTime,
  }
}

/**
 * 4 + 5. 確認接單（兩段式）
 *   PATCH /merchant-api/feedbacks/{feedback_no}/status  → status "1"、is_read "1"
 *   POST  /merchant-api/orders                         → 建立正式訂單
 *
 * quotedAmount 為商家輸入的估價金額，寫入 original_amount 與 final_amount。
 * 同時把原始諮詢內容打包進 vendor_data，讓商家出工前能查閱顧客的客製化需求。
 *
 * 建立訂單失敗時諮詢單狀態仍保持已接單（第一步已成功），
 * 回傳前端暫時訂單物件並以 Toast 提示，避免 UI 中斷。
 */
export async function acceptFeedback(
  feedbackNo: string,
  quotedAmount = 0
): Promise<{ success: boolean; feedback: mock.FormFeedback; newOrder: mock.OrderRecord }> {
  try {
    // ── 前置檢查 ──
    // 刻意在改動狀態「之前」先取回原始資料並驗證建單必要欄位。
    // POST /orders 的 inbr_account_id 為必填 UUID（實測：省略→missing、
    // 傳 null→uuid_type），缺少時無論如何都建不出訂單。若先 PATCH 再發現
    // 建不了單，會留下「諮詢單已接單但沒有訂單」的半成品狀態。
    const raw = (await fetchRawFeedbacks()).find((f) => f.feedback_no === feedbackNo)
    if (!raw) {
      notifyError(`找不到諮詢單 ${feedbackNo}，請重新載入後再試`)
      throw new Error(`Feedback ${feedbackNo} not found`)
    }
    if (!raw.inbr_account_id) {
      notifyError('此諮詢單缺少會員識別碼，無法建立訂單，請聯繫系統管理員')
      throw new Error(`Feedback ${feedbackNo} has no inbr_account_id`)
    }

    // ── Step 1：更新諮詢單狀態 ──
    await apiFetch(`/merchant-api/feedbacks/${feedbackNo}/status`, {
      method: 'PATCH',
      body: jsonBody({ status: FEEDBACK_STATUS_ACCEPTED, is_read: '1' }),
    })

    // raw 取於 PATCH 之前，狀態仍是舊值；此處已知 PATCH 成功，直接覆寫
    const resolvedFeedback: mock.FormFeedback = {
      ...(await mapFeedbackWithTitles(raw)),
      status: '已接單',
    }

    // ── Step 2：建立正式訂單 ──
    let newOrder: mock.OrderRecord
    try {
      const created = await apiFetch<ApiOrderItem>('/merchant-api/orders', {
        method: 'POST',
        body: jsonBody({
          order_no: generateOrderNo(),
          service_vendor_id: currentVendorId,
          service_id: raw.service_id ?? null,
          platform_code: '01',
          inbr_account_id: raw.inbr_account_id,
          member_name: raw?.contact_name ?? null,
          member_phone: raw?.contact_mobile ?? null,
          member_email: raw?.contact_email ?? null,
          order_type: '05', // 05=服務訂單
          order_status: '11', // 11=待訂金
          order_time: new Date().toISOString(),
          deposit_amount: 0,
          original_amount: quotedAmount,
          discount_amount: 0,
          shipping_fee_amount: 0,
          final_amount: quotedAmount,
          order_items: resolvedFeedback.selectedOptions.map((opt) => ({
            itemName: opt,
            quantity: 1,
            unitPrice: 0,
          })),
          // 帶入原始諮詢內容，供訂單詳細頁還原顧客填寫的需求
          vendor_data: buildOrderVendorData(resolvedFeedback, raw),
          remark: resolvedFeedback.specialRequirements || null,
          cre_id: getUpdId(),
        }),
      })
      newOrder = mapApiOrderToLocal(created)
    } catch (orderErr) {
      console.warn('[AcceptFeedback] Order creation failed:', orderErr)
      notifyError('諮詢單已接單，但訂單建立失敗，請至訂單管理頁確認')
      newOrder = {
        id: generateOrderNo(),
        customerName: resolvedFeedback.contactName,
        serviceName: resolvedFeedback.serviceType,
        originalAmount: quotedAmount,
        finalAmount: quotedAmount,
        serviceTime: '待確認',
        orderStatus: '11',
        createdAt: new Date().toLocaleString('zh-TW'),
        address: resolvedFeedback.address,
        phone: resolvedFeedback.phone,
        orderItems: [],
      }
    }

    return { success: true, feedback: resolvedFeedback, newOrder }
  } catch (err) {
    // ⚠️ 刻意不退回 Mock。原本失敗時回 mock.acceptFeedback() 會傳回
    // success: true 與假訂單，讓 UI 顯示接單成功、諮詢單變成「已接單」，
    // 但後端其實什麼都沒寫入 —— 這比直接報錯更危險。
    console.warn('[AcceptFeedback] 接單失敗:', err)
    throw err
  }
}

/**
 * 4. 婉拒諮詢
 * PATCH /merchant-api/feedbacks/{feedback_no}/status → status "2"
 *
 * ⚠️ 後端無「已拒絕」狀態與原因欄位，故以「已完成」結案，
 * 「已拒絕」標記與原因僅存在前端 state，重新載入後會消失。
 */
export async function declineFeedback(
  feedbackNo: string,
  reason: string
): Promise<{ success: boolean; feedback: mock.FormFeedback }> {
  try {
    await apiFetch(`/merchant-api/feedbacks/${feedbackNo}/status`, {
      method: 'PATCH',
      body: jsonBody({ status: FEEDBACK_STATUS_CLOSED, is_read: '1' }),
    })

    const raw = (await fetchRawFeedbacks()).find((f) => f.feedback_no === feedbackNo)
    const base = raw
      ? await mapFeedbackWithTitles(raw)
      : EMPTY_FEEDBACK(feedbackNo, '已拒絕')

    return {
      success: true,
      feedback: { ...base, status: '已拒絕', declineReason: reason },
    }
  } catch (err) {
    // 同 acceptFeedback：不退回 Mock，避免顯示成功但實際未寫入後端
    console.warn('[DeclineFeedback] 婉拒失敗:', err)
    notifyError('婉拒操作失敗，狀態未寫入後端')
    throw err
  }
}

// ════════════════════════════════════════════════════════════
// 5 ~ 7. 訂單 (Orders)
// ════════════════════════════════════════════════════════════

/** 後端 order 原始結構（mms_order_record + 附加的 review 欄位） */
interface ApiOrderItem {
  record_id: number
  order_no: string
  service_vendor_id?: number
  service_id?: number | null
  inbr_account_id?: string
  member_name?: string | null
  member_phone?: string | null
  member_email?: string | null
  order_type?: string | null
  order_status: string
  order_time?: string | null
  service_time?: string | null
  complete_time?: string | null
  deposit_amount?: number | null
  original_amount?: number | null
  discount_amount?: number | null
  final_amount?: number | null
  order_items?: ApiOrderItemDetail[] | null
  remark?: string | null
  /** 接單時帶入的原始諮詢內容，結構由前端定義（見 buildOrderVendorData） */
  vendor_data?: Record<string, unknown> | null
  review?: unknown | null
  cre_time?: string | null
  [key: string]: unknown
}

/** 將後端 vendor_data 還原為前端型別。非預期結構則回 undefined */
function parseOrderVendorData(raw: unknown): mock.OrderVendorData | undefined {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return undefined
  const v = raw as Record<string, unknown>

  const str = (k: string) => (typeof v[k] === 'string' ? (v[k] as string) : undefined)
  const contactRaw =
    v.contact && typeof v.contact === 'object' && !Array.isArray(v.contact)
      ? (v.contact as Record<string, unknown>)
      : undefined
  const contactStr = (k: string) =>
    contactRaw && typeof contactRaw[k] === 'string'
      ? (contactRaw[k] as string)
      : undefined

  const data: mock.OrderVendorData = {
    feedbackNo: str('feedback_no'),
    formId: typeof v.form_id === 'number' ? v.form_id : undefined,
    content: str('content'),
    selectedOptions: Array.isArray(v.selected_options)
      ? v.selected_options.filter((x): x is string => typeof x === 'string')
      : undefined,
    contact: contactRaw
      ? {
          name: contactStr('name'),
          phone: contactStr('phone'),
          email: contactStr('email'),
          address: contactStr('address'),
        }
      : undefined,
    specialRequirements: str('special_requirements'),
    preferredContactTime: str('preferred_contact_time'),
  }

  // 完全沒有可用內容時視為無資料，讓 UI 不顯示空區塊
  const hasContent =
    !!data.content ||
    (data.selectedOptions?.length ?? 0) > 0 ||
    !!data.specialRequirements ||
    !!data.contact
  return hasContent ? data : undefined
}

interface ApiOrderItemDetail {
  /** 實測後端用 camelCase，但同時容忍 snake_case 以防端點差異 */
  itemName?: string | null
  item_name?: string | null
  quantity?: number | null
  unitPrice?: number | null
  unit?: string
  attribute?: unknown
  itemAmount?: number | null
  [key: string]: unknown
}

/**
 * 取出項目名稱並過濾異常值
 *
 * ⚠️ 資料庫中存在少數 itemName 為字面字串 "[object Object]" 的訂單 ——
 * 那是早期 feedback_content 解析錯誤時，接單流程把錯誤結果寫進
 * order_items 造成的。解析已修正，但既有資料無法回溯修改，
 * 因此在顯示層改為明確標示異常，而非讓使用者看到 "[object Object]"。
 */
function sanitizeItemName(raw: unknown): string {
  const text = typeof raw === 'string' ? raw.trim() : ''
  if (!text) return '未命名項目'
  if (text === '[object Object]' || text === 'undefined' || text === 'null') {
    return '(項目資料異常)'
  }
  return text
}

const VALID_ORDER_STATUS: mock.OrderStatusCode[] = ['11', '12', '04', '80', '90']

function mapApiOrderToLocal(item: ApiOrderItem): mock.OrderRecord {
  const orderStatus = (
    VALID_ORDER_STATUS.includes(item.order_status as mock.OrderStatusCode)
      ? item.order_status
      : '11'
  ) as mock.OrderStatusCode

  // order_items 理應為陣列；若後端回物件或 null 則視為空清單，避免 .map 拋錯
  const rawItems = Array.isArray(item.order_items) ? item.order_items : []
  const orderItems: mock.OrderItem[] = rawItems.map((oi) => ({
    name: sanitizeItemName(oi.itemName ?? oi.item_name),
    quantity: oi.quantity || 1,
  }))

  return {
    id: item.order_no,
    customerName: item.member_name || '(加密隱藏)',
    serviceName:
      orderItems.length > 0 ? orderItems.map((i) => i.name).join('、') : '服務項目',
    originalAmount: item.original_amount || 0,
    finalAmount: item.final_amount || 0,
    serviceTime: item.service_time
      ? new Date(item.service_time).toLocaleString('zh-TW')
      : item.order_time
        ? new Date(item.order_time).toLocaleString('zh-TW')
        : '待確認',
    orderStatus,
    createdAt: item.cre_time ? new Date(item.cre_time).toLocaleString('zh-TW') : '',
    address: '', // 後端目前未提供
    phone: item.member_phone || '',
    orderItems,
    serviceId: item.service_id ?? undefined,
    vendorData: parseOrderVendorData(item.vendor_data),
    _recordId: item.record_id, // 保留供 PATCH 更新用
  } as mock.OrderRecord & { _recordId: number }
}

/** 6. 取回原始訂單清單（此端點回純陣列） */
async function fetchRawOrders(): Promise<ApiOrderItem[]> {
  const data = await apiFetch<ApiListResponse<ApiOrderItem> | ApiOrderItem[]>(
    `/merchant-api/vendors/${currentVendorId}/orders`
  )
  return extractItems(data)
}

/**
 * 6. 取得訂單清單
 * GET /merchant-api/vendors/{service_vendor_id}/orders
 *
 * 無資料或載入失敗都回空陣列，讓頁面顯示空清單，不以 Mock 範例資料充數。
 */
export async function fetchOrders(): Promise<mock.OrderRecord[]> {
  try {
    return (await fetchRawOrders()).map(mapApiOrderToLocal)
  } catch (err) {
    console.warn('[Orders] Real API failed:', err)
    notifyError('無法載入訂單資料，請稍後再試')
    return []
  }
}

/**
 * 7. 更新訂單狀態
 * PATCH /merchant-api/vendors/{service_vendor_id}/orders/{record_id}
 *
 * 需要 record_id；若呼叫端未提供，先從訂單清單以 order_no 反查。
 */
export async function updateOrderStatus(
  orderId: string,
  newStatus: mock.OrderStatusCode,
  recordId?: number
): Promise<{ success: boolean; order: mock.OrderRecord }> {
  try {
    let resolvedRecordId = recordId
    if (!resolvedRecordId) {
      const target = (await fetchRawOrders()).find((o) => o.order_no === orderId)
      resolvedRecordId = target?.record_id
    }
    if (!resolvedRecordId) {
      throw new Error(`找不到訂單 ${orderId} 對應的 record_id`)
    }

    await apiFetch(
      `/merchant-api/vendors/${currentVendorId}/orders/${resolvedRecordId}`,
      { method: 'PATCH', body: jsonBody({ order_status: newStatus }) }
    )

    // 回讀確認後端實際狀態
    const updated = (await fetchRawOrders()).find((o) => o.order_no === orderId)
    if (updated) {
      return { success: true, order: mapApiOrderToLocal(updated) }
    }
    throw new Error('Order not found after update')
  } catch (err) {
    // ⚠️ 不退回 Mock：狀態其實沒改成功時，畫面不該顯示已更新
    console.warn('[UpdateOrderStatus] Real API failed:', err)
    notifyError('訂單狀態更新失敗，請稍後再試')
    throw err
  }
}

// ════════════════════════════════════════════════════════════
// 8 & 9. 服務標籤 (Service Labels)
// ════════════════════════════════════════════════════════════
//
// GET /merchant-api/services/{service_id}/labels 同時扮演「字典」與
// 「已選狀態」兩個角色 —— 回傳系統全部標籤，並以 checked 標示是否已綁定：
//   [{ "id": 1, "name": "寵物友善", "checked": false }, ...]
// 因此不需要獨立的標籤字典端點。

interface ApiServiceLabel {
  id: number
  name: string
  checked: boolean
  category?: string | null
  /**
   * 標籤適用的服務類型。null / 未提供 = 通用標籤（所有服務都可用）。
   * ⚠️ 後端目前**沒有回傳此欄位**，因此無法過濾（例如「中餐廳」「泰式料理」
   * 這類 service_type=6 的餐廳標籤，也會出現在清潔類服務上）。
   * 一旦後端補上此欄位，下方 filterLabelsByServiceType 就會自動開始生效。
   */
  service_type?: string | null
}

/**
 * 依服務類型過濾標籤：保留通用標籤（service_type 為 null）與同類型標籤。
 *
 * 若後端未提供 service_type 欄位（目前情況），則全數保留，行為與過濾前相同。
 */
function filterLabelsByServiceType(
  items: ApiServiceLabel[],
  serviceType?: string
): ApiServiceLabel[] {
  // 後端沒帶 service_type 時不做過濾，避免把所有標籤都濾掉
  const hasTypeInfo = items.some((i) => i.service_type !== undefined)
  if (!hasTypeInfo || !serviceType) return items

  return items.filter(
    (i) =>
      i.service_type == null || // 通用標籤
      String(i.service_type) === String(serviceType)
  )
}

/** 將後端標籤陣列拆為「字典」與「已選 ID」兩份前端資料 */
function splitLabels(items: ApiServiceLabel[]): {
  allLabels: mock.ServiceLabel[]
  selectedIds: number[]
} {
  return {
    allLabels: items.map((item) => ({
      id: item.id,
      name: item.name,
      category: item.category ?? '服務標籤',
    })),
    selectedIds: items.filter((item) => item.checked).map((item) => item.id),
  }
}

/**
 * 8. 取得特定服務的標籤與勾選狀態
 * GET /merchant-api/services/{service_id}/labels
 */
export async function getServiceLabels(
  serviceId: number,
  /** 該服務的 type（cms_homepage_service.type），用於過濾不適用的標籤 */
  serviceType?: string
): Promise<{
  allLabels: mock.ServiceLabel[]
  selectedIds: number[]
}> {
  try {
    const data = await apiFetch<ApiListResponse<ApiServiceLabel> | ApiServiceLabel[]>(
      `/merchant-api/services/${serviceId}/labels`
    )
    const items = extractItems(data)
    return splitLabels(filterLabelsByServiceType(items, serviceType))
  } catch (err) {
    console.warn('[ServiceLabels] Real API failed:', err)
    notifyError('無法載入服務標籤，請稍後再試')
    return { allLabels: [], selectedIds: [] }
  }
}

/**
 * 9. 批次設定特定服務的標籤
 * PUT /merchant-api/services/{service_id}/labels
 * Body：{ label_ids: number[], upd_id }
 *
 * 後端以整批覆寫方式重建關聯，並回傳與 GET 相同格式的更新後清單。
 */
export async function updateServiceLabels(
  serviceId: number,
  labelIds: number[]
): Promise<{ success: boolean; allLabels: mock.ServiceLabel[]; selectedIds: number[] }> {
  try {
    const data = await apiFetch<ApiListResponse<ApiServiceLabel> | ApiServiceLabel[]>(
      `/merchant-api/services/${serviceId}/labels`,
      { method: 'PUT', body: jsonBody({ label_ids: labelIds }) }
    )
    const items = extractItems(data)
    // 後端理應回傳更新後清單；若回空則以送出值為準
    if (items.length === 0) {
      return { success: true, allLabels: [], selectedIds: labelIds }
    }
    return { success: true, ...splitLabels(items) }
  } catch (err) {
    // ⚠️ 不退回 Mock：過去這裡會回 success 讓畫面顯示「已更新」，
    // 但後端沒寫入，下次登入標籤又變回原樣（使用者實際踩過的坑）
    console.warn('[UpdateServiceLabels] Real API failed:', err)
    throw err
  }
}

// ════════════════════════════════════════════════════════════
// 11 ~ 13. 表單 (Vendor Forms)
// ════════════════════════════════════════════════════════════
//
// 註：GET /merchant-api/vendors/{id}/forms（清單）目前有 bug —— 新建立的
// 表單查不到、一律回空陣列。本模組改為依 service.form_id 直接取回各表單，
// 不依賴該清單端點。待後端修好後若需要「未綁定任何服務的表單」清單，
// 再補上對該端點的呼叫即可。

/** 11. GET /merchant-api/forms/{form_id}/full 中的表單主檔 */
interface ApiFormMaster {
  id: number
  service_vendor_id?: number
  service_id?: number | null
  type?: string | null
  sub_type?: string | null
  name: string | null
  intro_content?: string | null
  notice_content?: string | null
  terms_content?: string | null
  review_status?: string | null
  is_enable?: string | null
  cre_time?: string | null
  upd_time?: string | null
  [key: string]: unknown
}

interface ApiFormGroup {
  id: number
  form_id?: number
  name: string | null
  sort?: number | null
  topics?: ApiFormTopic[] // POST/PATCH 巢狀回應時使用
  [key: string]: unknown
}

/**
 * 題目結構。欄位名以 Swagger 為準：
 *   title（非 name）、type 為數字代碼字串、is_required 為 "1"/"0" 字串
 */
interface ApiFormTopic {
  id: number
  form_id?: number
  form_group_id?: number | null
  type: string | null
  title: string | null
  remark?: string | null
  is_required: string | null
  sort?: number | null
  options?: ApiTopicOption[]
  media?: unknown[]
  county_district_relations?: unknown[]
  [key: string]: unknown
}

/** 選項：option_name（非 name） */
interface ApiTopicOption {
  id: number
  option_name: string | null
  unit_price?: number | null
  sort?: number | null
  [key: string]: unknown
}

/** GET /forms/{id}/full 回應：{ form, groups, topics }，topics 為攤平陣列 */
interface ApiFormFull {
  form: ApiFormMaster
  groups?: ApiFormGroup[]
  topics?: ApiFormTopic[]
  [key: string]: unknown
}

/** POST/PATCH forms 回應：巢狀 { id, ..., groups: [{ topics: [{ options }] }] } */
interface ApiFormNested extends ApiFormMaster {
  groups?: ApiFormGroup[]
}

// ─── 題目型別代碼 ↔ 前端 FieldInputType 雙向映射 ───

const TOPIC_TYPE_TO_FIELD: Record<string, mock.FieldInputType> = {
  '1': 'short_text', // 簡答
  '2': 'long_text', // 詳答
  '3': 'single_choice', // 單選
  '4': 'multi_choice', // 複選
  '5': 'region', // 地區選單
  '6': 'photo', // 照片
  '7': 'remark', // 備註
  '8': 'contact', // 聯絡資料
  '9': 'date', // 日期
  '10': 'contact_no_address', // 聯絡資料(不含地址)
}

const FIELD_TO_TOPIC_TYPE: Record<mock.FieldInputType, string> = {
  short_text: '1',
  long_text: '2',
  single_choice: '3',
  multi_choice: '4',
  region: '5',
  photo: '6',
  remark: '7',
  contact: '8',
  date: '9',
  contact_no_address: '10',
}

function mapTopicType(raw: string | null | undefined): mock.FieldInputType {
  return TOPIC_TYPE_TO_FIELD[String(raw ?? '')] ?? 'short_text'
}

/** 後端 is_required 為 "1"/"0" 字串（也容忍 boolean） */
function parseRequired(raw: unknown): boolean {
  if (typeof raw === 'boolean') return raw
  return String(raw ?? '0') === '1'
}

function mapTopicToField(t: ApiFormTopic, groupId?: number): mock.FormField {
  const inputType = mapTopicType(t.type)
  return {
    id: String(t.id),
    label: t.title ?? '',
    inputType,
    required: parseRequired(t.is_required),
    placeholder: t.remark ?? undefined,
    options: mock.TYPES_WITH_OPTIONS.includes(inputType)
      ? [...(t.options ?? [])].sort(bySort).map((o) => o.option_name ?? '')
      : undefined,
    // 保留後端 id，儲存時才能做「更新」而非「刪除後重建」
    topicId: t.id,
    groupId: t.form_group_id ?? groupId,
  }
}

/**
 * 11. 將 GET /forms/{id}/full 回應轉為前端 ServiceForm
 *
 * topics 為攤平陣列，需依所屬 group 的 sort 再依 topic 自身 sort 排序，
 * 以還原使用者在編輯器中看到的順序。
 */
function mapApiFormFull(data: ApiFormFull): mock.ServiceForm {
  const master = data.form ?? ({} as ApiFormMaster)
  const groups = [...(data.groups ?? [])].sort(bySort)
  const groupOrder = new Map<number, number>()
  groups.forEach((g, idx) => groupOrder.set(g.id, idx))

  const topics = [...(data.topics ?? [])].sort((a, b) => {
    const ga = groupOrder.get(a.form_group_id ?? -1) ?? 0
    const gb = groupOrder.get(b.form_group_id ?? -1) ?? 0
    return ga !== gb ? ga - gb : bySort(a, b)
  })

  return {
    id: master.id,
    title: master.name ?? '',
    description: master.intro_content ?? '',
    fields: topics.map((t) => mapTopicToField(t)),
    createdAt: master.cre_time ?? '',
    updatedAt: master.upd_time ?? '',
    groups: groups.map((g, idx) => ({
      id: g.id,
      name: g.name ?? `題組 ${idx + 1}`,
      sort: g.sort ?? idx,
    })),
    type: master.type ?? undefined,
    subType: master.sub_type ?? undefined,
  }
}

/**
 * 依實際回應形狀選用對應的 mapper
 *
 * 實測兩支寫入端點的回應格式**不同**：
 *   POST  /merchant-api/forms        → { id, name, ..., groups: [{ topics: [{ options }] }] }
 *   PATCH /merchant-api/forms/{id}   → { form, groups, topics }（同 GET /full，topics 攤平在頂層）
 *
 * 因此以是否存在頂層 `form` 欄位判斷，避免用錯 mapper 導致 id/title 變空。
 * 無法辨識時回 null，由呼叫端改打 /full 回讀。
 */
function mapFormResponse(data: unknown): mock.ServiceForm | null {
  if (!data || typeof data !== 'object') return null
  const obj = data as Record<string, unknown>
  if (obj.form && typeof obj.form === 'object') {
    return mapApiFormFull(obj as unknown as ApiFormFull)
  }
  if (typeof obj.id === 'number' && Array.isArray(obj.groups)) {
    return mapApiFormNested(obj as unknown as ApiFormNested)
  }
  return null
}

/** 12/13. 將巢狀回應（groups[].topics[]）轉為前端 ServiceForm */
function mapApiFormNested(data: ApiFormNested): mock.ServiceForm {
  const sortedGroups = [...(data.groups ?? [])].sort(bySort)
  const fields: mock.FormField[] = []
  for (const g of sortedGroups) {
    for (const t of [...(g.topics ?? [])].sort(bySort)) {
      fields.push(mapTopicToField(t, g.id))
    }
  }
  return {
    id: data.id,
    title: data.name ?? '',
    description: data.intro_content ?? '',
    fields,
    createdAt: data.cre_time ?? '',
    updatedAt: data.upd_time ?? '',
    groups: sortedGroups.map((g, idx) => ({
      id: g.id,
      name: g.name ?? `題組 ${idx + 1}`,
      sort: g.sort ?? idx,
    })),
    type: data.type ?? undefined,
    subType: data.sub_type ?? undefined,
  }
}

/** 將單一前端欄位轉為後端 topic payload。帶 id 代表更新、不帶代表新增 */
function buildTopicPayload(
  f: Omit<mock.FormField, 'id'>,
  sort: number
): Record<string, unknown> {
  const topic: Record<string, unknown> = {
    type: FIELD_TO_TOPIC_TYPE[f.inputType],
    title: f.label,
    remark: f.placeholder ?? null,
    is_required: f.required ? '1' : '0',
    sort,
  }
  // 既有題目帶回 id，後端才會做 PATCH 更新而非刪除後重建
  if (f.topicId != null) topic.id = f.topicId

  // 僅單選/複選需要 options
  if (mock.TYPES_WITH_OPTIONS.includes(f.inputType)) {
    // 註：選項不帶 id —— 前端編輯器目前僅保存選項文字，
    // 因此每次儲存等同「刪除舊選項 + 新增現有選項」。
    // 若日後需要保留選項 id，需讓編輯器一併追蹤 option.id。
    topic.options = (f.options ?? [])
      .filter((opt) => opt.trim() !== '')
      .map((opt, optIdx) => ({
        option_name: opt,
        unit_price: 0,
        sort: optIdx,
      }))
  }
  return topic
}

/**
 * 將前端欄位陣列組裝為後端要求的四層巢狀 groups payload
 *
 * 後端 PATCH 是**差異比對式**：payload 中未出現的 group/topic/option 會被刪除，
 * 帶 id 者更新、不帶 id 者新增。因此這裡必須：
 *   1. 還原原本的題組結構（originalGroups），否則多題組表單會被壓縮成單一題組
 *   2. 帶回既有題目的 id，否則每次儲存都會刪光重建
 *
 * 新增的欄位（無 groupId）會歸入第一個題組；若表單原本沒有任何題組
 * （例如全新建立），則產生一個以表單標題命名的預設題組。
 */
function buildGroupsPayload(
  fields: Omit<mock.FormField, 'id'>[],
  fallbackGroupName: string,
  originalGroups?: mock.FormGroupMeta[]
) {
  const groups = [...(originalGroups ?? [])].sort((a, b) => a.sort - b.sort)

  // 沒有原始題組結構 → 全部欄位放進單一預設題組
  if (groups.length === 0) {
    return [
      {
        name: fallbackGroupName,
        sort: 0,
        topics: fields.map((f, idx) => buildTopicPayload(f, idx)),
      },
    ]
  }

  const firstGroupId = groups[0].id
  const byGroup = new Map<number, Omit<mock.FormField, 'id'>[]>()
  for (const g of groups) byGroup.set(g.id, [])

  for (const f of fields) {
    // 新欄位或原題組已不存在 → 歸入第一個題組
    const gid = f.groupId != null && byGroup.has(f.groupId) ? f.groupId : firstGroupId
    byGroup.get(gid)!.push(f)
  }

  return groups.map((g, gIdx) => ({
    id: g.id,
    name: g.name,
    sort: g.sort ?? gIdx,
    topics: (byGroup.get(g.id) ?? []).map((f, idx) => buildTopicPayload(f, idx)),
  }))
}

// ─── 服務清單（待後端提供端點）───

/**
 * 15. GET /merchant-api/vendors/{service_vendor_id}/services 回應
 * form_id 是該服務項目對應的諮詢表單 ID（服務指向表單）
 */
interface ApiVendorServiceItem {
  id: number
  service_vendor_id: number
  type?: string | null
  name?: string | null
  img_url?: string | null
  description?: string | null
  form_id?: number | null
  [key: string]: unknown
}

/** 服務類型代碼對應（後端 cms_homepage_service.type）*/
export const SERVICE_TYPE_LABELS: Record<string, string> = {
  '1': '居家清潔',
  '2': '家電清洗',
  '3': '包裹寄送',
  '6': '餐廳訂位',
  '9': '美食外送',
  '10': '水電修繕',
  '11': '商城購物',
}

/** 正規化後的服務項目 */
interface NormalizedService {
  id: number
  name: string
  type: string
  /** 服務主檔指向的表單 id，null 代表尚未綁定表單 */
  formId: number | null
}

function normalizeService(item: ApiVendorServiceItem): NormalizedService {
  return {
    id: item.id,
    name: item.name ?? `服務 #${item.id}`,
    type: item.type ?? '',
    formId: item.form_id ?? null,
  }
}

/**
 * 16. 新增服務項目
 * POST /merchant-api/services
 *
 * `id` 不傳時由 BFF 自動分配（查全平台最大 id + 1）。
 * ⚠️ 後端註明該分配非資料庫序列，高併發時極小機率撞號並回 409。
 */
export async function createVendorService(data: {
  name: string
  /** 服務類型代碼，必填。見 SERVICE_TYPE_LABELS */
  type: string
  description?: string
  imgUrl?: string
  /** 對應的諮詢表單 ID，未設定時傳 null */
  formId?: number | null
}): Promise<{ success: boolean; service: mock.VendorService }> {
  try {
    const created = await apiFetch<ApiVendorServiceItem>('/merchant-api/services', {
      method: 'POST',
      body: jsonBody({
        service_vendor_id: currentVendorId,
        type: data.type,
        name: data.name,
        img_url: data.imgUrl ?? null,
        description: data.description ?? null,
        form_id: data.formId ?? null,
      }),
    })

    const normalized = normalizeService(created)
    return {
      success: true,
      service: {
        id: normalized.id,
        name: normalized.name,
        vendorId: created.service_vendor_id ?? currentVendorId,
        type: normalized.type,
        form: null,
        sharedFormCount: 0,
      },
    }
  } catch (err) {
    console.warn('[CreateVendorService] Real API failed:', err)
    if (err instanceof ApiError && err.status === 409) {
      notifyError('服務項目編號衝突，請再試一次')
    } else {
      notifyError('新增服務項目失敗，資料未寫入後端')
    }
    throw err
  }
}

/**
 * 17. 刪除服務項目
 * DELETE /merchant-api/services/{service_id}
 *
 * 實體刪除（此表無 is_deleted 欄位），回 204 無內容。
 * 註：後端不會清除該 service 的 service_label 關聯，但查不到 service
 * 後就不會再被列出，不影響前端。
 */
export async function deleteVendorService(serviceId: number): Promise<{ success: boolean }> {
  try {
    await apiFetch(`/merchant-api/services/${serviceId}`, { method: 'DELETE' })
    return { success: true }
  } catch (err) {
    console.warn('[DeleteVendorService] Real API failed:', err)
    notifyError('刪除服務項目失敗，請稍後再試')
    throw err
  }
}

/**
 * 15. 取得該廠商的服務項目清單
 * GET /merchant-api/vendors/{service_vendor_id}/services
 */
async function fetchVendorServiceList(vid: number): Promise<NormalizedService[]> {
  const data = await apiFetch<
    ApiListResponse<ApiVendorServiceItem> | ApiVendorServiceItem[]
  >(`/merchant-api/vendors/${vid}/services`)
  return extractItems(data).map(normalizeService)
}

/**
 * 11. 取得單一表單完整結構
 * GET /merchant-api/forms/{form_id}/full
 */
async function resolveFormDetail(formId: number): Promise<mock.ServiceForm | null> {
  try {
    const full = await apiFetch<ApiFormFull>(`/merchant-api/forms/${formId}/full`)
    return mapApiFormFull(full)
  } catch (err) {
    console.warn(`[VendorServices] form ${formId} full fetch failed:`, err)
    return null
  }
}

/**
 * 15 + 11. 以「服務」為主體組合出服務清單與各自綁定的表單
 *
 * 一個服務最多綁定一張表單（service.form_id），但**一張表單可被多個服務共用**
 * —— 實測 vendor 1 的 4 個服務都指向 form_id 9。因此：
 *   - 相同 form_id 只請求一次 /full，結果快取重用
 *   - sharedFormCount 記錄共用該表單的服務數，供 UI 提示「編輯會影響其他服務」
 *
 * 刻意**不使用** GET /vendors/{id}/forms 清單端點 —— 該端點目前有 bug
 * （建立的表單查不到，回空陣列）。改為直接依 service.form_id 逐張取回，
 * 既繞過該 bug，也避免多餘請求。
 */
export async function fetchVendorServices(
  vendorId?: number
): Promise<mock.VendorService[]> {
  const vid = vendorId ?? currentVendorId
  try {
    const services = await fetchVendorServiceList(vid)
    if (services.length === 0) return []

    // 統計每張表單被幾個服務共用
    const shareCount = new Map<number, number>()
    for (const s of services) {
      if (s.formId != null) {
        shareCount.set(s.formId, (shareCount.get(s.formId) ?? 0) + 1)
      }
    }

    // 相同 form_id 只取一次完整結構
    const uniqueFormIds = [...shareCount.keys()]
    const detailCache = new Map<number, mock.ServiceForm | null>()
    await Promise.all(
      uniqueFormIds.map(async (formId) => {
        detailCache.set(formId, await resolveFormDetail(formId))
      })
    )

    return services.map((s) => ({
      id: s.id,
      name: s.name,
      vendorId: vid,
      type: s.type,
      form: s.formId != null ? (detailCache.get(s.formId) ?? null) : null,
      sharedFormCount: s.formId != null ? (shareCount.get(s.formId) ?? 1) : 0,
    }))
  } catch (err) {
    console.warn('[VendorServices] Real API failed:', err)
    notifyError('無法載入服務資料，請稍後再試')
    return []
  }
}

/**
 * 12. 一鍵建立完整表單
 * POST /merchant-api/forms
 * Body：{ form: {...}, groups: [{ name, sort, topics: [{ ..., options: [...] }] }], upd_id }
 *
 * serviceId 傳 null 代表「建立獨立新表單」（後端表單主檔本身不綁 service_id），
 * 此時回傳項目的 id 直接採用後端配發的 form_id。
 *
 * ⚠️ 失敗時不退回 Mock —— 會 throw 讓呼叫端知道「真的沒寫進後端」，
 * 避免顯示成功卻什麼都沒存。
 */
export async function createServiceForm(
  serviceId: number | null,
  data: {
    title: string
    description: string
    fields: Omit<mock.FormField, 'id'>[]
    groups?: mock.FormGroupMeta[]
  }
): Promise<{ success: boolean; service: mock.VendorService }> {
  try {
    const created = await apiFetch<ApiFormNested>('/merchant-api/forms', {
      method: 'POST',
      body: jsonBody({
        // 若已知所屬服務一併送出，讓後端可回寫 service.form_id 完成綁定
        ...(serviceId != null ? { service_id: serviceId } : {}),
        form: {
          service_vendor_id: currentVendorId,
          type: '1', // C 端（無需評估）
          sub_type: '1', // 一般表單
          name: data.title,
          intro_content: data.description,
          is_enable: '1',
        },
        // 新建表單無既有題組，一律產生單一預設題組
        groups: buildGroupsPayload(data.fields, data.title || '表單內容'),
      }),
    })

    const form =
      mapFormResponse(created) ??
      mapApiFormFull(
        await apiFetch<ApiFormFull>(`/merchant-api/forms/${created.id}/full`)
      )

    return {
      success: true,
      service: {
        id: serviceId ?? form.id, // 獨立新表單時以 form_id 作為項目 id
        name: form.title || data.title,
        vendorId: currentVendorId,
        form,
      },
    }
  } catch (err) {
    console.warn('[CreateServiceForm] Real API failed:', err)
    notifyError('建立表單失敗，資料未寫入後端')
    throw err
  }
}

/**
 * 13. 更新表單基本資訊與結構
 * PATCH /merchant-api/forms/{form_id}
 *
 * ⚠️ **表單是版本化的（copy-on-write）**：後端不會原地改寫，而是產生一張
 * 新的表單版本（新 form_id），再把該 service 的 form_id 指向新版本。
 * 舊版本保留在資料庫中，讓既有 feedback 仍能依自己的 form_id 找到當初
 * 的題目結構來解析答案。因此呼叫端**必須在成功後重新拉取服務清單**，
 * 否則畫面上的 form_id 會是舊的。
 *
 * ⚠️ 失敗時不退回 Mock —— 會 throw 讓呼叫端知道更新沒有生效。
 */
export async function updateServiceForm(
  serviceId: number,
  formId: number,
  data: {
    title: string
    description: string
    fields: Omit<mock.FormField, 'id'>[]
    /** 原始題組結構，用於還原題組（避免多題組被壓縮成一個） */
    groups?: mock.FormGroupMeta[]
    /** 原表單的 type / sub_type。後端要求必填，需原樣回送 */
    formType?: string
    formSubType?: string
  }
): Promise<{ success: boolean; service: mock.VendorService }> {
  try {
    const updated = await apiFetch<ApiFormNested>(`/merchant-api/forms/${formId}`, {
      method: 'PATCH',
      body: jsonBody({
        // service_id 為必填：後端會把該 service 的 form_id 指向產出的表單版本
        service_id: serviceId,
        form: {
          // service_vendor_id / type / sub_type 為後端必填欄位，
          // 缺任一個會回 422（文件寫「form 可省略」與實作不符）。
          service_vendor_id: currentVendorId,
          type: data.formType ?? '1',
          sub_type: data.formSubType ?? '1',
          name: data.title,
          intro_content: data.description,
        },
        groups: buildGroupsPayload(data.fields, data.title || '表單內容', data.groups),
      }),
    })

    const form =
      mapFormResponse(updated) ??
      mapApiFormFull(await apiFetch<ApiFormFull>(`/merchant-api/forms/${formId}/full`))

    return {
      success: true,
      service: {
        id: serviceId,
        name: form.title || data.title,
        vendorId: currentVendorId,
        form,
      },
    }
  } catch (err) {
    console.warn('[UpdateServiceForm] Real API failed:', err)
    notifyError('更新表單失敗，變更未寫入後端')
    throw err
  }
}

// ════════════════════════════════════════════════════════════
// 14. 評價與分析 (Reviews)
// ════════════════════════════════════════════════════════════

/** GET /merchant-api/vendors/{id}/reviews 回應（mms_order_review / ReviewOut） */
interface ApiOrderReview {
  record_id: number
  order_no: string
  service_vendor_id: number
  service_id: number | null
  inbr_account_id?: string
  overall_rating: number | null
  rating_detail?: Record<string, number> | null
  review_content: string | null
  media?: string[] | null
  status?: string | null
  is_deleted?: boolean
  cre_time?: string | null
  upd_time?: string | null
  [key: string]: unknown
}

/** 評分轉情緒分類：4-5 正面、3 中立、1-2 負面 */
function ratingToSentiment(rating: number | null): 'positive' | 'neutral' | 'negative' {
  if (rating == null) return 'neutral'
  if (rating >= 4) return 'positive'
  if (rating <= 2) return 'negative'
  return 'neutral'
}

function formatDate(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  return Number.isNaN(d.getTime())
    ? ''
    : `${d.getFullYear()}/${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')}`
}

/** rating_detail 各維度的中文名稱 */
const RATING_DIMENSION_LABELS: Record<string, string> = {
  service: '服務品質',
  attitude: '服務態度',
  cleanliness: '整潔程度',
  punctuality: '準時程度',
  professionalism: '專業程度',
}

/**
 * 將原始評價陣列轉換為 Dashboard 所需的 AiAnalysis 結構
 *
 * ⚠️ 此端點回傳的是 mms_order_review 原始評價，並非 AI 摘要，
 * 因此摘要與建議在前端由統計數據推導（情緒分佈、平均評分、
 * rating_detail 各維度平均），不做語意分析。
 */
function deriveAnalysisFromReviews(reviews: ApiOrderReview[]): mock.AiAnalysis {
  const valid = reviews.filter((r) => !r.is_deleted)
  const total = valid.length

  const counts = { positive: 0, neutral: 0, negative: 0 }
  for (const r of valid) counts[ratingToSentiment(r.overall_rating)] += 1
  const pct = (n: number) => (total === 0 ? 0 : Math.round((n / total) * 100))

  const ratings = valid
    .map((r) => r.overall_rating)
    .filter((n): n is number => typeof n === 'number')
  const avgRating =
    ratings.length > 0
      ? (ratings.reduce((s, n) => s + n, 0) / ratings.length).toFixed(1)
      : '—'

  // rating_detail 各維度平均
  const dimSums = new Map<string, { sum: number; n: number }>()
  for (const r of valid) {
    for (const [k, v] of Object.entries(r.rating_detail ?? {})) {
      if (typeof v !== 'number') continue
      const cur = dimSums.get(k) ?? { sum: 0, n: 0 }
      dimSums.set(k, { sum: cur.sum + v, n: cur.n + 1 })
    }
  }
  const dimAverages = [...dimSums.entries()]
    .map(([k, v]) => ({
      label: RATING_DIMENSION_LABELS[k] ?? k,
      avg: v.sum / v.n,
    }))
    .sort((a, b) => a.avg - b.avg) // 低分在前，方便看出弱項

  const times = valid
    .map((r) => r.cre_time)
    .filter((t): t is string => !!t)
    .sort()
  const analyzedPeriod =
    times.length > 0
      ? `${formatDate(times[0])} – ${formatDate(times[times.length - 1])}`
      : '尚無評價資料'

  const summaryList = [
    `本期共收到 ${total} 筆客戶評價，平均評分 ${avgRating} 分。`,
    `情緒分佈：正面 ${counts.positive} 筆、中立 ${counts.neutral} 筆、負面 ${counts.negative} 筆。`,
  ]
  if (dimAverages.length > 0) {
    summaryList.push(
      `各面向平均：${dimAverages.map((d) => `${d.label} ${d.avg.toFixed(1)}`).join('、')}。`
    )
  }
  const withComment = valid.filter((r) => (r.review_content ?? '').trim() !== '').length
  if (withComment > 0) {
    summaryList.push(`其中 ${withComment} 筆附有文字評論，可作為服務改善的具體參考。`)
  }

  const suggestions: string[] = []
  if (dimAverages.length > 0 && dimAverages[0].avg < 4.5) {
    suggestions.push(
      `「${dimAverages[0].label}」平均 ${dimAverages[0].avg.toFixed(1)} 分為各面向最低，建議優先改善此環節。`
    )
  }
  if (counts.negative > 0) {
    suggestions.push(
      `有 ${counts.negative} 筆負面評價（${pct(counts.negative)}%），建議檢視這些訂單的服務紀錄並主動聯繫客戶。`
    )
  }
  if (counts.neutral > 0) {
    suggestions.push(
      `${counts.neutral} 筆中立評價代表體驗尚可但未達期待，是最容易透過細節優化轉為正面的區間。`
    )
  }
  if (suggestions.length === 0) {
    suggestions.push('目前各面向表現良好，建議維持現有服務品質並持續累積評價樣本。')
  }

  return {
    summaryList,
    suggestions,
    sentimentScore: {
      positive: pct(counts.positive),
      neutral: pct(counts.neutral),
      negative: pct(counts.negative),
    },
    analyzedPeriod,
  }
}

/**
 * 17. GET /merchant-api/vendors/{service_vendor_id}/review-summary 回應
 *
 * ⚠️ summary_highlights 的形狀已改過兩次，三種都要容忍：
 *   文件版   { pros, cons }
 *   舊實測版 { summary_points: string[], suggestions }
 *   現行版   { summary: string, suggestions }   ← summary 是**單一字串**，不是陣列
 */
interface ApiReviewSummary {
  service_vendor_id?: number
  summary_content?: string | null
  summary_highlights?: {
    /** 現行版：整段敘述字串（防禦性地也容忍陣列） */
    summary?: string | string[] | null
    summary_points?: string[] | null
    suggestions?: string[] | null
    pros?: string[] | null
    cons?: string[] | null
  } | null
  sentiment_stats?: {
    positive?: number
    neutral?: number
    negative?: number
  } | null
  service_breakdown?:
    | { service_id?: number; review_count?: number; avg_rating?: number }[]
    | null
  source_review_count?: number | null
  source_avg_rating?: number | null
  latest_review_cre_time?: string | null
  ai_model?: string | null
  generate_status?: string | null
  generate_time?: string | null
  error_message?: string | null
  is_stale?: boolean
  [key: string]: unknown
}

const VALID_SUMMARY_STATUS: mock.SummaryGenerateStatus[] = ['00', '01', '02', '03']

/** 將 AI 摘要回應轉為 Dashboard 使用的 AiAnalysis */
function mapReviewSummary(data: ApiReviewSummary): mock.AiAnalysis {
  const h = data.summary_highlights ?? {}

  // 現行版的 summary 是單一字串；若後端哪天改回陣列也照樣接得住
  const rawSummary = h.summary
  const summaryText =
    typeof rawSummary === 'string'
      ? rawSummary.trim() || undefined
      : Array.isArray(rawSummary)
        ? rawSummary.filter((s): s is string => typeof s === 'string').join('\n').trim() ||
          undefined
        : undefined

  // 舊結構的陣列摘要（文件為 pros、舊實測為 summary_points）
  const summaryList = h.summary_points ?? h.pros ?? []
  const suggestions = h.suggestions ?? h.cons ?? []

  const counts = {
    positive: data.sentiment_stats?.positive ?? 0,
    neutral: data.sentiment_stats?.neutral ?? 0,
    negative: data.sentiment_stats?.negative ?? 0,
  }
  // sentiment_stats 是筆數，進度條需要百分比
  const total = counts.positive + counts.neutral + counts.negative
  const pct = (n: number) => (total === 0 ? 0 : Math.round((n / total) * 100))

  const status = VALID_SUMMARY_STATUS.includes(
    data.generate_status as mock.SummaryGenerateStatus
  )
    ? (data.generate_status as mock.SummaryGenerateStatus)
    : undefined

  return {
    summaryText,
    summaryList: summaryList.filter((s): s is string => typeof s === 'string'),
    suggestions: suggestions.filter((s): s is string => typeof s === 'string'),
    sentimentScore: {
      positive: pct(counts.positive),
      neutral: pct(counts.neutral),
      negative: pct(counts.negative),
    },
    // summary_content 實測為「分析期間：…」字串，直接作為期間顯示
    analyzedPeriod: data.summary_content?.trim() || '分析期間未提供',
    sentimentCounts: counts,
    sourceReviewCount: data.source_review_count ?? undefined,
    sourceAvgRating: data.source_avg_rating ?? undefined,
    serviceBreakdown: (data.service_breakdown ?? [])
      .filter((b) => typeof b?.service_id === 'number')
      .map((b) => ({
        serviceId: b.service_id!,
        reviewCount: b.review_count ?? 0,
        avgRating: b.avg_rating ?? 0,
      })),
    aiModel: data.ai_model ?? undefined,
    generateStatus: status,
    generateTime: data.generate_time ?? undefined,
    errorMessage: data.error_message ?? null,
    isStale: data.is_stale ?? false,
    latestReviewAt: data.latest_review_cre_time ?? undefined,
    source: 'ai-summary',
  }
}

/**
 * 由原始評價即時推導分析（AI 摘要尚未生成時的替代方案）
 *
 * 後端沒有任何評價時回 null —— 沒資料就讓卡片留空，不用 Mock 分析內容。
 */
async function deriveAnalysisFromReviewsEndpoint(): Promise<mock.AiAnalysis | null> {
  const data = await apiFetch<ApiListResponse<ApiOrderReview> | ApiOrderReview[]>(
    `/merchant-api/vendors/${currentVendorId}/reviews`
  )
  const reviews = extractItems(data)
  if (reviews.length === 0) {
    console.info('[Reviews] 後端無評價資料')
    return null
  }
  return { ...deriveAnalysisFromReviews(reviews), source: 'derived' }
}

/**
 * 17. 取得商家整合評價 AI 摘要
 * GET /merchant-api/vendors/{service_vendor_id}/review-summary
 *
 * 尚未生成過摘要時後端回 404 —— 此時改以 GET /vendors/{id}/reviews
 * 的原始評價即時推導（這是真實資料，不是 Mock）。
 * 兩條路都拿不到時回 null，由 UI 顯示「無摘要」而非假分析。
 */
export async function getDashboardAiAnalysis(): Promise<mock.AiAnalysis | null> {
  try {
    const data = await apiFetch<ApiReviewSummary>(
      `/merchant-api/vendors/${currentVendorId}/review-summary`
    )
    return mapReviewSummary(data)
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) {
      console.info('[ReviewSummary] 尚未生成 AI 摘要，改由原始評價即時推導')
      try {
        return await deriveAnalysisFromReviewsEndpoint()
      } catch (fallbackErr) {
        console.warn('[Reviews] 推導失敗:', fallbackErr)
        return null
      }
    }
    console.warn('[ReviewSummary] Real API failed:', err)
    notifyError('評價摘要暫時無法載入，請稍後再試')
    return null
  }
}

// ════════════════════════════════════════════════════════════
// 由上述端點推導的統計（不呼叫額外端點）
// ════════════════════════════════════════════════════════════

/**
 * Dashboard 統計 - BFF 無專用端點，從 feedbacks + orders 計算。
 * 兩支各自獨立 catch，任一支失效時另一支仍能提供真實數字。
 *
 * 兩支都失敗時回 null 讓畫面留空。刻意不回 0 —— 「載入失敗」與
 * 「今天真的是 0 筆」在畫面上長得一樣會誤導；也不用 Mock 假數字。
 */
export async function fetchDashboardStats(): Promise<mock.DashboardStats | null> {
  let feedbacksFailed = false
  let ordersFailed = false

  try {
    const [feedbackItems, orderItems] = await Promise.all([
      fetchRawFeedbacks().catch((e) => {
        console.warn('[DashboardStats] feedbacks failed:', e)
        feedbacksFailed = true
        return [] as ApiFeedbackItem[]
      }),
      fetchRawOrders().catch((e) => {
        console.warn('[DashboardStats] orders failed:', e)
        ordersFailed = true
        return [] as ApiOrderItem[]
      }),
    ])

    if (feedbacksFailed && ordersFailed) {
      notifyError('無法載入儀表板統計，請稍後再試')
      return null
    }

    const now = new Date()
    const todayKey = toLocalDateKey(now)
    const thisMonthKey = toLocalMonthKey(now)

    // 今日諮詢單
    const todayConsultations = feedbackItems.filter((f) => {
      const t = parseTime(f.cre_time)
      return t != null && toLocalDateKey(t) === todayKey
    }).length

    // 待處理訂單：待付款(11) / 已付訂金(12) / 服務進行中(04)
    const pendingOrders = orderItems.filter((o) =>
      ['11', '12', '04'].includes(o.order_status)
    ).length

    // 本月服務收益：當月「已完成(80)」訂單的實付金額(final_amount)總和。
    // 時間基準優先用完成時間，未提供則退而用訂單成立時間。
    const monthlyRevenue = orderItems
      .filter((o) => o.order_status === '80')
      .filter((o) => {
        const t = parseTime(o.complete_time) ?? orderPlacedAt(o)
        return t != null && toLocalMonthKey(t) === thisMonthKey
      })
      .reduce((sum, o) => sum + (o.final_amount || 0), 0)

    // 最近一筆訂單時間，供 UI 在「區間內無資料」時顯示提示
    const latestOrderAt = orderItems
      .map((o) => orderPlacedAt(o))
      .filter((d): d is Date => d != null)
      .sort((a, b) => b.getTime() - a.getTime())[0]

    return {
      todayConsultations,
      pendingOrders,
      monthlyRevenue,
      latestOrderAt: latestOrderAt?.toISOString(),
    }
  } catch (err) {
    console.warn('[DashboardStats] Real API failed:', err)
    notifyError('無法載入儀表板統計，請稍後再試')
    return null
  }
}

/**
 * 近 7 天訂單趨勢 - 由訂單清單推導
 *
 * 以訂單成立時間（order_time，缺則 cre_time）分桶，並用本地時區的日期比對。
 * 區間內沒有訂單時會回傳 7 個 0 的資料點（而非空陣列），
 * 讓圖表仍能畫出座標軸，由 UI 另外提示「近七天無訂單」。
 */
export async function fetchOrderTrends(): Promise<mock.OrderTrend[]> {
  try {
    const orderItems = await fetchRawOrders()

    // 先把每筆訂單歸到本地日期，避免在迴圈內重複解析
    const countByDate = new Map<string, number>()
    for (const o of orderItems) {
      const t = orderPlacedAt(o)
      if (!t) continue
      const key = toLocalDateKey(t)
      countByDate.set(key, (countByDate.get(key) ?? 0) + 1)
    }

    const trends: mock.OrderTrend[] = []
    for (let i = 6; i >= 0; i--) {
      const date = new Date()
      date.setDate(date.getDate() - i)
      trends.push({
        day: `${date.getMonth() + 1}/${date.getDate()}`,
        orders: countByDate.get(toLocalDateKey(date)) ?? 0,
      })
    }
    return trends
  } catch (err) {
    console.warn('[OrderTrends] Real API failed:', err)
    notifyError('無法載入訂單趨勢，請稍後再試')
    return []
  }
}

// ─── Re-export types and constants from mockApi ───

export {
  ORDER_STATUS_MAP,
  TYPES_WITH_OPTIONS,
  FIELD_INPUT_TYPE_LABELS,
  SUMMARY_STATUS_LABELS,
} from './mockApi'
export type {
  SummaryGenerateStatus,
  ServiceReviewBreakdown,
  OrderVendorData,
  DashboardStats,
  OrderTrend,
  FormFeedback,
  FeedbackStatus,
  OrderRecord,
  OrderItem,
  OrderStatusCode,
  AiAnalysis,
  VendorProfile,
  ServiceLabel,
  VendorService,
  ServiceForm,
  FormField,
  FieldInputType,
} from './mockApi'

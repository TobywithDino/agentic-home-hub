// ============================================================
// API Module - 智慧社區服務媒合平台 廠商端管理後台
// 對接真實後端 API (BFF Layer + AI Service)
// ============================================================

import * as mock from './mockApi'

export const BASE_URL = 'http://52.10.163.115:8100'
export const AI_BASE_URL = 'http://52.10.163.115:8000'

// 預設 vendor_id（登入成功後會更新）
let currentVendorId = 1
// account_id 為 UUID 字串格式，後端 Pydantic 要求必須是 UUID，不可傳 number
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

const defaultHeaders: HeadersInit = {
  'Content-Type': 'application/json',
}

async function apiFetch<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
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
    throw new Error(`API Error ${res.status}: ${errorBody || res.statusText}`)
  }

  return res.json() as Promise<T>
}

// ─── Error callback (Toast 顯示用) ───

type ErrorCallback = (message: string) => void
let onApiError: ErrorCallback | null = null

/**
 * 註冊全域 API 錯誤回呼，頁面可透過此函式接收錯誤訊息並顯示 Toast
 */
export function registerApiErrorHandler(cb: ErrorCallback) {
  onApiError = cb
}

function notifyError(message: string) {
  console.warn('[API Error]', message)
  if (onApiError) onApiError(message)
}

// ─── Login ───

interface LoginResponse {
  service_vendor_id?: number
  account_id?: string   // UUID 字串
  detail?: string
}

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
        currentAccountId = data.account_id   // 存 UUID 字串
      }
      return { success: true, vendorId: data.service_vendor_id }
    }

    return { success: false, message: data.detail || '登入失敗' }
  } catch (err) {
    // Fallback: 如果後端無法連線，使用 mock
    console.warn('[Login] Real API failed, falling back to mock:', err)
    notifyError('無法連線至伺服器，使用離線模式登入')
    return mock.login(account, password)
  }
}

// ─── Feedbacks (諮詢單) ───

/**
 * 後端回傳的原始 feedback 結構
 */
interface ApiFeedbackItem {
  feedback_no: string
  form_id: number | null
  service_vendor_id: number
  inbr_account_id: string
  contact_name: string | null
  contact_phone: string | null
  contact_email: string | null
  form_type: string | null
  feedback_content: string | null
  preferred_contact_time: string | null
  address: string | null
  status: string | null
  is_read: boolean
  remark: string | null
  cre_time: string | null
  upd_time: string | null
  [key: string]: unknown
}

interface ApiListResponse<T> {
  total: number
  limit: number
  offset: number
  items: T[]
}

/**
 * 將後端 feedback 格式轉換為前端 FormFeedback 格式
 */
function mapApiFeedbackToLocal(item: ApiFeedbackItem): mock.FormFeedback {
  // 將後端 status 對應到前端中文狀態
  let status: mock.FeedbackStatus = '待處理'
  if (item.status === 'accepted' || item.status === '已接單') status = '已接單'
  else if (item.status === 'declined' || item.status === '已拒絕') status = '已拒絕'
  else if (item.status === 'pending' || item.status === '待處理' || !item.status) status = '待處理'

  return {
    id: item.feedback_no,
    contactName: item.contact_name || '未提供',
    serviceType: item.form_type || '一般諮詢',
    preferredContactTime: item.preferred_contact_time || '未指定',
    status,
    phone: item.contact_phone || '未提供',
    email: item.contact_email || '未提供',
    address: item.address || '未提供',
    specialRequirements: item.remark || '',
    selectedOptions: [],
    content: item.feedback_content || '',
    createdAt: item.cre_time ? new Date(item.cre_time).toLocaleString('zh-TW') : '',
  }
}

export async function fetchFeedbacks(): Promise<mock.FormFeedback[]> {
  try {
    const data = await apiFetch<ApiListResponse<ApiFeedbackItem>>(
      `/merchant-api/vendors/${currentVendorId}/feedbacks`
    )
    return data.items.map(mapApiFeedbackToLocal)
  } catch (err) {
    console.warn('[Feedbacks] Real API failed, falling back to mock:', err)
    notifyError('無法載入諮詢單資料，已切換為離線模式')
    return mock.fetchFeedbacks()
  }
}

export async function acceptFeedback(
  feedbackNo: string
): Promise<{ success: boolean; feedback: mock.FormFeedback; newOrder: mock.OrderRecord }> {
  try {
    await apiFetch(`/merchant-api/feedbacks/${feedbackNo}/status`, {
      method: 'PATCH',
      body: JSON.stringify({
        status: 'accepted',
        upd_id: getUpdId(),
      }),
    })

    // 重新拉取最新資料以確保同步
    const feedbacks = await fetchFeedbacks()
    const updated = feedbacks.find((f) => f.id === feedbackNo)

    // 建立一筆 mock order 作為回傳（真實系統後端會自動建立）
    const newOrder: mock.OrderRecord = {
      id: `ORD-${Date.now()}`,
      customerName: updated?.contactName || '',
      serviceName: updated?.serviceType || '',
      originalAmount: 0,
      finalAmount: 0,
      serviceTime: '待確認',
      orderStatus: '11',
      createdAt: new Date().toLocaleString('zh-TW'),
      address: updated?.address || '',
      phone: updated?.phone || '',
      orderItems: [],
    }

    return {
      success: true,
      feedback: updated || { id: feedbackNo, contactName: '', serviceType: '', preferredContactTime: '', status: '已接單', phone: '', email: '', address: '', specialRequirements: '', selectedOptions: [], content: '', createdAt: '' },
      newOrder,
    }
  } catch (err) {
    console.warn('[AcceptFeedback] Real API failed, falling back to mock:', err)
    notifyError('接單操作失敗，已使用離線模式')
    return mock.acceptFeedback(feedbackNo)
  }
}

export async function declineFeedback(
  feedbackNo: string,
  reason: string
): Promise<{ success: boolean; feedback: mock.FormFeedback }> {
  try {
    await apiFetch(`/merchant-api/feedbacks/${feedbackNo}/status`, {
      method: 'PATCH',
      body: JSON.stringify({
        status: 'declined',
        remark: reason,
        upd_id: getUpdId(),
      }),
    })

    const feedbacks = await fetchFeedbacks()
    const updated = feedbacks.find((f) => f.id === feedbackNo)

    return {
      success: true,
      feedback: updated || { id: feedbackNo, contactName: '', serviceType: '', preferredContactTime: '', status: '已拒絕', phone: '', email: '', address: '', specialRequirements: '', selectedOptions: [], content: '', createdAt: '', declineReason: reason },
    }
  } catch (err) {
    console.warn('[DeclineFeedback] Real API failed, falling back to mock:', err)
    notifyError('婉拒操作失敗，已使用離線模式')
    return mock.declineFeedback(feedbackNo, reason)
  }
}

// ─── Orders (訂單) ───

/**
 * 後端回傳的原始 order 結構
 */
interface ApiOrderItem {
  record_id: number
  order_no: string
  service_vendor_id: number
  service_id: number | null
  inbr_account_id: string
  member_name: string | null
  member_name_hash: string | null
  member_phone: string | null
  member_phone_hash: string | null
  order_status: string
  order_time: string | null
  service_time: string | null
  complete_time: string | null
  original_amount: number
  final_amount: number
  order_items: ApiOrderItemDetail[] | null
  remark: string | null
  cre_time: string | null
  [key: string]: unknown
}

interface ApiOrderItemDetail {
  itemName: string
  quantity: number
  unitPrice: number
  unit?: string
  attribute?: string
  itemAmount?: number | null
}

function mapApiOrderToLocal(item: ApiOrderItem): mock.OrderRecord {
  const orderStatus = (['11', '12', '04', '80', '90'].includes(item.order_status)
    ? item.order_status
    : '11') as mock.OrderStatusCode

  const orderItems: mock.OrderItem[] = (item.order_items || []).map((oi) => ({
    name: oi.itemName || '未命名項目',
    quantity: oi.quantity || 1,
  }))

  return {
    id: item.order_no,
    customerName: item.member_name || '(加密隱藏)',
    serviceName: orderItems.length > 0 ? orderItems.map((i) => i.name).join('、') : '服務項目',
    originalAmount: item.original_amount || 0,
    finalAmount: item.final_amount || 0,
    serviceTime: item.service_time
      ? new Date(item.service_time).toLocaleString('zh-TW')
      : item.order_time
        ? new Date(item.order_time).toLocaleString('zh-TW')
        : '待確認',
    orderStatus,
    createdAt: item.cre_time ? new Date(item.cre_time).toLocaleString('zh-TW') : '',
    address: '',  // 後端目前未提供，保留空字串
    phone: '',    // 後端有 hash 但無明文
    orderItems,
    // 保留 record_id 供更新用
    _recordId: item.record_id,
  } as mock.OrderRecord & { _recordId: number }
}

export async function fetchOrders(): Promise<mock.OrderRecord[]> {
  try {
    const data = await apiFetch<ApiListResponse<ApiOrderItem>>(
      `/merchant-api/vendors/${currentVendorId}/orders`
    )
    return data.items.map(mapApiOrderToLocal)
  } catch (err) {
    console.warn('[Orders] Real API failed, falling back to mock:', err)
    notifyError('無法載入訂單資料，已切換為離線模式')
    return mock.fetchOrders()
  }
}

export async function updateOrderStatus(
  orderId: string,
  newStatus: mock.OrderStatusCode,
  recordId?: number
): Promise<{ success: boolean; order: mock.OrderRecord }> {
  try {
    // 需要 record_id 來呼叫後端 PATCH
    if (!recordId) {
      // 嘗試從已載入的訂單中找 record_id
      const orders = await apiFetch<ApiListResponse<ApiOrderItem>>(
        `/merchant-api/vendors/${currentVendorId}/orders`
      )
      const target = orders.items.find((o) => o.order_no === orderId)
      if (target) {
        recordId = target.record_id
      }
    }

    if (recordId) {
      await apiFetch(
        `/merchant-api/vendors/${currentVendorId}/orders/${recordId}`,
        {
          method: 'PATCH',
          body: JSON.stringify({
            order_status: newStatus,
            upd_id: getUpdId(),
          }),
        }
      )
    }

    // 重新拉取更新後的資料
    const updatedOrders = await fetchOrders()
    const updatedOrder = updatedOrders.find((o) => o.id === orderId)

    if (updatedOrder) {
      return { success: true, order: updatedOrder }
    }

    throw new Error('Order not found after update')
  } catch (err) {
    console.warn('[UpdateOrderStatus] Real API failed, falling back to mock:', err)
    notifyError('訂單狀態更新失敗，已使用離線模式')
    return mock.updateOrderStatus(orderId, newStatus)
  }
}

// ─── Dashboard Stats & AI Analysis ───

/**
 * Dashboard 統計 - 目前後端無專用端點，從 feedbacks + orders 計算
 */
export async function fetchDashboardStats(): Promise<mock.DashboardStats> {
  try {
    const [feedbacks, orders] = await Promise.all([
      apiFetch<ApiListResponse<ApiFeedbackItem>>(
        `/merchant-api/vendors/${currentVendorId}/feedbacks`
      ),
      apiFetch<ApiListResponse<ApiOrderItem>>(
        `/merchant-api/vendors/${currentVendorId}/orders`
      ),
    ])

    // 計算今日諮詢單
    const today = new Date().toISOString().slice(0, 10)
    const todayConsultations = feedbacks.items.filter(
      (f) => f.cre_time && f.cre_time.slice(0, 10) === today
    ).length

    // 計算待處理訂單 (status 11 or 12)
    const pendingOrders = orders.items.filter(
      (o) => o.order_status === '11' || o.order_status === '12'
    ).length

    // 本月收益 (status 80 已完成)
    const thisMonth = new Date().toISOString().slice(0, 7)
    const monthlyRevenue = orders.items
      .filter((o) => o.order_status === '80' && o.complete_time && o.complete_time.slice(0, 7) === thisMonth)
      .reduce((sum, o) => sum + (o.final_amount || 0), 0)

    return {
      todayConsultations: todayConsultations || feedbacks.total,
      pendingOrders,
      monthlyRevenue,
    }
  } catch (err) {
    console.warn('[DashboardStats] Real API failed, falling back to mock:', err)
    return mock.fetchDashboardStats()
  }
}

export async function fetchOrderTrends(): Promise<mock.OrderTrend[]> {
  try {
    const data = await apiFetch<ApiListResponse<ApiOrderItem>>(
      `/merchant-api/vendors/${currentVendorId}/orders`
    )

    // 根據真實訂單資料計算近 7 天趨勢
    const trends: mock.OrderTrend[] = []
    for (let i = 6; i >= 0; i--) {
      const date = new Date()
      date.setDate(date.getDate() - i)
      const dateStr = date.toISOString().slice(0, 10)
      const dayLabel = `${date.getMonth() + 1}/${date.getDate()}`
      const count = data.items.filter(
        (o) => o.cre_time && o.cre_time.slice(0, 10) === dateStr
      ).length
      trends.push({ day: dayLabel, orders: count })
    }

    return trends
  } catch (err) {
    console.warn('[OrderTrends] Real API failed, falling back to mock:', err)
    return mock.fetchOrderTrends()
  }
}

/**
 * AI 分析 - 對接 AI 服務 (port 8000)
 *
 * 端點: POST ${AI_BASE_URL}/ai/vendor-analysis
 * 後端利用 Amazon Bedrock 進行全量客戶回饋的大模型分析，回傳結構化洞察結果。
 *
 * 若 AI 服務不可用或端點尚未部署，自動降級 (Fallback) 至 Mock 資料。
 */
export async function getDashboardAiAnalysis(): Promise<mock.AiAnalysis> {
  try {
    const url = `${AI_BASE_URL}/ai/vendor-analysis`
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ service_vendor_id: currentVendorId }),
    })

    if (!res.ok) {
      throw new Error(`AI API Error ${res.status}: ${res.statusText}`)
    }

    const data = await res.json()

    // 將後端回傳格式正規化為 AiAnalysis 介面
    const analysis: mock.AiAnalysis = {
      summaryList: data.summary_list ?? data.summaryList ?? [],
      suggestions: data.suggestions ?? [],
      sentimentScore: {
        positive: data.sentiment_score?.positive ?? data.sentimentScore?.positive ?? 0,
        neutral: data.sentiment_score?.neutral ?? data.sentimentScore?.neutral ?? 0,
        negative: data.sentiment_score?.negative ?? data.sentimentScore?.negative ?? 0,
      },
      analyzedPeriod: data.analyzed_period ?? data.analyzedPeriod ?? '分析期間未提供',
    }

    return analysis
  } catch (err) {
    console.warn('[AI Analysis] AI service (port 8000) failed, falling back to mock:', err)
    notifyError('AI 分析服務暫時無法連線，已使用離線分析資料')
    return mock.getDashboardAiAnalysis()
  }
}

// ─── Re-export types and constants from mockApi ───

export { ORDER_STATUS_MAP } from './mockApi'
export type {
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
} from './mockApi'

// ─── Vendor Profile (仍使用 Mock，後端端點已知但格式待確認) ───

export { getVendorProfile, updateVendorProfile } from './mockApi'
export { getVendorLabels, updateVendorServiceLabels } from './mockApi'

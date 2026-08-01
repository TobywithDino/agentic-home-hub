// ============================================================
// Mock API - 智慧社區服務媒合平台 廠商端管理後台
// ============================================================

export interface DashboardStats {
  todayConsultations: number
  pendingOrders: number
  monthlyRevenue: number
}

export interface OrderTrend {
  day: string
  orders: number
}

// ─── pms_form_feedback (諮詢單 - 成交前：需求理解與報價階段) ───

export type FeedbackStatus = '待處理' | '已接單' | '已拒絕'

export interface FormFeedback {
  id: string // feedback_no
  contactName: string
  serviceType: string
  preferredContactTime: string
  status: FeedbackStatus
  phone: string
  email: string
  address: string
  specialRequirements: string
  selectedOptions: string[]
  content: string
  createdAt: string
  declineReason?: string
}

// ─── mms_order_record (訂單 - 成交後：正式交易與履約階段) ───

export type OrderStatusCode = '11' | '12' | '04' | '80' | '90'

export const ORDER_STATUS_MAP: Record<OrderStatusCode, string> = {
  '11': '待付款',
  '12': '已付訂金',
  '04': '服務進行中',
  '80': '已完成',
  '90': '已取消',
}

export interface OrderItem {
  name: string
  quantity: number
}

export interface OrderRecord {
  id: string // order_no
  customerName: string
  serviceName: string
  originalAmount: number
  finalAmount: number
  serviceTime: string
  orderStatus: OrderStatusCode
  createdAt: string
  address: string
  phone: string
  orderItems: OrderItem[]
}

// ---------- Mock Data ----------

const mockFeedbacks: FormFeedback[] = [
  {
    id: 'FB-20240801-001',
    contactName: '王小明',
    serviceType: '居家清潔',
    preferredContactTime: '平日下午 14:00-17:00',
    status: '待處理',
    phone: '0912-345-678',
    email: 'wang.ming@example.com',
    address: '台北市大安區忠孝東路三段 100 號 5 樓',
    specialRequirements: '家中有兩隻貓，需使用無毒清潔劑',
    selectedOptions: ['定期清潔', '每週一次', '三房兩廳'],
    content: '需要每週固定清潔服務，三房兩廳約 35 坪，家中有寵物（兩隻貓），希望使用無毒清潔劑。時間偏好為平日下午。',
    createdAt: '2024-08-01 09:30',
  },
  {
    id: 'FB-20240801-002',
    contactName: '李美玲',
    serviceType: '冷氣維修',
    preferredContactTime: '週末皆可',
    status: '待處理',
    phone: '0923-456-789',
    email: 'li.meiling@example.com',
    address: '新北市板橋區文化路一段 88 號 3 樓',
    specialRequirements: '冷氣已使用三年，最近有異味',
    selectedOptions: ['到府檢修', '大金品牌'],
    content: '客廳冷氣機不冷，已使用三年，品牌為大金。最近有異味產生，希望盡快處理。',
    createdAt: '2024-08-01 10:15',
  },
  {
    id: 'FB-20240801-003',
    contactName: '張志豪',
    serviceType: '水電修繕',
    preferredContactTime: '平日上午優先',
    status: '已接單',
    phone: '0934-567-890',
    email: 'zhang.zhihao@example.com',
    address: '台北市中山區南京東路二段 50 號 8 樓',
    specialRequirements: '希望同一天處理完畢',
    selectedOptions: ['水龍頭維修', '排水管疏通'],
    content: '浴室水龍頭漏水，廚房排水管堵塞，希望同一天處理完畢。',
    createdAt: '2024-07-30 14:00',
  },
  {
    id: 'FB-20240801-004',
    contactName: '陳雅婷',
    serviceType: '居家清潔',
    preferredContactTime: '週三、週五下午',
    status: '待處理',
    phone: '0945-678-901',
    email: 'chen.yating@example.com',
    address: '台北市信義區松仁路 200 號 12 樓',
    specialRequirements: '搬家後全屋深度清潔',
    selectedOptions: ['深度清潔', '窗戶清潔', '廚房油污', '浴室水垢'],
    content: '搬家後需要全屋深度清潔，包含窗戶、廚房油污、浴室水垢。面積約 28 坪。',
    createdAt: '2024-08-01 11:45',
  },
  {
    id: 'FB-20240801-005',
    contactName: '林建宏',
    serviceType: '冷氣維修',
    preferredContactTime: '不限',
    status: '已拒絕',
    phone: '0956-789-012',
    email: 'lin.jianhong@example.com',
    address: '新北市永和區中正路 150 號 6 樓',
    specialRequirements: '需確認窗框是否適合安裝',
    selectedOptions: ['窗型冷氣', '安裝諮詢'],
    content: '臥室窗型冷氣安裝諮詢，需要確認是否可以安裝在指定位置。',
    createdAt: '2024-07-28 16:20',
    declineReason: '超出服務區域',
  },
]

const mockOrders: OrderRecord[] = [
  {
    id: 'ORD-20240801-001',
    customerName: '王小明',
    serviceName: '居家清潔 - 定期方案',
    originalAmount: 3200,
    finalAmount: 2800,
    serviceTime: '2024-08-05 14:00',
    orderStatus: '11',
    createdAt: '2024-08-01 10:00',
    address: '台北市大安區忠孝東路三段 100 號 5 樓',
    phone: '0912-345-678',
    orderItems: [
      { name: '三房兩廳定期清潔', quantity: 1 },
      { name: '寵物環境消毒加價', quantity: 1 },
    ],
  },
  {
    id: 'ORD-20240801-002',
    customerName: '李美玲',
    serviceName: '冷氣維修 - 到府檢修',
    originalAmount: 1800,
    finalAmount: 1500,
    serviceTime: '2024-08-02 10:00',
    orderStatus: '04',
    createdAt: '2024-08-01 10:30',
    address: '新北市板橋區文化路一段 88 號 3 樓',
    phone: '0923-456-789',
    orderItems: [
      { name: '冷氣到府檢修', quantity: 1 },
      { name: '冷媒填充', quantity: 1 },
    ],
  },
  {
    id: 'ORD-20240731-003',
    customerName: '張志豪',
    serviceName: '水電修繕 - 一般維修',
    originalAmount: 3500,
    finalAmount: 3200,
    serviceTime: '2024-07-31 09:00',
    orderStatus: '80',
    createdAt: '2024-07-30 15:00',
    address: '台北市中山區南京東路二段 50 號 8 樓',
    phone: '0934-567-890',
    orderItems: [
      { name: '水龍頭更換', quantity: 1 },
      { name: '排水管疏通', quantity: 1 },
      { name: '材料費', quantity: 1 },
    ],
  },
  {
    id: 'ORD-20240801-004',
    customerName: '陳雅婷',
    serviceName: '居家清潔 - 深度清潔',
    originalAmount: 6000,
    finalAmount: 5500,
    serviceTime: '2024-08-06 09:00',
    orderStatus: '12',
    createdAt: '2024-08-01 12:00',
    address: '台北市信義區松仁路 200 號 12 樓',
    phone: '0945-678-901',
    orderItems: [
      { name: '全屋深度清潔', quantity: 1 },
      { name: '窗戶清潔', quantity: 4 },
      { name: '廚房油污清除', quantity: 1 },
      { name: '浴室水垢清除', quantity: 2 },
    ],
  },
  {
    id: 'ORD-20240730-005',
    customerName: '林建宏',
    serviceName: '冷氣維修 - 安裝服務',
    originalAmount: 4500,
    finalAmount: 4000,
    serviceTime: '2024-08-03 13:00',
    orderStatus: '90',
    createdAt: '2024-07-30 17:00',
    address: '新北市永和區中正路 150 號 6 樓',
    phone: '0956-789-012',
    orderItems: [
      { name: '窗型冷氣安裝', quantity: 1 },
      { name: '安裝支架', quantity: 1 },
    ],
  },
  {
    id: 'ORD-20240729-006',
    customerName: '黃雅芬',
    serviceName: '居家清潔 - 單次清潔',
    originalAmount: 2000,
    finalAmount: 1800,
    serviceTime: '2024-07-29 10:00',
    orderStatus: '80',
    createdAt: '2024-07-28 09:00',
    address: '台北市松山區南京東路五段 66 號 10 樓',
    phone: '0967-890-123',
    orderItems: [
      { name: '兩房一廳單次清潔', quantity: 1 },
    ],
  },
]

const mockOrderTrends: OrderTrend[] = [
  { day: '7/26', orders: 3 },
  { day: '7/27', orders: 5 },
  { day: '7/28', orders: 2 },
  { day: '7/29', orders: 7 },
  { day: '7/30', orders: 4 },
  { day: '7/31', orders: 6 },
  { day: '8/1', orders: 8 },
]

// ---------- Helper ----------

let orderCounter = 7

function generateOrderId(): string {
  const now = new Date()
  const dateStr = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`
  return `ORD-${dateStr}-${String(orderCounter++).padStart(3, '0')}`
}

function getNowString(): string {
  const now = new Date()
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')} ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`
}

// ---------- Mock API Functions ----------

function delay(ms: number = 500): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export async function login(username: string, password: string): Promise<{ success: boolean; vendorId?: number; message?: string }> {
  await delay(800)
  if (username && password) {
    return { success: true, vendorId: 1 }
  }
  return { success: false, message: '帳號或密碼錯誤' }
}

export async function fetchDashboardStats(): Promise<DashboardStats> {
  await delay(600)
  return {
    todayConsultations: 4,
    pendingOrders: 2,
    monthlyRevenue: 48500,
  }
}

export async function fetchOrderTrends(): Promise<OrderTrend[]> {
  await delay(400)
  return mockOrderTrends
}

export async function fetchFeedbacks(): Promise<FormFeedback[]> {
  await delay(500)
  return [...mockFeedbacks]
}

/**
 * 確認接單：將諮詢單狀態改為「已接單」，並自動產生一筆新訂單（狀態 11 待付款）
 */
export async function acceptFeedback(
  feedbackId: string
): Promise<{ success: boolean; feedback: FormFeedback; newOrder: OrderRecord }> {
  await delay(700)
  const feedback = mockFeedbacks.find((f) => f.id === feedbackId)
  if (!feedback) throw new Error('Feedback not found')
  if (feedback.status !== '待處理') throw new Error('只能對待處理的諮詢單進行接單')

  feedback.status = '已接單'

  const newOrder: OrderRecord = {
    id: generateOrderId(),
    customerName: feedback.contactName,
    serviceName: `${feedback.serviceType} - ${feedback.selectedOptions[0] || '一般服務'}`,
    originalAmount: 0,
    finalAmount: 0, // 待報價確認
    serviceTime: '待確認',
    orderStatus: '11',
    createdAt: getNowString(),
    address: feedback.address,
    phone: feedback.phone,
    orderItems: feedback.selectedOptions.map((opt) => ({ name: opt, quantity: 1 })),
  }
  mockOrders.unshift(newOrder)

  return { success: true, feedback: { ...feedback }, newOrder: { ...newOrder } }
}

/**
 * 婉拒諮詢：將諮詢單狀態改為「已拒絕」，不產生訂單
 */
export async function declineFeedback(
  feedbackId: string,
  reason: string
): Promise<{ success: boolean; feedback: FormFeedback }> {
  await delay(700)
  const feedback = mockFeedbacks.find((f) => f.id === feedbackId)
  if (!feedback) throw new Error('Feedback not found')
  if (feedback.status !== '待處理') throw new Error('只能對待處理的諮詢單進行婉拒')

  feedback.status = '已拒絕'
  feedback.declineReason = reason

  return { success: true, feedback: { ...feedback } }
}

export async function fetchOrders(): Promise<OrderRecord[]> {
  await delay(500)
  return [...mockOrders]
}

export async function updateOrderStatus(
  orderId: string,
  newStatus: OrderStatusCode
): Promise<{ success: boolean; order: OrderRecord }> {
  await delay(700)
  const order = mockOrders.find((o) => o.id === orderId)
  if (order) {
    order.orderStatus = newStatus
    return { success: true, order: { ...order } }
  }
  throw new Error('Order not found')
}

// ─── Vendor Profile (商家資訊設定) ───

export interface VendorProfile {
  // 區塊 A: 商家屬性
  name: string
  description: string
  // 區塊 B: 管理員帳號
  adminName: string
  adminPhone: string
  adminEmail: string
}

const mockVendorProfile: VendorProfile = {
  name: '潔淨家居清潔有限公司',
  description: '提供專業居家清潔、冷氣維修及水電修繕服務，服務範圍涵蓋大台北地區。擁有超過 10 年經驗，客戶滿意度達 98%。',
  adminName: '陳大明',
  adminPhone: '0912-000-111',
  adminEmail: 'admin@cleanhome.com.tw',
}

export async function getVendorProfile(): Promise<VendorProfile> {
  await delay(400)
  return { ...mockVendorProfile }
}

export async function updateVendorProfile(
  data: Partial<VendorProfile> & { newPassword?: string }
): Promise<{ success: boolean; profile: VendorProfile }> {
  await delay(600)
  if (data.name !== undefined) mockVendorProfile.name = data.name
  if (data.description !== undefined) mockVendorProfile.description = data.description
  if (data.adminName !== undefined) mockVendorProfile.adminName = data.adminName
  if (data.adminPhone !== undefined) mockVendorProfile.adminPhone = data.adminPhone
  if (data.adminEmail !== undefined) mockVendorProfile.adminEmail = data.adminEmail
  // newPassword: in a real app this would hash & persist; here we just accept it
  return { success: true, profile: { ...mockVendorProfile } }
}

// ─── AI 洞察分析 (Dashboard AI Insight) ───

export interface CustomerFeedbackRecord {
  id: string
  customerName: string
  serviceType: string
  rating: number // 1-5
  comment: string
  sentiment: 'positive' | 'neutral' | 'negative'
  date: string
}

export interface AiAnalysis {
  /** 本週住戶需求 AI 摘要 (Key Takeaways) */
  summaryList: string[]
  /** 廠商營運與服務優化建議 */
  suggestions: string[]
  /** 客戶情緒/滿意度分佈 (%) */
  sentimentScore: {
    positive: number
    neutral: number
    negative: number
  }
  /** 分析資料涵蓋時間 */
  analyzedPeriod: string
}

// 豐富的客戶歷史回饋假資料
const mockCustomerFeedbacks: CustomerFeedbackRecord[] = [
  {
    id: 'CFB-001',
    customerName: '王小明',
    serviceType: '居家清潔',
    rating: 5,
    comment: '清潔人員非常專業，使用無毒清潔劑讓我很放心，家裡寵物也不會受到影響。',
    sentiment: 'positive',
    date: '2024-07-29',
  },
  {
    id: 'CFB-002',
    customerName: '李美玲',
    serviceType: '冷氣維修',
    rating: 4,
    comment: '維修速度很快，但師傅遲到了 15 分鐘，整體服務還是滿意的。',
    sentiment: 'positive',
    date: '2024-07-29',
  },
  {
    id: 'CFB-003',
    customerName: '張志豪',
    serviceType: '水電修繕',
    rating: 5,
    comment: '水龍頭和排水管同一天修好，師傅技術好又有禮貌，下次還會再預約。',
    sentiment: 'positive',
    date: '2024-07-30',
  },
  {
    id: 'CFB-004',
    customerName: '陳雅婷',
    serviceType: '居家清潔',
    rating: 3,
    comment: '深度清潔效果普通，廚房油污沒有完全清除乾淨，希望下次可以更仔細。',
    sentiment: 'neutral',
    date: '2024-07-30',
  },
  {
    id: 'CFB-005',
    customerName: '黃雅芬',
    serviceType: '居家清潔',
    rating: 4,
    comment: '整體乾淨，但浴室角落有遺漏。溝通很順暢，時間準時。',
    sentiment: 'positive',
    date: '2024-07-31',
  },
  {
    id: 'CFB-006',
    customerName: '林建宏',
    serviceType: '冷氣維修',
    rating: 2,
    comment: '冷氣安裝被取消了，但通知時間太晚，影響我的行程安排。',
    sentiment: 'negative',
    date: '2024-07-31',
  },
  {
    id: 'CFB-007',
    customerName: '周美珍',
    serviceType: '居家清潔',
    rating: 5,
    comment: '非常細心，連窗戶軌道都有清理到，超級滿意！',
    sentiment: 'positive',
    date: '2024-08-01',
  },
  {
    id: 'CFB-008',
    customerName: '吳志明',
    serviceType: '水電修繕',
    rating: 3,
    comment: '修繕完成但收費比預期高，建議事先明確報價。',
    sentiment: 'neutral',
    date: '2024-08-01',
  },
  {
    id: 'CFB-009',
    customerName: '許家豪',
    serviceType: '冷氣維修',
    rating: 4,
    comment: '冷媒加完之後涼很多，師傅也有教我平時保養的方法。',
    sentiment: 'positive',
    date: '2024-08-01',
  },
  {
    id: 'CFB-010',
    customerName: '鄭淑芬',
    serviceType: '居家清潔',
    rating: 1,
    comment: '清潔人員態度不佳，沒有按照我的要求使用指定清潔劑，很失望。',
    sentiment: 'negative',
    date: '2024-08-01',
  },
]

/**
 * getDashboardAiAnalysis - 取得 AI 智慧洞察分析
 *
 * 目前為 Mock 實作，回傳預設的結構化分析結果。
 *
 * 🔮 未來真實 API 對接規劃：
 * ─────────────────────────────
 * 此函式將改為呼叫後端 FastAPI endpoint: POST /api/v1/ai/dashboard-analysis
 * 後端將：
 *   1. 從資料庫撈取近 7 天的全量客戶回饋 (pms_form_feedback + 訂單評價)
 *   2. 透過 Amazon Bedrock (Claude / Titan 模型) 進行大模型分析
 *   3. Prompt 設計涵蓋：需求摘要提煉、營運建議產出、情緒分類統計
 *   4. 回傳結構化 JSON 格式的 AiAnalysis 物件
 *
 * Bedrock 呼叫範例 (Python):
 *   bedrock_runtime.invoke_model(
 *     modelId="anthropic.claude-3-sonnet-20240229-v1:0",
 *     body=json.dumps({ "prompt": formatted_prompt, "max_tokens": 1024 })
 *   )
 * ─────────────────────────────
 */
export async function getDashboardAiAnalysis(): Promise<AiAnalysis> {
  await delay(1000)

  // Mock: 模擬 AI 分析後的結構化結果
  return {
    summaryList: [
      '本週「居家清潔」需求佔比最高 (58%)，其中「無毒/環保清潔劑」為住戶最常提及的關鍵需求，建議列為標準服務配備。',
      '「冷氣維修」諮詢量較上週成長 30%，多集中於冷媒填充與異味處理，可能與近日高溫有關。',
      '有 3 位住戶反映預約時間彈性不足，希望能增加週末早上的服務時段。',
    ],
    suggestions: [
      '建議將「環保無毒清潔劑」納入標準服務包，並在服務頁面醒目標示，預估可提升 15% 轉換率。',
      '目前「冷氣維修」回應時間平均 4.2 小時，建議增加週末值班人力或建立快速回覆模板，將回應時間縮短至 2 小時內。',
    ],
    sentimentScore: {
      positive: 62,
      neutral: 22,
      negative: 16,
    },
    analyzedPeriod: '2024/07/26 – 2024/08/01',
  }
}

// 匯出 mockCustomerFeedbacks 供其他頁面或測試使用
export { mockCustomerFeedbacks }

// ─── 商家服務標籤 (Service Labels - 對應 DB `label` 資料表) ───

export interface ServiceLabel {
  id: number
  name: string
  category: string
}

/**
 * mockLabels - 模擬 `label` 資料表中的可用服務標籤
 * 對應後端 GET /api/v1/labels 或 GET /api/v1/service-categories/labels
 */
const mockLabels: ServiceLabel[] = [
  { id: 1, name: '水電維修', category: '維修類' },
  { id: 2, name: '專業清潔', category: '清潔類' },
  { id: 3, name: '家電保養', category: '維修類' },
  { id: 4, name: '急修服務', category: '維修類' },
  { id: 5, name: '寵物友善', category: '特殊需求' },
  { id: 6, name: '環保無毒', category: '特殊需求' },
  { id: 7, name: '冷氣清洗', category: '清潔類' },
  { id: 8, name: '除蟲消毒', category: '清潔類' },
  { id: 9, name: '管線疏通', category: '維修類' },
  { id: 10, name: '油漆粉刷', category: '裝修類' },
  { id: 11, name: '地板打蠟', category: '清潔類' },
  { id: 12, name: '搬家服務', category: '其他' },
]

/**
 * 模擬該廠商目前已綁定的服務標籤 ID (對應 DB `sevice_label` 關聯表)
 * sevice_label 表結構: { vendor_id, label_id }
 */
let mockVendorLabelIds: number[] = [1, 2, 5, 6, 7]

/**
 * getVendorLabels - 取得所有可用標籤 & 該廠商目前已綁定的標籤
 *
 * 🔮 未來真實 API 對接：
 * ─────────────────────────────
 * - GET /api/v1/labels → 取得所有系統標籤
 * - GET /api/v1/service-vendors/{vendor_id}/labels → 取得廠商已綁定標籤
 * ─────────────────────────────
 */
export async function getVendorLabels(): Promise<{
  allLabels: ServiceLabel[]
  selectedIds: number[]
}> {
  await delay(400)
  return {
    allLabels: [...mockLabels],
    selectedIds: [...mockVendorLabelIds],
  }
}

/**
 * updateVendorServiceLabels - 更新該廠商的服務標籤綁定
 *
 * 🔮 未來真實 API 對接：
 * ─────────────────────────────
 * - PUT /api/v1/service-vendors/{vendor_id}/labels
 *   body: { label_ids: number[] }
 *
 * 後端邏輯：
 *   1. 刪除 `sevice_label` 表中該 vendor 的舊紀錄
 *   2. 批次寫入新的 label_id 關聯
 *   3. 同步更新 `cms_homepage_service` 中該廠商的服務標籤快取（供首頁展示）
 *   4. 回傳更新後的標籤清單
 * ─────────────────────────────
 */
export async function updateVendorServiceLabels(
  labelIds: number[]
): Promise<{ success: boolean; selectedIds: number[] }> {
  await delay(500)
  mockVendorLabelIds = [...labelIds]
  return { success: true, selectedIds: [...mockVendorLabelIds] }
}

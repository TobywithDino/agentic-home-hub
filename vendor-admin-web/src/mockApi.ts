// ============================================================
// Mock API - 智慧社區服務媒合平台 廠商端管理後台
// ============================================================

export interface DashboardStats {
  todayConsultations: number
  pendingOrders: number
  /** 本月服務收益：當月「已完成(80)」訂單的實付金額(final_amount)總和 */
  monthlyRevenue: number
  /** 最近一筆訂單的時間（ISO）。當區間內無資料時，供 UI 顯示提示 */
  latestOrderAt?: string
}

export interface OrderTrend {
  day: string
  orders: number
}

// ─── pms_form_feedback (諮詢單 - 成交前：需求理解與報價階段) ───

export type FeedbackStatus = '待處理' | '已接單' | '已拒絕'

/**
 * 諮詢單裡的單一題目作答（依該筆諮詢單所屬表單版本的結構還原）
 *
 * 每張表單的題目組成都不同，因此詳細頁不寫死欄位，
 * 而是照著表單的題組／題目順序逐題呈現。
 */
export interface FeedbackAnswerItem {
  /** 對應 pms_form_topic.id */
  topicId?: number
  /** 題目標題；表單結構取不到時退回型別名稱 */
  title: string
  /** 題目型別，供 UI 決定呈現方式（選擇題用 Badge、照片顯示張數…） */
  inputType?: FieldInputType
  /** 題目的補充說明（表單的 remark） */
  hint?: string
  isRequired?: boolean
  /** 可讀答案；複選會有多筆 */
  values: string[]
  /** 照片題的張數（後端只存路徑，商家無法直接檢視） */
  photoCount?: number
  /** 表單有這題但顧客沒有作答 */
  unanswered?: boolean
}

/** 諮詢單作答的題組區塊，順序與表單原始定義一致 */
export interface FeedbackAnswerSection {
  /** 對應 pms_form_group.id */
  groupId?: number
  groupName?: string
  items: FeedbackAnswerItem[]
}

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
  /** 所屬服務項目 ID（後端 service_id），供依服務篩選用 */
  serviceId?: number
  /** 該筆諮詢單所屬的表單版本 id（表單為版本化設計，每次修改會產生新 id） */
  formId?: number
  /**
   * 依表單結構還原的作答內容
   *
   * 有值時詳細頁改用「照表單逐題呈現」，取代單一段落的客戶描述。
   * 表單結構載入失敗（或該版本已不存在）時為 undefined，退回 content 文字。
   */
  answerSections?: FeedbackAnswerSection[]
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

/**
 * 接單時打包進訂單 vendor_data 的原始諮詢內容
 *
 * 訂單本身只有金額與項目，缺少顧客當初填寫的客製化需求。
 * 接單轉訂單時把諮詢單內容存進 vendor_data，商家出工前即可查閱。
 */
export interface OrderVendorData {
  feedbackNo?: string
  /** 當時的表單版本 id，供日後追溯題目結構 */
  formId?: number
  /** 已還原成「題目標題：答案」的多行文字 */
  content?: string
  /** 選擇題答案 */
  selectedOptions?: string[]
  contact?: {
    name?: string
    phone?: string
    email?: string
    address?: string
  }
  specialRequirements?: string
  preferredContactTime?: string
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
  /** 所屬服務項目 ID（後端 service_id），供依服務篩選用 */
  serviceId?: number
  /** 接單時帶入的原始諮詢表單內容（後端 vendor_data） */
  vendorData?: OrderVendorData
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

/** AI 摘要生成狀態 */
export type SummaryGenerateStatus = '00' | '01' | '02' | '03'

export const SUMMARY_STATUS_LABELS: Record<SummaryGenerateStatus, string> = {
  '00': '待生成',
  '01': '生成中',
  '02': '已完成',
  '03': '生成失敗',
}

/** 各服務的評價統計 */
export interface ServiceReviewBreakdown {
  serviceId: number
  reviewCount: number
  avgRating: number
}

export interface AiAnalysis {
  /**
   * 本週回饋摘要（整段敘述）
   *
   * 後端已把 summary_highlights.summary_points（字串陣列）改為
   * summary（單一字串）。有值時以段落呈現，比拆成假的編號清單更貼近原意。
   */
  summaryText?: string
  /** 本週回饋摘要 (Key Takeaways)。舊版陣列格式與本地推導／Mock 使用 */
  summaryList: string[]
  /** 廠商營運與服務優化建議 */
  suggestions: string[]
  /** 客戶情緒/滿意度分佈 (%)，供進度條使用 */
  sentimentScore: {
    positive: number
    neutral: number
    negative: number
  }
  /** 分析資料涵蓋時間 */
  analyzedPeriod: string

  // ─── 以下來自 GET /merchant-api/vendors/{id}/review-summary ───

  /** 情緒分佈的原始筆數（非百分比） */
  sentimentCounts?: {
    positive: number
    neutral: number
    negative: number
  }
  /** 納入這份摘要的評價總筆數 */
  sourceReviewCount?: number
  /** 納入這份摘要的平均評分 */
  sourceAvgRating?: number
  /** 橫跨名下所有服務的評價統計 */
  serviceBreakdown?: ServiceReviewBreakdown[]
  /** 產生摘要所用的 AI 模型 */
  aiModel?: string
  generateStatus?: SummaryGenerateStatus
  /** 摘要生成時間 */
  generateTime?: string
  /** generateStatus 為 '03' 時的錯誤訊息 */
  errorMessage?: string | null
  /** true 代表有新評價尚未納入這份摘要 */
  isStale?: boolean
  /** 最新一筆評價的時間 */
  latestReviewAt?: string
  /** 此份分析的來源：AI 摘要端點，或前端即時由評價推導 */
  source?: 'ai-summary' | 'derived'
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

// ─── 服務項目與表單結構（Service & Form Management）───

/**
 * 題目輸入類型
 *
 * 與後端 pms_form_topic.type 代碼一對一對應，避免來回轉換造成資訊遺失：
 *   "1"=簡答  "2"=詳答  "3"=單選  "4"=複選  "5"=地區選單
 *   "6"=照片  "7"=備註  "8"=聯絡資料  "9"=日期  "10"=聯絡資料(不含地址)
 */
export type FieldInputType =
  | 'short_text'          // 1  簡答
  | 'long_text'           // 2  詳答
  | 'single_choice'       // 3  單選
  | 'multi_choice'        // 4  複選
  | 'region'              // 5  地區選單
  | 'photo'               // 6  照片
  | 'remark'              // 7  備註
  | 'contact'             // 8  聯絡資料
  | 'date'                // 9  日期
  | 'contact_no_address'  // 10 聯絡資料(不含地址)

/** 僅單選/複選題需要選項清單，其餘型別後端允許省略 options */
export const TYPES_WITH_OPTIONS: FieldInputType[] = ['single_choice', 'multi_choice']

/** 題目型別的中文顯示名稱（供表單編輯器下拉選單使用） */
export const FIELD_INPUT_TYPE_LABELS: Record<FieldInputType, string> = {
  short_text: '簡答',
  long_text: '詳答',
  single_choice: '單選',
  multi_choice: '複選',
  region: '地區選單',
  photo: '照片上傳',
  remark: '備註',
  contact: '聯絡資料',
  date: '日期',
  contact_no_address: '聯絡資料(不含地址)',
}

/** 表單題目欄位 */
export interface FormField {
  id: string
  label: string          // 欄位名稱／題目（對應後端 topic.title）
  inputType: FieldInputType
  required: boolean
  placeholder?: string   // 對應後端 topic.remark
  options?: string[]     // 供單選／複選使用（對應後端 option.option_name）
  /**
   * 後端 topic.id。存回時帶上代表「更新既有題目」，
   * 不帶則後端視為新增。新建立的欄位為 undefined。
   */
  topicId?: number
  /** 後端 topic.form_group_id，用於還原題目原本所屬的題組 */
  groupId?: number
}

/** 題組中繼資料，用於儲存時還原原本的題組結構 */
export interface FormGroupMeta {
  id: number
  name: string
  sort: number
}

/** 表單主檔 */
export interface ServiceForm {
  id: number             // form_id
  title: string          // 表單標題
  description: string    // 表單說明
  fields: FormField[]
  createdAt: string
  updatedAt: string
  /**
   * 原始題組結構。編輯器是平面欄位清單，儲存時需靠這份中繼資料
   * 還原題組（否則多題組表單會被壓縮成單一題組）。
   */
  groups?: FormGroupMeta[]
  /**
   * 表單類型代碼（後端 form.type）。更新時後端要求必填，
   * 因此需從讀取結果保留下來原樣回送。
   */
  type?: string
  /** 表單子類型代碼（後端 form.sub_type），同樣為更新時必填 */
  subType?: string
}

/** 服務項目（對應 cms_homepage_service）*/
export interface VendorService {
  id: number             // service_id
  name: string           // 服務名稱
  vendorId: number       // service_vendor_id
  form: ServiceForm | null  // 目前綁定的表單（service.form_id），無則 null
  /** 服務類型代碼（後端 type，如 "1"=居家清潔） */
  type?: string
  /** 共用同一張表單的服務數量（含自己）。0 代表尚未綁定表單 */
  sharedFormCount?: number
}

// ---------- Mock 資料 ----------

const mockVendorServices: VendorService[] = [
  {
    id: 101,
    name: '居家清潔',
    vendorId: 1,
    form: {
      id: 1001,
      title: '居家清潔服務申請表',
      description: '請填寫您的清潔需求，我們將盡快與您聯繫確認。',
      fields: [
        { id: 'f1', label: '聯絡資料', inputType: 'contact', required: true, placeholder: '姓名、電話、地址' },
        { id: 'f2', label: '坪數', inputType: 'short_text', required: true, placeholder: '例：28' },
        { id: 'f3', label: '清潔類型', inputType: 'single_choice', required: true, options: ['一般清潔', '深度清潔', '搬家清潔'] },
        { id: 'f4', label: '希望服務地區', inputType: 'region', required: true },
        { id: 'f5', label: '期望服務日期', inputType: 'date', required: false },
        { id: 'f6', label: '特殊需求', inputType: 'long_text', required: false, placeholder: '例：有寵物、需使用環保清潔劑等' },
      ],
      createdAt: '2024-07-01 10:00',
      updatedAt: '2024-07-15 14:30',
    },
  },
  {
    id: 102,
    name: '冷氣維修',
    vendorId: 1,
    form: {
      id: 1002,
      title: '冷氣維修申請表',
      description: '填寫冷氣故障狀況，技師將於收到後 2 小時內回覆。',
      fields: [
        { id: 'f1', label: '聯絡資料', inputType: 'contact_no_address', required: true, placeholder: '姓名、電話' },
        { id: 'f2', label: '冷氣品牌', inputType: 'single_choice', required: true, options: ['大金', '日立', '三菱', '國際牌', '其他'] },
        { id: 'f3', label: '故障狀況', inputType: 'multi_choice', required: true, options: ['不冷', '異味', '漏水', '異音', '無法開機'] },
        { id: 'f4', label: '故障處照片', inputType: 'photo', required: false },
        { id: 'f5', label: '偏好到府時間', inputType: 'remark', required: false, placeholder: '例：週末上午' },
      ],
      createdAt: '2024-07-01 10:00',
      updatedAt: '2024-07-20 09:15',
    },
  },
  {
    id: 103,
    name: '水電修繕',
    vendorId: 1,
    form: null,  // 尚未建立表單
  },
  {
    id: 104,
    name: '油漆粉刷',
    vendorId: 1,
    form: null,  // 尚未建立表單
  },
]

let formIdCounter = 1010

function generateFormId(): number {
  return ++formIdCounter
}

function generateFieldId(): string {
  return `f${Date.now()}-${Math.random().toString(36).slice(2, 6)}`
}

// ---------- Mock API 函式 ----------

/** Mock 範例資料所屬的廠商 ID，作為找不到對應資料時的保底來源 */
const FALLBACK_VENDOR_ID = 1

/** 深拷貝單一服務，避免呼叫端直接改動 Mock 內部狀態 */
function cloneService(s: VendorService, overrideVendorId?: number): VendorService {
  return {
    ...s,
    vendorId: overrideVendorId ?? s.vendorId,
    form: s.form
      ? {
          ...s.form,
          fields: s.form.fields.map((f) => ({
            ...f,
            options: f.options ? [...f.options] : undefined,
          })),
        }
      : null,
  }
}

/**
 * 取得該廠商旗下所有服務項目（含表單資料）
 *
 * 保底機制：若 Mock 中找不到該 vendorId 的資料（例如登入取得的
 * service_vendor_id 不是 1），改用 FALLBACK_VENDOR_ID 的範例資料並
 * 改寫 vendorId 為請求值，避免回傳空陣列導致整頁空白。
 */
export async function fetchVendorServices(vendorId: number): Promise<VendorService[]> {
  await delay(500)
  const owned = mockVendorServices.filter((s) => s.vendorId === vendorId)
  if (owned.length > 0) {
    return owned.map((s) => cloneService(s))
  }
  return mockVendorServices
    .filter((s) => s.vendorId === FALLBACK_VENDOR_ID)
    .map((s) => cloneService(s, vendorId))
}

/**
 * 依 serviceId 取得 Mock 服務，找不到時就地建立一筆，
 * 讓離線模式下的建立/更新操作不會拋錯中斷 UI。
 */
function findOrCreateMockService(serviceId: number): VendorService {
  const existing = mockVendorServices.find((s) => s.id === serviceId)
  if (existing) return existing

  const created: VendorService = {
    id: serviceId,
    name: `服務 #${serviceId}`,
    vendorId: FALLBACK_VENDOR_ID,
    form: null,
  }
  mockVendorServices.push(created)
  return created
}

/**
 * 建立新表單並綁定至指定服務
 */
export async function createServiceForm(
  serviceId: number,
  data: { title: string; description: string; fields: Omit<FormField, 'id'>[] }
): Promise<{ success: boolean; service: VendorService }> {
  await delay(600)
  const service = findOrCreateMockService(serviceId)

  const now = getNowString()
  service.form = {
    id: generateFormId(),
    title: data.title,
    description: data.description,
    fields: data.fields.map((f) => ({ ...f, id: generateFieldId() })),
    createdAt: now,
    updatedAt: now,
  }
  return { success: true, service: cloneService(service) }
}

/**
 * 更新現有表單
 *
 * 保底機制：若該服務在 Mock 中尚無表單（或 formId 不符，例如 formId
 * 來自真實 API），直接以傳入內容建立／覆寫，不拋錯。
 */
export async function updateServiceForm(
  serviceId: number,
  formId: number,
  data: { title: string; description: string; fields: Omit<FormField, 'id'>[] }
): Promise<{ success: boolean; service: VendorService }> {
  await delay(600)
  const service = findOrCreateMockService(serviceId)
  const previousFields = service.form?.fields ?? []

  service.form = {
    id: service.form?.id ?? formId,
    title: data.title,
    description: data.description,
    fields: data.fields.map((f, i) => ({
      ...f,
      id: previousFields[i]?.id ?? generateFieldId(),
    })),
    createdAt: service.form?.createdAt ?? getNowString(),
    updatedAt: getNowString(),
  }
  return { success: true, service: cloneService(service) }
}

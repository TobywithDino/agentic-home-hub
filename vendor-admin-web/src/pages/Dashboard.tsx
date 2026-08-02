import { useEffect, useState, useCallback } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  fetchDashboardStats,
  fetchOrderTrends,
  getDashboardAiAnalysis,
  regenerateDashboardAiAnalysis,
  SUMMARY_STATUS_LABELS,
  type DashboardStats,
  type OrderTrend,
  type AiAnalysis,
  type SummaryRefreshPhase,
} from '@/api'
import { useServiceContext } from '@/contexts/ServiceContext'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts'
import { FileText, ShoppingCart, DollarSign, Sparkles, RefreshCw } from 'lucide-react'

// Skeleton loader for AI card
function AiCardSkeleton() {
  return (
    <div className="animate-pulse space-y-4 p-6">
      <div className="h-4 bg-white/30 rounded w-1/3" />
      <div className="space-y-2">
        <div className="h-3 bg-white/20 rounded w-full" />
        <div className="h-3 bg-white/20 rounded w-5/6" />
        <div className="h-3 bg-white/20 rounded w-4/6" />
      </div>
      <div className="h-4 bg-white/30 rounded w-1/4 mt-4" />
      <div className="space-y-2">
        <div className="h-3 bg-white/20 rounded w-full" />
        <div className="h-3 bg-white/20 rounded w-3/4" />
      </div>
      <div className="h-4 bg-white/30 rounded w-1/4 mt-4" />
      <div className="h-6 bg-white/20 rounded w-full mt-2" />
    </div>
  )
}

export default function Dashboard() {
  const [stats, setStats] = useState<DashboardStats | null>(null)
  const [trends, setTrends] = useState<OrderTrend[]>([])
  const [loading, setLoading] = useState(true)

  // AI Insight state
  const [aiAnalysis, setAiAnalysis] = useState<AiAnalysis | null>(null)
  const [aiLoading, setAiLoading] = useState(true)
  /** 重新生成摘要的階段，用來顯示「AI 正在生成」而非只是轉圈 */
  const [aiPhase, setAiPhase] = useState<SummaryRefreshPhase | null>(null)

  // 服務清單用於把 service_breakdown 的 service_id 換成可讀名稱
  const { services } = useServiceContext()

  useEffect(() => {
    async function loadData() {
      const [statsData, trendsData, aiData] = await Promise.all([
        fetchDashboardStats(),
        fetchOrderTrends(),
        getDashboardAiAnalysis(),
      ])
      setStats(statsData)
      setTrends(trendsData)
      setAiAnalysis(aiData)
      setLoading(false)
      setAiLoading(false)
    }
    loadData()
  }, [])

  /**
   * 重新生成摘要
   *
   * 後端的 refresh 端點是非同步觸發（立即回 202），所以這裡要等 api 層
   * 輪詢到 generate_status 變成已完成／失敗才會拿到結果 ——
   * 期間保持 loading，避免先把舊摘要印出來讓人以為已經更新。
   */
  const handleRefreshAi = useCallback(async () => {
    setAiLoading(true)
    setAiPhase('triggering')
    try {
      const data = await regenerateDashboardAiAnalysis({ onPhase: setAiPhase })
      setAiAnalysis(data)
    } finally {
      setAiPhase(null)
      setAiLoading(false)
    }
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-slate-500">載入中...</p>
      </div>
    )
  }

  // 七天內每一天都是 0 → 區間內無訂單（趨勢資料本身有正常回傳）
  const hasNoTrendData = trends.length > 0 && trends.every((t) => t.orders === 0)
  const latestOrderLabel = stats?.latestOrderAt
    ? new Date(stats.latestOrderAt).toLocaleDateString('zh-TW')
    : ''

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-slate-900">戰情儀表板</h1>

      {/* AI Insight Card */}
      <div className="rounded-2xl bg-gradient-to-br from-indigo-600 via-purple-600 to-pink-500 p-[2px] shadow-lg shadow-purple-200/50">
        <div className="rounded-[14px] bg-gradient-to-br from-indigo-600/95 via-purple-600/95 to-pink-500/95 backdrop-blur">
          {/* Header */}
          <div className="flex items-center justify-between px-6 pt-5 pb-3">
            <div className="flex items-center gap-2 flex-wrap">
              <Sparkles className="h-5 w-5 text-amber-300 animate-pulse" />
              <h2 className="text-lg font-bold text-white">AI 智慧洞察</h2>

              {aiAnalysis && (
                <span className="text-xs text-white/60 ml-1">
                  {aiAnalysis.analyzedPeriod}
                </span>
              )}

              {/* 生成狀態 */}
              {aiAnalysis?.generateStatus && (
                <span
                  className={`text-[11px] px-2 py-0.5 rounded-full font-medium ${
                    aiAnalysis.generateStatus === '02'
                      ? 'bg-emerald-400/20 text-emerald-100'
                      : aiAnalysis.generateStatus === '03'
                        ? 'bg-rose-400/20 text-rose-100'
                        : 'bg-amber-300/20 text-amber-100'
                  }`}
                >
                  {SUMMARY_STATUS_LABELS[aiAnalysis.generateStatus]}
                </span>
              )}

              {/* 有新評價尚未納入摘要 */}
              {aiAnalysis?.isStale && (
                <span className="text-[11px] px-2 py-0.5 rounded-full bg-amber-300/20 text-amber-100 font-medium">
                  有新評價未納入
                </span>
              )}

              {/* 非 AI 摘要而是前端即時推導 */}
              {aiAnalysis?.source === 'derived' && (
                <span className="text-[11px] px-2 py-0.5 rounded-full bg-white/15 text-white/80">
                  即時推導（尚未生成 AI 摘要）
                </span>
              )}
            </div>
            <Button
              variant="outline"
              size="sm"
              className="border-white/30 bg-white/10 text-white hover:bg-white/20 hover:text-white text-xs gap-1.5"
              onClick={handleRefreshAi}
              disabled={aiLoading}
            >
              <RefreshCw className={`h-3.5 w-3.5 ${aiLoading ? 'animate-spin' : ''}`} />
              {aiPhase === 'triggering'
                ? '觸發中...'
                : aiPhase === 'generating'
                  ? 'AI 生成中...'
                  : '重新生成摘要'}
            </Button>
          </div>

          {/* 生成是非同步的，明確告知使用者正在等 AI 產出，而非畫面卡住 */}
          {aiPhase === 'generating' && (
            <div className="mx-6 mb-3 rounded-lg bg-white/10 border border-white/20 px-4 py-2.5">
              <p className="text-xs text-white/80">
                AI 正在分析最新評價，完成後畫面會自動更新。這段時間可以先做別的事，
                不需要停留在此頁重複點擊。
              </p>
            </div>
          )}

          {/* 生成失敗時顯示後端回傳的原因 */}
          {!aiLoading && aiAnalysis?.generateStatus === '03' && aiAnalysis.errorMessage && (
            <div className="mx-6 mb-3 rounded-lg bg-rose-500/20 border border-rose-300/30 px-4 py-2.5">
              <p className="text-xs text-rose-50">
                摘要生成失敗：{aiAnalysis.errorMessage}
              </p>
            </div>
          )}

          {aiLoading ? (
            <AiCardSkeleton />
          ) : aiAnalysis ? (
            <div className="px-6 pb-6 grid grid-cols-1 lg:grid-cols-3 gap-5">
              {/* Section 1: Key Takeaways */}
              <div className="bg-white/10 rounded-xl p-4 backdrop-blur-sm">
                <h3 className="text-sm font-semibold text-amber-200 mb-3 flex items-center gap-1.5">
                  <span>📌</span> 本週回饋摘要
                </h3>
                {/* 後端已改為單一敘述字串（summary_highlights.summary），
                    有值時以段落呈現；舊版陣列格式與本地推導仍走編號清單 */}
                {aiAnalysis.summaryText ? (
                  <p className="text-sm text-white/90 leading-relaxed whitespace-pre-line">
                    {aiAnalysis.summaryText}
                  </p>
                ) : aiAnalysis.summaryList.length > 0 ? (
                  <ul className="space-y-2">
                    {aiAnalysis.summaryList.map((item, idx) => (
                      <li key={idx} className="text-sm text-white/90 leading-relaxed flex gap-2">
                        <span className="text-amber-300 font-bold shrink-0">{idx + 1}.</span>
                        <span>{item}</span>
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p className="text-sm text-white/60">尚無摘要內容</p>
                )}
              </div>

              {/* Section 2: Suggestions */}
              <div className="bg-white/10 rounded-xl p-4 backdrop-blur-sm">
                <h3 className="text-sm font-semibold text-emerald-200 mb-3 flex items-center gap-1.5">
                  <span>💡</span> 廠商營運與服務優化建議
                </h3>
                <ul className="space-y-2">
                  {aiAnalysis.suggestions.map((item, idx) => (
                    <li key={idx} className="text-sm text-white/90 leading-relaxed flex gap-2">
                      <span className="text-emerald-300 font-bold shrink-0">•</span>
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>

              {/* Section 3: Sentiment */}
              <div className="bg-white/10 rounded-xl p-4 backdrop-blur-sm">
                <h3 className="text-sm font-semibold text-sky-200 mb-3 flex items-center gap-1.5">
                  <span>📊</span> 客戶情緒/滿意度標籤
                </h3>
                <div className="space-y-3 mt-4">
                  {/* Progress bar */}
                  <div className="flex h-5 w-full rounded-full overflow-hidden bg-white/10">
                    <div
                      className="bg-emerald-400 flex items-center justify-center text-[10px] font-bold text-emerald-900 transition-all duration-500"
                      style={{ width: `${aiAnalysis.sentimentScore.positive}%` }}
                    >
                      {aiAnalysis.sentimentScore.positive}%
                    </div>
                    <div
                      className="bg-amber-300 flex items-center justify-center text-[10px] font-bold text-amber-900 transition-all duration-500"
                      style={{ width: `${aiAnalysis.sentimentScore.neutral}%` }}
                    >
                      {aiAnalysis.sentimentScore.neutral}%
                    </div>
                    <div
                      className="bg-rose-400 flex items-center justify-center text-[10px] font-bold text-rose-900 transition-all duration-500"
                      style={{ width: `${aiAnalysis.sentimentScore.negative}%` }}
                    >
                      {aiAnalysis.sentimentScore.negative}%
                    </div>
                  </div>
                  {/* Legend：有原始筆數時一併顯示，百分比之外提供絕對數量 */}
                  <div className="flex items-center gap-4 text-xs text-white/80">
                    <span className="flex items-center gap-1.5">
                      <span className="inline-block w-2.5 h-2.5 rounded-full bg-emerald-400" />
                      正面
                      {aiAnalysis.sentimentCounts && (
                        <span className="text-white/60">
                          {aiAnalysis.sentimentCounts.positive} 筆
                        </span>
                      )}
                    </span>
                    <span className="flex items-center gap-1.5">
                      <span className="inline-block w-2.5 h-2.5 rounded-full bg-amber-300" />
                      中立
                      {aiAnalysis.sentimentCounts && (
                        <span className="text-white/60">
                          {aiAnalysis.sentimentCounts.neutral} 筆
                        </span>
                      )}
                    </span>
                    <span className="flex items-center gap-1.5">
                      <span className="inline-block w-2.5 h-2.5 rounded-full bg-rose-400" />
                      需改進
                      {aiAnalysis.sentimentCounts && (
                        <span className="text-white/60">
                          {aiAnalysis.sentimentCounts.negative} 筆
                        </span>
                      )}
                    </span>
                  </div>

                  {/* 摘要來源統計 */}
                  {(aiAnalysis.sourceReviewCount != null ||
                    aiAnalysis.sourceAvgRating != null) && (
                    <div className="flex items-center gap-4 pt-2 border-t border-white/10 text-xs text-white/70">
                      {aiAnalysis.sourceReviewCount != null && (
                        <span>
                          累計評價
                          <span className="ml-1 font-semibold text-white">
                            {aiAnalysis.sourceReviewCount}
                          </span>
                          筆
                        </span>
                      )}
                      {aiAnalysis.sourceAvgRating != null && (
                        <span>
                          平均
                          <span className="ml-1 font-semibold text-white">
                            {aiAnalysis.sourceAvgRating.toFixed(2)}
                          </span>
                          分
                        </span>
                      )}
                    </div>
                  )}

                </div>
              </div>
            </div>
          ) : (
            /* 摘要與原始評價都拿不到 → 留空並說明，不以離線分析資料充數 */
            <div className="px-6 pb-6">
              <p className="text-sm text-white/70">
                目前沒有可用的評價摘要，請確認後端服務是否正常，或等有新評價後再重新載入。
              </p>
            </div>
          )}
        </div>
      </div>

      {/* 各服務評價統計（來自 AI 摘要的 service_breakdown）*/}
      {(aiAnalysis?.serviceBreakdown?.length ?? 0) > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">各服務評價統計</CardTitle>
            <p className="text-xs text-slate-500 mt-1">
              橫跨名下所有服務項目的評價數與平均分
              {aiAnalysis?.generateTime &&
                `，摘要產生於 ${new Date(aiAnalysis.generateTime).toLocaleString('zh-TW')}`}
            </p>
          </CardHeader>
          <CardContent>
            <div className="grid gap-2">
              {aiAnalysis!.serviceBreakdown!.map((b) => {
                const name =
                  services.find((s) => s.id === b.serviceId)?.name ??
                  `服務 #${b.serviceId}`
                // 5 分制轉百分比寬度
                const barWidth = Math.max(0, Math.min(100, (b.avgRating / 5) * 100))
                return (
                  <div
                    key={b.serviceId}
                    className="flex items-center gap-3 rounded-lg border border-slate-200 px-3 py-2.5"
                  >
                    <span className="w-40 shrink-0 truncate text-sm font-medium text-slate-800" title={name}>
                      {name}
                    </span>
                    <div className="flex-1 h-2 rounded-full bg-slate-100 overflow-hidden">
                      <div
                        className={`h-full rounded-full transition-all ${
                          b.avgRating >= 4
                            ? 'bg-emerald-500'
                            : b.avgRating >= 3
                              ? 'bg-amber-400'
                              : 'bg-rose-500'
                        }`}
                        style={{ width: `${barWidth}%` }}
                      />
                    </div>
                    <span className="w-14 shrink-0 text-right text-sm font-semibold text-slate-900">
                      {b.avgRating.toFixed(1)}
                    </span>
                    <span className="w-16 shrink-0 text-right text-xs text-slate-500">
                      {b.reviewCount} 筆
                    </span>
                  </div>
                )
              })}
            </div>

            {aiAnalysis?.aiModel && (
              <p className="text-[11px] text-slate-400 mt-3">
                分析模型：{aiAnalysis.aiModel}
              </p>
            )}
          </CardContent>
        </Card>
      )}

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-slate-500">今日諮詢單</CardTitle>
            <FileText className="h-5 w-5 text-blue-500" />
          </CardHeader>
          <CardContent>
            {/* stats 為 null 代表載入失敗（非 0 筆），以 — 表示無資料 */}
            <div className="text-3xl font-bold">
              {stats ? stats.todayConsultations : '—'}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-slate-500">待處理訂單</CardTitle>
            <ShoppingCart className="h-5 w-5 text-amber-500" />
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{stats ? stats.pendingOrders : '—'}</div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-slate-500">本月服務收益</CardTitle>
            <DollarSign className="h-5 w-5 text-emerald-500" />
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">
              {stats ? `NT$ ${stats.monthlyRevenue.toLocaleString()}` : '—'}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Order Trends Chart */}
      <Card>
        <CardHeader>
          <CardTitle>近七天訂單趨勢</CardTitle>
          {/* 區間內完全沒有訂單時，明確說明原因並指出最近一筆的時間，
              避免讓人以為是抓不到資料 */}
          {hasNoTrendData && (
            <p className="text-xs text-slate-500 mt-1">
              近七天沒有新訂單
              {latestOrderLabel && `，最近一筆訂單為 ${latestOrderLabel}`}
            </p>
          )}
          {/* 空陣列代表趨勢資料載入失敗，與「七天都是 0」不同 */}
          {trends.length === 0 && (
            <p className="text-xs text-slate-500 mt-1">無法載入訂單趨勢，請稍後再試</p>
          )}
        </CardHeader>
        <CardContent>
          <div className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={trends} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="day" tick={{ fontSize: 12 }} />
                {/* 訂單數為整數，關閉小數刻度避免出現 0.5 這類無意義的格線 */}
                <YAxis tick={{ fontSize: 12 }} allowDecimals={false} />
                <Tooltip
                  contentStyle={{ borderRadius: '8px', border: '1px solid #e2e8f0' }}
                  labelStyle={{ fontWeight: 600 }}
                />
                <Line
                  type="monotone"
                  dataKey="orders"
                  name="訂單數"
                  stroke="#1e293b"
                  strokeWidth={2}
                  // 保留節點，資料只有單一天有值時仍看得到
                  dot={{ r: 3, fill: '#1e293b' }}
                  activeDot={{ r: 5 }}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

import { useEffect, useState, useCallback } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { fetchDashboardStats, fetchOrderTrends, getDashboardAiAnalysis, type DashboardStats, type OrderTrend, type AiAnalysis } from '@/api'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
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

  const handleRefreshAi = useCallback(async () => {
    setAiLoading(true)
    const data = await getDashboardAiAnalysis()
    setAiAnalysis(data)
    setAiLoading(false)
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-slate-500">載入中...</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-slate-900">戰情儀表板</h1>

      {/* AI Insight Card */}
      <div className="rounded-2xl bg-gradient-to-br from-indigo-600 via-purple-600 to-pink-500 p-[2px] shadow-lg shadow-purple-200/50">
        <div className="rounded-[14px] bg-gradient-to-br from-indigo-600/95 via-purple-600/95 to-pink-500/95 backdrop-blur">
          {/* Header */}
          <div className="flex items-center justify-between px-6 pt-5 pb-3">
            <div className="flex items-center gap-2">
              <Sparkles className="h-5 w-5 text-amber-300 animate-pulse" />
              <h2 className="text-lg font-bold text-white">AI 智慧洞察</h2>
              {aiAnalysis && (
                <span className="text-xs text-white/60 ml-2">分析期間：{aiAnalysis.analyzedPeriod}</span>
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
              重新用 AI 分析最新回饋
            </Button>
          </div>

          {aiLoading ? (
            <AiCardSkeleton />
          ) : aiAnalysis ? (
            <div className="px-6 pb-6 grid grid-cols-1 lg:grid-cols-3 gap-5">
              {/* Section 1: Key Takeaways */}
              <div className="bg-white/10 rounded-xl p-4 backdrop-blur-sm">
                <h3 className="text-sm font-semibold text-amber-200 mb-3 flex items-center gap-1.5">
                  <span>📌</span> 本週住戶需求 AI 摘要
                </h3>
                <ul className="space-y-2">
                  {aiAnalysis.summaryList.map((item, idx) => (
                    <li key={idx} className="text-sm text-white/90 leading-relaxed flex gap-2">
                      <span className="text-amber-300 font-bold shrink-0">{idx + 1}.</span>
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
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
                  {/* Legend */}
                  <div className="flex items-center gap-4 text-xs text-white/80">
                    <span className="flex items-center gap-1.5">
                      <span className="inline-block w-2.5 h-2.5 rounded-full bg-emerald-400" />
                      正面
                    </span>
                    <span className="flex items-center gap-1.5">
                      <span className="inline-block w-2.5 h-2.5 rounded-full bg-amber-300" />
                      中立
                    </span>
                    <span className="flex items-center gap-1.5">
                      <span className="inline-block w-2.5 h-2.5 rounded-full bg-rose-400" />
                      需改進
                    </span>
                  </div>
                  {/* Summary text */}
                  <p className="text-xs text-white/60 mt-2">
                    基於近 7 天共 10 筆客戶回饋分析，整體滿意度良好，少數改進項目集中於服務態度與報價透明度。
                  </p>
                </div>
              </div>
            </div>
          ) : null}
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-slate-500">今日諮詢單</CardTitle>
            <FileText className="h-5 w-5 text-blue-500" />
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{stats?.todayConsultations}</div>
            <p className="text-xs text-slate-500 mt-1">較昨日 +2</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-slate-500">待處理訂單</CardTitle>
            <ShoppingCart className="h-5 w-5 text-amber-500" />
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">{stats?.pendingOrders}</div>
            <p className="text-xs text-slate-500 mt-1">需盡快處理</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-slate-500">本月服務收益</CardTitle>
            <DollarSign className="h-5 w-5 text-emerald-500" />
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold">
              NT$ {stats?.monthlyRevenue.toLocaleString()}
            </div>
            <p className="text-xs text-slate-500 mt-1">較上月 +12%</p>
          </CardContent>
        </Card>
      </div>

      {/* Order Trends Chart */}
      <Card>
        <CardHeader>
          <CardTitle>近七天訂單趨勢</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={trends} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="day" tick={{ fontSize: 12 }} />
                <YAxis tick={{ fontSize: 12 }} />
                <Tooltip
                  contentStyle={{ borderRadius: '8px', border: '1px solid #e2e8f0' }}
                  labelStyle={{ fontWeight: 600 }}
                />
                <Bar dataKey="orders" fill="#1e293b" radius={[4, 4, 0, 0]} name="訂單數" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

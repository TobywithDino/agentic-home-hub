import { useEffect, useMemo, useState } from 'react'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Modal } from '@/components/ui/modal'
import { fetchFeedbacks, acceptFeedback, declineFeedback, type FormFeedback, type FeedbackStatus } from '@/api'
import { ArrowUpDown, CheckCircle2, XCircle } from 'lucide-react'

function getStatusVariant(status: FeedbackStatus) {
  switch (status) {
    case '待處理': return 'warning' as const
    case '已接單': return 'success' as const
    case '已拒絕': return 'destructive' as const
  }
}

type SortKey = 'id' | 'contactName' | 'serviceType' | 'preferredContactTime' | 'status'
type SortDir = 'asc' | 'desc'

const STATUS_OPTIONS: FeedbackStatus[] = ['待處理', '已接單', '已拒絕']
const DECLINE_REASONS = ['行程已滿', '超出服務區域', '服務項目不符', '其他原因']

export default function Consultations() {
  const [feedbacks, setFeedbacks] = useState<FormFeedback[]>([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<FormFeedback | null>(null)
  const [processing, setProcessing] = useState(false)

  // Decline dialog state
  const [showDeclineDialog, setShowDeclineDialog] = useState(false)
  const [declineReason, setDeclineReason] = useState<string>(DECLINE_REASONS[0])

  // Sorting
  const [sortKey, setSortKey] = useState<SortKey>('id')
  const [sortDir, setSortDir] = useState<SortDir>('desc')

  // Filtering
  const [statusFilter, setStatusFilter] = useState<FeedbackStatus | '全部'>('全部')

  useEffect(() => {
    async function loadData() {
      const data = await fetchFeedbacks()
      setFeedbacks(data)
      setLoading(false)
    }
    loadData()
  }, [])

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
    } else {
      setSortKey(key)
      setSortDir('asc')
    }
  }

  const sortedAndFiltered = useMemo(() => {
    let data = [...feedbacks]
    if (statusFilter !== '全部') {
      data = data.filter((f) => f.status === statusFilter)
    }
    data.sort((a, b) => {
      const aVal = a[sortKey]
      const bVal = b[sortKey]
      const cmp = aVal < bVal ? -1 : aVal > bVal ? 1 : 0
      return sortDir === 'asc' ? cmp : -cmp
    })
    return data
  }, [feedbacks, sortKey, sortDir, statusFilter])

  // ─── Accept ───
  const handleAccept = async () => {
    if (!selected) return
    setProcessing(true)
    try {
      const result = await acceptFeedback(selected.id)
      setFeedbacks((prev) =>
        prev.map((f) => (f.id === result.feedback.id ? result.feedback : f))
      )
      setSelected(result.feedback)
    } catch {
      // demo: silently ignore
    } finally {
      setProcessing(false)
    }
  }

  // ─── Decline ───
  const handleDeclineConfirm = async () => {
    if (!selected) return
    setProcessing(true)
    try {
      const result = await declineFeedback(selected.id, declineReason)
      setFeedbacks((prev) =>
        prev.map((f) => (f.id === result.feedback.id ? result.feedback : f))
      )
      setSelected(result.feedback)
      setShowDeclineDialog(false)
    } catch {
      // demo: silently ignore
    } finally {
      setProcessing(false)
    }
  }

  const SortHeader = ({ label, field }: { label: string; field: SortKey }) => (
    <button
      className="flex items-center gap-1 hover:text-slate-900 transition-colors"
      onClick={() => handleSort(field)}
    >
      {label}
      <ArrowUpDown className={`h-3.5 w-3.5 ${sortKey === field ? 'text-slate-900' : 'text-slate-400'}`} />
    </button>
  )

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-slate-500">載入中...</p>
      </div>
    )
  }

  const isProcessed = selected?.status === '已接單' || selected?.status === '已拒絕'

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-slate-900">諮詢單管理</h1>

      {/* Filter Bar */}
      <div className="flex items-center gap-2">
        <span className="text-sm text-slate-500">狀態篩選：</span>
        {(['全部', ...STATUS_OPTIONS] as const).map((opt) => (
          <Button
            key={opt}
            variant={statusFilter === opt ? 'default' : 'outline'}
            size="sm"
            onClick={() => setStatusFilter(opt)}
          >
            {opt}
          </Button>
        ))}
      </div>

      <div className="rounded-xl border border-slate-200 bg-white shadow">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead><SortHeader label="諮詢單號" field="id" /></TableHead>
              <TableHead><SortHeader label="客戶姓名" field="contactName" /></TableHead>
              <TableHead><SortHeader label="服務類型" field="serviceType" /></TableHead>
              <TableHead><SortHeader label="預期聯絡時間" field="preferredContactTime" /></TableHead>
              <TableHead><SortHeader label="處理狀態" field="status" /></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {sortedAndFiltered.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5} className="text-center text-slate-400 py-8">
                  無符合條件的諮詢單
                </TableCell>
              </TableRow>
            ) : (
              sortedAndFiltered.map((item) => (
                <TableRow
                  key={item.id}
                  className="cursor-pointer"
                  onClick={() => setSelected(item)}
                >
                  <TableCell className="font-mono text-sm">{item.id}</TableCell>
                  <TableCell>{item.contactName}</TableCell>
                  <TableCell>{item.serviceType}</TableCell>
                  <TableCell className="text-sm text-slate-600">{item.preferredContactTime}</TableCell>
                  <TableCell>
                    <Badge variant={getStatusVariant(item.status)}>{item.status}</Badge>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>

      {/* Detail Modal */}
      <Modal
        open={!!selected && !showDeclineDialog}
        onClose={() => setSelected(null)}
        title="諮詢單詳細資訊"
        className="max-w-2xl"
      >
        {selected && (
          <div className="space-y-4">
            {/* Detail Fields */}
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-slate-500">諮詢單號</span>
                <p className="font-medium font-mono">{selected.id}</p>
              </div>
              <div>
                <span className="text-slate-500">處理狀態</span>
                <p><Badge variant={getStatusVariant(selected.status)}>{selected.status}</Badge></p>
              </div>
              <div>
                <span className="text-slate-500">客戶姓名</span>
                <p className="font-medium">{selected.contactName}</p>
              </div>
              <div>
                <span className="text-slate-500">電話</span>
                <p className="font-medium">{selected.phone}</p>
              </div>
              <div>
                <span className="text-slate-500">Email</span>
                <p className="font-medium">{selected.email}</p>
              </div>
              <div>
                <span className="text-slate-500">服務類型</span>
                <p className="font-medium">{selected.serviceType}</p>
              </div>
              <div>
                <span className="text-slate-500">預期聯絡時間</span>
                <p className="font-medium">{selected.preferredContactTime}</p>
              </div>
              <div>
                <span className="text-slate-500">建立時間</span>
                <p className="font-medium">{selected.createdAt}</p>
              </div>
            </div>

            <div>
              <span className="text-sm text-slate-500">服務地址</span>
              <p className="text-sm mt-1 p-3 bg-slate-50 rounded-lg">{selected.address}</p>
            </div>

            <div>
              <span className="text-sm text-slate-500">選擇的選項</span>
              <div className="flex flex-wrap gap-2 mt-1">
                {selected.selectedOptions.map((opt) => (
                  <Badge key={opt} variant="secondary">{opt}</Badge>
                ))}
              </div>
            </div>

            <div>
              <span className="text-sm text-slate-500">特殊需求</span>
              <p className="text-sm mt-1 p-3 bg-slate-50 rounded-lg">{selected.specialRequirements}</p>
            </div>

            <div>
              <span className="text-sm text-slate-500">客戶描述</span>
              <p className="text-sm mt-1 p-3 bg-slate-50 rounded-lg leading-relaxed">
                {selected.content}
              </p>
            </div>

            {/* Decline Reason (if already declined) */}
            {selected.status === '已拒絕' && selected.declineReason && (
              <div>
                <span className="text-sm text-slate-500">婉拒原因</span>
                <p className="text-sm mt-1 p-3 bg-red-50 text-red-700 rounded-lg">{selected.declineReason}</p>
              </div>
            )}

            {/* Action Buttons */}
            <div className="flex justify-end gap-3 pt-4 border-t">
              {isProcessed ? (
                <p className="text-sm text-slate-400 italic">此諮詢單已處理完成</p>
              ) : (
                <>
                  <Button
                    variant="outline"
                    className="text-red-600 border-red-200 hover:bg-red-50"
                    onClick={() => setShowDeclineDialog(true)}
                    disabled={processing}
                  >
                    <XCircle className="h-4 w-4 mr-1.5" />
                    婉拒諮詢
                  </Button>
                  <Button onClick={handleAccept} disabled={processing}>
                    <CheckCircle2 className="h-4 w-4 mr-1.5" />
                    {processing ? '處理中...' : '確認接單'}
                  </Button>
                </>
              )}
            </div>
          </div>
        )}
      </Modal>

      {/* Decline Confirmation Dialog */}
      <Modal
        open={showDeclineDialog}
        onClose={() => setShowDeclineDialog(false)}
        title="婉拒諮詢確認"
      >
        <div className="space-y-4">
          <p className="text-sm text-slate-600">
            確定要婉拒 <span className="font-semibold">{selected?.contactName}</span> 的諮詢嗎？請選擇婉拒原因：
          </p>

          <div className="space-y-2">
            {DECLINE_REASONS.map((reason) => (
              <label key={reason} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="radio"
                  name="decline-reason"
                  value={reason}
                  checked={declineReason === reason}
                  onChange={() => setDeclineReason(reason)}
                  className="h-4 w-4 text-slate-900"
                />
                <span className="text-sm">{reason}</span>
              </label>
            ))}
          </div>

          <div className="flex justify-end gap-3 pt-2">
            <Button variant="outline" onClick={() => setShowDeclineDialog(false)} disabled={processing}>
              取消
            </Button>
            <Button
              variant="destructive"
              onClick={handleDeclineConfirm}
              disabled={processing}
            >
              {processing ? '處理中...' : '確認婉拒'}
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}

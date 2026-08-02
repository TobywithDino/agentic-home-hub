import { useEffect, useMemo, useState } from 'react'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Modal } from '@/components/ui/modal'
import {
  fetchFeedbacks,
  acceptFeedback,
  declineFeedback,
  type FormFeedback,
  type FeedbackStatus,
} from '@/api'
import { useServiceContext } from '@/contexts/ServiceContext'
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
  const [declineError, setDeclineError] = useState('')

  // Accept dialog state：接單可輸入估價金額
  const [showAcceptDialog, setShowAcceptDialog] = useState(false)
  const [quotedAmount, setQuotedAmount] = useState('')
  const [acceptError, setAcceptError] = useState('')

  // Sorting
  const [sortKey, setSortKey] = useState<SortKey>('id')
  const [sortDir, setSortDir] = useState<SortDir>('desc')

  // Filtering
  const [statusFilter, setStatusFilter] = useState<FeedbackStatus | '全部'>('全部')

  // 跟隨側邊欄的全域服務選取
  const {
    selectedService,
    selectedServiceId,
    isAllServices,
    loading: servicesLoading,
  } = useServiceContext()

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
    // 跟隨全域選取；選「所有服務」時不做篩選
    if (typeof selectedServiceId === 'number') {
      data = data.filter((f) => f.serviceId === selectedServiceId)
    }
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
  }, [feedbacks, sortKey, sortDir, statusFilter, selectedServiceId])

  // ─── Accept ───

  /** 開啟接單確認 Modal（可輸入估價金額）*/
  const openAcceptDialog = () => {
    setQuotedAmount('')
    setAcceptError('')
    setShowAcceptDialog(true)
  }

  // 估價金額為選填：留空視為 0（待報價）。
  // 只有「填了但格式不對」才算無效，避免出現沒有原因的灰色按鈕。
  const amountEmpty = quotedAmount.trim() === ''
  const parsedAmount = amountEmpty ? 0 : Number(quotedAmount)
  const amountInvalid =
    !amountEmpty && (!Number.isFinite(parsedAmount) || parsedAmount < 0)

  const handleAcceptConfirm = async () => {
    if (!selected || amountInvalid) return
    setProcessing(true)
    try {
      const result = await acceptFeedback(selected.id, parsedAmount)
      setFeedbacks((prev) =>
        prev.map((f) => (f.id === result.feedback.id ? result.feedback : f))
      )
      setSelected(result.feedback)
      setShowAcceptDialog(false)
      setAcceptError('')
    } catch (err) {
      // 保留 Modal 讓使用者重試，並在 Modal 內顯示原因
      console.warn('[Feedbacks] 接單失敗:', err)
      setAcceptError('接單失敗，請稍後再試。若持續失敗請聯繫系統管理員。')
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
      setDeclineError('')
    } catch (err) {
      console.warn('[Feedbacks] 婉拒失敗:', err)
      setDeclineError('婉拒失敗，狀態未寫入後端，請稍後再試。')
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

  if (loading || servicesLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-slate-500">載入中...</p>
      </div>
    )
  }

  const isProcessed = selected?.status === '已接單' || selected?.status === '已拒絕'

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-900">諮詢單管理</h1>
        <p className="text-sm text-slate-500 mt-1">
          {isAllServices ? (
            <>
              目前顯示<span className="font-medium text-slate-700">所有服務</span>的諮詢單
            </>
          ) : selectedService ? (
            <>
              目前服務：
              <span className="font-medium text-slate-700">{selectedService.name}</span>
              <span className="text-slate-400">（可於左側切換）</span>
            </>
          ) : (
            '尚無服務項目，請先至「服務管理總覽」新增'
          )}
        </p>
      </div>

      {/* Filter Bar */}
      <div className="flex items-center gap-2 flex-wrap">
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
                <TableCell colSpan={5} className="text-center text-slate-400 py-10">
                  {feedbacks.length === 0
                    ? '目前沒有諮詢單'
                    : '沒有符合目前篩選條件的諮詢單'}
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
        open={!!selected && !showDeclineDialog && !showAcceptDialog}
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
                    onClick={() => {
                      setDeclineError('')
                      setShowDeclineDialog(true)
                    }}
                    disabled={processing}
                  >
                    <XCircle className="h-4 w-4 mr-1.5" />
                    婉拒諮詢
                  </Button>
                  <Button onClick={openAcceptDialog} disabled={processing}>
                    <CheckCircle2 className="h-4 w-4 mr-1.5" />
                    確認接單
                  </Button>
                </>
              )}
            </div>
          </div>
        )}
      </Modal>

      {/* Accept Confirmation Dialog：輸入估價金額後才建立訂單 */}
      <Modal
        open={showAcceptDialog}
        onClose={() => {
          if (!processing) setShowAcceptDialog(false)
        }}
        title="確認接單並建立訂單"
      >
        <div className="space-y-4">
          <p className="text-sm text-slate-600">
            將受理 <span className="font-semibold">{selected?.contactName}</span> 的諮詢並
            建立訂單。請輸入這筆服務的估價金額：
          </p>

          <div>
            <label
              htmlFor="quoted-amount"
              className="block text-sm font-medium text-slate-700 mb-1"
            >
              估價金額（NTD）
              <span className="ml-1 text-xs font-normal text-slate-400">選填</span>
            </label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-slate-400">
                NT$
              </span>
              <input
                id="quoted-amount"
                type="number"
                min={0}
                step={1}
                inputMode="numeric"
                value={quotedAmount}
                onChange={(e) => setQuotedAmount(e.target.value)}
                placeholder="0"
                className="w-full rounded-md border border-slate-300 pl-12 pr-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-slate-900 focus:border-transparent"
              />
            </div>
            {amountInvalid && (
              <p className="text-xs text-red-600 mt-1">請輸入 0 或以上的數字</p>
            )}
            <p className="text-xs text-slate-400 mt-1.5 leading-relaxed">
              {amountEmpty
                ? '留空代表尚未報價，訂單金額會記為 0，之後可於訂單管理調整。'
                : '此金額會寫入訂單的原始金額與實付金額，後續可於訂單管理調整。'}
              <br />
              顧客當初填寫的諮詢內容會一併存入訂單，供出工時查閱。
            </p>
          </div>

          {acceptError && (
            <p className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-md px-3 py-2">
              {acceptError}
            </p>
          )}

          <div className="flex justify-end gap-3 pt-2 border-t border-slate-100">
            <Button
              variant="outline"
              onClick={() => setShowAcceptDialog(false)}
              disabled={processing}
            >
              取消
            </Button>
            <Button onClick={handleAcceptConfirm} disabled={processing || amountInvalid}>
              {processing ? '建立中...' : amountEmpty ? '接單（暫不報價）' : '確認接單'}
            </Button>
          </div>
        </div>
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

          {declineError && (
            <p className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-md px-3 py-2">
              {declineError}
            </p>
          )}

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

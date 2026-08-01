import { useEffect, useMemo, useState } from 'react'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Modal } from '@/components/ui/modal'
import { fetchOrders, updateOrderStatus, ORDER_STATUS_MAP, type OrderRecord, type OrderStatusCode } from '@/api'
import { ArrowUpDown } from 'lucide-react'

function getStatusVariant(status: OrderStatusCode) {
  switch (status) {
    case '11': return 'warning' as const
    case '12': return 'info' as const
    case '04': return 'info' as const
    case '80': return 'success' as const
    case '90': return 'destructive' as const
  }
}

const ALL_STATUSES: OrderStatusCode[] = ['11', '12', '04', '80', '90']

type SortKey = 'id' | 'customerName' | 'serviceName' | 'finalAmount' | 'serviceTime' | 'orderStatus'
type SortDir = 'asc' | 'desc'

export default function Orders() {
  const [orders, setOrders] = useState<OrderRecord[]>([])
  const [loading, setLoading] = useState(true)

  // Sorting
  const [sortKey, setSortKey] = useState<SortKey>('id')
  const [sortDir, setSortDir] = useState<SortDir>('desc')

  // Filtering
  const [statusFilter, setStatusFilter] = useState<OrderStatusCode | '全部'>('全部')

  // Confirmation modal for status change
  const [confirmTarget, setConfirmTarget] = useState<{ order: OrderRecord; newStatus: OrderStatusCode } | null>(null)
  const [updating, setUpdating] = useState(false)

  // Detail modal
  const [detailOrder, setDetailOrder] = useState<OrderRecord | null>(null)
  const [detailNewStatus, setDetailNewStatus] = useState<OrderStatusCode | ''>('')

  useEffect(() => {
    async function loadData() {
      const data = await fetchOrders()
      setOrders(data)
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
    let data = [...orders]

    if (statusFilter !== '全部') {
      data = data.filter((o) => o.orderStatus === statusFilter)
    }

    data.sort((a, b) => {
      const aVal = a[sortKey]
      const bVal = b[sortKey]
      const cmp = aVal < bVal ? -1 : aVal > bVal ? 1 : 0
      return sortDir === 'asc' ? cmp : -cmp
    })

    return data
  }, [orders, sortKey, sortDir, statusFilter])

  // Handle inline select change in table -> open confirmation
  const handleSelectChange = (order: OrderRecord, newStatus: OrderStatusCode) => {
    if (newStatus === order.orderStatus) return
    setConfirmTarget({ order, newStatus })
  }

  // Confirm status update
  const handleConfirmUpdate = async () => {
    if (!confirmTarget) return
    setUpdating(true)
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const recordId = (confirmTarget.order as any)._recordId as number | undefined
      const result = await updateOrderStatus(confirmTarget.order.id, confirmTarget.newStatus, recordId)
      setOrders((prev) =>
        prev.map((o) => (o.id === result.order.id ? result.order : o))
      )
      // Also update detail modal if same order is open
      if (detailOrder && detailOrder.id === result.order.id) {
        setDetailOrder(result.order)
        setDetailNewStatus('')
      }
      setConfirmTarget(null)
    } catch {
      // silent in demo
    } finally {
      setUpdating(false)
    }
  }

  // Open detail modal
  const openDetail = (order: OrderRecord) => {
    setDetailOrder(order)
    setDetailNewStatus('')
  }

  // Handle status save from detail modal
  const handleDetailStatusSave = () => {
    if (!detailOrder || !detailNewStatus || detailNewStatus === detailOrder.orderStatus) return
    setConfirmTarget({ order: detailOrder, newStatus: detailNewStatus })
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

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-slate-900">訂單管理</h1>

      {/* Filter Bar */}
      <div className="flex items-center gap-2 flex-wrap">
        <span className="text-sm text-slate-500">狀態篩選：</span>
        <Button
          variant={statusFilter === '全部' ? 'default' : 'outline'}
          size="sm"
          onClick={() => setStatusFilter('全部')}
        >
          全部
        </Button>
        {ALL_STATUSES.map((code) => (
          <Button
            key={code}
            variant={statusFilter === code ? 'default' : 'outline'}
            size="sm"
            onClick={() => setStatusFilter(code)}
          >
            {ORDER_STATUS_MAP[code]}
          </Button>
        ))}
      </div>

      <div className="rounded-xl border border-slate-200 bg-white shadow">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead><SortHeader label="訂單編號" field="id" /></TableHead>
              <TableHead><SortHeader label="客戶姓名" field="customerName" /></TableHead>
              <TableHead><SortHeader label="服務項目" field="serviceName" /></TableHead>
              <TableHead><SortHeader label="實付金額" field="finalAmount" /></TableHead>
              <TableHead><SortHeader label="預約服務時間" field="serviceTime" /></TableHead>
              <TableHead><SortHeader label="訂單狀態" field="orderStatus" /></TableHead>
              <TableHead className="text-center">切換狀態</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {sortedAndFiltered.length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} className="text-center text-slate-400 py-8">
                  無符合條件的訂單
                </TableCell>
              </TableRow>
            ) : (
              sortedAndFiltered.map((order) => (
                <TableRow
                  key={order.id}
                  className="cursor-pointer hover:bg-slate-50"
                  onClick={() => openDetail(order)}
                >
                  <TableCell className="font-mono text-sm">{order.id}</TableCell>
                  <TableCell>{order.customerName}</TableCell>
                  <TableCell>{order.serviceName}</TableCell>
                  <TableCell>NT$ {order.finalAmount.toLocaleString()}</TableCell>
                  <TableCell className="text-sm">{order.serviceTime}</TableCell>
                  <TableCell>
                    <Badge variant={getStatusVariant(order.orderStatus)}>
                      {ORDER_STATUS_MAP[order.orderStatus]}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-center" onClick={(e) => e.stopPropagation()}>
                    <select
                      className="rounded-md border border-slate-300 bg-white px-2 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                      value={order.orderStatus}
                      onChange={(e) => handleSelectChange(order, e.target.value as OrderStatusCode)}
                    >
                      {ALL_STATUSES.map((code) => (
                        <option key={code} value={code}>
                          {ORDER_STATUS_MAP[code]}
                        </option>
                      ))}
                    </select>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>

      {/* Confirmation Modal */}
      <Modal
        open={!!confirmTarget}
        onClose={() => setConfirmTarget(null)}
        title="確認變更訂單狀態"
      >
        {confirmTarget && (
          <div className="space-y-4">
            <p className="text-sm text-slate-600">
              確定要將訂單 <span className="font-mono font-semibold">{confirmTarget.order.id}</span> 的狀態變更為
              {' '}
              <Badge variant={getStatusVariant(confirmTarget.newStatus)}>
                {ORDER_STATUS_MAP[confirmTarget.newStatus]}
              </Badge>
              {' '}嗎？
            </p>
            <div className="flex justify-end gap-3 pt-2">
              <Button variant="outline" onClick={() => setConfirmTarget(null)} disabled={updating}>
                取消
              </Button>
              <Button onClick={handleConfirmUpdate} disabled={updating}>
                {updating ? '更新中...' : '確認變更'}
              </Button>
            </div>
          </div>
        )}
      </Modal>

      {/* Order Detail Modal */}
      <Modal
        open={!!detailOrder}
        onClose={() => setDetailOrder(null)}
        title="訂單詳細資訊"
      >
        {detailOrder && (
          <div className="space-y-5">
            {/* Basic Info */}
            <section className="space-y-2">
              <h3 className="text-sm font-semibold text-slate-700 border-b border-slate-200 pb-1">基本與金額資訊</h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
                <div>
                  <span className="text-slate-500">訂單編號：</span>
                  <span className="font-mono font-medium">{detailOrder.id}</span>
                </div>
                <div>
                  <span className="text-slate-500">客戶姓名：</span>
                  <span className="font-medium">{detailOrder.customerName}</span>
                </div>
                <div>
                  <span className="text-slate-500">原始金額：</span>
                  <span className="font-medium">NT$ {detailOrder.originalAmount.toLocaleString()}</span>
                </div>
                <div>
                  <span className="text-slate-500">實付金額：</span>
                  <span className="font-medium text-blue-700">NT$ {detailOrder.finalAmount.toLocaleString()}</span>
                </div>
                <div>
                  <span className="text-slate-500">目前狀態：</span>
                  <Badge variant={getStatusVariant(detailOrder.orderStatus)}>
                    {ORDER_STATUS_MAP[detailOrder.orderStatus]}
                  </Badge>
                </div>
              </div>
            </section>

            {/* Time & Location */}
            <section className="space-y-2">
              <h3 className="text-sm font-semibold text-slate-700 border-b border-slate-200 pb-1">履約時間與地點</h3>
              <div className="grid grid-cols-1 gap-2 text-sm">
                <div>
                  <span className="text-slate-500">預約服務時間：</span>
                  <span className="font-medium">{detailOrder.serviceTime}</span>
                </div>
                <div>
                  <span className="text-slate-500">聯絡地址：</span>
                  <span className="font-medium">{detailOrder.address}</span>
                </div>
                <div>
                  <span className="text-slate-500">聯絡電話：</span>
                  <span className="font-medium">{detailOrder.phone}</span>
                </div>
              </div>
            </section>

            {/* Order Items */}
            <section className="space-y-2">
              <h3 className="text-sm font-semibold text-slate-700 border-b border-slate-200 pb-1">服務項目明細</h3>
              <div className="rounded-md border border-slate-200 overflow-hidden">
                <table className="w-full text-sm">
                  <thead className="bg-slate-50">
                    <tr>
                      <th className="text-left px-3 py-2 font-medium text-slate-600">項目</th>
                      <th className="text-center px-3 py-2 font-medium text-slate-600">數量</th>
                    </tr>
                  </thead>
                  <tbody>
                    {detailOrder.orderItems.map((item, idx) => (
                      <tr key={idx} className="border-t border-slate-100">
                        <td className="px-3 py-2">{item.name}</td>
                        <td className="px-3 py-2 text-center">{item.quantity}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>

            {/* Status Switch */}
            <section className="space-y-3 pt-2 border-t border-slate-200">
              <h3 className="text-sm font-semibold text-slate-700">狀態切換</h3>
              <div className="flex items-center gap-3">
                <select
                  className="flex-1 rounded-md border border-slate-300 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  value={detailNewStatus || detailOrder.orderStatus}
                  onChange={(e) => setDetailNewStatus(e.target.value as OrderStatusCode)}
                >
                  {ALL_STATUSES.map((code) => (
                    <option key={code} value={code}>
                      {ORDER_STATUS_MAP[code]}
                    </option>
                  ))}
                </select>
                <Button
                  size="sm"
                  disabled={!detailNewStatus || detailNewStatus === detailOrder.orderStatus}
                  onClick={handleDetailStatusSave}
                >
                  儲存狀態
                </Button>
              </div>
            </section>
          </div>
        )}
      </Modal>
    </div>
  )
}

import { useCallback, useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Toast } from '@/components/ui/toast'
import { Loader2, Save } from 'lucide-react'
import {
  getServiceLabels,
  updateServiceLabels,
  SERVICE_TYPE_LABELS,
  type ServiceLabel,
} from '@/api'
import { useServiceContext } from '@/contexts/ServiceContext'

/**
 * 服務標籤設定（單一服務層）
 *
 * 直接對接 GET / PUT /merchant-api/services/{selectedServiceId}/labels。
 * 該端點同時回傳完整標籤字典與此服務的勾選狀態，故不需額外的字典端點。
 */
export default function ServiceLabels() {
  const {
    services,
    selectedService,
    setSelectedServiceId,
    loading: servicesLoading,
  } = useServiceContext()

  const [allLabels, setAllLabels] = useState<ServiceLabel[]>([])
  const [selectedIds, setSelectedIds] = useState<number[]>([])
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)

  const [toast, setToast] = useState({
    visible: false,
    message: '',
    variant: 'success' as 'success' | 'error',
  })
  const showToast = (message: string, variant: 'success' | 'error' = 'success') =>
    setToast({ visible: true, message, variant })
  const handleToastClose = useCallback(
    () => setToast((p) => ({ ...p, visible: false })),
    []
  )

  const serviceId = selectedService?.id ?? null
  const serviceType = selectedService?.type

  // 切換服務時重新載入該服務的標籤
  useEffect(() => {
    if (serviceId == null) return
    let cancelled = false
    setLoading(true)
    getServiceLabels(serviceId, serviceType)
      .then(({ allLabels: dict, selectedIds: ids }) => {
        if (cancelled) return
        setAllLabels(dict)
        setSelectedIds(ids)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [serviceId, serviceType])

  const toggle = (labelId: number) => {
    setSelectedIds((prev) =>
      prev.includes(labelId) ? prev.filter((id) => id !== labelId) : [...prev, labelId]
    )
  }

  const handleSave = async () => {
    if (serviceId == null) return
    setSaving(true)
    try {
      const result = await updateServiceLabels(serviceId, selectedIds)
      setSelectedIds(result.selectedIds)
      if (result.allLabels.length > 0) setAllLabels(result.allLabels)
      showToast('服務標籤已儲存')
    } catch {
      showToast('標籤儲存失敗，請重試', 'error')
    } finally {
      setSaving(false)
    }
  }

  if (servicesLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-slate-500">載入中...</p>
      </div>
    )
  }

  // 選「所有服務」時無法設定（標籤以單一服務為單位），提供快速挑選
  if (!selectedService) {
    return (
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-slate-900">服務標籤設定</h1>
        <Card>
          <CardContent className="py-14 text-center">
            {services.length === 0 ? (
              <>
                <p className="text-slate-500 text-sm font-medium">尚無服務項目</p>
                <p className="text-slate-400 text-xs mt-1">
                  請先至「服務管理總覽」新增服務項目，再回此頁設定標籤
                </p>
              </>
            ) : (
              <>
                <p className="text-slate-500 text-sm font-medium">請選擇單一服務</p>
                <p className="text-slate-400 text-xs mt-1">
                  標籤以服務為單位設定，無法一次設定所有服務。請選擇要設定的服務：
                </p>
                <div className="flex flex-wrap justify-center gap-2 mt-5">
                  {services.map((s) => (
                    <Button
                      key={s.id}
                      size="sm"
                      variant="outline"
                      onClick={() => setSelectedServiceId(s.id)}
                    >
                      {s.name}
                    </Button>
                  ))}
                </div>
              </>
            )}
          </CardContent>
        </Card>
      </div>
    )
  }

  const typeLabel = serviceType ? SERVICE_TYPE_LABELS[serviceType] : undefined

  return (
    <div className="space-y-6">
      {/* 頁首 */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">服務標籤設定</h1>
          <p className="text-sm text-slate-500 mt-1">
            目前設定：
            <span className="font-medium text-slate-700">{selectedService.name}</span>
            {typeLabel && <span className="text-slate-400">（{typeLabel}）</span>}
          </p>
        </div>
        <div className="flex items-center gap-3 shrink-0">
          <Badge variant="secondary">已選 {selectedIds.length}</Badge>
          <Button onClick={handleSave} disabled={saving || loading} className="gap-1.5">
            {saving ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Save className="h-4 w-4" />
            )}
            {saving ? '儲存中...' : '儲存標籤'}
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">可用標籤</CardTitle>
          <p className="text-xs text-slate-500 mt-1 leading-relaxed">
            標籤會顯示在此服務的展示頁面，供客戶快速了解服務特色。
            點擊即可切換勾選狀態，儲存時會以覆蓋方式取代這個服務原有的標籤設定。
          </p>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex items-center gap-2 py-8 text-sm text-slate-400">
              <Loader2 className="h-4 w-4 animate-spin" />
              標籤載入中...
            </div>
          ) : allLabels.length === 0 ? (
            <p className="text-sm text-slate-400 py-8">目前沒有可用的標籤</p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {allLabels.map((label) => {
                const isSelected = selectedIds.includes(label.id)
                return (
                  <button
                    key={label.id}
                    type="button"
                    onClick={() => toggle(label.id)}
                    aria-pressed={isSelected}
                    className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium border transition-all duration-150 ${
                      isSelected
                        ? 'bg-slate-900 text-white border-slate-900 shadow-sm'
                        : 'bg-white text-slate-600 border-slate-300 hover:border-slate-400 hover:bg-slate-50'
                    }`}
                  >
                    {isSelected && (
                      <svg
                        className="w-3.5 h-3.5"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                        strokeWidth={3}
                      >
                        <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                      </svg>
                    )}
                    {label.name}
                  </button>
                )
              })}
            </div>
          )}
        </CardContent>
      </Card>

      <Toast
        message={toast.message}
        visible={toast.visible}
        onClose={handleToastClose}
        variant={toast.variant}
      />
    </div>
  )
}

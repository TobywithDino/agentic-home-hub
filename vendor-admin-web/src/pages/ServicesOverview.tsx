import { useCallback, useEffect, useState } from 'react'
import { Plus, Trash2, Users, Loader2, AlertTriangle } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import {
  createVendorService,
  deleteVendorService,
  createServiceForm,
  SERVICE_TYPE_LABELS,
  type VendorService,
} from '@/api'
import { useServiceContext } from '@/contexts/ServiceContext'
import {
  FieldListEditor,
  editableFieldsToPayload,
  type EditableField,
} from '@/components/FormFieldEditor'

/** 服務類型下拉選項，順序依後端代碼 */
const SERVICE_TYPE_OPTIONS = ['1', '2', '3', '6', '9', '10', '11'].map((value) => ({
  value,
  label: SERVICE_TYPE_LABELS[value] ?? value,
}))

/** 後端回傳 ISO 時間字串，轉為本地可讀格式；非 ISO 則原樣顯示 */
function formatTimestamp(raw: string): string {
  const d = new Date(raw)
  return Number.isNaN(d.getTime()) ? raw : d.toLocaleString('zh-TW')
}

// ─── 子元件：新增服務項目 Modal ──────────────────────────────

interface AddServiceModalProps {
  open: boolean
  onClose: () => void
  onCreated: (message: string) => void
  onError: (message: string) => void
}

function AddServiceModal({ open, onClose, onCreated, onError }: AddServiceModalProps) {
  const [name, setName] = useState('')
  const [type, setType] = useState<string>(SERVICE_TYPE_OPTIONS[0].value)
  const [description, setDescription] = useState('')
  const [fields, setFields] = useState<EditableField[]>([])
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (open) {
      setName('')
      setType(SERVICE_TYPE_OPTIONS[0].value)
      setDescription('')
      setFields([])
      setSaving(false)
    }
  }, [open])

  const inputClass =
    'w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-slate-900 focus:border-transparent'

  const hasErrors = !name.trim() || fields.some((f) => !f.label.trim())

  /**
   * 兩步建立流程：
   *   1. POST /merchant-api/services         → 取得新服務 id
   *   2. 若填了題目，POST /merchant-api/forms → 帶 service_id 讓後端回寫綁定
   *
   * 第 2 步失敗時服務已建立成功，因此如實提示，避免使用者重複新增服務。
   */
  const handleSubmit = async () => {
    if (hasErrors) return
    setSaving(true)
    try {
      const { service } = await createVendorService({
        name: name.trim(),
        type,
        description: description.trim() || undefined,
      })

      const validFields = fields.filter((f) => f.label.trim())
      if (validFields.length === 0) {
        onCreated(`服務項目「${service.name}」已建立`)
        onClose()
        return
      }

      try {
        await createServiceForm(service.id, {
          title: name.trim(),
          description: description.trim(),
          fields: editableFieldsToPayload(validFields),
        })
        onCreated(`服務項目「${service.name}」與諮詢表單已建立`)
      } catch {
        onError(`服務項目「${service.name}」已建立，但諮詢表單建立失敗，請至「表單內容修改」重試`)
      }
      onClose()
    } catch {
      onError('新增服務項目失敗，請重試')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="新增服務項目" className="max-w-2xl max-h-[90vh]">
      <div className="space-y-5">
        <div className="space-y-3">
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">
              服務名稱 <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="例：水電修繕-管線更換"
              maxLength={100}
              className={inputClass}
            />
            <p className="text-xs text-slate-400 mt-1">{name.length} / 100</p>
          </div>

          <div>
            <label htmlFor="new-service-type" className="block text-sm font-medium text-slate-700 mb-1">
              服務類型 <span className="text-red-500">*</span>
            </label>
            <select
              id="new-service-type"
              value={type}
              onChange={(e) => setType(e.target.value)}
              className={inputClass}
            >
              {SERVICE_TYPE_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">服務簡介</label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="向客戶說明此服務的內容（選填）"
              rows={3}
              className={`${inputClass} resize-none`}
            />
          </div>
        </div>

        {/* 初始表單題目（選填）*/}
        <div className="border-t border-slate-100 pt-4">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-medium text-slate-700">
              初始諮詢表單題目
              <span className="ml-1.5 text-xs text-slate-400 font-normal">（選填）</span>
            </h3>
            {fields.length > 0 && (
              <span className="text-xs text-slate-400">{fields.length} 個題目</span>
            )}
          </div>

          {fields.length === 0 && (
            <p className="text-xs text-slate-400 mb-2 leading-relaxed">
              不新增題目也可以，服務建立後可到「表單內容修改」再建立。
              若在此新增題目，會一併建立諮詢表單並自動綁定到這個服務。
            </p>
          )}

          <FieldListEditor fields={fields} onFieldsChange={setFields} addLabel="新增題目" />
        </div>

        <div className="flex items-center justify-between pt-2 border-t border-slate-100">
          <p className="text-xs text-slate-400">
            {hasErrors && '請填寫服務名稱，並確認所有題目名稱已填寫'}
          </p>
          <div className="flex gap-2">
            <Button variant="outline" onClick={onClose} disabled={saving}>
              取消
            </Button>
            <Button onClick={handleSubmit} disabled={saving || hasErrors} className="gap-1.5">
              {saving && <Loader2 className="h-4 w-4 animate-spin" />}
              {saving ? '建立中...' : '建立服務'}
            </Button>
          </div>
        </div>
      </div>
    </Modal>
  )
}

// ─── 子元件：刪除服務確認 Dialog ─────────────────────────────

interface DeleteServiceDialogProps {
  service: VendorService | null
  deleting: boolean
  onCancel: () => void
  onConfirm: () => void
}

function DeleteServiceDialog({
  service,
  deleting,
  onCancel,
  onConfirm,
}: DeleteServiceDialogProps) {
  return (
    <Modal open={service !== null} onClose={onCancel} title="刪除服務項目">
      <div className="space-y-4">
        <div className="flex items-start gap-3 rounded-lg border border-red-200 bg-red-50 px-4 py-3">
          <AlertTriangle className="h-5 w-5 text-red-600 shrink-0 mt-0.5" aria-hidden="true" />
          <p className="text-sm text-red-800 leading-relaxed">
            確定要刪除「<span className="font-semibold">{service?.name}</span>」嗎？
            此動作將連同該服務的諮詢表單一併移除且無法復原。
          </p>
        </div>

        {(service?.sharedFormCount ?? 0) > 1 && (
          <p className="text-xs text-slate-500 leading-relaxed">
            註：這張表單另有 {(service?.sharedFormCount ?? 1) - 1} 個服務共用，
            刪除本服務不會影響其他服務的表單設定。
          </p>
        )}

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onCancel} disabled={deleting}>
            取消
          </Button>
          <Button variant="destructive" onClick={onConfirm} disabled={deleting} className="gap-1.5">
            {deleting && <Loader2 className="h-4 w-4 animate-spin" />}
            {deleting ? '刪除中...' : '確認刪除'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}

// ─── 主頁面：服務管理總覽（廠商全域層）────────────────────────

export default function ServicesOverview() {
  const { services, loading, reloadServices } = useServiceContext()

  const [addOpen, setAddOpen] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<VendorService | null>(null)
  const [deleting, setDeleting] = useState(false)

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

  const handleServiceCreated = async (message: string) => {
    await reloadServices()
    showToast(message)
  }

  const handleDeleteConfirm = async () => {
    if (!deleteTarget) return
    const target = deleteTarget
    setDeleting(true)
    try {
      await deleteVendorService(target.id)
      // reloadServices 會在選取的服務消失時自動改選第一個
      await reloadServices()
      setDeleteTarget(null)
      showToast(`服務項目「${target.name}」已刪除`)
    } catch {
      showToast(`刪除「${target.name}」失敗，請重試`, 'error')
    } finally {
      setDeleting(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-slate-500">載入中...</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* 頁首 */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">服務管理總覽</h1>
          <p className="text-sm text-slate-500 mt-1">
            管理服務項目的新增與刪除。表單內容與標籤設定請於左側切換服務後，
            至「表單內容修改」與「服務標籤設定」操作。
          </p>
        </div>
        <div className="flex items-center gap-3 shrink-0">
          <Badge variant="secondary" className="text-sm px-3 py-1">
            共 {services.length} 項服務
          </Badge>
          <Badge variant="success" className="text-sm px-3 py-1">
            已建表單 {services.filter((s) => s.form !== null).length}
          </Badge>
          <Button onClick={() => setAddOpen(true)} className="gap-1.5">
            <Plus className="h-4 w-4" />
            新增服務
          </Button>
        </div>
      </div>

      {/* 服務卡片列表 */}
      {services.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-16 text-center">
            <p className="text-slate-500 text-sm font-medium">目前尚無服務項目</p>
            <p className="text-slate-400 text-xs mt-1 max-w-sm">
              請點擊上方按鈕新增服務項目，之後即可為每個服務設定諮詢表單與標籤。
            </p>
            <Button onClick={() => setAddOpen(true)} className="gap-1.5 mt-4">
              <Plus className="h-4 w-4" />
              新增第一個服務項目
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {services.map((service) => {
            const hasForm = service.form !== null
            const isShared = hasForm && (service.sharedFormCount ?? 0) > 1

            return (
              <Card key={service.id} className="hover:shadow-md transition-shadow">
                <CardContent className="py-4">
                  <div className="flex items-center gap-4">
                    {/* 服務資訊 */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-semibold text-slate-900">{service.name}</span>
                        {service.type && SERVICE_TYPE_LABELS[service.type] && (
                          <Badge variant="secondary">
                            {SERVICE_TYPE_LABELS[service.type]}
                          </Badge>
                        )}
                        {hasForm ? (
                          <Badge variant="success">已建立表單</Badge>
                        ) : (
                          <Badge variant="warning">尚無表單</Badge>
                        )}
                        {isShared && (
                          <Badge variant="warning" className="gap-1">
                            <Users className="h-3 w-3" />
                            {service.sharedFormCount} 個服務共用
                          </Badge>
                        )}
                      </div>

                      {hasForm ? (
                        <div className="mt-1 flex items-center gap-3 text-sm text-slate-500 flex-wrap">
                          <span className="truncate max-w-xs" title={service.form!.title}>
                            📋 {service.form!.title || '(未命名表單)'}
                          </span>
                          <span className="shrink-0 text-xs bg-slate-100 text-slate-600 px-2 py-0.5 rounded-full">
                            {service.form!.fields.length} 個欄位
                          </span>
                          {service.form!.updatedAt && (
                            <span className="shrink-0 text-xs text-slate-400">
                              最後更新：{formatTimestamp(service.form!.updatedAt)}
                            </span>
                          )}
                        </div>
                      ) : (
                        <p className="mt-1 text-sm text-slate-400">
                          尚未建立諮詢表單，客戶將無法線上提交需求
                        </p>
                      )}
                    </div>

                    {/* 本頁僅負責新增／刪除；表單與標籤設定請至左側對應頁面 */}
                    <div className="flex items-center gap-2 shrink-0">
                      <button
                        type="button"
                        onClick={() => setDeleteTarget(service)}
                        disabled={deleting}
                        aria-label={`刪除服務「${service.name}」`}
                        title={`刪除服務「${service.name}」`}
                        className="ml-1 p-2 rounded-md text-red-500 hover:bg-red-50 hover:text-red-600 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      <AddServiceModal
        open={addOpen}
        onClose={() => setAddOpen(false)}
        onCreated={handleServiceCreated}
        onError={(msg) => showToast(msg, 'error')}
      />

      <DeleteServiceDialog
        service={deleteTarget}
        deleting={deleting}
        onCancel={() => {
          if (!deleting) setDeleteTarget(null)
        }}
        onConfirm={handleDeleteConfirm}
      />

      <Toast
        message={toast.message}
        visible={toast.visible}
        onClose={handleToastClose}
        variant={toast.variant}
      />
    </div>
  )
}

import { useCallback, useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Toast } from '@/components/ui/toast'
import { Loader2, Save, Users } from 'lucide-react'
import { createServiceForm, updateServiceForm } from '@/api'
import { useServiceContext } from '@/contexts/ServiceContext'
import {
  FieldListEditor,
  editableFieldsToPayload,
  fieldToEditable,
  makeEmptyField,
  type EditableField,
} from '@/components/FormFieldEditor'

/**
 * 表單內容修改（單一服務層）
 *
 * 直接載入 Header 目前選取服務所綁定的表單題目結構供編輯。
 * 該服務尚未綁定表單時，本頁作為「建立表單」使用。
 */
export default function FormEditor() {
  const {
    services,
    selectedService,
    setSelectedServiceId,
    loading: servicesLoading,
    reloadServices,
  } = useServiceContext()

  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [fields, setFields] = useState<EditableField[]>([])
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

  const existingForm = selectedService?.form ?? null
  const isEdit = existingForm !== null

  // 切換服務時重新初始化編輯內容
  useEffect(() => {
    if (existingForm) {
      setTitle(existingForm.title)
      setDescription(existingForm.description)
      setFields(existingForm.fields.map(fieldToEditable))
    } else {
      setTitle(selectedService?.name ?? '')
      setDescription('')
      setFields([makeEmptyField()])
    }
  }, [selectedService?.id, existingForm, selectedService?.name])

  const hasErrors =
    !title.trim() || fields.length === 0 || fields.some((f) => !f.label.trim())

  const handleSave = async () => {
    if (!selectedService || hasErrors) return
    setSaving(true)
    try {
      const payload = {
        title: title.trim(),
        description: description.trim(),
        fields: editableFieldsToPayload(fields),
        // 帶回原始題組結構，避免後端差異比對時刪掉其他題組
        groups: existingForm?.groups,
        // 原樣回送表單類型，後端更新時要求必填
        formType: existingForm?.type,
        formSubType: existingForm?.subType,
      }

      if (isEdit) {
        await updateServiceForm(selectedService.id, existingForm.id, payload)
      } else {
        await createServiceForm(selectedService.id, payload)
      }

      // 表單是版本化的：更新會產生新的 form_id 並重新綁定服務，
      // 因此必須重新拉取，否則畫面仍指向舊版本。
      await reloadServices()
      showToast(isEdit ? '表單已更新（已建立新版本）' : '表單已建立並綁定至此服務')
    } catch {
      // api 層已顯示全域錯誤 Toast
      showToast(isEdit ? '更新表單失敗，請重試' : '建立表單失敗，請重試', 'error')
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

  // 選「所有服務」時無法編輯（表單以單一服務為單位），提供快速挑選
  if (!selectedService) {
    return (
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-slate-900">表單內容修改</h1>
        <Card>
          <CardContent className="py-14 text-center">
            {services.length === 0 ? (
              <>
                <p className="text-slate-500 text-sm font-medium">尚無服務項目</p>
                <p className="text-slate-400 text-xs mt-1">
                  請先至「服務管理總覽」新增服務項目，再回此頁設定表單
                </p>
              </>
            ) : (
              <>
                <p className="text-slate-500 text-sm font-medium">請選擇單一服務</p>
                <p className="text-slate-400 text-xs mt-1">
                  表單以服務為單位設定，無法一次編輯所有服務。請選擇要編輯的服務：
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

  const sharedCount = selectedService.sharedFormCount ?? 0

  return (
    <div className="space-y-6">
      {/* 頁首 */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">表單內容修改</h1>
          <p className="text-sm text-slate-500 mt-1">
            目前編輯：<span className="font-medium text-slate-700">{selectedService.name}</span>
            {isEdit ? '' : '（此服務尚未建立表單）'}
          </p>
        </div>
        <div className="flex items-center gap-3 shrink-0">
          <Badge variant={isEdit ? 'success' : 'warning'}>
            {isEdit ? `${fields.length} 個題目` : '尚無表單'}
          </Badge>
          <Button onClick={handleSave} disabled={saving || hasErrors} className="gap-1.5">
            {saving ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Save className="h-4 w-4" />
            )}
            {saving ? '儲存中...' : isEdit ? '更新表單' : '建立表單'}
          </Button>
        </div>
      </div>

      {/* 表單被多個服務共用時的警示 */}
      {isEdit && sharedCount > 1 && (
        <div className="flex items-start gap-2.5 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3">
          <Users className="h-4 w-4 text-amber-600 shrink-0 mt-0.5" aria-hidden="true" />
          <p className="text-xs text-amber-800 leading-relaxed">
            這張表單目前由 <span className="font-semibold">{sharedCount} 個服務</span>共用，
            修改後會同時套用到所有共用的服務。
          </p>
        </div>
      )}

      {/* 表單基本資訊 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">表單基本資訊</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <label htmlFor="form-title" className="block text-sm font-medium text-slate-700 mb-1">
              表單標題 <span className="text-red-500">*</span>
            </label>
            <input
              id="form-title"
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="請輸入表單標題"
              className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-slate-900 focus:border-transparent"
            />
          </div>
          <div>
            <label htmlFor="form-desc" className="block text-sm font-medium text-slate-700 mb-1">
              表單說明
            </label>
            <textarea
              id="form-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="向客戶說明此表單的用途（選填）"
              rows={3}
              className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-slate-900 focus:border-transparent"
            />
          </div>
        </CardContent>
      </Card>

      {/* 題目欄位 */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-base">
            題目欄位
            <span className="ml-2 text-xs text-slate-400 font-normal">
              {fields.length} 個
            </span>
          </CardTitle>
          {hasErrors && (
            <p className="text-xs text-amber-600">
              請填寫表單標題，並確認所有題目名稱已填寫
            </p>
          )}
        </CardHeader>
        <CardContent>
          <FieldListEditor fields={fields} onFieldsChange={setFields} addLabel="新增題目" />
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

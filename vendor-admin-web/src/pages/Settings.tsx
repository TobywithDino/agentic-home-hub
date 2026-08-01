import { useCallback, useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Toast } from '@/components/ui/toast'
import {
  getVendorProfile,
  updateVendorProfile,
  getVendorLabels,
  updateVendorServiceLabels,
  type VendorProfile,
  type ServiceLabel,
} from '@/api'

export default function Settings() {
  const [profile, setProfile] = useState<VendorProfile | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [toastVisible, setToastVisible] = useState(false)
  const [toastMessage, setToastMessage] = useState('')

  // Form fields
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [adminName, setAdminName] = useState('')
  const [adminPhone, setAdminPhone] = useState('')
  const [adminEmail, setAdminEmail] = useState('')
  const [newPassword, setNewPassword] = useState('')

  // Service Labels
  const [allLabels, setAllLabels] = useState<ServiceLabel[]>([])
  const [selectedLabelIds, setSelectedLabelIds] = useState<number[]>([])

  useEffect(() => {
    async function load() {
      const [profileData, labelsData] = await Promise.all([
        getVendorProfile(),
        getVendorLabels(),
      ])
      setProfile(profileData)
      setName(profileData.name)
      setDescription(profileData.description)
      setAdminName(profileData.adminName)
      setAdminPhone(profileData.adminPhone)
      setAdminEmail(profileData.adminEmail)
      setAllLabels(labelsData.allLabels)
      setSelectedLabelIds(labelsData.selectedIds)
      setLoading(false)
    }
    load()
  }, [])

  const toggleLabel = (labelId: number) => {
    setSelectedLabelIds((prev) =>
      prev.includes(labelId)
        ? prev.filter((id) => id !== labelId)
        : [...prev, labelId]
    )
  }

  const handleSave = async () => {
    setSaving(true)
    try {
      const [profileResult, labelsResult] = await Promise.all([
        updateVendorProfile({
          name,
          description,
          adminName,
          adminPhone,
          adminEmail,
          ...(newPassword ? { newPassword } : {}),
        }),
        updateVendorServiceLabels(selectedLabelIds),
      ])
      setProfile(profileResult.profile)
      setSelectedLabelIds(labelsResult.selectedIds)
      setNewPassword('')
      setToastMessage('商家標籤與設定已更新')
      setToastVisible(true)
    } catch {
      // demo: silently ignore
    } finally {
      setSaving(false)
    }
  }

  const handleToastClose = useCallback(() => setToastVisible(false), [])

  if (loading || !profile) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-slate-500">載入中...</p>
      </div>
    )
  }

  const inputClass =
    'w-full rounded-md border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-slate-900 focus:border-transparent'

  return (
    <div className="space-y-6 max-w-3xl">
      <h1 className="text-2xl font-bold text-slate-900">商家資訊設定</h1>

      {/* 區塊 A：商家屬性設定 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">商家屬性設定</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <label htmlFor="vendor-name" className="block text-sm font-medium text-slate-700 mb-1">
              商家名稱
            </label>
            <input
              id="vendor-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className={inputClass}
              placeholder="請輸入商家名稱"
            />
          </div>
          <div>
            <label htmlFor="vendor-desc" className="block text-sm font-medium text-slate-700 mb-1">
              商家描述
            </label>
            <textarea
              id="vendor-desc"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className={`${inputClass} min-h-[100px] resize-y`}
              placeholder="請輸入商家描述"
              rows={4}
            />
          </div>

          {/* Service Labels Chips */}
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">
              商家服務標籤
            </label>
            <p className="text-xs text-slate-400 mb-3">
              點擊標籤進行勾選或取消勾選，已選取的標籤將顯示於您的服務頁面
            </p>
            <div className="flex flex-wrap gap-2">
              {allLabels.map((label) => {
                const isSelected = selectedLabelIds.includes(label.id)
                return (
                  <button
                    key={label.id}
                    type="button"
                    onClick={() => toggleLabel(label.id)}
                    className={`
                      inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-medium
                      transition-all duration-150 border
                      ${
                        isSelected
                          ? 'bg-slate-900 text-white border-slate-900 shadow-sm'
                          : 'bg-white text-slate-600 border-slate-300 hover:border-slate-400 hover:bg-slate-50'
                      }
                    `}
                    aria-pressed={isSelected}
                  >
                    {isSelected && (
                      <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                      </svg>
                    )}
                    {label.name}
                  </button>
                )
              })}
            </div>
            <p className="text-xs text-slate-400 mt-2">
              已選取 {selectedLabelIds.length} 個標籤
            </p>
          </div>
        </CardContent>
      </Card>

      {/* 區塊 B：管理員聯絡方式與帳號設定 */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">管理員聯絡方式與帳號設定</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label htmlFor="admin-name" className="block text-sm font-medium text-slate-700 mb-1">
                管理員姓名
              </label>
              <input
                id="admin-name"
                type="text"
                value={adminName}
                onChange={(e) => setAdminName(e.target.value)}
                className={inputClass}
                placeholder="請輸入管理員姓名"
              />
            </div>
            <div>
              <label htmlFor="admin-phone" className="block text-sm font-medium text-slate-700 mb-1">
                聯絡手機
              </label>
              <input
                id="admin-phone"
                type="tel"
                value={adminPhone}
                onChange={(e) => setAdminPhone(e.target.value)}
                className={inputClass}
                placeholder="0912-345-678"
              />
            </div>
          </div>
          <div>
            <label htmlFor="admin-email" className="block text-sm font-medium text-slate-700 mb-1">
              聯絡 Email
            </label>
            <input
              id="admin-email"
              type="email"
              value={adminEmail}
              onChange={(e) => setAdminEmail(e.target.value)}
              className={inputClass}
              placeholder="admin@example.com"
            />
          </div>
          <div>
            <label htmlFor="new-password" className="block text-sm font-medium text-slate-700 mb-1">
              變更密碼
            </label>
            <input
              id="new-password"
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              className={inputClass}
              placeholder="如不更改請留空"
            />
            <p className="text-xs text-slate-400 mt-1">留空則不變更密碼</p>
          </div>
        </CardContent>
      </Card>

      {/* Save Button */}
      <div className="flex justify-end">
        <Button onClick={handleSave} disabled={saving} className="px-6">
          {saving ? '儲存中...' : '儲存變更'}
        </Button>
      </div>

      {/* Success Toast */}
      <Toast
        message={toastMessage}
        visible={toastVisible}
        onClose={handleToastClose}
      />
    </div>
  )
}

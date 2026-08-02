import { useCallback, useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Toast } from '@/components/ui/toast'
import { getVendorProfile, updateVendorProfile, type VendorProfile } from '@/api'

export default function Settings() {
  const [profile, setProfile] = useState<VendorProfile | null>(null)
  const [loading, setLoading] = useState(true)
  /** 後端載入失敗（與「還在載入」區分，避免永遠卡在載入中） */
  const [loadFailed, setLoadFailed] = useState(false)
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

  /** 把後端 profile 套用到 state 與各欄位，載入與儲存後回讀共用 */
  const applyProfile = useCallback((p: VendorProfile) => {
    setProfile(p)
    setName(p.name)
    setDescription(p.description)
    setAdminName(p.adminName)
    setAdminPhone(p.adminPhone)
    setAdminEmail(p.adminEmail)
  }, [])

  // 此頁為廠商全覽層級：只處理商家屬性與管理帳號。
  // 服務標籤已移至「服務表單管理」的各服務卡片，以 service_id 為範圍操作。
  const load = useCallback(async () => {
    setLoading(true)
    setLoadFailed(false)
    try {
      // 抓不到資料時回 null（不再以假資料填欄位），改顯示重新載入
      const p = await getVendorProfile()
      if (p) applyProfile(p)
      else setLoadFailed(true)
    } finally {
      setLoading(false)
    }
  }, [applyProfile])

  useEffect(() => {
    load()
  }, [load])

  const handleSave = async () => {
    setSaving(true)
    try {
      const profileResult = await updateVendorProfile({
        name,
        description,
        adminName,
        adminPhone,
        adminEmail,
        ...(newPassword ? { newPassword } : {}),
      })
      // 以後端回讀結果覆寫欄位，確保畫面與 DB 一致
      if (profileResult.profile) applyProfile(profileResult.profile)

      setNewPassword('')
      setToastMessage('商家資訊已儲存')
      setToastVisible(true)
    } catch {
      // 寫入失敗不能顯示成功，明確告知使用者
      setToastMessage('商家資訊儲存失敗，請稍後再試')
      setToastVisible(true)
    } finally {
      setSaving(false)
    }
  }

  const handleToastClose = useCallback(() => setToastVisible(false), [])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-slate-500">載入中...</p>
      </div>
    )
  }

  if (loadFailed || !profile) {
    return (
      <div className="space-y-6 max-w-3xl">
        <h1 className="text-2xl font-bold text-slate-900">商家資訊設定</h1>
        <Card>
          <CardContent className="py-12 text-center space-y-4">
            <p className="text-slate-500">無法載入商家資料，請確認後端服務是否正常。</p>
            <Button variant="outline" onClick={load}>
              重新載入
            </Button>
          </CardContent>
        </Card>
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


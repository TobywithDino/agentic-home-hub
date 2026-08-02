import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import {
  LayoutDashboard,
  FileText,
  ShoppingCart,
  LayoutList,
  ClipboardList,
  Tag,
  Settings,
  LogOut,
  ChevronDown,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { SERVICE_TYPE_LABELS } from '@/api'
import { ALL_SERVICES, useServiceContext } from '@/contexts/ServiceContext'

interface LayoutProps {
  onLogout: () => void
}

/** 廠商全域層：不受選取的服務影響 */
const vendorNavItems = [
  { to: '/dashboard', label: '戰情儀表板', icon: LayoutDashboard },
  { to: '/services', label: '服務管理總覽', icon: LayoutList },
  { to: '/settings', label: '商家資訊設定', icon: Settings },
]

/**
 * 單一服務層：跟隨選取的服務
 * 順序依業務流程排列：諮詢單 →（接單）→ 訂單 → 表單／標籤設定
 */
const serviceNavItems = [
  { to: '/feedbacks', label: '諮詢單管理', icon: FileText },
  { to: '/orders', label: '訂單管理', icon: ShoppingCart },
  { to: '/form-editor', label: '表單內容修改', icon: ClipboardList, singleOnly: true },
  { to: '/service-labels', label: '服務標籤設定', icon: Tag, singleOnly: true },
]

/**
 * 側邊欄的服務切換選單
 *
 * 放在「目前服務」區塊標題下方而非右側 —— 側邊欄寬度有限，
 * 整行呈現才不會讓較長的服務名稱被截斷。
 */
function ServiceSelector() {
  const { services, selectedServiceId, setSelectedServiceId, loading } =
    useServiceContext()

  if (loading) {
    return (
      <p className="px-3 py-2 text-xs text-slate-500">服務清單載入中...</p>
    )
  }

  if (services.length === 0) {
    return (
      <p className="px-3 py-2 text-xs text-slate-500 leading-relaxed">
        尚無服務項目
        <br />
        請至「服務管理總覽」新增
      </p>
    )
  }

  return (
    <div className="relative px-1">
      <select
        aria-label="切換服務"
        value={selectedServiceId ?? ''}
        onChange={(e) => {
          const v = e.target.value
          setSelectedServiceId(v === ALL_SERVICES ? ALL_SERVICES : Number(v))
        }}
        className="w-full appearance-none rounded-lg border border-slate-600 bg-slate-800 py-2 pl-3 pr-8 text-sm font-medium text-white cursor-pointer hover:border-slate-500 focus:outline-none focus:ring-2 focus:ring-slate-400 transition-colors"
      >
        <option value={ALL_SERVICES}>所有服務（{services.length}）</option>
        {services.map((s) => {
          const typeLabel = s.type ? SERVICE_TYPE_LABELS[s.type] : undefined
          return (
            <option key={s.id} value={s.id}>
              {typeLabel ? `${s.name}｜${typeLabel}` : s.name}
            </option>
          )
        })}
      </select>
      <ChevronDown
        className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400"
        aria-hidden="true"
      />
    </div>
  )
}

export default function Layout({ onLogout }: LayoutProps) {
  const navigate = useNavigate()
  const { isAllServices } = useServiceContext()

  const handleLogout = () => {
    onLogout()
    navigate('/login')
  }

  const navLinkClass = ({ isActive }: { isActive: boolean }) =>
    cn(
      'flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors',
      isActive
        ? 'bg-slate-800 text-white'
        : 'text-slate-300 hover:bg-slate-800 hover:text-white'
    )

  return (
    <div className="min-h-screen flex bg-slate-50">
      {/* Sidebar */}
      <aside className="w-72 bg-slate-900 text-white flex flex-col shrink-0">
        <div className="p-6 border-b border-slate-700">
          <h2 className="text-lg font-bold">智慧社區平台</h2>
          <p className="text-xs text-slate-400 mt-1">廠商管理後台</p>
        </div>

        <nav className="flex-1 p-4 space-y-5 overflow-y-auto">
          {/* 廠商全域層 */}
          <div className="space-y-1">
            <p className="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-slate-500">
              廠商全覽
            </p>
            {vendorNavItems.map((item) => (
              <NavLink key={item.to} to={item.to} className={navLinkClass}>
                <item.icon className="h-5 w-5" />
                {item.label}
              </NavLink>
            ))}
          </div>

          {/* 單一服務層：標題 + 切換選單 + 導覽項 */}
          <div className="space-y-1">
            <p className="px-3 pb-1.5 text-[11px] font-semibold uppercase tracking-wider text-slate-500">
              目前服務
            </p>

            <ServiceSelector />

            <div className="pt-2 space-y-1">
              {serviceNavItems.map((item) => {
                // 選「所有服務」時，需要單一服務的頁面標示為不適用
                const dimmed = item.singleOnly && isAllServices
                return (
                  <NavLink
                    key={item.to}
                    to={item.to}
                    className={navLinkClass}
                    title={dimmed ? '此頁需選擇單一服務' : undefined}
                  >
                    <item.icon className="h-5 w-5" />
                    <span className={dimmed ? 'opacity-50' : undefined}>{item.label}</span>
                  </NavLink>
                )
              })}
            </div>
          </div>
        </nav>

        <div className="p-4 border-t border-slate-700">
          <button
            onClick={handleLogout}
            className="flex items-center gap-3 px-3 py-2.5 w-full rounded-lg text-sm font-medium text-slate-300 hover:bg-slate-800 hover:text-white transition-colors"
          >
            <LogOut className="h-5 w-5" />
            登出
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 p-8 overflow-auto">
        <Outlet />
      </main>
    </div>
  )
}

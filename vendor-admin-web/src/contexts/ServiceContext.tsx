import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { fetchVendorServices, getVendorId, type VendorService } from '@/api'

/** 服務選取值：具體服務 id 或 'all'（所有服務一起列出） */
export type ServiceSelection = number | 'all'

/** 所有服務的選取常數 */
export const ALL_SERVICES = 'all' as const

interface ServiceContextValue {
  /** 該廠商的所有服務項目（含綁定的表單） */
  services: VendorService[]
  /**
   * 目前選取值。
   *   number → 單一服務
   *   'all'  → 所有服務（訂單／諮詢單不做篩選）
   *   null   → 尚未載入或廠商沒有任何服務
   */
  selectedServiceId: ServiceSelection | null
  /**
   * 目前選取的服務物件。選取 'all' 或無服務時為 null，
   * 因此需要單一服務的頁面可用它判斷是否可操作。
   */
  selectedService: VendorService | null
  /** 是否選取「所有服務」 */
  isAllServices: boolean
  /** 服務清單是否正在載入 */
  loading: boolean
  setSelectedServiceId: (id: ServiceSelection | null) => void
  /** 重新拉取服務清單（新增／刪除服務或更新表單後呼叫） */
  reloadServices: () => Promise<VendorService[]>
}

const ServiceContext = createContext<ServiceContextValue | null>(null)

/**
 * 全域服務選取狀態
 *
 * Header 的服務切換下拉選單寫入 selectedServiceId，
 * 訂單／諮詢單／表單編輯／標籤設定等單一服務層頁面則跟隨它自動切換。
 *
 * 服務清單集中在此載入，避免每個頁面各自呼叫 fetchVendorServices()
 * 造成重複請求（該函式會為每張表單額外抓 /forms/{id}/full）。
 */
export function ServiceProvider({ children }: { children: ReactNode }) {
  const [services, setServices] = useState<VendorService[]>([])
  const [selectedServiceId, setSelectedServiceId] = useState<ServiceSelection | null>(
    null
  )
  const [loading, setLoading] = useState(true)

  const reloadServices = useCallback(async () => {
    // api 層已包 try-catch 並顯示全域 Toast，失敗時回空陣列
    const list = await fetchVendorServices(getVendorId()).catch(
      () => [] as VendorService[]
    )
    setServices(list)

    setSelectedServiceId((prev) => {
      if (list.length === 0) return null
      // 'all' 永遠有效
      if (prev === ALL_SERVICES) return prev
      // 維持選取；若原選取的服務已不存在（例如剛被刪除）改選第一個
      return prev != null && list.some((s) => s.id === prev) ? prev : list[0].id
    })
    return list
  }, [])

  useEffect(() => {
    reloadServices().finally(() => setLoading(false))
  }, [reloadServices])

  const value = useMemo<ServiceContextValue>(
    () => ({
      services,
      selectedServiceId,
      selectedService:
        typeof selectedServiceId === 'number'
          ? (services.find((s) => s.id === selectedServiceId) ?? null)
          : null,
      isAllServices: selectedServiceId === ALL_SERVICES,
      loading,
      setSelectedServiceId,
      reloadServices,
    }),
    [services, selectedServiceId, loading, reloadServices]
  )

  return <ServiceContext.Provider value={value}>{children}</ServiceContext.Provider>
}

/** 取用全域服務選取狀態。必須在 ServiceProvider 內使用 */
export function useServiceContext(): ServiceContextValue {
  const ctx = useContext(ServiceContext)
  if (!ctx) {
    throw new Error('useServiceContext 必須在 ServiceProvider 內使用')
  }
  return ctx
}

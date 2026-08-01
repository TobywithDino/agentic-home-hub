import { useEffect, useState } from 'react'
import { cn } from '@/lib/utils'
import { CheckCircle2, AlertTriangle } from 'lucide-react'

interface ToastProps {
  message: string
  visible: boolean
  onClose: () => void
  duration?: number
  variant?: 'success' | 'error'
}

export function Toast({ message, visible, onClose, duration = 3000, variant = 'success' }: ToastProps) {
  const [show, setShow] = useState(false)

  useEffect(() => {
    if (visible) {
      setShow(true)
      const timer = setTimeout(() => {
        setShow(false)
        setTimeout(onClose, 200) // wait for fade-out
      }, duration)
      return () => clearTimeout(timer)
    }
  }, [visible, duration, onClose])

  if (!visible && !show) return null

  const isError = variant === 'error'

  return (
    <div className="fixed top-6 right-6 z-[100]">
      <div
        className={cn(
          'flex items-center gap-2 px-4 py-3 rounded-lg shadow-lg border transition-all duration-200',
          isError
            ? 'bg-red-50 border-red-200 text-red-800'
            : 'bg-emerald-50 border-emerald-200 text-emerald-800',
          show ? 'opacity-100 translate-y-0' : 'opacity-0 -translate-y-2'
        )}
      >
        {isError ? (
          <AlertTriangle className="h-5 w-5 text-red-600 shrink-0" />
        ) : (
          <CheckCircle2 className="h-5 w-5 text-emerald-600 shrink-0" />
        )}
        <span className="text-sm font-medium">{message}</span>
      </div>
    </div>
  )
}

import { useCallback, useEffect, useState } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import Login from '@/pages/Login'
import Dashboard from '@/pages/Dashboard'
import Feedbacks from '@/pages/Feedbacks'
import Orders from '@/pages/Orders'
import Settings from '@/pages/Settings'
import ServicesOverview from '@/pages/ServicesOverview'
import FormEditor from '@/pages/FormEditor'
import ServiceLabels from '@/pages/ServiceLabels'
import Layout from '@/components/Layout'
import { Toast } from '@/components/ui/toast'
import { registerApiErrorHandler, setVendorId } from '@/api'
import { ServiceProvider } from '@/contexts/ServiceContext'

export default function App() {
  const [vendorId, setVendorIdState] = useState<number | null>(null)

  // Global API error toast
  const [errorToast, setErrorToast] = useState({ visible: false, message: '' })

  useEffect(() => {
    registerApiErrorHandler((message) => {
      setErrorToast({ visible: true, message })
    })
  }, [])

  const handleToastClose = useCallback(() => {
    setErrorToast((prev) => ({ ...prev, visible: false }))
  }, [])

  const isLoggedIn = vendorId !== null

  const handleLogin = (id: number) => {
    setVendorIdState(id)
    setVendorId(id)
  }

  const handleLogout = () => {
    setVendorIdState(null)
  }

  return (
    <BrowserRouter>
      <Routes>
        <Route
          path="/login"
          element={
            isLoggedIn ? <Navigate to="/dashboard" replace /> : <Login onLogin={handleLogin} />
          }
        />
        <Route
          element={
            isLoggedIn ? (
              // ServiceProvider 掛在登入後的版面內，確保服務清單於登入取得
              // vendorId 之後才開始載入
              <ServiceProvider>
                <Layout onLogout={handleLogout} />
              </ServiceProvider>
            ) : (
              <Navigate to="/login" replace />
            )
          }
        >
          {/* 廠商全域層：不受 selectedServiceId 影響 */}
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/services" element={<ServicesOverview />} />
          <Route path="/settings" element={<Settings />} />

          {/* 單一服務層：完全跟隨 selectedServiceId */}
          <Route path="/orders" element={<Orders />} />
          <Route path="/feedbacks" element={<Feedbacks />} />
          <Route path="/form-editor" element={<FormEditor />} />
          <Route path="/service-labels" element={<ServiceLabels />} />
        </Route>
        <Route path="*" element={<Navigate to={isLoggedIn ? '/dashboard' : '/login'} replace />} />
      </Routes>

      {/* Global API Error Toast */}
      <Toast
        message={errorToast.message}
        visible={errorToast.visible}
        onClose={handleToastClose}
        variant="error"
        duration={4000}
      />
    </BrowserRouter>
  )
}

import { useCallback, useEffect, useState } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import Login from '@/pages/Login'
import Dashboard from '@/pages/Dashboard'
import Consultations from '@/pages/Consultations'
import Orders from '@/pages/Orders'
import Settings from '@/pages/Settings'
import Layout from '@/components/Layout'
import { Toast } from '@/components/ui/toast'
import { registerApiErrorHandler, setVendorId } from '@/api'

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
            isLoggedIn ? <Layout onLogout={handleLogout} /> : <Navigate to="/login" replace />
          }
        >
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/consultations" element={<Consultations />} />
          <Route path="/orders" element={<Orders />} />
          <Route path="/settings" element={<Settings />} />
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

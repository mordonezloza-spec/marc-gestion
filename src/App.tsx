import { useState } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './lib/auth'
import { Splash } from './components/Splash'
import { Layout } from './components/Layout'
import { Login } from './pages/Login'
import { Inicio } from './pages/Inicio'
import { Cotizaciones } from './pages/Cotizaciones'
import { CotizacionForm } from './pages/CotizacionForm'
import { CotizacionDetalle } from './pages/CotizacionDetalle'
import { Clientes } from './pages/Clientes'
import { Tarifario } from './pages/Tarifario'
import { Ajustes } from './pages/Ajustes'
import { Seccion } from './pages/Seccion'

export default function App() {
  const { session, perfil, errorPerfil, cargando, salir } = useAuth()
  const [splash, setSplash] = useState(() => !sessionStorage.getItem('marc_splash'))
  const fin = () => { sessionStorage.setItem('marc_splash', '1'); setSplash(false) }

  if (splash) return <Splash onDone={fin} />
  if (cargando) return <div className="loading">Cargando…</div>
  if (!session) return <Login />
  if (!perfil) return (
    <div className="lg-form" style={{ minHeight: '100%' }}>
      <div className="lg-card">
        <h2>{errorPerfil ? 'No se pudo leer tu perfil' : 'Usuario sin perfil'}</h2>
        {errorPerfil ? (
          <p className="sub">La base de datos rechazó la consulta: <code>{errorPerfil}</code>.
            {errorPerfil.includes('42501') && <> Faltan permisos: ejecuta <b>supabase/migrations/0004_permisos_data_api.sql</b> en el SQL Editor.</>}</p>
        ) : (
          <p className="sub">Tu cuenta (<b>{session.user.email}</b>) existe, pero no tiene un perfil activo en la tabla <b>perfiles</b>. Pide a gerencia que lo registre (ver README).</p>
        )}
        <button className="btn pri" onClick={salir}>Volver al inicio de sesión</button>
      </div>
    </div>
  )

  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/inicio" element={<Inicio />} />
        <Route path="/cotizaciones" element={<Cotizaciones />} />
        <Route path="/cotizaciones/nueva" element={<CotizacionForm modo="nueva" />} />
        <Route path="/cotizaciones/:id" element={<CotizacionDetalle />} />
        <Route path="/cotizaciones/:id/editar" element={<CotizacionForm modo="editar" />} />
        <Route path="/cotizaciones/:id/version" element={<CotizacionForm modo="version" />} />
        <Route path="/clientes" element={<Clientes />} />
        <Route path="/tarifario" element={<Tarifario />} />
        <Route path="/ajustes" element={<Ajustes />} />
        <Route path="/seccion/:id" element={<Seccion />} />
        <Route path="*" element={<Navigate to="/inicio" replace />} />
      </Route>
    </Routes>
  )
}

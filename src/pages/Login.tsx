import { useState, type FormEvent } from 'react'
import { useAuth } from '../lib/auth'
import { configurado } from '../lib/supabase'
import { Topo } from '../components/Topo'
import { Icon } from '../components/Icon'

export function Login() {
  const { ingresar } = useAuth()
  const [usuario, setUsuario] = useState(() => localStorage.getItem('marc_usuario') || '')
  const [clave, setClave] = useState('')
  const [ver, setVer] = useState(false)
  const [recordar, setRecordar] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  const enviar = async (e: FormEvent) => {
    e.preventDefault()
    if (!usuario.trim() || !clave) { setError('Escribe tu usuario y contraseña.'); return }
    setEnviando(true); setError(null)
    const err = await ingresar(usuario, clave)
    setEnviando(false)
    if (err) { setError(err); return }
    recordar ? localStorage.setItem('marc_usuario', usuario.trim().toUpperCase()) : localStorage.removeItem('marc_usuario')
  }

  return (
    <div id="login">
      <div className="lg-art">
        <Topo />
        <div className="lg-brand">
          <div className="plate"><img src="/logo.png" alt="MARC" /></div>
          <b>Sistema de gestión empresarial</b>
          <p>Cotizaciones, servicios, equipos, personal y finanzas en un solo lugar, con indicadores para decidir a tiempo.</p>
          <div className="lg-chips"><span>Alquiler de maquinaria</span><span>Camión grúa</span><span>Termofusión</span><span>Barranca · Supe</span></div>
        </div>
      </div>
      <div className="lg-form">
        <form className="lg-card" onSubmit={enviar} noValidate>
          <h2>Ingresa a tu cuenta</h2>
          <div className="sub">Usa el usuario asignado por la empresa.</div>
          {!configurado && <div className="err">Falta configurar Supabase en el archivo .env (ver README).</div>}
          <label>Usuario<input value={usuario} onChange={e => setUsuario(e.target.value)} autoComplete="username" placeholder="Ej.: AZELAYA o azelaya@marc-eirl.com" autoFocus={!usuario} /></label>
          <label>Contraseña
            <span className="pw">
              <input type={ver ? 'text' : 'password'} value={clave} onChange={e => setClave(e.target.value)} autoComplete="current-password" autoFocus={!!usuario} />
              <button type="button" onClick={() => setVer(v => !v)} aria-label={ver ? 'Ocultar contraseña' : 'Mostrar contraseña'}><Icon name="eye" /></button>
            </span>
          </label>
          <label style={{ flexDirection: 'row', alignItems: 'center', gap: 8, color: 'var(--ink)', fontWeight: 500 }}>
            <input type="checkbox" checked={recordar} onChange={e => setRecordar(e.target.checked)} style={{ width: 'auto' }} /> Recordar mi usuario
          </label>
          {error && <div className="lg-err">{error}</div>}
          <button className="btn pri" type="submit" disabled={enviando}>{enviando ? 'Ingresando…' : 'Ingresar'}</button>
          <div className="lg-note">¿No puedes ingresar? Pide a gerencia que restablezca tu contraseña.</div>
        </form>
      </div>
    </div>
  )
}

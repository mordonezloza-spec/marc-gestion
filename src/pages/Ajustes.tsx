import { useEffect, useState, type FormEvent } from 'react'
import { usePageHead, useUi } from '../components/Layout'
import { supabase } from '../lib/supabase'
import { ok, useQuery } from '../lib/useQuery'
import { useAuth } from '../lib/auth'
import { useTema } from '../lib/theme'
import type { Empresa, Perfil } from '../lib/types'

const ROL: Record<string, [string, string]> = {
  gerencia: ['Gerencia general', 'Todo, incluidos indicadores, finanzas y usuarios'],
  administracion: ['Administración y RR. HH.', 'Comercial, RR. HH., finanzas y costos'],
  comercial: ['Comercial y ventas', 'Clientes, cotizaciones y tarifario'],
  operaciones: ['Operaciones', 'Lectura comercial; partes diarios y equipos (siguiente fase)'],
}

export function Ajustes() {
  usePageHead('Ajustes del sistema', [{ label: 'Ajustes' }])
  const { perfil } = useAuth()
  const { toast } = useUi()
  const { tema, setTema } = useTema()
  const puedeEmpresa = perfil?.rol === 'gerencia' || perfil?.rol === 'administracion'
  const emp = useQuery(async () => ok(await supabase.from('empresa').select('*').eq('id', 1).single()) as Empresa, [])
  const usuarios = useQuery(async () => (perfil?.rol === 'gerencia' ? (ok(await supabase.from('perfiles').select('*').order('nombre')) as Perfil[]) : []), [perfil?.rol])
  const [e, setE] = useState<Empresa | null>(null)
  useEffect(() => { if (emp.data) setE(emp.data) }, [emp.data])

  const guardar = async (ev: FormEvent) => {
    ev.preventDefault(); if (!e) return
    const { error } = await supabase.from('empresa').update({ razon_social: e.razon_social, ruc: e.ruc, direccion: e.direccion, telefono: e.telefono, correo: e.correo,
      cuenta_soles: e.cuenta_soles, cuenta_detraccion: e.cuenta_detraccion }).eq('id', 1)
    toast(error ? 'No se pudo guardar: ' + error.message : 'Datos de la empresa guardados')
  }
  const campo = (k: keyof Empresa, label: string, ph = '') => (
    <label>{label}<input value={(e?.[k] as string) ?? ''} placeholder={ph} readOnly={!puedeEmpresa} onChange={x => setE({ ...e!, [k]: x.target.value })} /></label>)

  return (
    <>
      <div className="spec">
        <div className="card"><h2>Datos de la empresa</h2>
          {e && <form className="form" style={{ gridTemplateColumns: '1fr' }} onSubmit={guardar}>
            {campo('razon_social', 'Razón social')}{campo('ruc', 'RUC')}{campo('direccion', 'Dirección')}
            {campo('telefono', 'Teléfono')}{campo('correo', 'Correo')}
            {campo('cuenta_soles', 'Cuenta corriente en soles', 'Ej.: Cuenta corriente BCP soles N° …')}
            {campo('cuenta_detraccion', 'Cuenta de detracciones', 'Ej.: Banco de la Nación N° …')}
            {puedeEmpresa && <div className="toolbar" style={{ justifyContent: 'flex-end' }}><button className="btn pri" type="submit">Guardar</button></div>}
          </form>}
          <p className="sub">Se usan en las cotizaciones e informes. Las cuentas bancarias aparecen al pie de cada cotización.</p>
        </div>
        <div className="card"><h2>Apariencia</h2>
          <p className="sub" style={{ marginTop: 0 }}>Tema de la pantalla en este navegador.</p>
          <div className="toolbar">{(['system', 'light', 'dark'] as const).map(t =>
            <button key={t} className={`btn sm ${tema === t ? 'pri' : ''}`} onClick={() => setTema(t)}>{t === 'system' ? 'Sistema' : t === 'light' ? 'Claro' : 'Oscuro'}</button>)}</div>
          <p className="sub">El menú lateral se pliega a íconos con el botón redondo de su borde. Ctrl K abre el buscador del menú.</p>
        </div>
      </div>
      <div className="card"><h2>Usuarios y permisos</h2>
        <p className="sub" style={{ marginTop: 0 }}>Los permisos se aplican en la base de datos (RLS) según el rol de cada usuario.</p>
        <div className="tw"><table><thead><tr><th>Rol</th><th>Puede</th></tr></thead><tbody>
          {Object.entries(ROL).map(([k, [n, d]]) => <tr key={k}><td><b>{n}</b>{perfil?.rol === k && <> <span className="pill p-info">Tu rol</span></>}</td><td className="sub">{d}</td></tr>)}
        </tbody></table></div>
        {perfil?.rol === 'gerencia' && <>
          <h3 style={{ marginTop: 16 }}>Usuarios registrados</h3>
          <div className="tw"><table><thead><tr><th>Usuario</th><th>Nombre</th><th>Rol</th><th>Estado</th></tr></thead><tbody>
            {(usuarios.data ?? []).map(u => <tr key={u.id}><td><b>{u.usuario}</b></td><td>{u.nombre}</td><td>{ROL[u.rol]?.[0]}</td><td>{u.activo ? <span className="pill p-ok">Activo</span> : <span className="pill p-mute">Inactivo</span>}</td></tr>)}
          </tbody></table></div>
          <p className="sub">Para crear un usuario: Supabase → Authentication → Add user (correo usuario@dominio) y luego insertar su fila en la tabla perfiles (ver README).</p>
        </>}
      </div>
    </>
  )
}

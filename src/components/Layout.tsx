import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react'
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { AREAS, GRUPOS, secPath, type Area } from '../lib/catalogos'
import { useAuth } from '../lib/auth'
import { useTema } from '../lib/theme'
import { Icon } from './Icon'

/* ---------- Encabezado de página (migas + título) y avisos ---------- */
interface Head { title: string; crumbs: { label: string; to?: string }[] }
interface UiCtx { setHead: (h: Head) => void; toast: (t: string) => void }
const Ui = createContext<UiCtx>(null as unknown as UiCtx)
export const useUi = () => useContext(Ui)
/** Cada página declara su título y sus migas de pan */
export function usePageHead(title: string, crumbs: Head['crumbs'] = []) {
  const { setHead } = useUi()
  const key = title + crumbs.map(c => c.label).join('|')
  useEffect(() => { setHead({ title, crumbs }) }, [key]) // eslint-disable-line react-hooks/exhaustive-deps
}

const ROLES: Record<string, string> = { gerencia: 'Gerencia general', administracion: 'Administración y RR. HH.', comercial: 'Comercial y ventas', operaciones: 'Operaciones' }

export function Layout() {
  const [head, setHead] = useState<Head>({ title: '', crumbs: [] })
  const [msg, setMsg] = useState<string | null>(null)
  const [mini, setMini] = useState(() => localStorage.getItem('marc_menu_mini') === '1')
  const [open, setOpen] = useState(false)
  const timer = useRef<number>()
  const toast = useCallback((t: string) => { setMsg(t); clearTimeout(timer.current); timer.current = window.setTimeout(() => setMsg(null), 2600) }, [])
  const loc = useLocation()

  useEffect(() => { localStorage.setItem('marc_menu_mini', mini ? '1' : '0') }, [mini])
  useEffect(() => { setOpen(false); document.querySelector('main')?.scrollTo(0, 0) }, [loc.pathname])

  return (
    <Ui.Provider value={{ setHead, toast }}>
      <div className={`app ${mini ? 'mini' : ''}`}>
        <Sidebar mini={mini} setMini={setMini} open={open} />
        <main>
          <Topbar head={head} onMenu={() => setOpen(o => !o)} />
          <div className="page"><Outlet /></div>
        </main>
      </div>
      {msg && <div className="toast" role="status">{msg}</div>}
    </Ui.Provider>
  )
}

/* ---------- Menú lateral ---------- */
function Sidebar({ mini, setMini, open }: { mini: boolean; setMini: (v: boolean) => void; open: boolean }) {
  const loc = useLocation(); const nav = useNavigate()
  const [q, setQ] = useState('')
  const inputRef = useRef<HTMLInputElement>(null)
  const actual = AREAS.find(a => a.secs.some(s => s.path && loc.pathname.startsWith(s.path)) || a.secs.some(s => loc.pathname === `/seccion/${s.id}`))
  const [abiertas, setAbiertas] = useState<Set<string>>(() => new Set(actual ? [actual.id] : []))
  useEffect(() => { if (actual) setAbiertas(s => new Set(s).add(actual.id)) }, [actual?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); setMini(false); setTimeout(() => inputRef.current?.focus(), 50) }
    }
    window.addEventListener('keydown', h); return () => window.removeEventListener('keydown', h)
  }, [setMini])

  const ql = q.trim().toLowerCase()
  const filtrar = (a: Area) => a.secs.filter(s => !ql || s.n.toLowerCase().includes(ql) || a.n.toLowerCase().includes(ql))
  const toggle = (id: string) => { if (mini) return; setAbiertas(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n }) }

  return (
    <aside className={open ? 'open' : ''} aria-label="Menú principal">
      <div className="brand"><div className="plate">
        <img className="full" src="/logo.png" alt="MARC Distribution & Solutions Import E.I.R.L." />
        <img className="iso" src="/iso.png" alt="MARC" />
      </div></div>
      <button type="button" className="collapse" onClick={() => setMini(!mini)} aria-label="Plegar o desplegar el menú" title="Plegar o desplegar el menú">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4}><path d="M15 6l-6 6 6 6" /></svg>
      </button>
      <div className="side-scroll">
        <label className="msearch" title="Buscar en el menú (Ctrl K)" onClick={() => { if (mini) { setMini(false); setTimeout(() => inputRef.current?.focus(), 220) } }}>
          <Icon name="search" />
          <input ref={inputRef} value={q} placeholder="Buscar en el menú" aria-label="Buscar en el menú"
            onChange={e => setQ(e.target.value)}
            onKeyDown={e => {
              if (e.key === 'Escape') setQ('')
              if (e.key === 'Enter') { const a = AREAS.flatMap(filtrar)[0]; if (a) { setQ(''); nav(secPath(a)) } }
            }} />
          <span className="kbd">Ctrl K</span>
        </label>
        <NavLink to="/inicio" className={({ isActive }) => `navlink ${isActive ? 'on' : ''}`} title="Inicio"><Icon name="home" /><span className="lbl">Inicio</span></NavLink>
        {GRUPOS.map(([g, ids]) => {
          const areas = ids.map(id => AREAS.find(a => a.id === id)!).filter(a => filtrar(a).length)
          if (!areas.length) return null
          return (
            <div key={g}>
              <div className="grp">{g}</div>
              {areas.map(a => {
                const isOpen = !!ql || abiertas.has(a.id)
                return (
                  <div key={a.id} className={`area ${isOpen ? 'open' : ''} ${actual === a ? 'cur' : ''}`}>
                    <button type="button" className="area-btn" aria-expanded={isOpen} title={a.n} onClick={() => toggle(a.id)}>
                      <Icon name={a.id} /><span className="lbl">{a.n}</span><Icon name="chev" className="chev" />
                    </button>
                    <div className="subnav">
                      <div className="fly-h">{a.n}</div>
                      {filtrar(a).map(s => (
                        <NavLink key={s.id} to={secPath(s)} className={({ isActive }) => (isActive ? 'on' : '')}>
                          <span>{s.n}</span><span className={`tag ${s.path ? 'live' : ''}`}>{s.path ? 'Activo' : 'Fase ' + s.fase}</span>
                        </NavLink>
                      ))}
                    </div>
                  </div>
                )
              })}
            </div>
          )
        })}
      </div>
      <div className="side-foot">
        <NavLink to="/ajustes" className={({ isActive }) => `navlink ${isActive ? 'on' : ''}`} title="Ajustes"><Icon name="ajustes" /><span className="lbl">Ajustes</span></NavLink>
      </div>
    </aside>
  )
}

/* ---------- Barra superior ---------- */
function Topbar({ head, onMenu }: { head: Head; onMenu: () => void }) {
  const { perfil, salir } = useAuth()
  const { tema, siguiente } = useTema()
  const [umenu, setUmenu] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const h = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setUmenu(false) }
    document.addEventListener('click', h); return () => document.removeEventListener('click', h)
  }, [])
  const iniciales = (perfil?.nombre || '?').split(' ').map(x => x[0]).slice(0, 2).join('')
  const temaTxt = tema === 'system' ? 'Tema: sistema (clic para claro)' : tema === 'light' ? 'Tema: claro (clic para oscuro)' : 'Tema: oscuro (clic para sistema)'
  return (
    <div className="top">
      <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
        <button className="btn sm menu-btn" onClick={onMenu} aria-label="Abrir menú">Menú</button>
        <div>
          <nav className="crumb" aria-label="Ruta">
            <Link to="/inicio">Inicio</Link>
            {head.crumbs.map((c, i) => <Crumb key={i} {...c} />)}
            {head.title && <><span className="sep">›</span><b>{head.title}</b></>}
          </nav>
          <h1>{head.title}</h1>
        </div>
      </div>
      <div className="topr">
        <button type="button" className="themebtn" onClick={siguiente} title={temaTxt} aria-label={temaTxt}><Icon name={tema} /></button>
        <div style={{ position: 'relative' }} ref={ref}>
          <button type="button" className="uchip" aria-haspopup="true" aria-expanded={umenu} onClick={() => setUmenu(v => !v)}>
            <span className="av">{iniciales}</span><span>{perfil?.nombre.split(' ')[0]}</span><Icon name="down" />
          </button>
          {umenu && (
            <div className="umenu">
              <div className="who"><b>{perfil?.nombre}</b><div className="sub">{ROLES[perfil?.rol || ''] || ''} · {perfil?.usuario}</div></div>
              <Link to="/ajustes" onClick={() => setUmenu(false)}><Icon name="ajustes" /> Ajustes</Link>
              <button type="button" onClick={salir}><Icon name="logout" /> Cerrar sesión</button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
function Crumb({ label, to }: { label: string; to?: string }): ReactNode {
  return <><span className="sep">›</span>{to ? <Link to={to}>{label}</Link> : <span>{label}</span>}</>
}

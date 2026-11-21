import { Link, Navigate, useParams } from 'react-router-dom'
import { usePageHead } from '../components/Layout'
import { findSec, secPath } from '../lib/catalogos'

/** Ficha de una sección aún no construida: qué registrará, de dónde viene y qué indicadores alimenta. */
export function Seccion() {
  const { id } = useParams()
  const f = findSec(id || '')
  usePageHead(f?.s.n || 'Sección', f ? [{ label: f.a.n }] : [])
  if (!f) return <Navigate to="/inicio" replace />
  if (f.s.path) return <Navigate to={f.s.path} replace />
  const { a, s } = f
  return (
    <>
      <div className="card">
        <div className="toolbar" style={{ justifyContent: 'space-between' }}><h2 style={{ margin: 0 }}>{s.n}</h2><span className="pill p-warn">En diseño · Fase {s.fase}</span></div>
        <p style={{ maxWidth: '70ch', margin: '8px 0 0' }}>{s.que}</p>
      </div>
      <div className="spec">
        <div className="card"><h3>Qué se registrará</h3><div className="chips">{s.campos?.map(c => <span key={c} className="chip">{c}</span>)}</div></div>
        <div className="card"><h3>De dónde viene hoy</h3><p style={{ margin: 0 }}>{s.fuente}</p></div>
        <div className="card"><h3>Indicadores que alimenta</h3><div className="chips">{s.kpi?.map(c => <span key={c} className="chip">{c}</span>)}</div></div>
      </div>
      <div>
        <h3 style={{ font: '700 11px var(--display)', letterSpacing: '.8px', textTransform: 'uppercase', color: 'var(--muted)', margin: '6px 0 10px' }}>Otras secciones de {a.n}</h3>
        <div className="secs">{a.secs.filter(x => x.id !== s.id).map(x => (
          <Link key={x.id} className="card seccard" to={secPath(x)}><b>{x.n}</b><span className="sub">{x.path ? 'Activo' : 'Fase ' + x.fase}</span></Link>))}</div>
      </div>
    </>
  )
}

import { useMemo } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { usePageHead } from '../components/Layout'
import { PillEstado, PillPago } from '../components/Pills'
import { useQuery } from '../lib/useQuery'
import { traerCotizaciones } from '../lib/data'
import { ASESORES, ESTADOS, MESES, SERVICIOS } from '../lib/catalogos'
import { fdate, kmoney, money, monthOf } from '../lib/format'
import { useAuth } from '../lib/auth'

export function Cotizaciones() {
  usePageHead('Cotizaciones', [{ label: 'Comercial y ventas' }])
  const nav = useNavigate()
  const { puedeEditar } = useAuth()
  const [sp, setSp] = useSearchParams()
  const f = { q: sp.get('q') || '', mes: sp.get('mes') || '', est: sp.get('est') || '', as: sp.get('as') || '', serv: sp.get('serv') || '', anio: sp.has('anio') ? sp.get('anio') || '' : String(new Date().getFullYear()) }
  const set = (k: string, v: string) => { const n = new URLSearchParams(sp); v || k === 'anio' ? n.set(k, v) : n.delete(k); setSp(n, { replace: true }) }
  const { data, loading, error } = useQuery(traerCotizaciones, [])

  const anios = useMemo(() => [...new Set((data ?? []).map(r => r.fecha.slice(0, 4)))].sort().reverse(), [data])
  const R = useMemo(() => {
    const q = f.q.toLowerCase()
    return (data ?? []).filter(r => (!f.anio || r.fecha.startsWith(f.anio)) && (!f.mes || monthOf(r.fecha) === Number(f.mes)) && (!f.est || r.estado === f.est)
      && (!f.as || r.asesor === f.as) && (!f.serv || r.servicio === f.serv)
      && (!q || `${r.numero} ${r.cliente} ${r.descripcion ?? ''}`.toLowerCase().includes(q)))
  }, [data, f.q, f.mes, f.est, f.as, f.serv, f.anio])

  const acc = R.filter(r => r.estado === 'ACEPTADO'), rech = R.filter(r => r.estado === 'RECHAZADO')
  const dec = acc.length + rech.length
  const pen = (r: { moneda: string; venta: number }) => (r.moneda === 'USD' ? 0 : Number(r.venta))

  return (
    <>
      <div className="toolbar">
        <input className="grow" placeholder="Buscar por N°, cliente o descripción" value={f.q} onChange={e => set('q', e.target.value)} aria-label="Buscar" />
        <select style={{ width: 'auto' }} value={f.anio} onChange={e => set('anio', e.target.value)} aria-label="Año"><option value="">Todos los años</option>{anios.map(a => <option key={a}>{a}</option>)}</select>
        <select style={{ width: 'auto' }} value={f.mes} onChange={e => set('mes', e.target.value)} aria-label="Mes"><option value="">Todos los meses</option>{MESES.map((m, i) => <option key={m} value={i}>{m}</option>)}</select>
        <select style={{ width: 'auto' }} value={f.est} onChange={e => set('est', e.target.value)} aria-label="Estado"><option value="">Todos los estados</option>{ESTADOS.map(x => <option key={x}>{x}</option>)}</select>
        <select style={{ width: 'auto' }} value={f.as} onChange={e => set('as', e.target.value)} aria-label="Asesora"><option value="">Todas las asesoras</option>{ASESORES.map(x => <option key={x}>{x}</option>)}</select>
        <select style={{ width: 'auto' }} value={f.serv} onChange={e => set('serv', e.target.value)} aria-label="Servicio"><option value="">Todos los servicios</option>{SERVICIOS.map(x => <option key={x}>{x}</option>)}</select>
        {puedeEditar && <Link className="btn pri" to="/cotizaciones/nueva">+ Nueva cotización</Link>}
      </div>
      <div className="kpis">
        <div className="kpi"><span>Cotizaciones</span><b>{R.length}</b></div>
        <div className="kpi"><span>Aceptadas</span><b>{acc.length}</b><small>{dec ? Math.round((acc.length / dec) * 100) : 0}% de las respondidas</small></div>
        <div className="kpi"><span>Monto aceptado (S/, sin IGV)</span><b>{kmoney(acc.reduce((s, r) => s + pen(r), 0))}</b></div>
        <div className="kpi"><span>Rechazadas</span><b>{rech.length}</b><small>{kmoney(rech.reduce((s, r) => s + pen(r), 0))} cotizados</small></div>
      </div>
      {error && <div className="err">{error}</div>}
      <div className="card" style={{ padding: 0 }}><div className="tw"><table>
        <thead><tr><th>N° RQ</th><th>Fecha</th><th>Cliente</th><th>Servicio</th><th>Asesora</th><th className="num">Monto</th><th>Estado</th><th>Pago</th></tr></thead>
        <tbody>
          {loading && <tr><td colSpan={8} className="empty">Cargando…</td></tr>}
          {R.slice(0, 500).map(r => (
            <tr key={r.id} className="click" onClick={() => nav(`/cotizaciones/${r.id}`)}>
              <td style={{ whiteSpace: 'nowrap' }}><b>{r.numero}</b>{r.tipo_comprobante === 'LIBRE' && <> <span className="pill p-mute">LIBRE</span></>}</td>
              <td>{fdate(r.fecha)}</td>
              <td><div className="cli">{r.cliente}</div><div className="sub">{r.descripcion}</div></td>
              <td>{r.servicio}</td><td className="sub">{r.asesor || '—'}</td>
              <td className="num">{money(Number(r.venta), r.moneda)}</td>
              <td><PillEstado e={r.estado} /></td><td><PillPago e={r.estado_pago} /></td>
            </tr>))}
          {!loading && !R.length && <tr><td colSpan={8} className="empty">No hay cotizaciones con estos filtros</td></tr>}
        </tbody>
      </table></div></div>
      {R.length > 500 && <p className="sub">Se muestran 500 de {R.length}. Usa los filtros para acotar.</p>}
    </>
  )
}

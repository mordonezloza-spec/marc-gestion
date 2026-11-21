import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { usePageHead } from '../components/Layout'
import { BarChart } from '../components/BarChart'
import { PillPago } from '../components/Pills'
import { useQuery } from '../lib/useQuery'
import { traerCotizaciones } from '../lib/data'
import { proyectar } from '../lib/proyeccion'
import { fdate, kmoney, money, monthOf } from '../lib/format'
import type { Cotizacion } from '../lib/types'

const pen = (r: Cotizacion) => (r.moneda === 'USD' ? 0 : Number(r.venta))

/** Variación porcentual con signo, o null si no hay base */
const varPct = (a: number, b: number) => (b > 0 ? Math.round(((a - b) / b) * 100) : null)
function Delta({ v, label }: { v: number | null; label: string }) {
  if (v === null) return <small>Sin datos de {label}</small>
  return <small style={{ color: v >= 0 ? 'var(--ok)' : 'var(--bad)', fontWeight: 600 }}>{v >= 0 ? '▲' : '▼'} {Math.abs(v)}% vs {label}</small>
}

export function Inicio() {
  const hoy = new Date(), anioActual = hoy.getFullYear()
  const nav = useNavigate()
  const { data, loading, error } = useQuery(traerCotizaciones, [])
  const anios = useMemo(() => [...new Set((data ?? []).map(r => Number(r.fecha.slice(0, 4))))].sort((a, b) => b - a), [data])
  const [sel, setSel] = useState<number | null>(null)
  const anio = sel ?? anios[0] ?? anioActual
  usePageHead(`Tablero ejecutivo ${anio}`, [{ label: 'Inteligencia gerencial' }])

  const k = useMemo(() => {
    const todo = data ?? []
    // Ventas aceptadas por año y mes (todos los años cargados)
    const porAnio: Record<number, number[]> = {}
    todo.filter(r => r.estado === 'ACEPTADO').forEach(r => {
      const y = Number(r.fecha.slice(0, 4)), m = monthOf(r.fecha)
      ;(porAnio[y] ??= Array(12).fill(0))[m] += pen(r)
    })
    // Corte "mismo periodo": si es el año en curso, hasta el día de hoy del año anterior
    const corte = anio === anioActual ? hoy.toISOString().slice(5, 10) : '12-31'
    const enPeriodo = (r: Cotizacion) => r.fecha.slice(5, 10) <= corte
    const R = todo.filter(r => r.fecha.startsWith(String(anio)))
    const P = todo.filter(r => r.fecha.startsWith(String(anio - 1)) && enPeriodo(r))
    const acc = R.filter(r => r.estado === 'ACEPTADO'), accP = P.filter(r => r.estado === 'ACEPTADO')
    const conv = (X: Cotizacion[]) => { const a = X.filter(r => r.estado === 'ACEPTADO').length, d = a + X.filter(r => r.estado === 'RECHAZADO').length; return d ? Math.round((a / d) * 100) : 0 }
    const venta = acc.reduce((s, r) => s + pen(r), 0), ventaP = accP.reduce((s, r) => s + pen(r), 0)

    const meses = Array.from({ length: 12 }, () => ({ f: 0, l: 0 }))
    acc.forEach(r => { const m = monthOf(r.fecha); if (r.moneda !== 'USD') { meses[m].f += Number(r.subtotal); meses[m].l += Number(r.total_libre) } })
    const cerrados = anio < anioActual ? 12 : anio === anioActual ? hoy.getMonth() : 0
    const proy = proyectar(porAnio, anio, cerrados)
    const ultimoConDatos = Math.max(0, ...R.map(r => monthOf(r.fecha)))
    const mesesGrafico = proy.mensual.some(v => v > 0) ? 12 : ultimoConDatos + 1
    const prev = porAnio[anio - 1]

    const porCobrar = R.filter(r => r.estado_pago === 'PENDIENTE DE PAGO'), porFact = R.filter(r => r.estado_pago === 'PENDIENTE DE FACTURACIÓN')
    const cl: Record<string, number> = {}; acc.forEach(r => { cl[r.cliente] = (cl[r.cliente] || 0) + pen(r) })
    const top = Object.entries(cl).sort((a, b) => b[1] - a[1]).slice(0, 6)
    const sv: Record<string, number> = {}; acc.forEach(r => { const s = r.servicio || 'OTRO'; sv[s] = (sv[s] || 0) + pen(r) })
    // Pendientes de todos los años (lo que se debe hoy)
    const pendientes = todo.filter(r => r.estado_pago === 'PENDIENTE DE PAGO' || r.estado_pago === 'PENDIENTE DE FACTURACIÓN')
      .sort((a, b) => (b.dias_atraso ?? -999) - (a.dias_atraso ?? -999) || a.fecha.localeCompare(b.fecha)).slice(0, 10)
    const historico = Object.entries(porAnio).map(([y, v]) => ({ y: Number(y), total: v.reduce((a, b) => a + b, 0), meses: v.filter(x => x > 0).length })).sort((a, b) => a.y - b.y)
    return {
      R, acc, venta, ventaP, hayPrev: P.length > 0, conv: conv(R), convP: P.length ? conv(P) : null,
      cobrar: porCobrar.reduce((s, r) => s + Number(r.total), 0), nCobrar: porCobrar.length,
      facturar: porFact.reduce((s, r) => s + Number(r.venta), 0), nFact: porFact.length,
      sinResp: R.filter(r => r.estado === 'ENVIADO').length, meses, mesesGrafico, proy, prev, top,
      totCl: Object.values(cl).reduce((a, b) => a + b, 0), serv: Object.entries(sv).sort((a, b) => b[1] - a[1]).slice(0, 5), pendientes, historico,
    }
  }, [data, anio, anioActual]) // eslint-disable-line react-hooks/exhaustive-deps

  if (loading) return <div className="loading">Cargando indicadores…</div>
  if (error) return <div className="err">{error}</div>
  const maxS = Math.max(1, ...k.serv.map(s => s[1]))
  const etiquetaPrev = `${anio - 1}${anio === anioActual ? ' (mismo periodo)' : ''}`
  return (
    <>
      <div className="toolbar">
        <label style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>Año
          <select style={{ width: 'auto' }} value={anio} onChange={e => setSel(Number(e.target.value))}>{anios.map(a => <option key={a}>{a}</option>)}</select></label>
        <span className="sub">Años cargados: {k.historico.map(h => `${h.y} (${h.meses} meses)`).join(' · ') || '—'}</span>
      </div>
      <div className="kpis">
        <div className="kpi"><span>Ventas aceptadas (sin IGV)</span><b>{kmoney(k.venta)}</b><Delta v={k.hayPrev ? varPct(k.venta, k.ventaP) : null} label={etiquetaPrev} /></div>
        <div className="kpi"><span>Proyección de cierre {anio}</span><b>{kmoney(k.proy.total)}</b><small>{k.proy.metodo || 'Año cerrado'}</small></div>
        <div className="kpi"><span>Conversión de cotizaciones</span><b>{k.conv}%</b>{k.convP !== null ? <small>{k.convP}% en {etiquetaPrev}</small> : <small>{k.R.length} requerimientos</small>}</div>
        <div className="kpi"><span>Por cobrar (con IGV)</span><b>{kmoney(k.cobrar)}</b><small>{k.nCobrar} comprobantes</small></div>
        <div className="kpi"><span>Por facturar (sin IGV)</span><b>{kmoney(k.facturar)}</b><small>{k.nFact} servicios</small></div>
      </div>
      <div className="grid2">
        <div className="card"><h2>Ventas aceptadas por mes</h2>
          <BarChart data={k.meses} proy={k.proy.mensual} prev={k.prev} prevLabel={String(anio - 1)} meses={k.mesesGrafico} />
          {!k.proy.aniosBase.length && k.proy.metodo && <p className="sub" style={{ marginBottom: 0 }}>Cuando se carguen años anteriores completos, la proyección usará la estacionalidad real de cada mes y aparecerá la comparación con el año previo.</p>}
        </div>
        <div className="card"><h2>Concentración por cliente</h2>
          <div className="bars">{k.top.map(([c, v]) => (
            <div className="bar" key={c}><span title={c} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c}</span>
              <div className="t"><div style={{ width: `${(v / k.top[0][1]) * 100}%` }} /></div><b style={{ textAlign: 'right' }}>{Math.round((v / (k.totCl || 1)) * 100)}%</b></div>))}</div>
          <h3 style={{ marginTop: 16 }}>Por tipo de servicio</h3>
          <div className="bars">{k.serv.map(([s, v]) => (
            <div className="bar" key={s}><span>{s}</span><div className="t"><div style={{ width: `${(v / maxS) * 100}%` }} /></div><b style={{ textAlign: 'right' }}>{kmoney(v)}</b></div>))}</div>
        </div>
      </div>
      {k.historico.length > 1 && <div className="card"><h2>Evolución anual</h2>
        <div className="tw"><table><thead><tr><th>Año</th><th className="num">Venta aceptada</th><th className="num">Meses con datos</th><th className="num">Variación</th></tr></thead><tbody>
          {k.historico.map((h, i) => { const p = k.historico[i - 1]; const v = p && h.meses >= 12 && p.meses >= 12 ? varPct(h.total, p.total) : null
            return <tr key={h.y}><td><b>{h.y}</b></td><td className="num">{money(h.total)}</td><td className="num">{h.meses}</td><td className="num">{v === null ? <span className="sub">—</span> : <span style={{ color: v >= 0 ? 'var(--ok)' : 'var(--bad)' }}>{v >= 0 ? '+' : ''}{v}%</span>}</td></tr> })}
        </tbody></table></div></div>}
      <div className="card"><h2>Requiere atención: por cobrar y por facturar</h2>
        <div className="tw"><table><thead><tr><th>N° RQ</th><th>Fecha</th><th>Cliente</th><th className="num">Monto</th><th>Vencimiento</th><th>Pago</th></tr></thead><tbody>
          {k.pendientes.map(r => (
            <tr key={r.id} className="click" onClick={() => nav(`/cotizaciones/${r.id}`)}>
              <td style={{ whiteSpace: 'nowrap' }}>{r.numero}</td><td>{fdate(r.fecha)}</td><td className="cli">{r.cliente}</td>
              <td className="num">{money(Number(r.venta), r.moneda)}</td>
              <td>{r.fecha_vencimiento ? <>{fdate(r.fecha_vencimiento)}{(r.dias_atraso ?? 0) > 0 && <span className="pill p-bad" style={{ marginLeft: 6 }}>{r.dias_atraso} días</span>}</> : <span className="sub">—</span>}</td>
              <td><PillPago e={r.estado_pago} /></td></tr>))}
          {!k.pendientes.length && <tr><td colSpan={6} className="empty">Sin pendientes</td></tr>}
        </tbody></table></div></div>
    </>
  )
}

import { Fragment, useEffect, useState, type FormEvent } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { usePageHead, useUi } from '../components/Layout'
import { PillEstado } from '../components/Pills'
import { supabase } from '../lib/supabase'
import { ok, useQuery } from '../lib/useQuery'
import { useAuth } from '../lib/auth'
import { COND_DEF, COND_PAGO, MOTIVOS_RECHAZO, PAGOS } from '../lib/catalogos'
import { addDays, condDias, fdate, money } from '../lib/format'
import type { Costo, Cotizacion, Empresa, Item } from '../lib/types'

export function CotizacionDetalle() {
  const { id } = useParams()
  const nav = useNavigate()
  const { toast } = useUi()
  const { puedeEditar } = useAuth()
  const q = useQuery(async () => {
    const [c, it, co, em] = await Promise.all([
      supabase.from('v_cotizaciones').select('*').eq('id', id!).single(),
      supabase.from('cotizacion_items').select('*').eq('cotizacion_id', id!).order('orden'),
      supabase.from('cotizacion_costos').select('*').eq('cotizacion_id', id!),
      supabase.from('empresa').select('*').eq('id', 1).maybeSingle(),
    ])
    const cot = ok(c) as Cotizacion
    const rel = await supabase.from('cotizaciones').select('id,numero').in('id', [cot.version_de, cot.reemplazada_por].filter(Boolean) as string[])
    return { cot, items: ok(it) as Item[], costos: ok(co) as Costo[], empresa: (em.data as Empresa) ?? null, rel: rel.data ?? [] }
  }, [id])
  usePageHead(q.data ? `Cotización ${q.data.cot.numero}` : 'Cotización', [{ label: 'Comercial y ventas' }, { label: 'Cotizaciones', to: '/cotizaciones' }])
  const [rechazo, setRechazo] = useState<string | null>(null)

  if (q.loading) return <div className="loading">Cargando…</div>
  if (q.error || !q.data) return <div className="err">{q.error || 'No se encontró la cotización.'}</div>
  const { cot: r, items, costos, empresa, rel } = q.data
  const num = (x: string | null) => rel.find(z => z.id === x)?.numero ?? ''

  const actualizar = async (cambios: Partial<Cotizacion>, aviso: string) => {
    const { error } = await supabase.from('cotizaciones').update(cambios).eq('id', r.id)
    if (error) { toast('No se pudo guardar: ' + error.message); return }
    toast(aviso); q.reload()
  }

  const fact = r.tipo_comprobante !== 'LIBRE'
  const sub = Number(r.venta), igv = Number(r.igv)
  const lineas = items.length ? items : [{ descripcion: r.descripcion || 'Servicio', unidad: 'SERVICIO', cantidad: 1, precio_unitario: sub }]
  const venc = r.fecha_comprobante && r.condicion_pago ? addDays(r.fecha_comprobante, condDias(r.condicion_pago)) : null
  const atraso = r.dias_atraso ?? 0
  const pasos: [string, boolean, string][] = [
    ['Cotización enviada', true, fdate(r.fecha)],
    ['Respuesta del cliente', r.estado === 'ACEPTADO' || r.estado === 'RECHAZADO', r.estado === 'RECHAZADO' ? `Rechazada${r.motivo_rechazo ? ' · ' + r.motivo_rechazo : ''}` : r.estado === 'ACEPTADO' ? 'Aceptada' : 'Pendiente'],
    ['Orden de servicio / compra', !!r.orden_servicio, r.orden_servicio || '—'],
    ['Ejecución · partes diarios', !!r.partes, r.partes || '—'],
    ['Conformidad / HES', !!r.hes, r.hes || '—'],
    ['Comprobante', !!r.comprobante || !fact, r.comprobante ? `${r.comprobante} · ${fdate(r.fecha_comprobante)}` : !fact ? 'Libre (sin comprobante)' : '—'],
    ['Detracción', !Number(r.detraccion_pct) || r.estado_detraccion === 'CANCELADO' || r.estado_detraccion === 'NO APLICA',
      Number(r.detraccion_pct) ? `${Math.round(Number(r.detraccion_pct) * 100)}% · ${money(Number(r.detraccion_monto))} · ${r.estado_detraccion || 'PENDIENTE'}` : 'No aplica'],
    ['Cobro', r.estado_pago === 'CANCELADO', r.estado_pago === 'CANCELADO' ? `${money(r.monto_pagado)} · depositado ${fdate(r.fecha_pago)}${atraso > 0 ? ` · ${atraso} días después del vencimiento` : ''}`
      : venc ? `Vence ${fdate(venc)}${atraso > 0 ? ` · ${atraso} días vencida` : ''}` : (r.estado_pago || '—')],
  ]
  const cur = pasos.findIndex(p => !p[1])
  const cd = costos.reduce((s, x) => s + Number(x.monto), 0), ga = (cd * Number(r.gastos_adm_pct)) / 100, ut = sub - cd - ga
  const porRubro = costos.reduce<Record<string, number>>((a, x) => ((a[x.rubro] = (a[x.rubro] || 0) + Number(x.monto)), a), {})

  return (
    <>
      {r.reemplazada_por && <div className="hint no-print">Esta cotización fue reemplazada por la versión <Link to={`/cotizaciones/${r.reemplazada_por}`}>{num(r.reemplazada_por)}</Link>.</div>}
      {r.version_de && <div className="hint no-print">Nueva versión de la cotización <Link to={`/cotizaciones/${r.version_de}`}>{num(r.version_de)}</Link>.</div>}
      <div className="toolbar">
        <Link className="btn ghost" to="/cotizaciones">← Cotizaciones</Link><span className="grow" /><PillEstado e={r.estado} />
        {puedeEditar && r.estado !== 'ACEPTADO' && r.estado !== 'REEMPLAZADA' && <button className="btn sm" onClick={() => actualizar({ estado: 'ACEPTADO', estado_pago: r.estado_pago || 'PENDIENTE DE FACTURACIÓN' }, 'Marcada como aceptada')}>Marcar aceptada</button>}
        {puedeEditar && r.estado !== 'RECHAZADO' && r.estado !== 'REEMPLAZADA' && <button className="btn sm" onClick={() => setRechazo(MOTIVOS_RECHAZO[0])}>Marcar rechazada</button>}
        {puedeEditar && <button className="btn sm" onClick={() => nav(`/cotizaciones/${r.id}/editar`)}>Editar</button>}
        {puedeEditar && r.estado !== 'REEMPLAZADA' && <button className="btn sm" onClick={() => nav(`/cotizaciones/${r.id}/version`)}>Nueva versión</button>}
        <button className="btn sm" onClick={() => window.print()}>Imprimir / PDF</button>
      </div>
      <div className="grid2">
        <div className="doc">
          <div className="dh">
            <div><img src="/logo.png" alt="MARC" /><div style={{ color: '#5B6678', marginTop: 6 }}>RUC {empresa?.ruc} · {empresa?.direccion}</div></div>
            <div style={{ textAlign: 'right', whiteSpace: 'nowrap' }}><div style={{ color: '#5B6678', fontWeight: 600, fontSize: 11, letterSpacing: '.5px' }}>COTIZACIÓN N°</div><b className="no">{r.numero}</b></div>
          </div>
          <div className="meta">
            <span>Señores:</span><b>{r.cliente}</b><span>Fecha:</span><b>{fdate(r.fecha)}</b>
            <span>Atención:</span><span style={{ color: '#14213D' }}>{r.contacto || '—'}</span><span>Validez:</span><b>{r.validez_dias} días</b>
            <span>R.U.C.:</span><span style={{ color: '#14213D' }}>{r.ruc || '—'}</span><span>Moneda:</span><b>{r.moneda === 'USD' ? 'Dólares' : 'Soles'}</b>
            <span>Lugar:</span><span style={{ color: '#14213D' }}>{r.sede || '—'}</span><span /><span />
          </div>
          <p style={{ margin: '6px 0 10px' }}>En respuesta a su solicitud nos es grato saludarle y presentarle la siguiente propuesta económica:</p>
          <table><thead><tr><th>Ítem</th><th>Descripción</th><th className="num">Cant.</th><th className="num">Costo unit.</th><th className="num">Subtotal</th></tr></thead><tbody>
            {!r.mostrar_detalle
              ? <tr><td>1</td><td>{r.descripcion || lineas[0].descripcion}</td><td className="num">1</td><td className="num">{money(sub, r.moneda)}</td><td className="num">{money(sub, r.moneda)}</td></tr>
              : lineas.map((it, i) => <tr key={i}><td>{i + 1}</td><td>{it.descripcion}</td><td className="num">{Number(it.cantidad)} {it.unidad === 'HORAS' ? 'h' : ''}</td>
                <td className="num">{money(Number(it.precio_unitario), r.moneda)}</td><td className="num">{money(Number(it.cantidad) * Number(it.precio_unitario), r.moneda)}</td></tr>)}
          </tbody></table>
          <div className="totals" style={{ marginTop: 10 }}>
            <span>Sub total</span><b>{money(sub, r.moneda)}</b><span>I.G.V. 18%</span><b>{fact ? money(igv, r.moneda) : 'No aplica'}</b>
            <span className="big">Total</span><b className="big">{money(sub + igv, r.moneda)}</b>
          </div>
          <p style={{ whiteSpace: 'pre-line', marginTop: 14, fontSize: 12 }}><b>CONDICIONES COMERCIALES</b>{'\n'}{r.condiciones || COND_DEF}</p>
          {(empresa?.cuenta_soles || empresa?.cuenta_detraccion) && <p style={{ fontSize: 12 }}><b>DATOS BANCARIOS</b><br />{empresa?.cuenta_soles}<br />{empresa?.cuenta_detraccion}</p>}
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
          <div className="card"><h2>Seguimiento del servicio</h2><div className="steps">
            {pasos.map((p, i) => <div key={p[0]} className={`step ${p[1] ? 'done' : i === cur ? 'cur' : ''}`}><i>{p[1] ? '✓' : i + 1}</i><div><b>{p[0]}</b><div className="sub">{p[2]}</div></div></div>)}
          </div></div>
          <div className="card"><h2>Datos comerciales</h2><div className="sub" style={{ display: 'grid', gridTemplateColumns: 'auto 1fr', gap: '4px 12px' }}>
            <span>Asesora</span><b style={{ color: 'var(--ink)' }}>{r.asesor || '—'}</b>
            <span>Motivo</span><b style={{ color: 'var(--ink)' }}>{r.motivo_contacto || '—'}</b>
            <span>Servicio</span><b style={{ color: 'var(--ink)' }}>{r.servicio || '—'}</b>
            <span>Comprobante</span><b style={{ color: 'var(--ink)' }}>{r.tipo_comprobante}</b>
            {r.obs_comercial && <><span>Obs. comercial</span><b style={{ color: 'var(--ink)' }}>{r.obs_comercial}</b></>}
            <span>Origen</span><b style={{ color: 'var(--ink)' }}>{r.origen}</b>
          </div></div>
          {costos.length > 0 && <div className="card"><h2>Costeo estimado (interno)</h2><div className="sub" style={{ display: 'grid', gridTemplateColumns: '1fr auto', gap: '4px 12px' }}>
            {Object.entries(porRubro).map(([k, m]) => <Fragment key={k}><span>{k}</span><b style={{ color: 'var(--ink)', textAlign: 'right' }}>{money(m)}</b></Fragment>)}
            <span>Gastos administrativos {Number(r.gastos_adm_pct)}%</span><b style={{ color: 'var(--ink)', textAlign: 'right' }}>{money(ga)}</b>
            <span><b>Utilidad estimada</b></span><b style={{ textAlign: 'right', color: ut < 0 ? 'var(--bad)' : 'var(--ok)' }}>{money(ut)} · {sub ? Math.round((ut / sub) * 100) : 0}%</b>
          </div></div>}
        </div>
      </div>
      {puedeEditar && <Seguimiento r={r} venc={venc} onSave={c => actualizar(c, 'Seguimiento guardado')} />}
      {rechazo !== null && (
        <div className="modal"><div className="card"><h2>Motivo del rechazo</h2>
          <label>Motivo<select value={rechazo} onChange={e => setRechazo(e.target.value)}>{MOTIVOS_RECHAZO.map(m => <option key={m}>{m}</option>)}</select></label>
          <div className="toolbar" style={{ justifyContent: 'flex-end', marginTop: 12 }}>
            <button className="btn ghost" onClick={() => setRechazo(null)}>Cancelar</button>
            <button className="btn pri" onClick={async () => { await actualizar({ estado: 'RECHAZADO', motivo_rechazo: rechazo, estado_pago: 'RECHAZADO' }, 'Marcada como rechazada'); setRechazo(null) }}>Guardar</button>
          </div></div></div>)}
    </>
  )
}

function Seguimiento({ r, venc, onSave }: { r: Cotizacion; venc: string | null; onSave: (c: Partial<Cotizacion>) => void }) {
  const ini = () => ({
    orden_servicio: r.orden_servicio ?? '', partes: r.partes ?? '', hes: r.hes ?? '', condicion_pago: r.condicion_pago ?? '',
    comprobante: r.comprobante ?? '', fecha_comprobante: r.fecha_comprobante ?? '', estado_detraccion: r.estado_detraccion ?? '',
    estado_pago: r.estado_pago ?? '', fecha_pago: r.fecha_pago ?? '', monto_pagado: r.monto_pagado == null ? '' : String(r.monto_pagado),
    obs_cobro: r.obs_cobro ?? '', obs_comercial: r.obs_comercial ?? '',
  })
  const [s, setS] = useState(ini)
  useEffect(() => { setS(ini()) }, [r]) // eslint-disable-line react-hooks/exhaustive-deps
  const set = (k: keyof ReturnType<typeof ini>, v: string) => setS(x => ({ ...x, [k]: v }))
  const enviar = (e: FormEvent) => {
    e.preventDefault()
    const nul = (v: string) => (v.trim() === '' ? null : v.trim())
    onSave({
      orden_servicio: nul(s.orden_servicio), partes: nul(s.partes), hes: nul(s.hes), condicion_pago: nul(s.condicion_pago),
      comprobante: nul(s.comprobante), fecha_comprobante: nul(s.fecha_comprobante),
      estado_detraccion: (nul(s.estado_detraccion) as Cotizacion['estado_detraccion']), estado_pago: (nul(s.estado_pago) as Cotizacion['estado_pago']),
      fecha_pago: nul(s.fecha_pago), monto_pagado: s.monto_pagado === '' ? null : Number(s.monto_pagado), obs_cobro: nul(s.obs_cobro), obs_comercial: nul(s.obs_comercial),
    })
  }
  return (
    <div className="card no-print"><h2>Actualizar seguimiento</h2>
      <form className="form" onSubmit={enviar} noValidate>
        <label>N° orden de servicio / compra<input value={s.orden_servicio} onChange={e => set('orden_servicio', e.target.value)} /></label>
        <label>N° partes diarios<input value={s.partes} onChange={e => set('partes', e.target.value)} placeholder="Ej.: 856, 858" /></label>
        <label>N° HES / conformidad<input value={s.hes} onChange={e => set('hes', e.target.value)} /></label>
        <label>Condición de pago<select value={s.condicion_pago} onChange={e => set('condicion_pago', e.target.value)}><option value="">—</option>{COND_PAGO.map(x => <option key={x}>{x}</option>)}</select></label>
        <label>N° comprobante<input value={s.comprobante} onChange={e => set('comprobante', e.target.value)} placeholder="F001-1855" /></label>
        <label>Fecha de comprobante<input type="date" value={s.fecha_comprobante} onChange={e => set('fecha_comprobante', e.target.value)} /></label>
        <label>Estado de detracción<select value={s.estado_detraccion} onChange={e => set('estado_detraccion', e.target.value)}><option value="">—</option>{['PENDIENTE', 'CANCELADO', 'NO APLICA'].map(x => <option key={x}>{x}</option>)}</select></label>
        <label>Estado de pago<select value={s.estado_pago} onChange={e => set('estado_pago', e.target.value)}><option value="">—</option>{PAGOS.map(x => <option key={x}>{x}</option>)}</select></label>
        <label>Vencimiento (según condición)<input readOnly value={venc ? fdate(venc) : 'Se calcula con la fecha de comprobante y la condición'} /></label>
        <label>Fecha real de depósito<input type="date" value={s.fecha_pago} onChange={e => set('fecha_pago', e.target.value)} /></label>
        <label>Monto depositado<input type="number" step="0.01" value={s.monto_pagado} onChange={e => set('monto_pagado', e.target.value)} /></label>
        <span />
        <label className="s2">Observación de cobro (demoras, descuentos)<input value={s.obs_cobro} onChange={e => set('obs_cobro', e.target.value)} /></label>
        <label className="s2">Observación comercial (negociación, por qué no se cerró)<input value={s.obs_comercial} onChange={e => set('obs_comercial', e.target.value)} /></label>
        <div className="s4 toolbar" style={{ justifyContent: 'flex-end' }}><button className="btn pri" type="submit">Guardar seguimiento</button></div>
      </form>
    </div>
  )
}

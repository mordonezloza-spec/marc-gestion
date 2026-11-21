import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { usePageHead, useUi } from '../components/Layout'
import { supabase } from '../lib/supabase'
import { traerTodo } from '../lib/data'
import { ok, useQuery } from '../lib/useQuery'
import { useAuth } from '../lib/auth'
import { ASESORES, COND_DEF, COSTO_CAT, DETR_DEF, DETR_TXT, MOTIVOS, SERVICIOS, UNIDADES } from '../lib/catalogos'
import { hoyISO, money, n } from '../lib/format'
import type { Cliente, Costo, Cotizacion, Item, Tarifa } from '../lib/types'

type Modo = 'nueva' | 'editar' | 'version'

export function CotizacionForm({ modo }: { modo: Modo }) {
  const { id } = useParams()
  const nav = useNavigate()
  const { toast } = useUi()
  const { puedeEditar } = useAuth()

  const maestros = useQuery(async () => {
    const [clientes, tarifas] = await Promise.all([
      traerTodo<Cliente>('clientes', 'id,razon_social,ruc,direccion,rubro,condicion_pago', { col: 'razon_social' }),
      traerTodo<Tarifa>('tarifas', '*'),
    ])
    return { clientes, tarifas }
  }, [])
  const base = useQuery(async () => {
    if (modo === 'nueva' || !id) return null
    const [c, it, co] = await Promise.all([
      supabase.from('v_cotizaciones').select('*').eq('id', id).single(),
      supabase.from('cotizacion_items').select('*').eq('cotizacion_id', id).order('orden'),
      supabase.from('cotizacion_costos').select('*').eq('cotizacion_id', id),
    ])
    return { cot: ok(c) as Cotizacion, items: ok(it) as Item[], costos: ok(co) as Costo[] }
  }, [id, modo])

  const titulo = modo === 'nueva' ? 'Nueva cotización' : modo === 'editar' ? `Editar ${base.data?.cot.numero ?? ''}` : `Nueva versión de ${base.data?.cot.numero ?? ''}`
  usePageHead(titulo, [{ label: 'Comercial y ventas' }, { label: 'Cotizaciones', to: '/cotizaciones' }])

  if (!puedeEditar) return <div className="card">Tu usuario no tiene permiso para registrar cotizaciones.</div>
  if (maestros.loading || base.loading) return <div className="loading">Cargando…</div>
  if (maestros.error || base.error) return <div className="err">{maestros.error || base.error}</div>
  return <Formulario modo={modo} clientes={maestros.data!.clientes} tarifas={maestros.data!.tarifas} base={base.data}
    onSaved={(nid, num) => { toast(modo === 'editar' ? 'Cotización actualizada' : `Cotización ${num} registrada`); nav(`/cotizaciones/${nid}`) }} />
}

function Formulario({ modo, clientes, tarifas, base, onSaved }: {
  modo: Modo; clientes: Cliente[]; tarifas: Tarifa[]
  base: { cot: Cotizacion; items: Item[]; costos: Costo[] } | null
  onSaved: (id: string, numero: string) => void
}) {
  const c0 = base?.cot
  const [f, setF] = useState({
    fecha: modo === 'editar' && c0 ? c0.fecha : hoyISO(),
    asesor: c0?.asesor || ASESORES[0], motivo_contacto: c0?.motivo_contacto || MOTIVOS[0],
    cliente: c0?.cliente || '', ruc: c0?.ruc || '', direccion: c0?.direccion || '', sede: c0?.sede || '', contacto: c0?.contacto || '', correo: c0?.correo || '',
    servicio: c0?.servicio || 'RETROEXCAVADORA', tipo_comprobante: c0?.tipo_comprobante || 'FACTURADO', moneda: c0?.moneda || 'PEN',
    tipo_cambio: c0?.tipo_cambio ?? 3.75, validez_dias: c0?.validez_dias ?? 7, descripcion: c0?.descripcion || '',
    mostrar_detalle: c0?.mostrar_detalle ?? true, condiciones: c0?.condiciones || COND_DEF, gastos_adm_pct: c0?.gastos_adm_pct ?? 10,
  })
  const set = <K extends keyof typeof f>(k: K, v: (typeof f)[K]) => setF(s => ({ ...s, [k]: v }))
  const [items, setItems] = useState<Item[]>(() => base?.items.length ? base.items.map(x => ({ ...x }))
    : c0 ? [{ descripcion: c0.descripcion || '', unidad: 'SERVICIO', cantidad: 1, precio_unitario: Number(c0.venta) }]
      : [{ descripcion: '', unidad: 'HORAS', cantidad: 1, precio_unitario: 0 }])
  const [costos, setCostos] = useState<Costo[]>(() => (base?.costos ?? []).map(x => ({ ...x })))
  const [dpManual, setDpManual] = useState<number | null>(modo === 'editar' && c0 ? Number(c0.detraccion_pct) : null)
  const [error, setError] = useState<string | null>(null)
  const [guardando, setGuardando] = useState(false)

  const cli = useMemo(() => clientes.find(c => c.razon_social.toUpperCase() === f.cliente.trim().toUpperCase()), [clientes, f.cliente])
  useEffect(() => { if (cli) setF(s => ({ ...s, ruc: s.ruc || cli.ruc || '', direccion: s.direccion || cli.direccion || '' })) }, [cli])
  const tarifa = cli ? tarifas.find(t => t.cliente_id === cli.id && t.servicio === f.servicio && t.activo) : undefined

  const fact = f.tipo_comprobante === 'FACTURADO'
  const sub = items.reduce((s, it) => s + n(it.cantidad) * n(it.precio_unitario), 0)
  const igv = fact ? sub * 0.18 : 0, tot = sub + igv
  const totPEN = f.moneda === 'USD' ? tot * n(f.tipo_cambio) : tot
  const dp = dpManual ?? (fact && totPEN > 700 ? DETR_DEF(f.servicio) : 0)
  const dm = Math.round(totPEN * dp)
  const horas = items.filter(i => i.unidad === 'HORAS').reduce((s, i) => s + n(i.cantidad), 0)
  const cd = costos.reduce((s, x) => s + n(x.monto), 0), ga = (cd * n(f.gastos_adm_pct)) / 100, ut = sub - cd - ga

  const aplicarTarifa = () => {
    if (!tarifa) return
    setItems(its => { const c = [...its]; const x = { ...c[0] }; x.unidad = 'HORAS'; x.precio_unitario = Number(tarifa.tarifa)
      if (tarifa.horas_minimas && n(x.cantidad) < Number(tarifa.horas_minimas)) x.cantidad = Number(tarifa.horas_minimas)
      if (!x.descripcion) x.descripcion = f.descripcion || `SERV. DE ALQUILER DE ${tarifa.servicio}`
      c[0] = x; return c })
  }
  const setItem = (i: number, k: keyof Item, v: string) =>
    setItems(its => its.map((x, j) => (j === i ? { ...x, [k]: k === 'cantidad' || k === 'precio_unitario' ? Number(v) || 0 : v } : x)))
  const setCosto = (i: number, k: keyof Costo, v: string) =>
    setCostos(cs => cs.map((x, j) => (j === i ? { ...x, [k]: k === 'monto' ? Number(v) || 0 : v } : x)))

  const guardar = async (e: FormEvent) => {
    e.preventDefault(); setError(null)
    if (!f.cliente.trim()) { setError('Indica el cliente.'); return }
    if (!items.some(i => n(i.cantidad) * n(i.precio_unitario) > 0)) { setError('Agrega al menos un ítem con monto.'); return }
    setGuardando(true)
    const p = {
      id: modo === 'editar' ? c0?.id : null, version_de: modo === 'version' ? c0?.id : null,
      cliente_id: cli?.id ?? null, cliente_nombre: f.cliente.trim(), fecha: f.fecha, ruc: f.ruc.trim() || null, direccion: f.direccion.trim() || null,
      sede: f.sede, contacto: f.contacto, correo: f.correo, asesor: f.asesor, motivo_contacto: f.motivo_contacto, servicio: f.servicio,
      tipo_comprobante: f.tipo_comprobante, moneda: f.moneda, tipo_cambio: f.moneda === 'USD' ? f.tipo_cambio : null, validez_dias: f.validez_dias,
      descripcion: f.descripcion.trim() || items[0].descripcion, mostrar_detalle: f.mostrar_detalle, condiciones: f.condiciones,
      subtotal: fact ? sub : 0, total_libre: fact ? 0 : sub, detraccion_pct: dp, detraccion_monto: dm, gastos_adm_pct: f.gastos_adm_pct,
      items: items.filter(i => i.descripcion || n(i.cantidad) * n(i.precio_unitario)).map(({ descripcion, unidad, cantidad, precio_unitario }) => ({ descripcion, unidad, cantidad, precio_unitario })),
      costos: costos.filter(x => x.detalle || n(x.monto)).map(({ rubro, detalle, monto }) => ({ rubro, detalle, monto })),
    }
    const { data, error } = await supabase.rpc('guardar_cotizacion', { p })
    if (error) { setGuardando(false); setError(error.message); return }
    const { data: c } = await supabase.from('cotizaciones').select('numero').eq('id', data as string).single()
    setGuardando(false)
    onSaved(data as string, c?.numero ?? '')
  }

  return (
    <form className="page" style={{ padding: 0 }} onSubmit={guardar} noValidate>
      {modo === 'version' && <div className="hint">Nueva versión a pedido del cliente. La cotización {c0?.numero} quedará como <b>reemplazada</b> y enlazada a esta.</div>}
      <div className="card"><h2>1 · Datos generales</h2><div className="form">
        <label>N° de cotización<input value={modo === 'editar' ? c0?.numero : 'Se asigna al registrar'} readOnly /></label>
        <label>Fecha<input type="date" value={f.fecha} onChange={e => set('fecha', e.target.value)} /></label>
        <label>Asesora<select value={f.asesor} onChange={e => set('asesor', e.target.value)}>{ASESORES.map(a => <option key={a}>{a}</option>)}</select></label>
        <label>Motivo de contacto<select value={f.motivo_contacto} onChange={e => set('motivo_contacto', e.target.value)}>{MOTIVOS.map(a => <option key={a}>{a}</option>)}</select></label>
      </div></div>

      <div className="card"><h2>2 · Cliente</h2><div className="form">
        <label className="s2">Razón social<input list="cliList" value={f.cliente} onChange={e => set('cliente', e.target.value)} placeholder="Escribe para buscar o registrar uno nuevo" autoComplete="off" /></label>
        <datalist id="cliList">{clientes.map(c => <option key={c.id} value={c.razon_social} />)}</datalist>
        <label>RUC<input value={f.ruc} onChange={e => set('ruc', e.target.value)} inputMode="numeric" maxLength={11} /></label>
        <label>Sede / lugar del servicio<input value={f.sede} onChange={e => set('sede', e.target.value)} placeholder="Supe Puerto, Barranca…" /></label>
        <label className="s2">Dirección fiscal<input value={f.direccion} onChange={e => set('direccion', e.target.value)} /></label>
        <label>Contacto<input value={f.contacto} onChange={e => set('contacto', e.target.value)} /></label>
        <label>Correo / teléfono<input value={f.correo} onChange={e => set('correo', e.target.value)} /></label>
        {f.cliente.trim() && <div className="s4">{cli ? <span className="sub">Cliente registrado{cli.ruc ? ` · RUC ${cli.ruc}` : ''}.</span>
          : <div className="hint">Cliente nuevo: se creará en el maestro de clientes al registrar la cotización.</div>}</div>}
      </div></div>

      <div className="card"><h2>3 · Servicio</h2><div className="form">
        <label>Tipo de servicio<select value={f.servicio} onChange={e => set('servicio', e.target.value)}>{SERVICIOS.map(a => <option key={a}>{a}</option>)}</select></label>
        <label>Comprobante<select value={f.tipo_comprobante} onChange={e => set('tipo_comprobante', e.target.value as 'FACTURADO' | 'LIBRE')}><option>FACTURADO</option><option>LIBRE</option></select></label>
        <label>Moneda<select value={f.moneda} onChange={e => set('moneda', e.target.value as 'PEN' | 'USD')}><option value="PEN">Soles</option><option value="USD">Dólares</option></select></label>
        <label>Validez de la oferta (días)<input type="number" min={1} value={f.validez_dias} onChange={e => set('validez_dias', Number(e.target.value))} /></label>
        <label className="s4">Descripción del servicio<input value={f.descripcion} onChange={e => set('descripcion', e.target.value)} placeholder="Ej.: Servicio de alquiler de camión grúa (operador + rigger) – izaje de planchas" /></label>
        <div className="s4">
          {tarifa ? <div className="hint">Tarifa vigente de <b>{cli!.razon_social}</b> para {tarifa.servicio.toLowerCase()}: <b>{money(Number(tarifa.tarifa))}{tarifa.servicio === 'TRASLADO' ? '' : '/h'}</b>
            {tarifa.horas_minimas ? ` · mínimo ${tarifa.horas_minimas} h` : ''}{tarifa.cobra_recorrido ? ' · cobra recorrido' : ''}{tarifa.incluye_almuerzo ? ' · incluye almuerzo del operador' : ''}
            <button type="button" className="btn sm" style={{ marginLeft: 8 }} onClick={aplicarTarifa}>Aplicar tarifa</button></div>
            : cli ? <span className="sub">No hay tarifa registrada para este cliente y servicio.</span> : null}
          {tarifa?.horas_minimas && horas > 0 && horas < Number(tarifa.horas_minimas) &&
            <div className="warnbox" style={{ marginTop: 6 }}>Este cliente tiene un mínimo de {tarifa.horas_minimas} horas; la cotización suma {horas} h.</div>}
        </div>
      </div></div>

      <div className="card"><h2>4 · Detalle y montos</h2>
        <div className="tw"><table>
          <thead><tr><th style={{ minWidth: 240 }}>Descripción</th><th style={{ width: 130 }}>Unidad</th><th className="num" style={{ width: 110 }}>Cantidad</th><th className="num" style={{ width: 130 }}>P. unitario</th><th className="num">Subtotal</th><th /></tr></thead>
          <tbody>{items.map((it, i) => (
            <tr key={i}>
              <td><input value={it.descripcion} onChange={e => setItem(i, 'descripcion', e.target.value)} aria-label={`Descripción ítem ${i + 1}`} /></td>
              <td><select value={it.unidad} onChange={e => setItem(i, 'unidad', e.target.value)} aria-label="Unidad">{UNIDADES.map(u => <option key={u}>{u}</option>)}</select></td>
              <td><input type="number" step="0.5" style={{ textAlign: 'right' }} value={it.cantidad} onChange={e => setItem(i, 'cantidad', e.target.value)} aria-label="Cantidad" /></td>
              <td><input type="number" step="0.01" style={{ textAlign: 'right' }} value={it.precio_unitario} onChange={e => setItem(i, 'precio_unitario', e.target.value)} aria-label="Precio unitario" /></td>
              <td className="num">{money(n(it.cantidad) * n(it.precio_unitario), f.moneda)}</td>
              <td>{items.length > 1 && <button type="button" className="btn sm ghost danger" onClick={() => setItems(its => its.filter((_, j) => j !== i))} aria-label="Quitar ítem">✕</button>}</td>
            </tr>))}</tbody>
        </table></div>
        <div className="toolbar" style={{ marginTop: 8 }}><button type="button" className="btn sm" onClick={() => setItems(its => [...its, { descripcion: '', unidad: 'HORAS', cantidad: 1, precio_unitario: 0 }])}>+ Agregar ítem</button></div>
        <div style={{ display: 'flex', gap: 18, flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'flex-start', marginTop: 14 }}>
          <div className="form" style={{ gridTemplateColumns: 'repeat(2,minmax(0,170px))' }}>
            <label>% Detracción<select value={String(dp)} onChange={e => setDpManual(Number(e.target.value))}>{[0, 0.04, 0.1, 0.12].map(p => <option key={p} value={String(p)}>{p * 100}%</option>)}</select></label>
            {f.moneda === 'USD' && <label>Tipo de cambio<input type="number" step="0.001" value={f.tipo_cambio} onChange={e => set('tipo_cambio', Number(e.target.value))} /></label>}
          </div>
          <div className="totals">
            <span>Sub total</span><b>{money(sub, f.moneda)}</b>
            <span>I.G.V. 18%</span><b>{fact ? money(igv, f.moneda) : 'No aplica'}</b>
            <span className="big">Total</span><b className="big">{money(tot, f.moneda)}</b>
            <span>Detracción {dp * 100}%</span><b>{dp ? money(dm) : '—'}</b>
            <span>Neto a recibir</span><b>{money(totPEN - dm)}</b>
          </div>
        </div>
        <div className="sub" style={{ marginTop: 6 }}>{!fact ? 'Servicio libre: no aplica detracción.' : totPEN <= 700 ? 'Total hasta S/ 700: no aplica detracción.' : `Detracción sugerida por el tipo de servicio (${DETR_TXT(f.servicio)}). Se puede cambiar.`}</div>
        <label style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 10, fontSize: 13, color: 'var(--ink)' }}>
          <input type="checkbox" style={{ width: 'auto' }} checked={f.mostrar_detalle} onChange={e => set('mostrar_detalle', e.target.checked)} />
          Mostrar al cliente el detalle de los ítems (si se desmarca, la cotización muestra solo el servicio y el monto total)
        </label>
      </div>

      <div className="card"><h2>5 · Costeo estimado <span className="sub" style={{ fontWeight: 600 }}>(uso interno, no lo ve el cliente)</span></h2>
        <div className="tw"><table>
          <thead><tr><th style={{ width: 240 }}>Rubro</th><th>Detalle / proveedor</th><th className="num" style={{ width: 150 }}>Monto (S/)</th><th /></tr></thead>
          <tbody>
            {costos.map((x, i) => (
              <tr key={i}>
                <td><select value={x.rubro} onChange={e => setCosto(i, 'rubro', e.target.value)} aria-label="Rubro">{COSTO_CAT.map(c => <option key={c}>{c}</option>)}</select></td>
                <td><input value={x.detalle ?? ''} onChange={e => setCosto(i, 'detalle', e.target.value)} placeholder="Ej.: 60 bolquetadas de roca a S/ 1,600" aria-label="Detalle" /></td>
                <td><input type="number" step="0.01" style={{ textAlign: 'right' }} value={x.monto} onChange={e => setCosto(i, 'monto', e.target.value)} aria-label="Monto" /></td>
                <td><button type="button" className="btn sm ghost danger" onClick={() => setCostos(cs => cs.filter((_, j) => j !== i))} aria-label="Quitar costo">✕</button></td>
              </tr>))}
            {!costos.length && <tr><td colSpan={4} className="sub">Opcional. Agrega los costos para ver la utilidad estimada.</td></tr>}
          </tbody>
        </table></div>
        <div className="toolbar" style={{ marginTop: 8 }}>
          <button type="button" className="btn sm" onClick={() => setCostos(cs => [...cs, { rubro: 'PERSONAL', detalle: '', monto: 0 }])}>+ Agregar costo</button>
          <span className="grow" />
          <label style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>Gastos administrativos %<input type="number" style={{ width: 80 }} value={f.gastos_adm_pct} onChange={e => set('gastos_adm_pct', Number(e.target.value))} /></label>
        </div>
        {cd > 0 && <div className="totals" style={{ marginTop: 10 }}>
          <span>Costo directo</span><b>{money(cd)}</b><span>Gastos administrativos</span><b>{money(ga)}</b>
          <span>Precio (sub total)</span><b>{money(sub)}</b>
          <span className="big">Utilidad estimada</span><b className="big" style={{ color: ut < 0 ? 'var(--bad)' : 'var(--ok)' }}>{money(ut)} · {sub ? Math.round((ut / sub) * 100) : 0}%</b>
        </div>}
      </div>

      <div className="card"><h2>6 · Condiciones comerciales</h2><textarea value={f.condiciones} onChange={e => set('condiciones', e.target.value)} aria-label="Condiciones comerciales" /></div>
      {error && <div className="err">{error}</div>}
      <div className="toolbar" style={{ justifyContent: 'flex-end' }}>
        <Link className="btn ghost" to={c0 ? `/cotizaciones/${c0.id}` : '/cotizaciones'}>Cancelar</Link>
        <button className="btn pri" type="submit" disabled={guardando}>{guardando ? 'Guardando…' : modo === 'editar' ? 'Guardar cambios' : modo === 'version' ? 'Registrar nueva versión' : 'Registrar cotización'}</button>
      </div>
    </form>
  )
}

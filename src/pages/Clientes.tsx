import { useMemo, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { usePageHead, useUi } from '../components/Layout'
import { supabase } from '../lib/supabase'
import { traerTodo } from '../lib/data'
import { useQuery } from '../lib/useQuery'
import { useAuth } from '../lib/auth'
import { COND_PAGO } from '../lib/catalogos'
import { fdate, money } from '../lib/format'
import type { ClienteResumen } from '../lib/types'

const vacio = { id: '', razon_social: '', ruc: '', direccion: '', rubro: '', condicion_pago: '' }

export function Clientes() {
  usePageHead('Clientes', [{ label: 'Comercial y ventas' }])
  const nav = useNavigate()
  const { toast } = useUi()
  const { puedeEditar } = useAuth()
  const [q, setQ] = useState('')
  const [ed, setEd] = useState<typeof vacio | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const { data, loading, error, reload } = useQuery(() => traerTodo<ClienteResumen>('v_clientes_resumen', '*'), [])

  const L = useMemo(() => {
    const ql = q.toLowerCase()
    return (data ?? []).filter(c => !ql || c.razon_social.toLowerCase().includes(ql) || (c.ruc || '').includes(ql))
      .sort((a, b) => Number(b.venta_pen) - Number(a.venta_pen) || a.razon_social.localeCompare(b.razon_social))
  }, [data, q])
  const sinRuc = (data ?? []).filter(c => !c.ruc).length

  const guardar = async (e: FormEvent) => {
    e.preventDefault(); if (!ed) return
    if (!ed.razon_social.trim()) { setErr('Indica la razón social.'); return }
    if (ed.ruc && !/^\d{11}$/.test(ed.ruc.trim())) { setErr('El RUC debe tener 11 dígitos.'); return }
    const fila = { razon_social: ed.razon_social.trim().toUpperCase(), ruc: ed.ruc.trim() || null, direccion: ed.direccion.trim() || null,
      rubro: ed.rubro.trim() || null, condicion_pago: ed.condicion_pago || null }
    const { error } = ed.id ? await supabase.from('clientes').update(fila).eq('id', ed.id) : await supabase.from('clientes').insert(fila)
    if (error) { setErr(error.message.includes('duplicate') ? 'Ya existe un cliente con ese nombre o RUC.' : error.message); return }
    setEd(null); setErr(null); toast(ed.id ? 'Cliente actualizado' : 'Cliente registrado'); reload()
  }

  return (
    <>
      <div className="toolbar">
        <input className="grow" placeholder="Buscar cliente o RUC" value={q} onChange={e => setQ(e.target.value)} aria-label="Buscar cliente" />
        {puedeEditar && <button className="btn pri" onClick={() => { setEd({ ...vacio }); setErr(null) }}>+ Nuevo cliente</button>}
      </div>
      {sinRuc > 0 && <div className="hint">{sinRuc} clientes aún no tienen RUC. Completarlo evita duplicados y permite leer las facturas automáticamente.</div>}
      {error && <div className="err">{error}</div>}
      <div className="card" style={{ padding: 0 }}><div className="tw"><table>
        <thead><tr><th>Cliente</th><th>RUC</th><th>Condición de pago</th><th className="num">Cotizaciones</th><th className="num">Aceptadas</th><th className="num">Venta (S/)</th><th>Última</th><th>Tarifas</th>{puedeEditar && <th />}</tr></thead>
        <tbody>
          {loading && <tr><td colSpan={9} className="empty">Cargando…</td></tr>}
          {L.map(c => (
            <tr key={c.id} className="click" onClick={() => nav(`/cotizaciones?q=${encodeURIComponent(c.razon_social)}&anio=`)}>
              <td className="cli">{c.razon_social}</td><td className="sub">{c.ruc || 'Falta RUC'}</td><td className="sub">{c.condicion_pago || '—'}</td>
              <td className="num">{c.cotizaciones}</td><td className="num">{c.aceptadas}</td><td className="num">{Number(c.venta_pen) ? money(Number(c.venta_pen)) : '—'}</td>
              <td>{fdate(c.ultima_cotizacion)}</td>
              <td>{(c.servicios_tarifa || []).map(s => <span key={s} className="pill p-mute" style={{ marginRight: 4 }}>{s === 'CAMION GRUA' ? 'GRÚA' : s === 'RETROEXCAVADORA' ? 'RETRO' : s}</span>)}</td>
              {puedeEditar && <td><button className="btn sm" onClick={e => { e.stopPropagation(); setErr(null); setEd({ id: c.id, razon_social: c.razon_social, ruc: c.ruc || '', direccion: c.direccion || '', rubro: c.rubro || '', condicion_pago: c.condicion_pago || '' }) }}>Editar</button></td>}
            </tr>))}
        </tbody>
      </table></div></div>
      {ed && (
        <div className="modal"><div className="card"><h2>{ed.id ? 'Editar cliente' : 'Nuevo cliente'}</h2>
          <form className="form" style={{ gridTemplateColumns: '1fr' }} onSubmit={guardar} noValidate>
            <label>Razón social<input value={ed.razon_social} onChange={e => setEd({ ...ed, razon_social: e.target.value })} autoFocus /></label>
            <label>RUC<input value={ed.ruc} maxLength={11} inputMode="numeric" onChange={e => setEd({ ...ed, ruc: e.target.value })} /></label>
            <label>Dirección fiscal<input value={ed.direccion} onChange={e => setEd({ ...ed, direccion: e.target.value })} /></label>
            <label>Rubro<input value={ed.rubro} placeholder="Pesquera, agroexportadora, minera…" onChange={e => setEd({ ...ed, rubro: e.target.value })} /></label>
            <label>Condición de pago habitual<select value={ed.condicion_pago} onChange={e => setEd({ ...ed, condicion_pago: e.target.value })}><option value="">—</option>{COND_PAGO.map(x => <option key={x}>{x}</option>)}</select></label>
            {err && <div className="err">{err}</div>}
            <div className="toolbar" style={{ justifyContent: 'flex-end' }}><button type="button" className="btn ghost" onClick={() => setEd(null)}>Cancelar</button><button className="btn pri" type="submit">Guardar</button></div>
          </form></div></div>)}
    </>
  )
}

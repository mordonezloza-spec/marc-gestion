import { useMemo, useState, type FormEvent } from 'react'
import { usePageHead, useUi } from '../components/Layout'
import { supabase } from '../lib/supabase'
import { traerTodo } from '../lib/data'
import { useQuery } from '../lib/useQuery'
import { useAuth } from '../lib/auth'
import { money } from '../lib/format'
import type { Cliente, Tarifa } from '../lib/types'

const TABS = [['RETROEXCAVADORA', 'Retroexcavadora'], ['CAMION GRUA', 'Camión grúa'], ['TRASLADO', 'Traslados']] as const
type Ed = Partial<Tarifa> & { cliente_nombre?: string }

export function Tarifario() {
  usePageHead('Tarifario por cliente', [{ label: 'Comercial y ventas' }])
  const { toast } = useUi()
  const { puedeEditar } = useAuth()
  const [tab, setTab] = useState<string>('RETROEXCAVADORA')
  const [q, setQ] = useState('')
  const [ed, setEd] = useState<Ed | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const { data, loading, error, reload } = useQuery(async () => {
    const [tarifas, clientes] = await Promise.all([
      traerTodo<Tarifa>('tarifas', '*, clientes(razon_social)'),
      traerTodo<Cliente>('clientes', 'id,razon_social', { col: 'razon_social' }),
    ])
    return { tarifas, clientes }
  }, [])

  const L = useMemo(() => (data?.tarifas ?? []).filter(t => t.servicio === tab && t.activo && (!q || (t.clientes?.razon_social || '').toLowerCase().includes(q.toLowerCase())))
    .sort((a, b) => (a.clientes?.razon_social || '').localeCompare(b.clientes?.razon_social || '')), [data, tab, q])

  const guardar = async (e: FormEvent) => {
    e.preventDefault(); if (!ed) return
    const cli = data?.clientes.find(c => c.razon_social.toUpperCase() === (ed.cliente_nombre || '').trim().toUpperCase())
    if (!cli) { setErr('Elige un cliente registrado.'); return }
    if (!ed.tarifa) { setErr('Indica la tarifa.'); return }
    const fila = { cliente_id: cli.id, servicio: tab, horas_minimas: ed.horas_minimas ?? null, tarifa: ed.tarifa, cobra_recorrido: !!ed.cobra_recorrido,
      incluye_almuerzo: !!ed.incluye_almuerzo, incluye_igv: !!ed.incluye_igv, horas_jornada: ed.horas_jornada ?? null, tarifa_jornada: ed.tarifa_jornada ?? null,
      descripcion: ed.descripcion ?? null, origen: ed.origen ?? null, destino: ed.destino ?? null }
    const { error } = ed.id ? await supabase.from('tarifas').update(fila).eq('id', ed.id) : await supabase.from('tarifas').insert(fila)
    if (error) { setErr(error.message); return }
    setEd(null); toast('Tarifa guardada'); reload()
  }
  const numIn = (k: keyof Tarifa, label: string) => (
    <label>{label}<input type="number" step="0.01" value={(ed?.[k] as number | null | undefined) ?? ''} onChange={e => setEd({ ...ed!, [k]: e.target.value === '' ? null : Number(e.target.value) })} /></label>)
  const chk = (k: keyof Tarifa, label: string) => (
    <label style={{ flexDirection: 'row', alignItems: 'center', gap: 8, color: 'var(--ink)' }}><input type="checkbox" style={{ width: 'auto' }} checked={!!ed?.[k]} onChange={e => setEd({ ...ed!, [k]: e.target.checked })} />{label}</label>)
  const si = (b: boolean) => (b ? <span className="pill p-ok">Sí</span> : <span className="sub">No</span>)

  return (
    <>
      <div className="tabs" role="tablist">{TABS.map(([k, l]) => <button key={k} role="tab" className={tab === k ? 'on' : ''} onClick={() => setTab(k)}>{l}</button>)}</div>
      <div className="toolbar">
        <input className="grow" placeholder="Buscar cliente" value={q} onChange={e => setQ(e.target.value)} aria-label="Buscar en tarifario" />
        {puedeEditar && <button className="btn pri" onClick={() => { setErr(null); setEd({ horas_minimas: tab === 'TRASLADO' ? null : 4, horas_jornada: tab === 'TRASLADO' ? null : 8 }) }}>+ Nueva tarifa</button>}
      </div>
      <div className="hint">Al cotizar, el sistema propone la tarifa del cliente y avisa si no se cumple el mínimo de horas. Montos en soles, sin IGV.</div>
      {error && <div className="err">{error}</div>}
      <div className="card" style={{ padding: 0 }}><div className="tw"><table>
        {tab === 'TRASLADO'
          ? <thead><tr><th>Cliente</th><th>Descripción</th><th>Partida</th><th>Destino</th><th className="num">Tarifa</th>{puedeEditar && <th />}</tr></thead>
          : <thead><tr><th>Cliente</th><th className="num">Horas mínimas</th><th className="num">Tarifa / hora</th><th>Cobra recorrido</th><th>Almuerzo operador</th><th>Incluye IGV</th><th className="num">Jornada (h)</th><th className="num">Tarifa jornada / h</th>{puedeEditar && <th />}</tr></thead>}
        <tbody>
          {loading && <tr><td colSpan={9} className="empty">Cargando…</td></tr>}
          {L.map(t => {
            const editar = puedeEditar && <td><button className="btn sm" onClick={() => { setErr(null); setEd({ ...t, cliente_nombre: t.clientes?.razon_social }) }}>Editar</button></td>
            return tab === 'TRASLADO'
              ? <tr key={t.id}><td className="cli">{t.clientes?.razon_social}</td><td>{t.descripcion}</td><td>{t.origen}</td><td>{t.destino}</td><td className="num">{money(Number(t.tarifa))}</td>{editar}</tr>
              : <tr key={t.id}><td className="cli">{t.clientes?.razon_social}</td><td className="num">{t.horas_minimas ?? '—'}</td><td className="num"><b>{money(Number(t.tarifa))}</b></td>
                <td>{si(t.cobra_recorrido)}</td><td>{si(t.incluye_almuerzo)}</td><td>{si(t.incluye_igv)}</td><td className="num">{t.horas_jornada ?? '—'}</td><td className="num">{money(t.tarifa_jornada == null ? null : Number(t.tarifa_jornada))}</td>{editar}</tr>
          })}
          {!loading && !L.length && <tr><td colSpan={9} className="empty">Sin tarifas registradas</td></tr>}
        </tbody>
      </table></div></div>
      {ed && (
        <div className="modal"><div className="card" style={{ maxWidth: 520 }}><h2>{ed.id ? 'Editar tarifa' : 'Nueva tarifa'} · {TABS.find(x => x[0] === tab)?.[1]}</h2>
          <form className="form" style={{ gridTemplateColumns: '1fr 1fr' }} onSubmit={guardar} noValidate>
            <label className="s2" style={{ gridColumn: '1/-1' }}>Cliente<input list="tarCli" value={ed.cliente_nombre ?? ''} onChange={e => setEd({ ...ed, cliente_nombre: e.target.value })} /></label>
            <datalist id="tarCli">{data?.clientes.map(c => <option key={c.id} value={c.razon_social} />)}</datalist>
            {tab === 'TRASLADO' ? <>
              <label style={{ gridColumn: '1/-1' }}>Descripción<input value={ed.descripcion ?? ''} onChange={e => setEd({ ...ed, descripcion: e.target.value })} /></label>
              <label>Partida<input value={ed.origen ?? ''} onChange={e => setEd({ ...ed, origen: e.target.value })} /></label>
              <label>Destino<input value={ed.destino ?? ''} onChange={e => setEd({ ...ed, destino: e.target.value })} /></label>
              {numIn('tarifa', 'Tarifa por viaje (S/)')}
            </> : <>
              {numIn('horas_minimas', 'Horas mínimas')}{numIn('tarifa', 'Tarifa por hora (S/)')}
              {numIn('horas_jornada', 'Horas de la jornada')}{numIn('tarifa_jornada', 'Tarifa jornada por hora (S/)')}
              {chk('cobra_recorrido', 'Cobra recorrido')}{chk('incluye_almuerzo', 'Incluye almuerzo del operador')}{chk('incluye_igv', 'La tarifa incluye IGV')}
            </>}
            {err && <div className="err" style={{ gridColumn: '1/-1' }}>{err}</div>}
            <div className="toolbar" style={{ justifyContent: 'flex-end', gridColumn: '1/-1' }}><button type="button" className="btn ghost" onClick={() => setEd(null)}>Cancelar</button><button className="btn pri" type="submit">Guardar</button></div>
          </form></div></div>)}
    </>
  )
}

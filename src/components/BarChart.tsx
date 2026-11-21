import { MESES } from '../lib/catalogos'
import { money } from '../lib/format'

/**
 * Barras apiladas por mes: facturado (azul) + libre (naranja) + proyectado (contorno punteado).
 * Opcional: línea del año anterior para comparar.
 */
export function BarChart({ data, proy, prev, prevLabel, meses = 12 }: {
  data: { f: number; l: number }[]; proy?: number[]; prev?: number[]; prevLabel?: string; meses?: number
}) {
  const W = 680, H = 240, pl = 52, pb = 26, pt = 10
  const n = Math.max(meses, 1)
  const tot = (i: number) => (data[i]?.f || 0) + (data[i]?.l || 0)
  const max = Math.max(1, ...Array.from({ length: n }, (_, i) => tot(i) + (proy?.[i] || 0)), ...(prev ?? []).slice(0, n))
  const step = Math.pow(10, Math.floor(Math.log10(max)))
  const nice = Math.ceil(max / step) * step
  const bw = (W - pl - 10) / n
  const y = (v: number) => pt + (H - pt - pb) * (1 - v / nice)
  const cx = (i: number) => pl + i * bw + bw / 2
  const line = prev ? prev.slice(0, n).map((v, i) => `${i ? 'L' : 'M'}${cx(i).toFixed(1)} ${y(v).toFixed(1)}`).join('') : ''
  return (
    <>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" role="img" aria-label="Ventas aceptadas por mes">
        {[0, 1, 2, 3, 4].map(i => { const v = (nice * i) / 4; return (
          <g key={i}><line x1={pl} x2={W - 6} y1={y(v)} y2={y(v)} stroke="var(--line)" />
            <text x={pl - 6} y={y(v) + 4} textAnchor="end" fontSize="11" fill="var(--muted)">{v >= 1000 ? Math.round(v / 1000) + 'k' : v}</text></g>) })}
        {Array.from({ length: n }, (_, i) => {
          const m = data[i] || { f: 0, l: 0 }, x = pl + i * bw + bw * 0.18, w = bw * 0.64, p = proy?.[i] || 0
          return (
            <g key={i}>
              {m.f > 0 && <rect x={x} y={y(m.f)} width={w} height={y(0) - y(m.f)} fill="var(--brand)" rx="3"><title>{MESES[i]}: facturado {money(m.f)}</title></rect>}
              {m.l > 0 && <rect x={x} y={y(m.f + m.l)} width={w} height={y(m.f) - y(m.f + m.l)} fill="var(--orange)"><title>{MESES[i]}: libre {money(m.l)}</title></rect>}
              {p > 0 && <rect x={x + 1} y={y(tot(i) + p)} width={w - 2} height={y(tot(i)) - y(tot(i) + p)} fill="var(--brand-soft)" stroke="var(--brand)" strokeDasharray="4 3" rx="3"><title>{MESES[i]}: proyectado {money(p)}</title></rect>}
              <text x={x + w / 2} y={H - 8} textAnchor="middle" fontSize="11" fill="var(--muted)">{MESES[i].slice(0, 3)}</text>
            </g>)
        })}
        {prev && <><path d={line} fill="none" stroke="var(--muted)" strokeWidth="2" strokeDasharray="2 0" opacity=".8" />
          {prev.slice(0, n).map((v, i) => <circle key={i} cx={cx(i)} cy={y(v)} r="3" fill="var(--surface)" stroke="var(--muted)" strokeWidth="2"><title>{prevLabel} {MESES[i]}: {money(v)}</title></circle>)}</>}
      </svg>
      <div className="chips" style={{ marginTop: 4 }}>
        <span className="chip"><span style={{ display: 'inline-block', width: 10, height: 10, background: 'var(--brand)', borderRadius: 2 }} /> Facturado</span>
        <span className="chip"><span style={{ display: 'inline-block', width: 10, height: 10, background: 'var(--orange)', borderRadius: 2 }} /> Libre</span>
        {proy?.some(v => v > 0) && <span className="chip"><span style={{ display: 'inline-block', width: 10, height: 10, background: 'var(--brand-soft)', border: '1px dashed var(--brand)', borderRadius: 2 }} /> Proyectado</span>}
        {prev && <span className="chip"><span style={{ display: 'inline-block', width: 14, height: 2, background: 'var(--muted)', verticalAlign: 'middle' }} /> {prevLabel}</span>}
      </div>
    </>
  )
}

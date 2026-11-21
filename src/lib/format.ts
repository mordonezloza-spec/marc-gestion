export const money = (v: number | null | undefined, cur: 'PEN' | 'USD' = 'PEN') =>
  v == null || isNaN(Number(v)) ? '—'
    : new Intl.NumberFormat('es-PE', { style: 'currency', currency: cur, minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(v))

export const kmoney = (v: number) =>
  'S/ ' + (v >= 1000 ? (v / 1000).toLocaleString('es-PE', { maximumFractionDigits: 1 }) + ' mil' : Math.round(v).toLocaleString('es-PE'))

export const fdate = (s: string | null | undefined) => (s ? s.slice(0, 10).split('-').reverse().join('/') : '—')
export const monthOf = (s: string | null | undefined) => (s ? Number(s.slice(5, 7)) - 1 : -1)
export const hoyISO = () => new Date().toISOString().slice(0, 10)
export const condDias = (c: string | null | undefined) => { const m = /(\d+)/.exec(c || ''); return m ? Number(m[1]) : 0 }
export const addDays = (iso: string, n: number) => { const d = new Date(iso + 'T00:00:00'); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10) }
export const n = (v: unknown) => Number(v) || 0

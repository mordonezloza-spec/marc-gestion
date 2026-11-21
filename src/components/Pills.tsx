export function PillEstado({ e }: { e: string | null }) {
  const m: Record<string, string> = { ACEPTADO: 'p-ok', RECHAZADO: 'p-bad', ENVIADO: 'p-info', 'EN PROCESO': 'p-warn', REEMPLAZADA: 'p-mute' }
  return <span className={`pill ${m[e || ''] || 'p-mute'}`}>{e || '—'}</span>
}
export function PillPago({ e }: { e: string | null }) {
  if (!e) return <span className="sub">—</span>
  const m: Record<string, string> = { CANCELADO: 'p-ok', 'PENDIENTE DE PAGO': 'p-warn', 'PENDIENTE DE FACTURACIÓN': 'p-info' }
  const t = e === 'PENDIENTE DE FACTURACIÓN' ? 'POR FACTURAR' : e === 'PENDIENTE DE PAGO' ? 'POR COBRAR' : e
  return <span className={`pill ${m[e] || 'p-mute'}`}>{t}</span>
}

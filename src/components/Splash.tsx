import { useEffect, useState } from 'react'

/** Pantalla de carga con el isotipo girando (~2 s, se salta con un clic). */
export function Splash({ onDone }: { onDone: () => void }) {
  const [out, setOut] = useState(false)
  useEffect(() => {
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
    const t = setTimeout(() => setOut(true), reduce ? 300 : 2100)
    return () => clearTimeout(t)
  }, [])
  useEffect(() => { if (out) { const t = setTimeout(onDone, 500); return () => clearTimeout(t) } }, [out, onDone])
  return (
    <div id="splash" className={out ? 'out' : ''} role="status" aria-label="Cargando el sistema" onClick={() => setOut(true)}>
      <div className="sp-box">
        <div className="sp-mark">
          <svg className="sp-ring" viewBox="0 0 150 150" aria-hidden="true">
            <circle cx="75" cy="75" r="70" stroke="rgba(255,255,255,.12)" />
            <circle cx="75" cy="75" r="70" stroke="#F39200" strokeDasharray="90 350" />
            <circle cx="75" cy="75" r="70" stroke="#1BA0DB" strokeDasharray="40 400" strokeDashoffset={-200} />
          </svg>
          <img src="/iso.png" alt="" />
        </div>
        <div className="sp-word"><img src="/logo.png" alt="MARC Distribution & Solutions Import E.I.R.L." /></div>
        <div className="sp-bar"><div /></div>
        <div className="sp-txt">Preparando tu espacio de trabajo…</div>
      </div>
    </div>
  )
}

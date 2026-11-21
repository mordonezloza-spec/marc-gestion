import { useMemo } from 'react'

/** Curvas de nivel animadas para el panel de inicio de sesión. */
export function Topo() {
  const paths = useMemo(() => {
    let seed = 7
    const rnd = () => { seed = (seed * 9301 + 49297) % 233280; return seed / 233280 }
    const out: { d: string; c: string; len: number; delay: number }[] = []
    const centers: [number, number, number][] = [[560, 260, 15], [180, 700, 9]]
    centers.forEach(([cx, cy, n], ci) => {
      const ph = [0, 1, 2, 3].map(() => rnd() * 6.28), am = [0.12, 0.07, 0.05, 0.03].map(a => a * (0.7 + rnd() * 0.6))
      for (let i = 1; i <= n; i++) {
        const R = i * (ci ? 34 : 38); let d = ''
        for (let k = 0; k <= 72; k++) {
          const t = (k / 72) * 6.283
          const r = R * (1 + am[0] * Math.sin(2 * t + ph[0] + i * 0.15) + am[1] * Math.sin(3 * t + ph[1]) + am[2] * Math.sin(5 * t + ph[2] + i * 0.1) + am[3] * Math.sin(7 * t + ph[3]))
          d += (k ? 'L' : 'M') + (cx + r * Math.cos(t)).toFixed(1) + ' ' + (cy + r * Math.sin(t) * 0.85).toFixed(1)
        }
        out.push({ d: d + 'Z', c: i % 5 === 0 ? 'rgba(243,146,0,.55)' : `rgba(140,200,240,${(0.18 + 0.25 * (1 - i / n)).toFixed(2)})`,
          len: Math.round(2 * Math.PI * R * 1.15), delay: i * 0.06 + ci * 0.3 })
      }
    })
    return out
  }, [])
  return (
    <svg className="topo" viewBox="0 0 800 900" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
      {paths.map((p, i) => <path key={i} d={p.d} stroke={p.c} style={{ ['--len' as string]: p.len, animationDelay: `${p.delay}s` }} />)}
    </svg>
  )
}

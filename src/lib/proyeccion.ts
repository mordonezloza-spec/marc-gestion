/**
 * Proyección de ventas del año a partir de los meses ya cerrados.
 *
 * - Con años anteriores completos: usa la estacionalidad histórica (índice de cada mes
 *   respecto al promedio del año) y el nivel del año actual (lo vendido en los meses cerrados
 *   dividido por la suma de sus índices). Así un año que va 10% arriba se proyecta 10% arriba
 *   respetando los meses fuertes y débiles (temporada de pesca, El Niño, etc.).
 * - Sin historia: promedio de los últimos 3 meses cerrados.
 */
export interface Proyeccion {
  mensual: number[]        // proyección por mes (solo meses abiertos; 0 en los cerrados)
  total: number            // real cerrado + proyectado
  real: number
  metodo: string
  aniosBase: number[]
}

export function proyectar(porAnio: Record<number, number[]>, anio: number, mesesCerrados: number): Proyeccion {
  const actual = porAnio[anio] ?? Array(12).fill(0)
  const real = actual.slice(0, 12).reduce((a, b) => a + b, 0)
  const base = Object.keys(porAnio).map(Number).filter(y => y < anio && (porAnio[y] ?? []).filter(v => v > 0).length >= 10)
  const mensual = Array(12).fill(0)
  let metodo = ''

  if (mesesCerrados >= 12) return { mensual, total: real, real, metodo: 'Año cerrado', aniosBase: base }

  if (base.length && mesesCerrados >= 2) {
    const idx = Array(12).fill(0)
    base.forEach(y => { const v = porAnio[y]; const prom = v.reduce((a, b) => a + b, 0) / 12 || 1; v.forEach((x, k) => { idx[k] += x / prom / base.length }) })
    const sumIdx = idx.slice(0, mesesCerrados).reduce((a, b) => a + b, 0) || 1
    const nivel = actual.slice(0, mesesCerrados).reduce((a, b) => a + b, 0) / sumIdx
    for (let k = mesesCerrados; k < 12; k++) mensual[k] = Math.max(0, nivel * idx[k] - (actual[k] || 0))
    metodo = `Estacionalidad de ${base.join(', ')} aplicada al ritmo de ${anio}`
  } else if (mesesCerrados >= 1) {
    const ult = actual.slice(Math.max(0, mesesCerrados - 3), mesesCerrados)
    const prom = ult.reduce((a, b) => a + b, 0) / (ult.length || 1)
    for (let k = mesesCerrados; k < 12; k++) mensual[k] = Math.max(0, prom - (actual[k] || 0))
    metodo = `Promedio de los últimos ${ult.length} meses cerrados (sin años anteriores cargados)`
  }
  const total = real + mensual.reduce((a, b) => a + b, 0)
  return { mensual, total, real, metodo, aniosBase: base }
}

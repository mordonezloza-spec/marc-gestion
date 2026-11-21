import { supabase } from './supabase'
import type { Cotizacion } from './types'

/** Supabase devuelve como máximo 1000 filas por consulta: esta función pagina. */
export async function traerTodo<T>(tabla: string, columnas = '*', orden?: { col: string; asc?: boolean }): Promise<T[]> {
  const out: T[] = []
  for (let desde = 0; ; desde += 1000) {
    let q = supabase.from(tabla).select(columnas).range(desde, desde + 999)
    if (orden) q = q.order(orden.col, { ascending: orden.asc ?? true })
    const { data, error } = await q
    if (error) throw new Error(error.message)
    out.push(...((data ?? []) as T[]))
    if (!data || data.length < 1000) break
  }
  return out
}

export const COLS_LISTA = 'id,numero,fecha,cliente_id,cliente,descripcion,servicio,asesor,motivo_contacto,estado,estado_pago,tipo_comprobante,moneda,subtotal,total_libre,venta,total,fecha_vencimiento,dias_atraso'
export const traerCotizaciones = () => traerTodo<Cotizacion>('v_cotizaciones', COLS_LISTA, { col: 'fecha', asc: false })

import { useCallback, useEffect, useState } from 'react'

/** Carga datos asíncronos con estado de carga/error y función para recargar. */
export function useQuery<T>(fn: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const run = useCallback(fn, deps)
  const reload = useCallback(async () => {
    setLoading(true); setError(null)
    try { setData(await run()) } catch (e) { setError(e instanceof Error ? e.message : String(e)) } finally { setLoading(false) }
  }, [run])
  useEffect(() => { reload() }, [reload])
  return { data, error, loading, reload, setData }
}

/** Lanza el error de Supabase como excepción para usar con useQuery. */
export function ok<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw new Error(r.error.message)
  return r.data as T
}

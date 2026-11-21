import { useEffect, useState } from 'react'
export type Tema = 'system' | 'light' | 'dark'
const KEY = 'marc_tema'
const EVT = 'marc-tema'

export function aplicarTema(t: Tema) {
  const r = document.documentElement
  if (t === 'light' || t === 'dark') r.setAttribute('data-theme', t); else r.removeAttribute('data-theme')
}
/** Preferencia de tema compartida entre componentes (se guarda en el navegador). */
export function useTema() {
  const [tema, setLocal] = useState<Tema>(() => (localStorage.getItem(KEY) as Tema) || 'system')
  useEffect(() => {
    const h = () => setLocal((localStorage.getItem(KEY) as Tema) || 'system')
    window.addEventListener(EVT, h); return () => window.removeEventListener(EVT, h)
  }, [])
  const setTema = (t: Tema) => { localStorage.setItem(KEY, t); aplicarTema(t); setLocal(t); window.dispatchEvent(new Event(EVT)) }
  const siguiente = () => setTema(tema === 'system' ? 'light' : tema === 'light' ? 'dark' : 'system')
  return { tema, setTema, siguiente }
}

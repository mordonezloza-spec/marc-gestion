import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase, LOGIN_DOMAIN } from './supabase'
import type { Perfil } from './types'

interface AuthCtx {
  session: Session | null; perfil: Perfil | null; errorPerfil: string | null; cargando: boolean
  ingresar: (usuario: string, clave: string) => Promise<string | null>
  salir: () => Promise<void>
  puedeEditar: boolean
}
const Ctx = createContext<AuthCtx>(null as unknown as AuthCtx)
export const useAuth = () => useContext(Ctx)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [perfil, setPerfil] = useState<Perfil | null>(null)
  const [cargando, setCargando] = useState(true)
  const [errorPerfil, setErrorPerfil] = useState<string | null>(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); if (!data.session) setCargando(false) })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session) { setPerfil(null); return }
    setCargando(true)
    supabase.from('perfiles').select('*').eq('id', session.user.id).maybeSingle()
      .then(({ data, error }) => {
        setErrorPerfil(error ? `${error.code ?? ''} ${error.message}`.trim() : null)
        setPerfil((data as Perfil) ?? null); setCargando(false)
      })
  }, [session])

  const ingresar = async (usuario: string, clave: string) => {
    const u = usuario.trim().toLowerCase()
    const email = u.includes('@') ? u : `${u}@${LOGIN_DOMAIN}`
    const { error } = await supabase.auth.signInWithPassword({ email, password: clave })
    if (error) return error.message === 'Invalid login credentials' ? 'Usuario o contraseña incorrectos.' : error.message
    return null
  }
  const salir = async () => { await supabase.auth.signOut() }
  const puedeEditar = !!perfil && ['gerencia', 'administracion', 'comercial'].includes(perfil.rol)

  return <Ctx.Provider value={{ session, perfil, errorPerfil, cargando, ingresar, salir, puedeEditar }}>{children}</Ctx.Provider>
}

import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

export const configurado = Boolean(url && key)
if (!configurado) console.error('Faltan VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY en el archivo .env')

export const supabase = createClient(url || 'http://localhost:54321', key || 'sin-clave')
export const LOGIN_DOMAIN = import.meta.env.VITE_LOGIN_DOMAIN || 'marc-eirl.com'

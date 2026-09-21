import { createClient } from '@supabase/supabase-js'
const url = import.meta.env.VITE_SUPABASE_URL || 'https://yefapwkvbkfqelsytjiu.supabase.co'
// Esta clave es publicable. La autorización se verifica en Supabase mediante RLS.
const key = import.meta.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_AiGDbynVdvxZASMCbx1YcQ_gww69Clm'
export const supabase = createClient(url, key)
export const isSupabaseReady = Boolean(supabase)

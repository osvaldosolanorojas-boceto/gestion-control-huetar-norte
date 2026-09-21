import { createClient } from '@supabase/supabase-js'


const url = import.meta.env.VITE_SUPABASE_URL || 'https://yefapwkvbkfqelsytjiu.supabase.co'
const key = import.meta.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_AiGDbynVdvxZASMCbx1YcQ_gww69Clm'


export const supabase = url && key ? createClient(url, key, {auth:{detectSessionInUrl:true,persistSession:true}}) : null
export const isSupabaseReady = Boolean(supabase)

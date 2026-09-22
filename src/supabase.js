import { createClient } from '@supabase/supabase-js'


// Capture the purpose of the Auth link before createClient() processes and
// removes its parameters from the address bar.
const authHash = new URLSearchParams(window.location.hash.replace(/^#/, ''))
const authQuery = new URLSearchParams(window.location.search)
export const initialAuthLinkType = authHash.get('type') || authQuery.get('type') || (authQuery.has('code') ? 'recovery' : '')


const url = import.meta.env.VITE_SUPABASE_URL || 'https://yefapwkvbkfqelsytjiu.supabase.co'
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_AiGDbynVdvxZASMCbx1YcQ_gww69Clm'


export const supabase = url && key ? createClient(url, key, {auth:{detectSessionInUrl:true,persistSession:true}}) : null
export const isSupabaseReady = Boolean(supabase)

import React, { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { LayoutDashboard, ShoppingCart, Truck, Factory, WalletCards, Users, UserRound, Landmark, Menu, X, Plus, Search, ChevronRight, ArrowUpRight, ArrowDownRight, CircleDollarSign, PackageCheck, Settings, LogOut } from 'lucide-react'
import { isSupabaseReady, supabase } from './supabase'
import './styles.css'


const nav = [
  ['Resumen', LayoutDashboard], ['Órdenes de compra', ShoppingCart], ['Boletas de entrada', Truck],
  ['Producción y rendimientos', Factory], ['Órdenes de venta', PackageCheck], ['Finanzas', WalletCards],
  ['Bancos', Landmark], ['Proveedores', Users], ['Clientes', UserRound], ['Trabajadores', Users]
]


const seed = {
  'Órdenes de compra': [
    {codigo:'OC-2026-0341', principal:'Randall Calvo', detalle:'Yuca · A rendimiento', estado:'Pendiente', monto:'₡ 4.830.000'},
    {codigo:'OC-2026-0340', principal:'Agrosolano', detalle:'Yuca · Cosecha propia', estado:'En proceso', monto:'₡ 7.200.000'}
  ],
  'Boletas de entrada': [
    {codigo:'BE-2026-0815', principal:'Agrosolano · El Concho', detalle:'420 cajas · Línea 1', estado:'En proceso', monto:'8.610 kg'},
    {codigo:'BE-2026-0814', principal:'Luis Araya · Los Chiles', detalle:'285 cajas · Línea 2', estado:'Completada', monto:'5.842 kg'}
  ],
  'Órdenes de venta': [
    {codigo:'OV-2026-0198', principal:'Grupo Plátanos López 3', detalle:'21 paletas · Estados Unidos', estado:'Preparando', monto:'US$ 27.540'},
    {codigo:'OV-2026-0197', principal:'J&C', detalle:'1.320 cajas · Europa', estado:'Despachada', monto:'US$ 31.680'}
  ],
  Proveedores: [
    {codigo:'PR-001', principal:'Agrosolano', detalle:'Productor propio · Zona Norte', estado:'Activo', monto:'Yuca · Ñampí'},
    {codigo:'PR-002', principal:'Randall Calvo', detalle:'Agricultor · San Carlos', estado:'Activo', monto:'Yuca'}
  ],
  Clientes: [
    {codigo:'CL-001', principal:'Grupo Plátanos López', detalle:'Estados Unidos', estado:'Activo', monto:'4–5 contenedores/sem'},
    {codigo:'CL-002', principal:'J&C', detalle:'Europa', estado:'Activo', monto:'Crédito'}
  ]
}


const money = new Intl.NumberFormat('es-CR',{style:'currency',currency:'CRC',maximumFractionDigits:0})


function App(){
  const [section,setSection]=useState('Resumen'); const [open,setOpen]=useState(false); const [search,setSearch]=useState(''); const [modal,setModal]=useState(false)
  const rows = useMemo(()=> (seed[section]||[]).filter(r=>Object.values(r).join(' ').toLowerCase().includes(search.toLowerCase())),[section,search])
  const go=(x)=>{setSection(x);setOpen(false);setSearch('')}
  return <div className="app">
    <aside className={open?'sidebar open':'sidebar'}>
      <div className="brand"><div className="brandmark">HN</div><div><b>Gestión y Control</b><span>Huetar Norte S.A.</span></div><button className="close" onClick={()=>setOpen(false)}><X/></button></div>
      <nav>{nav.map(([label,Icon])=><button key={label} className={section===label?'active':''} onClick={()=>go(label)}><Icon size={19}/><span>{label}</span></button>)}</nav>
      <div className="sidefoot"><button><Settings size={19}/>Configuración</button><button><LogOut size={19}/>Cerrar sesión</button></div>
    </aside>
    {open&&<div className="scrim" onClick={()=>setOpen(false)}/>} 
    <main>
      <header><button className="menubtn" onClick={()=>setOpen(true)}><Menu/></button><div><span className="eyebrow">RAÍCES Y TUBÉRCULOS HUETAR NORTE S.A.</span><h1>{section}</h1></div><div className="headerRight"><div className="exchange"><span>Tipo de cambio</span><b>USD ₡ 493,50</b><small>EUR ₡ 579,20</small></div><div className="avatar">OS</div></div></header>
      <div className="content">{section==='Resumen'?<Dashboard go={go}/>:<Module title={section} rows={rows} search={search} setSearch={setSearch} onNew={()=>setModal(true)}/>}</div>
    </main>
    {modal&&<QuickModal title={section} close={()=>setModal(false)}/>} 
  </div>
}


function Dashboard({go}){return <>
  {!isSupabaseReady&&<div className="notice"><b>Modo de preparación:</b> la interfaz está funcionando. Falta conectar las claves privadas del proyecto Supabase.</div>}
  <section className="hero"><div><span>SEMANA 38 · 2026</span><h2>Buenos días, Osvaldo</h2><p>Estado general de la exportadora y la operación agrícola.</p></div><button onClick={()=>go('Órdenes de venta')}><Plus size={18}/> Nueva orden de venta</button></section>
  <div className="stats">
    <Stat title="Ventas de la semana" value="US$ 248.760" note="8 contenedores" up icon={CircleDollarSign}/>
    <Stat title="Compras de campo" value={money.format(42780000)} note="34 órdenes" icon={ShoppingCart}/>
    <Stat title="Cuentas por cobrar" value="US$ 186.420" note="US$ 61.300 vencido" warning icon={ArrowUpRight}/>
    <Stat title="Cuentas por pagar" value={money.format(68450000)} note="₡ 18.240.000 esta semana" icon={ArrowDownRight}/>
  </div>
  <div className="grid2"><section className="panel"><div className="panelhead"><div><h3>Operación de planta</h3><p>Producción y despachos de hoy</p></div><button onClick={()=>go('Boletas de entrada')}>Ver boletas <ChevronRight size={16}/></button></div><div className="plant"><div><b>8</b><span>Boletas recibidas</span></div><div><b>42.680</b><span>kg procesados</span></div><div><b>3</b><span>Contenedores listos</span></div><div><b>86,4%</b><span>Rendimiento exportable</span></div></div></section>
  <section className="panel"><div className="panelhead"><div><h3>Próximos movimientos</h3><p>Pagos y cobros prioritarios</p></div></div><ul className="moves"><li><i className="red"/><div><b>Pago a proveedores</b><span>Hoy · 14 facturas</span></div><strong>₡ 18,2 M</strong></li><li><i className="blue"/><div><b>Cobro Grupo Plátanos López</b><span>Mañana · 2 facturas</span></div><strong>US$ 54.900</strong></li><li><i className="yellow"/><div><b>Planilla semanal</b><span>Viernes · Campo y planta</span></div><strong>₡ 12,8 M</strong></li></ul></section></div>
  <section className="quick"><h3>Accesos rápidos</h3><div><button onClick={()=>go('Órdenes de compra')}><ShoppingCart/>Nueva compra</button><button onClick={()=>go('Boletas de entrada')}><Truck/>Recibir producto</button><button onClick={()=>go('Finanzas')}><WalletCards/>Registrar gasto</button><button onClick={()=>go('Bancos')}><Landmark/>Conciliar bancos</button></div></section>
  </>}


function Stat({title,value,note,icon:Icon,up,warning}){return <article className={warning?'stat warning':'stat'}><div className="staticon"><Icon size={22}/></div><span>{title}</span><b>{value}</b><small className={up?'positive':''}>{note}</small></article>}


function Module({title,rows,search,setSearch,onNew}){return <><div className="modulebar"><div><p>Administre y consulte la información de {title.toLowerCase()}.</p></div><button className="primary" onClick={onNew}><Plus size={18}/>Nuevo registro</button></div><section className="panel tablepanel"><div className="filters"><label><Search size={18}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Buscar por código, nombre o estado…"/></label><button>Todos los estados</button></div>{rows.length?<div className="rows">{rows.map(r=><article key={r.codigo}><div className="code">{r.codigo}</div><div className="who"><b>{r.principal}</b><span>{r.detalle}</span></div><span className="pill">{r.estado}</span><strong>{r.monto}</strong><button className="arrow"><ChevronRight/></button></article>)}</div>:<div className="empty"><PackageCheck size={42}/><h3>Módulo preparado</h3><p>Puede crear el primer registro de {title.toLowerCase()}.</p><button className="primary" onClick={onNew}><Plus size={18}/>Crear registro</button></div>}</section></>}


const tableBySection = {
  'Órdenes de compra':'ordenes_compra', 'Boletas de entrada':'boletas_entrada',
  'Órdenes de venta':'ordenes_venta', Proveedores:'proveedores', Clientes:'clientes'
}

function QuickModal({title,close}){
  const [form,setForm]=useState({fecha:new Date().toISOString().slice(0,10),nombre:'',moneda:'CRC',monto:'',observaciones:''})
  const [saving,setSaving]=useState(false); const [error,setError]=useState('')
  const change=e=>setForm({...form,[e.target.name]:e.target.value})
  const save=async()=>{
    if(!form.nombre.trim()){setError('Escriba el nombre o la descripción.');return}
    if(!supabase){setError('Falta conectar Supabase en la configuración de la aplicación.');return}
    const table=tableBySection[title]
    if(!table){setError(`El módulo ${title} todavía no tiene una tabla de guardado.`);return}
    const codigo=`${title==='Órdenes de compra'?'OC':title==='Boletas de entrada'?'BE':'OV'}-${Date.now()}`
    let payload
    if(title==='Proveedores') payload={nombre:form.nombre.trim(),tipo:'Agricultor'}
    else if(title==='Clientes') payload={nombre:form.nombre.trim()}
    else if(title==='Órdenes de compra') payload={codigo,fecha:form.fecha,producto:form.nombre.trim(),moneda:form.moneda,observaciones:form.observaciones||null}
    else if(title==='Boletas de entrada') payload={codigo,fecha_hora:`${form.fecha}T12:00:00`,producto:form.nombre.trim(),observaciones:form.observaciones||null}
    else payload={codigo,fecha:form.fecha,moneda:form.moneda,observaciones:form.observaciones||null}
    setSaving(true);setError('')
    const {error:saveError}=await supabase.from(table).insert(payload)
    setSaving(false)
    if(saveError){setError(`No se pudo guardar: ${saveError.message}`);return}
    close()
  }
  return <div className="modalwrap"><div className="modal"><div className="modalhead"><div><span>NUEVO REGISTRO</span><h2>{title}</h2></div><button onClick={close}><X/></button></div><div className="formgrid"><label>Fecha<input name="fecha" type="date" value={form.fecha} onChange={change}/></label><label>Código<input placeholder="Se genera automáticamente" disabled/></label><label className="wide">Nombre o descripción<input name="nombre" value={form.nombre} onChange={change} placeholder="Escriba aquí…"/></label><label>Moneda<select name="moneda" value={form.moneda} onChange={change}><option value="CRC">Colones (CRC)</option><option value="USD">Dólares (USD)</option><option value="EUR">Euros (EUR)</option></select></label><label>Monto<input name="monto" value={form.monto} onChange={change} type="number" step="0.01" placeholder="0,00"/></label><label className="wide">Observaciones<textarea name="observaciones" value={form.observaciones} onChange={change} rows="3" placeholder="Información adicional…"/></label></div>{error&&<div className="formerror">{error}</div>}<div className="modalactions"><button onClick={close} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':'Guardar registro'}</button></div></div></div>}


function AccessScreen(){
  const [email,setEmail]=useState(''); const [password,setPassword]=useState(''); const [error,setError]=useState(''); const [loading,setLoading]=useState(false)
  const login=async e=>{e.preventDefault();setLoading(true);setError('');const {error:loginError}=await supabase.auth.signInWithPassword({email,password});setLoading(false);if(loginError)setError('No se pudo ingresar. Revise el correo y la contraseña.')}
  return <div className="authpage"><div className="authcard"><div className="authmark">HN</div><span>ACCESO PRIVADO</span><h1>Gestión y Control</h1><p>Raíces y Tubérculos Huetar Norte S.A.</p><form onSubmit={login}><label>Correo electrónico<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required autoComplete="email"/></label><label>Contraseña<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required autoComplete="current-password"/></label>{error&&<div className="formerror">{error}</div>}<button className="primary" disabled={loading}>{loading?'Ingresando…':'Ingresar'}</button></form><small>Solo pueden ingresar usuarios autorizados.</small></div></div>
}

function SetPassword({done}){
  const [password,setPassword]=useState(''); const [repeat,setRepeat]=useState(''); const [error,setError]=useState(''); const [loading,setLoading]=useState(false)
  const save=async e=>{e.preventDefault();if(password.length<8){setError('La contraseña debe tener al menos 8 caracteres.');return}if(password!==repeat){setError('Las contraseñas no coinciden.');return}setLoading(true);const {error:saveError}=await supabase.auth.updateUser({password});setLoading(false);if(saveError){setError(saveError.message);return}done()}
  return <div className="authpage"><div className="authcard"><div className="authmark">HN</div><span>ACTIVAR CUENTA</span><h1>Cree su contraseña</h1><p>Esta será su clave privada para ingresar a Gestión y Control.</p><form onSubmit={save}><label>Nueva contraseña<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required autoComplete="new-password"/></label><label>Repetir contraseña<input type="password" value={repeat} onChange={e=>setRepeat(e.target.value)} required autoComplete="new-password"/></label>{error&&<div className="formerror">{error}</div>}<button className="primary" disabled={loading}>{loading?'Guardando…':'Activar mi cuenta'}</button></form></div></div>
}

function Root(){
  const [session,setSession]=useState(undefined)
  const [invited,setInvited]=useState(()=>window.location.hash.includes('type=invite'))
  useEffect(()=>{if(!supabase){setSession(null);return}supabase.auth.getSession().then(({data})=>setSession(data.session));const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));return()=>subscription.unsubscribe()},[])
  if(session===undefined)return <div className="authpage"><div className="authcard"><b>Abriendo Gestión y Control…</b></div></div>
  if(!session)return <AccessScreen/>
  if(invited)return <SetPassword done={()=>setInvited(false)}/>
  return <App/>
}

createRoot(document.getElementById('root')).render(<Root/>)

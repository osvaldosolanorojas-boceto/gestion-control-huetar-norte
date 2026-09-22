import React, { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { LayoutDashboard, ShoppingCart, Truck, Factory, WalletCards, Users, UserRound, Landmark, Menu, X, Plus, Search, ChevronRight, ArrowUpRight, ArrowDownRight, CircleDollarSign, PackageCheck, Settings, LogOut } from 'lucide-react'
import { initialAuthLinkType, isSupabaseReady, supabase } from './supabase'
import './styles.css'


const nav = [
  ['Resumen', LayoutDashboard], ['Órdenes de compra', ShoppingCart], ['Boletas de entrada', Truck],
  ['Producción y rendimientos', Factory], ['Órdenes de venta', PackageCheck], ['Finanzas', WalletCards],
  ['Bancos', Landmark], ['Proveedores', Users], ['Clientes', UserRound], ['Trabajadores', Users]
]


const money = new Intl.NumberFormat('es-CR',{style:'currency',currency:'CRC',maximumFractionDigits:0})


function App({profile}){
  const [section,setSection]=useState('Resumen'); const [open,setOpen]=useState(false); const [search,setSearch]=useState(''); const [modal,setModal]=useState(false); const [refresh,setRefresh]=useState(0)
  const go=(x)=>{setSection(x);setOpen(false);setSearch('')}
  return <div className="app">
    <aside className={open?'sidebar open':'sidebar'}>
      <div className="brand"><div className="brandmark">HN</div><div><b>Gestión y Control</b><span>Huetar Norte S.A.</span></div><button className="close" onClick={()=>setOpen(false)}><X/></button></div>
      <nav>{nav.map(([label,Icon])=><button key={label} className={section===label?'active':''} onClick={()=>go(label)}><Icon size={19}/><span>{label}</span></button>)}</nav>
      <div className="sidefoot"><button><Settings size={19}/>Configuración</button><button onClick={()=>supabase.auth.signOut()}><LogOut size={19}/>Cerrar sesión</button></div>
    </aside>
    {open&&<div className="scrim" onClick={()=>setOpen(false)}/>} 
    <main>
      <header><button className="menubtn" onClick={()=>setOpen(true)}><Menu/></button><div><span className="eyebrow">RAÍCES Y TUBÉRCULOS HUETAR NORTE S.A.</span><h1>{section}</h1></div><div className="headerRight"><div className="exchange"><span>Tipo de cambio</span><b>USD ₡ 493,50</b><small>EUR ₡ 579,20</small></div><div className="avatar">OS</div></div></header>
      <div className="content">{section==='Resumen'?<Dashboard go={go} profile={profile}/>:<Module title={section} search={search} setSearch={setSearch} onNew={()=>setModal(true)} refresh={refresh}/>}</div>
    </main>
    {modal&&(section==='Órdenes de venta'
      ? <SalesOrderModal close={()=>setModal(false)} onSaved={()=>{setModal(false);setRefresh(x=>x+1)}}/>
      : <QuickModal title={section} userId={profile.id} close={()=>setModal(false)} onSaved={()=>{setModal(false);setRefresh(x=>x+1)}}/>)}
  </div>
}


function Dashboard({go,profile}){return <>
  {!isSupabaseReady&&<div className="notice"><b>Modo de preparación:</b> la interfaz está funcionando. Falta conectar las claves privadas del proyecto Supabase.</div>}
  <section className="hero"><div><span>ACCESO {profile.rol.toUpperCase()}</span><h2>Buenos días, {profile.nombre.split(' ')[0]}</h2><p>La sesión está conectada de forma segura con Supabase.</p></div><button onClick={()=>go('Órdenes de venta')}><Plus size={18}/> Nueva orden de venta</button></section>
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


function Module({title,search,setSearch,onNew,refresh}){
  const [items,setItems]=useState([]); const [loading,setLoading]=useState(false); const [error,setError]=useState('')
  const table=tableBySection[title]
  useEffect(()=>{let active=true;if(!table){setItems([]);return}
    setLoading(true);setError('')
    supabase.from(table).select('*').order('creado_en',{ascending:false}).limit(100).then(({data,error:loadError})=>{
      if(!active)return;setLoading(false);if(loadError){setError('No se pudieron cargar los datos.');return}setItems(data||[])
    });return()=>{active=false}
  },[table,refresh])
  const rows=useMemo(()=>items.map((item,index)=>({
    key:item.id||index,
    codigo:item.codigo||`${title==='Proveedores'?'PR':'CL'}-${String(index+1).padStart(3,'0')}`,
    principal:item.nombre||item.producto||item.mercado||'Registro',
    detalle:item.tipo||item.lugar||item.finca_lugar||item.mercado||item.observaciones||'Sin detalle',
    estado:item.estado||(item.activo===false?'Inactivo':'Activo'),
    monto:item.kg_estimados?`${Number(item.kg_estimados).toLocaleString('es-CR')} kg`:item.moneda||''
  })).filter(r=>Object.values(r).join(' ').toLowerCase().includes(search.toLowerCase())),[items,search,title])
  return <><div className="modulebar"><div><p>Administre y consulte la información de {title.toLowerCase()}.</p></div>{table&&<button className="primary" onClick={onNew}><Plus size={18}/>Nuevo registro</button>}</div><section className="panel tablepanel"><div className="filters"><label><Search size={18}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Buscar por código, nombre o estado…"/></label><button>Todos los estados</button></div>{loading?<div className="empty"><p>Cargando información…</p></div>:error?<div className="formerror">{error}</div>:rows.length?<div className="rows">{rows.map(r=><article key={r.key}><div className="code">{r.codigo}</div><div className="who"><b>{r.principal}</b><span>{r.detalle}</span></div><span className="pill">{r.estado}</span><strong>{r.monto}</strong><button className="arrow"><ChevronRight/></button></article>)}</div>:<div className="empty"><PackageCheck size={42}/><h3>Sin registros todavía</h3><p>{table?`Puede crear el primer registro de ${title.toLowerCase()}.`:'Este módulo se conectará en la siguiente etapa.'}</p>{table&&<button className="primary" onClick={onNew}><Plus size={18}/>Crear registro</button>}</div>}</section></>
}


const tableBySection = {
  'Órdenes de compra':'ordenes_compra', 'Boletas de entrada':'boletas_entrada',
  'Órdenes de venta':'ordenes_venta', Proveedores:'proveedores', Clientes:'clientes'
}

const emptySaleLine = () => ({producto:'Yuca',presentacion_kg:'18',paletas:'1',cajas_por_paleta:'60',precio_caja:''})
const usd = new Intl.NumberFormat('es-CR',{style:'currency',currency:'USD',minimumFractionDigits:2})

function SalesOrderModal({close,onSaved}){
  const [form,setForm]=useState({fecha:new Date().toISOString().slice(0,10),cliente_id:'',mercado:'Estados Unidos',contenedor:'',observaciones:''})
  const [clientes,setClientes]=useState([]); const [loadingClientes,setLoadingClientes]=useState(true)
  const [lines,setLines]=useState([emptySaleLine()]); const [saving,setSaving]=useState(false); const [error,setError]=useState('')
  useEffect(()=>{let active=true;supabase.from('clientes').select('id,nombre').eq('activo',true).order('nombre').then(({data,error:loadError})=>{
    if(!active)return;setLoadingClientes(false);if(loadError){setError('No se pudieron cargar los clientes.');return}setClientes(data||[])
  });return()=>{active=false}},[])
  const change=e=>setForm({...form,[e.target.name]:e.target.value})
  const changeLine=(index,field,value)=>setLines(current=>current.map((line,i)=>i===index?{...line,[field]:value}:line))
  const lineBoxes=line=>(Number(line.paletas)||0)*(Number(line.cajas_por_paleta)||0)
  const lineTotal=line=>lineBoxes(line)*(Number(String(line.precio_caja).replace(',','.'))||0)
  const totalBoxes=lines.reduce((sum,line)=>sum+lineBoxes(line),0)
  const total=lines.reduce((sum,line)=>sum+lineTotal(line),0)
  const save=async()=>{
    if(!form.cliente_id){setError('Seleccione el cliente de esta orden de venta.');return}
    if(lines.some(line=>!Number.isInteger(Number(line.cajas_por_paleta))||Number(line.cajas_por_paleta)<=0)){
      setError('Escriba una cantidad válida de cajas por paleta.');return
    }
    if(lines.some(line=>Number(String(line.precio_caja).replace(',','.'))<=0)){
      setError('Escriba el precio por caja en cada producto.');return
    }
    setSaving(true);setError('')
    const codigo=`OV-${Date.now()}`
    const {data:order,error:orderError}=await supabase.from('ordenes_venta').insert({codigo,fecha:form.fecha,cliente_id:form.cliente_id,mercado:form.mercado,contenedor:form.contenedor||null,moneda:'USD',observaciones:form.observaciones||null}).select('id').single()
    if(orderError){setSaving(false);setError(`No se pudo guardar: ${orderError.message}`);return}
    const payload=lines.map(line=>({orden_venta_id:order.id,producto:line.producto,presentacion_kg:Number(line.presentacion_kg),paletas:Number(line.paletas),cajas_por_paleta:Number(line.cajas_por_paleta),cantidad_cajas:lineBoxes(line),precio_caja:Number(String(line.precio_caja).replace(',','.'))}))
    const {error:linesError}=await supabase.from('ordenes_venta_lineas').insert(payload)
    if(linesError){await supabase.from('ordenes_venta').delete().eq('id',order.id);setSaving(false);setError(`No se pudieron guardar los productos: ${linesError.message}`);return}
    setSaving(false);onSaved()
  }
  return <div className="modalwrap"><div className="modal realform salesform"><div className="modalhead"><div><span>NUEVO REGISTRO</span><h2>Orden de venta</h2></div><button onClick={close}><X/></button></div>
    <div className="formgrid"><label>Fecha<input name="fecha" type="date" value={form.fecha} onChange={change}/></label><label>Cliente<select name="cliente_id" value={form.cliente_id} onChange={change} disabled={loadingClientes}><option value="">{loadingClientes?'Cargando clientes…':'Seleccione un cliente'}</option>{clientes.map(cliente=><option key={cliente.id} value={cliente.id}>{cliente.nombre}</option>)}</select></label><label>Mercado<select name="mercado" value={form.mercado} onChange={change}><option>Estados Unidos</option><option>Europa</option><option>Canadá</option><option>Costa Rica</option></select></label><label>Contenedor<input name="contenedor" value={form.contenedor} onChange={change} placeholder="Número o referencia"/></label></div>
    <div className="sale-lines">{lines.map((line,index)=><section className="sale-line" key={index}><div className="linehead"><b>Producto {index+1}</b>{lines.length>1&&<button className="remove" type="button" onClick={()=>setLines(current=>current.filter((_,i)=>i!==index))}>Quitar producto</button>}</div><div className="formgrid">
      <label>Producto<select value={line.producto} onChange={e=>changeLine(index,'producto',e.target.value)}><option>Yuca</option><option>Ñampí</option><option>Cabeza de ñampí</option><option>Malanga lila</option><option>Malanga blanca</option><option>Camote</option></select></label>
      <label>Kilos por caja<input type="number" min="0.01" step="0.01" inputMode="decimal" value={line.presentacion_kg} onChange={e=>changeLine(index,'presentacion_kg',e.target.value)}/></label>
      <label>Cantidad de paletas<select value={line.paletas} onChange={e=>changeLine(index,'paletas',e.target.value)}>{Array.from({length:22},(_,i)=><option key={i+1} value={i+1}>{i+1} {i===0?'paleta':'paletas'}</option>)}</select></label>
      <label>Cajas por paleta<input type="number" min="1" step="1" inputMode="numeric" value={line.cajas_por_paleta} onChange={e=>changeLine(index,'cajas_por_paleta',e.target.value)} placeholder="Escriba la cantidad"/></label>
      <label className="wide">Precio por caja (USD)<input type="number" min="0.01" step="0.01" inputMode="decimal" value={line.precio_caja} onChange={e=>changeLine(index,'precio_caja',e.target.value)} placeholder="Ejemplo: 4,50"/></label>
    </div><div className="line-total"><span><small>TOTAL CALCULADO</small><b>{lineBoxes(line).toLocaleString('es-CR')} cajas · {line.paletas} paletas</b></span><strong>Subtotal: {usd.format(lineTotal(line))}</strong></div></section>)}</div>
    <button className="addline" type="button" onClick={()=>setLines(current=>[...current,emptySaleLine()])}><Plus size={18}/>Agregar producto</button>
    <label className="notes">Observaciones<textarea name="observaciones" value={form.observaciones} onChange={change} rows="3" placeholder="Información adicional…"/></label>
    <div className="order-total"><span>{totalBoxes.toLocaleString('es-CR')} cajas</span><b>Total de la orden: {usd.format(total)}</b></div>
    {error&&<div className="formerror">{error}</div>}<div className="modalactions"><button onClick={close} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':'Guardar orden'}</button></div>
  </div></div>
}

function QuickModal({title,close,onSaved,userId}){
  const [form,setForm]=useState({fecha:new Date().toISOString().slice(0,10),proveedor_id:'',nombre:'',moneda:'CRC',monto:'',observaciones:''})
  const [proveedores,setProveedores]=useState([]); const [loadingProveedores,setLoadingProveedores]=useState(title==='Órdenes de compra')
  const [saving,setSaving]=useState(false); const [error,setError]=useState('')
  useEffect(()=>{if(title!=='Órdenes de compra')return;let active=true;supabase.from('proveedores').select('id,nombre').eq('activo',true).order('nombre').then(({data,error:loadError})=>{
    if(!active)return;setLoadingProveedores(false);if(loadError){setError('No se pudieron cargar los proveedores.');return}setProveedores(data||[])
  });return()=>{active=false}},[title])
  const change=e=>setForm({...form,[e.target.name]:e.target.value})
  const save=async()=>{
    if(title==='Órdenes de compra'&&!form.proveedor_id){setError('Seleccione el proveedor de esta orden de compra.');return}
    if(!form.nombre.trim()){setError('Escriba el nombre o la descripción.');return}
    if(!supabase){setError('Falta conectar Supabase en la configuración de la aplicación.');return}
    const table=tableBySection[title]
    if(!table){setError(`El módulo ${title} todavía no tiene una tabla de guardado.`);return}
    const codigo=`${title==='Órdenes de compra'?'OC':title==='Boletas de entrada'?'BE':'OV'}-${Date.now()}`
    let payload
    if(title==='Proveedores') payload={nombre:form.nombre.trim(),tipo:'Agricultor'}
    else if(title==='Clientes') payload={nombre:form.nombre.trim()}
    else if(title==='Órdenes de compra') payload={codigo,fecha:form.fecha,proveedor_id:form.proveedor_id,producto:form.nombre.trim(),moneda:form.moneda,observaciones:form.observaciones||null,creado_por:userId}
    else if(title==='Boletas de entrada') payload={codigo,fecha_hora:`${form.fecha}T12:00:00`,producto:form.nombre.trim(),observaciones:form.observaciones||null}
    else payload={codigo,fecha:form.fecha,moneda:form.moneda,observaciones:form.observaciones||null}
    setSaving(true);setError('')
    const {error:saveError}=await supabase.from(table).insert(payload)
    setSaving(false)
    if(saveError){setError(`No se pudo guardar: ${saveError.message}`);return}
    onSaved()
  }
  return <div className="modalwrap"><div className="modal"><div className="modalhead"><div><span>NUEVO REGISTRO</span><h2>{title}</h2></div><button onClick={close}><X/></button></div><div className="formgrid"><label>Fecha<input name="fecha" type="date" value={form.fecha} onChange={change}/></label><label>Código<input placeholder="Se genera automáticamente" disabled/></label>{title==='Órdenes de compra'&&<label className="wide">Proveedor<select name="proveedor_id" value={form.proveedor_id} onChange={change} disabled={loadingProveedores}><option value="">{loadingProveedores?'Cargando proveedores…':'Seleccione un proveedor'}</option>{proveedores.map(proveedor=><option key={proveedor.id} value={proveedor.id}>{proveedor.nombre}</option>)}</select></label>}<label className="wide">{title==='Órdenes de compra'?'Producto':'Nombre o descripción'}<input name="nombre" value={form.nombre} onChange={change} placeholder={title==='Órdenes de compra'?'Escriba el producto…':'Escriba aquí…'}/></label><label>Moneda<select name="moneda" value={form.moneda} onChange={change}><option value="CRC">Colones (CRC)</option><option value="USD">Dólares (USD)</option><option value="EUR">Euros (EUR)</option></select></label><label>Monto<input name="monto" value={form.monto} onChange={change} type="number" step="0.01" placeholder="0,00"/></label><label className="wide">Observaciones<textarea name="observaciones" value={form.observaciones} onChange={change} rows="3" placeholder="Información adicional…"/></label></div>{error&&<div className="formerror">{error}</div>}<div className="modalactions"><button onClick={close} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':'Guardar registro'}</button></div></div></div>}


function AccessScreen(){
  const [email,setEmail]=useState(''); const [password,setPassword]=useState(''); const [error,setError]=useState(''); const [message,setMessage]=useState(''); const [loading,setLoading]=useState(false)
  const login=async e=>{e.preventDefault();setLoading(true);setError('');setMessage('');const {error:loginError}=await supabase.auth.signInWithPassword({email,password});setLoading(false);if(loginError)setError('No se pudo ingresar. Revise el correo y la contraseña.')}
  const recover=async()=>{if(!email.trim()){setError('Escriba primero su correo electrónico.');return}setLoading(true);setError('');setMessage('');const redirectTo=`${window.location.origin}${window.location.pathname}`;const {error:resetError}=await supabase.auth.resetPasswordForEmail(email.trim(),{redirectTo});setLoading(false);if(resetError){setError('No se pudo enviar el enlace. Intente nuevamente.');return}setMessage('Le enviamos un enlace para crear una contraseña nueva. Revise también Correo no deseado.')}
  return <div className="authpage"><div className="authcard"><div className="authmark">HN</div><span>ACCESO PRIVADO</span><h1>Gestión y Control</h1><p>Raíces y Tubérculos Huetar Norte S.A.</p><form onSubmit={login}><label>Correo electrónico<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required autoComplete="email"/></label><label>Contraseña<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required autoComplete="current-password"/></label>{error&&<div className="formerror">{error}</div>}{message&&<div className="notice">{message}</div>}<button className="primary" disabled={loading}>{loading?'Procesando…':'Ingresar'}</button><button type="button" onClick={recover} disabled={loading} style={{marginTop:12,background:'transparent',border:0,color:'#154c8c',fontWeight:800,textDecoration:'underline'}}>Olvidé mi contraseña</button></form><small>Solo pueden ingresar usuarios autorizados.</small></div></div>
}

function SetPassword({done}){
  const [password,setPassword]=useState(''); const [repeat,setRepeat]=useState(''); const [error,setError]=useState(''); const [loading,setLoading]=useState(false)
  const save=async e=>{e.preventDefault();if(password.length<8){setError('La contraseña debe tener al menos 8 caracteres.');return}if(password!==repeat){setError('Las contraseñas no coinciden.');return}setLoading(true);const {error:saveError}=await supabase.auth.updateUser({password});setLoading(false);if(saveError){setError(saveError.message);return}done()}
  return <div className="authpage"><div className="authcard"><div className="authmark">HN</div><span>NUEVA CONTRASEÑA</span><h1>Cree su contraseña</h1><p>Esta será su clave privada para ingresar a Gestión y Control.</p><form onSubmit={save}><label>Nueva contraseña<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required autoComplete="new-password"/></label><label>Repetir contraseña<input type="password" value={repeat} onChange={e=>setRepeat(e.target.value)} required autoComplete="new-password"/></label>{error&&<div className="formerror">{error}</div>}<button className="primary" disabled={loading}>{loading?'Guardando…':'Guardar nueva contraseña'}</button></form></div></div>
}

function Root(){
  const [session,setSession]=useState(undefined)
  const [profile,setProfile]=useState(undefined); const [accessError,setAccessError]=useState('')
  const [invited,setInvited]=useState(()=>initialAuthLinkType==='invite')
  const [recovering,setRecovering]=useState(()=>initialAuthLinkType==='recovery')
  useEffect(()=>{
    if(!supabase){setSession(null);return}
    let active=true
    const {data:{subscription}}=supabase.auth.onAuthStateChange((event,next)=>{
      if(!active)return
      setSession(next)
      if(event==='PASSWORD_RECOVERY')setRecovering(true)
    })
    supabase.auth.getSession().then(({data})=>{if(active)setSession(data.session)})
    return()=>{active=false;subscription.unsubscribe()}
  },[])
  useEffect(()=>{let active=true;if(!session){setProfile(undefined);return}
    supabase.from('perfiles').select('id,nombre,rol,activo').eq('id',session.user.id).single().then(({data,error})=>{
      if(!active)return
      if(error||!data||!data.activo){setAccessError('Su cuenta no tiene acceso activo. Comuníquese con el administrador.');setProfile(null);return}
      setAccessError('');setProfile(data)
    });return()=>{active=false}
  },[session])
  if((invited||recovering)&&session===undefined)return <div className="authpage"><div className="authcard"><b>Validando el enlace seguro…</b></div></div>
  if(session===undefined)return <div className="authpage"><div className="authcard"><b>Abriendo Gestión y Control…</b></div></div>
  if((invited||recovering)&&session)return <SetPassword done={()=>{setInvited(false);setRecovering(false);window.history.replaceState({},document.title,window.location.pathname)}}/>
  if(!session)return <AccessScreen/>
  if(profile===undefined)return <div className="authpage"><div className="authcard"><b>Verificando permisos…</b></div></div>
  if(!profile)return <div className="authpage"><div className="authcard"><h1>Acceso no autorizado</h1><p>{accessError}</p><button className="primary" onClick={()=>supabase.auth.signOut()}>Cerrar sesión</button></div></div>
  return <App profile={profile}/>
}

createRoot(document.getElementById('root')).render(<Root/>)

import React, { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { LayoutDashboard, ShoppingCart, Truck, Factory, WalletCards, Users, UserRound, Landmark, Menu, X, Plus, Search, ChevronRight, ArrowUpRight, ArrowDownRight, CircleDollarSign, PackageCheck, Settings, LogOut } from 'lucide-react'
import { initialAuthLinkType, isSupabaseReady, supabase } from './supabase'
import './styles.css'
import PurchaseOrderModal from './purchase-form'
import SalesOrderModal from './sales-form'
import ClientModal from './client-modal'
import ProviderModal from './provider-modal'
import CartonInventory from './carton-inventory'
import SupplyInventory from './supply-inventory'
import PlasticCrates from './plastic-crates'
import SecondInventory from './second-inventory'
import YucaBalance from './yuca-balance'
import Finance,{cash,useFinance} from './finance'
import LoadMap from './load-map'
import PlantReceipt from './plant-receipt'
import Workers from './workers'
import WeeklyClose from './weekly-close'
import {addDays,costaRicaToday,isoWeek,mondayOf,sundayOf} from './weekly-model'
import Farms from './farms'
import Companies from './companies'
import UsersSettings from './users-settings'
import OrderNeeds from './order-needs'


const nav = [
  ['Resumen', LayoutDashboard], ['Órdenes de compra', ShoppingCart], ['Boletas de entrada', Truck],
  ['Producción y rendimientos', Factory], ['Mapa de carga', PackageCheck], ['Saldo de yuca en planta', PackageCheck], ['Segundas y rechazo', PackageCheck], ['Órdenes de venta', PackageCheck],
  ['Proveedores', Users], ['Clientes', UserRound], ['Colaboradores', Users], ['Empresas', Landmark],
  ['Inventarios', PackageCheck], ['Finanzas', WalletCards], ['Efectivo', WalletCards], ['Bancos', Landmark], ['Corte semanal', CircleDollarSign], ['Fincas', PackageCheck]
]
const inventorySections=[['Inventario de cartones',PackageCheck],['Inventario de insumos',PackageCheck],['Cajas plásticas',PackageCheck]]
const visibleSections={planta:['Boletas de entrada','Mapa de carga','Saldo de yuca en planta'],bodega:['Inventarios'],finca:[],chofer:[]}
const inInventory=section=>inventorySections.some(([label])=>label===section)
function InventoryHome({go}){return <><div className="modulebar"><p>Seleccione el inventario que desea consultar o actualizar.</p></div><div className="module-hub">{inventorySections.map(([label,Icon])=><button key={label} type="button" onClick={()=>go(label)}><Icon size={26}/><span>{label}</span><ChevronRight size={20}/></button>)}</div></>}



const money = new Intl.NumberFormat('es-CR',{style:'currency',currency:'CRC',maximumFractionDigits:0})
function weekOf(value){
  if(!value)return ''
  const parsed=new Date(value)
  if(Number.isNaN(parsed.getTime()))return ''
  const day=/^\d{4}-\d{2}-\d{2}$/.test(value)?value:costaRicaToday(parsed)
  const monday=new Date(`${day}T12:00:00Z`).getUTCDay()===0?addDays(day,1):day
  const {year,week}=isoWeek(monday)
  return `${year}-${String(week).padStart(2,'0')}`
}


function App({profile}){
  const allowed=visibleSections[profile.rol]||nav.map(([label])=>label)
  const [section,setSection]=useState(allowed[0]||'Sin módulos asignados'); const [open,setOpen]=useState(false); const [search,setSearch]=useState(''); const [modal,setModal]=useState(false); const [editingClient,setEditingClient]=useState(null); const [plantOrderId,setPlantOrderId]=useState(null); const [refresh,setRefresh]=useState(0); const [salesWeek,setSalesWeek]=useState(()=>weekOf(costaRicaToday()))
  const go=(x)=>{setSection(x);setOpen(false);setSearch('')}
  return <div className="app">
    <aside className={open?'sidebar open':'sidebar'}>
      <div className="brand"><div className="brandmark">HN</div><div><b>Gestión y Control</b><span>Huetar Norte S.A.</span></div><button className="close" onClick={()=>setOpen(false)}><X/></button></div>
      <nav>{nav.filter(([label])=>allowed.includes(label)).map(([label,Icon])=><button key={label} className={section===label||label==='Inventarios'&&inInventory(section)||label==='Finanzas'&&['Cuentas por cobrar','Cuentas por pagar'].includes(section)||label==='Empresas'&&['Bancos Agro Solano','Efectivo Agro Solano'].includes(section)?'active':''} onClick={()=>go(label)}><Icon size={19}/><span>{label}</span></button>)}</nav>
      <div className="sidefoot">{profile.rol==='administrador'&&<button className={section==='Configuración'?'active':''} onClick={()=>go('Configuración')}><Settings size={19}/>Configuración</button>}<button onClick={()=>supabase.auth.signOut()}><LogOut size={19}/>Cerrar sesión</button></div>
    </aside>
    {open&&<div className="scrim" onClick={()=>setOpen(false)}/>} 
    <main>
      <header><button className="menubtn" onClick={()=>setOpen(true)}><Menu/></button><div><span className="eyebrow">RAÍCES Y TUBÉRCULOS HUETAR NORTE S.A.</span><h1>{section}</h1></div><div className="headerRight"><button type="button" className="refresh-app" onClick={()=>{const url=new URL(window.location.href);url.searchParams.set('actualiza',String(Date.now()));window.location.assign(url.href)}} title="Cargar la versión más reciente">Actualizar app</button><div className="exchange"><span>Tipo de cambio</span><b>USD ₡ 493,50</b><small>EUR ₡ 579,20</small></div><div className="avatar">OS</div></div></header>
      <div className="content">{section==='Configuración'&&profile.rol==='administrador'?<UsersSettings profile={profile}/>:!allowed.length?<div className="notice">Su usuario todavía no tiene módulos asignados.</div>:section==='Resumen'?<Dashboard go={go} profile={profile} refresh={refresh}/>:section==='Mapa de carga'?<LoadMap go={go}/>:section==='Saldo de yuca en planta'?<YucaBalance profile={profile}/>:section==='Inventarios'?<InventoryHome go={go}/>:section==='Corte semanal'?<WeeklyClose/>:section==='Fincas'?<Farms/>:section==='Empresas'?<Companies go={go}/>:['Finanzas','Bancos','Bancos Agro Solano','Efectivo','Efectivo Agro Solano','Cuentas por cobrar','Cuentas por pagar'].includes(section)?<Finance key={section} section={section} go={go}/>:section==='Inventario de cartones'?<CartonInventory/>:section==='Inventario de insumos'?<SupplyInventory/>:section==='Cajas plásticas'?<PlasticCrates/>:section==='Segundas y rechazo'?<SecondInventory/>:section==='Colaboradores'?<Workers/>:<Module title={section} role={profile.rol} search={search} setSearch={setSearch} onNew={()=>{setEditingClient(null);setModal(true)}} onEdit={item=>{setEditingClient(item);setModal(true)}} refresh={refresh} salesWeek={salesWeek} setSalesWeek={setSalesWeek}/>}</div>
    </main>
    {modal&&(section==='Órdenes de venta'
      ? <SalesOrderModal order={editingClient} selectedWeek={salesWeek} close={()=>{setModal(false);setEditingClient(null)}} onSaved={()=>{setModal(false);setEditingClient(null);setRefresh(x=>x+1)}}/>
      : section==='Órdenes de compra'
        ? <PurchaseOrderModal order={editingClient} userId={profile.id} close={()=>{setModal(false);setEditingClient(null)}} onSaved={()=>{setModal(false);setEditingClient(null);setRefresh(x=>x+1)}} onOpenReceipt={async receiptId=>{let selected=null;if(receiptId){const {data,error}=await supabase.from('boletas_entrada').select('*').eq('id',receiptId).single();if(error)throw error;selected=data}setPlantOrderId(editingClient.id);setEditingClient(selected);setSection('Boletas de entrada');setModal(true)}}/>
      : section==='Boletas de entrada'
        ? <PlantReceipt receipt={editingClient} initialOrderId={plantOrderId} role={profile.rol} close={()=>{setModal(false);setEditingClient(null);setPlantOrderId(null)}} onSaved={()=>{setModal(false);setEditingClient(null);setPlantOrderId(null);setRefresh(x=>x+1)}}/>
      : section==='Proveedores'
        ? <ProviderModal provider={editingClient} close={()=>{setModal(false);setEditingClient(null)}} onSaved={()=>{setModal(false);setEditingClient(null);setRefresh(x=>x+1)}}/>
      : section==='Clientes'
        ? <ClientModal client={editingClient} close={()=>{setModal(false);setEditingClient(null)}} onSaved={()=>{setModal(false);setEditingClient(null);setRefresh(x=>x+1)}}/>
        : <QuickModal title={section} userId={profile.id} close={()=>setModal(false)} onSaved={()=>{setModal(false);setRefresh(x=>x+1)}}/>)}
  </div>
}


function Dashboard({go,profile,refresh}){
  const {data,error,loading}=useFinance(),[plant,setPlant]=useState({count:0,kg:0})
  useEffect(()=>{let active=true;supabase.from('boletas_entrada').select('kg_estimados').then(({data:receipts})=>{if(active)setPlant({count:receipts?.length||0,kg:(receipts||[]).reduce((sum,r)=>sum+Number(r.kg_estimados||0),0)})});return()=>{active=false}},[refresh])
  const receivable=currency=>data.receivables.filter(r=>r.moneda===currency&&r.etapa!=='Pedido previsto').reduce((sum,r)=>sum+Math.max(0,Number(r.monto)-Number(r.aplicado)),0)
  const payable=data.payables.filter(r=>r.etapa!=='Faltan precios').reduce((sum,r)=>sum+Math.max(0,Number(r.monto)-Number(r.aplicado)),0)
  const weekStart=sundayOf(costaRicaToday())
  const weeklySales=data.receivables.filter(r=>r.fecha>=weekStart&&r.moneda==='USD'&&r.origen==='venta_exportacion').reduce((sum,r)=>sum+Number(r.monto),0)
  const weeklyLocal=data.receivables.filter(r=>r.fecha>=weekStart&&r.moneda==='CRC'&&r.origen==='venta_local').reduce((sum,r)=>sum+Number(r.monto),0)
  return <>{!isSupabaseReady&&<div className="notice">Falta conectar Supabase.</div>}
  <section className="hero"><div><span>ACCESO {profile.rol.toUpperCase()}</span><h2>Buenos días, {profile.nombre.split(' ')[0]}</h2><p>Resumen calculado a partir de los registros guardados.</p></div><button onClick={()=>go('Órdenes de venta')}><Plus size={18}/> Nueva orden de venta</button></section>
  {loading?<div className="empty">Cargando cifras reales…</div>:error?<div className="formerror">{error}</div>:<><div className="stats"><Stat title="Pedidos USD esta semana" value={cash(weeklySales,'USD')} note="Valor previsto de órdenes" icon={CircleDollarSign}/><Stat title="Ventas locales esta semana" value={cash(weeklyLocal)} note="Segundas y rechazo registrados" icon={ShoppingCart}/><Stat title="Por cobrar USD" value={cash(receivable('USD'),'USD')} note={`${data.receivables.length} ventas y pedidos`} icon={ArrowUpRight}/><Stat title="Por pagar estimado" value={cash(payable)} note="Compras con rendimiento y precio" icon={ArrowDownRight}/></div>
  <div className="grid2"><section className="panel"><div className="panelhead"><div><h3>Operación de planta</h3><p>Datos registrados</p></div><button onClick={()=>go('Boletas de entrada')}>Ver boletas <ChevronRight size={16}/></button></div><div className="plant"><div><b>{plant.count}</b><span>Boletas recibidas</span></div><div><b>{plant.kg.toLocaleString('es-CR')}</b><span>kg estimados de ingreso</span></div></div></section><section className="panel"><div className="panelhead"><div><h3>Por cobrar y bancos</h3><p>Colones y dólares se muestran separados</p></div></div><div className="finance-summary"><article><span>Por cobrar CRC</span><strong>{cash(receivable('CRC'))}</strong></article><article><span>Cuentas bancarias</span><strong>{data.accounts.filter(account=>account.tipo_cuenta==='banco').length}</strong></article></div></section></div></>}
  <OrderNeeds refresh={refresh}/>
  <section className="quick"><h3>Accesos rápidos</h3><div><button onClick={()=>go('Órdenes de compra')}><ShoppingCart/>Compras</button><button onClick={()=>go('Cuentas por cobrar')}><ArrowUpRight/>Por cobrar</button><button onClick={()=>go('Cuentas por pagar')}><ArrowDownRight/>Por pagar</button><button onClick={()=>go('Bancos')}><Landmark/>Bancos</button><button onClick={()=>go('Colaboradores')}><Users/>Colaboradores</button></div></section></>
}


function Stat({title,value,note,icon:Icon,up,warning}){return <article className={warning?'stat warning':'stat'}><div className="staticon"><Icon size={22}/></div><span>{title}</span><b>{value}</b><small className={up?'positive':''}>{note}</small></article>}


function Module({title,role,search,setSearch,onNew,onEdit,refresh,salesWeek,setSalesWeek}){
  const [items,setItems]=useState([]); const [loading,setLoading]=useState(false); const [error,setError]=useState('')
  const [receiptOrders,setReceiptOrders]=useState({})
  const [salesClients,setSalesClients]=useState({})
  const [closedPurchases,setClosedPurchases]=useState({})
  const [linkedPurchases,setLinkedPurchases]=useState({})
  const [retry,setRetry]=useState(0)
  const [history,setHistory]=useState(false);const [voided,setVoided]=useState(false);const [closing,setClosing]=useState(null)
  const [otherWeek,setOtherWeek]=useState(()=>title==='Órdenes de compra'?'all':weekOf(costaRicaToday()))
  const week=title==='Órdenes de venta'?salesWeek:otherWeek
  const setWeek=title==='Órdenes de venta'?setSalesWeek:setOtherWeek
  useEffect(()=>{setOtherWeek(title==='Órdenes de compra'?'all':weekOf(costaRicaToday()));setHistory(false);setVoided(false)},[title])
  const table=tableBySection[title]
  useEffect(()=>{let active=true;if(!table){setItems([]);return}
    setLoading(true);setError('')
    const load=async()=>{
      const [result,orders,purchaseReceipts,clientsResult,purchaseTypes]=await Promise.all([supabase.from(table).select(title==='Órdenes de venta'?'*,ordenes_venta_lineas(total)':'*').order('creado_en',{ascending:false}).limit(title==='Órdenes de compra'?1000:100),title==='Boletas de entrada'?supabase.rpc('ordenes_compra_para_planta',{p_incluir_vinculadas:true}):Promise.resolve({data:[],error:null}),title==='Órdenes de compra'?supabase.from('boletas_entrada').select('orden_compra_id,finalizada_en').limit(1000):Promise.resolve({data:[],error:null}),title==='Órdenes de venta'?supabase.from('clientes').select('id,nombre'):Promise.resolve({data:[],error:null}),title==='Boletas de entrada'&&['administrador','oficina'].includes(role)?supabase.from('ordenes_compra').select('id,tipo_compra,producto').limit(200):Promise.resolve({data:[],error:null})])
      if(!active)return;setLoading(false)
      if(result.error){setError(`No se pudieron cargar los datos: ${result.error.message}`);return}
      setItems(['Proveedores','Clientes'].includes(title)?(result.data||[]).filter(x=>x.activo!==false):result.data||[])
      if(title==='Órdenes de venta'){if(clientsResult.error){setError(`No se pudieron cargar los clientes: ${clientsResult.error.message}`);return}setSalesClients(Object.fromEntries((clientsResult.data||[]).map(client=>[client.id,client.nombre])))}
      if(title==='Boletas de entrada'&&orders.error){setError(`No se pudieron cargar los productores de las boletas: ${orders.error.message}`);return}
      const types=Object.fromEntries((purchaseTypes.data||[]).map(order=>[order.id,order]))
      setReceiptOrders(Object.fromEntries((orders.data||[]).map(order=>[order.id,{...order,...types[order.id]}])))
      if(title==='Órdenes de compra'&&!purchaseReceipts.error){const grouped={};for(const b of purchaseReceipts.data||[]){const state=grouped[b.orden_compra_id]||{count:0,closed:0};state.count++;if(b.finalizada_en)state.closed++;grouped[b.orden_compra_id]=state}setClosedPurchases(Object.fromEntries(Object.entries(grouped).map(([id,x])=>[id,x.count>0&&x.count===x.closed])));setLinkedPurchases(Object.fromEntries(Object.keys(grouped).map(id=>[id,true])))}
    }
    load();return()=>{active=false}
  },[table,refresh,retry,role])
  const voidPurchase=async item=>{
    if(!window.confirm(`¿Anular la orden ${item.codigo} de ${item.productor_nombre||'este productor'}?\n\nQuedará en la pestaña Anuladas y no podrá usarse para registrar boletas ni pagos.`))return
    setClosing(item.id);setError('')
    const {error:failure}=await supabase.rpc('anular_orden_compra',{p_orden_id:item.id})
    setClosing(null)
    if(failure){setError(`No se pudo anular: ${failure.message}`);return}
    setItems(current=>current.map(o=>o.id===item.id?{...o,estado:'Anulada'}:o))
  }
  const finish=async item=>{
    setClosing(item.id);setError('')
    const [purchase,parts]=await Promise.all([supabase.from('ordenes_compra').select('producto,tipo_compra,precio_en_pie,precio_europa,precio_eeuu,precio_segunda_gruesa,precio_segunda_menuda,precio_rechazo,precio_campo,campo_promedio_caja_kg').eq('id',item.orden_compra_id).single(),supabase.from('boleta_rendimientos').select('calidad,kg_resultado,paga_productor,cajas,kg_manual,presentacion_kg').eq('boleta_id',item.id)])
    if(purchase.error||parts.error){setClosing(null);setError(`No se pudo revisar la liquidación: ${(purchase.error||parts.error).message}`);return}
    const order=purchase.data
    if((parts.data||[]).some(part=>part.cajas>0&&part.kg_manual!==null)){setClosing(null);setError('Hay partidas con cajas y kilos manuales a la vez. Edite la boleta y guárdela para calcular el peso total por cajas antes de finalizar.');return}
    const fixedTruck=order.tipo_compra==='Puesto en camión'||order.tipo_compra==='En campo'&&order.campo_promedio_caja_kg!=null
    let estimate=0
    const breakdown=[]
    if(order.tipo_compra==='En pie'){estimate=Number(order.precio_en_pie||0);breakdown.push(`Precio pactado del lote: ${money.format(estimate)}`)}
    else for(const part of parts.data||[]){if(fixedTruck||!part.paga_productor)continue
      const quality=part.calidad
      const rate=['Ñampí','Cabeza de ñampí'].includes(order.producto)?order.precio_campo:quality==='Exportable Europa'?order.precio_europa:quality==='Exportable estadounidense'?order.precio_eeuu:quality==='Segunda gruesa'?order.precio_segunda_gruesa:quality==='Segunda menuda'?order.precio_segunda_menuda:quality.startsWith('Rechazo')?order.precio_rechazo:order.precio_campo
      if(rate===null||rate===undefined){setClosing(null);setError(`Falta el precio de ${quality} en la orden de compra.`);return}
      estimate+=Number(part.kg_resultado||0)/46*Number(rate)
      breakdown.push(`${quality}: ${Number(part.kg_resultado||0).toLocaleString('es-CR')} kg × ${money.format(rate)} por quintal`)
    }
    setClosing(null)
    if(!window.confirm(`Boleta ${item.codigo}\n\n${order.tipo_compra==='En pie'&&['Ñampí','Cabeza de ñampí'].includes(order.producto)?'El precio del lote ya figura una sola vez en cuentas por pagar. Esta boleta se sellará sin crear otro pago. La orden seguirá abierta para nuevas entregas.':fixedTruck?'Compra con pago pactado: la cuenta del productor y el flete figuran por separado desde que se guardó la orden. El rendimiento de planta solo sirve para comparar y no cambia el pago.':`${breakdown.join('\n')}\n\nCuenta por pagar aproximada: ${money.format(estimate)}.`}\n\n¿Finalizar y sellar esta boleta?`))return
    setClosing(item.id)
    const {data,error:failure}=await supabase.rpc('finalizar_boleta_entrada',{p_boleta_id:item.id})
    setClosing(null)
    if(failure){setError(`No se pudo finalizar: ${failure.message}`);return}
    setItems(current=>current.map(b=>b.id===item.id?{...b,finalizada_en:new Date().toISOString(),monto_cxp:data}:b))
  }
  const finishPiePurchase=async item=>{
    if(!window.confirm(`¿Finalizar la compra en pie ${item.codigo}?\n\nRevise antes las boletas y ventas directas: después no se podrán añadir más. El precio del lote seguirá apareciendo una sola vez en cuentas por pagar.`))return
    setClosing(item.id);setError('')
    const {error:failure}=await supabase.rpc('finalizar_compra_en_pie',{p_orden_id:item.id})
    setClosing(null)
    if(failure){setError(`No se pudo finalizar la compra: ${failure.message}`);return}
    setItems(current=>current.map(o=>o.id===item.id?{...o,en_pie_finalizada_en:new Date().toISOString()}:o))
  }
  const finishOrder=async item=>{
    const amount=(item.ordenes_venta_lineas||[]).reduce((sum,line)=>sum+Number(line.total||0),0)
    const currency=item.moneda||'USD'
    if(!window.confirm(`Pedido ${item.codigo}\n\nCuenta por cobrar: ${new Intl.NumberFormat('es-CR',{style:'currency',currency}).format(amount)}.\n\n¿Finalizar el pedido? Todas las cajas y sus boletas deben estar completas.`))return
    setClosing(item.id);setError('')
    const {data,error:failure}=await supabase.rpc('finalizar_orden_venta',{p_orden_id:item.id})
    setClosing(null)
    if(failure){setError(`No se pudo finalizar: ${failure.message}`);return}
    setItems(current=>current.map(o=>o.id===item.id?{...o,finalizada_en:new Date().toISOString(),monto_cxc:data}:o))
  }
  const rows=useMemo(()=>items.map((item,index)=>({
    key:item.id||index,
    item,
    codigo:item.codigo||`${title==='Proveedores'?'PR':'CL'}-${String(index+1).padStart(3,'0')}`,
    principal:title==='Órdenes de venta'?`${salesClients[item.cliente_id]||'Cliente pendiente'}${item.numero_cliente?` ${item.numero_cliente}`:''}`:title==='Boletas de entrada'?`${receiptOrders[item.orden_compra_id]?.productor_nombre||'Productor pendiente'} · ${item.producto||receiptOrders[item.orden_compra_id]?.producto||'Producto pendiente'}`:item.nombre||item.productor_nombre||item.producto||item.mercado||'Registro',
    detalle:title==='Órdenes de venta'?`Salida ${item.fecha_salida||'pendiente'} · Pedido recibido ${item.fecha||'sin fecha'} · ${item.mercado||'Mercado pendiente'}${item.contenedor?` · Contenedor ${item.contenedor}`:''}`:title==='Boletas de entrada'?`${item.producto||receiptOrders[item.orden_compra_id]?.producto||'Producto'} · ${receiptOrders[item.orden_compra_id]?.codigo||'Sin orden de compra'}`:title==='Órdenes de compra'?`${item.fecha||'Sin fecha'} · ${item.producto||'Producto pendiente'}${item.lugar?` · ${item.lugar}`:''}${item.boleta_campo_referencia?` · Boleta ${item.boleta_campo_referencia}`:''}${item.tipo_compra==='En pie'&&['Ñampí','Cabeza de ñampí'].includes(item.producto)&&!item.en_pie_finalizada_en?` · Abierta desde semana ${Number(weekOf(item.fecha).slice(-2))}`:''}`:item.tipo||item.lugar||item.finca_lugar||item.mercado||item.observaciones||'Sin detalle',
    estado:title==='Órdenes de compra'?(item.estado==='Anulada'?'Anulada':item.tipo_compra==='En pie'&&['Ñampí','Cabeza de ñampí'].includes(item.producto)?item.en_pie_finalizada_en?'Finalizada':'Abierta':closedPurchases[item.id]?'Sellada':'Pendiente'):['Boletas de entrada','Órdenes de venta'].includes(title)?(item.estado==='Anulada'?'Anulada':item.finalizada_en?'Finalizada':'Pendiente'):item.estado||(item.activo===false?'Inactivo':'Activo'),
    monto:title==='Boletas de entrada'&&item.finalizada_en&&role!=='planta'?money.format(item.monto_cxp||0):title==='Órdenes de venta'&&item.finalizada_en?new Intl.NumberFormat('es-CR',{style:'currency',currency:item.moneda||'USD'}).format(item.monto_cxc||0):title==='Órdenes de venta'&&item.ordenes_venta_lineas?new Intl.NumberFormat('es-CR',{style:'currency',currency:item.moneda||'USD'}).format(item.ordenes_venta_lineas.reduce((sum,l)=>sum+Number(l.total||0),0)):item.kg_estimados?`${Number(item.kg_estimados).toLocaleString('es-CR')} kg`:item.moneda||''
  })).filter(r=>(!['Boletas de entrada','Órdenes de venta','Órdenes de compra'].includes(title)||((title==='Órdenes de compra'?(voided?r.item.estado==='Anulada':r.item.estado!=='Anulada'&&(r.item.tipo_compra==='En pie'&&['Ñampí','Cabeza de ñampí'].includes(r.item.producto)?Boolean(r.item.en_pie_finalizada_en):Boolean(closedPurchases[r.item.id]))===history):Boolean(r.item.finalizada_en)===history)&&(week==='all'||(title==='Órdenes de compra'&&r.item.tipo_compra==='En pie'&&['Ñampí','Cabeza de ñampí'].includes(r.item.producto)?r.item.en_pie_finalizada_en?weekOf(r.item.en_pie_finalizada_en)===week:week>=weekOf(r.item.fecha):weekOf(title==='Órdenes de venta'?(r.item.fecha_salida||r.item.fecha):(r.item.fecha_hora||r.item.fecha))===week))))&&`${r.codigo} ${r.principal} ${r.detalle} ${r.estado}`.toLowerCase().includes(search.toLowerCase())).filter(r=>title!=='Órdenes de venta'||(voided?r.item.estado==='Anulada':r.item.estado!=='Anulada')).sort((a,b)=>title==='Órdenes de compra'?(a.item.fecha||'').localeCompare(b.item.fecha||'')||(a.item.creado_en||'').localeCompare(b.item.creado_en||''):0),[items,search,title,receiptOrders,salesClients,closedPurchases,history,voided,role,week])
  return <><div className="modulebar"><div><p>Administre y consulte la información de {title.toLowerCase()}.</p></div>{table&&<button className="primary" onClick={onNew}><Plus size={18}/>Nuevo registro</button>}</div><section className="panel tablepanel">{['Boletas de entrada','Órdenes de venta','Órdenes de compra'].includes(title)&&<div className="load-selector"><button type="button" className={!history&&!voided?'primary':''} onClick={()=>{setHistory(false);setVoided(false)}}>Pendientes</button><button type="button" className={history&&!voided?'primary':''} onClick={()=>{setHistory(true);setVoided(false)}}>Historial de finalizadas</button>{['Órdenes de compra','Órdenes de venta'].includes(title)&&<button type="button" className={voided?'primary':''} onClick={()=>setVoided(true)}>Anuladas</button>}<label>{title==='Órdenes de venta'?'Semana de salida':'Semana'}<select value={week} onChange={e=>setWeek(e.target.value)}><option value="all">Todas las semanas</option>{[...new Set([weekOf(costaRicaToday()),weekOf(addDays(costaRicaToday(),7)),week,...items.map(x=>weekOf(title==='Órdenes de venta'?(x.fecha_salida||x.fecha):(x.fecha_hora||x.fecha))),...items.filter(x=>title==='Órdenes de compra'&&x.en_pie_finalizada_en).map(x=>weekOf(x.en_pie_finalizada_en))])].filter(Boolean).sort().reverse().map(x=><option key={x} value={x}>Semana {Number(x.slice(-2))} · {x.slice(0,4)}</option>)}</select></label>{title==='Órdenes de venta'&&week!=='all'&&<button type="button" onClick={()=>{const monday=mondayOf(`${week.slice(0,4)}-01-04`);setWeek(weekOf(addDays(monday,(Number(week.slice(-2))-1)*7+7)))}}>Semana siguiente →</button>}</div>}<div className="filters"><label><Search size={18}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Buscar por código, nombre o estado…"/></label><button>Todos los estados</button></div>{error&&<div className="formerror">{error} <button type="button" onClick={()=>setRetry(n=>n+1)}>Reintentar</button></div>}{loading?<div className="empty"><p>Cargando información…</p></div>:rows.length?<div className="rows">{rows.map(r=><article key={r.key}><div className="code">{r.codigo}</div><div className="who"><b>{r.principal}</b><span>{r.detalle}</span></div><span className="pill">{r.estado}</span><strong>{r.monto}</strong>{title==='Órdenes de venta'&&!r.item.finalizada_en&&r.item.estado!=='Anulada'&&['administrador','oficina'].includes(role)&&<button type="button" onClick={()=>finishOrder(r.item)} disabled={closing===r.item.id}>{closing===r.item.id?'Finalizando…':'Finalizar pedido'}</button>}{title==='Boletas de entrada'&&!r.item.finalizada_en&&['administrador','oficina'].includes(role)&&<button type="button" onClick={()=>finish(r.item)} disabled={closing===r.item.id}>{closing===r.item.id?'Finalizando…':'Finalizar'}</button>}{title==='Órdenes de compra'&&r.item.tipo_compra==='En pie'&&['Ñampí','Cabeza de ñampí'].includes(r.item.producto)&&!r.item.en_pie_finalizada_en&&['administrador','oficina'].includes(role)&&<button type="button" onClick={()=>finishPiePurchase(r.item)} disabled={closing===r.item.id}>{closing===r.item.id?'Finalizando…':'Finalizar compra en pie'}</button>}{title==='Órdenes de compra'&&r.item.estado!=='Anulada'&&!linkedPurchases[r.item.id]&&['administrador','oficina'].includes(role)&&<button type="button" onClick={()=>voidPurchase(r.item)} disabled={closing===r.item.id}>{closing===r.item.id?'Anulando…':'Anular'}</button>}<button className={['Clientes','Proveedores','Órdenes de compra','Órdenes de venta','Boletas de entrada'].includes(title)?'arrow edit-client':'arrow'} type="button" onClick={()=>onEdit(r.item)} aria-label={`Editar ${r.principal}`} disabled={!['Clientes','Proveedores','Órdenes de compra','Órdenes de venta','Boletas de entrada'].includes(title)||(title==='Órdenes de venta'||title==='Boletas de entrada'&&!['administrador','oficina'].includes(role))&&!!r.item.finalizada_en||['Órdenes de compra','Órdenes de venta'].includes(title)&&r.item.estado==='Anulada'}>{['Clientes','Proveedores','Órdenes de compra','Órdenes de venta','Boletas de entrada'].includes(title)?'Editar':<ChevronRight/>}</button></article>)}</div>:<div className="empty"><PackageCheck size={42}/><h3>Sin registros todavía</h3><p>{['Boletas de entrada','Órdenes de venta','Órdenes de compra'].includes(title)?(voided?'No hay órdenes anuladas.':history?'Todavía no hay registros finalizados.':'No hay registros pendientes.'):table?`Puede crear el primer registro de ${title.toLowerCase()}.`:'Este módulo se conectará en la siguiente etapa.'}</p>{table&&<button className="primary" onClick={onNew}><Plus size={18}/>Crear registro</button>}</div>}</section></>
}


const tableBySection = {
  'Órdenes de compra':'ordenes_compra', 'Boletas de entrada':'boletas_entrada',
  'Órdenes de venta':'ordenes_venta', Proveedores:'proveedores', Clientes:'clientes'
}


function QuickModal({title,close,onSaved,userId}){
  const [form,setForm]=useState({fecha:new Date().toISOString().slice(0,10),proveedor_id:'',orden_compra_id:'',nombre:'',moneda:'CRC',monto:'',observaciones:''})
  const [proveedores,setProveedores]=useState([]); const [ordenes,setOrdenes]=useState([]); const [loadingProveedores,setLoadingProveedores]=useState(title==='Órdenes de compra')
  const [saving,setSaving]=useState(false); const [error,setError]=useState('')
  useEffect(()=>{if(title!=='Órdenes de compra')return;let active=true;supabase.from('proveedores').select('id,nombre').eq('activo',true).order('nombre').then(({data,error:loadError})=>{
    if(!active)return;setLoadingProveedores(false);if(loadError){setError('No se pudieron cargar los proveedores.');return}setProveedores(data||[])
  });return()=>{active=false}},[title])
  useEffect(()=>{if(title!=='Boletas de entrada')return;let active=true;supabase.from('ordenes_compra').select('id,codigo,producto,productor_nombre').order('fecha',{ascending:false}).limit(100).then(({data})=>{if(active)setOrdenes(data||[])});return()=>{active=false}},[title])
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
    else if(title==='Órdenes de compra') payload={codigo,fecha:form.fecha,proveedor_id:form.proveedor_id,producto:form.nombre.trim(),moneda:form.moneda,observaciones:form.observaciones||null,creado_por:userId}
    else if(title==='Boletas de entrada') payload={codigo,fecha_hora:`${form.fecha}T12:00:00`,orden_compra_id:form.orden_compra_id||null,producto:form.nombre.trim(),observaciones:form.observaciones||null}
    else payload={codigo,fecha:form.fecha,moneda:form.moneda,observaciones:form.observaciones||null}
    setSaving(true);setError('')
    const {error:saveError}=await supabase.from(table).insert(payload)
    setSaving(false)
    if(saveError){setError(`No se pudo guardar: ${saveError.message}`);return}
    onSaved()
  }
  return <div className="modalwrap"><div className="modal"><div className="modalhead"><div><span>NUEVO REGISTRO</span><h2>{title}</h2></div><button onClick={close}><X/></button></div><div className="formgrid"><label>Fecha<input name="fecha" type="date" value={form.fecha} onChange={change}/></label><label>Código<input placeholder="Se genera automáticamente" disabled/></label>{title==='Boletas de entrada'&&<label className="wide">Orden de compra relacionada<select name="orden_compra_id" value={form.orden_compra_id} onChange={change}><option value="">Enlazar después</option>{ordenes.map(o=><option key={o.id} value={o.id}>{o.codigo} · {o.productor_nombre||'Productor'} · {o.producto}</option>)}</select></label>}{title==='Órdenes de compra'&&<label className="wide">Proveedor<select name="proveedor_id" value={form.proveedor_id} onChange={change} disabled={loadingProveedores}><option value="">{loadingProveedores?'Cargando proveedores…':'Seleccione un proveedor'}</option>{proveedores.map(proveedor=><option key={proveedor.id} value={proveedor.id}>{proveedor.nombre}</option>)}</select></label>}<label className="wide">{title==='Órdenes de compra'?'Producto':'Nombre o descripción'}<input name="nombre" value={form.nombre} onChange={change} placeholder={title==='Órdenes de compra'?'Escriba el producto…':'Escriba aquí…'}/></label><label>Moneda<select name="moneda" value={form.moneda} onChange={change}><option value="CRC">Colones (CRC)</option><option value="USD">Dólares (USD)</option><option value="EUR">Euros (EUR)</option></select></label><label>Monto<input name="monto" value={form.monto} onChange={change} type="number" step="0.01" placeholder="0,00"/></label><label className="wide">Observaciones<textarea name="observaciones" value={form.observaciones} onChange={change} rows="3" placeholder="Información adicional…"/></label></div>{error&&<div className="formerror">{error}</div>}<div className="modalactions"><button onClick={close} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':'Guardar registro'}</button></div></div></div>}


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

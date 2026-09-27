import React,{useEffect,useState} from 'react'
import {Plus,X} from 'lucide-react'
import {supabase} from './supabase'
import {costaRicaToday} from './weekly-model'

const line=()=>({insumo_id:'',presentacion:'',factor:'1',cantidad:'',precio:''})
const fresh=()=>({fecha:costaRicaToday(),proveedor_id:'',proveedor_nombre:'',moneda:'USD',observaciones:'',lineas:[line()]})
const fmt=(value,currency)=>new Intl.NumberFormat('es-CR',{style:'currency',currency:currency||'CRC'}).format(Number(value)||0)
export default function SupplyPurchases({go}){
  const [orders,setOrders]=useState([]),[lines,setLines]=useState([]),[supplies,setSupplies]=useState([]),[providers,setProviders]=useState([])
  const [form,setForm]=useState(null),[receiving,setReceiving]=useState(null),[receipt,setReceipt]=useState({cantidad:'',fecha:costaRicaToday(),referencia:''})
  const [error,setError]=useState(''),[saving,setSaving]=useState(false),[loading,setLoading]=useState(true)
  const load=async()=>{
    const results=await Promise.all([
      supabase.from('ordenes_insumos').select('*').order('creado_en',{ascending:false}).limit(500),
      supabase.from('ordenes_insumos_lineas').select('*').limit(2000),
      supabase.from('insumos').select('id,nombre,unidad,activo,presentacion_compra,unidades_por_presentacion,precio_referencia,moneda_referencia').order('nombre'),
      supabase.from('proveedores').select('id,nombre').eq('activo',true).order('nombre')])
    setLoading(false)
    const failed=results.find(x=>x.error)
    if(failed){setError(failed.error.message);return}
    if(results[0].data.length===500||results[1].data.length===2000){setError('Hay más órdenes que el límite de consulta; revise el historial antes de utilizar los totales.');return}
    setOrders(results[0].data);setLines(results[1].data);setSupplies(results[2].data);setProviders(results[3].data)
  }
  useEffect(()=>{load()},[])
  const updateLine=(i,patch)=>setForm(f=>({...f,lineas:f.lineas.map((row,j)=>j===i?{...row,...patch}:row)}))
  const choose=(i,id)=>{const item=supplies.find(x=>x.id===id);updateLine(i,{insumo_id:id,presentacion:item?.presentacion_compra||item?.unidad||'',factor:String(item?.unidades_por_presentacion||1),precio:item?.moneda_referencia===form.moneda?String(item?.precio_referencia??''):''})}
  const save=async()=>{
    if(!form.proveedor_nombre.trim()||!form.fecha||form.lineas.some(x=>!x.insumo_id||!x.presentacion.trim()||!Number.isFinite(Number(x.factor))||Number(x.factor)<=0||!Number.isFinite(Number(x.cantidad))||Number(x.cantidad)<=0||!Number.isFinite(Number(x.precio))||Number(x.precio)<0)){
      setError('Complete proveedor, fecha, artículos, presentación, cantidad y precio de cada línea.');return
    }
    setSaving(true);setError('')
    const {error:e}=await supabase.rpc('crear_orden_insumos',{p_fecha:form.fecha,p_proveedor_nombre:form.proveedor_nombre.trim(),p_proveedor_id:form.proveedor_id||null,p_moneda:form.moneda,p_observaciones:form.observaciones.trim()||null,p_lineas:form.lineas.map(x=>({insumo_id:x.insumo_id,presentacion:x.presentacion.trim(),factor:Number(x.factor),cantidad:Number(x.cantidad),precio:Number(x.precio)}))})
    setSaving(false);if(e){setError(e.message);return}setForm(null);load()
  }
  const receive=async()=>{
    const left=Number(receiving.cantidad_presentaciones)-Number(receiving.recibido_presentaciones),n=Number(receipt.cantidad)
    if(!receipt.fecha||!Number.isFinite(n)||n<=0||n>left){setError('Indique fecha y cantidad positiva que no supere el pendiente.');return}
    setSaving(true);setError('')
    const {error:e}=await supabase.rpc('recibir_orden_insumos',{p_linea_id:receiving.id,p_cantidad:n,p_fecha:receipt.fecha,p_referencia:receipt.referencia.trim()||null})
    setSaving(false);if(e){setError(e.message);return}setReceiving(null);load()
  }
  return <>
    <div className="modulebar"><div><p>Compre insumos con su precio real. El inventario aumenta al recibirlos y el costo de producción se registra cuando se consumen.</p></div><div className="cost-buttons"><button onClick={()=>go('Inventario de insumos')}>Ver inventario</button><button className="primary" onClick={()=>{setForm(fresh());setError('')}}><Plus size={17}/>Nueva orden de insumos</button></div></div>
    {error&&!form&&!receiving&&<div className="formerror" role="alert">{error}</div>}
    {loading?<div className="empty">Cargando órdenes…</div>:<div className="workers-panel"><h3>Órdenes de insumos</h3>{orders.map(order=>{const rows=lines.filter(x=>x.orden_id===order.id),total=rows.reduce((n,x)=>n+Number(x.cantidad_presentaciones)*Number(x.precio_presentacion),0);return <article key={order.id} className="supply-order"><div><b>{order.codigo} · {order.proveedor_nombre}</b><span>{order.fecha} · {order.estado} · {rows.length} artículos</span><details><summary>Artículos y recepción</summary>{rows.map(row=>{const item=supplies.find(x=>x.id===row.insumo_id),left=Number(row.cantidad_presentaciones)-Number(row.recibido_presentaciones);return <p key={row.id}>{item?.nombre||'Insumo'} · {row.recibido_presentaciones}/{row.cantidad_presentaciones} {row.presentacion} ({row.unidades_por_presentacion} {item?.unidad} cada uno) · {fmt(row.precio_presentacion,order.moneda)} por {row.presentacion} {left>0&&order.estado==='Abierta'&&<button type="button" onClick={()=>{setReceiving(row);setReceipt({cantidad:String(left),fecha:costaRicaToday(),referencia:''});setError('')}}>Recibir {left} pendiente</button>}</p>})}</details></div><strong>{fmt(total,order.moneda)}</strong></article>})}{!orders.length&&<p>Aún no hay órdenes de insumos. Puede crear la primera aquí.</p>}</div>}
    {form&&<div className="modalwrap"><div className="modal plant-form weekly-modal"><div className="modalhead"><div><span>COMPRAS DE INSUMOS</span><h2>Nueva orden de insumos</h2></div><button onClick={()=>setForm(null)} aria-label="Cerrar"><X/></button></div>
      <div className="formgrid"><label>Fecha *<input type="date" value={form.fecha} onChange={e=>setForm({...form,fecha:e.target.value})}/></label><label>Moneda *<select value={form.moneda} onChange={e=>setForm({...form,moneda:e.target.value,lineas:form.lineas.map(x=>({...x,precio:''}))})}><option value="USD">Dólares (USD)</option><option value="CRC">Colones (CRC)</option></select></label><label className="wide">Proveedor *<input list="supply-providers" value={form.proveedor_nombre} onChange={e=>{const p=providers.find(x=>x.nombre===e.target.value);setForm({...form,proveedor_nombre:e.target.value,proveedor_id:p?.id||''})}} placeholder="Seleccione o escriba el proveedor"/><datalist id="supply-providers">{providers.map(x=><option key={x.id} value={x.nombre}/>)}</datalist></label><label className="wide">Observaciones<input value={form.observaciones} onChange={e=>setForm({...form,observaciones:e.target.value})}/></label></div>
      <h3>Artículos</h3>{form.lineas.map((row,i)=><div key={i} className="supply-purchase-line formgrid"><label className="wide">Insumo *<select value={row.insumo_id} onChange={e=>choose(i,e.target.value)}><option value="">Seleccione</option>{supplies.filter(x=>x.activo).map(x=><option key={x.id} value={x.id}>{x.nombre} · {x.unidad}</option>)}</select></label><label>Presentación *<input value={row.presentacion} onChange={e=>updateLine(i,{presentacion:e.target.value})} placeholder="caja, bidón, rollo…"/></label><label>Unidades por presentación *<input type="number" min="0.001" step="0.001" value={row.factor} onChange={e=>updateLine(i,{factor:e.target.value})}/></label><label>Cantidad de presentaciones *<input type="number" min="0.001" step="0.001" value={row.cantidad} onChange={e=>updateLine(i,{cantidad:e.target.value})}/></label><label>Precio por presentación ({form.moneda}) *<input type="number" min="0" step="0.01" value={row.precio} onChange={e=>updateLine(i,{precio:e.target.value})}/></label><strong className="wide">Subtotal: {fmt(Number(row.cantidad)*Number(row.precio),form.moneda)}</strong>{form.lineas.length>1&&<button type="button" onClick={()=>setForm({...form,lineas:form.lineas.filter((_,j)=>j!==i)})}>Quitar artículo</button>}</div>)}<button type="button" onClick={()=>setForm({...form,lineas:[...form.lineas,line()]})}>+ Agregar artículo</button><p><b>Total estimado: {fmt(form.lineas.reduce((n,x)=>n+Number(x.cantidad)*Number(x.precio),0),form.moneda)}</b></p><p>Los precios de referencia son editables. Esta orden todavía no crea existencias ni registra un costo de producción.</p>
      {error&&<div className="formerror" role="alert">{error}</div>}<div className="modalactions"><button onClick={()=>setForm(null)} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':'Guardar orden'}</button></div></div></div>}
    {receiving&&<div className="modalwrap"><div className="modal plant-form weekly-modal"><div className="modalhead"><div><span>ENTRADA DE INSUMOS</span><h2>Recibir material</h2></div><button onClick={()=>setReceiving(null)} aria-label="Cerrar"><X/></button></div><p>Pendiente: {Number(receiving.cantidad_presentaciones)-Number(receiving.recibido_presentaciones)} {receiving.presentacion}. El inventario aumentará en {receiving.unidades_por_presentacion} unidades por presentación recibida.</p><div className="formgrid"><label>Fecha de recepción *<input type="date" value={receipt.fecha} onChange={e=>setReceipt({...receipt,fecha:e.target.value})}/></label><label>Cantidad recibida *<input type="number" min="0.001" step="0.001" value={receipt.cantidad} onChange={e=>setReceipt({...receipt,cantidad:e.target.value})}/></label><label className="wide">Factura / referencia<input value={receipt.referencia} onChange={e=>setReceipt({...receipt,referencia:e.target.value})}/></label></div>{error&&<div className="formerror" role="alert">{error}</div>}<div className="modalactions"><button onClick={()=>setReceiving(null)} disabled={saving}>Cancelar</button><button className="primary" onClick={receive} disabled={saving}>{saving?'Recibiendo…':'Confirmar recepción'}</button></div></div></div>}
  </>
}

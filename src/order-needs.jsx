import React,{useEffect,useMemo,useState} from 'react'
import {supabase} from './supabase'
import {costaRicaToday} from './weekly-model'

const fmt=value=>Number(value||0).toLocaleString('es-CR',{maximumFractionDigits:2})

export default function OrderNeeds({refresh}){
  const [orders,setOrders]=useState([]),[lines,setLines]=useState([]),[assigned,setAssigned]=useState([])
  const [period,setPeriod]=useState('all'),[expanded,setExpanded]=useState(''),[loading,setLoading]=useState(true),[error,setError]=useState('')
  useEffect(()=>{let active=true;const load=async()=>{
    setLoading(true)
    const [o,l,a]=await Promise.all([
      supabase.from('ordenes_venta').select('id,codigo,fecha_salida,mercado,estado,finalizada_en,clientes(nombre)').neq('estado','Anulada').is('finalizada_en',null).limit(1000),
      supabase.from('ordenes_venta_lineas').select('id,orden_venta_id,producto,presentacion_kg,cantidad_cajas').limit(3000),
      supabase.from('boleta_rendimientos').select('orden_venta_linea_id,cajas').not('orden_venta_linea_id','is',null).limit(5000)
    ])
    if(!active)return
    setLoading(false)
    if(o.error||l.error||a.error){setError(`No se pudo calcular la necesidad de pedidos: ${(o.error||l.error||a.error).message}`);return}
    if(o.data?.length===1000||l.data?.length===3000||a.data?.length===5000){setError('Hay demasiados registros para un resumen completo. Revise los pedidos antes de usar estas cifras.');return}
    setError('');setOrders(o.data||[]);setLines(l.data||[]);setAssigned(a.data||[])
  };load();return()=>{active=false}},[refresh])
  const today=costaRicaToday()
  const months=useMemo(()=>[...new Set(orders.map(o=>o.fecha_salida?.slice(0,7)).filter(Boolean))].sort().reverse(),[orders])
  const summary=useMemo(()=>{
    const included=new Map(orders.filter(o=>period==='all'||period==='upcoming'&&o.fecha_salida>=today||period==='overdue'&&(!o.fecha_salida||o.fecha_salida<today)||o.fecha_salida?.startsWith(period)).map(o=>[o.id,o]))
    const completed={};for(const a of assigned)completed[a.orden_venta_linea_id]=(completed[a.orden_venta_linea_id]||0)+Number(a.cajas||0)
    const grouped=new Map()
    for(const line of lines){const order=included.get(line.orden_venta_id);if(!order)continue
      const key=`${line.producto}|${order.mercado||'Sin mercado'}`,row=grouped.get(key)||{producto:line.producto,mercado:order.mercado||'Sin mercado',pedidos:new Set(),cajas:0,kg:0,pendientes:0,detail:[]}
      const boxes=Number(line.cantidad_cajas),weight=Number(line.presentacion_kg),done=Number(completed[line.id]||0)
      if(!line.producto||!Number.isInteger(boxes)||boxes<=0||!Number.isFinite(weight)||weight<=0||!Number.isInteger(done)||done<0||done>boxes)return {error:`Revise cajas, peso o asignaciones en ${order.codigo||order.id} (${line.producto||'sin producto'}). No se muestran totales parciales.`,rows:[],products:[]}
      row.pedidos.add(order.id);row.cajas+=boxes;row.kg+=boxes*weight;row.pendientes+=(boxes-done)*weight;row.detail.push({id:line.id,code:order.codigo,client:order.clientes?.nombre||'Sin cliente',date:order.fecha_salida,boxes,weight,done,kg:boxes*weight});grouped.set(key,row)
    }
    const rows=[...grouped.values()].sort((a,b)=>a.producto.localeCompare(b.producto,'es')||a.mercado.localeCompare(b.mercado,'es'))
    const products=new Map()
    for(const row of rows){const total=products.get(row.producto)||{producto:row.producto,cajas:0,kg:0,pendientes:0};total.cajas+=row.cajas;total.kg+=row.kg;total.pendientes+=row.pendientes;products.set(row.producto,total)}
    return {rows,products:[...products.values()],error:''}
  },[orders,lines,assigned,period,today])
  const {rows,products,error:calculationError}=summary
  return <section className="panel order-needs"><div className="panelhead"><div><h3>Producto necesario para pedidos abiertos</h3><p>Según cajas y peso por caja registrados en órdenes de venta</p></div><label>Salida<select value={period} onChange={e=>{setPeriod(e.target.value);setExpanded('')}}><option value="all">Todos los abiertos</option><option value="upcoming">Desde hoy</option><option value="overdue">Fechas vencidas</option>{months.map(m=><option key={m} value={m}>Mes {m}</option>)}</select></label></div>
    {loading?<p>Cargando pedidos…</p>:error||calculationError?<div className="formerror">{error||calculationError}</div>:rows.length?<><h4>Total por producto</h4><div className="order-needs-scroll"><table><thead><tr><th>Producto</th><th>Cajas</th><th>Neto pedido</th><th>Asignado en planta</th><th>Pendiente de asignar</th></tr></thead><tbody>{products.map(p=><tr key={p.producto}><td>{p.producto}</td><td>{fmt(p.cajas)}</td><td>{fmt(p.kg)} kg · {fmt(p.kg/46)} qq</td><td>{fmt(p.kg-p.pendientes)} kg · {fmt((p.kg-p.pendientes)/46)} qq</td><td>{fmt(p.pendientes)} kg · {fmt(p.pendientes/46)} qq</td></tr>)}</tbody></table></div><h4>Desglose por mercado</h4><div className="order-needs-scroll"><table><thead><tr><th>Producto</th><th>Mercado</th><th>Pedidos</th><th>Cajas</th><th>Neto pedido</th><th>Pendiente de asignar</th><th>Detalle</th></tr></thead><tbody>{rows.map(r=>{const key=`${r.producto}|${r.mercado}`;return <React.Fragment key={key}><tr><td>{r.producto}</td><td>{r.mercado}</td><td>{fmt(r.pedidos.size)}</td><td>{fmt(r.cajas)}</td><td>{fmt(r.kg)} kg · {fmt(r.kg/46)} qq</td><td>{fmt(r.pendientes)} kg · {fmt(r.pendientes/46)} qq</td><td><button type="button" onClick={()=>setExpanded(expanded===key?'':key)}>{expanded===key?'Ocultar':'Ver órdenes'}</button></td></tr>{expanded===key&&<tr><td colSpan="7"><div className="order-needs-detail">{r.detail.map(d=><div key={d.id}><b>{d.client} · {d.code}</b><span>Salida {d.date||'sin fecha'} · {fmt(d.boxes)} cajas × {fmt(d.weight)} kg = {fmt(d.kg)} kg ({fmt(d.kg/46)} qq) · Asignadas {fmt(d.done)} cajas · Pendientes {fmt(d.boxes-d.done)} cajas ({fmt((d.boxes-d.done)*d.weight)} kg)</span></div>)}</div></td></tr>}</React.Fragment>})}</tbody></table></div><p className="sale-help">«Todos los abiertos» incluye pedidos con fecha vencida. Los kilos son netos pedidos, calculados como cajas × peso por caja. «Pendiente» indica cajas sin asignar desde planta; no equivale a producto por comprar. Para estimar compra bruta faltan rendimiento, merma e inventario disponible. Un quintal equivale a 46 kg.</p></>:<p>No hay pedidos abiertos con líneas para esta fecha.</p>}
  </section>
}

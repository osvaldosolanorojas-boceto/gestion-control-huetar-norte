import React,{useEffect,useMemo,useState} from 'react'
import {supabase} from './supabase'

const fmt=value=>Number(value||0).toLocaleString('es-CR',{maximumFractionDigits:2})

export default function OrderNeeds({refresh}){
  const [orders,setOrders]=useState([]),[lines,setLines]=useState([]),[assigned,setAssigned]=useState([])
  const [week,setWeek]=useState('all'),[loading,setLoading]=useState(true),[error,setError]=useState('')
  useEffect(()=>{let active=true;const load=async()=>{
    setLoading(true)
    const [o,l,a]=await Promise.all([
      supabase.from('ordenes_venta').select('id,codigo,fecha_salida,mercado,estado,finalizada_en').neq('estado','Anulada').is('finalizada_en',null).limit(1000),
      supabase.from('ordenes_venta_lineas').select('id,orden_venta_id,producto,presentacion_kg,cantidad_cajas').limit(3000),
      supabase.from('boleta_rendimientos').select('orden_venta_linea_id,cajas').not('orden_venta_linea_id','is',null).limit(5000)
    ])
    if(!active)return
    setLoading(false)
    if(o.error||l.error||a.error){setError(`No se pudo calcular la necesidad de pedidos: ${(o.error||l.error||a.error).message}`);return}
    if(o.data?.length===1000||l.data?.length===3000||a.data?.length===5000){setError('Hay demasiados registros para un resumen completo. Revise los pedidos antes de usar estas cifras.');return}
    setError('');setOrders(o.data||[]);setLines(l.data||[]);setAssigned(a.data||[])
  };load();return()=>{active=false}},[refresh])
  const weeks=useMemo(()=>[...new Set(orders.map(o=>o.fecha_salida?.slice(0,7)).filter(Boolean))].sort().reverse(),[orders])
  const rows=useMemo(()=>{
    const included=new Map(orders.filter(o=>week==='all'||o.fecha_salida?.startsWith(week)).map(o=>[o.id,o]))
    const completed={};for(const a of assigned)completed[a.orden_venta_linea_id]=(completed[a.orden_venta_linea_id]||0)+Number(a.cajas||0)
    const grouped=new Map()
    for(const line of lines){const order=included.get(line.orden_venta_id);if(!order)continue
      const key=`${line.producto}|${order.mercado||'Sin mercado'}`,row=grouped.get(key)||{producto:line.producto,mercado:order.mercado||'Sin mercado',pedidos:new Set(),cajas:0,kg:0,pendientes:0}
      const boxes=Number(line.cantidad_cajas||0),weight=Number(line.presentacion_kg||0)
      row.pedidos.add(order.id);row.cajas+=boxes;row.kg+=boxes*weight;row.pendientes+=Math.max(0,boxes-Number(completed[line.id]||0))*weight;grouped.set(key,row)
    }
    return [...grouped.values()].sort((a,b)=>a.producto.localeCompare(b.producto,'es')||a.mercado.localeCompare(b.mercado,'es'))
  },[orders,lines,assigned,week])
  return <section className="panel order-needs"><div className="panelhead"><div><h3>Producto necesario para pedidos abiertos</h3><p>Según cajas y peso por caja registrados en órdenes de venta</p></div><label>Salida<select value={week} onChange={e=>setWeek(e.target.value)}><option value="all">Todas las fechas</option>{weeks.map(w=><option key={w} value={w}>{w}</option>)}</select></label></div>
    {loading?<p>Cargando pedidos…</p>:error?<div className="formerror">{error}</div>:rows.length?<><div className="order-needs-scroll"><table><thead><tr><th>Producto</th><th>Mercado</th><th>Pedidos</th><th>Cajas</th><th>Venta neta</th><th>Falta asignar en planta</th></tr></thead><tbody>{rows.map(r=><tr key={`${r.producto}|${r.mercado}`}><td>{r.producto}</td><td>{r.mercado}</td><td>{fmt(r.pedidos.size)}</td><td>{fmt(r.cajas)}</td><td>{fmt(r.kg)} kg · {fmt(r.kg/46)} qq</td><td>{fmt(r.pendientes)} kg · {fmt(r.pendientes/46)} qq</td></tr>)}</tbody></table></div><p className="sale-help">Estos son kilos netos empacados. Los kilos que debe comprar en campo dependen del rendimiento y las mermas; todavía no se estiman aquí. Un quintal equivale a 46 kg.</p></>:<p>No hay pedidos abiertos con líneas para esta fecha.</p>}
  </section>
}

import React,{useEffect,useMemo,useState} from 'react'
import {supabase} from './supabase'
import {buildLoadMap} from './load-map-model'

const fmt=n=>Number(n||0).toLocaleString('es-CR')
export default function LoadMap({go}){
  const [lines,setLines]=useState([]),[receipts,setReceipts]=useState([]),[purchases,setPurchases]=useState({}),[selected,setSelected]=useState(''),[error,setError]=useState(''),[loading,setLoading]=useState(true)
  const reload=async()=>{
    setLoading(true);setError('')
    const [a,b,c]=await Promise.all([supabase.rpc('pedidos_mapa_para_planta'),supabase.from('boleta_rendimientos').select('id,orden_venta_linea_id,cajas,posicion_paleta,codigo_trazabilidad,calidad,creado_en,boletas_entrada(codigo,orden_compra_id)').not('orden_venta_linea_id','is',null).order('creado_en').limit(1000),supabase.rpc('ordenes_compra_para_planta')])
    setLoading(false)
    if(a.error||b.error||c.error){setError(`No se pudo cargar el mapa: ${(a.error||b.error||c.error).message}`);return}
    setLines(a.data||[]);setReceipts(b.data||[]);setPurchases(Object.fromEntries((c.data||[]).map(x=>[x.id,x])))
    setSelected(current=>(a.data||[]).some(x=>x.orden_id===current)?current:a.data?.[0]?.orden_id||'')
  }
  useEffect(()=>{reload()},[])
  const orders=useMemo(()=>[...new Map(lines.map(x=>[x.orden_id,{id:x.orden_id,codigo:x.codigo,cliente:x.cliente,contenedor:x.contenedor}])).values()],[lines])
  const current=lines.filter(x=>x.orden_id===selected),ids=new Set(current.map(x=>x.linea_id)),assigned=receipts.filter(x=>ids.has(x.orden_venta_linea_id))
  const map=useMemo(()=>buildLoadMap(current,assigned),[lines,receipts,selected])
  const ordered=current.reduce((sum,x)=>sum+Number(x.cantidad_cajas||0),0),total=assigned.reduce((sum,x)=>sum+Number(x.cajas||0),0),pct=ordered?Math.min(100,Math.round(total/ordered*100)):0
  return <><div className="modulebar"><div><p>Avance calculado con los rendimientos guardados. Una partida de 450 cajas se reparte entre paletas de 60, conservando su boleta y código.</p></div><button onClick={reload} disabled={loading}>Actualizar avance</button></div>
    {error&&<div className="formerror">{error}</div>}{loading?<div className="empty">Cargando pedidos y boletas…</div>:!orders.length?<div className="empty">Todavía no hay órdenes de venta con líneas.</div>:<><div className="load-selector"><label>Pedido o contenedor<select value={selected} onChange={e=>setSelected(e.target.value)}>{orders.map(x=><option key={x.id} value={x.id}>{x.codigo} · {x.cliente||'Cliente'} · {x.contenedor||'Sin número de contenedor'}</option>)}</select></label><button onClick={()=>go('Boletas de entrada')}>Ir a boletas</button></div>
    <div className="load-overview"><div><small>Avance del pedido</small><strong>{fmt(total)} / {fmt(ordered)} cajas</strong><span>{pct}% asignado desde planta · {fmt(Math.max(0,ordered-total))} pendientes</span></div><div className="load-track"><div style={{width:`${pct}%`}}/></div></div>
    <div className="load-lines">{current.map(line=>{const count=assigned.filter(r=>r.orden_venta_linea_id===line.linea_id).reduce((sum,r)=>sum+Number(r.cajas),0);return <article key={line.linea_id}><b>{line.producto} · {line.presentacion_kg} kg · {line.carton||'Cartón'}</b><span>{fmt(count)} de {fmt(line.cantidad_cajas)} cajas · {line.paletas} paletas de {line.cajas_por_paleta}</span><div className="load-track"><div style={{width:`${Math.min(100,Math.round(count/Number(line.cantidad_cajas)*100)||0)}%`}}/></div></article>})}</div>
    <h3>Mapa de paletas</h3><p className="sale-help">La posición anotada en planta sirve como inicio. Si la partida excede la capacidad de esa paleta, el mapa continúa en las siguientes posiciones disponibles. El mapa refleja asignación; confirme la carga física al despachar.</p>
    <div className="load-grid">{map.slots.map(p=><article key={p.position} className={p.loaded>=p.capacity?'load-full':p.loaded?'load-partial':''}><div className="load-head"><strong>Paleta {p.position}</strong><span>{fmt(p.loaded)} / {fmt(p.capacity)} cajas</span></div><small>{p.product} · {p.weight} kg {p.carton?`· ${p.carton}`:''}</small><div className="load-track"><div style={{width:`${Math.min(100,p.loaded/p.capacity*100)}%`}}/></div>{p.chunks.length?<div className="load-chunks">{p.chunks.map((part,i)=><div key={`${part.sourceId}-${i}`}><b>{part.count} cajas · {part.receipt}</b><span>{purchases[part.purchase]?.productor_nombre||'Productor pendiente'} · {part.code||'Sin código'}</span></div>)}</div>:<p>Sin asignación todavía</p>}</article>)}</div>
    {map.unmapped.length>0&&<div className="formerror">Hay {fmt(map.unmapped.reduce((sum,x)=>sum+x.count,0))} cajas que exceden la capacidad de las paletas previstas. Revise el pedido y las boletas.</div>}
    {assigned.some(r=>!r.posicion_paleta)&&<p className="sale-help">Algunas partidas no tienen posición anotada; se ubicaron en el primer espacio disponible del mapa.</p>}</>}
  </>
}

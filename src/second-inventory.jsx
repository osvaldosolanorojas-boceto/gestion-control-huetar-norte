import React,{useEffect,useState} from 'react'
import {X} from 'lucide-react'
import {supabase} from './supabase'

const localQuality=q=>['Segunda','Segunda gruesa','Segunda menuda','Rechazo','Rechazo grueso','Rechazo menuda'].includes(q)
const num=n=>Number(n||0).toLocaleString('es-CR',{maximumFractionDigits:3})
export default function SecondInventory(){
  const [lots,setLots]=useState([]),[sales,setSales]=useState([]),[orders,setOrders]=useState({}),[selected,setSelected]=useState(null),[form,setForm]=useState({comprador:'',cantidad:'',fecha:new Date().toISOString().slice(0,10),referencia:'',observaciones:''}),[error,setError]=useState(''),[saving,setSaving]=useState(false),[showAll,setShowAll]=useState(false)
  const reload=async()=>{
    const [a,b,c]=await Promise.all([supabase.from('boleta_rendimientos').select('id,producto,calidad,cajas,kg_resultado,presentacion_kg,codigo_trazabilidad,orden_venta_linea_id,boletas_entrada(codigo,fecha_hora,orden_compra_id)').order('creado_en',{ascending:false}).limit(500),supabase.from('ventas_segundas').select('*').order('creado_en',{ascending:false}).limit(1000),supabase.rpc('ordenes_compra_para_planta')])
    if(a.error||b.error||c.error){setError(`No se pudo cargar la lista: ${(a.error||b.error||c.error).message}`);return}
    setLots((a.data||[]).filter(r=>localQuality(r.calidad)&&!r.orden_venta_linea_id));setSales(b.data||[]);setOrders(Object.fromEntries((c.data||[]).map(o=>[o.id,o])))
  }
  useEffect(()=>{reload()},[])
  const remaining=r=>{const sold=sales.filter(s=>s.rendimiento_id===r.id).reduce((sum,s)=>sum+Number(r.cajas>0?s.cajas:s.kilos),0);return Math.max(0,Number(r.cajas>0?r.cajas:r.kg_resultado)-sold)}
  const save=async()=>{
    const qty=Number(String(form.cantidad).replace(',','.'))
    if(!form.comprador.trim()||!Number.isFinite(qty)||qty<=0||(selected.cajas>0&&!Number.isInteger(qty))||qty>remaining(selected)){setError('Indique comprador y una cantidad que no supere el saldo disponible.');return}
    setSaving(true);setError('')
    const {error:e}=await supabase.rpc('registrar_venta_segunda',{p_rendimiento_id:selected.id,p_comprador:form.comprador.trim(),p_cantidad:qty,p_fecha:form.fecha,p_referencia:form.referencia.trim()||null,p_observaciones:form.observaciones.trim()||null})
    setSaving(false);if(e){setError(`No se pudo registrar la venta: ${e.message}`);return}setSelected(null);reload()
  }
  const visible=lots.filter(r=>showAll||remaining(r)>0)
  return <><div className="modulebar"><div><p>Los rendimientos de segunda y rechazo sin pedido aparecen aquí al guardar la boleta. Registre la venta después, incluso si sale en varias entregas.</p></div><button onClick={()=>setShowAll(x=>!x)}>{showAll?'Ver pendientes':'Ver también vendidos'}</button></div>
    <div className="supply-grid">{visible.map(r=>{const order=orders[r.boletas_entrada?.orden_compra_id],unit=r.cajas>0?'cajas':'kg';return <article className="supply-card" key={r.id}><small>{r.boletas_entrada?.codigo||'Boleta'} · {order?.codigo||'Compra sin referencia'}</small><h3>{order?.productor_nombre||'Productor pendiente'}</h3><p>{r.producto} · {r.calidad}{r.presentacion_kg?` · ${num(r.presentacion_kg)} kg por caja`:''}</p><strong className={remaining(r)===0?'low':''}>{num(remaining(r))} {unit}</strong><p>Producido: {num(r.cajas>0?r.cajas:r.kg_resultado)} {unit}{r.codigo_trazabilidad?` · Lote ${r.codigo_trazabilidad}`:''}</p><button disabled={!remaining(r)} onClick={()=>{setSelected(r);setForm({comprador:'',cantidad:'',fecha:new Date().toISOString().slice(0,10),referencia:'',observaciones:''});setError('')}}>Registrar comprador / salida</button><details><summary>Ventas de este lote</summary>{sales.filter(s=>s.rendimiento_id===r.id).map(s=><p key={s.id}>{s.fecha} · {s.comprador} · {num(r.cajas>0?s.cajas:s.kilos)} {unit}</p>)}</details></article>})}</div>
    {!visible.length&&<div className="empty"><h3>Sin producto pendiente</h3><p>Al guardar una segunda o rechazo sin orden de venta, aparecerá aquí con el nombre del productor.</p></div>}
    {selected&&<div className="modalwrap"><div className="modal carton-modal supply-modal"><div className="modalhead"><div><span>VENTA LOCAL DE SEGUNDA</span><h2>{selected.producto} · {selected.calidad}</h2></div><button onClick={()=>setSelected(null)} aria-label="Cerrar"><X/></button></div><div className="formgrid"><label className="wide">Comprador *<input value={form.comprador} onChange={e=>setForm({...form,comprador:e.target.value})} placeholder="Nombre de quien compró el producto"/></label><label>Fecha de salida<input type="date" value={form.fecha} onChange={e=>setForm({...form,fecha:e.target.value})}/></label><label>Cantidad ({selected.cajas>0?'cajas':'kg'}) *<input type="number" min="0.001" max={remaining(selected)} step={selected.cajas>0?'1':'0.001'} inputMode="decimal" value={form.cantidad} onChange={e=>setForm({...form,cantidad:e.target.value})}/></label><label className="wide">Referencia de venta o factura<input value={form.referencia} onChange={e=>setForm({...form,referencia:e.target.value})}/></label><label className="wide">Observaciones<input value={form.observaciones} onChange={e=>setForm({...form,observaciones:e.target.value})}/></label><p className="wide">Disponible: <b>{num(remaining(selected))} {selected.cajas>0?'cajas':'kg'}</b></p></div>{error&&<div className="formerror">{error}</div>}<div className="modalactions"><button disabled={saving} onClick={()=>setSelected(null)}>Cancelar</button><button disabled={saving} className="primary" onClick={save}>{saving?'Guardando…':'Registrar venta'}</button></div></div></div>}
    {!selected&&error&&<div className="formerror">{error}</div>}</>
}

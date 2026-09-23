import React,{useEffect,useState} from 'react'
import {Plus,X} from 'lucide-react'
import {supabase} from './supabase'

const localQualities=['Segunda','Segunda gruesa','Segunda menuda','Rechazo','Rechazo grueso','Rechazo menuda']
const num=n=>Number(n||0).toLocaleString('es-CR',{maximumFractionDigits:3})
const money=(n,c)=>new Intl.NumberFormat('es-CR',{style:'currency',currency:c,maximumFractionDigits:2}).format(Number(n)||0)
const parse=n=>Number(String(n??'').replace(',','.'))
const emptyLine=id=>({rendimiento_id:id||'',cantidad:'',peso_caja_kg:'',precio_unitario:'',unidad_precio:'caja'})
const initial=()=>({codigo:`VL-${Date.now()}`,fecha:new Date().toISOString().slice(0,10),comprador:'',referencia:'',moneda:'CRC',observaciones:'',lineas:[emptyLine()]})
export default function SecondInventory(){
  const [lots,setLots]=useState([]),[sold,setSold]=useState([]),[orders,setOrders]=useState({}),[sales,setSales]=useState([]),[clients,setClients]=useState([]),[open,setOpen]=useState(false),[form,setForm]=useState(initial),[error,setError]=useState(''),[loading,setLoading]=useState(true),[soldLoaded,setSoldLoaded]=useState(false),[saving,setSaving]=useState(false),[showAll,setShowAll]=useState(false)
  const reload=async()=>{
    setLoading(true);setSoldLoaded(false);setError('')
    try{
      const a=await supabase.from('boleta_rendimientos').select('id,producto,calidad,cajas,kg_resultado,presentacion_kg,codigo_trazabilidad,orden_venta_linea_id,boletas_entrada(codigo,fecha_hora,orden_compra_id)').in('calidad',localQualities).is('orden_venta_linea_id',null).order('creado_en',{ascending:false}).limit(500)
      if(a.error)throw a.error
      setLots(a.data||[]);setLoading(false)
      const [b,c,d,clientsResult]=await Promise.allSettled([supabase.from('ventas_segundas').select('*').order('creado_en',{ascending:false}).limit(1000),supabase.rpc('ordenes_compra_para_planta',{p_incluir_vinculadas:true}),supabase.from('ventas_locales').select('*').order('creado_en',{ascending:false}).limit(100),supabase.from('clientes').select('id,nombre').eq('activo',true).order('nombre')])
      if(b.status==='fulfilled'&&!b.value.error){setSold(b.value.data||[]);setSoldLoaded(true)}
      if(c.status==='fulfilled'&&!c.value.error)setOrders(Object.fromEntries((c.value.data||[]).map(o=>[o.id,o])))
      if(d.status==='fulfilled'&&!d.value.error)setSales(d.value.data||[])
      if(clientsResult.status==='fulfilled'&&!clientsResult.value.error)setClients(clientsResult.value.data||[])
      if([b,c,d].some(x=>x.status==='rejected'||x.value.error))setError('Las partidas cargaron, pero faltan datos de ventas o productores. Pulse Reintentar para completar la información.')
    }catch(e){setLoading(false);setError(`No se pudieron cargar las partidas: ${e.message||'Error de conexión'}. Pulse Reintentar.`)}
  }
  useEffect(()=>{reload()},[])
  const remaining=r=>Math.max(0,Number(r.cajas>0?r.cajas:r.kg_resultado)-sold.filter(s=>s.rendimiento_id===r.id).reduce((sum,s)=>sum+Number(r.cajas>0?s.cajas:s.kilos),0))
  const label=r=>{const order=orders[r.boletas_entrada?.orden_compra_id];return `${r.boletas_entrada?.codigo||'Boleta'} · ${order?.productor_nombre||'Productor pendiente'} · ${r.producto} · ${r.calidad} · ${num(remaining(r))} ${r.cajas>0?'cajas':'kg'}`}
  const editLine=(index,key,value)=>setForm(f=>({...f,lineas:f.lineas.map((line,i)=>i===index?{...line,[key]:value,...(key==='rendimiento_id'?{cantidad:'',peso_caja_kg:String(lots.find(r=>r.id===value)?.presentacion_kg||''),unidad_precio:lots.find(r=>r.id===value)?.cajas>0?'caja':'kg'}:{})}:line)}))
  const totals=form.lineas.map(line=>{const lot=lots.find(r=>r.id===line.rendimiento_id),qty=parse(line.cantidad),weight=parse(line.peso_caja_kg),price=parse(line.precio_unitario);return Number.isFinite(qty)&&Number.isFinite(price)&&qty>0&&price>=0?Math.round(price*(line.unidad_precio==='kg'&&lot?.cajas>0?qty*weight:qty)*100)/100:0})
  const start=id=>{setForm({...initial(),lineas:[{...emptyLine(id),peso_caja_kg:String(lots.find(r=>r.id===id)?.presentacion_kg||''),unidad_precio:lots.find(r=>r.id===id)?.cajas>0?'caja':'kg'}]});setError('');setOpen(true)}
  const save=async()=>{
    if(!form.comprador.trim()||!form.fecha||!form.lineas.length){setError('Complete comprador, fecha y al menos una partida.');return}
    const used={};const lines=[]
    for(const line of form.lineas){
      const lot=lots.find(r=>r.id===line.rendimiento_id),qty=parse(line.cantidad),weight=parse(line.peso_caja_kg),price=parse(line.precio_unitario)
      if(!lot||!Number.isFinite(qty)||qty<=0||(lot.cajas>0&&!Number.isInteger(qty))||(lot.cajas>0&&(!Number.isFinite(weight)||weight<=0))||!Number.isFinite(price)||price<0){setError('Revise boleta, cantidad, peso por caja y precio de cada partida.');return}
      used[lot.id]=(used[lot.id]||0)+qty
      if(used[lot.id]>remaining(lot)){setError(`La cantidad supera el saldo disponible de ${label(lot)}.`);return}
      lines.push({rendimiento_id:lot.id,cantidad:qty,peso_caja_kg:lot.cajas>0?weight:null,precio_unitario:price,unidad_precio:lot.cajas>0?line.unidad_precio:'kg'})
    }
    setSaving(true);setError('')
    const {error:e}=await supabase.rpc('registrar_venta_local',{p_codigo:form.codigo,p_fecha:form.fecha,p_comprador:form.comprador.trim(),p_referencia:form.referencia.trim()||null,p_moneda:form.moneda,p_observaciones:form.observaciones.trim()||null,p_lineas:lines})
    setSaving(false);if(e){setError(`No se pudo registrar la venta: ${e.message}`);return}setOpen(false);reload()
  }
  const visible=lots.filter(r=>showAll||remaining(r)>0)
  const groups=[
    {title:'Yuca · Gruesa',items:visible.filter(r=>r.producto==='Yuca'&&/(gruesa|grueso)$/.test(r.calidad))},
    {title:'Yuca · Menuda',items:visible.filter(r=>r.producto==='Yuca'&&r.calidad.endsWith('menuda'))},
    {title:'Otras segundas y rechazos',items:visible.filter(r=>r.producto!=='Yuca'||!/(gruesa|grueso|menuda)$/.test(r.calidad))}
  ]
  const groupBalance=items=>items.reduce((total,r)=>{const pending=remaining(r);return {boxes:total.boxes+(r.cajas>0?pending:0),kg:total.kg+(r.cajas>0?pending*(Number(r.kg_resultado||0)/Number(r.cajas)||Number(r.presentacion_kg)||0):pending)}},{boxes:0,kg:0})
  const renderLot=r=><article className="supply-card" key={r.id}><small>{r.boletas_entrada?.codigo||'Boleta'} · {orders[r.boletas_entrada?.orden_compra_id]?.codigo||'Compra'}</small><h3>{orders[r.boletas_entrada?.orden_compra_id]?.productor_nombre||'Productor pendiente'}</h3><p>{r.producto} · {r.calidad}{r.presentacion_kg?` · ${num(r.presentacion_kg)} kg por caja`:''}</p><strong>{num(remaining(r))} {r.cajas>0?'cajas':'kg'}</strong><p>Producido: {num(r.cajas>0?r.cajas:r.kg_resultado)} {r.cajas>0?'cajas':'kg'}</p><button disabled={!soldLoaded||!remaining(r)} onClick={()=>start(r.id)}>Vender de esta boleta</button><details><summary>Salidas registradas</summary>{sold.filter(s=>s.rendimiento_id===r.id).map(s=><p key={s.id}>{s.fecha} · {s.comprador} · {num(r.cajas>0?s.cajas:s.kilos)} {r.cajas>0?'cajas':'kg'}{s.peso_caja_kg?` · ${num(s.peso_caja_kg)} kg/caja`:''}</p>)}</details></article>
  return <><div className="modulebar"><div><p>Segundas y rechazo pendientes por boleta. Una venta local puede incluir varios productores, calidades y productos.</p></div><button className="primary" disabled={!soldLoaded} onClick={()=>start()}><Plus size={18}/>Nueva venta local</button></div>
    <div className="crate-actions"><button onClick={()=>setShowAll(x=>!x)}>{showAll?'Ver pendientes':'Ver también vendidos'}</button></div>
    {groups.filter(group=>group.items.length).map(group=>{const balance=groupBalance(group.items);return <section className="second-group" key={group.title}><div className="second-group-heading"><h3>{group.title}</h3><strong>{soldLoaded?`${num(balance.boxes)} cajas · ${num(balance.kg)} kg pendientes`:'Calculando saldo…'}</strong></div><div className="supply-grid">{group.items.map(renderLot)}</div></section>})}
    {loading?<div className="empty"><h3>Cargando partidas…</h3></div>:!visible.length&&!error&&<div className="empty"><h3>Sin producto pendiente</h3><p>Guarde una línea de segunda o rechazo sin pedido para que aparezca aquí.</p></div>}
    <section className="workers-panel"><h3>Ventas locales registradas</h3>{sales.map(s=><article key={s.id}><div><b>{s.codigo} · {s.comprador}</b><span>{s.fecha} · {s.moneda} · {sold.filter(x=>x.venta_local_id===s.id).map(x=>money(x.subtotal,s.moneda)).join(' + ')||'Sin partidas'}</span></div><strong>{money(sold.filter(x=>x.venta_local_id===s.id).reduce((sum,x)=>sum+Number(x.subtotal||0),0),s.moneda)}</strong></article>)}{!sales.length&&<p>No hay ventas locales registradas todavía.</p>}</section>
    {open&&<div className="modalwrap"><div className="modal plant-form local-sale-modal"><div className="modalhead"><div><span>VENTA LOCAL DE SEGUNDAS</span><h2>{form.codigo}</h2></div><button onClick={()=>setOpen(false)} aria-label="Cerrar"><X/></button></div><div className="formgrid"><label>Comprador (cliente) *<input list="local-buyers" value={form.comprador} onChange={e=>setForm({...form,comprador:e.target.value})}/><datalist id="local-buyers">{clients.map(client=><option key={client.id} value={client.nombre}/>)}</datalist></label><label>Fecha de salida *<input type="date" value={form.fecha} onChange={e=>setForm({...form,fecha:e.target.value})}/></label><label>Moneda<select value={form.moneda} onChange={e=>setForm({...form,moneda:e.target.value})}><option value="CRC">Colones (CRC)</option><option value="USD">Dólares (USD)</option></select></label><label>Referencia de factura o venta<input value={form.referencia} onChange={e=>setForm({...form,referencia:e.target.value})}/></label></div>
    {form.lineas.map((line,i)=>{const lot=lots.find(r=>r.id===line.rendimiento_id);return <section className="yield-row" key={i}><div className="work-heading"><b>Partida {i+1}</b><button onClick={()=>setForm(f=>({...f,lineas:f.lineas.filter((_,j)=>j!==i)}))}>Quitar</button></div><div className="formgrid"><label className="wide">Boleta, productor, producto y calidad *<select value={line.rendimiento_id} onChange={e=>editLine(i,'rendimiento_id',e.target.value)}><option value="">Seleccione una boleta</option>{lots.filter(r=>remaining(r)>0||r.id===line.rendimiento_id).map(r=><option key={r.id} value={r.id}>{label(r)}</option>)}</select></label><label>Cantidad ({lot?.cajas>0?'cajas':'kg'}) *<input type="number" min="0.001" step={lot?.cajas>0?'1':'0.001'} inputMode="decimal" value={line.cantidad} onChange={e=>editLine(i,'cantidad',e.target.value)}/></label>{lot?.cajas>0&&<label>Peso por caja (kg) *<input type="number" min="0.001" step="0.001" inputMode="decimal" value={line.peso_caja_kg} onChange={e=>editLine(i,'peso_caja_kg',e.target.value)}/></label>}<label>Precio unitario *<input type="number" min="0" step="0.01" inputMode="decimal" value={line.precio_unitario} onChange={e=>editLine(i,'precio_unitario',e.target.value)}/></label>{lot?.cajas>0&&<label>Precio por<select value={line.unidad_precio} onChange={e=>editLine(i,'unidad_precio',e.target.value)}><option value="caja">Caja</option><option value="kg">Kilo</option></select></label>}<p className="wide">Disponible: {lot?`${num(remaining(lot))} ${lot.cajas>0?'cajas':'kg'}`:'Seleccione una boleta'} · Subtotal: <b>{money(totals[i],form.moneda)}</b></p></div></section>})}
    <button className="plant-add-worker local-add" onClick={()=>setForm(f=>({...f,lineas:[...f.lineas,emptyLine()]}))}><Plus size={16}/>Agregar otro producto o boleta</button><div className="receipt-calculation">Total a cobrar: <b>{money(totals.reduce((a,b)=>a+b,0),form.moneda)}</b></div><div className="formgrid"><label className="wide">Observaciones<input value={form.observaciones} onChange={e=>setForm({...form,observaciones:e.target.value})}/></label></div>{error&&<div className="formerror">{error}</div>}<div className="modalactions"><button disabled={saving} onClick={()=>setOpen(false)}>Cancelar</button><button disabled={saving} className="primary" onClick={save}>{saving?'Guardando…':'Registrar venta local'}</button></div></div></div>}
    {!open&&error&&<div className="formerror" role="alert">{error} <button type="button" onClick={reload}>Reintentar</button></div>}</>
}

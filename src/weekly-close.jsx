import React,{useEffect,useState} from 'react'
import {Plus,X} from 'lucide-react'
import {supabase} from './supabase'
import {addDays,costaRicaToday,isoWeek,mondayOf,weeklyTotals} from './weekly-model'

const money=(n,currency)=>new Intl.NumberFormat('es-CR',{style:'currency',currency,maximumFractionDigits:2}).format(Number(n)||0)
const labels={planilla:'Planilla',inventario:'Material consumido',servicios:'Servicios (luz, agua, gas)',contenedor:'Gasto de contenedor',transporte:'Transporte',otros:'Otro gasto'}
const blank=()=>({fecha:costaRicaToday(),categoria:'planilla',concepto:'',moneda:'CRC',monto:'',trabajador_id:'',orden_venta_id:'',unidad:'',cantidad:'',tarifa:'',referencia:'',observaciones:''})
const value=n=>n===''?null:Number(n)

export default function WeeklyClose(){
  const [monday,setMonday]=useState(()=>mondayOf(costaRicaToday()))
  const [records,setRecords]=useState({sales:[],purchases:[],locals:[],costs:[]})
  const [workers,setWorkers]=useState([]),[orders,setOrders]=useState([])
  const [loading,setLoading]=useState(true),[error,setError]=useState(''),[editing,setEditing]=useState(null),[form,setForm]=useState(blank),[saving,setSaving]=useState(false)
  const sunday=addDays(monday,6),next=addDays(monday,7),week=isoWeek(monday)
  const reload=async()=>{
    setLoading(true);setError('')
    const start=`${monday}T06:00:00Z`,end=`${next}T06:00:00Z`
    const results=await Promise.all([
      supabase.from('ordenes_venta').select('id,codigo,monto_cxc,finalizada_en').gte('finalizada_en',start).lt('finalizada_en',end),
      supabase.from('boletas_entrada').select('id,codigo,monto_cxp,finalizada_en').gte('finalizada_en',start).lt('finalizada_en',end),
      supabase.from('ventas_locales').select('id,codigo,fecha,moneda,ventas_segundas(subtotal)').gte('fecha',monday).lte('fecha',sunday),
      supabase.from('costos_operativos').select('*').gte('fecha',monday).lte('fecha',sunday).is('anulado_en',null).order('fecha',{ascending:false}).limit(1000),
      supabase.from('trabajadores').select('id,nombre').eq('activo',true).order('nombre').limit(1000),
      supabase.from('ordenes_venta').select('id,codigo,contenedor').order('creado_en',{ascending:false}).limit(1000)
    ])
    setLoading(false)
    const failure=results.find(r=>r.error)?.error
    if(failure){setError(`No se pudo cargar el corte: ${failure.message}`);return}
    setRecords({sales:results[0].data||[],purchases:results[1].data||[],locals:results[2].data||[],costs:results[3].data||[]})
    setWorkers(results[4].data||[]);setOrders(results[5].data||[])
  }
  useEffect(()=>{reload()},[monday])
  const totals=weeklyTotals(records)
  const open=(row=null)=>{
    setError('');setEditing(row?.id||'new')
    setForm(row?Object.fromEntries(Object.keys(blank()).map(k=>[k,row[k]??''])):{...blank(),fecha:monday})
  }
  const change=(key,val)=>setForm(f=>{
    const updated={...f,[key]:val}
    if((key==='cantidad'||key==='tarifa')&&updated.cantidad!==''&&updated.tarifa!=='')updated.monto=String(Math.round(Number(updated.cantidad)*Number(updated.tarifa)*100)/100)
    if(key==='trabajador_id'&&!f.concepto)updated.concepto=`Planilla · ${workers.find(w=>w.id===val)?.nombre||''}`
    if(key==='categoria'&&val!=='planilla'){updated.trabajador_id=''}
    return updated
  })
  const save=async()=>{
    const amount=Number(form.monto)
    if(!form.fecha||form.fecha<monday||form.fecha>sunday){setError('Seleccione una fecha dentro de la semana mostrada.');return}
    if(!form.concepto.trim()||!Number.isFinite(amount)||amount<=0||Math.round(amount*100)!==amount*100){setError('Complete concepto y monto positivo con hasta dos decimales.');return}
    if(form.categoria==='planilla'&&!form.trabajador_id){setError('Seleccione el trabajador de la planilla.');return}
    if((form.cantidad!==''||form.tarifa!==''||form.unidad!=='')&&(!form.unidad.trim()||!Number.isFinite(Number(form.cantidad))||Number(form.cantidad)<=0||!Number.isFinite(Number(form.tarifa))||Number(form.tarifa)<0)){setError('Para calcular por unidad complete unidad, cantidad y tarifa.');return}
    const payload={fecha:form.fecha,categoria:form.categoria,concepto:form.concepto.trim(),moneda:form.moneda,monto:amount,trabajador_id:form.categoria==='planilla'?form.trabajador_id:null,orden_venta_id:form.orden_venta_id||null,unidad:form.unidad.trim()||null,cantidad:value(form.cantidad),tarifa:value(form.tarifa),referencia:form.referencia.trim()||null,observaciones:form.observaciones.trim()||null}
    setSaving(true);setError('')
    const result=editing==='new'?await supabase.from('costos_operativos').insert(payload):await supabase.from('costos_operativos').update(payload).eq('id',editing).select('id').single()
    setSaving(false)
    if(result.error){setError(`No se pudo guardar: ${result.error.message}`);return}
    setEditing(null);reload()
  }
  const voidCost=async(row)=>{
    if(!window.confirm(`¿Anular el costo «${row.concepto}» de ${money(row.monto,row.moneda)}? Quedará conservado para auditoría.`))return
    const {error:failure}=await supabase.from('costos_operativos').update({anulado_en:new Date().toISOString()}).eq('id',row.id).select('id').single()
    if(failure){setError(`No se pudo anular: ${failure.message}`);return}
    reload()
  }
  return <><div className="modulebar"><div><p>Registre costos de la semana y vea ingresos y compras finalizados. El resultado es parcial hasta completar planilla, inventario y demás gastos.</p></div><button className="primary" onClick={()=>open()}><Plus size={18}/>Registrar costo</button></div>
    <div className="weekly-nav"><button onClick={()=>setMonday(addDays(monday,-7))}>← Semana anterior</button><label>Semana {week.week} · {week.year}<input type="date" value={monday} onChange={e=>e.target.value&&setMonday(mondayOf(e.target.value))}/></label><span>Del {monday} al {sunday}</span><button onClick={()=>setMonday(next)}>Semana siguiente →</button></div>
    {error&&!editing&&<div className="formerror" role="alert">{error}</div>}
    {loading?<div className="empty">Cargando el corte semanal…</div>:<><div className="bank-note">Resultado operativo <b>parcial</b>: se asignan ventas exportadas y compras por fecha de finalización, y ventas locales por fecha de venta. Los movimientos bancarios no se vuelven a sumar. Los importes en USD y CRC permanecen separados.</div>
      <div className="weekly-grid">{['CRC','USD'].map(currency=>{const t=totals[currency],result=t.export+t.local-t.product-t.costs;return <article key={currency}><small>{currency==='CRC'?'Colones':'Dólares'} · {currency}</small><div><span>Venta exportación finalizada</span><b>{money(t.export,currency)}</b></div><div><span>Venta local</span><b>{money(t.local,currency)}</b></div><div><span>Compra de producto finalizada</span><b>-{money(t.product,currency)}</b></div><div><span>Planilla y gastos registrados</span><b>-{money(t.costs,currency)}</b></div><div className="weekly-result"><span>Resultado parcial</span><strong>{money(result,currency)}</strong></div></article>})}</div>
      <div className="workers-panel"><h3>Gastos por categoría</h3>{Object.entries(labels).map(([category,name])=>{const parts=records.costs.filter(x=>x.categoria===category);return <article key={category}><div><b>{name}</b><span>{parts.length} registro(s)</span></div><strong>{['CRC','USD'].filter(currency=>parts.some(x=>x.moneda===currency)).map(currency=>`${money(parts.filter(x=>x.moneda===currency).reduce((sum,x)=>sum+Number(x.monto),0),currency)}`).join(' · ')||'Sin registrar'}</strong></article>})}</div>
      {records.costs.some(x=>x.orden_venta_id)&&<div className="workers-panel"><h3>Gastos asociados a pedidos</h3>{orders.filter(order=>records.costs.some(x=>x.orden_venta_id===order.id)).map(order=>{const parts=records.costs.filter(x=>x.orden_venta_id===order.id);return <article key={order.id}><div><b>{order.codigo} · {order.contenedor||'Sin contenedor'}</b><span>{parts.length} gasto(s) asociados</span></div><strong>{['CRC','USD'].filter(currency=>parts.some(x=>x.moneda===currency)).map(currency=>money(parts.filter(x=>x.moneda===currency).reduce((sum,x)=>sum+Number(x.monto),0),currency)).join(' · ')}</strong></article>})}</div>}
      <div className="workers-panel"><h3>Costos registrados en la semana</h3>{records.costs.map(row=><article key={row.id}><div><b>{row.fecha} · {labels[row.categoria]} · {row.concepto}</b><span>{row.trabajador_id?`${workers.find(w=>w.id===row.trabajador_id)?.nombre||'Trabajador'} · `:''}{row.orden_venta_id?`${orders.find(o=>o.id===row.orden_venta_id)?.codigo||'Pedido'} · `:''}{row.cantidad?`${row.cantidad} ${row.unidad} × ${money(row.tarifa,row.moneda)} · `:''}{row.referencia||'Sin referencia'}</span></div><strong>{money(row.monto,row.moneda)}</strong><button type="button" onClick={()=>open(row)}>Editar</button><button type="button" onClick={()=>voidCost(row)}>Anular</button></article>)}{!records.costs.length&&<p>Aún no se registraron planillas o gastos de esta semana.</p>}</div>
      <div className="weekly-sources"><details><summary>Documentos que alimentan el corte</summary><p>{records.sales.length} pedidos finalizados · {records.locals.length} ventas locales · {records.purchases.length} boletas finalizadas.</p>{records.sales.map(x=><p key={x.id}>Venta {x.codigo} · {money(x.monto_cxc,'USD')}</p>)}{records.locals.map(x=><p key={x.id}>Venta local {x.codigo} · {money((x.ventas_segundas||[]).reduce((sum,l)=>sum+Number(l.subtotal),0),x.moneda)}</p>)}{records.purchases.map(x=><p key={x.id}>Compra {x.codigo} · {money(x.monto_cxp,'CRC')}</p>)}</details></div>
    </>}
    {editing&&<div className="modalwrap"><div className="modal plant-form weekly-modal"><div className="modalhead"><div><span>CORTE SEMANAL</span><h2>{editing==='new'?'Registrar costo':'Editar costo'}</h2></div><button onClick={()=>setEditing(null)} aria-label="Cerrar"><X/></button></div><div className="formgrid"><label>Fecha de gasto<input type="date" value={form.fecha} min={monday} max={sunday} onChange={e=>change('fecha',e.target.value)}/></label><label>Categoría<select value={form.categoria} onChange={e=>change('categoria',e.target.value)}>{Object.entries(labels).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>{form.categoria==='planilla'&&<label className="wide">Trabajador<select value={form.trabajador_id} onChange={e=>change('trabajador_id',e.target.value)}><option value="">Seleccione un trabajador</option>{workers.map(w=><option key={w.id} value={w.id}>{w.nombre}</option>)}</select></label>}<label className="wide">Concepto<input value={form.concepto} onChange={e=>change('concepto',e.target.value)} placeholder="Ejemplo: planilla de empaque, electricidad, gas…"/></label><label>Moneda<select value={form.moneda} onChange={e=>change('moneda',e.target.value)}><option value="CRC">Colones</option><option value="USD">Dólares</option></select></label><label>Monto<input type="number" min="0.01" step="0.01" inputMode="decimal" value={form.monto} onChange={e=>change('monto',e.target.value)}/></label><label>Unidad (opcional)<input value={form.unidad} onChange={e=>change('unidad',e.target.value)} placeholder="días, horas, cajas, kg…"/></label><label>Cantidad<input type="number" min="0.001" step="0.001" inputMode="decimal" value={form.cantidad} onChange={e=>change('cantidad',e.target.value)}/></label><label>Tarifa por unidad<input type="number" min="0" step="0.0001" inputMode="decimal" value={form.tarifa} onChange={e=>change('tarifa',e.target.value)}/></label><label>Pedido o contenedor (opcional)<select value={form.orden_venta_id} onChange={e=>change('orden_venta_id',e.target.value)}><option value="">Gasto general de la semana</option>{orders.map(o=><option key={o.id} value={o.id}>{o.codigo} · {o.contenedor||'Contenedor pendiente'}</option>)}</select></label><label className="wide">Referencia o factura<input value={form.referencia} onChange={e=>change('referencia',e.target.value)}/></label><label className="wide">Observaciones<input value={form.observaciones} onChange={e=>change('observaciones',e.target.value)}/></label></div><p className="plant-help">Para material consumido registre aquí su costo; la cantidad física se registra por separado en Inventario de insumos. Registrar un pago bancario no duplica este costo.</p>{error&&<div className="formerror" role="alert">{error}</div>}<div className="modalactions"><button onClick={()=>setEditing(null)} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':'Guardar costo'}</button></div></div></div>}
  </>
}

import React,{useEffect,useState} from 'react'
import {supabase} from './supabase'
import {costaRicaToday} from './weekly-model'

const fresh=()=>({fecha:costaRicaToday(),comprador:'',sacos:'',kg_brutos:'',castigo_pct:'12',precio_quintal:'3000',moneda:'CRC',referencia:'',observaciones:'',boleta_id:'',fecha_vencimiento:costaRicaToday()})
const fmt=n=>Number(n||0).toLocaleString('es-CR',{maximumFractionDigits:2})

export default function FieldRejectSales({order,onSaved}){
  const [rows,setRows]=useState([]),[clients,setClients]=useState([]),[receipts,setReceipts]=useState([]),[form,setForm]=useState(fresh),[editing,setEditing]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState('')
  const [available,setAvailable]=useState({kg:order.rechazo_campo_kg??'',sacos:order.rechazo_campo_sacos??''})
  const [measured,setMeasured]=useState({kg:order.rechazo_campo_kg??'',sacos:order.rechazo_campo_sacos??''})
  const load=async()=>{
    const [sales,buyers,purchase,boletas]=await Promise.all([
      supabase.from('ventas_rechazo_campo').select('*').eq('orden_compra_id',order.id).order('fecha'),
      supabase.from('clientes').select('nombre').eq('activo',true).order('nombre'),
      supabase.from('ordenes_compra').select('rechazo_campo_kg,rechazo_campo_sacos,campo_sacos,campo_promedio_saco_kg').eq('id',order.id).single(),
      supabase.from('boletas_entrada').select('id,codigo,fecha_hora').eq('orden_compra_id',order.id)
    ])
    if(sales.error)setError(sales.error.message)
    else {setRows(sales.data||[]);if(order.editSaleId){const row=(sales.data||[]).find(r=>r.id===order.editSaleId);if(row)edit(row)}}
    if(boletas.error)setError(boletas.error.message);else setReceipts(boletas.data||[])
    if(!buyers.error)setClients(buyers.data||[])
    if(!purchase.error){
      const source=purchase.data
      const kg=order.tipo_compra==='En campo'?Number(source.campo_sacos||0)*Number(source.campo_promedio_saco_kg||0):source.rechazo_campo_kg??''
      const sacos=order.tipo_compra==='En campo'?source.campo_sacos:source.rechazo_campo_sacos??''
      setAvailable({kg,sacos});setMeasured({kg,sacos})
    }
  }
  useEffect(()=>{load()},[order.id])
  const amount=Number(form.kg_brutos||0)*(1-Number(form.castigo_pct||0)/100)/46*Number(form.precio_quintal||0)
  const change=(key,value)=>setForm(f=>({...f,[key]:value}))
  const edit=row=>{setEditing(row.id);setForm(Object.fromEntries(Object.keys(fresh()).map(k=>[k,String(row[k]??'')])));setError('')}
  const saveMeasured=async()=>{
    const kg=Number(measured.kg),sacos=Number(measured.sacos)
    if(!Number.isFinite(kg)||kg<0||!Number.isInteger(sacos)||sacos<0||kg<rows.reduce((sum,row)=>sum+Number(row.kg_brutos),0)){
      setError('Los kilos y sacos deben ser válidos; no puede reducir los kilos por debajo de los ya vendidos.');return
    }
    setBusy(true);setError('')
    const {error:e}=await supabase.from('ordenes_compra').update({rechazo_campo_kg:kg,rechazo_campo_sacos:sacos}).eq('id',order.id)
    setBusy(false)
    if(e){setError(`No se guardó el pesaje: ${e.message}`);return}
    load()
  }
  const save=async()=>{
    const sacos=Number(form.sacos),kg=Number(form.kg_brutos),discount=Number(form.castigo_pct),price=Number(form.precio_quintal)
    if(!form.fecha||!form.comprador.trim()||!Number.isInteger(sacos)||sacos<=0||(form.kg_brutos!==''&&(!Number.isFinite(kg)||kg<=0))||!Number.isFinite(discount)||discount<0||discount>=100||(form.precio_quintal!==''&&(!Number.isFinite(price)||price<=0))){
      setError('Anote fecha, comprador, sacos, kilos brutos, castigo de 0 a menos de 100 % y precio por quintal.');return
    }
    const payload={orden_compra_id:order.id,fecha:form.fecha,comprador:form.comprador.trim(),sacos,kg_brutos:form.kg_brutos===''?null:kg,castigo_pct:discount,precio_quintal:form.precio_quintal===''?null:price,boleta_id:form.boleta_id||null,fecha_vencimiento:form.fecha_vencimiento||form.fecha,moneda:form.moneda,referencia:form.referencia.trim()||null,observaciones:form.observaciones.trim()||null}
    setBusy(true);setError('')
    const {error:e}=editing?await supabase.from('ventas_rechazo_campo').update(payload).eq('id',editing):await supabase.from('ventas_rechazo_campo').insert(payload)
    setBusy(false)
    if(e){setError(`No se guardó la venta: ${e.message}`);return}
    setEditing(null);setForm(fresh());load();onSaved?.()
  }
  return <div className="formsection">
    <h3>Rechazo entregado desde el campo · {order.codigo}</h3><p>Puede guardar la entrega con fecha, comprador y sacos. Complete los kilos y el precio cuando el comprador dé la liquidación; mientras tanto aparecerá en Cuentas por cobrar como pendiente de liquidar.</p>
    <p className="purchasehint">Anote aquí el rechazo que no llegó a planta. Esta venta genera una cuenta por cobrar y se suma al ingreso del lote. La primera que entra a planta y la segunda que sale de planta se registran en sus boletas; no vuelva a anotarlas aquí.</p>
    {order.tipo_compra==='En campo'?<p className="receipt-calculation">Rechazo pesado en la compra de campo: {fmt(available.kg)} kg en {available.sacos} sacos. Corrija el pesaje en la sección de campo de esta orden.</p>:<div className="formgrid"><label>Rechazo generado en campo: sacos<input type="number" min="0" step="1" value={measured.sacos} onChange={e=>setMeasured(v=>({...v,sacos:e.target.value}))}/></label><label>Kilos brutos de rechazo generado<input type="number" min="0" step="0.001" value={measured.kg} onChange={e=>setMeasured(v=>({...v,kg:e.target.value}))}/></label><button type="button" disabled={busy} onClick={saveMeasured}>Guardar pesaje de campo</button></div>}
    <p className="receipt-calculation">Rechazo vendido: <b>{fmt(rows.reduce((sum,row)=>sum+Number(row.kg_brutos),0))} kg</b> · Pendiente de destino: <b>{available.kg===''?'Falta pesaje':`${fmt(Math.max(0,Number(available.kg)-rows.reduce((sum,row)=>sum+Number(row.kg_brutos),0)))} kg`}</b></p>
    {rows.map(row=><div className="receipt-calculation" key={row.id}><b>{row.fecha} · {row.comprador}</b> · {row.sacos} sacos · {fmt(row.kg_brutos)} kg brutos − {fmt(row.castigo_pct)} % = {fmt(row.kg_pagables)} kg pagables · {row.monto==null?'Pendiente de liquidar':`${row.moneda} ${fmt(row.monto)}`} · {row.boleta_id?receipts.find(b=>b.id===row.boleta_id)?.codigo||'Boleta vinculada':'Sin boleta vinculada'} <button type="button" onClick={()=>edit(row)}>Editar venta</button></div>)}
    <h4>{editing?'Corregir venta':'Nueva venta de rechazo'}</h4>
    <div className="formgrid">
      <label>Fecha de salida *<input type="date" value={form.fecha} onChange={e=>change('fecha',e.target.value)}/></label>
      <label>Comprador *<input list="compradores-rechazo" value={form.comprador} onChange={e=>change('comprador',e.target.value)} placeholder="Seleccione o escriba un comprador"/><datalist id="compradores-rechazo">{clients.map(c=><option key={c.nombre} value={c.nombre}/>)}</datalist></label>
      <label>Sacos enviados *<input type="number" min="1" step="1" value={form.sacos} onChange={e=>change('sacos',e.target.value)}/></label>
      <label>Kilos brutos (puede completar después)<input type="number" min="0.001" step="0.001" value={form.kg_brutos} onChange={e=>change('kg_brutos',e.target.value)}/></label>
      <label>Castigo del comprador (%) *<input type="number" min="0" max="99.99" step="0.01" value={form.castigo_pct} onChange={e=>change('castigo_pct',e.target.value)}/></label>
      <label>Precio por quintal (puede completar después)<input type="number" min="0.01" step="0.01" value={form.precio_quintal} onChange={e=>change('precio_quintal',e.target.value)}/></label>
      <label>Moneda<select value={form.moneda} onChange={e=>change('moneda',e.target.value)}><option>CRC</option><option>USD</option></select></label>
      <label>Boleta de origen<select value={form.boleta_id} onChange={e=>change('boleta_id',e.target.value)}><option value="">Sin boleta todavía</option>{receipts.map(b=><option key={b.id} value={b.id}>{b.codigo}</option>)}</select></label><label>Fecha prevista de cobro<input type="date" value={form.fecha_vencimiento} onChange={e=>change('fecha_vencimiento',e.target.value)}/></label>
      <label>Referencia del comprador<input value={form.referencia} onChange={e=>change('referencia',e.target.value)}/></label>
      <label className="wide">Observaciones<input value={form.observaciones} onChange={e=>change('observaciones',e.target.value)}/></label>
      <div className="receipt-calculation wide">Kilos pagables: <b>{fmt(Number(form.kg_brutos||0)*(1-Number(form.castigo_pct||0)/100))}</b> · Venta prevista: <b>{form.kg_brutos===''||form.precio_quintal===''?'Pendiente de liquidar':`${form.moneda} ${fmt(amount)}`}</b></div>
    </div>
    {error&&<p className="formerror" role="alert">{error}</p>}
    <button type="button" disabled={busy} onClick={save}>{busy?'Guardando…':editing?'Guardar corrección':'Guardar venta y generar cuenta por cobrar'}</button>
    {editing&&<button type="button" onClick={()=>{setEditing(null);setForm(fresh());setError('')}}>Cancelar corrección</button>}
  </div>
}

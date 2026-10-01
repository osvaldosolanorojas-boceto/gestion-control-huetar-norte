import React,{useEffect,useState} from 'react'
import {supabase} from './supabase'
import {cash} from './finance'

const blank=()=>({finca_id:'',nombre:'',tipo:'Finca',modalidad:'Alquilada',propietario:'',alquiler_monto:'',moneda:'CRC',frecuencia_pago:'',forma_pago:'',contrato_inicio:'',contrato_vencimiento:'',porcentaje_propietario:'',tierra_mecanizada:false,obligaciones:'',observaciones:''})
export default function FarmProperties({farms,onChange}){
 const [rows,setRows]=useState([]),[form,setForm]=useState(null),[error,setError]=useState(''),[saving,setSaving]=useState(false)
 const load=async()=>{const {data,error:e}=await supabase.from('propiedades_finca').select('*').order('nombre');if(e)setError(e.message);else{setRows(data||[]);setError('')}}
 useEffect(()=>{load()},[])
 const change=(key,value)=>setForm(f=>({...f,[key]:value}))
 const edit=row=>setForm({...blank(),...Object.fromEntries(Object.entries(row).map(([k,v])=>[k,v??'']))})
 const save=async()=>{
  if(!form.finca_id||!form.nombre.trim()){setError('Seleccione la administración y escriba el nombre.');return}
  const percent=form.porcentaje_propietario===''?null:Number(form.porcentaje_propietario),amount=form.alquiler_monto===''?null:Number(form.alquiler_monto)
  if(form.modalidad==='Porcentaje sobre ventas brutas'&&(percent===null||!Number.isFinite(percent)||percent<0||percent>100)){setError('Escriba el porcentaje del propietario entre 0 y 100.');return}
  if(form.modalidad==='Alquilada'&&amount!==null&&(!Number.isFinite(amount)||amount<0)){setError('El alquiler debe ser un monto válido, mayor o igual a cero.');return}
  if(form.contrato_inicio&&form.contrato_vencimiento&&form.contrato_vencimiento<form.contrato_inicio){setError('El vencimiento no puede ser anterior al inicio.');return}
  const payload=Object.fromEntries(Object.keys(blank()).map(k=>[k,form[k]===''?null:form[k]]));payload.nombre=form.nombre.trim();payload.alquiler_monto=form.modalidad==='Alquilada'?amount:null;payload.porcentaje_propietario=form.modalidad==='Porcentaje sobre ventas brutas'?percent:null
  setSaving(true);setError('');const query=form.id?supabase.from('propiedades_finca').update(payload).eq('id',form.id):supabase.from('propiedades_finca').insert(payload);const {error:e}=await query.select('id').single();setSaving(false)
  if(e){setError(`No se pudo guardar: ${e.message}`);return}setForm(null);await load();onChange()
 }
 const today=new Date().toLocaleDateString('en-CA',{timeZone:'America/Costa_Rica'})
 return <section className="panel farm-panel"><div className="panelhead"><div><h3>Propiedades y contratos</h3><p>Cada administración comparte bodega, inventarios, personal y planilla. Sus propiedades conservan su contrato y sus lotes.</p></div><button onClick={()=>{setForm(blank());setError('')}}>Agregar propiedad</button></div>
 {error&&<p className="formerror">{error}</p>}
 {form&&<div className="formgrid">
 <label>Administración<select value={form.finca_id} onChange={e=>change('finca_id',e.target.value)} disabled={Boolean(form.id)}><option value="">Seleccione</option>{farms.filter(f=>f.activa!==false||f.id===form.finca_id).map(f=><option key={f.id} value={f.id}>{f.nombre}</option>)}</select></label>
 <label>Nombre de la propiedad<input value={form.nombre} onChange={e=>change('nombre',e.target.value)}/></label>
 <label>Tipo<select value={form.tipo} onChange={e=>change('tipo',e.target.value)}>{['Finca','Lote pequeño'].map(v=><option key={v}>{v}</option>)}</select></label>
 <label>Modalidad<select value={form.modalidad} onChange={e=>change('modalidad',e.target.value)}>{['Pendiente','Alquilada','Propia','Porcentaje sobre ventas brutas'].map(v=><option key={v}>{v}</option>)}</select></label>
 <label>Propietario<input value={form.propietario} onChange={e=>change('propietario',e.target.value)}/></label>
 {form.modalidad==='Alquilada'&&<><label>Monto del alquiler<input type="number" min="0" step="0.01" value={form.alquiler_monto} onChange={e=>change('alquiler_monto',e.target.value)} placeholder="Pendiente"/></label><label>Moneda<select value={form.moneda} onChange={e=>change('moneda',e.target.value)}><option>CRC</option><option>USD</option></select></label><label>Frecuencia de pago<input value={form.frecuencia_pago} onChange={e=>change('frecuencia_pago',e.target.value)} placeholder="Mensual, anual, por cosecha…"/></label><label>Forma y condiciones de pago<input value={form.forma_pago} onChange={e=>change('forma_pago',e.target.value)} placeholder="Depósito, adelanto, cuotas…"/></label></>}
 {form.modalidad==='Porcentaje sobre ventas brutas'&&<><label>Porcentaje del propietario (%)<input type="number" min="0" max="100" step="0.01" value={form.porcentaje_propietario} onChange={e=>change('porcentaje_propietario',e.target.value)}/></label><p className="wide">Se pacta sobre lo vendido en bruto de esta propiedad, antes de descontar los gastos agrícolas.</p></>}
 {form.modalidad==='Propia'?<p className="wide">Propiedad de Agrosolano. La valoración del terreno queda para una etapa posterior.</p>:<><label>Inicio del contrato<input type="date" value={form.contrato_inicio} onChange={e=>change('contrato_inicio',e.target.value)}/></label><label>Vencimiento del contrato<input type="date" value={form.contrato_vencimiento} onChange={e=>change('contrato_vencimiento',e.target.value)}/></label></>}
 <label><input type="checkbox" checked={form.tierra_mecanizada} onChange={e=>change('tierra_mecanizada',e.target.checked)}/> El propietario aporta tierra mecanizada</label>
 <label className="wide">Obligaciones del acuerdo<textarea value={form.obligaciones} onChange={e=>change('obligaciones',e.target.value)} placeholder="Cuidar cercas, reparar caminos y otras condiciones"/></label>
 <label className="wide">Observaciones<textarea value={form.observaciones} onChange={e=>change('observaciones',e.target.value)}/></label>
 <button className="primary" disabled={saving} onClick={save}>{saving?'Guardando…':'Guardar ficha'}</button><button disabled={saving} onClick={()=>setForm(null)}>Cancelar</button></div>}
 {farms.filter(f=>rows.some(p=>p.finca_id===f.id)).map(f=><details key={f.id} open><summary><b>{f.nombre}</b></summary>{rows.filter(p=>p.finca_id===f.id).map(p=><article className="farm-lot" key={p.id}><div className="panelhead"><h4>{p.nombre} · {p.tipo}</h4><button onClick={()=>edit(p)}>Editar ficha</button></div><p>{p.modalidad}{p.propietario?` · ${p.propietario}`:''}{p.modalidad==='Porcentaje sobre ventas brutas'?` · ${p.porcentaje_propietario}% de ventas brutas`:p.modalidad==='Alquilada'?` · ${p.alquiler_monto==null?'Monto pendiente':cash(p.alquiler_monto,p.moneda)}${p.frecuencia_pago?` · ${p.frecuencia_pago}`:''}`:''}</p>{p.forma_pago&&<p>Pago: {p.forma_pago}</p>}{p.modalidad!=='Propia'&&<p>Inicio: {p.contrato_inicio||'Pendiente'} · Vencimiento: {p.contrato_vencimiento||'Pendiente'}{p.contrato_vencimiento&&p.contrato_vencimiento<today?' · CONTRATO VENCIDO':''}</p>}{p.tierra_mecanizada&&<p>El propietario aporta tierra mecanizada.</p>}{p.obligaciones&&<p>Obligaciones: {p.obligaciones}</p>}{p.observaciones&&<p>{p.observaciones}</p>}</article>)}</details>)}
 <p>Esta ficha registra lo pactado. Los pagos y gastos se registran por separado; guardar el contrato no genera cobros ni pagos automáticos.</p></section>
}

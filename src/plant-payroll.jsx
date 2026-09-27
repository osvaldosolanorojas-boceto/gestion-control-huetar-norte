import React,{useEffect,useState} from 'react'
import {Plus,X} from 'lucide-react'
import {supabase} from './supabase'
import {addDays,costaRicaToday,isoWeek,sundayOf} from './weekly-model'

const colones=n=>new Intl.NumberFormat('es-CR',{style:'currency',currency:'CRC',maximumFractionDigits:2}).format(Number(n)||0)
const blank=()=>({trabajador_id:'',modalidad:'Fijo semanal',salario_semanal:'',horas_ordinarias:'',tarifa_hora:'',horas_extra:'',tarifa_extra:'',adicionales:'',deducciones:'',observaciones:''})
const amount=v=>v===''?0:Number(v)
const calculated=f=>{
  const base=f.modalidad==='Fijo semanal'?amount(f.salario_semanal):amount(f.horas_ordinarias)*amount(f.tarifa_hora)
  const bruto=Math.round((base+amount(f.horas_extra)*amount(f.tarifa_extra)+amount(f.adicionales))*100)/100
  return {bruto,neto:Math.round((bruto-amount(f.deducciones))*100)/100}
}

export default function PlantPayroll({go}){
  const [weekStart,setWeekStart]=useState(()=>sundayOf(costaRicaToday()))
  const [workers,setWorkers]=useState([]),[rows,setRows]=useState([]),[history,setHistory]=useState([])
  const [editing,setEditing]=useState(null),[form,setForm]=useState(blank),[error,setError]=useState(''),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false)
  const end=addDays(weekStart,6),label=isoWeek(addDays(weekStart,1))
  const reload=async()=>{
    setLoading(true);setError('')
    const [people,payroll,past]=await Promise.all([
      supabase.from('trabajadores').select('id,nombre,categoria,activo,modalidad_pago').order('nombre').limit(1000),
      supabase.from('planillas_planta').select('*').eq('semana_inicio',weekStart).is('anulado_en',null).order('creado_en').limit(1000),
      supabase.from('planillas_planta').select('trabajador_id,modalidad,salario_semanal,horas_ordinarias,tarifa_hora,tarifa_extra').lt('semana_inicio',weekStart).is('anulado_en',null).order('semana_inicio',{ascending:false}).limit(1000)
    ])
    setLoading(false)
    const failure=people.error||payroll.error||past.error
    if(failure){setError(`No se pudo cargar la planilla: ${failure.message}`);return}
    setWorkers(people.data||[]);setRows(payroll.data||[]);setHistory(past.data||[])
  }
  useEffect(()=>{reload()},[weekStart])
  const open=row=>{setError('');setEditing(row?.id||'new');setForm(row?Object.fromEntries(Object.keys(blank()).map(key=>[key,String(row[key]??'')])):blank())}
  const chooseWorker=id=>{
    const previous=history.find(row=>row.trabajador_id===id)
    const worker=workers.find(row=>row.id===id)
    setForm(current=>({...current,...blank(),trabajador_id:id,modalidad:worker?.modalidad_pago==='Salario fijo'?'Fijo semanal':'Por horas',...(previous?{
      modalidad:previous.modalidad,salario_semanal:previous.modalidad==='Fijo semanal'?String(previous.salario_semanal):'',
      horas_ordinarias:previous.modalidad==='Por horas'?String(previous.horas_ordinarias):'',
      tarifa_hora:previous.modalidad==='Por horas'?String(previous.tarifa_hora):'',
      tarifa_extra:Number(previous.tarifa_extra)>0?String(previous.tarifa_extra):''
    }:{})}))
  }
  const save=async()=>{
    if(!form.trabajador_id){setError('Seleccione un colaborador.');return}
    if(rows.some(row=>row.trabajador_id===form.trabajador_id&&row.id!==editing)){setError('Este colaborador ya tiene una planilla en la semana. Edite ese registro.');return}
    const numeric=['salario_semanal','horas_ordinarias','tarifa_hora','horas_extra','tarifa_extra','adicionales','deducciones']
    if(numeric.some(key=>!Number.isFinite(amount(form[key]))||amount(form[key])<0||Math.round(amount(form[key])*100)!==amount(form[key])*100)){setError('Revise los importes y horas; use números positivos con hasta dos decimales.');return}
    if(form.modalidad==='Fijo semanal'&&!(amount(form.salario_semanal)>0)||form.modalidad==='Por horas'&&(!(amount(form.horas_ordinarias)>0)||!(amount(form.tarifa_hora)>0))){setError('Indique el salario semanal o las horas y tarifa ordinaria.');return}
    if((amount(form.horas_extra)>0)!==(amount(form.tarifa_extra)>0)){setError('Para las horas extra indique cantidad y tarifa; deje ambos en cero si no hubo extras.');return}
    const {neto}=calculated(form)
    if(neto<0){setError('Las deducciones no pueden superar el salario bruto.');return}
    const payload={semana_inicio:weekStart,trabajador_id:form.trabajador_id,modalidad:form.modalidad,
      salario_semanal:form.modalidad==='Fijo semanal'?amount(form.salario_semanal):0,
      horas_ordinarias:form.modalidad==='Por horas'?amount(form.horas_ordinarias):0,
      tarifa_hora:form.modalidad==='Por horas'?amount(form.tarifa_hora):0,
      horas_extra:amount(form.horas_extra),tarifa_extra:amount(form.tarifa_extra),
      adicionales:amount(form.adicionales),deducciones:amount(form.deducciones),
      observaciones:form.observaciones.trim()||null}
    setSaving(true);setError('')
    const result=editing==='new'
      ?await supabase.from('planillas_planta').insert(payload).select('id').single()
      :await supabase.from('planillas_planta').update(payload).eq('id',editing).select('id').single()
    setSaving(false)
    if(result.error){setError(`No se pudo guardar la planilla: ${result.error.message}`);return}
    setEditing(null);reload()
  }
  const voidRow=async row=>{
    if(!window.confirm(`¿Anular la planilla de ${workers.find(w=>w.id===row.trabajador_id)?.nombre||'este colaborador'} de la semana ${label.week}? El registro queda para auditoría.`))return
    setError('')
    const {error:failure}=await supabase.from('planillas_planta').update({anulado_en:new Date().toISOString()}).eq('id',row.id).select('id').single()
    if(failure){setError(`No se pudo anular: ${failure.message}`);return}
    reload()
  }
  const gross=rows.reduce((sum,row)=>sum+Number(row.bruto),0),net=rows.reduce((sum,row)=>sum+Number(row.neto),0)
  const preview=calculated(form)
  return <>
    <div className="modulebar"><div><p>Registre una planilla por colaborador y semana. Incluye personal operativo, encargados y administrativos de planta.</p></div><button className="primary" onClick={()=>open()}><Plus size={18}/>Agregar colaborador</button></div>
    <div className="weekly-nav"><button onClick={()=>setWeekStart(addDays(weekStart,-7))}>← Semana anterior</button><label>Semana {label.week} · {label.year}<input type="date" value={weekStart} onChange={e=>e.target.value&&setWeekStart(sundayOf(e.target.value))}/></label><span>Del {weekStart} al {end}</span><button onClick={()=>setWeekStart(addDays(weekStart,7))}>Semana siguiente →</button></div>
    {error&&!editing&&<div className="formerror" role="alert">{error}</div>}
    <div className="bank-note">El salario bruto se suma al gasto del corte semanal. Las deducciones cambian el neto del colaborador, sin rebajar el costo de planta. Registre aquí esta planilla para evitar duplicarla como costo manual.</div>
    <div className="weekly-grid"><article><small>Planilla de planta · CRC</small><div><span>Colaboradores</span><b>{rows.length}</b></div><div><span>Costo bruto de la semana</span><b>{colones(gross)}</b></div><div><span>Deducciones</span><b>{colones(gross-net)}</b></div><div className="weekly-result"><span>Neto calculado</span><strong>{colones(net)}</strong></div></article></div>
    {loading?<div className="empty">Cargando planilla…</div>:<div className="workers-panel"><h3>Detalle por colaborador</h3>{rows.map(row=>{const worker=workers.find(w=>w.id===row.trabajador_id);return <article key={row.id}><div><b>{worker?.nombre||'Colaborador'} · {worker?.categoria||'Operativo'}</b><span>{row.modalidad}{row.modalidad==='Por horas'?` · ${row.horas_ordinarias} horas × ${colones(row.tarifa_hora)}`:''}{Number(row.horas_extra)>0?` · ${row.horas_extra} extras × ${colones(row.tarifa_extra)}`:''} · Bruto {colones(row.bruto)} · Deducciones {colones(row.deducciones)}</span>{row.observaciones&&<small>{row.observaciones}</small>}</div><strong>{colones(row.neto)} neto</strong><button onClick={()=>open(row)}>Editar</button><button onClick={()=>voidRow(row)}>Anular</button></article>})}{!rows.length&&<p>Aún no hay planilla registrada para esta semana.</p>}</div>}
    <button type="button" onClick={()=>go('Colaboradores')}>Administrar fichas de colaboradores</button>
    {editing&&<div className="modalwrap"><div className="modal plant-form weekly-modal"><div className="modalhead"><div><span>PLANILLA DE PLANTA · SEMANA {label.week}</span><h2>{editing==='new'?'Agregar colaborador':'Editar planilla'}</h2></div><button onClick={()=>setEditing(null)} aria-label="Cerrar"><X/></button></div>
      <div className="formgrid"><label className="wide">Colaborador *<select value={form.trabajador_id} onChange={e=>chooseWorker(e.target.value)}><option value="">Seleccione un colaborador</option>{workers.filter(w=>w.activo||w.id===form.trabajador_id).map(w=><option key={w.id} value={w.id}>{w.nombre} · {w.categoria||'Operativo'}</option>)}</select></label>
        <label>Forma de cálculo<select value={form.modalidad} onChange={e=>setForm(current=>({...current,modalidad:e.target.value,salario_semanal:'',horas_ordinarias:'',tarifa_hora:''}))}><option>Fijo semanal</option><option>Por horas</option></select></label>
        {form.modalidad==='Fijo semanal'?<label>Salario fijo de esta semana (₡) *<input type="number" min="0" step="0.01" value={form.salario_semanal} onChange={e=>setForm({...form,salario_semanal:e.target.value})}/></label>:<><label>Horas ordinarias *<input type="number" min="0" step="0.01" value={form.horas_ordinarias} onChange={e=>setForm({...form,horas_ordinarias:e.target.value})}/></label><label>Tarifa por hora (₡) *<input type="number" min="0" step="0.01" value={form.tarifa_hora} onChange={e=>setForm({...form,tarifa_hora:e.target.value})}/></label></>}
        <label>Horas extra<input type="number" min="0" step="0.01" value={form.horas_extra} onChange={e=>setForm({...form,horas_extra:e.target.value})}/></label><label>Tarifa de hora extra (₡)<input type="number" min="0" step="0.01" value={form.tarifa_extra} onChange={e=>setForm({...form,tarifa_extra:e.target.value})}/></label>
        <label>Adicionales (₡)<input type="number" min="0" step="0.01" value={form.adicionales} onChange={e=>setForm({...form,adicionales:e.target.value})}/></label><label>Deducciones (₡)<input type="number" min="0" step="0.01" value={form.deducciones} onChange={e=>setForm({...form,deducciones:e.target.value})}/></label>
        <label className="wide">Observaciones<input value={form.observaciones} onChange={e=>setForm({...form,observaciones:e.target.value})}/></label>
      </div><div className="receipt-calculation">Costo bruto: <b>{colones(preview.bruto)}</b> · Neto calculado: <b>{colones(preview.neto)}</b></div>
      {error&&<div className="formerror" role="alert">{error}</div>}<div className="modalactions"><button onClick={()=>setEditing(null)} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':'Guardar planilla'}</button></div>
    </div></div>}
  </>
}

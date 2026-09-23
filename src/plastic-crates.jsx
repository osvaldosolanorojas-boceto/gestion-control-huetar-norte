import React,{useEffect,useState} from 'react'
import {supabase} from './supabase'

const blank=()=>({tipo:'entrega',cantidad:'',responsable_id:'',nombre:'',referencia:'',observaciones:''})
const kinds={entrega:'Entrega',devolucion:'Devolución',compra:'Compra / inventario inicial',baja_planta:'Baja en planta',perdida_tercero:'Pérdida confirmada'}
export default function PlasticCrates(){
  const [stock,setStock]=useState(null),[people,setPeople]=useState([]),[history,setHistory]=useState([]),[form,setForm]=useState(blank),[saving,setSaving]=useState(false),[error,setError]=useState(''),[show,setShow]=useState(false)
  const reload=async()=>{
    const [a,b,c]=await Promise.all([supabase.from('control_cajas_plasticas').select('*').eq('id',1).single(),supabase.from('responsables_cajas').select('*').order('nombre'),supabase.from('movimientos_cajas_plasticas').select('*').order('creado_en',{ascending:false}).limit(150)])
    if(a.error||b.error||c.error){setError(`No se pudieron cargar las cajas: ${(a.error||b.error||c.error).message}`);return}
    setStock(a.data);setPeople(b.data||[]);setHistory(c.data||[])
  }
  useEffect(()=>{reload()},[])
  const open=(tipo='entrega',person=null)=>{setForm({...blank(),tipo,responsable_id:person?.id||''});setError('');setShow(true)}
  const save=async()=>{
    const quantity=Number(form.cantidad),needsPerson=['entrega','devolucion','perdida_tercero'].includes(form.tipo)
    if(!Number.isInteger(quantity)||quantity<=0){setError('Indique una cantidad entera mayor que cero.');return}
    if(needsPerson&&!form.responsable_id&&!(form.tipo==='entrega'&&form.nombre.trim())){setError('Seleccione o escriba quién lleva las cajas.');return}
    setSaving(true);setError('')
    const {error:e}=await supabase.rpc('registrar_movimiento_cajas',{p_tipo:form.tipo,p_cantidad:quantity,p_responsable_id:form.responsable_id||null,p_nombre:form.nombre.trim()||null,p_referencia:form.referencia.trim()||null,p_observaciones:form.observaciones.trim()||null})
    setSaving(false);if(e){setError(`No se pudo registrar: ${e.message}`);return}setShow(false);reload()
  }
  const outstanding=people.reduce((sum,p)=>sum+p.pendientes,0)
  return <><div className="modulebar"><div><p>Controle entregas y devoluciones por persona o cuadrilla. El saldo pendiente muestra quién tiene cajas fuera de planta.</p></div><button className="primary" onClick={()=>open()}>Registrar entrega</button></div>
    <div className="crate-stats"><article><small>Total registrado</small><strong>{stock?.total??'—'}</strong></article><article><small>Disponibles en planta</small><strong>{stock?.disponibles??'—'}</strong></article><article><small>En manos de terceros</small><strong>{outstanding}</strong></article></div>
    <div className="crate-actions"><button onClick={()=>open('compra')}>Ingresar cajas / saldo inicial</button><button onClick={()=>open('devolucion')}>Registrar devolución</button><button onClick={()=>open('baja_planta')}>Dar de baja</button></div>
    <section className="workers-panel"><h3>¿Quién tiene las cajas?</h3>{people.filter(p=>p.pendientes>0).map(p=><article key={p.id}><div><b>{p.nombre}</b><span>{p.pendientes} cajas pendientes de devolver</span></div><button onClick={()=>open('devolucion',p)}>Registrar devolución</button></article>)}{!people.some(p=>p.pendientes>0)&&<p>No hay cajas pendientes registradas.</p>}</section>
    <section className="workers-panel"><h3>Movimientos recientes</h3>{history.map(m=><article key={m.id}><div><b>{kinds[m.tipo]} · {m.cantidad} cajas</b><span>{people.find(p=>p.id===m.responsable_id)?.nombre||'Planta'} · {new Date(m.creado_en).toLocaleString('es-CR')}{m.referencia?` · ${m.referencia}`:''}{m.observaciones?` · ${m.observaciones}`:''}</span></div></article>)}{!history.length&&<p>Sin movimientos todavía.</p>}</section>
    {show&&<div className="modalwrap"><div className="modal carton-modal supply-modal"><div className="modalhead"><div><span>CAJAS PLÁSTICAS</span><h2>Registrar movimiento</h2></div><button aria-label="Cerrar" onClick={()=>setShow(false)}>×</button></div><div className="formgrid"><label>Movimiento<select value={form.tipo} onChange={e=>setForm({...form,tipo:e.target.value,responsable_id:'',nombre:''})}>{Object.entries(kinds).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label><label>Cantidad de cajas *<input type="number" min="1" step="1" inputMode="numeric" value={form.cantidad} onChange={e=>setForm({...form,cantidad:e.target.value})}/></label>
    {['entrega','devolucion','perdida_tercero'].includes(form.tipo)&&<><label className="wide">Responsable<select value={form.responsable_id} onChange={e=>setForm({...form,responsable_id:e.target.value,nombre:''})}><option value="">{form.tipo==='entrega'?'Persona o cuadrilla nueva':'Seleccione quién las tiene'}</option>{people.filter(p=>form.tipo==='entrega'||p.pendientes>0).map(p=><option key={p.id} value={p.id}>{p.nombre} · {p.pendientes} pendientes</option>)}</select></label>{form.tipo==='entrega'&&!form.responsable_id&&<label className="wide">Nombre de nueva persona o cuadrilla<input value={form.nombre} onChange={e=>setForm({...form,nombre:e.target.value})} placeholder="Nombre completo o cuadrilla"/></label>}</>}
    <label className="wide">Referencia (boleta, finca o compra)<input value={form.referencia} onChange={e=>setForm({...form,referencia:e.target.value})}/></label><label className="wide">Observaciones<input value={form.observaciones} onChange={e=>setForm({...form,observaciones:e.target.value})}/></label></div>
    {error&&<div className="formerror">{error}</div>}<div className="modalactions"><button onClick={()=>setShow(false)} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':'Guardar movimiento'}</button></div></div></div>}
    {!show&&error&&<div className="formerror">{error}</div>}</>
}

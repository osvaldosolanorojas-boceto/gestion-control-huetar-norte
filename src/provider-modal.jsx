import React,{useState} from 'react'
import {X} from 'lucide-react'
import {supabase} from './supabase'

const empty={nombre:'',cedula:'',telefono:'',residencia:'',zona:'',tipo:'Agricultor',productos:[],activo:true}
export default function ProviderModal({provider,close,onSaved}){
  const [form,setForm]=useState(()=>provider?Object.fromEntries(Object.keys(empty).map(key=>[key,provider[key]??empty[key]])):empty)
  const [products,setProducts]=useState(()=>(provider?.productos||[]).join(', '))
  const [saving,setSaving]=useState(false),[error,setError]=useState('')
  const change=e=>setForm(current=>({...current,[e.target.name]:e.target.type==='checkbox'?e.target.checked:e.target.value}))
  const save=async()=>{
    if(!form.nombre.trim()){setError('Escriba el nombre del proveedor.');return}
    setSaving(true);setError('')
    const payload={...form,nombre:form.nombre.trim(),cedula:form.cedula.trim()||null,telefono:form.telefono.trim()||null,residencia:form.residencia.trim()||null,zona:form.zona.trim()||null,productos:products.split(',').map(x=>x.trim()).filter(Boolean)}
    const {error:failure}=provider?await supabase.from('proveedores').update(payload).eq('id',provider.id):await supabase.from('proveedores').insert(payload)
    setSaving(false)
    if(failure){setError(`No se pudo guardar: ${failure.message}`);return}
    onSaved()
  }
  const remove=async()=>{
    if(!window.confirm(`¿Eliminar a ${provider.nombre} de la lista de proveedores? Sus compras y pagos anteriores conservarán el historial.`))return
    setSaving(true);setError('')
    const {error:failure}=await supabase.rpc('retirar_registro',{p_tipo:'proveedor',p_id:provider.id})
    setSaving(false);if(failure){setError(`No se pudo eliminar: ${failure.message}`);return}onSaved()
  }
  return <div className="modalwrap"><div className="modal realform clientform"><div className="modalhead"><div><span>{provider?'EDITAR REGISTRO':'NUEVO REGISTRO'}</span><h2>Ficha del proveedor</h2></div><button onClick={close} aria-label="Cerrar"><X/></button></div><div className="formsection"><h3>Datos del proveedor</h3><div className="formgrid">
    <label>Nombre completo o razón social *<input name="nombre" value={form.nombre} onChange={change}/></label><label>Cédula o identificación<input name="cedula" value={form.cedula} onChange={change}/></label>
    <label>Teléfono<input name="telefono" type="tel" value={form.telefono} onChange={change}/></label><label>Tipo<select name="tipo" value={form.tipo} onChange={change}><option>Agricultor</option><option>Intermediario</option><option>Propio</option><option>Transportista</option></select></label>
    <label>Residencia<input name="residencia" value={form.residencia} onChange={change}/></label><label>Zona<input name="zona" value={form.zona} onChange={change}/></label>
    <label className="wide">Productos (separados por coma)<input value={products} onChange={e=>setProducts(e.target.value)} placeholder="Yuca, ñampí…"/></label><label className="checklabel"><input type="checkbox" name="activo" checked={form.activo} onChange={change}/> Proveedor activo</label>
  </div></div>{error&&<div className="formerror">{error}</div>}<div className="modalactions">{provider?.activo&&<button className="danger-action" type="button" onClick={remove} disabled={saving}>Eliminar proveedor</button>}<button onClick={close} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':provider?'Guardar cambios':'Guardar proveedor'}</button></div></div></div>
}

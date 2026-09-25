import React,{useEffect,useState} from 'react'
import {Plus, X, Pencil, Trash2, Users, ShieldCheck} from 'lucide-react'
import {supabase} from './supabase'
import './users-settings.css'

const groups=[
  ['Operación',['Resumen','Órdenes de compra','Boletas de entrada','Producción y rendimientos','Mapa de carga','Saldo yuca EE. UU.','Segundas y rechazo','Órdenes de venta']],
  ['Personas y catálogos',['Proveedores','Clientes','Colaboradores','Empresas','Fincas']],
  ['Administración',['Inventarios','Finanzas','Efectivo','Bancos','Corte semanal']]
]
const presets={
  planta:['Boletas de entrada','Producción y rendimientos','Mapa de carga','Saldo yuca EE. UU.','Segundas y rechazo'],
  oficina:['Resumen','Órdenes de compra','Boletas de entrada','Órdenes de venta','Proveedores','Clientes','Finanzas','Bancos','Efectivo','Corte semanal'],
  finca:['Fincas'],bodega:['Inventarios'],chofer:['Mapa de carga']
}
const empty={nombre:'',correo:'',area:'planta',modulos:presets.planta,observaciones:''}
const title=area=>({planta:'Planta',oficina:'Oficina',finca:'Finca',bodega:'Bodega',chofer:'Chofer'})[area]||area

export default function UsersSettings({profile}){
  const [rows,setRows]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[editing,setEditing]=useState(null),[saving,setSaving]=useState(false)
  const load=async()=>{setLoading(true);const {data,error:loadError}=await supabase.from('usuarios_preparados').select('*').order('creado_en',{ascending:true});setLoading(false);if(loadError)setError(`No se pudieron cargar los usuarios preparados: ${loadError.message}`);else{setRows(data||[]);setError('')}}
  useEffect(()=>{load()},[])
  const save=async e=>{e.preventDefault();setSaving(true);setError('');const payload={nombre:editing.nombre.trim(),correo:editing.correo.trim().toLowerCase(),area:editing.area,modulos:editing.modulos,observaciones:editing.observaciones.trim()};const result=editing.id?await supabase.from('usuarios_preparados').update({...payload,actualizado_en:new Date().toISOString()}).eq('id',editing.id):await supabase.from('usuarios_preparados').insert(payload);setSaving(false);if(result.error){setError(`No se pudo guardar: ${result.error.message}`);return}setEditing(null);await load()}
  const remove=async row=>{if(!window.confirm(`¿Quitar el borrador de ${row.nombre}? No afecta ninguna cuenta de acceso.`))return;const {error:removeError}=await supabase.from('usuarios_preparados').delete().eq('id',row.id);if(removeError)setError(`No se pudo quitar: ${removeError.message}`);else load()}
  if(profile.rol!=='administrador')return <div className="notice">Solo el administrador puede configurar usuarios.</div>
  return <div className="users-settings">
    <div className="users-intro"><div><span>CONFIGURACIÓN · USUARIOS</span><h2>Usuarios y permisos</h2><p>Prepare los accesos de planta, oficina y finca. Puede agregar tantos usuarios como necesite.</p></div><button className="primary" type="button" onClick={()=>{setError('');setEditing({...empty,modulos:[...empty.modulos]})}}><Plus size={18}/>Preparar usuario</button></div>
    <div className="users-summary"><div><ShieldCheck size={24}/><b>1</b><span>Administrador activo</span></div><div><Users size={24}/><b>{rows.length}</b><span>Usuarios preparados</span></div></div>
    <div className="notice">Estos son borradores para revisar permisos. Guardarlos no envía invitaciones ni permite iniciar sesión. Cada persona creará su propia contraseña cuando se activen las invitaciones.</div>
    {error&&<div className="formerror users-error">{error}</div>}
    <section className="panel users-list"><h3>Cuentas</h3><article className="users-person"><div className="users-person-main"><b>{profile.nombre}</b><span>Administrador · acceso completo</span></div><span className="users-status active">Activo</span></article>
      {loading?<p>Cargando usuarios…</p>:rows.length?rows.map(row=><article className="users-person" key={row.id}><div className="users-person-main"><b>{row.nombre}</b><span>{row.correo} · {title(row.area)} · {row.modulos.length} módulos</span></div><span className="users-status">Borrador</span><div className="users-actions"><button type="button" onClick={()=>{setError('');setEditing({...row,modulos:[...row.modulos]})}} aria-label={`Editar ${row.nombre}`}><Pencil size={16}/></button><button type="button" onClick={()=>remove(row)} aria-label={`Quitar ${row.nombre}`}><Trash2 size={16}/></button></div></article>):<p className="users-empty">Todavía no hay usuarios preparados. Agregue los nombres y correos cuando los tenga.</p>}
    </section>
    {editing&&<div className="modalwrap" role="presentation"><form className="modal users-modal" onSubmit={save}><div className="modalhead"><div><span>CONFIGURACIÓN</span><h2>{editing.id?'Editar usuario':'Preparar usuario'}</h2></div><button type="button" onClick={()=>setEditing(null)} aria-label="Cerrar"><X/></button></div><div className="users-form"><div className="users-fields"><label>Nombre<input required minLength="2" value={editing.nombre} onChange={e=>setEditing({...editing,nombre:e.target.value})} placeholder="Nombre y apellidos"/></label><label>Correo electrónico<input required type="email" value={editing.correo} onChange={e=>setEditing({...editing,correo:e.target.value})} placeholder="persona@empresa.com"/></label><label>Área<select value={editing.area} onChange={e=>setEditing({...editing,area:e.target.value,modulos:[...presets[e.target.value]]})}>{Object.keys(presets).map(area=><option key={area} value={area}>{title(area)}</option>)}</select></label><label>Nota opcional<input value={editing.observaciones} onChange={e=>setEditing({...editing,observaciones:e.target.value})} placeholder="Por ejemplo, encargado de turno"/></label></div><p className="users-hint">Seleccione los módulos que propone para esta persona. La activación requerirá verificar también los permisos de datos.</p><div className="users-groups">{groups.map(([group,modules])=><fieldset key={group}><legend>{group}</legend>{modules.map(module=><label key={module} className="users-check"><input type="checkbox" checked={editing.modulos.includes(module)} onChange={e=>setEditing({...editing,modulos:e.target.checked?[...editing.modulos,module]:editing.modulos.filter(x=>x!==module)})}/><span>{module}</span></label>)}</fieldset>)}</div></div><div className="modalactions"><button type="button" onClick={()=>setEditing(null)}>Cancelar</button><button className="primary" disabled={saving}>{saving?'Guardando…':'Guardar borrador'}</button></div></form></div>}
  </div>
}

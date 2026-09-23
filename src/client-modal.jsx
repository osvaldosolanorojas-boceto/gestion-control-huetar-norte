import React, {useState} from 'react'
import {X} from 'lucide-react'
import {supabase} from './supabase'

export default function ClientModal({client,close,onSaved}){
  const initialForm={nombre:'',razon_social:'',identificacion_fiscal:'',pais:'',ciudad:'',mercado:'Estados Unidos',direccion:'',puerto_llegada:'',contacto:'',contacto_cargo:'',telefono:'',whatsapp:'',correo:'',correo_facturacion:'',moneda_habitual:'USD',condiciones_pago:'',plazo_pago_dias:'',incoterm:'',direccion_facturacion:'',direccion_entrega:'',naviera:'',logo_url:'',observaciones:'',activo:true}
  const [form,setForm]=useState(()=>client?Object.fromEntries(Object.keys(initialForm).map(key=>[key,client[key]??initialForm[key]])):initialForm)
  const [saving,setSaving]=useState(false); const [error,setError]=useState('')
  const change=e=>setForm({...form,[e.target.name]:e.target.type==='checkbox'?e.target.checked:e.target.value})
  const save=async()=>{
    if(!form.nombre.trim()){setError('Escriba el nombre comercial del cliente.');return}
    if(!form.pais.trim()){setError('Escriba el país del cliente.');return}
    setSaving(true);setError('')
    const payload={...form,nombre:form.nombre.trim(),pais:form.pais.trim(),plazo_pago_dias:form.plazo_pago_dias?Number(form.plazo_pago_dias):null}
    Object.keys(payload).forEach(key=>{if(payload[key]==='')payload[key]=null})
    const result=client?await supabase.from('clientes').update(payload).eq('id',client.id).select('id,nombre').single():await supabase.from('clientes').insert(payload).select('id,nombre').single()
    const {error:saveError}=result
    setSaving(false)
    if(saveError){setError(`No se pudo guardar: ${saveError.message}`);return}
    onSaved(result.data)
  }
  return <div className="modalwrap"><div className="modal realform clientform"><div className="modalhead"><div><span>{client?'EDITAR REGISTRO':'NUEVO REGISTRO'}</span><h2>Ficha del cliente</h2></div><button onClick={close}><X/></button></div>
    <div className="formsection"><h3>Identificación y destino</h3><div className="formgrid">
      <label>Nombre comercial *<input name="nombre" value={form.nombre} onChange={change} placeholder="Ejemplo: J&C Tropicals"/></label><label>Razón social<input name="razon_social" value={form.razon_social} onChange={change}/></label>
      <label>Identificación fiscal<input name="identificacion_fiscal" value={form.identificacion_fiscal} onChange={change}/></label><label>Mercado<select name="mercado" value={form.mercado} onChange={change}><option>Estados Unidos</option><option>Europa</option><option>Canadá</option><option>Costa Rica</option><option>Otro</option></select></label>
      <label>País de destino *<input name="pais" value={form.pais} onChange={change}/></label><label>Ciudad<input name="ciudad" value={form.ciudad} onChange={change}/></label>
      <label>Puerto de llegada<input name="puerto_llegada" value={form.puerto_llegada} onChange={change} placeholder="Puerto habitual"/></label><label>Incoterm<input name="incoterm" value={form.incoterm} onChange={change} placeholder="FOB, CIF, DDP…"/></label>
      <label className="wide">Dirección completa<textarea name="direccion" value={form.direccion} onChange={change} rows="2"/></label>
    </div></div>
    <div className="formsection"><h3>Contacto y facturación</h3><div className="formgrid">
      <label>Persona de contacto<input name="contacto" value={form.contacto} onChange={change}/></label><label>Cargo<input name="contacto_cargo" value={form.contacto_cargo} onChange={change}/></label>
      <label>Teléfono<input name="telefono" type="tel" value={form.telefono} onChange={change}/></label><label>WhatsApp<input name="whatsapp" type="tel" value={form.whatsapp} onChange={change}/></label>
      <label>Correo general<input name="correo" type="email" value={form.correo} onChange={change}/></label><label>Correo de facturación<input name="correo_facturacion" type="email" value={form.correo_facturacion} onChange={change}/></label>
      <label>Moneda habitual<select name="moneda_habitual" value={form.moneda_habitual} onChange={change}><option value="USD">Dólares (USD)</option><option value="CRC">Colones (CRC)</option><option value="EUR">Euros (EUR)</option></select></label><label>Plazo de pago (días)<input name="plazo_pago_dias" type="number" min="0" step="1" value={form.plazo_pago_dias} onChange={change}/></label>
      <label className="wide">Condiciones de pago<input name="condiciones_pago" value={form.condiciones_pago} onChange={change} placeholder="Crédito, transferencia, anticipo…"/></label>
      <label className="wide">Dirección de facturación<textarea name="direccion_facturacion" value={form.direccion_facturacion} onChange={change} rows="2"/></label><label className="wide">Dirección de entrega<textarea name="direccion_entrega" value={form.direccion_entrega} onChange={change} rows="2"/></label>
    </div></div>
    <div className="formsection"><h3>Logística y datos adicionales</h3><div className="formgrid">
      <label>Naviera o transportista habitual<input name="naviera" value={form.naviera} onChange={change}/></label><label>Enlace del logo<input name="logo_url" type="url" value={form.logo_url} onChange={change} placeholder="https://…"/></label>
      <label className="wide">Observaciones<textarea name="observaciones" value={form.observaciones} onChange={change} rows="3" placeholder="Información adicional…"/></label><label className="checklabel"><input name="activo" type="checkbox" checked={form.activo} onChange={change}/> Cliente activo</label>
    </div></div>
    {error&&<div className="formerror">{error}</div>}<div className="modalactions"><button onClick={close} disabled={saving}>Cancelar</button><button className="primary" onClick={save} disabled={saving}>{saving?'Guardando…':client?'Guardar cambios':'Guardar cliente'}</button></div>
  </div></div>
}


import React,{useEffect,useState} from 'react'
import {Plus,X} from 'lucide-react'
import {supabase} from './supabase'

const categories=['Parafina','Cera','Esquineros','Papel','Guantes','Fleje','Grapas','Grapas para cartón','Cloro','Etiquetas','Otros']
const empty=()=>({nombre:'',categoria:'Otros',unidad:'unidades',minimo:'0',activo:true})
const fmt=value=>Number(value||0).toLocaleString('es-CR',{maximumFractionDigits:3})
export default function SupplyInventory(){
  const [items,setItems]=useState([]),[moves,setMoves]=useState([]),[orders,setOrders]=useState([]),[editing,setEditing]=useState(null),[moving,setMoving]=useState(null)
  const [form,setForm]=useState(empty),[entry,setEntry]=useState({tipo:'entrada',cantidad:'',referencia:'',observaciones:''}),[saving,setSaving]=useState(false),[error,setError]=useState(''),[filter,setFilter]=useState('')
  const reload=async()=>{
    const [a,b,c]=await Promise.all([supabase.from('insumos').select('*').order('nombre'),supabase.from('movimientos_insumos').select('*').order('creado_en',{ascending:false}).limit(150),supabase.from('ordenes_venta').select('codigo').order('fecha',{ascending:false}).limit(40)])
    if(a.error||b.error){setError(`No se pudo cargar el inventario: ${(a.error||b.error).message}`);return}
    setItems(a.data||[]);setMoves(b.data||[]);setOrders(c.data||[])
  }
  useEffect(()=>{reload()},[])
  const open=item=>{setEditing(item?.id||'new');setForm(item?{...item,minimo:String(item.minimo)}:empty());setError('')}
  const save=async()=>{
    const minimo=Number(String(form.minimo).replace(',','.'))
    if(!form.nombre.trim()||!form.unidad.trim()||!Number.isFinite(minimo)||minimo<0||Math.round(minimo*1000)!==minimo*1000){setError('Escriba nombre, unidad y un mínimo válido (hasta tres decimales).');return}
    setSaving(true);setError('')
    const payload={nombre:form.nombre.trim(),categoria:form.categoria.trim()||'Otros',unidad:form.unidad.trim(),minimo,activo:form.activo}
    const {error:e}=editing==='new'?await supabase.from('insumos').insert(payload):await supabase.from('insumos').update(payload).eq('id',editing)
    setSaving(false);if(e){setError(`No se pudo guardar: ${e.message}`);return}setEditing(null);reload()
  }
  const record=async()=>{
    const cantidad=Number(String(entry.cantidad).replace(',','.'))
    if(!Number.isFinite(cantidad)||cantidad<=0||Math.round(cantidad*1000)!==cantidad*1000){setError('Escriba una cantidad positiva con hasta tres decimales.');return}
    setSaving(true);setError('')
    const {error:e}=await supabase.rpc('registrar_movimiento_insumo',{p_insumo_id:moving.id,p_tipo:entry.tipo,p_cantidad:cantidad,p_referencia:entry.referencia.trim()||null,p_observaciones:entry.observaciones.trim()||null})
    setSaving(false);if(e){setError(`No se pudo registrar: ${e.message}`);return}setMoving(null);reload()
  }
  const close=()=>{setEditing(null);setMoving(null);setError('')}
  return <><div className="modulebar"><div><p>Registre compras y consumos de materiales. Cada movimiento actualiza la existencia y conserva su referencia.</p></div><button className="primary" onClick={()=>open(null)}><Plus size={18}/>Agregar insumo</button></div>
    <div className="supply-tools"><label>Buscar insumo<input value={filter} onChange={e=>setFilter(e.target.value)} placeholder="Parafina, etiquetas, cloro…"/></label><span>{items.length} insumos registrados</span></div>
    <div className="supply-grid">{items.filter(x=>`${x.nombre} ${x.categoria}`.toLowerCase().includes(filter.toLowerCase())).map(item=><article key={item.id} className="supply-card"><div><small>{item.categoria}{!item.activo?' · Inactivo':''}</small><h3>{item.nombre}</h3><strong className={Number(item.existencia)<=Number(item.minimo)?'low':''}>{fmt(item.existencia)} {item.unidad}</strong><p>Mínimo: {fmt(item.minimo)} {item.unidad}{Number(item.existencia)<=Number(item.minimo)?' · Reponer':''}</p></div><div className="supply-actions"><button disabled={!item.activo} onClick={()=>{setMoving(item);setEntry({tipo:'entrada',cantidad:'',referencia:'',observaciones:''});setError('')}}>Registrar movimiento</button><button onClick={()=>open(item)}>Editar</button></div><details><summary>Últimos movimientos</summary>{moves.filter(m=>m.insumo_id===item.id).slice(0,8).map(m=><p key={m.id}>{new Date(m.creado_en).toLocaleDateString('es-CR')} · {m.tipo.replace('_',' ')} {m.tipo.includes('salida')||m.tipo==='consumo'?'-':'+'}{fmt(m.cantidad)} {item.unidad}{m.referencia?` · ${m.referencia}`:''}</p>)}</details></article>)}</div>
    {!items.length&&<div className="empty"><h3>Inventario de insumos vacío</h3><p>Agregue un artículo y después registre su primera entrada.</p></div>}
    {(editing||moving)&&<div className="modalwrap"><div className="modal carton-modal supply-modal"><div className="modalhead"><div><span>{editing?'CATÁLOGO DE INSUMOS':'MOVIMIENTO DE INVENTARIO'}</span><h2>{editing?(editing==='new'?'Nuevo insumo':form.nombre):moving.nombre}</h2></div><button onClick={close} aria-label="Cerrar"><X/></button></div>
    {editing?<div className="formgrid"><label>Nombre *<input value={form.nombre} onChange={e=>setForm({...form,nombre:e.target.value})} placeholder="Ejemplo: Parafina"/></label><label>Categoría<select value={categories.includes(form.categoria)?form.categoria:'Otra categoría'} onChange={e=>setForm({...form,categoria:e.target.value==='Otra categoría'?'':e.target.value})}>{categories.map(c=><option key={c}>{c}</option>)}<option>Otra categoría</option></select>{!categories.includes(form.categoria)&&<input value={form.categoria} onChange={e=>setForm({...form,categoria:e.target.value})} placeholder="Escriba la categoría"/>}</label><label>Unidad de control *<input value={form.unidad} onChange={e=>setForm({...form,unidad:e.target.value})} placeholder="kg, litros, rollos, unidades…"/></label><label>Mínimo para alerta<input type="number" min="0" step="0.001" inputMode="decimal" value={form.minimo} onChange={e=>setForm({...form,minimo:e.target.value})}/></label><label className="checklabel"><input type="checkbox" checked={form.activo} onChange={e=>setForm({...form,activo:e.target.checked})}/>Activo</label></div>:<div className="formgrid"><label>Tipo<select value={entry.tipo} onChange={e=>setEntry({...entry,tipo:e.target.value})}><option value="entrada">Entrada por compra o recepción</option><option value="consumo">Consumo en planta</option><option value="ajuste_entrada">Ajuste: sobrante</option><option value="ajuste_salida">Ajuste: faltante</option></select></label><label>Cantidad ({moving.unidad}) *<input type="number" min="0.001" step="0.001" inputMode="decimal" value={entry.cantidad} onChange={e=>setEntry({...entry,cantidad:e.target.value})}/></label><label className="wide">Referencia de pedido, compra o factura<input list="supply-orders" value={entry.referencia} onChange={e=>setEntry({...entry,referencia:e.target.value})} placeholder="Número de orden o factura"/><datalist id="supply-orders">{orders.map(o=><option key={o.codigo} value={o.codigo}/>)}</datalist></label><label className="wide">Observaciones<input value={entry.observaciones} onChange={e=>setEntry({...entry,observaciones:e.target.value})}/></label><p className="wide">Existencia actual: <b>{fmt(moving.existencia)} {moving.unidad}</b></p></div>}
    {error&&<div className="formerror">{error}</div>}<div className="modalactions"><button disabled={saving} onClick={close}>Cancelar</button><button className="primary" disabled={saving} onClick={editing?save:record}>{saving?'Guardando…':editing?'Guardar insumo':'Registrar movimiento'}</button></div></div></div>}
    {!editing&&!moving&&error&&<div className="formerror">{error}</div>}</>
}

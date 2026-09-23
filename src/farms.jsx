import React,{useEffect,useMemo,useState} from 'react'
import {Plus} from 'lucide-react'
import {supabase} from './supabase'
import {cash} from './finance'

const year=new Date().getFullYear()
const blankCost=()=>({lote_id:'',fecha:new Date().toLocaleDateString('en-CA'),categoria:'Planilla',descripcion:'',monto:''})

export default function Farms(){
  const [farms,setFarms]=useState([]),[lots,setLots]=useState([]),[orders,setOrders]=useState([]),[payables,setPayables]=useState([]),[costs,setCosts]=useState([])
  const [yearFilter,setYearFilter]=useState(year),[farmName,setFarmName]=useState(''),[lotForm,setLotForm]=useState({finca_id:'',anio:year,nombre:'',producto:''}),[costForm,setCostForm]=useState(blankCost)
  const [error,setError]=useState(''),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false)
  const reload=async()=>{
    const [a,b,c,d,e]=await Promise.all([supabase.from('fincas').select('*').order('nombre'),supabase.from('lotes_finca').select('*').order('anio',{ascending:false}).order('nombre'),supabase.from('ordenes_compra').select('id,codigo,fecha,producto,finca_lote_id,proveedor_id,productor_nombre').not('finca_lote_id','is',null).neq('estado','Anulada').order('fecha'),supabase.from('cxp_operativa').select('origen_id,monto,aplicado'),supabase.from('costos_finca').select('*').order('fecha')])
    setLoading(false)
    if(a.error||b.error||c.error||d.error||e.error){setError(`No se pudo cargar el control de fincas: ${(a.error||b.error||c.error||d.error||e.error).message}`);return}
    setError('');setFarms(a.data||[]);setLots(b.data||[]);setOrders(c.data||[]);setPayables(d.data||[]);setCosts(e.data||[])
  }
  useEffect(()=>{reload()},[])
  const selected=lots.filter(l=>String(l.anio)===String(yearFilter))
  const payableById=useMemo(()=>Object.fromEntries(payables.map(p=>[p.origen_id,p])),[payables])
  const saveFarm=async()=>{
    const nombre=farmName.trim();if(!nombre){setError('Escriba el nombre de la finca.');return}
    setSaving(true);const {data,error:e}=await supabase.from('fincas').insert({nombre}).select('id').single();setSaving(false)
    if(e){setError(`No se pudo guardar la finca: ${e.message}`);return}
    setFarmName('');setLotForm(f=>({...f,finca_id:data.id}));reload()
  }
  const saveLot=async()=>{
    if(!lotForm.finca_id||!lotForm.nombre.trim()||!Number.isInteger(Number(lotForm.anio))||Number(lotForm.anio)<2000||Number(lotForm.anio)>2100){setError('Seleccione finca, año y nombre del lote.');return}
    setSaving(true);const {error:e}=await supabase.from('lotes_finca').insert({finca_id:lotForm.finca_id,anio:Number(lotForm.anio),nombre:lotForm.nombre.trim(),producto:lotForm.producto.trim()||null});setSaving(false)
    if(e){setError(`No se pudo guardar el lote: ${e.message}`);return}
    setYearFilter(Number(lotForm.anio));setLotForm(f=>({...f,nombre:'',producto:''}));reload()
  }
  const saveCost=async()=>{
    const amount=Number(costForm.monto);if(!costForm.lote_id||!costForm.fecha||!costForm.categoria.trim()||!Number.isFinite(amount)||amount<=0){setError('Complete lote, fecha, tipo de gasto y monto positivo.');return}
    setSaving(true);const {error:e}=await supabase.from('costos_finca').insert({lote_id:costForm.lote_id,fecha:costForm.fecha,categoria:costForm.categoria.trim(),descripcion:costForm.descripcion.trim()||null,monto:amount});setSaving(false)
    if(e){setError(`No se pudo guardar el costo: ${e.message}`);return}
    setCostForm(f=>({...blankCost(),lote_id:f.lote_id}));reload()
  }
  return <><div className="modulebar"><p>Producción propia por finca, año y lote. Las compras de Agro Solano se enlazan desde Órdenes de compra; los pagos se toman de Bancos.</p></div>{error&&<div className="formerror">{error}</div>}
    <section className="panel farm-panel"><h3>Fincas y lotes</h3><div className="formgrid"><label>Nueva finca<input value={farmName} onChange={e=>setFarmName(e.target.value)} placeholder="Nombre de la finca"/></label><button type="button" onClick={saveFarm} disabled={saving}><Plus size={16}/>Guardar finca</button></div><div className="formgrid"><label>Finca<select value={lotForm.finca_id} onChange={e=>setLotForm({...lotForm,finca_id:e.target.value})}><option value="">Seleccione la finca</option>{farms.map(f=><option key={f.id} value={f.id}>{f.nombre}</option>)}</select></label><label>Año<input type="number" min="2000" max="2100" value={lotForm.anio} onChange={e=>setLotForm({...lotForm,anio:e.target.value})}/></label><label>Nombre o código del lote<input value={lotForm.nombre} onChange={e=>setLotForm({...lotForm,nombre:e.target.value})} placeholder="Ejemplo: Lote 1"/></label><label>Producto previsto<input value={lotForm.producto} onChange={e=>setLotForm({...lotForm,producto:e.target.value})} placeholder="Opcional"/></label><button type="button" className="primary" onClick={saveLot} disabled={saving}>Guardar lote</button></div></section>
    <section className="panel farm-panel"><h3>Registrar costo de finca</h3><p>Estos son costos operativos por lote en colones; no crean un movimiento bancario.</p><div className="formgrid"><label>Lote<select value={costForm.lote_id} onChange={e=>setCostForm({...costForm,lote_id:e.target.value})}><option value="">Seleccione un lote</option>{lots.map(l=><option key={l.id} value={l.id}>{farms.find(f=>f.id===l.finca_id)?.nombre} · {l.anio} · {l.nombre}</option>)}</select></label><label>Fecha<input type="date" value={costForm.fecha} onChange={e=>setCostForm({...costForm,fecha:e.target.value})}/></label><label>Tipo de costo<select value={costForm.categoria} onChange={e=>setCostForm({...costForm,categoria:e.target.value})}>{['Planilla','Insumos','Maquinaria','Combustible','Flete','Servicios','Otro'].map(c=><option key={c}>{c}</option>)}</select></label><label>Monto (₡)<input type="number" min="0.01" step="0.01" inputMode="decimal" value={costForm.monto} onChange={e=>setCostForm({...costForm,monto:e.target.value})}/></label><label className="wide">Detalle<input value={costForm.descripcion} onChange={e=>setCostForm({...costForm,descripcion:e.target.value})}/></label><button type="button" className="primary" disabled={saving} onClick={saveCost}>Guardar costo</button></div></section>
    <section className="panel farm-panel"><div className="panelhead"><div><h3>Resultado por finca y lote</h3><p>Valor de producto facturado a la exportadora frente a costos registrados</p></div><label>Año<select value={yearFilter} onChange={e=>setYearFilter(e.target.value)}>{[...new Set([year,...lots.map(l=>l.anio)])].sort((a,b)=>b-a).map(y=><option key={y} value={y}>{y}</option>)}</select></label></div>{loading?<p>Cargando fincas…</p>:selected.length?selected.map(l=>{const linked=orders.filter(o=>o.finca_lote_id===l.id),expenses=costs.filter(c=>c.lote_id===l.id),value=linked.reduce((s,o)=>s+Number(payableById[o.id]?.monto||0),0),paid=linked.reduce((s,o)=>s+Number(payableById[o.id]?.aplicado||0),0),spent=expenses.reduce((s,c)=>s+Number(c.monto||0),0),pending=linked.filter(o=>!payableById[o.id]);return <article className="farm-lot" key={l.id}><h4>{farms.find(f=>f.id===l.finca_id)?.nombre} · {l.anio} · {l.nombre}{l.producto?` · ${l.producto}`:''}</h4><div className="farm-metrics"><span>Producción reconocida <b>{cash(value)}</b></span><span>Pagado por exportadora <b>{cash(paid)}</b></span><span>Costos registrados <b>{cash(spent)}</b></span><span>Resultado provisional <b>{cash(value-spent)}</b></span></div>{pending.length>0&&<p>{pending.length} {pending.length===1?'compra pendiente de liquidación':'compras pendientes de liquidación'}; su producción aún no figura en el valor reconocido.</p>}{linked.map(o=><div className="farm-line" key={o.id}><span>{o.fecha} · {o.codigo} · {o.producto}</span><b>{payableById[o.id]?cash(payableById[o.id].monto):'Pendiente'} · pagado {cash(payableById[o.id]?.aplicado||0)}</b></div>)}{expenses.map(c=><div className="farm-line" key={c.id}><span>{c.fecha} · {c.categoria}{c.descripcion?` · ${c.descripcion}`:''}</span><b>− {cash(c.monto)}</b></div>)}</article>}):<p>No hay lotes para este año. Cree una finca y un lote para comenzar.</p>}<p>El resultado es provisional hasta registrar todas las entregas, liquidaciones y costos. El adelanto se controla por separado en Finanzas.</p></section></>
}

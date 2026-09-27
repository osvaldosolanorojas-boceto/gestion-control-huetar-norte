import React,{useEffect,useState} from 'react'
import {Plus,X} from 'lucide-react'
import {supabase} from './supabase'
import {addDays,costaRicaToday,isoWeek,sundayOf} from './weekly-model'
import {periodShare,sumCost} from './cost-model'

const products=['Yuca','Ñampí','Cabeza de ñampí','Camote','Caña de azúcar','Jengibre','Cúrcuma','Malanga lila','Malanga blanca','Malanga taro','Papa china','Ñame','Chayote','Ayote']
const names={gas:'Gas de hornos',electricidad:'Electricidad',agua:'Agua',carton:'Cartón',empaque:'Otros materiales de empaque',tratamiento:'Parafina y cera',limpieza:'Limpieza y cloro',proteccion:'Protección personal',mantenimiento:'Mantenimiento y repuestos',carga:'Carga y descarga',puerto:'Puerto y contenedor',documentacion:'Documentación de exportación',alquiler:'Alquiler',depreciacion:'Equipos y depreciación',otros:'Otro costo'}
const lossNames={tierra:'Tierra y suciedad',humedad:'Humedad y secado',pelado:'Pelado y recorte',proceso:'Merma de proceso',danio:'Producto dañado',desperdicio:'Desperdicio',otra:'Otra diferencia'}
const money=(n,c)=>new Intl.NumberFormat('es-CR',{style:'currency',currency:c,maximumFractionDigits:2}).format(Number(n)||0)
const emptyCost=()=>({categoria:'gas',concepto:'',periodo_inicio:costaRicaToday(),periodo_fin:costaRicaToday(),fecha_factura:'',moneda:'CRC',monto:'',cantidad:'',unidad:'',producto:'',linea_proceso:'',orden_venta_id:'',boleta_id:'',referencia:'',observaciones:''})
const emptyLoss=()=>({boleta_id:'',categoria:'tierra',kilos:'',observaciones:''})
const emptyStock=()=>({insumo_id:'',cantidad:'',fecha:costaRicaToday(),moneda:'CRC',monto:'',producto:'',linea_proceso:'',boleta_id:'',orden_venta_id:'',referencia:'',observaciones:''})
const numeric=v=>v===''?null:Number(v)
const validMoney=v=>Number.isFinite(Number(v))&&Number(v)>0&&Math.abs(Math.round(Number(v)*100)-Number(v)*100)<0.000001

export default function CostControl(){
  const [week,setWeek]=useState(()=>sundayOf(costaRicaToday())),end=addDays(week,6),label=isoWeek(addDays(week,1))
  const [costs,setCosts]=useState([]),[losses,setLosses]=useState([]),[receipts,setReceipts]=useState([]),[yields,setYields]=useState([]),[orders,setOrders]=useState([]),[supplies,setSupplies]=useState([])
  const [kind,setKind]=useState(''),[editing,setEditing]=useState(null),[cost,setCost]=useState(emptyCost),[loss,setLoss]=useState(emptyLoss),[stock,setStock]=useState(emptyStock)
  const [error,setError]=useState(''),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false)
  const reload=async()=>{
    setLoading(true);setError('')
    const result=await Promise.all([
      supabase.from('costos_produccion').select('*').lte('periodo_inicio',end).gte('periodo_fin',week).is('anulado_en',null).order('periodo_inicio',{ascending:false}).limit(1000),
      supabase.from('boletas_entrada').select('id,codigo,producto,fecha_labor,kg_estimados,linea_proceso').gte('fecha_labor',week).lte('fecha_labor',end).order('fecha_labor',{ascending:false}).limit(1000),
      supabase.from('ordenes_venta').select('id,codigo,contenedor').order('creado_en',{ascending:false}).limit(500),
      supabase.from('insumos').select('id,nombre,categoria,unidad,existencia,activo').eq('activo',true).order('nombre').limit(1000)
    ])
    const failure=result.find(r=>r.error)?.error
    if(failure){setLoading(false);setError(`No se pudieron cargar costos: ${failure.message}`);return}
    const r=result[1].data||[],ids=r.map(x=>x.id)
    const extra=ids.length?await Promise.all([
      supabase.from('boleta_rendimientos').select('boleta_id,calidad,kg_resultado').in('boleta_id',ids).limit(2000),
      supabase.from('mermas_produccion').select('*').in('boleta_id',ids).is('anulado_en',null).limit(1000)
    ]):[{data:[]},{data:[]}]
    setLoading(false)
    if(extra.some(x=>x.error)){setError(`No se pudieron cargar mermas: ${extra.find(x=>x.error).error.message}`);return}
    if(result[0].data.length===1000||r.length===1000||extra[0].data.length===2000||extra[1].data.length===1000){setError('Hay más movimientos que el límite de consulta. No se muestran totales parciales.');return}
    setCosts(result[0].data);setReceipts(r);setOrders(result[2].data||[]);setSupplies(result[3].data||[]);setYields(extra[0].data);setLosses(extra[1].data)
  }
  useEffect(()=>{reload()},[week])
  const start=k=>{setKind(k);setEditing(null);setError('');setCost(emptyCost());setLoss(emptyLoss());setStock(emptyStock())}
  const editCost=row=>{setKind('cost');setEditing(row.id);setError('');setCost(Object.fromEntries(Object.keys(emptyCost()).map(key=>[key,String(row[key]??'')])))}
  const saveCost=async()=>{
    if(!cost.concepto.trim()||!validMoney(cost.monto)||!cost.periodo_inicio||!cost.periodo_fin||cost.periodo_fin<cost.periodo_inicio||cost.periodo_fin>addDays(cost.periodo_inicio,366)){
      setError('Complete concepto, monto y un período válido de hasta un año.');return
    }
    if(cost.cantidad!==''&&(!Number.isFinite(Number(cost.cantidad))||Number(cost.cantidad)<=0||!cost.unidad.trim())||cost.cantidad===''&&cost.unidad.trim()){
      setError('Si anota cantidad, indique una unidad y un número positivo.');return
    }
    const payload={...cost,concepto:cost.concepto.trim(),monto:Number(cost.monto),cantidad:numeric(cost.cantidad),unidad:cost.unidad.trim()||null,fecha_factura:cost.fecha_factura||null,producto:cost.producto||null,linea_proceso:numeric(cost.linea_proceso),orden_venta_id:cost.orden_venta_id||null,boleta_id:cost.boleta_id||null,referencia:cost.referencia.trim()||null,observaciones:cost.observaciones.trim()||null}
    setSaving(true);setError('')
    const result=editing?await supabase.from('costos_produccion').update(payload).eq('id',editing).select('id').single():await supabase.from('costos_produccion').insert(payload).select('id').single()
    setSaving(false)
    if(result.error){setError(result.error.message);return}setKind('');reload()
  }
  const saveStock=async()=>{
    const selected=supplies.find(x=>x.id===stock.insumo_id)
    if(!selected||!stock.fecha||!validMoney(stock.monto)||!Number.isFinite(Number(stock.cantidad))||Number(stock.cantidad)<=0||Math.abs(Math.round(Number(stock.cantidad)*1000)-Number(stock.cantidad)*1000)>0.000001||Number(stock.cantidad)>Number(selected.existencia)){
      setError('Seleccione un insumo y complete fecha, cantidad disponible y costo del consumo.');return
    }
    setSaving(true);setError('')
    const {error:e}=await supabase.rpc('consumir_insumo_costeado',{p_insumo_id:stock.insumo_id,p_cantidad:Number(stock.cantidad),p_fecha:stock.fecha,p_moneda:stock.moneda,p_monto:Number(stock.monto),p_producto:stock.producto||null,p_linea:numeric(stock.linea_proceso),p_boleta_id:stock.boleta_id||null,p_orden_venta_id:stock.orden_venta_id||null,p_referencia:stock.referencia.trim()||null,p_observaciones:stock.observaciones.trim()||null})
    setSaving(false);if(e){setError(e.message);return}setKind('');reload()
  }
  const saveLoss=async()=>{
    const receipt=receipts.find(x=>x.id===loss.boleta_id),qty=Number(loss.kilos)
    if(!receipt||!Number.isFinite(qty)||qty<=0||Math.abs(Math.round(qty*1000)-qty*1000)>0.000001){setError('Seleccione una boleta y una cantidad válida en kilos.');return}
    const output=yields.filter(x=>x.boleta_id===receipt.id).reduce((sum,x)=>sum+Number(x.kg_resultado||0),0)
    const known=losses.filter(x=>x.boleta_id===receipt.id).reduce((sum,x)=>sum+Number(x.kilos),0)
    if(Number(receipt.kg_estimados)>0&&qty+known>Math.max(0,Number(receipt.kg_estimados)-output)+0.001){setError('La merma registrada supera la diferencia estimada entre entrada y rendimientos. Revise la boleta.');return}
    setSaving(true);setError('')
    const {error:e}=await supabase.from('mermas_produccion').insert({boleta_id:receipt.id,categoria:loss.categoria,kilos:qty,observaciones:loss.observaciones.trim()||null})
    setSaving(false);if(e){setError(e.message);return}setKind('');reload()
  }
  const voidCost=async row=>{
    if(!window.confirm(`¿Anular «${row.concepto}»? Quedará conservado para auditoría.`))return
    const {error:e}=await supabase.from('costos_produccion').update({anulado_en:new Date().toISOString()}).eq('id',row.id).select('id').single()
    if(e){setError(e.message);return}reload()
  }
  const voidLoss=async row=>{
    if(!window.confirm('¿Anular esta clasificación de merma?'))return
    const {error:e}=await supabase.from('mermas_produccion').update({anulado_en:new Date().toISOString()}).eq('id',row.id).select('id').single()
    if(e){setError(e.message);return}reload()
  }
  const byCategory=Object.entries(names).map(([key,name])=>({key,name,crc:sumCost(costs.filter(x=>x.categoria===key),week,end,'CRC'),usd:sumCost(costs.filter(x=>x.categoria===key),week,end,'USD')})).filter(x=>x.crc||x.usd)
  const byProduct=[...new Set(costs.map(x=>x.producto||'Sin producto asignado'))].map(name=>({name,crc:sumCost(costs.filter(x=>(x.producto||'Sin producto asignado')===name),week,end,'CRC'),usd:sumCost(costs.filter(x=>(x.producto||'Sin producto asignado')===name),week,end,'USD')}))
  return <>
    <div className="modulebar"><p>Registre los costos cuando se consumen. Gas y luz pueden cubrir varias semanas; el corte distribuye el monto entre las fechas indicadas.</p><div className="cost-buttons"><button className="primary" onClick={()=>start('cost')}><Plus size={17}/>Registrar costo</button><button onClick={()=>start('stock')}>Consumir insumo con costo</button><button onClick={()=>start('loss')}>Clasificar merma</button></div></div>
    <div className="weekly-nav"><button onClick={()=>setWeek(addDays(week,-7))}>← Semana anterior</button><label>Semana {label.week} · {label.year}<input type="date" value={week} onChange={e=>e.target.value&&setWeek(sundayOf(e.target.value))}/></label><span>Del {week} al {end}</span><button onClick={()=>setWeek(addDays(week,7))}>Semana siguiente →</button></div>
    {error&&!kind&&<div className="formerror" role="alert">{error}</div>}
    {loading?<div className="empty">Cargando costos…</div>:<>
      <div className="bank-note">Resumen de costos de producción registrados: <b>{money(sumCost(costs,week,end,'CRC'),'CRC')}</b> y <b>{money(sumCost(costs,week,end,'USD'),'USD')}</b>. Se asignan según los días del período. Los costos sin producto se muestran aparte; no se reparten automáticamente entre productos.</div>
      <div className="workers-panel"><h3>Costos por clasificación</h3>{byCategory.map(x=><article key={x.key}><div><b>{x.name}</b></div><strong>{x.crc?money(x.crc,'CRC'):''}{x.crc&&x.usd?' · ':''}{x.usd?money(x.usd,'USD'):''}</strong></article>)}{!byCategory.length&&<p>No hay costos clasificados para esta semana.</p>}</div>
      <div className="workers-panel"><h3>Costos por producto</h3>{byProduct.map(x=><article key={x.name}><div><b>{x.name}</b></div><strong>{x.crc?money(x.crc,'CRC'):''}{x.crc&&x.usd?' · ':''}{x.usd?money(x.usd,'USD'):''}</strong></article>)}{!byProduct.length&&<p>Asigne un producto al registrar un costo para ver su desglose.</p>}</div>
      <div className="workers-panel"><h3>Movimientos y períodos</h3>{costs.map(row=><article key={row.id}><div><b>{names[row.categoria]} · {row.concepto}</b><span>{row.periodo_inicio}{row.periodo_fin!==row.periodo_inicio?` al ${row.periodo_fin}`:''} · {row.producto||'Costo común'}{row.linea_proceso?` · Línea ${row.linea_proceso}`:''}{row.boleta_id?` · ${receipts.find(x=>x.id===row.boleta_id)?.codigo||'Boleta'}`:''}{row.orden_venta_id?` · ${orders.find(x=>x.id===row.orden_venta_id)?.codigo||'Pedido'}`:''}</span>{row.cantidad&&<small>{row.cantidad} {row.unidad}{row.referencia?` · ${row.referencia}`:''}</small>}</div><strong>{money(periodShare(row,week,end),row.moneda)} esta semana <small>de {money(row.monto,row.moneda)}</small></strong>{!row.movimiento_insumo_id&&<><button onClick={()=>editCost(row)}>Editar</button><button onClick={()=>voidCost(row)}>Anular</button></>}</article>)}{!costs.length&&<p>Aún no hay movimientos de costo en esta semana.</p>}</div>
      <div className="workers-panel"><h3>Entradas y mermas por boleta</h3>{receipts.map(row=>{const output=yields.filter(y=>y.boleta_id===row.id).reduce((n,y)=>n+Number(y.kg_resultado||0),0),classified=losses.filter(x=>x.boleta_id===row.id).reduce((n,x)=>n+Number(x.kilos||0),0),difference=Number(row.kg_estimados||0)-output;return <article key={row.id}><div><b>{row.codigo} · {row.producto}</b><span>Ingreso estimado {Number(row.kg_estimados||0).toLocaleString('es-CR')} kg · Salida registrada {output.toLocaleString('es-CR')} kg · Merma clasificada {classified.toLocaleString('es-CR')} kg</span></div><strong>{(difference-classified).toLocaleString('es-CR',{maximumFractionDigits:3})} kg sin clasificar</strong></article>})}{!receipts.length&&<p>No hay boletas con fecha de labor en esta semana.</p>}{losses.map(x=><article key={x.id}><div><b>{receipts.find(r=>r.id===x.boleta_id)?.codigo} · {lossNames[x.categoria]}</b><span>{x.observaciones||'Sin observaciones'}</span></div><strong>{Number(x.kilos).toLocaleString('es-CR')} kg</strong><button onClick={()=>voidLoss(x)}>Anular</button></article>)}</div>
    </>}
    {kind&&<div className="modalwrap"><div className="modal plant-form weekly-modal"><div className="modalhead"><div><span>CONTROL DE COSTOS</span><h2>{kind==='cost'?(editing?'Editar costo':'Registrar costo'):kind==='stock'?'Consumir insumo con costo':'Clasificar merma'}</h2></div><button onClick={()=>setKind('')} aria-label="Cerrar"><X/></button></div>
      {kind==='cost'?<div className="formgrid">
        <label>Clasificación<select value={cost.categoria} onChange={e=>setCost({...cost,categoria:e.target.value})}>{Object.entries(names).map(([key,name])=><option key={key} value={key}>{name}</option>)}</select></label><label>Concepto *<input value={cost.concepto} onChange={e=>setCost({...cost,concepto:e.target.value})} placeholder="Ejemplo: recarga de gas de horno 1"/></label>
        <label>Desde *<input type="date" value={cost.periodo_inicio} onChange={e=>setCost({...cost,periodo_inicio:e.target.value,periodo_fin:cost.periodo_fin<e.target.value?e.target.value:cost.periodo_fin})}/></label><label>Hasta *<input type="date" value={cost.periodo_fin} onChange={e=>setCost({...cost,periodo_fin:e.target.value})}/></label>
        <label>Moneda<select value={cost.moneda} onChange={e=>setCost({...cost,moneda:e.target.value})}><option>CRC</option><option>USD</option></select></label><label>Monto total *<input type="number" min="0.01" step="0.01" value={cost.monto} onChange={e=>setCost({...cost,monto:e.target.value})}/></label>
        <label>Cantidad (opcional)<input type="number" min="0.001" step="0.001" value={cost.cantidad} onChange={e=>setCost({...cost,cantidad:e.target.value})}/></label><label>Unidad<input value={cost.unidad} onChange={e=>setCost({...cost,unidad:e.target.value})} placeholder="litros, kWh, cartones…"/></label>
        <label>Producto<select value={cost.producto} onChange={e=>setCost({...cost,producto:e.target.value})}><option value="">Costo común / pendiente de asignar</option>{products.map(x=><option key={x}>{x}</option>)}</select></label><label>Línea / horno<select value={cost.linea_proceso} onChange={e=>setCost({...cost,linea_proceso:e.target.value})}><option value="">Toda la planta</option><option value="1">Línea 1</option><option value="2">Línea 2</option></select></label>
        <label>Boleta de entrada<select value={cost.boleta_id} onChange={e=>setCost({...cost,boleta_id:e.target.value})}><option value="">Ninguna / costo general</option>{receipts.map(x=><option key={x.id} value={x.id}>{x.codigo} · {x.producto}</option>)}</select></label><label>Pedido o contenedor<select value={cost.orden_venta_id} onChange={e=>setCost({...cost,orden_venta_id:e.target.value})}><option value="">Ninguno</option>{orders.map(x=><option key={x.id} value={x.id}>{x.codigo} · {x.contenedor||'Sin contenedor'}</option>)}</select></label>
        <label>Fecha de factura<input type="date" value={cost.fecha_factura} onChange={e=>setCost({...cost,fecha_factura:e.target.value})}/></label><label>Referencia / factura<input value={cost.referencia} onChange={e=>setCost({...cost,referencia:e.target.value})}/></label><label className="wide">Observaciones<input value={cost.observaciones} onChange={e=>setCost({...cost,observaciones:e.target.value})}/></label>
      </div>:kind==='stock'?<div className="formgrid">
        <label className="wide">Insumo *<select value={stock.insumo_id} onChange={e=>setStock({...stock,insumo_id:e.target.value})}><option value="">Seleccione un insumo existente</option>{supplies.map(x=><option key={x.id} value={x.id}>{x.nombre} · {x.existencia} {x.unidad} disponibles</option>)}</select></label>
        <label>Fecha de consumo<input type="date" value={stock.fecha} onChange={e=>setStock({...stock,fecha:e.target.value})}/></label><label>Cantidad consumida *<input type="number" min="0.001" step="0.001" value={stock.cantidad} onChange={e=>setStock({...stock,cantidad:e.target.value})}/></label>
        <label>Moneda<select value={stock.moneda} onChange={e=>setStock({...stock,moneda:e.target.value})}><option>CRC</option><option>USD</option></select></label><label>Costo total consumido *<input type="number" min="0.01" step="0.01" value={stock.monto} onChange={e=>setStock({...stock,monto:e.target.value})}/></label>
        <label>Producto<select value={stock.producto} onChange={e=>setStock({...stock,producto:e.target.value})}><option value="">Costo común</option>{products.map(x=><option key={x}>{x}</option>)}</select></label><label>Línea / horno<select value={stock.linea_proceso} onChange={e=>setStock({...stock,linea_proceso:e.target.value})}><option value="">Toda la planta</option><option value="1">Línea 1</option><option value="2">Línea 2</option></select></label>
        <label>Boleta<select value={stock.boleta_id} onChange={e=>setStock({...stock,boleta_id:e.target.value})}><option value="">Ninguna</option>{receipts.map(x=><option key={x.id} value={x.id}>{x.codigo}</option>)}</select></label><label>Pedido<select value={stock.orden_venta_id} onChange={e=>setStock({...stock,orden_venta_id:e.target.value})}><option value="">Ninguno</option>{orders.map(x=><option key={x.id} value={x.id}>{x.codigo}</option>)}</select></label>
        <label>Referencia<input value={stock.referencia} onChange={e=>setStock({...stock,referencia:e.target.value})}/></label><label>Observaciones<input value={stock.observaciones} onChange={e=>setStock({...stock,observaciones:e.target.value})}/></label>
        <p className="wide">Este movimiento resta unidades del inventario y registra su costo una sola vez. Indique el valor del material consumido, no el total de la compra si aún queda inventario.</p>
      </div>:<div className="formgrid">
        <label className="wide">Boleta *<select value={loss.boleta_id} onChange={e=>setLoss({...loss,boleta_id:e.target.value})}><option value="">Seleccione una boleta de esta semana</option>{receipts.map(x=><option key={x.id} value={x.id}>{x.codigo} · {x.producto}</option>)}</select></label>
        <label>Tipo de merma<select value={loss.categoria} onChange={e=>setLoss({...loss,categoria:e.target.value})}>{Object.entries(lossNames).map(([key,name])=><option key={key} value={key}>{name}</option>)}</select></label><label>Kilos *<input type="number" min="0.001" step="0.001" value={loss.kilos} onChange={e=>setLoss({...loss,kilos:e.target.value})}/></label>
        <label className="wide">Observaciones<input value={loss.observaciones} onChange={e=>setLoss({...loss,observaciones:e.target.value})}/></label>
        <p className="wide">Segundas y rechazos ya registrados en rendimientos son salidas de producto; clasifique aquí solo la diferencia restante de la boleta.</p>
      </div>}
      {error&&<div className="formerror" role="alert">{error}</div>}<div className="modalactions"><button onClick={()=>setKind('')} disabled={saving}>Cancelar</button><button className="primary" onClick={kind==='cost'?saveCost:kind==='stock'?saveStock:saveLoss} disabled={saving}>{saving?'Guardando…':'Guardar'}</button></div>
    </div></div>}
  </>
}

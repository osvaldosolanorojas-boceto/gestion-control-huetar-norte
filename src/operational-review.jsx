import React,{useEffect,useState} from 'react'
import {supabase} from './supabase'

export default function OperationalReview({go,refresh}){
  const [receipts,setReceipts]=useState([]),[orders,setOrders]=useState([]),[error,setError]=useState('')
  const [other,setOther]=useState({salary:0,attendance:0,cartons:0,banks:0})
  const [showAllReceipts,setShowAllReceipts]=useState(false),[showAllOrders,setShowAllOrders]=useState(false)
  useEffect(()=>{let active=true;(async()=>{
    const [b,r,o,w,c,a,m,k,bank,direct]=await Promise.all([
      supabase.from('boletas_entrada').select('id,codigo,fecha_labor,kg_estimados,cantidad_recipientes,observaciones,finalizada_en').order('creado_en',{ascending:false}).limit(1000),
      supabase.from('boleta_rendimientos').select('boleta_id,kg_resultado').limit(5000),
      supabase.from('ordenes_venta').select('id,codigo,fecha_salida,finalizada_en,estado').order('fecha_salida',{ascending:false}).limit(1000),
      supabase.from('trabajadores').select('id').eq('activo',true).limit(1000),
      supabase.from('condiciones_salariales').select('trabajador_id').limit(2000),
      supabase.from('asistencias_planta').select('id').not('salida','is',null).is('jornada_id',null).limit(1000),
      supabase.from('movimientos_cartones').select('id').eq('tipo','entrada').limit(1000),
      supabase.from('costos_cartones').select('movimiento_id,precio_unitario').not('movimiento_id','is',null).limit(1000),
      supabase.from('cuentas_bancarias').select('id').eq('saldo_simulado',true).limit(100),
      supabase.from('ventas_externas_boleta').select('boleta_id,cantidad,unidad,peso_saco_kg').limit(5000)
    ])
    if(!active)return
    const failure=[b,r,o,w,c,a,m,k,bank,direct].find(x=>x.error)
    if(failure){setError(failure.error.message);return}
    if([b,o,w,a,m,k].some(x=>x.data.length===1000)||r.data.length===5000||direct.data.length===5000||c.data.length===2000){setError('Hay más registros que el límite de revisión. No se muestra un resumen incompleto.');return}
    const sums={};for(const line of r.data)sums[line.boleta_id]=(sums[line.boleta_id]||0)+Number(line.kg_resultado||0)
    for(const sale of direct.data)sums[sale.boleta_id]=(sums[sale.boleta_id]||0)+Number(sale.cantidad||0)*(sale.unidad==='Sacos'?Number(sale.peso_saco_kg||0):46)
    setReceipts(b.data.map(item=>({...item,classified:sums[item.id]||0})))
    setOrders(o.data.filter(item=>!item.finalizada_en&&item.estado!=='Anulada'))
    const rated=new Set(c.data.map(x=>x.trabajador_id)),priced=new Set(k.data.filter(x=>Number(x.precio_unitario)>0).map(x=>x.movimiento_id))
    setOther({salary:w.data.filter(x=>!rated.has(x.id)).length,attendance:a.data.length,cartons:m.data.filter(x=>!priced.has(x.id)).length,banks:bank.data.length})
  })();return()=>{active=false}},[refresh])
  const exceptions=receipts.map(item=>{const input=Number(item.kg_estimados),output=item.classified,tolerance=Math.max(0,Number(item.cantidad_recipientes||0)),explained=Boolean(item.observaciones?.trim());return {...item,problem:!item.kg_estimados?'Sin peso estimado de entrada':output===0?'Sin clasificación':output-input>tolerance+0.01&&!explained?`Salida ${Math.round((output-input)*100)/100} kg sobre el estimado; explique la variación`:input-output>Math.max(20,input*0.02,tolerance)&&!explained?`Diferencia de ${Math.round((input-output)*100)/100} kg; registre merma o explique lluvia/raíz`:null}}).filter(item=>item.problem)
  return <section className="panel"><div className="panelhead"><div><h3>Pendientes para cerrar</h3><p>Revise diferencias de boletas y pedidos abiertos, de todas las semanas.</p></div></div>
    {error&&<p className="formerror" role="alert">No se pudo completar la revisión: {error}</p>}
    {!error&&<><p><b>{exceptions.length} boletas que requieren datos o explicación</b> · <b>{orders.length} pedidos abiertos</b>. El ingreso es estimado por muestra; se admite una variación de 1 kg por recipiente. Diferencias mayores explicadas no se señalan como error.</p>
    <div className="workers-panel"><h4>Boletas para revisar</h4>{exceptions.slice(0,showAllReceipts?undefined:12).map(item=><article key={item.id}><div><b>{item.codigo} · {item.problem}</b><span>{item.fecha_labor||'Sin fecha de labor'} · entrada {item.kg_estimados??'pendiente'} kg · clasificado {item.classified.toLocaleString('es-CR')} kg · {item.finalizada_en?'Finalizada previamente':'Pendiente'}</span></div><button type="button" onClick={()=>go('Boletas de entrada',item.codigo,Boolean(item.finalizada_en))}>Buscar boleta</button></article>)}{exceptions.length>12&&<button type="button" onClick={()=>setShowAllReceipts(v=>!v)}>{showAllReceipts?'Mostrar menos':`Ver las ${exceptions.length} boletas`}</button>}</div>
    <div className="workers-panel"><h4>Pedidos sin finalizar</h4>{orders.slice(0,showAllOrders?undefined:12).map(item=><article key={item.id}><div><b>{item.codigo}</b><span>Salida {item.fecha_salida||'sin fecha'} · pendiente de comprobar producción, cartones y cuenta por cobrar</span></div><button type="button" onClick={()=>go('Órdenes de venta',item.codigo)}>Buscar pedido</button></article>)}{orders.length>12&&<button type="button" onClick={()=>setShowAllOrders(v=>!v)}>{showAllOrders?'Mostrar menos':`Ver los ${orders.length} pedidos`}</button>}</div></>}
    {!error&&<div className="workers-panel"><h4>Datos necesarios para cerrar costos</h4>{[['Planilla de planta',other.salary,'colaboradores sin tarifa registrada'],['Planilla de planta',other.attendance,'salidas de asistencia pendientes de calcular'],['Inventario de cartones',other.cartons,'entradas de cartón sin costo registrado'],['Bancos',other.banks,'saldos iniciales de banco simulados']].filter(([,count])=>count>0).map(([section,count,label])=><article key={label}><div><b>{count} {label}</b><span>Abra el módulo para completar o reemplazar el dato de prueba.</span></div><button type="button" onClick={()=>go(section)}>Completar</button></article>)}</div>}
  </section>
}

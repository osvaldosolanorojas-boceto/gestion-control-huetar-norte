import React,{useEffect,useState} from 'react'
import {supabase} from './supabase'
import {loadWeeklyRecords} from './weekly-data'
import {weeklyTotals,weeklyResult,isoWeek} from './weekly-model'
import {cash} from './finance'

export default function WeekProfit({start,end,refresh,go}){
 const [data,setData]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(true)
 useEffect(()=>{let active=true;setLoading(true);setError('');const load=async()=>{
  try{
   const [cut,moves]=await Promise.all([loadWeeklyRecords(start,end),supabase.from('movimientos_bancarios').select('tipo,monto,cuentas_bancarias(moneda,empresa)').gte('fecha',start).lte('fecha',end).limit(1000)])
   if(moves.error)throw new Error(moves.error.message)
   if(moves.data?.length>=1000)throw new Error('Hay demasiados movimientos para mostrar un total completo.')
   let rate=cut.rate
   if(!rate){const current=await supabase.functions.invoke('bccr-rate');if(!current.error&&Number(current.data?.compra)>0)rate={usd_crc:current.data.compra,fuente:`BCCR compra · ${current.data.fecha}`,simulado:false}}
   const flow={CRC:0,USD:0}
   for(const m of moves.data||[]){const a=m.cuentas_bancarias;if(a?.empresa==='exportadora'&&a.moneda in flow)flow[a.moneda]+=(m.tipo==='egreso'?-1:1)*Number(m.monto)}
   if(active)setData({...cut,rate,flow,results:weeklyResult(weeklyTotals(cut.records))})
  }catch(e){if(active)setError(`No se pudo calcular el resultado semanal: ${e.message}`)}finally{if(active)setLoading(false)}
 };load();return()=>{active=false}},[start,end,refresh])
 const week=isoWeek(start).week
 if(loading)return <section className="panel profit-panel"><h3>Ganancia o pérdida · semana {week}</h3><p>Calculando ventas, compras y gastos…</p></section>
 if(error)return <section className="panel profit-panel"><h3>Ganancia o pérdida · semana {week}</h3><div className="formerror">{error}</div></section>
 if(!data)return null
 const {results,records,rate}=data,value=rate?results.CRC.result+results.USD.result*Number(rate.usd_crc):null
 const pendingContainers=data.orders.filter(o=>o.finalizada_en&&o.fecha_salida>=start&&o.fecha_salida<=end&&records.sales.some(s=>s.id===o.id&&s.mercado!=='Costa Rica')&&!records.confirmedCosts.includes(o.id)).length
 const simulated=records.sales.some(s=>records.simulatedOrders.includes(s.id))||records.cartonCosts.some(c=>c.simulado)||rate?.simulado
 const sign=value===null?'neutral':value<0?'loss':value>0?'gain':'neutral'
 return <section className={`panel profit-panel ${sign}`}><div className="panelhead"><div><h3>Ganancia o pérdida · semana {week}</h3><p>Ventas finalizadas menos costo vendido, pérdidas y gastos; conserva el costo del saldo en planta</p></div><button type="button" onClick={()=>go('Corte semanal',start)}>Ver corte semanal</button></div><div className="profit-total"><span>{value===null?'Resultado por moneda':value<0?'Pérdida provisional':value>0?'Ganancia provisional':'Resultado provisional'}</span>{value!==null?<strong>{cash(value)}</strong>:<strong>Falta tipo de cambio para consolidar</strong>}<small>{rate?`USD convertido a ₡${Number(rate.usd_crc).toLocaleString('es-CR')} · ${rate.fuente}${simulated?' · Incluye datos de ejercicio':''}`:'Se mantienen colones y dólares separados.'}</small></div><div className="profit-currencies">{['CRC','USD'].map(currency=><article key={currency}><h4>{currency==='CRC'?'Colones':'Dólares'}</h4><p><span>Ventas netas</span><b>{cash(results[currency].income,currency)}</b></p><p><span>Costo vendido, pérdidas y gastos</span><b>{cash(results[currency].expense,currency)}</b></p><p className={results[currency].result<0?'result-loss':'result-gain'}><span>Resultado</span><b>{cash(results[currency].result,currency)}</b></p></article>)}</div><div className="profit-flow"><b>Inventario de arrastre · costo de compra y reproceso</b><span>Inicio: {cash(records.inventory?.opening||0)} · Cierre: {cash(records.inventory?.closing||0)}</span><small>El saldo pendiente conserva su costo. El reproceso no cambia la cuenta por pagar del agricultor.</small></div><div className="profit-flow"><b>Movimiento neto de bancos + efectivo en la semana</b><span>{cash(data.flow.CRC)} · {cash(data.flow.USD,'USD')}</span><small>Cobros menos pagos registrados. Se muestra como movimiento de dinero y no se suma otra vez a la ganancia.</small></div><p className="profit-note">Resultado operativo provisional según lo registrado.{records.cartonMissing.length>0?` Falta resolver el costo de cartón en ${records.cartonMissing.length} línea(s).`:''}{pendingContainers?` Gastos de ${pendingContainers} contenedor(es) pendientes de revisión.`:''}{records.chronology.length?' Hay boletas con fecha posterior a la salida.':''} Los gastos no registrados todavía no están incluidos.</p></section>
}

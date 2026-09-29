export function costaRicaToday(date=new Date()){
  const parts=Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:'America/Costa_Rica',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date).filter(x=>x.type!=='literal').map(x=>[x.type,x.value]))
  return `${parts.year}-${parts.month}-${parts.day}`
}
export function mondayOf(value){
  const date=new Date(`${value}T12:00:00Z`)
  date.setUTCDate(date.getUTCDate()-(date.getUTCDay()+6)%7)
  return date.toISOString().slice(0,10)
}
export function sundayOf(value){
  const date=new Date(`${value}T12:00:00Z`)
  date.setUTCDate(date.getUTCDate()-date.getUTCDay())
  return date.toISOString().slice(0,10)
}
export function addDays(value,days){
  const date=new Date(`${value}T12:00:00Z`)
  date.setUTCDate(date.getUTCDate()+days)
  return date.toISOString().slice(0,10)
}
export function isoWeek(value){
  const thursday=new Date(`${mondayOf(value)}T12:00:00Z`)
  thursday.setUTCDate(thursday.getUTCDate()+3)
  const first=new Date(Date.UTC(thursday.getUTCFullYear(),0,4,12))
  first.setUTCDate(first.getUTCDate()-(first.getUTCDay()+6)%7+3)
  return {year:thursday.getUTCFullYear(),week:1+Math.round((thursday-first)/604800000)}
}
export const isIntegralPlantEstimate=row=>/EJERCICIO.*proceso de planta a/i.test(row.concepto||'')
export function weeklyResult(totals){
  return Object.fromEntries(['CRC','USD'].map(currency=>{const t=totals[currency],income=t.export+t.local+t.manualIncome-t.credits,expense=t.product+t.freight+t.costs;return [currency,{income,expense,result:income-expense}]}))
}
export function weeklyTotals({sales=[],purchases=[],fixedPurchases=[],freights=[],purchasePayroll=[],locals=[],fieldSales=[],directSales=[],costs=[],notes=[],manual=[],payroll=[],productionCosts=[],cartonCosts=[]}){
  const totals={CRC:{export:0,local:0,product:0,freight:0,costs:0,credits:0,manualIncome:0},USD:{export:0,local:0,product:0,freight:0,costs:0,credits:0,manualIncome:0}}
  const hasIntegralEstimate=productionCosts.some(isIntegralPlantEstimate)
  for(const row of sales){const currency=row.moneda||'USD';if(totals[currency])totals[currency][row.mercado==='Costa Rica'?'local':'export']+=Number(row.monto_cxc||0)}
  for(const row of purchases)totals.CRC.product+=Number(row.monto_cxp||0)
  for(const row of fixedPurchases)totals.CRC.product+=Number(row.monto||0)
  for(const row of freights)totals.CRC.freight+=Number(row.monto||0)
  for(const row of purchasePayroll)totals.CRC.costs+=Number(row.monto||0)
  for(const row of locals){const currency=row.moneda;if(totals[currency])totals[currency].local+=(row.ventas_segundas||[]).reduce((sum,x)=>sum+Number(x.subtotal||0),0)}
  for(const row of fieldSales)if(totals[row.moneda])totals[row.moneda].local+=Number(row.monto||0)
  for(const row of directSales)if(totals[row.moneda])totals[row.moneda].local+=Number(row.cantidad||0)*Number(row.precio_unitario||0)
  const isExercisePayroll=row=>row.categoria==='otros'&&/EJERCICIO.*estimado de planilla/i.test(row.concepto||'')
  for(const row of costs)if(totals[row.moneda]&&(!hasIntegralEstimate||row.categoria!=='planilla'))totals[row.moneda].costs+=Number(row.monto||0)
  if(!hasIntegralEstimate&&!costs.some(isExercisePayroll))for(const row of payroll)totals.CRC.costs+=Number(row.bruto||0)
  for(const row of productionCosts)if(totals[row.moneda]&&(!hasIntegralEstimate||isIntegralPlantEstimate(row)))totals[row.moneda].costs+=Number(row.weekAmount||0)
  for(const row of cartonCosts)if(totals[row.moneda])totals[row.moneda].costs+=Number(row.monto||0)
  for(const row of notes){const currency=row.ordenes_venta?.moneda||'USD';if(totals[currency])totals[currency].credits+=Number(row.monto||0)}
  for(const row of manual)if(totals[row.moneda]&&!row.costo_operativo_id)totals[row.moneda][row.tipo==='cobrar'?'manualIncome':'costs']+=Number(row.monto||0)
  return totals
}

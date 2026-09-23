export function costaRicaToday(date=new Date()){
  const parts=Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:'America/Costa_Rica',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date).filter(x=>x.type!=='literal').map(x=>[x.type,x.value]))
  return `${parts.year}-${parts.month}-${parts.day}`
}
export function mondayOf(value){
  const date=new Date(`${value}T12:00:00Z`)
  date.setUTCDate(date.getUTCDate()-(date.getUTCDay()+6)%7)
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
export function weeklyTotals({sales=[],purchases=[],locals=[],costs=[]}){
  const totals={CRC:{export:0,local:0,product:0,costs:0},USD:{export:0,local:0,product:0,costs:0}}
  for(const row of sales)totals.USD.export+=Number(row.monto_cxc||0)
  for(const row of purchases)totals.CRC.product+=Number(row.monto_cxp||0)
  for(const row of locals){const currency=row.moneda;if(totals[currency])totals[currency].local+=(row.ventas_segundas||[]).reduce((sum,x)=>sum+Number(x.subtotal||0),0)}
  for(const row of costs)if(totals[row.moneda])totals[row.moneda].costs+=Number(row.monto||0)
  return totals
}

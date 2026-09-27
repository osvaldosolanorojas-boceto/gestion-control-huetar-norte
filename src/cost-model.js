const utc=date=>Date.parse(`${date}T12:00:00Z`)
const days=(start,end)=>Math.round((utc(end)-utc(start))/86400000)+1
export function periodShare(row,start,end){
  const from=row.periodo_inicio,to=row.periodo_fin
  if(!from||!to||to<start||from>end)return 0
  const length=days(from,to),before=Math.max(0,Math.round((utc(start)-utc(from))/86400000))
  const through=Math.min(length,days(from,end<to?end:to))
  const cents=Math.round(Number(row.monto||0)*100)
  return (Math.round(cents*through/length)-Math.round(cents*before/length))/100
}
export const sumCost=(rows,start,end,currency)=>rows.filter(r=>r.moneda===currency).reduce((sum,r)=>sum+periodShare(r,start,end),0)

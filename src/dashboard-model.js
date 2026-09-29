import {addDays,isoWeek,mondayOf} from './weekly-model.js'
export function greeting(date=new Date()){
  const hour=Number(new Intl.DateTimeFormat('en-US',{timeZone:'America/Costa_Rica',hour:'numeric',hourCycle:'h23'}).format(date))
  return hour<12&&hour>=5?'Buenos días':hour<18&&hour>=12?'Buenas tardes':'Buenas noches'
}
export function weekValue(date){const {year,week}=isoWeek(date);return `${year}-W${String(week).padStart(2,'0')}`}
export function weekRange(value){const [year,week]=value.split('-W').map(Number);const start=addDays(mondayOf(`${year}-01-04`),(week-1)*7);return {start,end:addDays(start,6),year,week}}
export function financeSummary(data){
  return Object.fromEntries(['CRC','USD'].map(currency=>[currency,{
    receivable:data.receivables.filter(r=>r.moneda===currency&&r.etapa!=='Pedido previsto').reduce((n,r)=>n+Math.max(0,Number(r.monto)-Number(r.aplicado)),0),
    payable:data.payables.filter(r=>r.moneda===currency&&r.etapa!=='Faltan precios').reduce((n,r)=>n+Math.max(0,Number(r.monto)-Number(r.aplicado)),0),
    available:data.accounts.filter(a=>a.moneda===currency&&a.empresa==='exportadora'&&['banco','efectivo'].includes(a.tipo_cuenta)).reduce((n,a)=>n+Number(a.neto_movimientos||0)+(a.saldo_confirmado||a.saldo_simulado?Number(a.saldo_inicial):0),0)
  }]))
}

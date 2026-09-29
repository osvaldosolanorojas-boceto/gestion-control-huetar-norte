const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'}
const base='https://www.bccr.fi.cr/content/bccr/cr/es/home/jcr:content/root/container/container/economicindicators/'
let cache:{fecha:string,compra:number,venta:number,fuente:string}|null=null
let cachedAt=0
export async function readRate(url:string,code:string){
 const response=await fetch(url,{signal:AbortSignal.timeout(15000)})
 if(!response.ok)throw new Error('BCCR no disponible')
 const data=await response.json(),series=data.series?.[0]
 if(String(data.codigoIndicador)!==code||!series||!/^\d{4}-\d{2}-\d{2}$/.test(series.fecha)||!Number.isFinite(Number(series.valorDatoPorPeriodo))||Number(series.valorDatoPorPeriodo)<=0)throw new Error('Respuesta del BCCR inválida')
 return {fecha:series.fecha,valor:Number(series.valorDatoPorPeriodo)}
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors})
 const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}})
 // La plataforma exige el JWT del usuario. No se consultan ni modifican datos contables.
 if(!req.headers.get('authorization')?.startsWith('Bearer '))return json({error:'Acceso requerido'},401)
 try{
  if(cache&&Date.now()-cachedAt<30*60*1000)return json(cache)
  const [buy,sell]=await Promise.all([readRate(base+'cardindicador.indicator.317.json','317'),readRate(base+'item_1774647976317.indicator.318.json','318')])
  if(buy.fecha!==sell.fecha)throw new Error('Fechas del BCCR distintas')
  cache={fecha:buy.fecha,compra:buy.valor,venta:sell.valor,fuente:'BCCR'};cachedAt=Date.now()
  return json(cache)
 }catch{return json({error:'No se pudo consultar el tipo de cambio oficial del BCCR.'},502)}
})

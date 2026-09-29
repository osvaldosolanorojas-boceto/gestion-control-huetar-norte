export const blankShipping=()=>({contenedor:'',ryan:'',marchamos:'',factura:'',telefono:'',tratamiento:'',pesos_brutos:{}})
export const reportRows=(lines,shipping)=>lines.map(l=>({id:l.id,paletas:Number(l.paletas),producto:`${l.producto} ${Number(l.presentacion_kg)} kg × ${Number(l.cajas_por_paleta)}`,cajas:Number(l.cantidad_cajas),precio:Number(l.precio_caja),total:Number(l.total),neto:Number(l.cantidad_cajas)*Number(l.presentacion_kg),bruto:shipping.pesos_brutos?.[l.id]===undefined?null:Number(shipping.pesos_brutos[l.id])}))
export const reportTotals=rows=>({paletas:rows.reduce((n,r)=>n+r.paletas,0),cajas:rows.reduce((n,r)=>n+r.cajas,0),total:rows.reduce((n,r)=>n+r.total,0),neto:rows.reduce((n,r)=>n+r.neto,0),bruto:rows.every(r=>r.bruto!==null)?rows.reduce((n,r)=>n+r.bruto,0):null})
export const reportMoney=(v,currency='USD')=>new Intl.NumberFormat('es-CR',{style:'currency',currency,minimumFractionDigits:2,maximumFractionDigits:2}).format(v)
export const reportNumber=v=>v===null?'Pendiente':Number(v).toLocaleString('es-CR',{maximumFractionDigits:3})
export const reportTitle=(order,client)=>`${client}${order.numero_cliente?` #${order.numero_cliente}`:''}`

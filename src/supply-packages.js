const fmt=n=>Number(n).toLocaleString('es-CR',{maximumFractionDigits:3})
export function packageEquivalent(item){
  const factor=Number(item.unidades_por_presentacion),stock=Number(item.existencia)
  if(!item.presentacion_compra||!Number.isFinite(factor)||factor<=1||!Number.isFinite(stock)||stock<0)return ''
  // Work in thousandths, matching the precision of the inventory quantities.
  const amount=Math.round(stock*1000),size=Math.round(factor*1000)
  const complete=Math.floor(amount/size),remainder=(amount%size)/1000
  const unit=item.presentacion_compra.toLowerCase()==='caja'?(complete===1?'caja':'cajas'):item.presentacion_compra
  return `${fmt(complete)} ${unit} de ${fmt(factor)} ${item.unidad}${remainder>0?` + ${fmt(remainder)} ${item.unidad}`:''}`
}

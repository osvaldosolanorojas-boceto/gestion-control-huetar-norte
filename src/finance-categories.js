export function accountCategory(row,kind){
  if(row.manual?.categoria)return row.manual.categoria
  if(kind==='receivables'){
    if(row.origen==='venta_rechazo_campo')return 'Rechazos de campo'
    if(row.origen==='venta_local')return 'Ventas locales · segundas y otros'
    if(row.origen==='venta_exportacion')return 'Ventas de exportación'
    if(row.origen==='venta_directa_en_pie')return 'Ventas directas de campo'
    if(row.origen==='saldo_productor')return 'Adelantos por recuperar'
    return 'Otras cuentas por cobrar'
  }
  if(row.origen==='flete_compra')return 'Fletes'
  if(row.origen?.startsWith('planilla'))return 'Planillas'
  if(row.origen==='compra_insumos')return row.insumos?.length?`Insumos · ${[...new Set(row.insumos.map(i=>i.categoria||i.nombre))].join(' / ')}`:'Insumos'
  if(row.origen==='compra_cartones')return 'Cartón'
  if(row.producto)return row.producto
  return 'Otras cuentas por pagar'
}

export const payableFamilies=['Materia prima','Insumos','Fletes','Planillas','Otros']
export function payableFamily(row){
  const category=accountCategory(row,'payables').toLocaleLowerCase('es-CR')
  if(row.origen==='flete_compra'||category.includes('flete'))return 'Fletes'
  if(row.origen?.startsWith('planilla')||category.includes('planilla'))return 'Planillas'
  if(['compra_insumos','compra_cartones'].includes(row.origen)||/insumo|cart[oó]n|parafina|cera/.test(category))return 'Insumos'
  if(row.origen==='compra_campo'||row.producto||category.includes('materia prima'))return 'Materia prima'
  return 'Otros'
}

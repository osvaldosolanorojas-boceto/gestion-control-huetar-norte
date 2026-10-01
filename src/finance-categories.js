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
  if(row.origen==='compra_insumos')return 'Insumos'
  if(row.origen==='compra_cartones')return 'Cartón'
  if(row.producto)return row.producto
  return 'Otras cuentas por pagar'
}

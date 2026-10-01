export const auditDate='2026-10-01'
export const exampleDefaults={mode:'Porcentaje',ownerPercent:30,harvestKg:70000,europaQq:1000,usaQq:300,secondBoxes:100,rejectSacks:200,secondBoxKg:30,rejectSackKg:30,wasteKg:1200,seedUnits:2000,europaPrice:14000,usaPrice:7000,secondPrice:5000,rejectPrice:3000,seedPrice:100,operatingCosts:4800000,mechanization:1000000,rental:450000,lossPercent:0,paidPercent:25,tractorValue:12000000,implementValue:2000000,stockValue:1650000}
const money=v=>Math.round(v*100)/100
export function runFarmExample(input){
 const x={...exampleDefaults,...input},errors=[]
 for(const key of Object.keys(exampleDefaults).filter(k=>k!=='mode')){x[key]=Number(x[key]);if(!Number.isFinite(x[key])||x[key]<0)errors.push(`Revise ${key}: debe ser un número mayor o igual a cero.`)}
 if(!['Propia','Alquilada','Porcentaje','Mecanizada'].includes(x.mode))errors.push('Seleccione una modalidad válida.')
 if(x.lossPercent>100||x.ownerPercent>100||x.paidPercent>100)errors.push('Los porcentajes no pueden superar 100%.')
 if(x.mechanization>x.operatingCosts)errors.push('La mecanización incluida no puede superar los costos del cultivo.')
 const classifiedKg=(x.europaQq+x.usaQq)*46+x.secondBoxes*x.secondBoxKg+x.rejectSacks*x.rejectSackKg+x.wasteKg
 if(Math.abs(classifiedKg-x.harvestKg)>0.001)errors.push('Los kilos de primera, segunda, rechazo y desperdicio deben sumar la cosecha prevista.')
 if(errors.length)return {errors}
 const factor=1-x.lossPercent/100
 const lines=[['Primera Europa',x.europaQq,'quintales',x.europaPrice],['Primera EEUU',x.usaQq,'quintales',x.usaPrice],['Segunda vendida directamente en finca',x.secondBoxes,'cajas',x.secondPrice],['Rechazo vendido directamente en finca',x.rejectSacks,'sacos',x.rejectPrice],['Semilla / estacas vendidas',x.seedUnits,'unidades',x.seedPrice]].map(([name,quantity,unit,price])=>({name,quantity:quantity*factor,unit,price,revenue:money(quantity*factor*price)}))
 const revenue=money(lines.reduce((sum,l)=>sum+l.revenue,0)),owner=money(['Porcentaje','Mecanizada'].includes(x.mode)?revenue*x.ownerPercent/100:0)
 const rent=x.mode==='Alquilada'?x.rental:0,costs=money(x.operatingCosts-(x.mode==='Mecanizada'?x.mechanization:0)),net=money(revenue-owner-rent-costs)
 const collected=money(revenue*x.paidPercent/100),receivable=money(revenue-collected)
 const cultivationInvestment=costs+rent,assets=money(x.tractorValue+x.implementValue),beforeHarvest=money(assets+x.stockValue+cultivationInvestment)
 return {errors:[],lines,revenue,owner,rent,costs,net,collected,receivable,classifiedKg,lostKg:x.harvestKg*x.lossPercent/100,normalWasteKg:x.wasteKg*factor,rootSalesKg:(classifiedKg-x.wasteKg)*factor,assets,cultivationInvestment,beforeHarvest,afterClosedFixedAndStock:money(assets+x.stockValue)}
}
export const auditedChecks=[
 ['Entrega directa','OK','Recibe 100 sacos por ₡1.000.000 y genera una deuda de Agrosolano.'],
 ['Compra sin consumo','OK','La recepción conserva inventario y todavía no registra costo del cultivo.'],
 ['Deuda de insumos','OK','Una cuenta por pagar, por el monto correcto y en la empresa correcta.'],
 ['Reintento de entrega','OK','La misma solicitud no duplica existencia ni deuda.'],
 ['Traslado entre fincas','OK','Conserva ₡3.000.000 de valor total y aplica costo promedio.'],
 ['Consumo por lote','OK','40 sacos pasan a costo agrícola por ₡600.000.'],
 ['Existencia insuficiente','OK','Rechaza el exceso y conserva el saldo previo.'],
 ['Lote ajeno','OK','Rechaza la finca incorrecta y revierte toda la operación.'],
 ['Planilla','OK','Distingue costo bruto ₡150.000 y neto por pagar ₡140.000.'],
 ['Edición de planilla','OK','Actualiza el mismo costo y la misma deuda, sin duplicarlos.'],
 ['Banco de otra empresa','OK','Rechaza pagar deuda de Agrosolano desde la exportadora.'],
 ['Pago parcial','OK','Paga ₡100.000 y deja ₡70.000 por pagar.'],
 ['Edición después del pago','OK','Rechaza reducir la deuda por debajo de lo ya pagado.'],
 ['Combustible','OK','Registra litros, costo, deuda y horómetro.'],
 ['Edición de combustible','OK','Actualiza un solo costo.'],
 ['Tractor de otra finca','OK','Rechaza una asignación incorrecta.'],
 ['Gastos generales sin lote','Corregido','Ahora se muestran aparte y se pueden asignar a un lote de la misma finca.'],
 ['Valor del inventario','Corregido','La inversión usa saldos de bodega y conserva fichas manuales como referencia, sin sumarlas dos veces.'],
 ['Liquidación del dueño','Pendiente','El 30%/38% está en el contrato. Falta calcular la liquidación sobre las ventas agrícolas de la propiedad y generar la deuda.'],
 ['Subproductos por finca','Pendiente','Las ventas directas necesitan origen finca/lote, kilos, precio y cuenta por cobrar propia.'],
 ['Cierre y pérdida del cultivo','Pendiente','La marca en curso no sustituye una liquidación final ni un registro de pérdida.']
]
export const farmPriorities=[
 ['Primero','Ciclo de cultivo','Área, variedad, siembra, cosecha estimada y real, cosechas parciales, estado, responsable y costo por hectárea/quintal. Un lote puede tener varios ciclos.'],
 ['Primero','Cosecha y balance físico','Kilos cosechados = entregados + vendidos directamente + semilla retenida + remanente + pérdidas. Evitar vender dos veces la misma cantidad.'],
 ['Primero','Ventas directas y subproductos','Primera local, segunda, rechazo, semilla/estacas y otros, con cliente, origen, unidad/peso y cobro. La venta de planta pertenece a exportadora; no se suma otra vez en finca.'],
 ['Primero','Liquidación del propietario','Base bruta por propiedad; porcentaje pactado, anticipos, pagos, saldo y correcciones. Aclarar cómo se tratan devoluciones/descuentos y semilla antes de automatizar.'],
 ['Primero','Cierre del cultivo','Cierre parcial/final, costos pendientes, ventas pendientes, pérdidas, remanentes y reapertura con motivo. Conservar resultado e historial.'],
 ['Primero','Costos compartidos','Repartir planilla, combustible, alquiler y caminos entre lotes con criterio visible: horas, hectáreas o monto manual. Mostrar lo que queda sin asignar.'],
 ['Primero','Una ficha por máquina','Unificar la ficha patrimonial y la ficha de operación del tractor para tener valor, horómetro, trabajos y mantenimiento sin doble registro.'],
 ['Después','Compras de insumos en USD','Conservar deuda en la moneda original y tipo de cambio de cada compra. Separar diferencia cambiaria del costo agrícola.'],
 ['Después','Bodega completa','Devoluciones a central/proveedor, sobrantes, pérdidas, conteos físicos, responsable y motivo de ajuste; lotes de producto y vencimiento cuando aplique.'],
 ['Después','Traslados e historial de maquinaria','Guardar finca origen/destino y fecha; conservar gastos históricos aunque cambie la ubicación actual. Registrar venta, baja o pérdida del equipo.'],
 ['Después','Mantenimiento y llantas','Servicios por horas/fecha, historial, repuestos, costo, trabajos pendientes y alertas próximas, sin bloquear las operaciones.'],
 ['Después','Contratos','Documento adjunto, ubicación/área, depósito, calendario de cuotas, prórrogas y aviso de vencimiento. Distribuir el alquiler entre los cultivos del período.'],
 ['Después','Inversión y caja separadas','Mostrar activos y cultivos, deuda por pagar, cuentas por cobrar y dinero efectivamente desembolsado. Inversión no equivale a gasto ni a utilidad cobrada.'],
 ['Después','Operación en campo','Asignación de personal por finca, labores por lote, cantidades realizadas, evidencia y permisos que ocultan montos al personal de campo.'],
 ['Después','Correcciones','Motivo, usuario, fecha y antes/después para costos, inventarios, cosechas, contratos y traslados.'],
 ['Más adelante','Terrenos propios','Valoración de Copevega y demás activos según el criterio acordado; mantenerla aparte del resultado operativo agrícola.'],
 ['Más adelante','Documentos y controles','Comprobantes, conciliación de bancos, respaldo comprobable, presupuesto frente a ejecución y recordatorios.'],
 ['Simplificar','Inventario manual duplicado','Usar una sola existencia por insumo y bodega. El saldo manual inicial debe convertirse en entrada identificada.'],
 ['Simplificar','Fincas históricas','Ocultar inactivas en nuevas operaciones, conservar su historia y evitar crear dos fincas con nombres escritos distinto.'],
 ['Simplificar','Pantalla de Fincas','Separar contratos, maquinaria, bodega, cultivos y resultados en secciones plegables; mostrar primero el resumen y el ejercicio.']
]

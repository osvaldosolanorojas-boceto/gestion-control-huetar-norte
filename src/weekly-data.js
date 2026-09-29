import {supabase} from './supabase'
import {addDays,isoWeek,sundayOf} from './weekly-model.js'
import {periodShare} from './cost-model.js'

export async function loadWeeklyRecords(weekStart,saturday){
  const week=isoWeek(addDays(weekStart,1))
    const results=await Promise.all([
      supabase.from('ordenes_venta').select('id,codigo,monto_cxc,moneda,mercado,finalizada_en').not('finalizada_en','is',null).gte('fecha_salida',weekStart).lte('fecha_salida',saturday),
      supabase.from('boletas_entrada').select('id,codigo,monto_cxp,finalizada_en').not('finalizada_en','is',null).gte('fecha_labor',weekStart).lte('fecha_labor',saturday),
      supabase.from('ventas_locales').select('id,codigo,fecha,moneda,ventas_segundas(subtotal)').gte('fecha',weekStart).lte('fecha',saturday),
      supabase.from('costos_operativos').select('*').gte('fecha',weekStart).lte('fecha',saturday).is('anulado_en',null).order('fecha',{ascending:false}).limit(1000),
      supabase.from('trabajadores').select('id,nombre').eq('activo',true).order('nombre').limit(1000),
      supabase.from('ordenes_venta').select('id,codigo,contenedor,fecha_salida,finalizada_en').order('creado_en',{ascending:false}).limit(1000),
      supabase.from('cxp_operativa').select('origen_id,codigo,fecha,monto,etapa').in('etapa',['Puesto en camión · precio fijo','En campo · pesaje pactado']).gte('fecha',weekStart).lte('fecha',saturday).limit(1000),
      supabase.from('cxp_operativa').select('origen,origen_id,codigo,fecha,monto,contraparte').eq('origen','flete_compra').gte('fecha',weekStart).lte('fecha',saturday).limit(1000),
      supabase.from('notas_credito_ventas').select('id,fecha,monto,motivo,ordenes_venta(codigo,moneda)').gte('fecha',weekStart).lte('fecha',saturday),
      supabase.from('cuentas_manuales').select('id,codigo,fecha,tipo,monto,moneda,costo_operativo_id').gte('fecha',weekStart).lte('fecha',saturday),
      supabase.from('cxc_operativa').select('origen,origen_id,codigo,fecha,fecha_salida,moneda,monto,aplicado,etapa').lte('fecha',saturday).limit(1000),
      supabase.from('cxp_operativa').select('origen,origen_id,codigo,fecha,moneda,monto,aplicado,etapa').lte('fecha',saturday).limit(1000),
      supabase.from('planillas_planta').select('id,trabajador_id,bruto,neto,semana_inicio').gte('semana_inicio',addDays(weekStart,-6)).lte('semana_inicio',saturday).is('anulado_en',null).limit(1000),
      supabase.from('costos_produccion').select('id,categoria,concepto,periodo_inicio,periodo_fin,moneda,monto,producto').lte('periodo_inicio',saturday).gte('periodo_fin',weekStart).is('anulado_en',null).limit(1000),
      supabase.from('jornadas_trabajo').select('id,trabajador_id,costo_bruto,tipo_pago').gte('fecha_labor',weekStart).lte('fecha_labor',saturday).limit(2000),
      supabase.from('planillas_fijas').select('id,trabajador_id,periodo_inicio,periodo_fin,costo_total,neto').lte('periodo_inicio',saturday).gte('periodo_fin',weekStart).limit(1000),
      supabase.from('costos_cartones').select('carton_id,fecha,cantidad,precio_unitario,moneda,simulado').lte('fecha',saturday).limit(1000),
      supabase.from('ordenes_venta_lineas').select('orden_venta_id,carton_id,cantidad_cajas,presentacion_kg').limit(2000),
      supabase.from('tasas_corte_semanal').select('semana_inicio,usd_crc,fuente,simulado').in('semana_inicio',[weekStart,sundayOf(addDays(weekStart,1))]).order('semana_inicio',{ascending:false}).limit(1).maybeSingle(),
      supabase.from('cxp_operativa').select('origen_id,codigo,fecha,monto,etapa').eq('origen','planilla_compra').gte('fecha',weekStart).lte('fecha',saturday).limit(1000),
      supabase.from('pedidos_ejercicio').select('orden_venta_id').limit(1000),
      supabase.from('ordenes_compra').select('id,codigo,fecha,precio_en_pie,en_pie_finalizada_en').eq('tipo_compra','En pie').lte('fecha',saturday).neq('estado','Anulada').limit(1000),
      supabase.from('boletas_entrada').select('orden_compra_id,fecha_labor,finalizada_en').not('orden_compra_id','is',null).not('finalizada_en','is',null).limit(2000),
      supabase.from('ordenes_compra').select('id,codigo,precio_eeuu').like('codigo',`OC-EJ-${week.week}-%`).eq('producto','Yuca').eq('precio_eeuu',7000).limit(1000),
      supabase.from('ventas_rechazo_campo').select('id,orden_compra_id,fecha,comprador,sacos,kg_brutos,kg_pagables,castigo_pct,precio_quintal,monto,moneda').gte('fecha',weekStart).lte('fecha',saturday).limit(1000),
      supabase.from('ventas_externas_en_pie').select('id,fecha,producto,comprador,cantidad,unidad,precio_unitario,moneda').gte('fecha',weekStart).lte('fecha',saturday).limit(1000),
      supabase.from('boleta_rendimientos').select('cajas,kg_resultado,boletas_entrada(codigo,fecha_labor,fecha_hora),ordenes_venta_lineas(ordenes_venta(codigo,fecha_salida))').not('orden_venta_linea_id','is',null).limit(2000),
      supabase.from('revision_gastos_contenedor').select('orden_venta_id').limit(1000)
    ])
    if(results.some(r=>Array.isArray(r.data)&&r.data.length>=1000))throw new Error('Hay demasiados registros para calcular un resultado completo.');
    const failure=results.find(r=>r.error)?.error
    if(failure)throw new Error(`No se pudo cargar el corte: ${failure.message}`)
    if(results[6].data?.length===1000||results[7].data?.length===1000||results[10].data?.length===1000||results[11].data?.length===1000||results[13].data?.length===1000||results[14].data?.length===2000||results[15].data?.length===1000||results[16].data?.length===1000||results[17].data?.length===2000||results[19].data?.length===1000||results[20].data?.length===1000||results[21].data?.length===1000||results[22].data?.length===2000||results[23].data?.length===1000||results[24].data?.length===1000||results[25].data?.length===1000||results[26].data?.length===2000||results[27].data?.length===1000)throw new Error('Hay más registros que el límite de consulta; no se muestran cifras parciales.')
    const rate=results[18].data||null
    const balances={receivables:results[10].data||[],payables:results[11].data||[]}
    const older=(results[12].data||[]).map(row=>({...row,bruto:periodShare({periodo_inicio:row.semana_inicio,periodo_fin:addDays(row.semana_inicio,6),monto:row.bruto},weekStart,saturday),neto:periodShare({periodo_inicio:row.semana_inicio,periodo_fin:addDays(row.semana_inicio,6),monto:row.neto},weekStart,saturday)})),legacyIds=new Set(older.map(x=>x.trabajador_id))
    const hourly=[...new Set((results[14].data||[]).filter(x=>x.tipo_pago==='Por horas'&&!legacyIds.has(x.trabajador_id)).map(x=>x.trabajador_id))].map(id=>{const total=(results[14].data||[]).filter(x=>x.trabajador_id===id).reduce((v,x)=>v+Number(x.costo_bruto||0),0);return {id:`jornadas-${id}`,trabajador_id:id,bruto:total,neto:total}})
    const fixed=(results[15].data||[]).filter(x=>!legacyIds.has(x.trabajador_id)).map(x=>({id:`fijo-${x.id}`,trabajador_id:x.trabajador_id,bruto:periodShare({periodo_inicio:x.periodo_inicio,periodo_fin:x.periodo_fin,monto:x.costo_total},weekStart,saturday),neto:periodShare({periodo_inicio:x.periodo_inicio,periodo_fin:x.periodo_fin,monto:x.neto},weekStart,saturday)}))
    const allOrders=results[5].data||[],priced=results[16].data||[],cartonCosts=[],cartonMissing=[]
    for(const line of results[17].data||[]){const order=allOrders.find(o=>o.id===line.orden_venta_id);if(!line.carton_id||!order?.finalizada_en||!order.fecha_salida||order.fecha_salida<weekStart||order.fecha_salida>saturday)continue
      const candidates=priced.filter(c=>c.carton_id===line.carton_id&&c.fecha<=order.fecha_salida&&Number(c.precio_unitario)>0),prices=[...new Set(candidates.map(c=>`${c.moneda}:${c.precio_unitario}`))]
      const usedToDate=(results[17].data||[]).filter(x=>x.carton_id===line.carton_id&&allOrders.some(o=>o.id===x.orden_venta_id&&o.finalizada_en&&o.fecha_salida<=order.fecha_salida)).reduce((sum,x)=>sum+Number(x.cantidad_cajas||0),0)
      if(prices.length!==1||candidates.reduce((sum,c)=>sum+Number(c.cantidad),0)<usedToDate){cartonMissing.push({codigo:order.codigo,cantidad:line.cantidad_cajas,reason:prices.length===0?'Falta precio':prices.length>1?'Hay varios precios; falta asignar lote':'Faltan cartones con costo'});continue}
      const [currency,unit]=prices[0].split(':');cartonCosts.push({codigo:order.codigo,moneda:currency,monto:Number(line.cantidad_cajas)*Number(unit),cantidad:line.cantidad_cajas,simulado:candidates.some(c=>c.simulado)})
    }
    const standing=(results[21].data||[]).map(order=>{
      const dates=(results[22].data||[]).filter(b=>b.orden_compra_id===order.id).map(b=>b.fecha_labor||b.finalizada_en?.slice(0,10)).filter(Boolean).sort()
      return {...order,costDate:dates[0]||order.en_pie_finalizada_en?.slice(0,10)||null,started:dates.length>0}
    })
    const standingExpense=standing.filter(x=>x.costDate>=weekStart&&x.costDate<=saturday).map(x=>({origen_id:x.id,codigo:x.codigo,fecha:x.costDate,monto:x.precio_en_pie,etapa:x.started?'Compra en pie · primer lote procesado':'Compra en pie · lote finalizado'}))
    const simulatedOrders=(results[20].data||[]).map(x=>x.orden_venta_id)
    const chronology=Object.values((results[26].data||[]).reduce((groups,r)=>{const sale=r.ordenes_venta_lineas?.ordenes_venta,source=r.boletas_entrada,origin=source?.fecha_labor||source?.fecha_hora?.slice(0,10);if(!sale?.fecha_salida||sale.fecha_salida<weekStart||sale.fecha_salida>saturday||!origin||origin<=sale.fecha_salida)return groups;const key=`${sale.codigo}:${source.codigo}`;const item=groups[key]||(groups[key]={pedido:sale.codigo,salida:sale.fecha_salida,boleta:source.codigo,origen:origin,cajas:0,kg:0});item.cajas+=Number(r.cajas||0);item.kg+=Number(r.kg_resultado||0);return groups},{}))
    const records={sales:results[0].data||[],purchases:results[1].data||[],locals:results[2].data||[],fieldSales:results[24].data||[],directSales:results[25].data||[],chronology,costs:results[3].data||[],fixedPurchases:[...(results[6].data||[]),...standingExpense],freights:results[7].data||[],purchasePayroll:results[19].data||[],openStanding:standing.filter(x=>!x.costDate&&!x.en_pie_finalizada_en),startedStanding:standing.filter(x=>x.started&&!x.en_pie_finalizada_en&&x.costDate>=weekStart&&x.costDate<=saturday),notes:results[8].data||[],manual:results[9].data||[],payroll:[...older,...hourly,...fixed],productionCosts:(results[13].data||[]).map(row=>({...row,weekAmount:periodShare(row,weekStart,saturday)})),cartonCosts,cartonMissing,simulatedOrders,outdatedPrices:week.year===2026?results[23].data||[]:[],confirmedCosts:(results[27].data||[]).map(x=>x.orden_venta_id)}
    return {records,workers:results[4].data||[],orders:allOrders,balances,rate}
}

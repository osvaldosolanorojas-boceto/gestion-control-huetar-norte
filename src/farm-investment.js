export function farmInvestment(farmId,assets,lots,costs,orders=[],stockRows=null){
 const activeLots=new Set(lots.filter(l=>l.finca_id===farmId&&l.inversion_en_curso).map(l=>l.id))
 const own=assets.filter(a=>a.finca_id===farmId&&a.pertenencia==='Propio'&&a.estado!=='Retirado'&&Number(a.cantidad)>0)
 const cents=a=>Math.round(Number(a.cantidad)*Number(a.valor_actual_unitario_crc)*100)
 const amount=type=>own.filter(a=>a.tipo===type&&a.valor_actual_unitario_crc!=null).reduce((s,a)=>s+cents(a),0)/100
 const cultivation=(costs.filter(c=>activeLots.has(c.lote_id)&&c.incluir_en_inversion!==false).reduce((s,c)=>s+Math.round(Number(c.monto)*100),0)+orders.filter(o=>activeLots.has(o.finca_lote_id)).reduce((s,o)=>s+Math.round(Number(o.cuadrilla_arranca||0)*100)+Math.round(Number(o.flete||0)*100),0))/100
 const tractors=amount('Tractor'),implementsValue=amount('Implemento agrícola')
 // The warehouse ledger is authoritative when available. Never add its value
 // to a manually entered supply valuation for the same administration.
 const supplies=stockRows===null?amount('Insumo disponible'):stockRows.filter(s=>s.finca_id===farmId).reduce((sum,s)=>sum+Math.round(Number(s.valor_crc)*100),0)/100
 const unallocated=costs.filter(c=>c.finca_id===farmId&&!c.lote_id)
 const unallocatedCosts=unallocated.reduce((s,c)=>s+Math.round(Number(c.monto)*100),0)/100
 const pending=own.filter(a=>(stockRows===null||a.tipo!=='Insumo disponible')&&a.valor_actual_unitario_crc==null).length
 const legacySupplies=stockRows!==null?own.filter(a=>a.tipo==='Insumo disponible').length:0
 return {tractors,implementsValue,supplies,cultivation,total:Math.round((tractors+implementsValue+supplies+cultivation)*100)/100,pending,activeLots:activeLots.size,unallocatedCosts,unallocatedCount:unallocated.length,legacySupplies}
}

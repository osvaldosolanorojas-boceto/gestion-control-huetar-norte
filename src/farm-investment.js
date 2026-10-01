export function farmInvestment(farmId,assets,lots,costs,orders=[]){
 const activeLots=new Set(lots.filter(l=>l.finca_id===farmId&&l.inversion_en_curso).map(l=>l.id))
 const own=assets.filter(a=>a.finca_id===farmId&&a.pertenencia==='Propio'&&a.estado!=='Retirado'&&Number(a.cantidad)>0)
 const cents=a=>Math.round(Number(a.cantidad)*Number(a.valor_actual_unitario_crc)*100)
 const amount=type=>own.filter(a=>a.tipo===type&&a.valor_actual_unitario_crc!=null).reduce((s,a)=>s+cents(a),0)/100
 const cultivation=(costs.filter(c=>activeLots.has(c.lote_id)&&c.incluir_en_inversion!==false).reduce((s,c)=>s+Math.round(Number(c.monto)*100),0)+orders.filter(o=>activeLots.has(o.finca_lote_id)).reduce((s,o)=>s+Math.round(Number(o.cuadrilla_arranca||0)*100)+Math.round(Number(o.flete||0)*100),0))/100
 const tractors=amount('Tractor'),implementsValue=amount('Implemento agrícola'),supplies=amount('Insumo disponible')
 return {tractors,implementsValue,supplies,cultivation,total:tractors+implementsValue+supplies+cultivation,pending:own.filter(a=>a.valor_actual_unitario_crc==null).length,activeLots:activeLots.size}
}

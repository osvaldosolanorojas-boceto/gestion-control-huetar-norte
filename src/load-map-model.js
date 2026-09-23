// Reparte cada renglón de rendimiento en paletas sin alterar sus cajas ni su lote.
export function buildLoadMap(lines,receipts){
  const positions=Array.from({length:22},(_,i)=>i+1),used=new Set(),slots=[]
  const sorted=[...lines].sort((a,b)=>{
    const first=line=>Math.min(...receipts.filter(r=>r.orden_venta_linea_id===line.linea_id&&r.posicion_paleta).map(r=>Number(r.posicion_paleta)),99)
    return first(a)-first(b)||String(a.linea_id).localeCompare(String(b.linea_id))
  })
  for(const line of sorted){
    const preferred=receipts.filter(r=>r.orden_venta_linea_id===line.linea_id&&r.posicion_paleta).map(r=>Number(r.posicion_paleta)).sort((a,b)=>a-b)[0]||1
    const options=[...positions.filter(p=>p>=preferred),...positions.filter(p=>p<preferred)]
    for(const pos of options){
      if(slots.filter(s=>s.linea_id===line.linea_id).length>=Number(line.paletas)||used.has(pos))continue
      used.add(pos);slots.push({position:pos,linea_id:line.linea_id,capacity:Number(line.cajas_por_paleta),loaded:0,chunks:[],product:line.producto,weight:line.presentacion_kg,carton:line.carton})
    }
  }
  const unmapped=[]
  for(const line of sorted){
    const pallets=slots.filter(s=>s.linea_id===line.linea_id).sort((a,b)=>a.position-b.position)
    const rows=receipts.filter(r=>r.orden_venta_linea_id===line.linea_id).sort((a,b)=>String(a.creado_en).localeCompare(String(b.creado_en))||String(a.id).localeCompare(String(b.id)))
    for(const r of rows){
      let pending=Number(r.cajas)||0
      const preferred=Number(r.posicion_paleta)||pallets[0]?.position||1
      const candidates=[...pallets.filter(p=>p.position>=preferred),...pallets.filter(p=>p.position<preferred)]
      for(const pallet of candidates){
        if(pending<=0)break
        const count=Math.min(pending,pallet.capacity-pallet.loaded)
        if(count<=0)continue
        pallet.loaded+=count;pending-=count
        pallet.chunks.push({count,receipt:r.boletas_entrada?.codigo||'Boleta',purchase:r.boletas_entrada?.orden_compra_id||null,code:r.codigo_trazabilidad||'',quality:r.calidad,sourceId:r.id})
      }
      if(pending>0)unmapped.push({linea_id:line.linea_id,receipt:r.boletas_entrada?.codigo,count:pending})
    }
  }
  return {slots:slots.sort((a,b)=>a.position-b.position),unmapped}
}

export function europeYucaProgress(lines,assignments){
 const ids=new Set(lines.map(l=>l.id)),seen=new Set()
 let required=0,completed=0
 for(const line of lines){const n=Number(line.cantidad_cajas);if(!Number.isInteger(n)||n<0)throw new Error('Revise las cajas pedidas de yuca Europa.');required+=n}
 for(const row of assignments){if(!ids.has(row.orden_venta_linea_id)||seen.has(row.id))continue;seen.add(row.id);const n=Number(row.cajas);if(!Number.isInteger(n)||n<0)throw new Error('Revise las cajas asignadas desde planta.');completed+=n}
 return {required,completed,pending:Math.max(0,required-completed),excess:Math.max(0,completed-required),percent:required?Math.min(100,completed/required*100):0}
}

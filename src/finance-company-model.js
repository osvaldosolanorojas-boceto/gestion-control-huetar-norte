export const documentCompany=row=>row.manual?.empresa||'exportadora'
export function companyDocuments(rows,company){return rows.filter(row=>documentCompany(row)===company)}
export function agroReceivables(payables,purchases,providers){
 const ownIds=new Set(purchases.filter(o=>providers.some(p=>p.id===o.proveedor_id&&p.tipo==='Propio')).map(o=>o.id))
 return payables.filter(r=>r.origen==='compra_campo'&&ownIds.has(r.origen_id)).map(r=>({...r,origen:'venta_agro_exportadora',contraparte:'Raíces y Tubérculos Huetar Norte S.A.',etapa:'Producto entregado a exportadora'}))
}

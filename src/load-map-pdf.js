import {jsPDF} from 'jspdf'
import autoTable from 'jspdf-autotable'

export function makeLoadMapPDF(order,map,purchases,ordered){
  const doc=new jsPDF({orientation:'landscape',unit:'mm',format:'a4'})
  const loaded=map.slots.reduce((n,p)=>n+p.loaded,0)+map.unmapped.reduce((n,p)=>n+p.count,0)
  const label=`${order.cliente||'Cliente'}${order.numero_cliente?` ${order.numero_cliente}`:''}`
  doc.setFont('helvetica','bold');doc.setFontSize(16);doc.text('Mapa de carga',12,17)
  doc.setFontSize(11);doc.text(doc.splitTextToSize(`${label} · ${order.codigo}`,273),12,24)
  doc.setFont('helvetica','normal');doc.setFontSize(10)
  doc.text(doc.splitTextToSize(`Salida: ${order.fecha_salida||'Pendiente'} · Contenedor: ${order.contenedor||'Pendiente'}`,273),12,36)
  doc.text(`${loaded} / ${ordered} cajas asignadas · ${Math.max(0,ordered-loaded)} pendientes`,12,47)
  const excess=map.unmapped.reduce((n,p)=>n+p.count,0)
  doc.setFontSize(9);doc.text(excess?`ATENCIÓN: ${excess} cajas exceden la capacidad prevista. Revise pedido y boletas.`:'Asignación desde planta. Confirme la carga física al despachar.',12,54)
  for(let position=1;position<=22;position++){
    const p=map.slots.find(x=>x.position===position),col=(position-1)%2,row=Math.floor((position-1)/2),x=12+col*139,y=61+row*11
    doc.setFillColor(...(!p?[242,244,247]:p.loaded>=p.capacity?[217,237,229]:[255,244,211]));doc.rect(x,y,134,10,'FD')
    doc.setFont('helvetica','bold');doc.setFontSize(9);doc.text(`Paleta ${position}`,x+3,y+4)
    doc.setFont('helvetica','normal');doc.setFontSize(8)
    const text=p?`${p.product} · ${p.weight} kg · ${p.loaded}/${p.capacity} cajas`:'Sin paleta prevista'
    doc.text(doc.splitTextToSize(text,128)[0],x+3,y+8)
  }
  doc.addPage();doc.setFont('helvetica','bold');doc.setFontSize(14);doc.text('Detalle de trazabilidad por paleta',12,17)
  const body=map.slots.flatMap(p=>p.chunks.length?p.chunks.map(c=>[p.position,`${p.product} · ${p.weight} kg\n${p.carton||'Cartón pendiente'}`,c.count,c.receipt,purchases[c.purchase]?.productor_nombre||'Productor pendiente',c.code||'Sin código']):[[p.position,`${p.product} · ${p.weight} kg`,0,'Sin asignación','','']])
  for(const c of map.unmapped)body.push(['Excedente','Sin posición',c.count,c.receipt||'Boleta','',''])
  autoTable(doc,{startY:23,margin:{left:12,right:12,bottom:18},head:[['Paleta','Producto / cartón','Cajas','Boleta','Productor','Código de trazabilidad']],body,theme:'grid',styles:{fontSize:9,cellPadding:3,overflow:'linebreak'},headStyles:{fillColor:[21,76,140]},rowPageBreak:'avoid'})
  const pages=doc.getNumberOfPages()
  for(let i=1;i<=pages;i++){doc.setPage(i);doc.setFont('helvetica','normal');doc.setFontSize(8);doc.text(`Mapa de carga · ${order.codigo} · Página ${i} de ${pages}`,12,202)}
  return doc
}

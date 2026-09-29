import {jsPDF} from 'jspdf'
import autoTable from 'jspdf-autotable'
import {isoWeek} from './weekly-model.js'
import {reportRows,reportTotals,reportTitle,reportMoney,reportNumber} from './shipping-report-model.js'
export function makeShippingPDF(order,client,lines,shipping){
 const doc=new jsPDF({orientation:'landscape',unit:'mm',format:'a4'}),rows=reportRows(lines,shipping),totals=reportTotals(rows),title=reportTitle(order,client),week=isoWeek(order.fecha_salida||order.fecha)
 doc.setFillColor(255,237,117);doc.rect(12,12,273,10,'F');doc.setFont('helvetica','bold');doc.setFontSize(15);doc.text(title,15,19)
 doc.setFillColor(217,237,229);doc.rect(12,23,273,8,'F');doc.setFontSize(12);doc.text(`Semana # ${week.week} · ${week.year}`,15,29)
 doc.setFontSize(10);doc.setFont('helvetica','normal')
 const fields=[['Contenedor',shipping.contenedor],['Marchamos',shipping.marchamos],['Ryan',shipping.ryan],['Fecha de salida',order.fecha_salida],['Tratamiento',shipping.tratamiento],['Factura #',shipping.factura]]
 fields.forEach(([key,val],i)=>{const x=i<4?14:163,y=i<4?39+i*7:39+(i-4)*7;doc.setFont('helvetica','bold');doc.text(`${key}:`,x,y);doc.setFont('helvetica','normal');doc.text(String(val||'Pendiente'),x+34,y,{maxWidth:i<4?111:88})})
 const fmt=v=>reportMoney(v,order.moneda||'USD')
 autoTable(doc,{startY:67,margin:{left:12,right:12},head:[['Paletas','Producto','Cajas','Precio / caja','Total','P. Bruto (kg)','P. Neto (kg)']],body:rows.map(r=>[reportNumber(r.paletas),r.producto,reportNumber(r.cajas),fmt(r.precio),fmt(r.total),reportNumber(r.bruto),reportNumber(r.neto)]),foot:[[reportNumber(totals.paletas),'Total',reportNumber(totals.cajas),'',fmt(totals.total),reportNumber(totals.bruto),reportNumber(totals.neto)]],theme:'grid',styles:{font:'helvetica',fontSize:10,cellPadding:3,lineColor:[70,70,70],lineWidth:.25,textColor:[25,25,25]},headStyles:{fillColor:[232,236,237],textColor:[20,20,20]},footStyles:{fillColor:[255,237,117],textColor:[150,35,35],fontStyle:'bold'},columnStyles:{0:{halign:'center'},2:{halign:'right'},3:{halign:'right'},4:{halign:'right'},5:{halign:'right'},6:{halign:'right'}}})
 const y=doc.lastAutoTable.finalY+8;if(y<195){doc.setFontSize(9);doc.text(`Orden ${order.codigo} · Reporte de embarque · ${order.moneda||'USD'}`,14,y);doc.text('Documento operativo de embarque',14,y+5)}
 return doc
}

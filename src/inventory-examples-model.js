// Presentaciones y precios ilustrativos; no son especificaciones de proveedores.
export const inventoryExamples=[
 ['Parafina','kg','caja',25,4,45,'USD',10],
 ['Cera','kg','caja',25,2,28,'USD',5],
 ['Aceite hidráulico para perras','litros','bidón',20,2,50000,'CRC',5],
 ['Cloro al 12%','litros','bidón',20,3,15000,'CRC',8],
 ['Alcohol en gel','litros','envase',1,12,2500,'CRC',2],
 ['Desinfectante','litros','bidón',5,4,6000,'CRC',3],
 ['Esquineros de cartón','unidades','paquete',50,4,10000,'CRC',40],
 ['Esquineros plásticos','unidades','paquete',50,4,15000,'CRC',30],
 ['Etiquetas','unidades','rollo',1000,3,12000,'CRC',400],
 ['Fleje','rollos','rollo',1,6,18000,'CRC',1],
 ['Grapas para cartón','unidades','caja',2000,2,16000,'CRC',250],
 ['Grapas para fleje','unidades','caja',1000,2,12000,'CRC',100],
 ['Guantes','pares','caja',50,2,15000,'CRC',12],
 ['Jabón en polvo','kg','saco',10,2,14000,'CRC',3],
 ['Jabón para manos','litros','bidón',5,3,7000,'CRC',2],
 ['Papel higiénico','rollos','paquete',12,5,6000,'CRC',8],
 ['Papel para envolver ñame','kg','paquete',10,4,9000,'CRC',5],
 ['Productos de limpieza de sanitarios','unidades','envase',1,10,3000,'CRC',2],
 ['Cartón · caja de 18 kg','cartones','cartón',1,1320,2,'USD',120],
].map(([name,unit,pack,factor,quantity,price,currency,used])=>({name,unit,pack,factor,quantity,price,currency,used}))
export function exampleTotals(row){
 const factor=Number(row.factor),quantity=Number(row.quantity),price=Number(row.price),used=Number(row.used)
 if(![factor,quantity,price,used].every(Number.isFinite)||factor<=0||quantity<=0||price<0||used<0||used>factor*quantity)return null
 const received=Math.round(factor*quantity*1000)/1000
 return {received,remaining:Math.round((received-used)*1000)/1000,total:Math.round(quantity*price*100)/100,unitPrice:price/factor,consumedCost:Math.round(used*price/factor*100)/100}
}
export const validThousandths=n=>Number.isFinite(n)&&Math.abs(n*1000-Math.round(n*1000))<0.0000001

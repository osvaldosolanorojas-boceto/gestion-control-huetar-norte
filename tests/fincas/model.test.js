import test from 'node:test'
import assert from 'node:assert/strict'
import {exampleDefaults,runFarmExample} from '../../src/farm-audit-model.js'
import {farmInvestment} from '../../src/farm-investment.js'
test('César: balance físico, ventas brutas y 30% antes de gastos',()=>{
 const r=runFarmExample({});assert.deepEqual(r.errors,[]);assert.equal(r.classifiedKg,70000);assert.equal(r.rootSalesKg+r.normalWasteKg+r.lostKg,70000);assert.equal(r.revenue,17400000);assert.equal(r.owner,5220000);assert.equal(r.net,7380000)
})
test('Víctor: 38% y tierra mecanizada no crean maquinaria propia',()=>{
 const r=runFarmExample({mode:'Mecanizada',ownerPercent:38,tractorValue:0,implementValue:0});assert.equal(r.owner,6612000);assert.equal(r.costs,3800000);assert.equal(r.net,6988000);assert.equal(r.assets,0)
})
test('Alquiler fijo y propiedad propia son modalidades distintas',()=>{
 const rented=runFarmExample({mode:'Alquilada'}),own=runFarmExample({mode:'Propia'});assert.equal(rented.owner,0);assert.equal(rented.rent,450000);assert.equal(rented.net,12150000);assert.equal(own.rent,0);assert.equal(own.net,12600000)
})
test('Pérdida de 20% reduce ventas, conserva costos y cuadra todos los kilos',()=>{
 const r=runFarmExample({lossPercent:20});assert.equal(r.revenue,13920000);assert.equal(r.owner,4176000);assert.equal(r.costs,4800000);assert.equal(r.net,4944000);assert.equal(r.rootSalesKg+r.normalWasteKg+r.lostKg,70000)
})
test('Pérdida total: el alquiler continúa y el porcentaje sin ventas es cero',()=>{
 const percent=runFarmExample({lossPercent:100}),rental=runFarmExample({lossPercent:100,mode:'Alquilada'});assert.equal(percent.revenue,0);assert.equal(percent.owner,0);assert.equal(percent.net,-4800000);assert.equal(rental.net,-5250000)
})
test('Cobros diferidos no cambian la utilidad; la CxC conserva el saldo',()=>{
 const r=runFarmExample({paidPercent:25}),full=runFarmExample({paidPercent:100});assert.equal(r.collected,4350000);assert.equal(r.receivable,13050000);assert.equal(r.net,full.net);assert.equal(full.receivable,0)
})
test('Precio agrícola 10% menor reduce resultado sin alterar costos',()=>{
 const r=runFarmExample(Object.fromEntries(['europaPrice','usaPrice','secondPrice','rejectPrice','seedPrice'].map(k=>[k,exampleDefaults[k]*0.9])));assert.equal(r.revenue,15660000);assert.equal(r.owner,4698000);assert.equal(r.net,6162000)
})
test('Cierre del cultivo separa activos del gasto de cosecha y de las CxC',()=>{
 const r=runFarmExample({});assert.equal(r.beforeHarvest,20450000);assert.equal(r.afterClosedFixedAndStock,15650000);assert.equal(r.beforeHarvest-r.afterClosedFixedAndStock,4800000)
})
test('Cantidades inconsistentes, negativos y porcentajes inválidos se rechazan',()=>{
 for(const bad of [{harvestKg:60000},{operatingCosts:-1},{paidPercent:101},{lossPercent:101},{ownerPercent:101},{mechanization:99999999},{europaQq:'texto'}])assert.ok(runFarmExample(bad).errors.length)
})
const asset=(finca_id,tipo,value,extra={})=>({finca_id,tipo,valor_actual_unitario_crc:value,cantidad:1,pertenencia:'Propio',estado:'Bueno',...extra})
test('La bodega reemplaza la valoración manual de insumos y no duplica inversión',()=>{
 const assets=[asset('f','Tractor',1000),asset('f','Insumo disponible',9999)],stocks=[{finca_id:'f',valor_crc:750},{finca_id:'otra',valor_crc:9999}]
 const r=farmInvestment('f',assets,[],[],[],stocks);assert.equal(r.supplies,750);assert.equal(r.total,1750);assert.equal(r.legacySupplies,1);assert.equal(farmInvestment('f',assets,[],[],[],[]).supplies,0)
})
test('Consumo conserva inversión: baja stock y sube costo del cultivo una sola vez',()=>{
 const lots=[{id:'l',finca_id:'f',inversion_en_curso:true}]
 const before=farmInvestment('f',[],lots,[],[],[{finca_id:'f',valor_crc:1000}]),after=farmInvestment('f',[],lots,[{lote_id:'l',monto:300}],[],[{finca_id:'f',valor_crc:700}]);assert.equal(before.total,after.total)
})
test('Gastos sin lote son visibles; no se capitalizan sin asignación',()=>{
 const costs=[{finca_id:'f',lote_id:null,monto:20000}],lots=[{id:'l',finca_id:'f',inversion_en_curso:true}]
 const general=farmInvestment('f',[],lots,costs,[],[]);assert.equal(general.unallocatedCosts,20000);assert.equal(general.unallocatedCount,1);assert.equal(general.cultivation,0)
 const assigned=farmInvestment('f',[],lots,[{...costs[0],lote_id:'l'}],[],[]);assert.equal(assigned.unallocatedCosts,0);assert.equal(assigned.cultivation,20000)
})
test('Históricos, activos ajenos, retirados y gastos excluidos no inflan el total',()=>{
 const assets=[asset('f','Tractor',1000),asset('f','Tractor',9000,{pertenencia:'De tercero'}),asset('f','Tractor',9000,{estado:'Retirado'}),asset('otra','Tractor',9000),asset('f','Implemento agrícola',null)]
 const lots=[{id:'l',finca_id:'f',inversion_en_curso:true},{id:'viejo',finca_id:'f',inversion_en_curso:false}],costs=[{lote_id:'l',monto:100},{lote_id:'l',monto:500,incluir_en_inversion:false},{lote_id:'viejo',monto:9000}]
 const r=farmInvestment('f',assets,lots,costs,[],[]);assert.equal(r.total,1100);assert.equal(r.pending,1);assert.equal(r.activeLots,1)
})
test('Traslado de activo cambia ubicación, conserva inversión empresarial',()=>{
 const a=[asset('a','Tractor',10000)],moved=[{...a[0],finca_id:'b'}]
 const total=list=>['a','b'].reduce((sum,id)=>sum+farmInvestment(id,list,[],[],[],[]).total,0);assert.equal(total(a),total(moved));assert.equal(farmInvestment('a',moved,[],[],[],[]).total,0)
})

import {test} from 'node:test'
import assert from 'node:assert/strict'
import {companyDocuments,agroReceivables} from '../src/finance-company-model.js'
import {accountCategory} from '../src/finance-categories.js'
test('Las cuentas automáticas y manuales quedan en su empresa',()=>{
 const rows=[{origen:'compra_campo',monto:500},{manual:{empresa:'exportadora'},monto:200},{manual:{empresa:'agro_solano'},monto:900}]
 assert.deepEqual(companyDocuments(rows,'exportadora'),rows.slice(0,2))
 assert.deepEqual(companyDocuments(rows,'agro_solano'),[rows[2]])
})
test('Compra propia refleja una sola cuenta por cobrar de Agrosolano con el mismo saldo',()=>{
 const rows=[{origen:'compra_campo',origen_id:'propia',monto:1000,aplicado:300},{origen:'flete_compra',origen_id:'propia',monto:200},{origen:'compra_campo',origen_id:'tercero',monto:500}]
 const result=agroReceivables(rows,[{id:'propia',proveedor_id:'agro'},{id:'tercero',proveedor_id:'externo'}],[{id:'agro',tipo:'Propio'},{id:'externo',tipo:'Productor'}])
 assert.equal(result.length,1);assert.equal(result[0].monto-result[0].aplicado,700)
 assert.equal(result[0].origen,'venta_agro_exportadora');assert.equal(rows[0].origen,'compra_campo')
})
test('Fletes se separan del producto y gastos manuales conservan su concepto',()=>{
 assert.equal(accountCategory({origen:'flete_compra',producto:'Yuca'},'payables'),'Fletes')
 assert.equal(accountCategory({origen:'compra_campo',producto:'Ñampí'},'payables'),'Ñampí')
 assert.equal(accountCategory({manual:{categoria:'Llantas'}},'payables'),'Llantas')
})

import assert from 'node:assert/strict'
import {weeklyTotals,weeklyResult} from '../src/weekly-model.js'
const original=684782.61
// Unsold carry-over cancels purchase expense for this stock in its origin week.
assert.equal(weeklyResult(weeklyTotals({purchases:[{monto_cxp:original}],inventory:{opening:0,closing:original}})).CRC.expense,0)
// Next week carries the same cost, without another purchase or payable.
assert.equal(weeklyResult(weeklyTotals({inventory:{opening:original,closing:original}})).CRC.expense,0)
// A selection loss is borne by the packer when the stock value falls.
assert.equal(weeklyResult(weeklyTotals({inventory:{opening:10000,closing:9000}})).CRC.expense,1000)
// Extra processing spend is recorded once; the portion still in stock is retained.
assert.equal(weeklyResult(weeklyTotals({inventory:{opening:10000,closing:10800},costs:[{moneda:'CRC',monto:1000,categoria:'otros'}]})).CRC.expense,200)
// A dispatched order consumes stock cost and recognizes its own sale.
assert.equal(weeklyResult(weeklyTotals({sales:[{moneda:'CRC',mercado:'Costa Rica',monto_cxc:12000}],inventory:{opening:10000,closing:0}})).CRC.result,2000)
// Liquidated local sales of carry-over are included, by their own currency.
assert.equal(weeklyResult(weeklyTotals({saldoSales:[{moneda:'CRC',kg_primera:46,precio_final_qq:18500}]})).CRC.income,18500)
console.log('6 comprobaciones de costo, arrastre, pérdida y venta: OK')

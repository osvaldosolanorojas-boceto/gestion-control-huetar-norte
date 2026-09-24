import React,{useEffect,useState} from 'react'
import {supabase} from './supabase'
import {cash} from './finance'

export default function Companies({go}){
  const [data,setData]=useState({accounts:[],balances:{},moves:[],farms:[],lots:[],costs:[],own:[],payables:[],transfers:[]})
  const [loading,setLoading]=useState(true),[error,setError]=useState('')
  useEffect(()=>{let active=true;Promise.all([
    supabase.from('cuentas_bancarias').select('id,banco,moneda,saldo_inicial,saldo_confirmado,empresa'),
    supabase.from('saldos_movimientos_bancarios').select('cuenta_id,neto'),
    supabase.from('fincas').select('id,nombre'),supabase.from('lotes_finca').select('id,finca_id,nombre,anio'),
    supabase.from('costos_finca').select('lote_id,monto,categoria,fecha'),
    supabase.from('ordenes_compra').select('id,codigo,fecha,finca_lote_id,proveedor_id,productor_nombre').not('finca_lote_id','is',null).neq('estado','Anulada'),
    supabase.from('cxp_operativa').select('origen,origen_id,monto,aplicado').eq('origen','compra_campo'),
    supabase.from('transferencias_entre_empresas').select('id,orden_compra_id,monto,fecha').order('fecha',{ascending:false}).limit(100)
  ]).then(results=>{if(!active)return;setLoading(false);const failed=results.find(r=>r.error);if(failed){setError(`No se pudo cargar el resumen de empresas: ${failed.error.message}`);return}const [a,b,c,d,e,f,g,h]=results.map(r=>r.data||[]);setData({accounts:a,balances:Object.fromEntries(b.map(x=>[x.cuenta_id,Number(x.neto)])),farms:c,lots:d,costs:e,own:f,payables:g,transfers:h})});return()=>{active=false}},[])
  const ownIds=new Set(data.own.map(o=>o.id))
  const ownRevenue=data.payables.filter(p=>ownIds.has(p.origen_id)).reduce((sum,p)=>sum+Number(p.monto),0)
  const ownPaid=data.payables.filter(p=>ownIds.has(p.origen_id)).reduce((sum,p)=>sum+Number(p.aplicado),0)
  const farmCosts=data.costs.reduce((sum,c)=>sum+Number(c.monto),0)
  const supplies=data.costs.filter(c=>c.categoria==='Insumos').reduce((sum,c)=>sum+Number(c.monto),0)
  const accounts=company=>data.accounts.filter(a=>a.empresa===company)
  const balances=(company,currency='CRC')=>accounts(company).filter(a=>a.moneda===currency).reduce((sum,a)=>sum+(a.saldo_confirmado?Number(a.saldo_inicial||0):0)+Number(data.balances[a.id]||0),0)
  return <><div className="modulebar"><p>Control separado de la exportadora y Agro Solano. Los pagos entre sociedades se registran en ambas cuentas.</p></div>{error&&<div className="formerror">{error}</div>}
    {loading?<div className="empty">Cargando empresas…</div>:<div className="module-hub company-hub">
      <section className="panel"><h2>Raíces y Tubérculos Huetar Norte S.A.</h2><p>Exportadora · compras, ventas y bancos</p><strong>Saldo CRC: {cash(balances('exportadora'))} · Saldo USD: {cash(balances('exportadora','USD'),'USD')}</strong><p>{accounts('exportadora').length} cuentas bancarias y cajas</p><div className="finance-links"><button onClick={()=>go('Finanzas')}>Finanzas</button><button onClick={()=>go('Bancos')}>Bancos</button></div></section>
      <section className="panel"><h2>Agro Solano</h2><p>Agrícola · fincas, lotes y producción propia</p><strong>Saldo CRC: {cash(balances('agro_solano'))} · Saldo USD: {cash(balances('agro_solano','USD'),'USD')}</strong><p>Producto reconocido por exportadora: {cash(ownRevenue)} · Aplicado a compras: {cash(ownPaid)}</p><p>Costos registrados por finca: {cash(farmCosts)} · Insumos: {cash(supplies)}</p><div className="finance-links"><button onClick={()=>go('Fincas')}>Fincas y lotes</button><button onClick={()=>go('Bancos Agro Solano')}>Bancos</button><button onClick={()=>go('Efectivo Agro Solano')}>Efectivo</button></div></section>
    </div>}
    {!loading&&<section className="workers-panel"><h3>Pagos entre sociedades</h3>{data.transfers.map(t=>{const order=data.own.find(o=>o.id===t.orden_compra_id);return <article key={t.id}><div><b>{t.fecha} · {order?.codigo||'Compra propia'}</b><span>Exportadora → Agro Solano</span></div><strong>{cash(t.monto)}</strong></article>})}{!data.transfers.length&&<p>Sin transferencias registradas todavía.</p>}</section>}
    {!loading&&<section className="workers-panel"><h3>Fincas y lotes de Agro Solano</h3>{data.farms.map(farm=><article key={farm.id}><div><b>{farm.nombre}</b><span>{data.lots.filter(l=>l.finca_id===farm.id).map(l=>`${l.anio} · ${l.nombre}`).join(' · ')||'Sin lotes'}</span></div></article>)}{!data.farms.length&&<p>Registre las fincas en Fincas y lotes.</p>}</section>}
  </>
}

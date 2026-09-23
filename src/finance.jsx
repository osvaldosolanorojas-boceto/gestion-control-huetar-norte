import React,{useEffect,useState} from 'react'
import {Plus,X} from 'lucide-react'
import {supabase} from './supabase'

export const cash=(value,currency='CRC')=>new Intl.NumberFormat('es-CR',{style:'currency',currency,maximumFractionDigits:2}).format(Number(value)||0)
const parse=value=>Number(String(value??'').replace(',','.'))
const today=()=>{const d=new Date(),pad=n=>String(n).padStart(2,'0');return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`}
const blank=()=>({cuenta_id:'',fecha:today(),tipo:'ingreso',monto:'',concepto:'',referencia:'',aplicaciones:[]})
const key=row=>`${row.origen}:${row.origen_id}`
export function useFinance(){
  const [data,setData]=useState({accounts:[],moves:[],receivables:[],payables:[],applications:[]}),[error,setError]=useState(''),[loading,setLoading]=useState(true)
  const reload=async()=>{
    const requests=[supabase.from('cuentas_bancarias').select('*').order('banco'),supabase.from('movimientos_bancarios').select('*').order('fecha',{ascending:false}).limit(500),supabase.from('cxc_operativa').select('*').order('fecha',{ascending:false}),supabase.from('cxp_operativa').select('*').order('fecha',{ascending:false}),supabase.from('aplicaciones_bancarias').select('*').order('creado_en',{ascending:false}).limit(1000)]
    const [a,b,c,d,e]=await Promise.all(requests)
    setLoading(false)
    if(a.error||b.error||c.error||d.error||e.error){setError(`No se pudieron cargar las finanzas: ${(a.error||b.error||c.error||d.error||e.error).message}`);return}
    setError('');setData({accounts:a.data||[],moves:b.data||[],receivables:c.data||[],payables:d.data||[],applications:e.data||[]})
  }
  useEffect(()=>{reload()},[])
  return {data,error,loading,reload}
}
export default function Finance({section,go}){
  const {data,error,loading,reload}=useFinance(),[editing,setEditing]=useState(null),[form,setForm]=useState(blank),[initial,setInitial]=useState(null),[saving,setSaving]=useState(false),[formError,setFormError]=useState('')
  const availableDocs=form.tipo==='ingreso'?data.receivables:data.payables
  const docs=availableDocs.filter(row=>row.moneda===data.accounts.find(a=>a.id===form.cuenta_id)?.moneda&&Number(row.monto)-Number(row.aplicado)>0&&row.etapa!=='Faltan precios')
  const open=account=>{setForm({...blank(),cuenta_id:account?.id||data.accounts[0]?.id||''});setEditing('movement');setFormError('')}
  const saveInitial=async()=>{
    const amount=parse(initial.value)
    if(!Number.isFinite(amount)){setFormError('Indique un saldo inicial válido.');return}
    setSaving(true);const {error:e}=await supabase.from('cuentas_bancarias').update({saldo_inicial:amount,saldo_confirmado:true}).eq('id',initial.id).select('id').single();setSaving(false)
    if(e){setFormError(e.message);return}setInitial(null);setFormError('');reload()
  }
  const saveMove=async()=>{
    const amount=parse(form.monto)
    if(!form.cuenta_id||!form.fecha||!form.concepto.trim()||!Number.isFinite(amount)||amount<=0||Math.round(amount*100)!==amount*100){setFormError('Seleccione cuenta y complete fecha, concepto y monto positivo.');return}
    const apps=form.aplicaciones.map(x=>({...x,monto:parse(x.monto)}))
    if(apps.some(x=>!Number.isFinite(x.monto)||x.monto<=0)||apps.reduce((sum,x)=>sum+x.monto,0)>amount+0.001){setFormError('Revise las aplicaciones: su suma no puede superar el movimiento.');return}
    setSaving(true);setFormError('')
    const {error:e}=await supabase.rpc('registrar_movimiento_bancario',{p_cuenta_id:form.cuenta_id,p_fecha:form.fecha,p_tipo:form.tipo,p_monto:amount,p_concepto:form.concepto.trim(),p_referencia:form.referencia.trim()||null,p_aplicaciones:apps})
    setSaving(false);if(e){setFormError(`No se pudo registrar: ${e.message}`);return}setEditing(null);reload()
  }
  const toggleDoc=row=>setForm(f=>{
    const current=f.aplicaciones.filter(x=>!(x.origen===row.origen&&x.origen_id===row.origen_id))
    if(current.length<f.aplicaciones.length)return {...f,aplicaciones:current}
    const amount=Math.max(0,Math.min(Number(row.monto)-Number(row.aplicado),parse(f.monto)||0))
    return {...f,aplicaciones:[...current,{origen:row.origen,origen_id:row.origen_id,monto:String(amount)}]}
  })
  const updateApplication=(row,value)=>setForm(f=>({...f,aplicaciones:f.aplicaciones.map(x=>x.origen===row.origen&&x.origen_id===row.origen_id?{...x,monto:value}:x)}))
  if(loading)return <div className="empty">Cargando finanzas…</div>
  if(error)return <div className="formerror">{error}</div>
  const kind=section==='Cuentas por cobrar'?'receivables':section==='Cuentas por pagar'?'payables':null
  return <><div className="modulebar"><p>{kind?'Saldos derivados de pedidos y rendimientos. “Previsto” y “estimado” todavía requieren factura o liquidación para ser definitivos.':'Registre los saldos iniciales y cada depósito o pago real. Un movimiento puede aplicarse a varios pedidos o compras.'}</p>{!kind&&<button className="primary" onClick={()=>open()}><Plus size={18}/>Nuevo movimiento</button>}</div>
    {kind?<><div className="finance-summary">{['CRC','USD'].map(currency=><article key={currency}><span>Saldo calculable {currency}</span><strong>{cash(data[kind].filter(r=>r.moneda===currency&&r.etapa!=='Faltan precios').reduce((sum,r)=>sum+Math.max(0,Number(r.monto)-Number(r.aplicado)),0),currency)}</strong></article>)}</div><div className="workers-panel"><h3>{section}</h3>{data[kind].map(r=><article key={key(r)}><div><b>{r.codigo} · {r.contraparte}</b><span>{r.fecha} · {r.etapa} · {r.etapa==='Faltan precios'?'Subtotal parcial':'Total'} {cash(r.monto,r.moneda)} · Aplicado {cash(r.aplicado,r.moneda)}</span></div><strong>{r.etapa==='Faltan precios'?'Completar precios':cash(Math.max(0,Number(r.monto)-Number(r.aplicado)),r.moneda)}</strong></article>)}{!data[kind].length&&<p>No hay registros con importe todavía.</p>}</div><button className="primary" onClick={()=>go('Bancos')}>Registrar cobro o pago en Bancos</button></>:<><div className="finance-summary">{data.accounts.map(a=>{const balance=Number(a.saldo_inicial)+data.moves.filter(m=>m.cuenta_id===a.id).reduce((sum,m)=>sum+(m.tipo==='ingreso'?1:-1)*Number(m.monto),0);return <article key={a.id}><span>{a.banco} · {a.moneda}</span><strong>{a.saldo_confirmado?cash(balance,a.moneda):'Saldo inicial pendiente'}</strong><small>{a.saldo_confirmado?`Saldo inicial ${cash(a.saldo_inicial,a.moneda)}`:'Confirme el saldo del banco antes de conciliar'}</small><div><button onClick={()=>{setInitial({id:a.id,value:String(a.saldo_inicial),name:a.banco,currency:a.moneda});setFormError('')}}>Saldo inicial</button><button onClick={()=>open(a)}>Movimiento</button></div></article>})}</div><div className="workers-panel"><h3>Movimientos bancarios</h3>{data.moves.map(m=>{const a=data.accounts.find(x=>x.id===m.cuenta_id),links=data.applications.filter(x=>x.movimiento_id===m.id);return <article key={m.id}><div><b>{m.fecha} · {m.concepto}</b><span>{a?.banco} · {a?.moneda}{m.referencia?` · ${m.referencia}`:''} · {links.length} aplicación(es)</span></div><strong className={m.tipo==='egreso'?'finance-out':''}>{m.tipo==='egreso'?'-':'+'}{cash(m.monto,a?.moneda||'CRC')}</strong></article>})}{!data.moves.length&&<p>Todavía no hay depósitos ni pagos registrados.</p>}</div></>}
    {initial&&<div className="modalwrap"><div className="modal carton-modal"><div className="modalhead"><h2>Saldo inicial · {initial.name} ({initial.currency})</h2><button onClick={()=>setInitial(null)}><X/></button></div><div className="formgrid"><label className="wide">Saldo confirmado por el banco<input type="number" step="0.01" inputMode="decimal" value={initial.value} onChange={e=>setInitial({...initial,value:e.target.value})}/></label></div><p className="plant-help">Registre aquí el saldo con que comienza el control. Los movimientos posteriores se suman o restan automáticamente.</p>{formError&&<div className="formerror">{formError}</div>}<div className="modalactions"><button onClick={()=>setInitial(null)}>Cancelar</button><button className="primary" disabled={saving} onClick={saveInitial}>Guardar saldo</button></div></div></div>}
    {editing&&<div className="modalwrap"><div className="modal plant-form finance-modal"><div className="modalhead"><div><span>BANCO</span><h2>Registrar {form.tipo==='ingreso'?'depósito o cobro':'pago o egreso'}</h2></div><button onClick={()=>setEditing(null)}><X/></button></div><div className="formgrid"><label>Cuenta<select value={form.cuenta_id} onChange={e=>setForm({...form,cuenta_id:e.target.value,aplicaciones:[]})}>{data.accounts.map(a=><option key={a.id} value={a.id}>{a.banco} · {a.moneda}</option>)}</select></label><label>Tipo<select value={form.tipo} onChange={e=>setForm({...form,tipo:e.target.value,aplicaciones:[]})}><option value="ingreso">Ingreso / depósito</option><option value="egreso">Egreso / pago</option></select></label><label>Fecha<input type="date" value={form.fecha} onChange={e=>setForm({...form,fecha:e.target.value})}/></label><label>Monto<input type="number" min="0.01" step="0.01" inputMode="decimal" value={form.monto} onChange={e=>setForm({...form,monto:e.target.value})}/></label><label className="wide">Concepto<input value={form.concepto} onChange={e=>setForm({...form,concepto:e.target.value})} placeholder="Ejemplo: depósito de cliente"/></label><label className="wide">Referencia bancaria<input value={form.referencia} onChange={e=>setForm({...form,referencia:e.target.value})}/></label></div><section className="finance-docs"><h3>Aplicar a {form.tipo==='ingreso'?'cuentas por cobrar':'cuentas por pagar'} (opcional)</h3><p>Puede repartir un depósito o pago entre varios documentos. También puede dejarlo sin aplicar y conciliarlo después.</p>{docs.map(row=>{const selected=form.aplicaciones.find(x=>x.origen===row.origen&&x.origen_id===row.origen_id);return <div key={key(row)}><label><input type="checkbox" checked={!!selected} onChange={()=>toggleDoc(row)}/>{row.codigo} · {row.contraparte} · saldo {cash(Number(row.monto)-Number(row.aplicado),row.moneda)}</label>{selected&&<input aria-label={`Aplicar a ${row.codigo}`} type="number" min="0.01" step="0.01" inputMode="decimal" value={selected.monto} onChange={e=>updateApplication(row,e.target.value)}/>}</div>})}{!docs.length&&<p>No hay documentos con saldo en la moneda de esta cuenta.</p>}</section>{formError&&<div className="formerror">{formError}</div>}<div className="modalactions"><button disabled={saving} onClick={()=>setEditing(null)}>Cancelar</button><button className="primary" disabled={saving} onClick={saveMove}>{saving?'Guardando…':'Registrar movimiento'}</button></div></div></div>}</>
}

import React,{useEffect,useState} from 'react'
import {supabase} from './supabase'
import {isoWeek} from './weekly-model'
import {europeYucaProgress} from './europe-yuca-model'
const fmt=n=>Number(n).toLocaleString('es-CR',{maximumFractionDigits:0})
export default function EuropeYuca({start,end,refresh,onProgress}){
 const [progress,setProgress]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(true),[retry,setRetry]=useState(0)
 useEffect(()=>{let active=true;const load=async()=>{setLoading(true);onProgress?.(null);try{
  const orders=await supabase.from('ordenes_venta').select('id').eq('mercado','Europa').neq('estado','Anulada').gte('fecha_salida',start).lte('fecha_salida',end).limit(1000)
  if(orders.error)throw orders.error
  if(orders.data.length>=1000)throw new Error('Hay demasiados pedidos para un conteo completo.')
  let lines=[],assignments=[]
  if(orders.data.length){const l=await supabase.from('ordenes_venta_lineas').select('id,cantidad_cajas').in('orden_venta_id',orders.data.map(o=>o.id)).eq('producto','Yuca').eq('presentacion_kg',18).limit(1000);if(l.error)throw l.error;if(l.data.length>=1000)throw new Error('Hay demasiadas líneas para un conteo completo.');lines=l.data}
  if(lines.length){const a=await supabase.from('boleta_rendimientos').select('id,orden_venta_linea_id,cajas').in('orden_venta_linea_id',lines.map(l=>l.id)).limit(1000);if(a.error)throw a.error;if(a.data.length>=1000)throw new Error('Hay demasiadas partidas para un conteo completo.');assignments=a.data}
  const result=europeYucaProgress(lines,assignments);if(active){setProgress(result);onProgress?.(result);setError('')}
 }catch(e){if(active)setError(`No se pudo calcular el faltante: ${e.message}`)}finally{if(active)setLoading(false)}};load();return()=>{active=false}},[start,end,refresh,retry,onProgress])
 // Relee boletas guardadas por otros usuarios; el cálculo nunca usa cantidades locales sin guardar.
 useEffect(()=>{const timer=setInterval(()=>{if(document.visibilityState==='visible')setRetry(r=>r+1)},60000);const focus=()=>setRetry(r=>r+1);window.addEventListener('focus',focus);return()=>{clearInterval(timer);window.removeEventListener('focus',focus)}},[])
 return <section className="panel europe-yuca"><div className="panelhead"><div><h3>Yuca Europa · cajas de 18 kg · semana {isoWeek(start).week}</h3><p>Guía rápida de lo que falta completar para los pedidos de la semana</p></div><button type="button" disabled={loading} onClick={()=>setRetry(r=>r+1)}>Actualizar conteo</button></div>{loading?<p className="yuca-count-message">Actualizando conteo…</p>:error?<div className="formerror">{error}</div>:progress&&<><div className="yuca-counts"><article><span>Total pedido</span><strong>{fmt(progress.required)}</strong><small>cajas de 18 kg</small></article><article><span>Completadas desde planta</span><strong>{fmt(progress.completed)}</strong><small>cajas asignadas a estos pedidos</small></article><article className="yuca-pending"><span>Faltan para Europa</span><strong>{fmt(progress.pending)}</strong><small>equivalente en cajas de 18 kg</small></article></div><div className="yuca-progress" role="progressbar" aria-label="Avance yuca Europa" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(progress.percent)}><div style={{width:`${progress.percent}%`}}/></div><p className="yuca-count-message">{Math.round(progress.percent)}% completado.{progress.excess?` Hay ${fmt(progress.excess)} cajas asignadas por encima del total pedido; revise las boletas.`:progress.required&&progress.pending===0?' Pedido semanal de yuca Europa de 18 kg completo.':''} El faltante baja al guardar más cajas para estos pedidos. Incluye pedidos abiertos y finalizados; excluye anulados. La yuca en planta sin rendimiento asignado aún no se descuenta.</p></>}</section>
}

import React,{useEffect,useState} from 'react'
import {supabase} from './supabase'
export default function BccrRate({children}){
 const [rate,setRate]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(true)
 const refresh=async()=>{setLoading(true);const {data,error:e}=await supabase.functions.invoke('bccr-rate');setLoading(false);if(e||data?.error){setError('No se pudo consultar el BCCR.');return}setRate(data);setError('')}
 useEffect(()=>{refresh();const timer=setInterval(refresh,30*60*1000);return()=>clearInterval(timer)},[])
 const fmt=n=>Number(n).toLocaleString('es-CR',{minimumFractionDigits:2,maximumFractionDigits:2})
 return <div className="exchange"><span>BCCR · USD / CRC</span>{rate?<><b>Compra ₡{fmt(rate.compra)}</b><small>Venta ₡{fmt(rate.venta)} · {rate.fecha}</small>{error&&<small role="alert">{error} Última consulta disponible.</small>}</>:<small>{loading?'Consultando BCCR…':error}</small>}<button type="button" disabled={loading} onClick={refresh}>{loading?'Consultando…':'Actualizar BCCR'}</button><details><summary>Tasa manual de trabajo</summary>{children}</details></div>
}

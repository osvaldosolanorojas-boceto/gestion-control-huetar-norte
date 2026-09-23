-- El cierre conserva la boleta y fija el monto por pagar de esa recepción.
alter table public.boletas_entrada add column finalizada_en timestamptz;
alter table public.boletas_entrada add column monto_cxp numeric(16,2) check (monto_cxp >= 0);
alter table public.boletas_entrada add column finalizada_por uuid references public.perfiles(id);

create function public.bloquear_boleta_finalizada() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_table_name='boletas_entrada' then
    if tg_op='DELETE' and old.finalizada_en is not null then raise exception 'La boleta finalizada no se puede eliminar'; end if;
    if tg_op='UPDATE' and old.finalizada_en is not null then raise exception 'La boleta finalizada no se puede modificar'; end if;
  elsif exists(select 1 from public.boletas_entrada b where b.id=case when tg_op='DELETE' then old.boleta_id else new.boleta_id end and b.finalizada_en is not null) then
    raise exception 'Los rendimientos de una boleta finalizada no se pueden modificar';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
create trigger bloquear_cierre_boleta before update or delete on public.boletas_entrada for each row execute function public.bloquear_boleta_finalizada();
create trigger bloquear_cierre_rendimiento before insert or update or delete on public.boleta_rendimientos for each row execute function public.bloquear_boleta_finalizada();

create function public.finalizar_boleta_entrada(p_boleta_id uuid) returns numeric
language plpgsql security definer set search_path='' as $$
declare v_b public.boletas_entrada%rowtype; v_o public.ordenes_compra%rowtype; v_r record; v_price numeric; v_amount numeric:=0;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then raise exception 'Solo administración u oficina puede finalizar boletas'; end if;
  select * into v_b from public.boletas_entrada where id=p_boleta_id for update;
  if not found then raise exception 'No se encontró la boleta'; end if;
  if v_b.finalizada_en is not null then raise exception 'Esta boleta ya está finalizada'; end if;
  if v_b.orden_compra_id is null then raise exception 'Enlace la orden de compra antes de finalizar'; end if;
  select * into v_o from public.ordenes_compra where id=v_b.orden_compra_id for update;
  if v_b.fin_proceso is null then raise exception 'Registre el final del proceso antes de finalizar'; end if;
  if not exists(select 1 from public.boleta_rendimientos where boleta_id=p_boleta_id) then raise exception 'Registre al menos un rendimiento antes de finalizar'; end if;
  if v_o.tipo_compra='En pie' then
    if v_o.precio_en_pie is null or v_o.precio_en_pie<=0 then raise exception 'Falta el precio de compra en pie'; end if;
    if exists(select 1 from public.boletas_entrada where orden_compra_id=v_o.id and finalizada_en is not null) then
      raise exception 'Esta compra en pie ya tiene una boleta cerrada; revise su liquidación';
    end if;
    v_amount:=v_o.precio_en_pie;
  else
    for v_r in select calidad,kg_resultado,paga_productor from public.boleta_rendimientos where boleta_id=p_boleta_id loop
      if v_r.paga_productor then
        if coalesce(v_r.kg_resultado,0)<=0 then raise exception 'Falta el peso de una partida que se paga al productor'; end if;
        v_price:=case when v_r.calidad='Exportable Europa' then v_o.precio_europa
          when v_r.calidad='Exportable estadounidense' then v_o.precio_eeuu
          when v_r.calidad='Segunda gruesa' then v_o.precio_segunda_gruesa
          when v_r.calidad='Segunda menuda' then v_o.precio_segunda_menuda
          when v_r.calidad like 'Rechazo%' then v_o.precio_rechazo
          else v_o.precio_campo end;
        if v_price is null then raise exception 'Falta el precio de % en la orden de compra',v_r.calidad; end if;
        v_amount:=v_amount+v_r.kg_resultado/46*v_price;
      end if;
    end loop;
  end if;
  update public.boletas_entrada set finalizada_en=now(),finalizada_por=(select auth.uid()),monto_cxp=round(v_amount,2) where id=p_boleta_id;
  return round(v_amount,2);
end;
$$;
revoke all on function public.finalizar_boleta_entrada(uuid) from public,anon;
grant execute on function public.finalizar_boleta_entrada(uuid) to authenticated;

-- La cuenta por pagar nace al cerrar la boleta y se suma por orden de compra.
create or replace view public.cxp_operativa with (security_invoker=true) as
select 'compra_campo'::text origen,o.id origen_id,o.codigo,o.fecha,
  coalesce(o.productor_nombre,p.nombre,'Productor pendiente') contraparte,'CRC'::text moneda,
  coalesce(sum(b.monto_cxp),0)::numeric(16,2) monto,
  coalesce((select sum(a.monto) from public.aplicaciones_bancarias a where a.origen='compra_campo' and a.origen_id=o.id),0)::numeric(16,2) aplicado,
  'Boleta finalizada'::text etapa
from public.ordenes_compra o join public.boletas_entrada b on b.orden_compra_id=o.id and b.finalizada_en is not null
left join public.proveedores p on p.id=o.proveedor_id
group by o.id,o.codigo,o.fecha,o.productor_nombre,p.nombre;

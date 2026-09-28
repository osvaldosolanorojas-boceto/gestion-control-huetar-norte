-- Una compra con dinero adelantado debe conservarse para poder reclamarlo.
create or replace function public.anular_orden_compra(p_orden_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_o public.ordenes_compra%rowtype;
begin
  if not exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')) then
    raise exception 'Solo administración u oficina puede anular compras';
  end if;
  select * into v_o from public.ordenes_compra where id=p_orden_id for update;
  if not found then raise exception 'No se encontró la orden de compra'; end if;
  if v_o.estado='Anulada' then raise exception 'La orden ya está anulada'; end if;
  if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=p_orden_id) then
    raise exception 'La compra tiene boletas; no puede anularla';
  end if;
  if exists(select 1 from public.adelantos_compra a where a.orden_compra_id=p_orden_id) then
    raise exception 'La compra tiene adelantos pagados; conserve la orden y gestione el cobro al productor';
  end if;
  if exists(select 1 from public.aplicaciones_bancarias a where a.origen in ('compra_campo','flete_compra') and a.origen_id=p_orden_id) then
    raise exception 'La compra tiene pagos aplicados; no puede anularla';
  end if;
  update public.ordenes_compra set estado='Anulada',anulada_en=now(),anulada_por=(select auth.uid()) where id=p_orden_id;
end;
$$;
revoke all on function public.anular_orden_compra(uuid) from public,anon;
grant execute on function public.anular_orden_compra(uuid) to authenticated;

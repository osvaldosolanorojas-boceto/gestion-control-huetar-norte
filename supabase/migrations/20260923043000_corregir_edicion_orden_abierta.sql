-- Las órdenes abiertas conservan los valores nuevos; las selladas siguen bloqueadas.
create or replace function public.proteger_orden_compra_cerrada() returns trigger language plpgsql set search_path='' as $$
begin
  if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=old.id and b.finalizada_en is not null)
    and not exists(select 1 from public.boletas_entrada b where b.orden_compra_id=old.id and b.finalizada_en is null) then
    raise exception 'La orden de compra tiene todas sus boletas finalizadas y está sellada';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

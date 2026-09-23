-- Una orden con todas sus boletas finalizadas queda sellada.
create function public.proteger_orden_compra_cerrada() returns trigger language plpgsql set search_path='' as $$
begin
  if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=old.id and b.finalizada_en is not null)
    and not exists(select 1 from public.boletas_entrada b where b.orden_compra_id=old.id and b.finalizada_en is null) then
    raise exception 'La orden de compra tiene todas sus boletas finalizadas y está sellada';
  end if;
  return old;
end;
$$;
create trigger proteger_orden_compra before update or delete on public.ordenes_compra for each row execute function public.proteger_orden_compra_cerrada();
create function public.proteger_nuevas_boletas_compra_cerrada() returns trigger language plpgsql set search_path='' as $$
begin
  if exists(select 1 from public.boletas_entrada b where b.orden_compra_id=new.orden_compra_id and b.finalizada_en is not null)
    and not exists(select 1 from public.boletas_entrada b where b.orden_compra_id=new.orden_compra_id and b.finalizada_en is null) then
    raise exception 'La orden de compra está sellada; no puede agregar nuevas boletas';
  end if;
  return new;
end;
$$;
create trigger proteger_nueva_boleta_compra before insert on public.boletas_entrada for each row execute function public.proteger_nuevas_boletas_compra_cerrada();

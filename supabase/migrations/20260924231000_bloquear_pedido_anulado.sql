-- Impide reabrir, finalizar o asignar producción a una venta cancelada.
create function public.bloquear_venta_anulada() returns trigger language plpgsql set search_path='' as $$
begin
  if old.estado='Anulada' then raise exception 'La orden de venta anulada no se puede modificar'; end if;
  return new;
end;
$$;
create trigger bloquear_venta_anulada before update on public.ordenes_venta
for each row execute function public.bloquear_venta_anulada();
revoke all on function public.bloquear_venta_anulada() from public,anon,authenticated;

create function public.impedir_asignacion_venta_anulada() returns trigger language plpgsql set search_path='' as $$
begin
  if new.orden_venta_linea_id is not null and exists(
    select 1 from public.ordenes_venta_lineas l join public.ordenes_venta v on v.id=l.orden_venta_id
    where l.id=new.orden_venta_linea_id and v.estado='Anulada'
  ) then raise exception 'La orden de venta está anulada; no se le pueden asignar cajas'; end if;
  return new;
end;
$$;
create trigger impedir_asignacion_venta_anulada before insert or update of orden_venta_linea_id
on public.boleta_rendimientos for each row execute function public.impedir_asignacion_venta_anulada();
revoke all on function public.impedir_asignacion_venta_anulada() from public,anon,authenticated;

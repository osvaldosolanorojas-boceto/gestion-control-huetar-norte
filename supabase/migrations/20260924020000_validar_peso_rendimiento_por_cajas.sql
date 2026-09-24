-- Los kilos manuales representan el total solo cuando no se cuentan cajas.
-- Los registros anteriores no se recalculan automáticamente; requieren revisión individual.
create function public.validar_kilos_manual_rendimiento() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if new.cajas>0 and new.kg_manual is not null then
    raise exception 'Si anota cajas, deje en blanco los kilos totales medidos; el peso se calcula con cajas por peso por caja';
  end if;
  return new;
end;
$$;
create trigger validar_kilos_manual_rendimiento
before insert or update of cajas,kg_manual on public.boleta_rendimientos
for each row execute function public.validar_kilos_manual_rendimiento();

-- An audited, additive correction for a finalized ñampí receipt. Existing
-- first-grade allocations and the fixed purchase amount are left intact.
create table if not exists public.correcciones_merma_boleta (
  id uuid primary key default gen_random_uuid(),
  boleta_id uuid not null references public.boletas_entrada(id),
  rendimiento_id uuid not null references public.boleta_rendimientos(id),
  kg numeric(14,2) not null check (kg>0),
  motivo text not null,
  creado_por uuid not null references auth.users(id),
  creado_en timestamptz not null default now()
);
alter table public.correcciones_merma_boleta enable row level security;
create policy correcciones_merma_administrador on public.correcciones_merma_boleta
  for select to authenticated using (exists (
    select 1 from public.perfiles p where p.id=(select auth.uid())
    and p.activo and p.rol='administrador'
  ));

create or replace function public.registrar_descarte_nampi_finalizada(
  p_boleta_id uuid,p_kg numeric,p_motivo text
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_b public.boletas_entrada%rowtype; v_kg numeric; v_new uuid;
begin
  if not exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador') then
    raise exception 'Solo administración puede corregir una boleta finalizada';
  end if;
  select * into v_b from public.boletas_entrada where id=p_boleta_id for update;
  if not found or v_b.finalizada_en is null or v_b.producto not in ('Ñampí','Cabeza de ñampí') then
    raise exception 'Seleccione una boleta de ñampí finalizada';
  end if;
  if p_motivo is null or length(btrim(p_motivo))<15 then raise exception 'Describa la causa o indique expresamente que aún no fue medida'; end if;
  select coalesce(sum(r.kg_resultado),0) into v_kg from public.boleta_rendimientos r where r.boleta_id=p_boleta_id;
  if p_kg is null or p_kg<=0 or round(p_kg,2)<>round(v_b.kg_estimados-v_kg,2) then
    raise exception 'El descarte debe cuadrar exactamente con la diferencia actual (% kg)',round(v_b.kg_estimados-v_kg,2);
  end if;
  perform set_config('app.corrigiendo_boleta','completa',true);
  insert into public.boleta_rendimientos(boleta_id,producto,calidad,cajas,kg_manual,paga_productor,observaciones,codigo_trazabilidad)
    values(p_boleta_id,v_b.producto,'Desperdicio',0,round(p_kg,2),false,btrim(p_motivo),v_b.codigo)
    returning id into v_new;
  update public.boletas_entrada set observaciones=concat_ws(E'\n',nullif(observaciones,''),
    'CORRECCIÓN DE EJERCICIO: '||round(p_kg,2)||' kg clasificados como descarte. '||btrim(p_motivo))
    where id=p_boleta_id;
  insert into public.correcciones_merma_boleta(boleta_id,rendimiento_id,kg,motivo,creado_por)
    values(p_boleta_id,v_new,round(p_kg,2),btrim(p_motivo),(select auth.uid()));
  return v_new;
end;
$$;
revoke all on function public.registrar_descarte_nampi_finalizada(uuid,numeric,text) from public,anon;
grant execute on function public.registrar_descarte_nampi_finalizada(uuid,numeric,text) to authenticated;

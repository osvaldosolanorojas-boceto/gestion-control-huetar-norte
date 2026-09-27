create table if not exists public.tasas_corte_semanal (
 semana_inicio date primary key,
 usd_crc numeric(12,4) not null check(usd_crc>0),
 fuente text not null,
 simulado boolean not null default true,
 actualizado_en timestamptz not null default now()
);
alter table public.tasas_corte_semanal enable row level security;
revoke all on public.tasas_corte_semanal from anon,authenticated;
grant select,insert,update on public.tasas_corte_semanal to authenticated;
drop policy if exists oficina_tasas_corte on public.tasas_corte_semanal;
create policy oficina_tasas_corte on public.tasas_corte_semanal for all to authenticated
 using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
 with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
insert into public.tasas_corte_semanal(semana_inicio,usd_crc,fuente,simulado)
 values ('2026-09-06',440,'SIMULADO: valor de trabajo para ejercicio',true),
        ('2026-09-13',440,'SIMULADO: valor de trabajo para ejercicio',true),
        ('2026-09-20',440,'SIMULADO: valor de trabajo para ejercicio',true),
        ('2026-09-27',440,'SIMULADO: valor de trabajo para ejercicio',true)
on conflict(semana_inicio) do nothing;

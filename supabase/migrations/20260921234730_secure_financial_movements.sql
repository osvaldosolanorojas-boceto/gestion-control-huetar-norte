revoke all on public.movimientos_financieros from anon, authenticated;
grant select, insert, update, delete on public.movimientos_financieros to authenticated;

create policy gestion_oficina
on public.movimientos_financieros
for all
to authenticated
using (
  exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid())
      and p.activo
      and p.rol in ('administrador', 'oficina')
  )
)
with check (
  exists (
    select 1 from public.perfiles p
    where p.id = (select auth.uid())
      and p.activo
      and p.rol in ('administrador', 'oficina')
  )
);

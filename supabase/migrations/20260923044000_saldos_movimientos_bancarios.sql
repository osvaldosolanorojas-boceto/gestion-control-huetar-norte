-- Suma todos los movimientos de cada cuenta, aunque el historial mostrado esté paginado.
create view public.saldos_movimientos_bancarios with (security_invoker=true) as
select a.id cuenta_id,
  coalesce(sum(case when m.tipo='ingreso' then m.monto else -m.monto end),0)::numeric(16,2) neto,
  count(m.id)::integer movimientos
from public.cuentas_bancarias a left join public.movimientos_bancarios m on m.cuenta_id=a.id
group by a.id;
revoke all on public.saldos_movimientos_bancarios from anon,authenticated;
grant select on public.saldos_movimientos_bancarios to authenticated;

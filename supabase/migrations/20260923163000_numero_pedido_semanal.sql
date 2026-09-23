drop index if exists public.ordenes_venta_cliente_salida_numero_idx;
with numeradas as (
  select id, row_number() over (
    partition by cliente_id, date_trunc('week', fecha::timestamp)
    order by creado_en, id
  )::integer as numero from public.ordenes_venta
)
update public.ordenes_venta o set numero_cliente=n.numero
from numeradas n where o.id=n.id and o.numero_cliente is distinct from n.numero;
create unique index ordenes_venta_cliente_semana_numero_idx
  on public.ordenes_venta(cliente_id, date_trunc('week', fecha::timestamp), numero_cliente)
  where numero_cliente is not null;

alter table public.clientes
  add column if not exists razon_social text,
  add column if not exists identificacion_fiscal text,
  add column if not exists ciudad text,
  add column if not exists direccion text,
  add column if not exists puerto_llegada text,
  add column if not exists contacto_cargo text,
  add column if not exists telefono text,
  add column if not exists whatsapp text,
  add column if not exists correo text,
  add column if not exists correo_facturacion text,
  add column if not exists moneda_habitual public.moneda not null default 'USD',
  add column if not exists condiciones_pago text,
  add column if not exists plazo_pago_dias integer,
  add column if not exists incoterm text,
  add column if not exists direccion_facturacion text,
  add column if not exists direccion_entrega text,
  add column if not exists naviera text,
  add column if not exists logo_url text,
  add column if not exists observaciones text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'clientes_plazo_pago_dias_check'
  ) then
    alter table public.clientes
      add constraint clientes_plazo_pago_dias_check check (plazo_pago_dias >= 0);
  end if;
end $$;

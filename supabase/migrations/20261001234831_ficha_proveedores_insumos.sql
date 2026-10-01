alter table public.proveedores
add column if not exists correo_facturacion text,
add column if not exists contacto text,
add column if not exists banco text,
add column if not exists cuenta_bancaria text,
add column if not exists moneda_cuenta text default 'CRC' check (moneda_cuenta in ('CRC','USD')),
add column if not exists condiciones_pago text,
add column if not exists observaciones text;

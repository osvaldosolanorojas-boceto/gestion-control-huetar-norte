alter table public.trabajadores
  add column if not exists vencimiento_documento date,
  add column if not exists nacionalidad text,
  add column if not exists telefono_alternativo text,
  add column if not exists correo text,
  add column if not exists parentesco_emergencia text,
  add column if not exists puesto text,
  add column if not exists fecha_ingreso date,
  add column if not exists observaciones text;

-- Saldos iniciales exclusivamente de prueba para recorrer bancos y pagos.
-- Reemplazar cada importe con el extracto real desde la pantalla Bancos.
alter table public.cuentas_bancarias
  add column if not exists saldo_simulado boolean not null default false;

update public.cuentas_bancarias
set saldo_inicial = case
  when banco = 'BAC San José' and moneda = 'CRC' then 12500000
  when banco = 'BAC San José' and moneda = 'USD' then 45000
  when banco = 'Banco de Costa Rica' and moneda = 'CRC' then 8200000
  when banco = 'Banco de Costa Rica' and moneda = 'USD' then 30000
  when banco = 'Banco Nacional de Costa Rica' and moneda = 'CRC' then 15000000
  when banco = 'Banco Nacional de Costa Rica' and moneda = 'USD' then 60000
  else saldo_inicial end,
  saldo_confirmado = false,
  saldo_simulado = true
where banco in ('BAC San José','Banco de Costa Rica','Banco Nacional de Costa Rica')
  and moneda in ('CRC','USD') and tipo_cuenta = 'banco'
  and saldo_confirmado = false;

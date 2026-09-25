-- Permite preparar el equipo antes de reunir todos los correos.
-- El índice UNIQUE existente sigue impidiendo repetir un correo informado.
alter table public.usuarios_preparados alter column correo drop not null;

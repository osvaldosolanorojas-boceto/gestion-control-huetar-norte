create table public.programacion_personal_arranque (
 id uuid primary key default gen_random_uuid(),
 usuario_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 semana_inicio date not null check (extract(isodow from semana_inicio)=1),
 nombre text not null check (char_length(trim(nombre)) between 1 and 150),
 cajas_18 integer not null check (cajas_18>0),
 fecha_prevista date,
 notas text not null default '' check (char_length(notas)<=1000),
 creado_en timestamptz not null default now()
);
create index programacion_personal_usuario_semana on public.programacion_personal_arranque(usuario_id,semana_inicio);
alter table public.programacion_personal_arranque enable row level security;
revoke all on public.programacion_personal_arranque from anon;
grant select,insert,update,delete on public.programacion_personal_arranque to authenticated;
create policy programacion_personal_select on public.programacion_personal_arranque for select to authenticated using ((select auth.uid())=usuario_id);
create policy programacion_personal_insert on public.programacion_personal_arranque for insert to authenticated with check ((select auth.uid())=usuario_id);
create policy programacion_personal_update on public.programacion_personal_arranque for update to authenticated using ((select auth.uid())=usuario_id) with check ((select auth.uid())=usuario_id);
create policy programacion_personal_delete on public.programacion_personal_arranque for delete to authenticated using ((select auth.uid())=usuario_id);

-- Los precios de compra, lotes y costos son exclusivos del administrador.
drop policy if exists gestion_oficina on public.insumos;
create policy administracion_insumos on public.insumos for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'));
drop policy if exists oficina_ordenes_insumos on public.ordenes_insumos;
create policy administracion_ordenes_insumos on public.ordenes_insumos for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'));
drop policy if exists oficina_lineas_insumos on public.ordenes_insumos_lineas;
create policy administracion_lineas_insumos on public.ordenes_insumos_lineas for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'));
drop policy if exists oficina_lotes_insumos on public.lotes_insumos;
create policy administracion_lotes_insumos on public.lotes_insumos for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'));
drop policy if exists gestion_costos_produccion on public.costos_produccion;
create policy administracion_costos_produccion on public.costos_produccion for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol='administrador'));

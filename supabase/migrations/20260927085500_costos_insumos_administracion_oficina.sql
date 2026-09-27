-- Administración y oficina gestionan precios y costos; planta y bodega sólo cantidades.
drop policy if exists administracion_insumos on public.insumos;
create policy administracion_oficina_insumos on public.insumos for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
drop policy if exists administracion_ordenes_insumos on public.ordenes_insumos;
create policy administracion_oficina_ordenes_insumos on public.ordenes_insumos for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
drop policy if exists administracion_lineas_insumos on public.ordenes_insumos_lineas;
create policy administracion_oficina_lineas_insumos on public.ordenes_insumos_lineas for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
drop policy if exists administracion_lotes_insumos on public.lotes_insumos;
create policy administracion_oficina_lotes_insumos on public.lotes_insumos for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));
drop policy if exists administracion_costos_produccion on public.costos_produccion;
create policy administracion_oficina_costos_produccion on public.costos_produccion for all to authenticated
using (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')))
with check (exists(select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol in ('administrador','oficina')));

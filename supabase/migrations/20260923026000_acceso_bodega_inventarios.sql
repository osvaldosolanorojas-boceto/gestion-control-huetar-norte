-- Bodega puede manejar inventarios; no recibe acceso a precios ni finanzas.
do $$ declare t text; begin
  foreach t in array array['inventario_cartones','movimientos_cartones','insumos','movimientos_insumos','control_cajas_plasticas','responsables_cajas','movimientos_cajas_plasticas'] loop
    execute format('create policy acceso_bodega on public.%I for all to authenticated using (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol=''bodega'')) with check (exists (select 1 from public.perfiles p where p.id=(select auth.uid()) and p.activo and p.rol=''bodega''))',t);
  end loop;
end $$;

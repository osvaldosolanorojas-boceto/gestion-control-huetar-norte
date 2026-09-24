-- Corrección autorizada: las 72 cajas sin pedido de Mario Guápiles son exportables de EE. UU.
do $$
begin
  if (select count(*) from public.boleta_rendimientos r
      join public.boletas_entrada b on b.id=r.boleta_id
      join public.ordenes_compra o on o.id=b.orden_compra_id
      where r.id='454fae61-1a3d-406a-8282-0035ed3ead13'::uuid
        and b.codigo='BE-1790286926775' and b.finalizada_en is null
        and o.productor_nombre='Mario Guapiles' and r.producto='Yuca'
        and r.calidad='Exportable Europa' and r.cajas=72
        and r.orden_venta_linea_id is null) <> 1 then
    raise exception 'La partida de 72 cajas de Mario Guápiles cambió; no se aplicó la corrección';
  end if;
  update public.boleta_rendimientos set calidad='Exportable estadounidense'
    where id='454fae61-1a3d-406a-8282-0035ed3ead13'::uuid;
end;
$$;

-- Corrige partidas antiguas que tenían cajas y, además, un peso manual de solo una caja.
-- La boleta finalizada conserva sus cajas, presentación, trazabilidad y pago pactado.
do $$
declare v_count integer;
begin
  select count(*) into v_count from public.boleta_rendimientos r
    join public.boletas_entrada b on b.id=r.boleta_id
    join public.ordenes_compra o on o.id=b.orden_compra_id
    where b.codigo='BE-1790195318280' and o.codigo='OC-1790188759380'
      and b.finalizada_en is not null and o.tipo_compra='Puesto en camión'
      and r.id in ('b7c5882d-b8ac-4aef-8db9-3136958313d6'::uuid,
                   'fda67d5a-f8a1-4e84-88f1-4d74fe2717af'::uuid,
                   'f85ff7e1-40e5-482c-b40b-c53916e0b5b9'::uuid)
      and r.cajas>0 and r.kg_manual=r.presentacion_kg;
  if v_count<>3 then raise exception 'Las partidas cambiaron; no se aplicó la corrección'; end if;
  perform set_config('app.corrigiendo_boleta','completa',true);
  update public.boleta_rendimientos set kg_manual=null
    where id in ('b7c5882d-b8ac-4aef-8db9-3136958313d6'::uuid,
                 'fda67d5a-f8a1-4e84-88f1-4d74fe2717af'::uuid,
                 'f85ff7e1-40e5-482c-b40b-c53916e0b5b9'::uuid);
end;
$$;

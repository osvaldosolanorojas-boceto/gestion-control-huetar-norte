# Revisión de fincas - 2026-10-01

Estado del trabajo: ejercicio y diagnóstico completos; publicación y PDF en verificación.

## Evidencia

- 16 controles ejecutados con rol administrador en Supabase, en una transacción finalizada con ROLLBACK.
- Ninguna finca de prueba persistió.
- 14 pruebas de cálculo ejecutadas con node:test.
- Compilación Vite satisfactoria. La prueba en pantalla y la publicación se verifican por separado.

## Ejercicio base ilustrativo

70.000 kg: Europa 46.000; EEUU 13.800; segunda 3.000; rechazo 6.000; desperdicio 1.200. Las estacas son un producto separado de las raíces. Primera entregada a exportadora y subproductos vendidos directamente usan cantidades distintas.

Ventas brutas CRC 17.400.000; participación de César 30% = CRC 5.220.000; costos CRC 4.800.000; resultado provisional CRC 7.380.000. Cobrado 25% = CRC 4.350.000; CxC CRC 13.050.000. Activos propios CRC 14.000.000 + bodega CRC 1.650.000 + cultivo en curso CRC 4.800.000 = CRC 20.450.000 antes de cosecha. Después del cierre, activos y bodega CRC 15.650.000 y cuentas por cobrar aparte.

Los montos son supuestos editables. No hay operaciones ficticias persistentes en las cuentas reales.

## Chequeos

- **OK: Entrega directa.** Recibe 100 sacos por ₡1.000.000 y genera una deuda de Agrosolano.
- **OK: Compra sin consumo.** La recepción conserva inventario y todavía no registra costo del cultivo.
- **OK: Deuda de insumos.** Una cuenta por pagar, por el monto correcto y en la empresa correcta.
- **OK: Reintento de entrega.** La misma solicitud no duplica existencia ni deuda.
- **OK: Traslado entre fincas.** Conserva ₡3.000.000 de valor total y aplica costo promedio.
- **OK: Consumo por lote.** 40 sacos pasan a costo agrícola por ₡600.000.
- **OK: Existencia insuficiente.** Rechaza el exceso y conserva el saldo previo.
- **OK: Lote ajeno.** Rechaza la finca incorrecta y revierte toda la operación.
- **OK: Planilla.** Distingue costo bruto ₡150.000 y neto por pagar ₡140.000.
- **OK: Edición de planilla.** Actualiza el mismo costo y la misma deuda, sin duplicarlos.
- **OK: Banco de otra empresa.** Rechaza pagar deuda de Agrosolano desde la exportadora.
- **OK: Pago parcial.** Paga ₡100.000 y deja ₡70.000 por pagar.
- **OK: Edición después del pago.** Rechaza reducir la deuda por debajo de lo ya pagado.
- **OK: Combustible.** Registra litros, costo, deuda y horómetro.
- **OK: Edición de combustible.** Actualiza un solo costo.
- **OK: Tractor de otra finca.** Rechaza una asignación incorrecta.
- **Corregido: Gastos generales sin lote.** Ahora se muestran aparte y se pueden asignar a un lote de la misma finca.
- **Corregido: Valor del inventario.** La inversión usa saldos de bodega y conserva fichas manuales como referencia, sin sumarlas dos veces.
- **Pendiente: Liquidación del dueño.** El 30%/38% está en el contrato. Falta calcular la liquidación sobre las ventas agrícolas de la propiedad y generar la deuda.
- **Pendiente: Subproductos por finca.** Las ventas directas necesitan origen finca/lote, kilos, precio y cuenta por cobrar propia.
- **Pendiente: Cierre y pérdida del cultivo.** La marca en curso no sustituye una liquidación final ni un registro de pérdida.

## Prioridades

- **Primero: Ciclo de cultivo.** Área, variedad, siembra, cosecha estimada y real, cosechas parciales, estado, responsable y costo por hectárea/quintal. Un lote puede tener varios ciclos.
- **Primero: Cosecha y balance físico.** Kilos cosechados = entregados + vendidos directamente + semilla retenida + remanente + pérdidas. Evitar vender dos veces la misma cantidad.
- **Primero: Ventas directas y subproductos.** Primera local, segunda, rechazo, semilla/estacas y otros, con cliente, origen, unidad/peso y cobro. La venta de planta pertenece a exportadora; no se suma otra vez en finca.
- **Primero: Liquidación del propietario.** Base bruta por propiedad; porcentaje pactado, anticipos, pagos, saldo y correcciones. Aclarar cómo se tratan devoluciones/descuentos y semilla antes de automatizar.
- **Primero: Cierre del cultivo.** Cierre parcial/final, costos pendientes, ventas pendientes, pérdidas, remanentes y reapertura con motivo. Conservar resultado e historial.
- **Primero: Costos compartidos.** Repartir planilla, combustible, alquiler y caminos entre lotes con criterio visible: horas, hectáreas o monto manual. Mostrar lo que queda sin asignar.
- **Primero: Una ficha por máquina.** Unificar la ficha patrimonial y la ficha de operación del tractor para tener valor, horómetro, trabajos y mantenimiento sin doble registro.
- **Después: Compras de insumos en USD.** Conservar deuda en la moneda original y tipo de cambio de cada compra. Separar diferencia cambiaria del costo agrícola.
- **Después: Bodega completa.** Devoluciones a central/proveedor, sobrantes, pérdidas, conteos físicos, responsable y motivo de ajuste; lotes de producto y vencimiento cuando aplique.
- **Después: Traslados e historial de maquinaria.** Guardar finca origen/destino y fecha; conservar gastos históricos aunque cambie la ubicación actual. Registrar venta, baja o pérdida del equipo.
- **Después: Mantenimiento y llantas.** Servicios por horas/fecha, historial, repuestos, costo, trabajos pendientes y alertas próximas, sin bloquear las operaciones.
- **Después: Contratos.** Documento adjunto, ubicación/área, depósito, calendario de cuotas, prórrogas y aviso de vencimiento. Distribuir el alquiler entre los cultivos del período.
- **Después: Inversión y caja separadas.** Mostrar activos y cultivos, deuda por pagar, cuentas por cobrar y dinero efectivamente desembolsado. Inversión no equivale a gasto ni a utilidad cobrada.
- **Después: Operación en campo.** Asignación de personal por finca, labores por lote, cantidades realizadas, evidencia y permisos que ocultan montos al personal de campo.
- **Después: Correcciones.** Motivo, usuario, fecha y antes/después para costos, inventarios, cosechas, contratos y traslados.
- **Más adelante: Terrenos propios.** Valoración de Copevega y demás activos según el criterio acordado; mantenerla aparte del resultado operativo agrícola.
- **Más adelante: Documentos y controles.** Comprobantes, conciliación de bancos, respaldo comprobable, presupuesto frente a ejecución y recordatorios.
- **Simplificar: Inventario manual duplicado.** Usar una sola existencia por insumo y bodega. El saldo manual inicial debe convertirse en entrada identificada.
- **Simplificar: Fincas históricas.** Ocultar inactivas en nuevas operaciones, conservar su historia y evitar crear dos fincas con nombres escritos distinto.
- **Simplificar: Pantalla de Fincas.** Separar contratos, maquinaria, bodega, cultivos y resultados en secciones plegables; mostrar primero el resumen y el ejercicio.

## Cambios del chequeo

1. El valor de inventario se toma de existencias_insumos_finca. Las fichas manuales de insumos se conservan como referencia y no se suman nuevamente. Si el saldo no se puede consultar, se informa el uso provisional de fichas manuales.
2. Gastos generales sin lote se muestran aparte y pueden asignarse al lote correcto. Si el costo proviene de una actividad de tractor, se corrige también la actividad de origen. No se capitaliza un gasto histórico sin asignación explícita.
3. En Fincas se incluye un ejercicio editable y el checklist. Los porcentajes, pérdidas, cobros, precios y cantidades se calculan sin escribir operaciones en la base de datos.
4. Las 14 pruebas de cálculo corren antes de compilar y publicar.

## Reproducción

Ejecutar npm run test:fincas para cálculos. tests/fincas/ejercicio-transaccional.sql contiene el ejercicio de base de datos y termina en ROLLBACK. No usarlo como migración ni quitar la reversión final.

## Límites conocidos

La liquidación real del dueño, las ventas directas por finca/lote y el cierre formal aún no están implementados. Los escenarios los ilustran, no generan documentos reales. El motor de bodegas y actividades de tractor fue revisado en la base de datos; su interfaz completa pertenece al trabajo previo de fincas/tractores/bodegas y debe integrarse sin duplicar las fichas. La ficha patrimonial y la operativa de tractor necesitan una única identidad.

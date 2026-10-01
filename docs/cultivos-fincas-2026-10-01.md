# Cultivos y liquidación agrícola

Publicado en la aplicación existente, misma dirección y acceso desde el ícono del teléfono.

## Uso

1. Fincas → Cultivos, cosechas y liquidación → Nuevo cultivo: escoger lote, siembra, producto, área y acuerdo del dueño. El porcentaje y propietario se copian de la propiedad; revisar y guardar. El lote puede tener varios ciclos.
2. Registrar cosecha por producto, calidad y unidad física. Las estacas se registran en unidades, separadas de los kilos de raíz.
3. Registrar salidas: venta en campo, entrega a exportadora, pérdida o uso como semilla. Las ventas directas crean un cobro de Agrosolano. Las entregas usan una orden de cosecha propia del mismo lote; su valor agrícola viene de las boletas finalizadas y se cuenta una sola vez por orden.
4. Registrar los costos nuevos o asignar al cultivo el gasto que ya creó un consumo de insumos, una planilla o una actividad de tractor. Los gastos generales se reparten entre cultivos de la misma administración por monto o hectáreas. El reparto no vuelve a crear gasto ni deuda.
5. Generar/actualizar liquidación del dueño. El 25%, 30%, 38% u otro porcentaje se calcula sobre venta bruta EN CAMPO, antes de rebajos. No usa el precio de venta de exportación. La participación se resta una sola vez del resultado; no volver a incluirla como costo manual.
6. Cobrar y pagar desde Finanzas, Agrosolano, Bancos. La modificación de una liquidación pagada conserva el pago y genera un reintegro por cobrar cuando el dueño recibió de más.
7. Destinar remanentes mediante venta, pérdida, semilla o arrastre a otro cultivo abierto. El costo arrastrado pasa de origen a destino y conserva la inversión total.
8. Cerrar el cultivo con motivo. Se requiere inventario físico sin remanentes, compras liquidadas y gastos del lote asignados. Los saldos financieros siguen pendientes después del cierre. Reabrir con motivo para corregir; se conserva la fotografía del cierre anterior.

## Maquinaria e inversión

La ficha de tractor está enlazada a un solo registro operativo. Desde la ficha se anotan combustible en litros, horómetro, trabajo, mantenimiento y llantas. Se genera un solo costo, y cuenta por pagar si se indica beneficiario. Su traslado conserva el historial de trabajo en la finca original.

La inversión usa activos propios, bodega real y costos de cultivos abiertos. Los lotes anteriores sin ciclos conservan la selección manual. Un lote con ciclos no vuelve a sumar sus costos históricos. El costo marcado como excluido de inversión sigue contando en el resultado agrícola, pero no en la inversión.

## Correcciones

Las cantidades y precios de cosecha/salidas pueden corregirse en un cultivo abierto, con motivo y registro del antes/después. No se permite dejar inventario negativo ni reducir un cobro por debajo de lo ya aplicado. Los arrastres conservan su pareja origen/destino. Las cuentas generadas se corrigen desde su operación de origen.

## Verificación y límites

16 pruebas transaccionales del ciclo completo, 16 del control anterior de bodega/pagos y 16 pruebas de cálculo. Pruebas con rol authenticated de administrador y ROLLBACK: no se guardan operaciones ficticias. Compilación de producción comprobada. No se afirma una prueba visual completa de todas las pantallas.

Los datos históricos se conservan y su asignación al ciclo es explícita. Anticipos a dueños anteriores a ventas, documentos adjuntos de contratos, alertas de mantenimiento, productividad por hectárea, devolución a bodega central y valoración del terreno quedan para ampliar. Los gastos compartidos del mismo lote que abarca varios ciclos requieren seleccionar su destino con criterio del administrador. Las cajas y sacos conservan la cantidad física real digitada; quintales se validan a 46 kg.

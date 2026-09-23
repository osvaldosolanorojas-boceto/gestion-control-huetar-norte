# Corte semanal de operación — diseño para revisión

Estado: primera captura operativa disponible en **Corte semanal**. El resultado se muestra como parcial y no se han creado gastos ni liquidaciones automáticamente.

La primera versión permite capturar planilla por trabajador, materiales valorizados manualmente, servicios, transporte y gastos de contenedor; editar o anular cada partida; y consultar ventas locales, pedidos y boletas finalizados de la semana. Aún falta definir y automatizar tarifas de planilla, valoración por lote de inventarios, conversión de monedas y criterios de reparto. No existe botón de cierre definitivo hasta que esas reglas se aprueben.

## Período y dos vistas distintas

- Semana ISO en horario de Costa Rica: lunes a domingo. Semana 39 de 2026: 21–27 de septiembre.
- **Resultado operativo devengado:** ventas que corresponden a la semana menos producto comprado, planilla trabajada, materiales consumidos y otros gastos causados en la semana. Un depósito o un pago bancario no crea otro ingreso o gasto aquí: liquida una cuenta ya contabilizada.
- **Caja de la semana:** depósitos menos pagos, por banco y moneda, conciliados contra documentos. No equivale a utilidad.
- Mostrar CRC y USD por separado hasta definir tipo de cambio y fecha de conversión; mostrar costos incompletos como pendientes, no como cero.

## Flujo de captura

1. Registrar planilla por semana y trabajador: período, días/horas/cajas/quintales o labor, tarifa, bruto, deducciones, neto, estado (borrador, aprobada, pagada), finca/planta, y referencia de pago. La ficha de trabajadores existente aporta identidad; las labores en boletas aportan trazabilidad, pero hoy no contienen tarifas ni horas pagables.
2. Registrar consumos del inventario con fecha de operación, insumo, cantidad, costo unitario de la partida y destino (contenedor/pedido, boleta o gasto general). La tabla actual `movimientos_insumos` registra cantidad y fecha de registro, pero no costo, fecha efectiva ni destino estructurado. Su compra entra al inventario; el costo se reconoce al consumirlo. Las reservas de cartón por orden no son todavía consumo físico ni costo.
3. Registrar gastos de operación: electricidad, gas, agua, flete, empaque, servicios y otros. Cada uno lleva fecha efectiva, categoría, moneda, monto, proveedor, documento, forma de asignación (pedido concreto o gasto general), y referencia de pago si existe. Un pago bancario ligado al gasto no se suma de nuevo al resultado.
4. Registrar costos fijos o específicos de un contenedor en la orden respectiva, con concepto y documento. Los costos compartidos se asignan semanalmente con un criterio visible (por cajas, kg u otro aprobado), conservando tanto el costo original como el reparto.
5. Revisar el cierre semanal: ingresos de pedidos finalizados y ventas locales, compra de producto de boletas finalizadas, planilla, consumos, gastos por contenedor y gastos generales; presentar margen bruto, resultado operativo y campos pendientes. Guardar un cierre con fecha, responsable y detalle de ajustes para que una corrección posterior no reescriba silenciosamente semanas ya aprobadas.

## Fuentes que ya existen

| Dato | Fuente actual | Límite para el corte |
| --- | --- | --- |
| Venta exportación | `ordenes_venta.monto_cxc` al finalizar | Confirmar si se reconoce al finalizar, al salir el contenedor o al facturar. |
| Venta local | `ventas_locales` y subtotales de `ventas_segundas` | Elegir fecha de salida/venta para asignar semana. |
| Compra de producto | `boletas_entrada.monto_cxp` al finalizar | El cierre fija monto por boleta; asociar a semana operativa, no a fecha del pago. |
| Planilla | `trabajadores` y `boleta_trabajos` | Falta registro de tiempo/unidades, tarifas y liquidación semanal. |
| Insumos | `insumos` y `movimientos_insumos` | Falta costo por unidad, fecha efectiva y destino para calcular consumo en CRC/USD. |
| Cartones | `inventario_cartones`, `movimientos_cartones` y reservas por pedido | Falta salida física y costo de adquisición por lote. |
| Banco | `movimientos_bancarios` y `aplicaciones_bancarias` | Se usa solo para caja y conciliación, evitando duplicar ingreso/gasto. |

## Pantalla propuesta

Selector de semana (por defecto la actual) y sociedad; cuatro secciones: **Ventas**, **Costo de producto**, **Planilla y materiales**, **Servicios y gastos de contenedor**. Al final, resultado en cada moneda, cobertura de costos (completo/incompleto) y botón **Cerrar semana** disponible solo cuando los rubros requeridos estén revisados. Detalle por pedido/contenedor y por finca/planta para localizar desviaciones.

## Definiciones para revisar con Osvaldo

- Tarifa de planilla: por día/hora, cajas, quintales o labor; deducciones y tratamiento de las dos cuadrillas de yuca y la de ñampí.
- Fecha que determina el ingreso de exportación y reparto de gastos compartidos.
- Tarifas/costo de cartones e insumos y cuándo se considera consumo real.
- Moneda de presentación final y tipo de cambio por semana o por transacción.
- Qué gastos fijos pertenecen a un contenedor y cuáles a toda la semana; separación Exportadora/Agrosolano.

No cargar datos de muestra ni liquidar una semana real hasta confirmar estas reglas.

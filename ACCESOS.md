# Accesos del sistema

Cada persona inicia sesión con su propio usuario de Supabase Auth. El perfil en `public.perfiles` determina el rol y si el acceso está activo. La pantalla filtra los módulos y las políticas RLS de Supabase controlan la lectura y escritura reales.

| Función | Rol actual | Acceso implementado |
| --- | --- | --- |
| Dirección (Osvaldo) | `administrador` | Todos los módulos actuales. |
| Oficina | `oficina` | Módulos administrativos actuales, incluidos importes. Es un rol amplio; asignarlo solo a personas autorizadas para todos esos datos. |
| Empaque / planta | `planta` | Boletas y rendimientos mediante las funciones restringidas de planta, sin precios de compra ni venta. |
| Bodega | `bodega` | Inventarios de cartones, insumos y cajas plásticas. |
| Finca y chofer | `finca`, `chofer` | Sin módulo operativo asignado aún. |

## Pendiente antes de crear usuarios de planillas y pagos

Planillas y pagos requieren roles nuevos y módulos con permisos de base de datos separados. No usar `oficina` para esos usuarios: actualmente ese rol permite ver compras, ventas y finanzas completas. Diseñar primero las tablas y operaciones de planillas y pagos, luego agregar los roles y sus políticas RLS, y finalmente crear los usuarios individuales. El administrador conservará acceso total. Nunca compartir la contraseña del administrador.

El inventario de insumos registra el consumo con referencia de orden o factura. La salida física no se descuenta al crear una orden de venta: primero debe anotarse la cantidad usada. Las cajas plásticas se entregan a responsables y se devuelven con saldos pendientes; registrar el inventario inicial como una entrada de cajas.

# Gestión y Control — Raíces y Tubérculos Huetar Norte S.A.

Aplicación privada para compras de campo, recepción de planta, rendimientos, ventas, finanzas, bancos, proveedores, clientes y trabajadores.

## Desarrollo

```bash
npm install
cp .env.example .env
npm run dev
```

Configure `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` en `.env`. Ejecute `supabase/schema.sql` en el editor SQL de Supabase antes de ingresar datos reales.

## Seguridad

- El archivo `.env` no se guarda en GitHub.
- El esquema habilita RLS en todas las tablas operativas.
- Los permisos de escritura por rol se completan al conectar el primer usuario administrador.

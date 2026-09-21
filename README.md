# Gestión y Control — Raíces y Tubérculos Huetar Norte S.A.

Aplicación privada para compras de campo, recepción de planta, rendimientos, ventas, finanzas, bancos, proveedores, clientes y trabajadores.

## Desarrollo

```bash
npm install
cp .env.example .env
npm run dev
```

Configure `VITE_SUPABASE_URL` y `VITE_SUPABASE_PUBLISHABLE_KEY` en `.env`. La aplicación publicada usa solamente la clave publicable; nunca requiere una clave secreta en el navegador. Ejecute `supabase/schema.sql` en un proyecto nuevo antes de ingresar datos reales.

## Seguridad

- El archivo `.env` no se guarda en GitHub.
- El esquema habilita RLS en todas las tablas operativas.
- Cada sesión se valida contra `public.perfiles`; una cuenta sin perfil activo no puede abrir la aplicación.

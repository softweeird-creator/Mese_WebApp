# Servidor de MESE

Servidor en TypeScript (Node + Fastify) que une la página con la base de datos MySQL de `db/`.
Es delgado: revisa quién está conectado, valida lo que llega y llama a los procedimientos `sp_...`
de la base, donde viven las reglas.

## Qué hace hoy (fase 1)

- **Inicio de sesión** con usuario y contraseña (cifrada con argon2). La sesión dura hasta que la persona
  toca **Salir** o la administración la cierra.
- **Administrador genérico** para la primera vez: usuario `admin`, contraseña `mese2026`. Al entrar, la
  página pide crear una contraseña propia (puede ser fácil de recordar).
- **Usuarios** (solo administración): agregar, editar, poner contraseña temporal, desactivar y cerrar
  sesiones a distancia (por ejemplo, un teléfono perdido).
- Tras 5 contraseñas equivocadas seguidas, la cuenta espera 15 minutos.
- Entrega la página (`index.html`) y los archivos para instalarla en el teléfono, nada más.

Los paneles todavía muestran datos de ejemplo; leerlos y guardarlos en la base es la fase 2.

## Instalar y correr

Requiere Node 20 o superior y la base instalada (ver `db/README.md`, incluido `08_seguridad.sql`).

```bash
cd server
cp .env.example .env      # ponga la contraseña del usuario mese_app de MySQL
npm install
npm run dev               # http://localhost:3000
```

En producción: `npm run build && npm start`, detrás de HTTPS y con `MODO=produccion` en `.env`.

## Comandos

| Comando | Para qué |
|---|---|
| `npm run dev` | Servidor que se reinicia solo al cambiar el código |
| `npm test` | Pruebas contra la base MySQL de `.env` |
| `npm run typecheck` | Revisa los tipos de TypeScript |
| `npm run clave -- admin NuevaClave` | Pone una contraseña desde la consola (si se olvidó la del administrador) |

## API

| Ruta | Quién | Qué hace |
|---|---|---|
| `POST /api/entrar` | Todos | `{usuario, clave}` → abre sesión (cookie) |
| `POST /api/salir` | Con sesión | Cierra la sesión |
| `GET /api/yo` | Con sesión | Quién está conectado (401 si nadie) |
| `POST /api/clave` | Con sesión | `{actual, nueva}` → cambia la propia contraseña |
| `GET /api/usuarios` | Administración | Lista de usuarios |
| `POST /api/usuarios` | Administración | `{nombre, usuario, correo, rol, clave}` → alta con contraseña temporal |
| `PUT /api/usuarios/:id` | Administración | Editar nombre, usuario, correo y rol |
| `POST /api/usuarios/:id/clave` | Administración | `{clave}` → contraseña temporal; cierra sus sesiones |
| `POST /api/usuarios/:id/activo` | Administración | `{activo}` → activar o desactivar |
| `POST /api/usuarios/:id/cerrar-sesiones` | Administración | Cierra todas sus sesiones |

Los errores responden `{ "error": "mensaje en español" }`, listo para mostrar.

## Seguridad

- La cookie de sesión no la pueden leer otros scripts (`HttpOnly`), solo viaja al mismo sitio
  (`SameSite=Strict`) y en producción solo por HTTPS. En la base se guarda su SHA-256, no el valor.
- Las peticiones que cambian datos se rechazan si vienen de otro sitio.
- La aplicación entra a MySQL con `mese_app`, que solo puede leer vistas y ejecutar procedimientos.
- `.env` no se sube a GitHub.

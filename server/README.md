# Servidor de MESE

Servidor en TypeScript (Node + Fastify) que une la página con la base de datos MySQL de `db/`.
Es delgado: revisa quién está conectado, valida lo que llega y llama a los procedimientos `sp_...`
de la base, donde viven las reglas.

## Qué hace hoy (fases 1, 2 y 3)

- **Inicio de sesión** con usuario y contraseña (cifrada con argon2). La sesión dura hasta que la persona
  toca **Salir** o la administración la cierra.
- **Administrador genérico** para la primera vez: usuario `admin`, contraseña `mese2026`. Al entrar, la
  página pide crear una contraseña propia (puede ser fácil de recordar).
- **Usuarios** (solo la administración principal): agregar, editar, poner contraseña temporal, desactivar y cerrar
  sesiones a distancia (por ejemplo, un teléfono perdido).
- **Permisos por persona.** Cada usuario tiene un rol, que solo sugiere permisos, y la administración elige:
  - **A quién ve:** a todos los participantes, o solo a los que tiene asignados y a sus familias (trabajo social).
  - **Qué secciones ve:** activos, histórico, familiares, bajas, visitas, reporte del mes.
  - **Qué puede hacer:** agregar, editar, dar de baja, borrar, capturar visitas, descargar e imprimir.
    Con ninguna marcada, la persona solo consulta (por ejemplo, otras áreas de MESE).
  - Los cambios aplican al momento, sin que la persona vuelva a entrar.
- **Participantes de cada trabajadora social:** la administración los asigna desde **Usuarios → Asignar participantes**
  y, si alguien se va, **Pasar sus participantes** los mueve a otra persona.
- **Las secciones leen la base** (`GET /api/datos`): cada persona recibe solo lo que puede ver. Sin internet,
  la página muestra lo último que descargó.
- Tras 5 contraseñas equivocadas seguidas, la cuenta espera 15 minutos.
- Entrega la página (`index.html`) y los archivos para instalarla en el teléfono, nada más.

- **Guardar desde la página** (fase 3): agregar y editar participantes, familiares y registros históricos, dar de baja
  y reactivar. La base revisa el permiso y el alcance de cada persona y responde los errores en español
  (CURP inválida, grado que no existe, teléfono incompleto...). Después de guardar, la página vuelve a leer los datos.

Falta la fase 4: subir a la base las visitas que se capturan en el teléfono.

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
| `POST /api/usuarios` | Administración | `{nombre, usuario, correo, rol, alcance, permisos, clave}` → alta con contraseña temporal |
| `PUT /api/usuarios/:id` | Administración | Editar nombre, usuario, correo, rol, alcance y permisos (con `clave`, da acceso a quien no lo tenía) |
| `POST /api/usuarios/:id/clave` | Administración | `{clave}` → contraseña temporal; cierra sus sesiones |
| `POST /api/usuarios/:id/activo` | Administración | `{activo}` → activar o desactivar |
| `POST /api/usuarios/:id/cerrar-sesiones` | Administración | Cierra todas sus sesiones |
| `PUT /api/usuarios/:id/asignados` | Administración | `{participantes: [id...]}` → participantes activos que atiende |
| `POST /api/usuarios/:id/reasignar` | Administración | `{a}` → pasa todos sus participantes a otra persona |
| `GET /api/roles` | Administración | Permisos que existen y los sugeridos de cada rol |
| `GET /api/datos` | Con sesión | `{activos, historico, familiares, bajas}`: solo las secciones y participantes que puede ver |
| `POST /api/activos` · `/api/familiares` · `/api/historico` | Permiso AGREGAR | Lo capturado con las claves de la página → `{id}` |
| `PUT /api/activos/:id` · `/api/familiares/:id` · `/api/historico/:id` | Permiso EDITAR | Guarda los cambios (solo de los participantes que le tocan) |
| `POST /api/activos/:id/baja` | Permiso BAJAS | `{fb, mot, ce, cx, ct, rte, rne, mo}` → registra la baja |
| `POST /api/bajas/:id/reactivar` | Permiso BAJAS | Abre un periodo nuevo con fecha de hoy |

Los errores responden `{ "error": "mensaje en español" }`, listo para mostrar.

## Seguridad

- La cookie de sesión no la pueden leer otros scripts (`HttpOnly`), solo viaja al mismo sitio
  (`SameSite=Strict`) y en producción solo por HTTPS. En la base se guarda su SHA-256, no el valor.
- Las peticiones que cambian datos se rechazan si vienen de otro sitio.
- La aplicación entra a MySQL con `mese_app`, que solo puede leer vistas y ejecutar procedimientos.
- `.env` no se sube a GitHub.

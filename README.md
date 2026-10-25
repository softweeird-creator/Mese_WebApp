# MESE · Sistema de gestión (prototipo front-end)

Prototipo en HTML, CSS y JavaScript para administrar participantes, familiares, bajas, registro histórico y visitas domiciliarias de MESE Vasco de Quiroga I.A.P.

## Cómo usarlo
- **Demostración:** abra `index.html` en cualquier navegador. Usa datos de ejemplo y no necesita instalación.
- **Para que MESE la use:** publíquela con el servidor y la base. La guía para hacerlo gratis en Oracle Cloud,
  con un solo script, está en [`deploy/oracle/README.md`](deploy/oracle/README.md).

En cada teléfono abra la dirección **una vez con internet** y elija “Agregar a pantalla de inicio” (o el botón
“Instalar en el teléfono”). Desde ese momento abre y guarda visitas aunque no haya señal.

## Qué incluye
- Paneles: Participantes activos, Registro histórico, Familiares, Bajas y Visitas domiciliarias.
- Barra de búsqueda en cada panel (sin importar acentos ni mayúsculas) y buscador general en Inicio.
- Filtros combinables y gráficas. Año de ingreso con campo manual y mes de ingreso con los 12 meses.
- Altas, ediciones, bajas (con filtro por mes de baja) y reactivaciones.
- Reporte del mes con filtros de mes, año, género y nivel; hoja de estadísticas imprimible y en PDF.

### Visitas domiciliarias (formato “Seguimiento familiar”)
- Formulario por pasos pensado para el celular, con las 10 secciones del formato en papel, más datos de la visita y firmas.
- Opciones grandes para tocar con el dedo, tablas de integrantes y antecedentes médicos que crecen según se necesite, totales de ingresos, apoyos y egresos calculados solos.
- Buscador de participantes ya registrados para llenar sus datos automáticamente.
- Ubicación GPS opcional del domicilio y firmas con el dedo (trabajadora social y madre o tutor).
- Guardado automático mientras se escribe: si se cierra el navegador o se acaba la batería, la captura se puede continuar.
- Borradores y visitas terminadas; búsqueda, filtros (trabajadora social, colonia, estado, vivienda, rango de fechas), edición y eliminación.
- Gráficas y **reporte por fecha** (este mes, mes pasado, últimos 7 días, año o rango libre) con impresión, PDF y exportación a Excel (tabla con filtros, fechas y montos con formato; hojas de visitas, integrantes y antecedentes).
- Ficha individual de cada visita imprimible o en PDF.
- Respaldo: descargar o enviar (WhatsApp, correo) una página ordenada con el logo de MESE, un resumen, la lista y la ficha de cada visita; se abre en cualquier teléfono o computadora. En la oficina, “Importar respaldo” con esos archivos junta las visitas de varios teléfonos sin duplicarlas.

## Base de datos
La carpeta `db/` tiene la base de datos MySQL normalizada (esquema, catálogos, vistas, procedimientos, triggers, carga desde Excel, pruebas y permisos). Ver `db/README.md`.

## Servidor
La carpeta `server/` tiene el servidor en TypeScript (Fastify): inicio de sesión, usuarios con permisos por persona (qué secciones ve, qué puede hacer y si ve a todos o solo a sus participantes asignados), lectura de los datos desde la base y entrega de la página. Ver `server/README.md`.
Cuando la página la entrega el servidor, pide usuario y contraseña (primera vez: `admin` / `mese2026`). Abierta directo como archivo, sigue funcionando como demostración sin login.

## Archivos
- `index.html` – la aplicación completa.
- `sw.js` – permite abrir la aplicación sin internet. **Cambie el número de versión (`mese-v9`) cada vez que publique cambios** para que los teléfonos reciban la actualización.
- `manifest.webmanifest`, `icon-192.png`, `icon-512.png`, `logo.png` – logo e instalación en la pantalla de inicio. El logo dentro de la página está en la constante `LOGO` de `index.html`.

## Pendiente
- Abierta directo como archivo (sin servidor), la página usa datos de ejemplo que viven solo en la memoria del navegador. Con servidor, participantes, familiares, bajas e histórico se leen y se guardan en la base.
- Las visitas se guardan en el dispositivo (IndexedDB) y cada teléfono tiene las suyas. Falta enviarlas a la base con `sp_guardar_visita` (fase 4). Cada visita ya tiene un `id` único y fecha de modificación (`mod`), listos para sincronizarse.

#!/usr/bin/env bash
# =====================================================================
#  deploy/oracle/actualizar.sh — pasa a la máquina la versión nueva del
#  repositorio sin borrar datos.
#
#    cd Mese_WebApp && git pull && sudo bash deploy/oracle/actualizar.sh
#
#  Respalda la base, vuelve a instalar funciones, vistas, procedimientos y
#  triggers (03, 04, 05, 06, 09 y los permisos de 08) y reinicia el servidor.
#  Nunca corre 01_esquema ni 02_catalogos, que borran tablas y catálogos.
#  Si una versión nueva cambia tablas, traerá su propio archivo de cambios.
# =====================================================================
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Corra el script con sudo."; exit 1; }
REPO=$(cd "$(dirname "$0")/../.." && pwd)
APP=/opt/mese
# shellcheck disable=SC1091
. /etc/mese/credenciales

echo "=== Respaldo antes de actualizar ==="
/usr/local/bin/mese-respaldo

echo "=== Base de datos ==="
cd "$REPO/db"
for f in 03_funciones_vistas 04_procedimientos 05_triggers 06_carga_excel 09_pagina; do
  mysql < "$f.sql" > /dev/null && echo "  $f.sql"
done
# Volver a crear un procedimiento le quita sus permisos: se dan otra vez (los usuarios ya existen y no cambian)
sed "s/CAMBIE_ESTA_CONTRASENA_1/$CLAVE_APP/; s/CAMBIE_ESTA_CONTRASENA_2/$CLAVE_REP/" 08_seguridad.sql | mysql && echo "  permisos (08_seguridad.sql)"

echo "=== Servidor ==="
rsync -a --delete --exclude .git --exclude node_modules --exclude server/.env --exclude server/dist "$REPO/" "$APP/"
chown -R mese:mese "$APP"
sudo -u mese -H bash -c "cd $APP/server && npm ci --no-audit --no-fund --loglevel=error && npm run build --silent"
install -m 755 "$REPO/deploy/oracle/respaldo.sh" /usr/local/bin/mese-respaldo
systemctl restart mese
sleep 2
systemctl is-active --quiet mese && echo "Listo: el servidor está corriendo." || { echo "El servidor no arrancó:"; journalctl -u mese -n 30 --no-pager; exit 1; }

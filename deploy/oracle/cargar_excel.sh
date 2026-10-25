#!/usr/bin/env bash
# =====================================================================
#  deploy/oracle/cargar_excel.sh — carga los tres Excel de MESE en un paso.
#
#  1. En Excel, guarde cada hoja como "CSV UTF-8 (delimitado por comas)":
#       hoja BASE del Excel de activos     → base.csv
#       hoja B-DATOS del Excel BDI         → bdi.csv
#       hoja DATOS de la base histórica    → historica.csv
#  2. Súbalos a la máquina (por ejemplo: scp *.csv ubuntu@IP:~/)
#  3. sudo bash deploy/oracle/cargar_excel.sh base.csv bdi.csv historica.csv 2026-10-31
#     (la fecha es el corte: el último día que cubre el Excel)
#
#  ATENCIÓN: borra lo que se haya cargado antes desde Excel y lo vuelve a
#  cargar. Lo que se agregó desde la página se conserva, pero los cambios
#  hechos en la página a personas que venían del Excel se pierden. Pensado
#  para la carga inicial. Antes hace un respaldo.
# =====================================================================
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Corra el script con sudo."; exit 1; }
[ $# -eq 4 ] || { sed -n '3,17p' "$0"; exit 2; }
BASE=$1 BDI=$2 HIST=$3 CORTE=$4
for f in "$BASE" "$BDI" "$HIST"; do [ -r "$f" ] || { echo "No encuentro $f"; exit 1; }; done
[[ $CORTE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "La fecha de corte va como AAAA-MM-DD, por ejemplo 2026-10-31"; exit 1; }

read -r -p "Esto vuelve a cargar los Excel y borra la carga anterior. Escriba SI para seguir: " r
[ "$r" = "SI" ] || { echo "No se cargó nada."; exit 0; }

/usr/local/bin/mese-respaldo
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# Excel en Windows termina los renglones con \r\n; se dejan en \n
for par in "base:$BASE" "bdi:$BDI" "historica:$HIST"; do sed 's/\r$//' "${par#*:}" > "$tmp/${par%%:*}.csv"; done
chmod 644 "$tmp"/*.csv; chmod 755 "$tmp"

columnas() { local s=""; for i in $(seq 1 "$1"); do s="$s,c$(printf %02d "$i")"; done; echo "${s#,}"; }
cargar() {  # tabla, archivo, columnas, renglones de encabezado
  echo "LOAD DATA LOCAL INFILE '$tmp/$2' INTO TABLE $1 CHARACTER SET utf8mb4
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"' LINES TERMINATED BY '\n' IGNORE $4 LINES ($(columnas "$3"));"
}
mysql -e "SET GLOBAL local_infile = 1"
{ echo "USE mese; SET NAMES utf8mb4; SET @formato_fecha = '%d/%m/%Y'; TRUNCATE stg_base; TRUNCATE stg_bdi; TRUNCATE stg_historica;"
  cargar stg_base base.csv 78 5; cargar stg_bdi bdi.csv 62 5; cargar stg_historica historica.csv 26 2
  echo "CALL sp_carga_todo('$CORTE');"
  echo "SELECT columna, valor, problema, COUNT(*) AS veces FROM carga_pendiente GROUP BY columna, valor, problema ORDER BY veces DESC LIMIT 40;"
} | mysql --local-infile=1 --table
mysql -e "SET GLOBAL local_infile = 0"
echo
echo "Carga terminada. Arriba: el resumen y los valores que conviene revisar."
echo "Después, en la página, la administración asigna los participantes a cada trabajadora social (Usuarios → Asignar participantes)."

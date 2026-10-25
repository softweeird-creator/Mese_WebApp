#!/usr/bin/env bash
# =====================================================================
#  pruebas/probar_todo.sh — instala la base desde cero en un MySQL de
#  PRUEBA y corre todas las pruebas:
#    1. 01..06 en orden
#    2. 07_pruebas.sql (reglas de la base)
#    3. pruebas_carga.sql con los CSV ficticios de pruebas/datos/ (06)
#    4. 08_seguridad.sql con contraseñas de prueba y revisa los permisos
#       entrando como mese_app y mese_reportes
#
#  BORRA la base "mese" y los usuarios mese_app / mese_reportes.
#  Nunca lo corra en el servidor real.
#
#  Uso (desde la carpeta db/):
#    BORRAR_BASE=si bash pruebas/probar_todo.sh
#  Variables opcionales: MYSQL_ROOT="mysql -uroot -pXXXX"  MYSQL_HOST=127.0.0.1
# =====================================================================
set -u
cd "$(dirname "$0")/.."

ROOT=${MYSQL_ROOT:-mysql -uroot}
HOST=${MYSQL_HOST:-127.0.0.1}
PASS_APP='PruebaApp#2026'
PASS_REP='PruebaRep#2026'
fallas=0

if [ "${BORRAR_BASE:-}" != "si" ]; then
  echo "Este script borra la base 'mese'. Si es un servidor de prueba, corra: BORRAR_BASE=si bash $0"
  exit 2
fi

paso() { echo; echo "=== $* ==="; }
ok()   { echo "  PASÓ   $*"; }
mal()  { echo "  FALLÓ  $*"; fallas=$((fallas + 1)); }

# Lee "pasaron fallaron" de la última línea de un archivo de pruebas
revisar_resumen() {
  local nombre=$1 salida=$2 ult
  ult=$(printf '%s\n' "$salida" | tail -1)
  printf '%s\n' "$salida" | grep -F 'FALLÓ' || true
  if [[ $ult =~ ^([0-9]+)[[:space:]]+0$ ]]; then ok "$nombre: ${BASH_REMATCH[1]} pasaron, 0 fallaron"
  else mal "$nombre: $ult (pasaron / fallaron)"; fi
}

paso "Instalación limpia"
$ROOT -e "DROP DATABASE IF EXISTS mese; DROP USER IF EXISTS 'mese_app'@'%', 'mese_reportes'@'%';
          DROP ROLE IF EXISTS 'mese_app_rol', 'mese_lectura_rol'; SET GLOBAL local_infile = 1;" || exit 1
for f in 01_esquema 02_catalogos 03_funciones_vistas 04_procedimientos 05_triggers 06_carga_excel; do
  if $ROOT < "$f.sql" > /dev/null; then ok "$f.sql"; else mal "$f.sql"; exit 1; fi
done

paso "07_pruebas.sql"
revisar_resumen "07_pruebas" "$($ROOT --batch --skip-column-names < 07_pruebas.sql)"

paso "06_carga_excel.sql con datos ficticios"
columnas() { local s=""; for i in $(seq 1 "$1"); do s="$s,c$(printf %02d "$i")"; done; echo "${s#,}"; }
cargar() {  # tabla, archivo, columnas, renglones de encabezado
  echo "LOAD DATA LOCAL INFILE 'pruebas/datos/$2' INTO TABLE $1 CHARACTER SET utf8mb4
        FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"' LINES TERMINATED BY '\r\n' IGNORE $4 LINES ($(columnas "$3"));"
}
salida=$( { echo "USE mese; SET @formato_fecha = '%d/%m/%Y'; TRUNCATE stg_base; TRUNCATE stg_bdi; TRUNCATE stg_historica;"
            cargar stg_base base.csv 78 5; cargar stg_bdi bdi.csv 62 5; cargar stg_historica historica.csv 26 2
            cat pruebas/pruebas_carga.sql; } | $ROOT --local-infile=1 --batch --skip-column-names)
revisar_resumen "pruebas_carga" "$salida"

paso "08_seguridad.sql con contraseñas de prueba"
sed "s/CAMBIE_ESTA_CONTRASENA_1/$PASS_APP/; s/CAMBIE_ESTA_CONTRASENA_2/$PASS_REP/" 08_seguridad.sql | $ROOT \
  && ok "08_seguridad.sql" || mal "08_seguridad.sql"

app() { MYSQL_PWD=$PASS_APP mysql -h"$HOST" -umese_app --batch --skip-column-names mese -e "$1" 2>&1; }
rep() { MYSQL_PWD=$PASS_REP mysql -h"$HOST" -umese_reportes --batch --skip-column-names mese -e "$1" 2>&1; }
permite() { local quien=$1 nombre=$2 sql=$3 r; r=$($quien "$sql"); if [[ $r == *ERROR* ]]; then mal "$nombre → $r"; else ok "$nombre"; fi; }
niega()   { local quien=$1 nombre=$2 sql=$3 r; r=$($quien "$sql"); if [[ $r == *denied* ]]; then ok "$nombre"; else mal "$nombre (se esperaba 'denied') → $r"; fi; }

permite app "mese_app tiene su rol por omisión"      "SELECT CURRENT_ROLE()"
permite app "mese_app lee vistas"                      "SELECT COUNT(*) FROM v_activo"
permite app "mese_app da de alta con el procedimiento (y crea colonia nueva)" \
  "CALL sp_alta_participante('Prueba Permisos','Zzapp',NULL,'2015-01-02','F',NULL,NULL,'Colonia Zzapp','Rosa Zzapp','Madre','4431112233',CURDATE(),'PRIM',4,'Escuela Zzapp',NULL,@id);
   SELECT IF(COUNT(*) = 1, 'ok', 'ERROR no aparece') FROM v_activo WHERE persona_id = @id;"
permite app "mese_app registra la baja"               "SET @id = (SELECT persona_id FROM v_activo WHERE nombre_completo LIKE '%Zzapp%');
   CALL sp_registrar_baja(@id, CURDATE(), 'Cambio de domicilio', NULL, NULL, NULL, NULL, NULL, NULL);
   SELECT IF(COUNT(*) = 1, 'ok', 'ERROR no aparece en bajas') FROM v_baja WHERE persona_id = @id;"
niega app "mese_app no puede INSERT directo"          "INSERT INTO cat_colonia (nombre) VALUES ('x')"
niega app "mese_app no puede UPDATE directo"          "UPDATE persona SET nombres = 'x' WHERE id = 1"
niega app "mese_app no puede DELETE directo"          "DELETE FROM visita"
niega app "mese_app no puede leer la bitácora"        "SELECT * FROM bitacora LIMIT 1"
niega app "mese_app no puede borrar la base"          "DROP DATABASE mese"
permite rep "mese_reportes lee vistas"                 "SELECT COUNT(*) FROM v_historico"
permite rep "mese_reportes saca estadísticas"          "CALL sp_estadisticas_mes(YEAR(CURDATE()), MONTH(CURDATE()))"
permite rep "mese_reportes usa la búsqueda"           "CALL sp_buscar('zzapp', 10)"
niega rep "mese_reportes no puede dar de alta"        "CALL sp_alta_participante('X','X',NULL,'2015-01-02','F',NULL,NULL,NULL,NULL,NULL,NULL,CURDATE(),'PRIM',4,NULL,NULL,@id)"
niega rep "mese_reportes no puede registrar bajas"    "CALL sp_registrar_baja(1, CURDATE(), 'Otro', NULL, NULL, NULL, NULL, NULL, NULL)"
niega rep "mese_reportes no lee tablas directo"       "SELECT * FROM persona LIMIT 1"

# Limpia lo que crearon las pruebas de permisos
$ROOT mese -e "SET @importando = 1;
  SET @p = (SELECT id FROM persona WHERE apellido_paterno = 'Zzapp');
  SET @f = (SELECT familia_id FROM participante WHERE persona_id = @p);
  DELETE FROM participante_escolaridad WHERE participante_id = @p; DELETE FROM inscripcion WHERE participante_id = @p;
  DELETE FROM participante WHERE persona_id = @p; DELETE FROM familia_integrante WHERE familia_id = @f;
  DELETE FROM persona WHERE apellido_paterno = 'Zzapp' OR nombres = 'Rosa Zzapp'; DELETE FROM familia WHERE id = @f;
  DELETE FROM cat_colonia WHERE nombre = 'Colonia Zzapp'; DELETE FROM cat_escuela WHERE nombre = 'Escuela Zzapp'; DELETE FROM bitacora;"

echo
if [ "$fallas" -eq 0 ]; then echo "TODO PASÓ"; else echo "$fallas FALLARON"; fi
exit $(( fallas > 0 ))

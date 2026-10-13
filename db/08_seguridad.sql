-- =====================================================================
--  08_seguridad.sql — usuarios con el mínimo de permisos
--
--  La aplicación se conecta con "mese_app": puede LEER vistas y catálogos
--  y EJECUTAR procedimientos, pero no puede hacer INSERT/UPDATE/DELETE
--  directo en las tablas. Así, toda escritura pasa por las reglas de los
--  procedimientos (y los procedimientos corren con los permisos de su
--  creador: SQL SECURITY DEFINER, el valor por omisión).
--
--  Cambie las contraseñas antes de correr este archivo.
--  Requiere MySQL 8.0 (roles).
-- =====================================================================
USE mese;

CREATE ROLE IF NOT EXISTS 'mese_app_rol', 'mese_lectura_rol';

-- Lectura: vistas y catálogos
GRANT SELECT ON mese.v_participante      TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.v_activo            TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.v_baja              TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.v_historico         TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.v_familiar          TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.v_visita_resumen    TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.v_respuesta         TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.v_familia_actual    TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.v_escolaridad_actual TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_colonia         TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_escuela         TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_nivel_educativo TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_parentesco      TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_causa_baja      TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_causa_baja_estadistica TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_caso_exito      TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_pregunta        TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_opcion          TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_ocupacion       TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_estado_civil    TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_tipo_sangre     TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.cat_turno           TO 'mese_lectura_rol', 'mese_app_rol';
GRANT SELECT ON mese.usuario             TO 'mese_lectura_rol', 'mese_app_rol';

-- Reportes (solo leen)
GRANT EXECUTE ON PROCEDURE mese.sp_estadisticas_mes TO 'mese_lectura_rol', 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_buscar           TO 'mese_lectura_rol', 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_reporte_visitas  TO 'mese_lectura_rol', 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_visitas_tabla    TO 'mese_lectura_rol', 'mese_app_rol';

-- Escritura: solo a través de procedimientos
GRANT EXECUTE ON PROCEDURE mese.sp_alta_participante   TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_actualizar_persona  TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_guardar_familiar    TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_guardar_escolaridad TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_registrar_baja      TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_reactivar           TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_guardar_visita      TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_eliminar_visita     TO 'mese_app_rol';

-- Usuarios (cambie las contraseñas)
CREATE USER IF NOT EXISTS 'mese_app'@'%'     IDENTIFIED BY 'CAMBIE_ESTA_CONTRASENA_1';
CREATE USER IF NOT EXISTS 'mese_reportes'@'%' IDENTIFIED BY 'CAMBIE_ESTA_CONTRASENA_2';
GRANT 'mese_app_rol' TO 'mese_app'@'%';
GRANT 'mese_lectura_rol' TO 'mese_reportes'@'%';
SET DEFAULT ROLE 'mese_app_rol' TO 'mese_app'@'%';
SET DEFAULT ROLE 'mese_lectura_rol' TO 'mese_reportes'@'%';

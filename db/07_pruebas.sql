-- =====================================================================
--  07_pruebas.sql — pruebas automáticas de las reglas de la base
--  Correr después de 01..05 (con o sin datos cargados). Al final muestra
--  una tabla con cada prueba y si pasó. Borra lo que crea.
-- =====================================================================
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;   -- misma intercalación que la base

DROP TABLE IF EXISTS prueba_resultado;
CREATE TABLE prueba_resultado (
  n INT AUTO_INCREMENT PRIMARY KEY, prueba VARCHAR(160), esperado VARCHAR(10), obtenido VARCHAR(10),
  paso BOOLEAN AS (esperado = obtenido) STORED, mensaje VARCHAR(300)
) ENGINE=InnoDB;

DROP PROCEDURE IF EXISTS _probar;
DROP PROCEDURE IF EXISTS _afirmar;
DROP PROCEDURE IF EXISTS _pruebas;
DELIMITER //
-- Ejecuta una instrucción y anota si dio error o no (esperado: 'ERROR' u 'OK')
CREATE PROCEDURE _probar(IN p_nombre VARCHAR(160), IN p_esperado VARCHAR(10), IN p_sql TEXT)
BEGIN
  DECLARE v_msg VARCHAR(300) DEFAULT NULL;
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
  SET @p_sql = p_sql;
  PREPARE st_prueba FROM @p_sql; EXECUTE st_prueba; DEALLOCATE PREPARE st_prueba;
  INSERT INTO prueba_resultado (prueba, esperado, obtenido, mensaje) VALUES (p_nombre, p_esperado, IF(v_msg IS NULL, 'OK', 'ERROR'), v_msg);
END //

-- Compara un valor calculado con el esperado
CREATE PROCEDURE _afirmar(IN p_nombre VARCHAR(160), IN p_esperado VARCHAR(100), IN p_obtenido VARCHAR(100))
BEGIN
  INSERT INTO prueba_resultado (prueba, esperado, obtenido, mensaje)
  VALUES (p_nombre, 'SI', IF(p_esperado <=> p_obtenido, 'SI', 'NO'), CONCAT('esperado ', COALESCE(p_esperado, 'NULL'), ', obtenido ', COALESCE(p_obtenido, 'NULL')));
END //

CREATE PROCEDURE _pruebas()
BEGIN
  DECLARE v_p, v_p2, v_fam INT UNSIGNED; DECLARE v_activos INT; DECLARE v_vis INT UNSIGNED; DECLARE v_txt VARCHAR(100);
  SET @usuario_id = 1;
  SET v_activos = (SELECT COUNT(*) FROM v_activo);

  -- ---- Personas ----
  CALL _probar('CURP con formato inválido se rechaza', 'ERROR', "INSERT INTO persona (nombres, curp) VALUES ('Prueba', 'PEMA1O0101HMNRRNA7')");
  CALL _probar('Género fuera de F/M se rechaza', 'ERROR', "INSERT INTO persona (nombres, genero) VALUES ('Prueba', 'X')");
  CALL _probar('Fecha de nacimiento futura se rechaza (trigger)', 'ERROR', "INSERT INTO persona (nombres, fecha_nacimiento) VALUES ('Prueba', CURDATE() + INTERVAL 1 DAY)");
  CALL _probar('Nombre vacío se rechaza', 'ERROR', "INSERT INTO persona (nombres) VALUES ('   ')");
  INSERT INTO persona (nombres, apellido_paterno, telefono) VALUES ('  Prueba   Teléfono ', 'Zzprueba', '44-33-67-12-07');
  SET v_p = LAST_INSERT_ID();
  CALL _afirmar('El teléfono se guarda solo con dígitos (trigger)', '4433671207', (SELECT telefono FROM persona WHERE id = v_p));
  CALL _afirmar('Los espacios dobles del nombre se limpian (trigger)', 'Prueba Teléfono', (SELECT nombres FROM persona WHERE id = v_p));
  DELETE FROM persona WHERE id = v_p;

  -- ---- Alta, baja y reactivación ----
  CALL sp_alta_participante('Zzprueba José', 'Pérez', 'Núñez', '2014-05-10', 'M', NULL, NULL, 'Colonia de prueba', 'María Núñez Zzprueba', 'Madre', '443-111-2233',
                            CURDATE() - INTERVAL 1 YEAR, 'PRIM', 5, 'Primaria de prueba', NULL, v_p);
  CALL _afirmar('Alta: aparece en participantes activos', CAST(v_activos + 1 AS CHAR), (SELECT CAST(COUNT(*) AS CHAR) FROM v_activo));
  CALL _afirmar('Alta: se creó su tutora', 'Madre', (SELECT parentesco_tutor FROM v_participante WHERE persona_id = v_p));
  CALL _afirmar('Alta: escolaridad Primaria 5°', 'Primaria 5', (SELECT CONCAT(nivel, ' ', grado) FROM v_participante WHERE persona_id = v_p));
  SET v_fam = (SELECT familia_id FROM participante WHERE persona_id = v_p);
  CALL _probar('Grado inexistente (Secundaria 5°) se rechaza', 'ERROR',
    CONCAT("INSERT INTO participante_escolaridad (participante_id, ciclo_id, nivel_id, grado) VALUES (", v_p, ", fn_ciclo(CURDATE()) + 1, (SELECT id FROM cat_nivel_educativo WHERE clave = 'SEC'), 5)"));
  CALL _probar('No puede tener dos periodos abiertos', 'ERROR', CONCAT("INSERT INTO inscripcion (participante_id, fecha_ingreso) VALUES (", v_p, ", CURDATE())"));
  CALL _probar('Fecha de baja anterior al ingreso se rechaza', 'ERROR', CONCAT("UPDATE inscripcion SET fecha_baja = fecha_ingreso - INTERVAL 1 DAY, causa_baja_id = 1 WHERE participante_id = ", v_p));
  CALL _probar('Ingreso con fecha futura se rechaza (trigger)', 'ERROR', CONCAT("UPDATE inscripcion SET fecha_ingreso = CURDATE() + INTERVAL 3 DAY WHERE participante_id = ", v_p));
  CALL _probar('Baja con causa inexistente se rechaza', 'ERROR', CONCAT("CALL sp_registrar_baja(", v_p, ", CURDATE(), 'No existe', NULL, NULL, NULL, NULL, NULL, NULL)"));
  CALL _probar('Baja válida', 'OK', CONCAT("CALL sp_registrar_baja(", v_p, ", CURDATE(), 'Cambio de domicilio', 'Continúa estudiando', NULL, 'Se mudó a otra ciudad', NULL, 'Económico/Emocional', 'Medio')"));
  CALL _afirmar('Baja: guarda nivel y tipos de riesgo al egreso', 'Medio 2',
    (SELECT CONCAT(nr.nombre, ' ', (SELECT COUNT(*) FROM inscripcion_riesgo r WHERE r.inscripcion_id = i.id AND r.momento = 'EGRESO'))
     FROM inscripcion i JOIN cat_nivel_riesgo nr ON nr.id = i.riesgo_egreso_id WHERE i.participante_id = v_p));
  CALL _afirmar('Baja: pasa al panel de bajas', 'Cambio de domicilio', (SELECT causa_baja FROM v_baja WHERE persona_id = v_p));
  CALL _afirmar('Baja: guarda el grado con el que salió', 'Primaria 5', (SELECT CONCAT(ne.nombre, ' ', i.grado_final) FROM inscripcion i JOIN cat_nivel_educativo ne ON ne.id = i.nivel_final_id WHERE i.participante_id = v_p));
  CALL _afirmar('Baja: queda en la bitácora', 'SI', IF(EXISTS (SELECT 1 FROM bitacora WHERE tabla = 'inscripcion' AND accion = 'UPDATE' AND JSON_EXTRACT(despues, '$.baja') IS NOT NULL AND usuario_id = 1), 'SI', 'NO'));
  CALL _probar('Dar de baja dos veces se rechaza', 'ERROR', CONCAT("CALL sp_registrar_baja(", v_p, ", CURDATE(), 'Otro', NULL, NULL, NULL, NULL, NULL, NULL)"));
  CALL _probar('Reactivar con fecha dentro del periodo anterior se rechaza (trigger)', 'ERROR', CONCAT("CALL sp_reactivar(", v_p, ", CURDATE() - INTERVAL 2 MONTH)"));
  CALL _probar('Reactivar', 'OK', CONCAT("CALL sp_reactivar(", v_p, ", CURDATE())"));
  CALL _afirmar('Reactivar: vuelve a activos con 2 periodos', 'ACTIVO 2', (SELECT CONCAT(estado, ' ', periodos) FROM v_participante WHERE persona_id = v_p));
  CALL _afirmar('Histórico: resultado "Sigue activo"', 'Sigue activo', (SELECT resultado FROM v_historico WHERE persona_id = v_p));

  -- ---- Búsqueda sin acentos ----
  DROP TEMPORARY TABLE IF EXISTS t_b;
  CREATE TEMPORARY TABLE t_b (tipo VARCHAR(20), persona_id INT, nombre VARCHAR(210), detalle VARCHAR(400));
  SET v_txt = (SELECT nombre_completo FROM persona WHERE id = v_p);
  CALL _afirmar('Búsqueda: "zzprueba jose perez" encuentra a "Zzprueba José Pérez"', 'SI',
    IF((SELECT COUNT(*) FROM v_participante WHERE nombre_completo LIKE '%zzprueba%jose%perez%') = 1, 'SI', 'NO'));

  -- ---- Cuestionario ----
  INSERT INTO visita (familia_id, participante_id, fecha) VALUES (v_fam, v_p, CURDATE());
  SET v_vis = LAST_INSERT_ID();
  CALL _probar('Respuesta válida ("Su casa es: Rentada")', 'OK',
    CONCAT("INSERT INTO visita_respuesta (visita_id, pregunta_id, opcion_id) SELECT ", v_vis, ", q.id, o.id FROM cat_pregunta q JOIN cat_opcion o ON o.pregunta_id = q.id WHERE q.clave = 'casa' AND o.etiqueta = 'Rentada'"));
  CALL _probar('Segunda respuesta a pregunta de respuesta única se rechaza (trigger)', 'ERROR',
    CONCAT("INSERT INTO visita_respuesta (visita_id, pregunta_id, opcion_id) SELECT ", v_vis, ", q.id, o.id FROM cat_pregunta q JOIN cat_opcion o ON o.pregunta_id = q.id WHERE q.clave = 'casa' AND o.etiqueta = 'Propia'"));
  CALL _probar('Opción de otra pregunta se rechaza (llave compuesta)', 'ERROR',
    CONCAT("INSERT INTO visita_respuesta (visita_id, pregunta_id, opcion_id) SELECT ", v_vis, ", (SELECT id FROM cat_pregunta WHERE clave = 'comidas'), o.id FROM cat_opcion o JOIN cat_pregunta q ON q.id = o.pregunta_id WHERE q.clave = 'piso' AND o.etiqueta = 'Vitropiso'"));
  CALL _probar('"Otro" escrito en pregunta que no lo permite se rechaza (trigger)', 'ERROR',
    CONCAT("INSERT INTO visita_respuesta (visita_id, pregunta_id, texto_otro) SELECT ", v_vis, ", id, 'algo' FROM cat_pregunta WHERE clave = 'hig'"));
  CALL _probar('Visita con fecha futura se rechaza (trigger)', 'ERROR', CONCAT("UPDATE visita SET fecha = CURDATE() + INTERVAL 1 DAY WHERE id = ", v_vis));
  CALL _probar('Monto negativo se rechaza', 'ERROR', CONCAT("INSERT INTO visita_monto (visita_id, concepto_id, monto) VALUES (", v_vis, ", 1, -5)"));
  DELETE FROM visita WHERE id = v_vis;

  -- ---- Visita enviada desde el teléfono (mismo formato que guarda la página) ----
  SET @json = CONCAT('{"id":"zzprueba-uuid-1","est":"Completa","mod":"', DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 1 HOUR, '%Y-%m-%dT%H:%i:%s'), '.000Z","d":{',
    '"ts":"Trabajadora Zzprueba","fecha":"', CURDATE(), '","nom":"Zzprueba José","ap_p":"Pérez","ap_m":"Núñez","col":"Colonia de prueba",',
    '"casa":"Rentada","serv":["Agua","Luz"],"piso":["Cemento","Tierra"],"car":["Obra negra"],"car_ot":"Azotea","comidas":"Tres","deu":"Sí",',
    '"fam":[{"n":"María Núñez Zzprueba","par":"Madre","ed":"38","oc":"Comercio","ing":"6500"},{"n":"Juan Pérez Zzprueba","par":"Padre","ing":"4000"}],',
    '"ap_bj":"1900","eg_renta":"2500","eg_alim":"3000","cov_p":"Sí","cov_p_d":"2",',
    '"ant":[{"n":"Abuela Rosa","par":"Abuela","enf":"Diabetes","at":"IMSS"}],"diag":"Prueba automática","gps":"19.700000,-101.190000",',
    '"gen":"Hombre","fnac":"2014-05-10","curp":"penj140510hmnrxs09","tel_p":"443 555 1234","mail":"Familia@Zzprueba.com","pat":["Repsol","Bécalos"],',
    '"carrera":"Carrera Zzprueba","aviso":"Firmado","nivel_pobreza":"Pobreza","dx_nutricional":"Sobrepeso"}}');
  CALL _probar('sp_guardar_visita: guarda una visita de la página', 'OK', "CALL sp_guardar_visita(@json, NULL)");
  SET v_vis = (SELECT id FROM visita WHERE uuid_cliente = 'zzprueba-uuid-1');
  CALL _afirmar('Visita: se enlazó al participante existente (no lo duplicó)', CAST(v_p AS CHAR), (SELECT CAST(participante_id AS CHAR) FROM visita WHERE id = v_vis));
  CALL _afirmar('Visita: respuestas guardadas (casa, 2 servicios, 2 pisos, car + otro, comidas, deudas, pobreza, dx nutricional)', '11', (SELECT CAST(COUNT(*) AS CHAR) FROM visita_respuesta WHERE visita_id = v_vis));
  CALL _afirmar('Visita: ingreso total = 6500 + 4000', '10500.00', (SELECT CAST(ingreso_total AS CHAR) FROM v_visita_resumen WHERE visita_id = v_vis));
  CALL _afirmar('Visita: balance = 10500 + 1900 − 5500', '6900.00', (SELECT CAST(balance AS CHAR) FROM v_visita_resumen WHERE visita_id = v_vis));
  CALL _afirmar('Visita: reconoció a la madre ya registrada (no la duplicó)', '1', (SELECT CAST(COUNT(*) AS CHAR) FROM familia_integrante fi JOIN persona p ON p.id = fi.persona_id WHERE fi.familia_id = v_fam AND p.nombre_completo LIKE 'María Núñez Zzprueba%'));
  CALL _afirmar('Visita: vacuna y antecedente guardados', '1-1', (SELECT CONCAT((SELECT COUNT(*) FROM visita_vacuna WHERE visita_id = v_vis), '-', (SELECT COUNT(*) FROM visita_antecedente WHERE visita_id = v_vis))));
  CALL _afirmar('Visita: actualiza género, nacimiento, CURP y teléfono del participante', 'M 2014-05-10 PENJ140510HMNRXS09 4435551234',
    (SELECT CONCAT_WS(' ', genero, fecha_nacimiento, curp, telefono) FROM persona WHERE id = v_p));
  CALL _afirmar('Visita: becas Repsol y Bécalos, carrera, correo y aviso de privacidad', '2 Carrera Zzprueba familia@zzprueba.com SI',
    (SELECT CONCAT_WS(' ', (SELECT COUNT(*) FROM participante_beca WHERE participante_id = v_p AND hasta IS NULL),
                      (SELECT carrera FROM v_escolaridad_actual WHERE participante_id = v_p), f.correo, IF(f.aviso_privacidad IS NULL, 'NO', 'SI'))
     FROM familia f WHERE f.id = v_fam));
  CALL _afirmar('Visita: aparece como situación actual de la familia', 'Rentada', (SELECT casa FROM v_familia_actual WHERE familia_id = v_fam));
  -- Un teléfono con una copia vieja no sobrescribe la versión más nueva
  SET @json_viejo = REPLACE(REPLACE(@json, '"casa":"Rentada"', '"casa":"Propia"'), DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 1 HOUR, '%Y-%m-%dT%H'), DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 5 HOUR, '%Y-%m-%dT%H'));
  CALL sp_guardar_visita(@json_viejo, NULL);
  CALL _afirmar('Sincronización: una copia más vieja no sobrescribe', 'Rentada', (SELECT respuesta FROM v_respuesta WHERE visita_id = v_vis AND clave = 'casa'));
  SET @json_nuevo = REPLACE(REPLACE(@json, '"casa":"Rentada"', '"casa":"Prestada"'), DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 1 HOUR, '%Y-%m-%dT%H'), DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%dT%H'));
  CALL sp_guardar_visita(@json_nuevo, NULL);
  CALL _afirmar('Sincronización: una copia más nueva sí actualiza (sin duplicar)', 'Prestada 1', (SELECT CONCAT(respuesta, ' ', (SELECT COUNT(*) FROM visita WHERE uuid_cliente = 'zzprueba-uuid-1')) FROM v_respuesta WHERE visita_id = v_vis AND clave = 'casa'));
  CALL _probar('Datos del programa (becado, grupo, trabajadora, beca)', 'OK', CONCAT("CALL sp_datos_programa(", v_p, ", 2, 3, 'Trabajadora Zzprueba', 'Soriana', NULL)"));
  CALL _afirmar('Datos del programa: cambia la beca a Soriana y guarda becado 2, grupo 3', 'Soriana 2 3',
    (SELECT CONCAT_WS(' ', (SELECT GROUP_CONCAT(cp.nombre) FROM participante_beca b JOIN cat_patrocinador cp ON cp.id = b.patrocinador_id
                            WHERE b.participante_id = v_p AND b.hasta IS NULL), numero_becado, grupo_beca) FROM participante WHERE persona_id = v_p));
  CALL _probar('Visita terminada sin nombre se rechaza', 'ERROR', "CALL sp_guardar_visita('{\"id\":\"zzprueba-uuid-2\",\"est\":\"Completa\",\"d\":{\"fecha\":\"2026-01-01\"}}', NULL)");

  -- ---- Acceso a la página ----
  CALL sp_usuario_guardar(NULL, 'Usuaria Zzprueba', 'zzprueba', NULL, 'TRABAJO_SOCIAL', 'hash-de-prueba', @u);
  CALL _probar('Usuario repetido se rechaza', 'ERROR', "CALL sp_usuario_guardar(NULL, 'Otra', 'zzprueba', NULL, 'TRABAJO_SOCIAL', 'x', @u2)");
  CALL _probar('Usuario con espacios o acentos se rechaza', 'ERROR', "CALL sp_usuario_guardar(NULL, 'Otra', 'maría lópez', NULL, 'TRABAJO_SOCIAL', 'x', @u2)");
  CALL sp_acceso_registrar(@u, FALSE, NULL, NULL, NULL); CALL sp_acceso_registrar(@u, FALSE, NULL, NULL, NULL);
  CALL sp_acceso_registrar(@u, FALSE, NULL, NULL, NULL); CALL sp_acceso_registrar(@u, FALSE, NULL, NULL, NULL);
  CALL _afirmar('Acceso: 4 intentos fallidos aún no bloquean', '0', (SELECT CAST(bloqueado AS CHAR) FROM v_usuario WHERE id = @u));
  CALL sp_acceso_registrar(@u, FALSE, NULL, NULL, NULL);
  CALL _afirmar('Acceso: el 5º intento fallido bloquea 15 minutos', '1', (SELECT CAST(bloqueado AS CHAR) FROM v_usuario WHERE id = @u));
  CALL sp_acceso_registrar(@u, TRUE, REPEAT('a', 64), 'Prueba', '127.0.0.1');
  CALL sp_acceso_registrar(@u, TRUE, REPEAT('b', 64), 'Prueba', '127.0.0.1');
  CALL _afirmar('Acceso: entrar desbloquea y abre sesiones', '0 2', (SELECT CONCAT(bloqueado, ' ', sesiones_abiertas) FROM v_usuario WHERE id = @u));
  CALL sp_usuario_clave(@u, 'hash-nuevo', FALSE, REPEAT('a', 64));
  CALL _afirmar('Acceso: cambiar la contraseña cierra las otras sesiones', '1', (SELECT CAST(sesiones_abiertas AS CHAR) FROM v_usuario WHERE id = @u));
  CALL sp_sesion_cerrar(REPEAT('a', 64));
  CALL _afirmar('Acceso: salir cierra la sesión (ya no se reconoce)', '0',
    (SELECT CAST(COUNT(*) AS CHAR) FROM sesion WHERE token_hash = REPEAT('a', 64) AND cerrada_en IS NULL));
  CALL _probar('No se puede desactivar al último administrador', 'ERROR',
    CONCAT('CALL sp_usuario_activar(', (SELECT id FROM v_usuario WHERE login = 'admin'), ', FALSE)'));
  DELETE FROM usuario WHERE id = @u;

  -- ---- Reportes ----
  CALL _probar('Estadísticas del mes se generan', 'OK', CONCAT('CALL sp_estadisticas_mes(', YEAR(CURDATE()), ',', MONTH(CURDATE()), ')'));
  CALL _probar('Reporte de visitas se genera', 'OK', 'CALL sp_reporte_visitas(NULL, NULL, NULL, NULL)');
  CALL _probar('Tabla de visitas (columnas dinámicas) se genera', 'OK', 'CALL sp_visitas_tabla(NULL, NULL)');
  CALL _probar('Búsqueda general se ejecuta', 'OK', "CALL sp_buscar('zzprueba', 10)");

  -- ---- Limpieza ----
  SET @importando = 1;
  DELETE FROM visita WHERE familia_id = v_fam;
  DELETE FROM participante_beca WHERE participante_id = v_p;
  DELETE FROM participante_escolaridad WHERE participante_id = v_p;
  DELETE FROM inscripcion WHERE participante_id = v_p;
  DELETE FROM participante WHERE persona_id = v_p;
  DELETE FROM familia_integrante WHERE familia_id = v_fam;
  DELETE FROM persona WHERE nombre_completo LIKE '%Zzprueba%' OR nombres LIKE 'Abuela Rosa%';
  DELETE FROM familia WHERE id = v_fam;
  DELETE FROM usuario WHERE nombre IN ('Trabajadora Zzprueba', 'Usuaria Zzprueba');
  DELETE FROM cat_colonia WHERE nombre = 'Colonia de prueba';
  DELETE FROM cat_escuela WHERE nombre = 'Primaria de prueba';
  DELETE FROM cat_carrera WHERE nombre = 'Carrera Zzprueba';
  DELETE FROM bitacora WHERE registro_id IN (SELECT id FROM (SELECT CAST(v_p AS CHAR) AS id) x) OR JSON_EXTRACT(despues, '$.participante') = v_p OR JSON_EXTRACT(antes, '$.participante') = v_p;
  SET @importando = 0;
END //
DELIMITER ;

CALL _pruebas();
SELECT n, prueba, IF(paso, 'PASÓ', '*** FALLÓ ***') AS resultado, mensaje FROM prueba_resultado ORDER BY n;
SELECT SUM(paso) AS pasaron, SUM(NOT paso) AS fallaron FROM prueba_resultado;
DROP PROCEDURE _probar; DROP PROCEDURE _afirmar; DROP PROCEDURE _pruebas;

-- =====================================================================
--  pruebas/pruebas_pagina.sql — pruebas de 09_pagina.sql (guardar desde
--  la página) con personas inventadas. Las corre probar_todo.sh.
--  ¡Solo en una base de prueba! Deja los registros de prueba en la base.
-- =====================================================================
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;   -- misma intercalación que la base

DROP TABLE IF EXISTS prueba_pagina_resultado;
CREATE TABLE prueba_pagina_resultado (
  n INT AUTO_INCREMENT PRIMARY KEY, prueba VARCHAR(160), esperado VARCHAR(200), obtenido VARCHAR(200),
  paso BOOLEAN AS (esperado <=> obtenido) STORED
) ENGINE=InnoDB;

DROP PROCEDURE IF EXISTS _afirmar;
DROP PROCEDURE IF EXISTS _error_de;
DROP PROCEDURE IF EXISTS _pruebas_pagina;
DELIMITER //
CREATE PROCEDURE _afirmar(IN p_nombre VARCHAR(160), IN p_esperado VARCHAR(200), IN p_obtenido VARCHAR(200))
BEGIN
  INSERT INTO prueba_pagina_resultado (prueba, esperado, obtenido) VALUES (p_nombre, p_esperado, p_obtenido);
END //

-- Corre una instrucción y devuelve el mensaje de error (NULL si no falló)
CREATE PROCEDURE _error_de(IN p_sql TEXT, OUT p_err TEXT)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION GET DIAGNOSTICS CONDITION 1 p_err = MESSAGE_TEXT;
  SET p_err = NULL, @s = p_sql;
  PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;
END //

CREATE PROCEDURE _pruebas_pagina()
BEGIN
  DECLARE v_admin, v_ts, v_consulta SMALLINT UNSIGNED;
  DECLARE v_ana, v_luis, v_fam, v_abuela, v_hist INT UNSIGNED;
  DECLARE v_err TEXT;

  SET v_admin = (SELECT id FROM usuario WHERE rol = 'ADMIN' ORDER BY id LIMIT 1);
  CALL sp_usuario_guardar(NULL, 'Zzts Pagina', 'zzts_pagina', NULL, 'TRABAJO_SOCIAL', NULL, NULL, 'x', v_ts);
  CALL sp_usuario_guardar(NULL, 'Zzconsulta Pagina', 'zzconsulta_pagina', NULL, 'CONSULTA', NULL, NULL, 'x', v_consulta);
  SET @admin = v_admin, @ts = v_ts, @consulta = v_consulta;

  -- Alta desde la página
  CALL sp_pagina_activo(v_admin, NULL, '{"n":"Ana Sofía Zzpag de la Torre","fn":"2015-03-04","g":"Mujer","sangre":"O−","nv":"Primaria","gr":5,
    "esc":"Escuela Zzpag","tur":"Matutino","grp":"B","y":2024,"m":8,"gb":2,"pat":"Repsol / Bécalos","mad":"Patricia Zzpag","tel":"443 123 4567",
    "telp":"","mail":"familia@zzpag.mx","col":"Colonia Zzpag","av":"Firmado"}', v_ana);
  CALL _afirmar('alta: separa nombre y apellidos', 'Ana Sofía|Zzpag|de la Torre',
    (SELECT CONCAT_WS('|', nombres, apellido_paterno, apellido_materno) FROM persona WHERE id = v_ana));
  CALL _afirmar('alta: queda activo con su escuela', 'Primaria 5 Escuela Zzpag Matutino',
    (SELECT CONCAT_WS(' ', nivel, grado, escuela, turno) FROM v_activo WHERE persona_id = v_ana));
  CALL _afirmar('alta: "Repsol / Bécalos" son dos becas', 'Bécalos / Repsol', (SELECT becas FROM v_activo WHERE persona_id = v_ana));
  CALL _afirmar('alta: madre como tutora con teléfono limpio', 'Patricia Zzpag 4431234567',
    (SELECT CONCAT_WS(' ', tutor, telefono_tutor) FROM v_activo WHERE persona_id = v_ana));
  CALL _afirmar('alta: ingreso agosto 2024, aviso firmado, tipo de sangre', '2024-08-01 1 O-',
    (SELECT CONCAT_WS(' ', fecha_ingreso, aviso_privacidad IS NOT NULL, tipo_sangre) FROM v_activo WHERE persona_id = v_ana));

  -- Permisos y alcance
  CALL _error_de(CONCAT('CALL sp_pagina_activo(', v_consulta, ', NULL, ''{"n":"Zz Nadie"}'', @x)'), v_err);
  CALL _afirmar('solo consulta no puede agregar', 'No tiene permiso para esto. Hable con la administración de MESE.', v_err);
  CALL _error_de(CONCAT('CALL sp_pagina_activo(', v_ts, ', ', v_ana, ', ''{"n":"Ana Sofía Zzpag de la Torre"}'', @x)'), v_err);
  CALL _afirmar('trabajo social no edita a quien no atiende', 'Ese participante no está entre los que usted atiende.', v_err);
  CALL sp_pagina_activo(v_ts, NULL, '{"n":"Luis Zzpag Mora","g":"Hombre","ed":12,"nv":"Secundaria","gr":1,"ts":"Otra Persona"}', v_luis);
  CALL _afirmar('lo que agrega trabajo social queda asignado a ella', v_ts, (SELECT trabajadora_id FROM participante WHERE persona_id = v_luis));
  CALL _afirmar('solo con la edad se guarda una fecha aproximada', '12 1',
    (SELECT CONCAT_WS(' ', fn_edad(fecha_nacimiento, CURDATE()), fecha_nac_aprox) FROM persona WHERE id = v_luis));
  CALL sp_pagina_activo(v_ts, v_luis, '{"n":"Luis Zzpag Mora","g":"Hombre","ed":12,"nv":"Secundaria","gr":2}', @x);
  CALL _afirmar('trabajo social edita a los suyos', 'Secundaria 2', (SELECT CONCAT_WS(' ', nivel, grado) FROM v_activo WHERE persona_id = v_luis));

  -- Validaciones con mensaje claro
  CALL _error_de(CONCAT('CALL sp_pagina_activo(', v_admin, ', NULL, ''{"n":"Zz Curp Mala","curp":"ABC"}'', @x)'), v_err);
  CALL _afirmar('CURP inválida', 'La CURP no es válida: son 18 letras y números, por ejemplo AUCL160726HMNBSNA5.', v_err);
  CALL _error_de(CONCAT('CALL sp_pagina_activo(', v_admin, ', NULL, ''{"n":"Zz Grado Malo","nv":"Secundaria","gr":5}'', @x)'), v_err);
  CALL _afirmar('grado que no existe', 'Escuela: Secundaria no tiene 5° grado.', v_err);
  CALL _error_de(CONCAT('CALL sp_pagina_activo(', v_admin, ', NULL, ''{"n":"Zz Tel Malo","tel":"12345"}'', @x)'), v_err);
  CALL _afirmar('teléfono incompleto', 'Los teléfonos deben tener 10 dígitos.', v_err);
  CALL _afirmar('una alta rechazada no deja nada a medias', '0', (SELECT COUNT(*) FROM persona WHERE nombres LIKE 'Zz%' AND apellido_paterno IN ('Curp', 'Grado', 'Tel')));

  -- Familiares
  CALL sp_pagina_familiar(v_admin, NULL, '{"n":"Lupita Zzpag","par":"Abuelo(a)","hijo":"Ana Sofía","g":"Mujer","esl":"Hasta primaria","oc":"Hogar","ed":66}', v_abuela);
  CALL _afirmar('familiar: "Abuelo(a)" mujer = Abuela, en la familia de Ana', 'Abuela 0 Primaria',
    (SELECT CONCAT_WS(' ', parentesco, es_tutor, escolaridad) FROM v_familiar WHERE persona_id = v_abuela AND familia_id = (SELECT familia_id FROM participante WHERE persona_id = v_ana)));
  CALL _error_de(CONCAT('CALL sp_pagina_familiar(', v_admin, ', NULL, ''{"n":"Zz Huerfano","par":"Padre","hijo":"Nadie Zzinexistente"}'', @x)'), v_err);
  CALL _afirmar('familiar de un participante que no existe', 'No encontré al participante "Nadie Zzinexistente". Elíjalo de la lista.', v_err);
  CALL sp_pagina_familiar(v_admin, v_abuela, '{"n":"Lupita Zzpag","par":"Abuelo(a)","g":"Mujer","esl":"Hasta primaria","oc":"Hogar","ed":66}', @x);
  CALL _afirmar('familiar: editar sin cambios conserva el parentesco', 'Abuela', (SELECT parentesco FROM v_familiar WHERE persona_id = v_abuela));

  -- Baja y reactivar
  CALL _error_de(CONCAT('CALL sp_pagina_baja(', v_consulta, ', ', v_ana, ', ''{"mot":"Otro"}'')'), v_err);
  CALL _afirmar('solo consulta no puede dar de baja', 'No tiene permiso para esto. Hable con la administración de MESE.', v_err);
  CALL sp_pagina_baja(v_admin, v_ana, '{"fb":"2025-06-30","mot":"Cambio de domicilio","ce":"Cambio de residencia","rte":"Económico","rne":"Medio","mo":"Se mudó"}');
  CALL _afirmar('baja con fecha anterior a sus becas', 'Cambio de domicilio 2025-06-30 Medio',
    (SELECT CONCAT_WS(' ', causa_baja, fecha_baja, nivel_riesgo_egreso) FROM v_baja WHERE persona_id = v_ana));
  CALL sp_pagina_reactivar(v_admin, v_ana);
  CALL _afirmar('reactivar', 'ACTIVO', (SELECT estado FROM v_participante WHERE persona_id = v_ana));
  CALL _error_de(CONCAT('CALL sp_pagina_reactivar(', v_admin, ', ', v_ana, ')'), v_err);
  CALL _afirmar('no se reactiva a quien ya está activo', 'Este participante ya está activo.', v_err);

  -- Registro histórico
  CALL sp_pagina_historico(v_admin, NULL, '{"n":"Paola Zzpag Arce","g":"Mujer","ci":"2019-2020","fs":"2023-07-10","eei":12,"nvi":"Secundaria","gri":1,
    "nv":"Bachillerato","gr":3,"esc":"Prepa Zzpag","res":"Caso de éxito","cx":"Preparatoria","ct":"Certificado de preparatoria","rti":"Económico",
    "rni":"Alto","rne":"Bajo","cb":"Concluyó estudios","ce":"Egreso institucional","dir":"Calle Zzpag 1","col":"Colonia Zzpag"}', v_hist);
  CALL _afirmar('histórico: entrada al inicio del ciclo y caso de éxito', '2019-08-01 2023-07-10 Caso de éxito Preparatoria 12',
    (SELECT CONCAT_WS(' ', fecha_entrada, fecha_salida, resultado, caso_exito, edad_al_entrar) FROM v_historico WHERE persona_id = v_hist));
  CALL _afirmar('histórico: no aparece como activo ni como baja actual', 'BAJA', (SELECT estado FROM v_participante WHERE persona_id = v_hist));
  CALL _error_de(CONCAT('CALL sp_pagina_historico(', v_admin, ', ', v_ana, ', ''{"n":"Ana Sofía Zzpag de la Torre","res":"No concluyó"}'', @x)'), v_err);
  CALL _afirmar('histórico: a un activo no se le cierra el periodo desde aquí',
    'Esta persona sigue activa. Para registrar su salida use "Dar de baja" en Participantes activos.', v_err);
  CALL _error_de(CONCAT('CALL sp_pagina_historico(', v_admin, ', NULL, ''{"n":"Zz Exito","res":"Caso de éxito"}'', @x)'), v_err);
  CALL _afirmar('histórico: caso de éxito pide el nivel', 'Elija el nivel con el que concluyó (caso de éxito).', v_err);
END //
DELIMITER ;

CALL _pruebas_pagina();
SELECT n, prueba, IF(paso, 'PASÓ', '*** FALLÓ ***') AS resultado, esperado, obtenido FROM prueba_pagina_resultado ORDER BY n;
SELECT SUM(paso) AS pasaron, SUM(NOT paso) AS fallaron FROM prueba_pagina_resultado;
DROP PROCEDURE _afirmar; DROP PROCEDURE _error_de; DROP PROCEDURE _pruebas_pagina;

-- =====================================================================
--  09_pagina.sql — Guardar desde la página (fase 3)
--
--  Procedimientos que reciben lo que captura la página (las mismas claves
--  cortas que usa: n, curp, fn, nv, gr...) junto con el usuario conectado.
--  Cada uno revisa en la base si ese usuario puede hacer el cambio
--  (permiso y alcance) y lo guarda en una sola transacción.
--
--  Se instala después de 08_seguridad.sql (al final da permiso de
--  ejecutarlos al usuario de la aplicación).
-- =====================================================================
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;   -- misma intercalación que la base

DROP FUNCTION IF EXISTS fn_j;
DROP FUNCTION IF EXISTS fn_jnum;
DROP FUNCTION IF EXISTS fn_jfecha;
DROP FUNCTION IF EXISTS fn_nivel_pagina;
DROP FUNCTION IF EXISTS fn_parentesco_pagina;
DROP FUNCTION IF EXISTS fn_escolaridad_pagina;
DROP PROCEDURE IF EXISTS _partir_nombre;
DROP PROCEDURE IF EXISTS _pagina_puede;
DROP PROCEDURE IF EXISTS _pagina_validar;
DROP PROCEDURE IF EXISTS _pagina_grado;
DROP PROCEDURE IF EXISTS sp_pagina_activo;
DROP PROCEDURE IF EXISTS sp_pagina_baja;
DROP PROCEDURE IF EXISTS sp_pagina_reactivar;
DROP PROCEDURE IF EXISTS sp_pagina_familiar;
DROP PROCEDURE IF EXISTS sp_pagina_historico;

DELIMITER //

-- Texto de una clave del objeto de la página ('' y null = NULL)
CREATE FUNCTION fn_j(p JSON, k VARCHAR(20)) RETURNS TEXT DETERMINISTIC NO SQL
BEGIN
  DECLARE v JSON DEFAULT JSON_EXTRACT(p, CONCAT('$.', k));
  IF v IS NULL OR JSON_TYPE(v) = 'NULL' THEN RETURN NULL; END IF;
  RETURN fn_texto(JSON_UNQUOTE(v));
END //

CREATE FUNCTION fn_jnum(p JSON, k VARCHAR(20)) RETURNS INT DETERMINISTIC NO SQL
BEGIN
  DECLARE s TEXT DEFAULT fn_j(p, k);
  RETURN IF(s REGEXP '^[0-9]{1,6}$', CAST(s AS UNSIGNED), NULL);
END //

CREATE FUNCTION fn_jfecha(p JSON, k VARCHAR(20)) RETURNS DATE DETERMINISTIC NO SQL
BEGIN
  DECLARE s TEXT DEFAULT fn_j(p, k);
  RETURN IF(s REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$', STR_TO_DATE(s, '%Y-%m-%d'), NULL);
END //

-- La página usa los nombres del Excel ("Bachillerato"); la base, su catálogo
CREATE FUNCTION fn_nivel_pagina(p TEXT) RETURNS VARCHAR(10) DETERMINISTIC READS SQL DATA
RETURN (SELECT clave FROM cat_nivel_educativo WHERE nombre = IF(p = 'Bachillerato', 'Preparatoria', p)) //

-- "Hermano(a)" + género → "Hermana"; "Tutor" → "Tutor(a)"
CREATE FUNCTION fn_parentesco_pagina(p TEXT, p_genero CHAR(1)) RETURNS VARCHAR(40) DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE base VARCHAR(40);
  IF p IS NULL THEN RETURN NULL; END IF;
  IF p = 'Tutor' THEN RETURN 'Tutor(a)'; END IF;
  IF EXISTS (SELECT 1 FROM cat_parentesco WHERE nombre = p) THEN RETURN p; END IF;
  SET base = REPLACE(p, '(a)', '');
  RETURN IF(p_genero = 'F', CONCAT(LEFT(base, CHAR_LENGTH(base) - 1), 'a'), base);
END //

-- Escolaridad de un adulto en los tres grupos de la página
CREATE FUNCTION fn_escolaridad_pagina(p_nivel TEXT) RETURNS VARCHAR(20) DETERMINISTIC NO SQL
RETURN CASE WHEN p_nivel IS NULL THEN NULL
            WHEN p_nivel IN ('Preescolar', 'Primaria', 'INEA', 'Educación especial') THEN 'Hasta primaria'
            WHEN p_nivel LIKE 'Secundaria%' THEN 'Secundaria'
            ELSE 'Preparatoria o más' END //

-- "Ana Sofía Ramírez de la Torre" → nombres "Ana Sofía", paterno "Ramírez", materno "de la Torre".
-- Con dos palabras: nombre y apellido paterno.
CREATE PROCEDURE _partir_nombre(IN p TEXT, OUT o_n VARCHAR(80), OUT o_p VARCHAR(60), OUT o_m VARCHAR(60))
BEGIN
  DECLARE s TEXT DEFAULT fn_texto(p); DECLARE w VARCHAR(100); DECLARE buf VARCHAR(200) DEFAULT '';
  DECLARE palabras TEXT DEFAULT ''; DECLARE n TINYINT DEFAULT 0;
  SET o_n = NULL, o_p = NULL, o_m = NULL;
  IF s IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Escriba el nombre completo.'; END IF;
  WHILE s <> '' DO
    SET w = SUBSTRING_INDEX(s, ' ', 1);
    SET s = IF(LOCATE(' ', s) > 0, SUBSTRING(s, LOCATE(' ', s) + 1), '');
    IF UPPER(w) IN ('DE','DEL','LA','LAS','LOS','SAN','SANTA','MC','VAN','VON') AND s <> '' THEN
      SET buf = CONCAT(buf, w, ' ');
    ELSE
      SET palabras = CONCAT(palabras, IF(n = 0, '', '|'), buf, w), buf = '', n = n + 1;
    END IF;
  END WHILE;
  IF n = 1 THEN SET o_n = palabras;
  ELSEIF n = 2 THEN SET o_n = SUBSTRING_INDEX(palabras, '|', 1), o_p = SUBSTRING_INDEX(palabras, '|', -1);
  ELSE
    SET o_m = SUBSTRING_INDEX(palabras, '|', -1),
        o_p = SUBSTRING_INDEX(SUBSTRING_INDEX(palabras, '|', -2), '|', 1),
        o_n = REPLACE(LEFT(palabras, CHAR_LENGTH(palabras) - CHAR_LENGTH(SUBSTRING_INDEX(palabras, '|', -2)) - 1), '|', ' ');
  END IF;
END //

-- Rechaza el cambio si el usuario no tiene el permiso, o si el participante no le toca
CREATE PROCEDURE _pagina_puede(IN p_usuario SMALLINT UNSIGNED, IN p_permiso VARCHAR(20), IN p_participante INT UNSIGNED)
BEGIN
  IF NOT fn_puede(p_usuario, p_permiso) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No tiene permiso para esto. Hable con la administración de MESE.';
  END IF;
  IF p_participante IS NOT NULL AND NOT fn_ve_participante(p_usuario, p_participante) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ese participante no está entre los que usted atiende.';
  END IF;
END //

-- Formatos que la base exige, con mensajes para la persona que captura
CREATE PROCEDURE _pagina_validar(IN p_persona INT UNSIGNED, IN p_curp TEXT, IN p_tel TEXT, IN p_tel2 TEXT, IN p_correo TEXT)
BEGIN
  IF p_curp IS NOT NULL AND fn_curp(p_curp) IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La CURP no es válida: son 18 letras y números, por ejemplo AUCL160726HMNBSNA5.';
  END IF;
  IF p_curp IS NOT NULL AND EXISTS (SELECT 1 FROM persona WHERE curp = UPPER(p_curp) AND id <> COALESCE(p_persona, 0)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya hay otra persona registrada con esa CURP.';
  END IF;
  IF (p_tel IS NOT NULL AND REGEXP_REPLACE(p_tel, '[^0-9]', '') NOT REGEXP '^[0-9]{10}$')
     OR (p_tel2 IS NOT NULL AND REGEXP_REPLACE(p_tel2, '[^0-9]', '') NOT REGEXP '^[0-9]{10}$') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Los teléfonos deben tener 10 dígitos.';
  END IF;
  IF p_correo IS NOT NULL AND p_correo NOT LIKE '%_@_%._%' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El correo electrónico no es válido.';
  END IF;
END //

-- Grado que no existe en ese nivel (p. ej. Secundaria 5°)
CREATE PROCEDURE _pagina_grado(IN p_nivel VARCHAR(10), IN p_grado INT, IN p_que VARCHAR(40))
BEGIN
  DECLARE v_msg VARCHAR(200);
  IF p_nivel IS NOT NULL AND p_grado IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM cat_nivel_grado ng JOIN cat_nivel_educativo ne ON ne.id = ng.nivel_id WHERE ne.clave = p_nivel AND ng.grado = p_grado) THEN
    SET v_msg = CONCAT(p_que, ': ', (SELECT nombre FROM cat_nivel_educativo WHERE clave = p_nivel), ' no tiene ', p_grado, '° grado.');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
END //

-- ---------------------------------------------------------------------
-- Participante activo: alta (p_id NULL) o edición.
-- Claves: n, curp, fn, g, ed, sangre, nv, gr, esc, car, grp, tur, y, m, ts,
--         nb, gb, pat, mad, tel, telp, mail, col, av
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_pagina_activo(IN p_usuario SMALLINT UNSIGNED, IN p_id INT UNSIGNED, IN p_json JSON, OUT p_out INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE v_n VARCHAR(80); DECLARE v_p, v_m VARCHAR(60); DECLARE v_fam, v_tutor, v_insc INT UNSIGNED;
  DECLARE v_nac DATE; DECLARE v_aprox BOOLEAN DEFAULT FALSE; DECLARE v_gen CHAR(1);
  DECLARE v_nivel VARCHAR(10); DECLARE v_grado INT; DECLARE v_ing DATE; DECLARE v_ts SMALLINT UNSIGNED;
  DECLARE v_pat VARCHAR(200); DECLARE v_msg VARCHAR(200); DECLARE v_nuevo BOOLEAN DEFAULT p_id IS NULL;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_id IS NULL THEN
    CALL _pagina_puede(p_usuario, 'AGREGAR', NULL);
  ELSE
    CALL _pagina_puede(p_usuario, 'EDITAR', p_id);
    SELECT familia_id INTO v_fam FROM participante WHERE persona_id = p_id;
    SELECT id INTO v_insc FROM inscripcion WHERE participante_id = p_id AND abierta = 1;
    IF v_insc IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este participante ya no está activo.'; END IF;
  END IF;

  CALL _pagina_validar(p_id, fn_j(p_json, 'curp'), fn_j(p_json, 'tel'), fn_j(p_json, 'telp'), fn_j(p_json, 'mail'));
  SET v_gen = CASE fn_j(p_json, 'g') WHEN 'Mujer' THEN 'F' WHEN 'Hombre' THEN 'M' END;
  SET v_nac = fn_jfecha(p_json, 'fn');
  IF v_nac IS NULL AND fn_jnum(p_json, 'ed') BETWEEN 1 AND 99 THEN      -- solo se sabe la edad
    SET v_nac = MAKEDATE(YEAR(CURDATE()) - fn_jnum(p_json, 'ed'), 1), v_aprox = TRUE;
    -- si la edad no cambió se conserva la fecha que ya se tenía
    IF fn_edad((SELECT fecha_nacimiento FROM persona WHERE id = p_id), CURDATE()) = fn_jnum(p_json, 'ed') THEN
      SELECT fecha_nacimiento, fecha_nac_aprox INTO v_nac, v_aprox FROM persona WHERE id = p_id;
    END IF;
  END IF;
  SET v_nivel = fn_nivel_pagina(fn_j(p_json, 'nv')), v_grado = fn_jnum(p_json, 'gr');
  CALL _pagina_grado(v_nivel, v_grado, 'Escuela');
  IF fn_jnum(p_json, 'y') BETWEEN 1990 AND 2100 THEN
    SET v_ing = LEAST(MAKEDATE(fn_jnum(p_json, 'y'), 1) + INTERVAL (COALESCE(fn_jnum(p_json, 'm'), 1) - 1) MONTH, CURDATE());
  END IF;
  IF fn_jnum(p_json, 'gb') IS NOT NULL AND fn_jnum(p_json, 'gb') NOT BETWEEN 1 AND 9 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El grupo de beca va del 1 al 9.';
  END IF;
  -- Trabajadora social: solo quien ve a todos la cambia; quien atiende solo a los suyos se queda con lo que agrega
  IF fn_ve_todos(p_usuario) THEN
    IF fn_j(p_json, 'ts') IS NOT NULL THEN
      SELECT id INTO v_ts FROM usuario WHERE nombre = fn_j(p_json, 'ts') AND activo LIMIT 1;
      IF v_ts IS NULL THEN
        SET v_msg = CONCAT('No hay ninguna persona activa llamada "', LEFT(fn_j(p_json, 'ts'), 80), '" en Usuarios.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
      END IF;
    END IF;
  ELSEIF p_id IS NULL THEN
    SET v_ts = p_usuario;
  ELSE
    SET v_ts = (SELECT trabajadora_id FROM participante WHERE persona_id = p_id);
  END IF;
  CALL _partir_nombre(fn_j(p_json, 'n'), v_n, v_p, v_m);

  START TRANSACTION;
  IF p_id IS NULL THEN
    INSERT INTO familia (colonia_id) VALUES (fn_colonia(fn_j(p_json, 'col'), NULL));
    SET v_fam = LAST_INSERT_ID();
    INSERT INTO persona (nombres, apellido_paterno, apellido_materno) VALUES (v_n, v_p, v_m);
    SET p_id = LAST_INSERT_ID();
    INSERT INTO participante (persona_id, familia_id, numero_becado, trabajadora_id) VALUES (p_id, v_fam, 1, v_ts);
    INSERT INTO inscripcion (participante_id, fecha_ingreso) VALUES (p_id, COALESCE(v_ing, CURDATE()));
  ELSE
    -- Si el nombre no cambió se conservan sus partes tal como están
    IF fn_j(p_json, 'n') <> (SELECT nombre_completo FROM persona WHERE id = p_id) THEN
      UPDATE persona SET nombres = v_n, apellido_paterno = v_p, apellido_materno = v_m WHERE id = p_id;
    END IF;
    UPDATE familia SET colonia_id = fn_colonia(fn_j(p_json, 'col'), NULL) WHERE id = v_fam;
    UPDATE participante SET trabajadora_id = v_ts WHERE persona_id = p_id;
    IF v_ing IS NOT NULL AND (YEAR(v_ing), MONTH(v_ing)) <> (SELECT YEAR(fecha_ingreso), MONTH(fecha_ingreso) FROM inscripcion WHERE id = v_insc) THEN
      UPDATE inscripcion SET fecha_ingreso = v_ing WHERE id = v_insc;
    END IF;
  END IF;

  UPDATE persona SET genero = v_gen, curp = UPPER(fn_j(p_json, 'curp')),
         fecha_nacimiento = v_nac, fecha_nac_aprox = v_aprox,
         tipo_sangre_id = (SELECT id FROM cat_tipo_sangre WHERE nombre = REPLACE(fn_j(p_json, 'sangre'), '−', '-')),
         telefono = REGEXP_REPLACE(fn_j(p_json, 'telp'), '[^0-9]', '')
   WHERE id = p_id;
  UPDATE participante SET numero_becado = COALESCE(fn_jnum(p_json, 'nb'), numero_becado), grupo_beca = fn_jnum(p_json, 'gb')
   WHERE persona_id = p_id;
  UPDATE familia SET correo = fn_j(p_json, 'mail'),
         aviso_privacidad = IF(fn_j(p_json, 'av') = 'Firmado', COALESCE(aviso_privacidad, CURDATE()), NULL)
   WHERE id = v_fam;

  -- Madre o tutora: se edita la registrada o se agrega una
  SELECT persona_id INTO v_tutor FROM v_tutor_principal WHERE familia_id = v_fam LIMIT 1;
  IF v_tutor IS NOT NULL AND fn_j(p_json, 'mad') IS NOT NULL THEN
    UPDATE persona SET nombres = fn_j(p_json, 'mad'), apellido_paterno = NULL, apellido_materno = NULL,
                       telefono = REGEXP_REPLACE(fn_j(p_json, 'tel'), '[^0-9]', '')
     WHERE id = v_tutor AND (nombre_completo <> fn_j(p_json, 'mad') OR NOT (telefono <=> REGEXP_REPLACE(fn_j(p_json, 'tel'), '[^0-9]', '')));
  ELSEIF v_tutor IS NULL AND fn_j(p_json, 'mad') IS NOT NULL THEN
    INSERT INTO persona (nombres, genero, telefono) VALUES (fn_j(p_json, 'mad'), 'F', REGEXP_REPLACE(fn_j(p_json, 'tel'), '[^0-9]', ''));
    SET v_tutor = LAST_INSERT_ID();
    INSERT INTO familia_integrante (familia_id, persona_id, parentesco_id, es_tutor)
    SELECT v_fam, v_tutor, id, TRUE FROM cat_parentesco WHERE nombre = 'Madre';
  END IF;

  -- Escuela del ciclo escolar actual
  IF v_nivel IS NOT NULL OR fn_j(p_json, 'esc') IS NOT NULL OR fn_j(p_json, 'car') IS NOT NULL THEN
    CALL sp_guardar_escolaridad(p_id, NULL, v_nivel, v_grado, fn_j(p_json, 'esc'), fn_j(p_json, 'tur'), fn_j(p_json, 'grp'), fn_j(p_json, 'car'));
  END IF;

  -- Becas: "Repsol / Bécalos" son dos; se cierran las que ya no están y se abren las nuevas
  SET v_pat = REPLACE(REPLACE(COALESCE(fn_j(p_json, 'pat'), ''), ' / ', ','), '/', ',');
  UPDATE participante_beca b JOIN cat_patrocinador cp ON cp.id = b.patrocinador_id
     SET b.hasta = GREATEST(b.desde, CURDATE())
   WHERE b.participante_id = p_id AND b.hasta IS NULL AND NOT FIND_IN_SET(cp.nombre, v_pat);
  INSERT IGNORE INTO participante_beca (participante_id, patrocinador_id, desde)
  SELECT p_id, cp.id, IF(v_nuevo, COALESCE(v_ing, CURDATE()), CURDATE()) FROM cat_patrocinador cp
   WHERE FIND_IN_SET(cp.nombre, v_pat)
     AND NOT EXISTS (SELECT 1 FROM participante_beca b WHERE b.participante_id = p_id AND b.patrocinador_id = cp.id AND b.hasta IS NULL);
  COMMIT;
  SET p_out = p_id;
END //

-- ---------------------------------------------------------------------
-- Dar de baja. Claves: fb (fecha), mot (causa), ce, cx, ct, rte, rne, mo
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_pagina_baja(IN p_usuario SMALLINT UNSIGNED, IN p_id INT UNSIGNED, IN p_json JSON)
MODIFIES SQL DATA
BEGIN
  CALL _pagina_puede(p_usuario, 'BAJAS', p_id);
  CALL sp_registrar_baja(p_id, COALESCE(fn_jfecha(p_json, 'fb'), CURDATE()), fn_j(p_json, 'mot'), fn_j(p_json, 'ce'), fn_j(p_json, 'cx'),
                         fn_j(p_json, 'mo'), fn_j(p_json, 'ct'), fn_j(p_json, 'rte'), fn_j(p_json, 'rne'));
END //

-- Reactivar: abre un periodo nuevo con fecha de hoy
CREATE PROCEDURE sp_pagina_reactivar(IN p_usuario SMALLINT UNSIGNED, IN p_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  CALL _pagina_puede(p_usuario, 'BAJAS', p_id);
  IF EXISTS (SELECT 1 FROM inscripcion WHERE participante_id = p_id AND abierta = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este participante ya está activo.';
  END IF;
  CALL sp_reactivar(p_id, CURDATE());
END //

-- ---------------------------------------------------------------------
-- Familiar: alta (p_id NULL) o edición.
-- Claves: n, par, hijo (participante a su cargo), esl, oc, tel, g, fn, ed
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_pagina_familiar(IN p_usuario SMALLINT UNSIGNED, IN p_id INT UNSIGNED, IN p_json JSON, OUT p_out INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE v_fam INT UNSIGNED; DECLARE v_familias INT; DECLARE v_gen CHAR(1); DECLARE v_par TINYINT UNSIGNED;
  DECLARE v_tutor BOOLEAN; DECLARE v_nac DATE; DECLARE v_aprox BOOLEAN DEFAULT FALSE; DECLARE v_esc TINYINT UNSIGNED;
  DECLARE v_msg VARCHAR(200);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  CALL _pagina_puede(p_usuario, IF(p_id IS NULL, 'AGREGAR', 'EDITAR'), NULL);
  IF fn_j(p_json, 'n') IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Escriba el nombre completo.'; END IF;
  CALL _pagina_validar(p_id, NULL, fn_j(p_json, 'tel'), NULL, NULL);
  SET v_gen = CASE fn_j(p_json, 'g') WHEN 'Mujer' THEN 'F' WHEN 'Hombre' THEN 'M' END;

  IF p_id IS NULL THEN
    -- La familia es la del participante a su cargo (de los que este usuario puede ver)
    SELECT COUNT(DISTINCT familia_id), MIN(familia_id) INTO v_familias, v_fam FROM v_participante
     WHERE (nombre_completo = fn_j(p_json, 'hijo') OR nombres = fn_j(p_json, 'hijo')) AND fn_ve_participante(p_usuario, persona_id);
    IF v_familias = 0 THEN
      SET v_msg = CONCAT('No encontré al participante "', LEFT(COALESCE(fn_j(p_json, 'hijo'), ''), 80), '". Elíjalo de la lista.');
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    ELSEIF v_familias > 1 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Hay varios participantes con ese nombre. Escriba el nombre completo.';
    END IF;
  ELSE
    SELECT MIN(familia_id) INTO v_fam FROM familia_integrante WHERE persona_id = p_id AND fn_ve_familia(p_usuario, familia_id);
    IF v_fam IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ese familiar no está entre las familias que usted atiende.'; END IF;
  END IF;

  -- Parentesco: si en la página dice lo mismo que ya está, se conserva (p. ej. "Abuela")
  SET v_par = (SELECT fi.parentesco_id FROM familia_integrante fi JOIN cat_parentesco pa ON pa.id = fi.parentesco_id
                WHERE fi.familia_id = v_fam AND fi.persona_id = p_id
                  AND (pa.nombre = fn_j(p_json, 'par') OR fn_parentesco_pagina(fn_j(p_json, 'par'), 'M') = fn_parentesco_pagina(pa.nombre, 'M')
                       OR fn_parentesco_pagina(fn_j(p_json, 'par'), 'F') = pa.nombre));
  IF v_par IS NULL THEN SET v_par = (SELECT id FROM cat_parentesco WHERE nombre = fn_parentesco_pagina(fn_j(p_json, 'par'), v_gen)); END IF;
  IF v_par IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Elija un parentesco de la lista.'; END IF;
  -- Tutor: se conserva al editar; uno nuevo lo es si es "Tutor" o si es madre o padre y la familia no tiene tutor
  SET v_tutor = COALESCE((SELECT es_tutor FROM familia_integrante WHERE familia_id = v_fam AND persona_id = p_id),
                         fn_j(p_json, 'par') = 'Tutor'
                         OR (fn_j(p_json, 'par') IN ('Madre', 'Padre') AND NOT EXISTS (SELECT 1 FROM familia_integrante WHERE familia_id = v_fam AND es_tutor)));
  SET v_nac = fn_jfecha(p_json, 'fn');
  IF v_nac IS NULL AND fn_jnum(p_json, 'ed') BETWEEN 1 AND 110 THEN SET v_nac = MAKEDATE(YEAR(CURDATE()) - fn_jnum(p_json, 'ed'), 1), v_aprox = TRUE; END IF;
  -- Escolaridad: si el grupo de la página es el mismo que ya está, se conserva el nivel exacto
  SET v_esc = (SELECT p.escolaridad_nivel_id FROM persona p JOIN cat_nivel_educativo ne ON ne.id = p.escolaridad_nivel_id
                WHERE p.id = p_id AND fn_escolaridad_pagina(ne.nombre) = fn_j(p_json, 'esl'));
  IF v_esc IS NULL THEN
    SET v_esc = (SELECT id FROM cat_nivel_educativo WHERE clave = CASE fn_j(p_json, 'esl') WHEN 'Hasta primaria' THEN 'PRIM'
                   WHEN 'Secundaria' THEN 'SEC' WHEN 'Preparatoria o más' THEN 'PREPA' END);
  END IF;

  START TRANSACTION;
  IF p_id IS NULL THEN
    INSERT INTO persona (nombres) VALUES (fn_j(p_json, 'n'));
    SET p_id = LAST_INSERT_ID();
  ELSEIF fn_j(p_json, 'n') <> (SELECT nombre_completo FROM persona WHERE id = p_id) THEN
    UPDATE persona SET nombres = fn_j(p_json, 'n'), apellido_paterno = NULL, apellido_materno = NULL WHERE id = p_id;
  END IF;
  UPDATE persona SET genero = v_gen, fecha_nacimiento = v_nac, fecha_nac_aprox = v_aprox,
         telefono = REGEXP_REPLACE(fn_j(p_json, 'tel'), '[^0-9]', ''),
         ocupacion_id = fn_ocupacion(fn_j(p_json, 'oc')),
         escolaridad_grado = IF(escolaridad_nivel_id <=> v_esc, escolaridad_grado, NULL), escolaridad_nivel_id = v_esc
   WHERE id = p_id;
  INSERT INTO familia_integrante (familia_id, persona_id, parentesco_id, es_tutor) VALUES (v_fam, p_id, v_par, v_tutor)
  ON DUPLICATE KEY UPDATE parentesco_id = VALUES(parentesco_id);
  COMMIT;
  SET p_out = p_id;
END //

-- ---------------------------------------------------------------------
-- Registro histórico: alta (p_id NULL) o edición del periodo más reciente.
-- Claves: n, g, ci, fe, fs, eei, nvi, gri, nv, gr, esc, res, cx, ct,
--         rti, rni, rte, rne, cb, ce, mo, dir, col, tel
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_pagina_historico(IN p_usuario SMALLINT UNSIGNED, IN p_id INT UNSIGNED, IN p_json JSON, OUT p_out INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE v_n VARCHAR(80); DECLARE v_p, v_m VARCHAR(60); DECLARE v_fam, v_insc, v_primera INT UNSIGNED;
  DECLARE v_ent, v_sal DATE; DECLARE v_sin, v_abierta BOOLEAN DEFAULT FALSE; DECLARE v_gen CHAR(1);
  DECLARE v_nvi, v_nvf VARCHAR(10); DECLARE v_res VARCHAR(20);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_id IS NULL THEN
    CALL _pagina_puede(p_usuario, 'AGREGAR', NULL);
  ELSE
    CALL _pagina_puede(p_usuario, 'EDITAR', p_id);
    SELECT familia_id INTO v_fam FROM participante WHERE persona_id = p_id;
    SELECT id, COALESCE(abierta, 0) = 1 INTO v_insc, v_abierta FROM v_inscripcion_actual WHERE participante_id = p_id;
    SELECT id INTO v_primera FROM inscripcion WHERE participante_id = p_id ORDER BY fecha_ingreso, id LIMIT 1;
    IF v_insc IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe ese registro.'; END IF;
  END IF;
  CALL _pagina_validar(p_id, NULL, fn_j(p_json, 'tel'), NULL, NULL);
  CALL _partir_nombre(fn_j(p_json, 'n'), v_n, v_p, v_m);

  SET v_gen = CASE fn_j(p_json, 'g') WHEN 'Mujer' THEN 'F' WHEN 'Hombre' THEN 'M' END;
  SET v_res = COALESCE(fn_j(p_json, 'res'), 'No concluyó');
  SET v_ent = fn_jfecha(p_json, 'fe'), v_sal = fn_jfecha(p_json, 'fs');
  IF v_ent IS NULL AND REGEXP_SUBSTR(COALESCE(fn_j(p_json, 'ci'), ''), '^(19|20)[0-9]{2}') <> '' THEN
    SET v_ent = MAKEDATE(CAST(REGEXP_SUBSTR(fn_j(p_json, 'ci'), '^(19|20)[0-9]{2}') AS UNSIGNED), 1) + INTERVAL 7 MONTH;   -- inicio del ciclo
  END IF;
  IF v_sal < v_ent THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de salida es anterior a la de entrada.'; END IF;
  IF v_res = 'Sigue activo' AND v_sal IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Si sigue activo no lleva fecha de salida.';
  END IF;
  IF v_res = 'Caso de éxito' AND fn_j(p_json, 'cx') IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Elija el nivel con el que concluyó (caso de éxito).';
  END IF;
  IF v_res <> 'Sigue activo' AND v_sal IS NULL AND v_ent IS NULL THEN SET v_sin = TRUE; END IF;
  IF v_res <> 'Sigue activo' AND v_sal IS NULL AND v_ent IS NOT NULL THEN SET v_sal = v_ent; END IF;   -- sale sin fecha conocida
  IF v_res = 'Sigue activo' AND v_ent IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Escriba la fecha de entrada.'; END IF;
  -- Un periodo abierto se cierra con "Dar de baja" y uno cerrado se abre con "Reactivar"
  IF p_id IS NOT NULL AND v_abierta AND v_res <> 'Sigue activo' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esta persona sigue activa. Para registrar su salida use "Dar de baja" en Participantes activos.';
  END IF;
  IF p_id IS NOT NULL AND NOT v_abierta AND v_res = 'Sigue activo' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Para que vuelva a estar activa use "Reactivar" en Bajas.';
  END IF;
  SET v_nvi = fn_nivel_pagina(fn_j(p_json, 'nvi')), v_nvf = fn_nivel_pagina(fn_j(p_json, 'nv'));
  CALL _pagina_grado(v_nvi, fn_jnum(p_json, 'gri'), 'Escolaridad inicial');
  CALL _pagina_grado(v_nvf, fn_jnum(p_json, 'gr'), 'Escolaridad final');

  START TRANSACTION;
  IF p_id IS NULL THEN
    INSERT INTO familia (calle) VALUES (NULL);
    SET v_fam = LAST_INSERT_ID();
    INSERT INTO persona (nombres, apellido_paterno, apellido_materno) VALUES (v_n, v_p, v_m);
    SET p_id = LAST_INSERT_ID();
    INSERT INTO participante (persona_id, familia_id, trabajadora_id) VALUES (p_id, v_fam, IF(fn_ve_todos(p_usuario), NULL, p_usuario));
    INSERT INTO inscripcion (participante_id, sin_fechas, fecha_ingreso, fecha_baja) VALUES (p_id, v_sin, v_ent, v_sal);
    SET v_insc = LAST_INSERT_ID(), v_primera = v_insc;
  ELSE
    IF fn_j(p_json, 'n') <> (SELECT nombre_completo FROM persona WHERE id = p_id) THEN
      UPDATE persona SET nombres = v_n, apellido_paterno = v_p, apellido_materno = v_m WHERE id = p_id;
    END IF;
    IF v_ent IS NOT NULL THEN UPDATE inscripcion SET fecha_ingreso = v_ent, sin_fechas = FALSE WHERE id = v_primera; END IF;
    IF NOT v_abierta THEN UPDATE inscripcion SET fecha_baja = v_sal, sin_fechas = v_sin WHERE id = v_insc; END IF;
  END IF;

  UPDATE persona SET genero = v_gen,
         fecha_nacimiento = IF(fn_jnum(p_json, 'eei') BETWEEN 1 AND 40 AND v_ent IS NOT NULL AND (fecha_nacimiento IS NULL OR fecha_nac_aprox),
                               MAKEDATE(YEAR(v_ent) - fn_jnum(p_json, 'eei'), 1), fecha_nacimiento),
         fecha_nac_aprox = IF(fn_jnum(p_json, 'eei') BETWEEN 1 AND 40 AND v_ent IS NOT NULL AND (fecha_nacimiento IS NULL OR fecha_nac_aprox), TRUE, fecha_nac_aprox)
   WHERE id = p_id;
  UPDATE familia SET calle = fn_j(p_json, 'dir'), colonia_id = fn_colonia(fn_j(p_json, 'col'), NULL),
         telefono = REGEXP_REPLACE(fn_j(p_json, 'tel'), '[^0-9]', '')
   WHERE id = v_fam;
  UPDATE inscripcion SET
         causa_baja_id        = IF(v_res = 'Sigue activo', NULL, (SELECT id FROM cat_causa_baja WHERE nombre = fn_j(p_json, 'cb'))),
         causa_estadistica_id = IF(v_res = 'Sigue activo', NULL, (SELECT id FROM cat_causa_baja_estadistica WHERE nombre = fn_j(p_json, 'ce'))),
         caso_exito_id        = IF(v_res = 'Caso de éxito', (SELECT id FROM cat_caso_exito WHERE nombre = fn_j(p_json, 'cx')), NULL),
         motivo               = IF(v_res = 'Sigue activo', NULL, fn_j(p_json, 'mo')),
         certificado_id       = (SELECT id FROM cat_certificado WHERE nombre = fn_j(p_json, 'ct')),
         nivel_inicial_id     = (SELECT id FROM cat_nivel_educativo WHERE clave = v_nvi),
         grado_inicial        = IF(v_nvi IS NULL, NULL, COALESCE(fn_jnum(p_json, 'gri'), 1)),
         nivel_final_id       = (SELECT id FROM cat_nivel_educativo WHERE clave = v_nvf),
         grado_final          = IF(v_nvf IS NULL, NULL, COALESCE(fn_jnum(p_json, 'gr'), (SELECT grados FROM cat_nivel_educativo WHERE clave = v_nvf))),
         riesgo_ingreso_id    = (SELECT id FROM cat_nivel_riesgo WHERE nombre = fn_j(p_json, 'rni')),
         riesgo_egreso_id     = (SELECT id FROM cat_nivel_riesgo WHERE nombre = fn_j(p_json, 'rne'))
   WHERE id = v_insc;
  DELETE FROM inscripcion_riesgo WHERE inscripcion_id = v_insc;
  INSERT IGNORE INTO inscripcion_riesgo (inscripcion_id, momento, tipo_riesgo_id)
  SELECT v_insc, x.m, tr.id FROM (SELECT 'INGRESO' AS m, fn_j(p_json, 'rti') AS t UNION ALL SELECT 'EGRESO', fn_j(p_json, 'rte')) x
  JOIN cat_tipo_riesgo tr ON FIND_IN_SET(tr.nombre, REPLACE(x.t, '/', ','));   -- "Económico/Emocional" = dos
  -- Escuela donde estaba al salir
  IF fn_j(p_json, 'esc') IS NOT NULL AND v_nvf IS NOT NULL AND COALESCE(v_sal, v_ent) IS NOT NULL THEN
    CALL sp_guardar_escolaridad(p_id, (SELECT nombre FROM cat_ciclo_escolar WHERE id = fn_ciclo(COALESCE(v_sal, v_ent))),
                                v_nvf, (SELECT grado_final FROM inscripcion WHERE id = v_insc), fn_j(p_json, 'esc'), NULL, NULL, NULL);
  END IF;
  COMMIT;
  SET p_out = p_id;
END //

DELIMITER ;

GRANT EXECUTE ON PROCEDURE mese.sp_pagina_activo    TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_pagina_baja      TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_pagina_reactivar TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_pagina_familiar  TO 'mese_app_rol';
GRANT EXECUTE ON PROCEDURE mese.sp_pagina_historico TO 'mese_app_rol';

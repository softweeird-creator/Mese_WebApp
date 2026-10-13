-- =====================================================================
--  04_procedimientos.sql — operaciones y reportes
--  La aplicación (Java o web) solo hace CALL sp_... y SELECT * FROM v_...
--  Cada procedimiento que escribe trabaja en una transacción: o se guarda
--  todo o no se guarda nada.
-- =====================================================================
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;   -- misma intercalación que la base

DROP FUNCTION  IF EXISTS fn_num;
DROP FUNCTION  IF EXISTS fn_texto;
DROP FUNCTION  IF EXISTS fn_colonia;
DROP FUNCTION  IF EXISTS fn_ocupacion;
DROP FUNCTION  IF EXISTS fn_usuario;
DROP PROCEDURE IF EXISTS sp_estadisticas_mes;
DROP PROCEDURE IF EXISTS sp_alta_participante;
DROP PROCEDURE IF EXISTS sp_registrar_baja;
DROP PROCEDURE IF EXISTS sp_reactivar;
DROP PROCEDURE IF EXISTS sp_guardar_visita;
DROP PROCEDURE IF EXISTS sp_buscar;
DROP PROCEDURE IF EXISTS sp_reporte_visitas;
DROP PROCEDURE IF EXISTS sp_visitas_tabla;
DROP PROCEDURE IF EXISTS sp_actualizar_persona;
DROP PROCEDURE IF EXISTS sp_guardar_familiar;
DROP PROCEDURE IF EXISTS sp_guardar_escolaridad;
DROP PROCEDURE IF EXISTS sp_eliminar_visita;

DELIMITER //

-- ---------------------------------------------------------------------
-- Pequeñas funciones de apoyo
-- ---------------------------------------------------------------------
-- Texto a número; NULL si viene vacío o no es número ("$6,500" → 6500)
CREATE FUNCTION fn_num(p VARCHAR(40)) RETURNS DECIMAL(12,2)
DETERMINISTIC NO SQL
BEGIN
  DECLARE v VARCHAR(40) DEFAULT REPLACE(REPLACE(REPLACE(TRIM(p), '$', ''), ',', ''), ' ', '');
  RETURN IF(v REGEXP '^-?[0-9]+(\\.[0-9]+)?$', CAST(v AS DECIMAL(12,2)), NULL);
END //

-- Texto limpio o NULL si viene vacío
CREATE FUNCTION fn_texto(p TEXT) RETURNS TEXT
DETERMINISTIC NO SQL
BEGIN
  RETURN NULLIF(TRIM(REGEXP_REPLACE(COALESCE(p, ''), '[[:space:]]+', ' ')), '');
END //

-- Busca una colonia de Morelia por nombre; si no existe la crea. Devuelve su id.
CREATE FUNCTION fn_colonia(p_nombre VARCHAR(100), p_cp VARCHAR(10)) RETURNS SMALLINT UNSIGNED
MODIFIES SQL DATA
BEGIN
  DECLARE v_id SMALLINT UNSIGNED; DECLARE v_mun SMALLINT UNSIGNED;
  SET p_nombre = fn_texto(p_nombre);
  IF p_nombre IS NULL THEN RETURN NULL; END IF;
  SELECT id INTO v_mun FROM cat_municipio WHERE nombre = 'Morelia' LIMIT 1;
  SELECT id INTO v_id FROM cat_colonia WHERE nombre = p_nombre AND municipio_id = v_mun LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO cat_colonia (nombre, codigo_postal, municipio_id)
    VALUES (p_nombre, IF(p_cp REGEXP '^[0-9]{5}$', p_cp, NULL), v_mun);
    SET v_id = LAST_INSERT_ID();
  END IF;
  RETURN v_id;
END //

CREATE FUNCTION fn_ocupacion(p_nombre VARCHAR(80)) RETURNS SMALLINT UNSIGNED
MODIFIES SQL DATA
BEGIN
  DECLARE v_id SMALLINT UNSIGNED;
  SET p_nombre = fn_texto(p_nombre);
  IF p_nombre IS NULL THEN RETURN NULL; END IF;
  SELECT id INTO v_id FROM cat_ocupacion WHERE nombre = p_nombre LIMIT 1;
  IF v_id IS NULL THEN INSERT INTO cat_ocupacion (nombre) VALUES (p_nombre); SET v_id = LAST_INSERT_ID(); END IF;
  RETURN v_id;
END //

CREATE FUNCTION fn_usuario(p_nombre VARCHAR(100)) RETURNS SMALLINT UNSIGNED
MODIFIES SQL DATA
BEGIN
  DECLARE v_id SMALLINT UNSIGNED;
  SET p_nombre = fn_texto(p_nombre);
  IF p_nombre IS NULL THEN RETURN NULL; END IF;
  SELECT id INTO v_id FROM usuario WHERE nombre = p_nombre LIMIT 1;
  IF v_id IS NULL THEN INSERT INTO usuario (nombre) VALUES (p_nombre); SET v_id = LAST_INSERT_ID(); END IF;
  RETURN v_id;
END //

-- ---------------------------------------------------------------------
-- Hoja "ESTADÍSTICAS <MES> <AÑO>"
-- Devuelve una sola tabla: bloque, fila, femenino, masculino, total.
-- Cuenta a quienes estaban activos el último día del mes, con la edad que
-- tenían ese día, así que se puede volver a sacar cualquier mes pasado.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_estadisticas_mes(IN p_anio SMALLINT, IN p_mes TINYINT)
READS SQL DATA
BEGIN
  DECLARE v_fin DATE DEFAULT LAST_DAY(MAKEDATE(p_anio, 1) + INTERVAL (p_mes - 1) MONTH);
  DECLARE v_ini DATE DEFAULT MAKEDATE(p_anio, 1) + INTERVAL (p_mes - 1) MONTH;
  DECLARE v_ciclo SMALLINT UNSIGNED DEFAULT fn_ciclo(v_fin);

  DROP TEMPORARY TABLE IF EXISTS t_act, t_fam, t_hist, t_res;

  -- Participantes directos activos al cierre del mes
  CREATE TEMPORARY TABLE t_act (PRIMARY KEY (persona_id)) AS
  SELECT p.id AS persona_id, p.genero, fn_edad(p.fecha_nacimiento, v_fin) AS edad, pt.familia_id, f.colonia_id,
         (SELECT ne.clave FROM participante_escolaridad pe JOIN cat_ciclo_escolar c ON c.id = pe.ciclo_id
            JOIN cat_nivel_educativo ne ON ne.id = pe.nivel_id
           WHERE pe.participante_id = p.id AND c.inicio <= v_fin ORDER BY c.inicio DESC LIMIT 1) AS nivel,
         (SELECT pe.grado FROM participante_escolaridad pe JOIN cat_ciclo_escolar c ON c.id = pe.ciclo_id
           WHERE pe.participante_id = p.id AND c.inicio <= v_fin ORDER BY c.inicio DESC LIMIT 1) AS grado
  FROM inscripcion i
  JOIN participante pt ON pt.persona_id = i.participante_id
  JOIN persona p ON p.id = pt.persona_id
  JOIN familia f ON f.id = pt.familia_id
  WHERE i.fecha_ingreso <= v_fin AND (i.fecha_baja IS NULL OR i.fecha_baja > v_fin);

  -- Tutores e indirectos de esas familias
  CREATE TEMPORARY TABLE t_fam AS
  SELECT DISTINCT p.id AS persona_id, p.genero, fn_edad(p.fecha_nacimiento, v_fin) AS edad, fi.es_tutor
  FROM familia_integrante fi
  JOIN persona p ON p.id = fi.persona_id
  WHERE fi.familia_id IN (SELECT familia_id FROM t_act);

  -- Base de datos histórica al cierre del mes: quienes ya habían salido y no están activos
  CREATE TEMPORARY TABLE t_hist (PRIMARY KEY (persona_id)) AS
  SELECT i.participante_id AS persona_id, MAX(p.genero) AS genero,
         MAX(ce.orden) AS exito_orden,
         MAX(CASE WHEN i.fecha_baja BETWEEN v_ini AND v_fin AND i.caso_exito_id IS NOT NULL THEN 1 ELSE 0 END) AS termino_en_mes
  FROM inscripcion i
  JOIN persona p ON p.id = i.participante_id
  LEFT JOIN cat_caso_exito ce ON ce.id = i.caso_exito_id
  WHERE (i.fecha_ingreso <= v_fin AND i.fecha_baja IS NOT NULL AND i.fecha_baja <= v_fin)
     OR i.sin_fechas                                   -- salieron sin fecha registrada: cuentan en el histórico
  GROUP BY i.participante_id;
  DELETE FROM t_hist WHERE persona_id IN (SELECT persona_id FROM t_act);

  CREATE TEMPORARY TABLE t_res (
    bloque_orden TINYINT, bloque VARCHAR(60), fila_orden SMALLINT, fila VARCHAR(60),
    femenino INT NULL, masculino INT NULL, total INT NULL);

  -- 1. Participantes directos por rango de edad
  INSERT INTO t_res
  SELECT 1, 'Participantes directos', r.orden, r.etiqueta,
         COUNT(IF(a.genero = 'F', 1, NULL)), COUNT(IF(a.genero = 'M', 1, NULL)), COUNT(a.persona_id)
  FROM cat_rango_edad r LEFT JOIN t_act a ON a.edad BETWEEN r.edad_min AND r.edad_max
  WHERE r.grupo = 'DIRECTOS' GROUP BY r.orden, r.etiqueta;
  INSERT INTO t_res SELECT 1, 'Participantes directos', 99, 'Total', SUM(genero = 'F'), SUM(genero = 'M'), COUNT(*) FROM t_act;

  -- 2 y 3. Padres y/o tutores, y rangos de tutores
  INSERT INTO t_res
  SELECT IF(r.grupo = 'TUTORES', 2, 3), IF(r.grupo = 'TUTORES', 'Padres y/o tutores', 'Rangos tutores'), r.orden, r.etiqueta,
         COUNT(IF(t.genero = 'F', 1, NULL)), COUNT(IF(t.genero = 'M', 1, NULL)), COUNT(t.persona_id)
  FROM cat_rango_edad r LEFT JOIN t_fam t ON t.es_tutor AND t.edad BETWEEN r.edad_min AND r.edad_max
  WHERE r.grupo IN ('TUTORES', 'RANGOS_TUTORES') GROUP BY r.grupo, r.orden, r.etiqueta;
  INSERT INTO t_res SELECT 2, 'Padres y/o tutores', 99, 'Total', SUM(genero = 'F'), SUM(genero = 'M'), COUNT(*) FROM t_fam WHERE es_tutor;
  INSERT INTO t_res SELECT 3, 'Rangos tutores', 99, 'Total', SUM(genero = 'F'), SUM(genero = 'M'), COUNT(*) FROM t_fam WHERE es_tutor;

  -- 4. Participantes indirectos (familiares que no son tutores)
  INSERT INTO t_res
  SELECT 4, 'Participantes indirectos', r.orden, r.etiqueta,
         COUNT(IF(t.genero = 'F', 1, NULL)), COUNT(IF(t.genero = 'M', 1, NULL)), COUNT(t.persona_id)
  FROM cat_rango_edad r LEFT JOIN t_fam t ON NOT t.es_tutor AND t.edad BETWEEN r.edad_min AND r.edad_max
  WHERE r.grupo = 'INDIRECTOS' GROUP BY r.orden, r.etiqueta;
  INSERT INTO t_res SELECT 4, 'Participantes indirectos', 99, 'Total', SUM(genero = 'F'), SUM(genero = 'M'), COUNT(*) FROM t_fam WHERE NOT es_tutor;

  -- 5. Totales (indirectos = tutores + otros familiares, como en la hoja)
  INSERT INTO t_res SELECT 5, 'Totales', 1, 'Participantes directos', NULL, NULL, COUNT(*) FROM t_act;
  INSERT INTO t_res SELECT 5, 'Totales', 2, 'Participantes indirectos', NULL, NULL, COUNT(*) FROM t_fam;
  INSERT INTO t_res SELECT 5, 'Totales', 3, 'Personas sin edad registrada', NULL, NULL,
    (SELECT COUNT(*) FROM t_act WHERE edad IS NULL) + (SELECT COUNT(*) FROM t_fam WHERE edad IS NULL);

  -- 6. Base de datos histórica y casos de éxito
  INSERT INTO t_res SELECT 6, 'Base de datos histórica', 0, 'Base de datos histórica', SUM(genero = 'F'), SUM(genero = 'M'), COUNT(*) FROM t_hist;
  INSERT INTO t_res SELECT 6, 'Base de datos histórica', 1, 'Casos de éxito', SUM(genero = 'F'), SUM(genero = 'M'), COUNT(*) FROM t_hist WHERE exito_orden IS NOT NULL;
  INSERT INTO t_res
  SELECT 6, 'Base de datos histórica', 1 + ce.orden, ce.nombre,
         COUNT(IF(h.genero = 'F', 1, NULL)), COUNT(IF(h.genero = 'M', 1, NULL)), COUNT(h.persona_id)
  FROM cat_caso_exito ce LEFT JOIN t_hist h ON h.exito_orden = ce.orden GROUP BY ce.orden, ce.nombre;
  INSERT INTO t_res SELECT 6, 'Base de datos histórica', 50, 'No concluyeron', SUM(genero = 'F'), SUM(genero = 'M'), COUNT(*) FROM t_hist WHERE exito_orden IS NULL;

  -- 7. Otros datos
  INSERT INTO t_res SELECT 7, 'Otros datos', 1, 'Participantes', NULL, NULL, COUNT(*) FROM t_act;
  INSERT INTO t_res SELECT 7, 'Otros datos', 2, 'Familias', NULL, NULL, COUNT(DISTINCT familia_id) FROM t_act;
  INSERT INTO t_res SELECT 7, 'Otros datos', 3, 'Colonias', NULL, NULL, COUNT(DISTINCT colonia_id) FROM t_act;

  -- 8. Documento de terminación (casos de éxito que salieron este mes)
  INSERT INTO t_res SELECT 8, 'Documento de terminación', 1, 'Terminaron en el mes', SUM(genero = 'F'), SUM(genero = 'M'), COUNT(*) FROM t_hist WHERE termino_en_mes = 1;

  -- 9. Menores que han pasado por MESE
  INSERT INTO t_res SELECT 9, 'Menores que han pasado por MESE', 1, 'Activos + histórico', NULL, NULL,
    (SELECT COUNT(*) FROM t_act) + (SELECT COUNT(*) FROM t_hist);

  -- 10. Grado escolar (Primaria, Secundaria, Oficio, Preparatoria y Licenciatura siempre; otros niveles si hay alguien)
  INSERT INTO t_res
  SELECT 10, 'Grado escolar', ne.orden * 10 + ng.grado, CONCAT(ne.nombre, ' ', ng.grado, '°'),
         COUNT(IF(a.genero = 'F', 1, NULL)), COUNT(IF(a.genero = 'M', 1, NULL)), COUNT(a.persona_id)
  FROM cat_nivel_grado ng
  JOIN cat_nivel_educativo ne ON ne.id = ng.nivel_id
  LEFT JOIN t_act a ON a.nivel = ne.clave AND a.grado = ng.grado
  GROUP BY ne.orden, ne.nombre, ne.clave, ng.grado
  HAVING ne.clave IN ('PRIM','SEC','OFICIO','PREPA','LIC') OR COUNT(a.persona_id) > 0;
  INSERT INTO t_res SELECT 10, 'Grado escolar', 999, 'Sin escolaridad registrada', SUM(genero = 'F'), SUM(genero = 'M'), COUNT(*) FROM t_act WHERE nivel IS NULL;

  -- 11. Participantes directos por edad exacta (5 a 24 años)
  INSERT INTO t_res
  SELECT 11, 'Participantes directos por edad', e.n, CONCAT(e.n, ' años'),
         COUNT(IF(a.genero = 'F', 1, NULL)), COUNT(IF(a.genero = 'M', 1, NULL)), COUNT(a.persona_id)
  FROM (WITH RECURSIVE x(n) AS (SELECT 5 UNION ALL SELECT n + 1 FROM x WHERE n < 24) SELECT n FROM x) e
  LEFT JOIN t_act a ON a.edad = e.n GROUP BY e.n;

  SELECT DATE_FORMAT(v_fin, '%Y-%m') AS periodo, bloque_orden, bloque, fila_orden, fila, femenino, masculino, total
  FROM t_res ORDER BY bloque_orden, fila_orden;

  DROP TEMPORARY TABLE IF EXISTS t_act, t_fam, t_hist, t_res;
END //

-- ---------------------------------------------------------------------
-- Alta de un participante nuevo (y de su familia y tutor si no existen)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_alta_participante(
  IN p_nombres VARCHAR(80), IN p_apellido_paterno VARCHAR(60), IN p_apellido_materno VARCHAR(60),
  IN p_fecha_nacimiento DATE, IN p_genero CHAR(1), IN p_curp CHAR(18),
  IN p_familia_id INT UNSIGNED,                      -- NULL = familia nueva
  IN p_colonia VARCHAR(100), IN p_tutor_nombre VARCHAR(160), IN p_tutor_parentesco VARCHAR(40), IN p_tutor_telefono VARCHAR(20),
  IN p_fecha_ingreso DATE, IN p_nivel_clave VARCHAR(10), IN p_grado TINYINT, IN p_escuela VARCHAR(150),
  IN p_trabajadora_id SMALLINT UNSIGNED,
  OUT p_persona_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE v_fam INT UNSIGNED DEFAULT p_familia_id;
  DECLARE v_tutor INT UNSIGNED; DECLARE v_esc SMALLINT UNSIGNED; DECLARE v_nivel TINYINT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF fn_texto(p_nombres) IS NULL OR fn_texto(p_apellido_paterno) IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Escriba el nombre y el apellido paterno del participante.';
  END IF;
  IF p_fecha_ingreso IS NULL THEN SET p_fecha_ingreso = CURDATE(); END IF;

  START TRANSACTION;
  IF v_fam IS NULL THEN
    INSERT INTO familia (colonia_id) VALUES (fn_colonia(p_colonia, NULL));
    SET v_fam = LAST_INSERT_ID();
    IF fn_texto(p_tutor_nombre) IS NOT NULL THEN
      INSERT INTO persona (nombres, telefono, genero)
      VALUES (fn_texto(p_tutor_nombre), NULLIF(REGEXP_REPLACE(COALESCE(p_tutor_telefono, ''), '[^0-9]', ''), ''),
              CASE COALESCE(p_tutor_parentesco, 'Madre') WHEN 'Madre' THEN 'F' WHEN 'Padre' THEN 'M' ELSE NULL END);
      SET v_tutor = LAST_INSERT_ID();
      INSERT INTO familia_integrante (familia_id, persona_id, parentesco_id, es_tutor)
      SELECT v_fam, v_tutor, id, TRUE FROM cat_parentesco WHERE nombre = COALESCE(p_tutor_parentesco, 'Madre');
    END IF;
  END IF;

  INSERT INTO persona (nombres, apellido_paterno, apellido_materno, fecha_nacimiento, genero, curp)
  VALUES (p_nombres, p_apellido_paterno, p_apellido_materno, p_fecha_nacimiento, p_genero, p_curp);
  SET p_persona_id = LAST_INSERT_ID();

  INSERT INTO participante (persona_id, familia_id, numero_becado, trabajadora_id)
  VALUES (p_persona_id, v_fam, (SELECT COUNT(*) + 1 FROM participante x WHERE x.familia_id = v_fam), p_trabajadora_id);

  INSERT INTO inscripcion (participante_id, fecha_ingreso) VALUES (p_persona_id, p_fecha_ingreso);

  IF p_nivel_clave IS NOT NULL THEN
    SELECT id INTO v_nivel FROM cat_nivel_educativo WHERE clave = p_nivel_clave;
    IF fn_texto(p_escuela) IS NOT NULL THEN
      INSERT IGNORE INTO cat_escuela (nombre, nivel_id) VALUES (fn_texto(p_escuela), v_nivel);
      SELECT id INTO v_esc FROM cat_escuela WHERE nombre = fn_texto(p_escuela);
    END IF;
    INSERT INTO participante_escolaridad (participante_id, ciclo_id, escuela_id, nivel_id, grado)
    VALUES (p_persona_id, fn_ciclo(p_fecha_ingreso), v_esc, v_nivel, p_grado);
  END IF;
  COMMIT;
END //

-- ---------------------------------------------------------------------
-- Dar de baja: cierra el periodo abierto. Los datos no se borran.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_registrar_baja(
  IN p_participante_id INT UNSIGNED, IN p_fecha DATE, IN p_causa VARCHAR(80),
  IN p_causa_estadistica VARCHAR(60), IN p_caso_exito VARCHAR(60), IN p_motivo TEXT)
MODIFIES SQL DATA
BEGIN
  DECLARE v_insc INT UNSIGNED; DECLARE v_causa TINYINT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  SELECT id INTO v_insc FROM inscripcion WHERE participante_id = p_participante_id AND abierta = 1;
  IF v_insc IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este participante no está activo; no se puede dar de baja.';
  END IF;
  SELECT id INTO v_causa FROM cat_causa_baja WHERE nombre = p_causa;
  IF v_causa IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Elija una causa de baja de la lista.';
  END IF;

  START TRANSACTION;
  UPDATE inscripcion
     SET fecha_baja = COALESCE(p_fecha, CURDATE()),
         causa_baja_id = v_causa,
         causa_estadistica_id = (SELECT id FROM cat_causa_baja_estadistica WHERE nombre = p_causa_estadistica),
         caso_exito_id = (SELECT id FROM cat_caso_exito WHERE nombre = p_caso_exito),
         motivo = fn_texto(p_motivo),
         nivel_final_id = (SELECT pe.nivel_id FROM participante_escolaridad pe JOIN cat_ciclo_escolar c ON c.id = pe.ciclo_id
                            WHERE pe.participante_id = p_participante_id ORDER BY c.inicio DESC LIMIT 1),
         grado_final    = (SELECT pe.grado FROM participante_escolaridad pe JOIN cat_ciclo_escolar c ON c.id = pe.ciclo_id
                            WHERE pe.participante_id = p_participante_id ORDER BY c.inicio DESC LIMIT 1)
   WHERE id = v_insc;
  UPDATE participante_beca SET hasta = COALESCE(p_fecha, CURDATE())
   WHERE participante_id = p_participante_id AND hasta IS NULL;
  COMMIT;
END //

-- Reactivar: abre un periodo nuevo (el anterior queda en el historial)
CREATE PROCEDURE sp_reactivar(IN p_participante_id INT UNSIGNED, IN p_fecha DATE)
MODIFIES SQL DATA
BEGIN
  IF NOT EXISTS (SELECT 1 FROM participante WHERE persona_id = p_participante_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe ese participante.';
  END IF;
  INSERT INTO inscripcion (participante_id, fecha_ingreso) VALUES (p_participante_id, COALESCE(p_fecha, CURDATE()));
END //

-- ---------------------------------------------------------------------
-- Guardar una visita domiciliaria enviada por la página web o el teléfono.
-- Recibe el mismo objeto que guarda la página: {"id","est","mod","d":{...}}
-- * Si la visita ya existe (mismo id del teléfono) la actualiza; si la copia
--   de la base es más reciente, no la sobrescribe.
-- * Si el participante no existe, lo registra como candidato con su familia.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_guardar_visita(IN p_json JSON, IN p_usuario_id SMALLINT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE d JSON DEFAULT JSON_EXTRACT(p_json, '$.d');
  DECLARE v_uuid VARCHAR(40) DEFAULT JSON_UNQUOTE(JSON_EXTRACT(p_json, '$.id'));
  DECLARE v_estado VARCHAR(9) DEFAULT IF(JSON_UNQUOTE(JSON_EXTRACT(p_json, '$.est')) = 'Completa', 'COMPLETA', 'BORRADOR');
  -- la página guarda la fecha de modificación en UTC; se pasa a la hora del servidor
  DECLARE v_mod DATETIME DEFAULT CONVERT_TZ(STR_TO_DATE(LEFT(JSON_UNQUOTE(JSON_EXTRACT(p_json, '$.mod')), 19), '%Y-%m-%dT%H:%i:%s'), '+00:00', 'SYSTEM');
  DECLARE v_id INT UNSIGNED; DECLARE v_mod_bd DATETIME;
  DECLARE v_part INT UNSIGNED; DECLARE v_fam INT UNSIGNED; DECLARE v_usr SMALLINT UNSIGNED;
  DECLARE v_nom, v_app, v_apm VARCHAR(80);
  DECLARE v_gps VARCHAR(40);
  DECLARE v_fin BOOLEAN DEFAULT FALSE;
  DECLARE c_n, c_ec, c_par, c_esc, c_oc, c_fn VARCHAR(160); DECLARE c_ed, c_ing, c_tel VARCHAR(40);
  DECLARE v_pid INT UNSIGNED;
  DECLARE cur_fam CURSOR FOR
    SELECT n, ed, fn, ec, tel, par, esc, oc, ing FROM JSON_TABLE(JSON_EXTRACT(p_json, '$.d.fam'), '$[*]' COLUMNS (
      n VARCHAR(160) PATH '$.n', ed VARCHAR(40) PATH '$.ed', fn VARCHAR(160) PATH '$.fn', ec VARCHAR(160) PATH '$.ec',
      tel VARCHAR(40) PATH '$.tel', par VARCHAR(160) PATH '$.par', esc VARCHAR(160) PATH '$.esc', oc VARCHAR(160) PATH '$.oc',
      ing VARCHAR(40) PATH '$.ing')) jt;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = TRUE;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF d IS NULL OR v_uuid IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La visita no tiene el formato esperado ({"id":..., "d":{...}}).';
  END IF;
  SET v_nom = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.nom')));
  SET v_app = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.ap_p')));
  SET v_apm = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.ap_m')));
  IF v_estado = 'COMPLETA' AND (v_nom IS NULL OR v_app IS NULL OR JSON_UNQUOTE(JSON_EXTRACT(d, '$.fecha')) IS NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Para terminar la visita faltan el nombre, el apellido paterno o la fecha.';
  END IF;

  SELECT id, modificado_en INTO v_id, v_mod_bd FROM visita WHERE uuid_cliente = v_uuid;
  IF v_id IS NOT NULL AND v_mod IS NOT NULL AND v_mod_bd > v_mod THEN
    SELECT v_id AS visita_id, 'SIN_CAMBIOS' AS resultado;   -- la base ya tiene una versión más nueva
  ELSE
    START TRANSACTION;
    SET v_usr = COALESCE(p_usuario_id, fn_usuario(JSON_UNQUOTE(JSON_EXTRACT(d, '$.ts'))));

    -- Participante: por id, por nombre exacto, o nuevo candidato
    SET v_part = fn_num(JSON_UNQUOTE(JSON_EXTRACT(d, '$.participante_id')));
    IF v_part IS NULL AND v_nom IS NOT NULL THEN
      SELECT pt.persona_id INTO v_part FROM participante pt JOIN persona p ON p.id = pt.persona_id
       WHERE p.nombres = v_nom AND p.apellido_paterno <=> v_app AND (v_apm IS NULL OR p.apellido_materno = v_apm) LIMIT 1;
    END IF;
    IF v_part IS NULL AND v_nom IS NOT NULL THEN
      INSERT INTO familia (colonia_id) VALUES (NULL);
      SET v_fam = LAST_INSERT_ID();
      INSERT INTO persona (nombres, apellido_paterno, apellido_materno, fecha_nacimiento, fecha_nac_aprox, tipo_sangre_id)
      VALUES (v_nom, v_app, v_apm,
              IF(fn_num(JSON_UNQUOTE(JSON_EXTRACT(d, '$.edad'))) IS NULL, NULL,
                 MAKEDATE(YEAR(CURDATE()) - fn_num(JSON_UNQUOTE(JSON_EXTRACT(d, '$.edad'))), 1)),
              fn_num(JSON_UNQUOTE(JSON_EXTRACT(d, '$.edad'))) IS NOT NULL,
              (SELECT id FROM cat_tipo_sangre WHERE nombre = REPLACE(JSON_UNQUOTE(JSON_EXTRACT(d, '$.sangre')), '−', '-')));
      SET v_part = LAST_INSERT_ID();
      INSERT INTO participante (persona_id, familia_id, trabajadora_id) VALUES (v_part, v_fam, v_usr);
    END IF;
    IF v_part IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Escriba al menos el nombre del participante.';
    END IF;
    SELECT familia_id INTO v_fam FROM participante WHERE persona_id = v_part;

    -- Domicilio actual de la familia
    SET v_gps = JSON_UNQUOTE(JSON_EXTRACT(d, '$.gps'));
    UPDATE familia SET
      calle        = COALESCE(fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.calle'))), calle),
      numero_ext   = COALESCE(fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.next'))), numero_ext),
      colonia_id   = COALESCE(fn_colonia(JSON_UNQUOTE(JSON_EXTRACT(d, '$.col')), JSON_UNQUOTE(JSON_EXTRACT(d, '$.cp'))), colonia_id),
      referencias  = COALESCE(fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.ref'))), referencias),
      entre_calles = COALESCE(fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.entre'))), entre_calles),
      telefono     = COALESCE(NULLIF(REGEXP_REPLACE(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(d, '$.tel_t')), ''), '[^0-9]', ''), ''), telefono),
      latitud      = COALESCE(fn_num(SUBSTRING_INDEX(v_gps, ',', 1)), latitud),
      longitud     = COALESCE(fn_num(SUBSTRING_INDEX(v_gps, ',', -1)), longitud)
    WHERE id = v_fam;

    -- La visita
    IF v_id IS NULL THEN
      INSERT INTO visita (uuid_cliente, familia_id, participante_id, fecha) VALUES (v_uuid, v_fam, v_part, CURDATE());
      SET v_id = LAST_INSERT_ID();
    END IF;
    UPDATE visita SET
      familia_id = v_fam, participante_id = v_part, usuario_id = v_usr,
      fecha = COALESCE(STR_TO_DATE(JSON_UNQUOTE(JSON_EXTRACT(d, '$.fecha')), '%Y-%m-%d'), fecha),
      estado = v_estado,
      folio_seguimiento = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.nseg'))),
      cuadrante = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.cuad'))),
      verificada_en = CASE JSON_UNQUOTE(JSON_EXTRACT(d, '$.verif')) WHEN 'Oficina' THEN 'OFICINA' WHEN 'Visita domiciliaria' THEN 'DOMICILIO' END,
      recamaras = fn_num(JSON_UNQUOTE(JSON_EXTRACT(d, '$.rec'))),
      banos = fn_num(JSON_UNQUOTE(JSON_EXTRACT(d, '$.banos'))),
      actividad_comunitaria = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.com_c'))),
      actividad_fisica = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.fis_c'))),
      actividad_productiva = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.prod'))),
      huerto_motivo = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.huerto_pq'))),
      huerto_beneficio = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.huerto_ben'))),
      deudas_detalle = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.deu_c'))),
      necesidad_material = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.mat'))),
      documentos_obs = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.docs_obs'))),
      mejora_condiciones = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.mej'))),
      hacinamiento_obs = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.hac'))),
      diagnostico_social = fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.diag'))),
      latitud = fn_num(SUBSTRING_INDEX(v_gps, ',', 1)),
      longitud = fn_num(SUBSTRING_INDEX(v_gps, ',', -1)),
      modificado_en = COALESCE(v_mod, CURRENT_TIMESTAMP)
    WHERE id = v_id;

    -- Se reemplazan las partes de la visita
    DELETE FROM visita_respuesta WHERE visita_id = v_id;
    DELETE FROM visita_integrante WHERE visita_id = v_id;
    DELETE FROM visita_monto WHERE visita_id = v_id;
    DELETE FROM visita_vacuna WHERE visita_id = v_id;
    DELETE FROM visita_antecedente WHERE visita_id = v_id;
    DELETE FROM visita_firma WHERE visita_id = v_id;

    -- Respuestas de opción: sirve igual para "Propia" que para ["Agua","Luz"]
    INSERT INTO visita_respuesta (visita_id, pregunta_id, opcion_id)
    SELECT v_id, q.id, o.id
    FROM cat_pregunta q JOIN cat_opcion o ON o.pregunta_id = q.id
    WHERE JSON_CONTAINS(JSON_EXTRACT(d, CONCAT('$."', q.clave, '"')), JSON_QUOTE(o.etiqueta));
    -- Respuestas "Otro, ¿cuál?"
    INSERT INTO visita_respuesta (visita_id, pregunta_id, opcion_id, texto_otro)
    SELECT v_id, q.id, NULL, LEFT(fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$."', q.clave, '_ot"')))), 120)
    FROM cat_pregunta q
    WHERE q.permite_otro AND fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$."', q.clave, '_ot"')))) IS NOT NULL;
    -- "Otro familiar" con adicciones: el nombre va como texto de la pregunta adi_o
    INSERT INTO visita_respuesta (visita_id, pregunta_id, opcion_id, texto_otro)
    SELECT v_id, q.id, NULL, LEFT(fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.adi_o_n'))), 120)
    FROM cat_pregunta q WHERE q.clave = 'adi_o' AND fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.adi_o_n'))) IS NOT NULL
      AND fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.adi_o_ot'))) IS NULL;

    -- Apoyos y egresos
    INSERT INTO visita_monto (visita_id, concepto_id, monto, detalle)
    SELECT v_id, c.id, fn_num(JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$."', c.clave, '"')))),
           IF(c.clave = 'ap_ot', fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, '$.ap_ot_n'))), NULL)
    FROM cat_concepto_monto c
    WHERE fn_num(JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$."', c.clave, '"')))) > 0;

    -- Vacunas
    INSERT INTO visita_vacuna (visita_id, vacuna_id, rol, aplicada, dosis)
    SELECT v_id, cv.id, x.rol, JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$.', x.k))) = 'Sí', fn_num(JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$.', x.k, '_d'))))
    FROM (SELECT 'COVID-19' AS vac, 'PARTICIPANTE' AS rol, 'cov_p' AS k UNION ALL SELECT 'COVID-19', 'TUTOR', 'cov_t'
          UNION ALL SELECT 'Sarampión', 'PARTICIPANTE', 'sar_p' UNION ALL SELECT 'Sarampión', 'TUTOR', 'sar_t') x
    JOIN cat_vacuna cv ON cv.nombre = x.vac
    WHERE JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$.', x.k))) IN ('Sí', 'No');

    -- Antecedentes médicos familiares
    INSERT INTO visita_antecedente (visita_id, nombre_completo, parentesco_id, enfermedad, atencion_medica)
    SELECT v_id, fn_texto(a.n), (SELECT id FROM cat_parentesco WHERE nombre = fn_texto(a.par)),
           COALESCE(fn_texto(a.enf), 'Sin especificar'), fn_texto(a.at)
    FROM JSON_TABLE(JSON_EXTRACT(p_json, '$.d.ant'), '$[*]' COLUMNS (
      n VARCHAR(160) PATH '$.n', par VARCHAR(40) PATH '$.par', enf VARCHAR(150) PATH '$.enf', at VARCHAR(100) PATH '$.at')) a
    WHERE fn_texto(a.n) IS NOT NULL OR fn_texto(a.enf) IS NOT NULL;

    -- Firmas (imagen PNG que viene como data:image/png;base64,...)
    INSERT INTO visita_firma (visita_id, rol, nombre, imagen)
    SELECT v_id, x.rol, fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$.', x.kn)))),
           FROM_BASE64(SUBSTRING_INDEX(JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$.', x.k))), ',', -1))
    FROM (SELECT 'TRABAJADORA' AS rol, 'f_ts' AS k, 'f_ts_n' AS kn UNION ALL SELECT 'TUTOR', 'f_tu', 'f_tu_n') x
    WHERE JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$.', x.k))) LIKE 'data:image/%'
       OR fn_texto(JSON_UNQUOTE(JSON_EXTRACT(d, CONCAT('$.', x.kn)))) IS NOT NULL;

    -- Integrantes de la familia: se reconoce a la persona por su nombre dentro de la familia
    SET v_fin = FALSE;
    OPEN cur_fam;
    leer: LOOP
      FETCH cur_fam INTO c_n, c_ed, c_fn, c_ec, c_tel, c_par, c_esc, c_oc, c_ing;
      IF v_fin THEN LEAVE leer; END IF;
      IF fn_texto(c_n) IS NULL THEN ITERATE leer; END IF;
      -- (asignación con subconsulta: un SELECT ... INTO sin filas activaría el fin del cursor)
      SET v_pid = (SELECT p.id FROM familia_integrante fi JOIN persona p ON p.id = fi.persona_id
                    WHERE fi.familia_id = v_fam AND p.nombre_completo = fn_texto(c_n) LIMIT 1);
      IF v_pid IS NULL THEN
        INSERT INTO persona (nombres, fecha_nacimiento, fecha_nac_aprox, genero, telefono, estado_civil_id, escolaridad_nivel_id, ocupacion_id)
        VALUES (fn_texto(c_n),
                COALESCE(STR_TO_DATE(NULLIF(c_fn, ''), '%Y-%m-%d'), IF(fn_num(c_ed) IS NULL, NULL, MAKEDATE(YEAR(CURDATE()) - fn_num(c_ed), 1))),
                NULLIF(c_fn, '') IS NULL AND fn_num(c_ed) IS NOT NULL,
                CASE WHEN fn_texto(c_par) IN ('Madre','Abuela','Tía','Hermana','Prima','Sobrina','Cuñada','Hija','Bisabuela','Madrastra') THEN 'F'
                     WHEN fn_texto(c_par) IN ('Padre','Abuelo','Tío','Hermano','Primo','Sobrino','Cuñado','Hijo','Bisabuelo','Padrastro') THEN 'M' END,
                NULLIF(REGEXP_REPLACE(COALESCE(c_tel, ''), '[^0-9]', ''), ''),
                (SELECT id FROM cat_estado_civil WHERE nombre = fn_texto(c_ec)),
                (SELECT id FROM cat_nivel_educativo WHERE nombre = fn_texto(c_esc)),
                fn_ocupacion(c_oc));
        SET v_pid = LAST_INSERT_ID();
        INSERT INTO familia_integrante (familia_id, persona_id, parentesco_id, es_tutor)
        SELECT v_fam, v_pid, COALESCE((SELECT id FROM cat_parentesco WHERE nombre = fn_texto(c_par)), (SELECT id FROM cat_parentesco WHERE nombre = 'Otro')),
               fn_texto(c_par) IN ('Madre','Padre','Tutor(a)');
      END IF;
      INSERT INTO visita_integrante (visita_id, persona_id, parentesco_id, ocupacion_id, ingreso_mensual)
      VALUES (v_id, v_pid, (SELECT id FROM cat_parentesco WHERE nombre = fn_texto(c_par)), fn_ocupacion(c_oc), COALESCE(fn_num(c_ing), 0))
      ON DUPLICATE KEY UPDATE ingreso_mensual = ingreso_mensual + VALUES(ingreso_mensual);
    END LOOP;
    CLOSE cur_fam;

    COMMIT;
    SELECT v_id AS visita_id, 'GUARDADA' AS resultado;
  END IF;
END //

-- ---------------------------------------------------------------------
-- Búsqueda general (barra de búsqueda de Inicio)
-- Sin importar acentos ni mayúsculas, por nombre, colonia o escuela.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_buscar(IN p_texto VARCHAR(100), IN p_limite SMALLINT)
READS SQL DATA
BEGIN
  DECLARE v_patron VARCHAR(220) DEFAULT CONCAT('%', REPLACE(TRIM(REGEXP_REPLACE(p_texto, '[[:space:]]+', ' ')), ' ', '%'), '%');
  SELECT * FROM (
    SELECT 'Participante' AS tipo, persona_id, nombre_completo AS nombre,
           CONCAT_WS(' · ', CASE estado WHEN 'ACTIVO' THEN 'Activo' WHEN 'BAJA' THEN 'Baja' ELSE 'Candidato' END, colonia, escuela) AS detalle
    FROM v_participante
    WHERE nombre_completo LIKE v_patron OR colonia LIKE v_patron OR escuela LIKE v_patron
    UNION ALL
    SELECT 'Familiar', persona_id, nombre_completo, CONCAT_WS(' · ', parentesco, CONCAT('de ', participantes))
    FROM v_familiar WHERE nombre_completo LIKE v_patron
  ) r
  ORDER BY tipo DESC, nombre
  LIMIT p_limite;
END //

-- ---------------------------------------------------------------------
-- Reporte de visitas por fecha: 1) resumen, 2) conteo de cada respuesta
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_reporte_visitas(IN p_desde DATE, IN p_hasta DATE, IN p_usuario_id SMALLINT UNSIGNED, IN p_colonia_id SMALLINT UNSIGNED)
READS SQL DATA
BEGIN
  DROP TEMPORARY TABLE IF EXISTS t_vis;
  CREATE TEMPORARY TABLE t_vis (PRIMARY KEY (visita_id)) AS
  SELECT vr.* FROM v_visita_resumen vr JOIN familia f ON f.id = vr.familia_id
  JOIN visita v ON v.id = vr.visita_id
  WHERE vr.fecha BETWEEN COALESCE(p_desde, '1900-01-01') AND COALESCE(p_hasta, '2999-12-31')
    AND (p_usuario_id IS NULL OR v.usuario_id = p_usuario_id)
    AND (p_colonia_id IS NULL OR f.colonia_id = p_colonia_id);

  SELECT SUM(estado = 'COMPLETA') AS visitas_terminadas,
         SUM(estado = 'BORRADOR') AS borradores,
         COUNT(DISTINCT familia_id) AS familias,
         ROUND(AVG(IF(estado = 'COMPLETA' AND ingreso_total > 0, ingreso_total, NULL)), 2) AS ingreso_promedio,
         ROUND(AVG(IF(estado = 'COMPLETA' AND egreso_total > 0, egreso_total, NULL)), 2) AS egreso_promedio,
         ROUND(100 * AVG(IF(estado = 'COMPLETA', apoyos_total > 0, NULL)), 1) AS pct_con_apoyo
  FROM t_vis;

  SELECT q.seccion_id, q.clave, q.texto AS pregunta, COALESCE(o.etiqueta, 'Otro') AS respuesta, COUNT(*) AS familias
  FROM t_vis t
  JOIN visita_respuesta r ON r.visita_id = t.visita_id
  JOIN cat_pregunta q ON q.id = r.pregunta_id
  LEFT JOIN cat_opcion o ON o.id = r.opcion_id
  WHERE t.estado = 'COMPLETA'
  GROUP BY q.seccion_id, q.orden, q.clave, q.texto, o.orden, o.etiqueta
  ORDER BY q.seccion_id, q.orden, o.orden;

  DROP TEMPORARY TABLE IF EXISTS t_vis;
END //

-- ---------------------------------------------------------------------
-- Una fila por visita y una columna por pregunta (para exportar a Excel).
-- Las columnas se arman con las preguntas del catálogo: si se agrega una
-- pregunta, aparece sola.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_visitas_tabla(IN p_desde DATE, IN p_hasta DATE)
READS SQL DATA
BEGIN
  DECLARE v_cols TEXT;
  SET SESSION group_concat_max_len = 100000;
  SELECT GROUP_CONCAT(
           CONCAT('GROUP_CONCAT(CASE WHEN q.clave = ', QUOTE(clave),
                  ' THEN COALESCE(o.etiqueta, CONCAT(''Otro: '', r.texto_otro)) END ORDER BY o.orden SEPARATOR '', '') AS `',
                  REPLACE(texto, '`', ''), '`')
           ORDER BY seccion_id, orden SEPARATOR ',\n')
    INTO v_cols FROM cat_pregunta WHERE activa;

  SET @sql = CONCAT(
    'SELECT vr.visita_id, vr.fecha, vr.estado, vr.participante, vr.colonia, vr.trabajadora_social, ',
    'vr.ingreso_total, vr.apoyos_total, vr.egreso_total, vr.balance, vr.integrantes, ', v_cols,
    ' FROM v_visita_resumen vr LEFT JOIN visita_respuesta r ON r.visita_id = vr.visita_id',
    ' LEFT JOIN cat_pregunta q ON q.id = r.pregunta_id LEFT JOIN cat_opcion o ON o.id = r.opcion_id',
    ' WHERE vr.fecha BETWEEN ? AND ?',
    ' GROUP BY vr.visita_id, vr.fecha, vr.estado, vr.participante, vr.colonia, vr.trabajadora_social,',
    ' vr.ingreso_total, vr.apoyos_total, vr.egreso_total, vr.balance, vr.integrantes',
    ' ORDER BY vr.fecha DESC');
  SET @desde = COALESCE(p_desde, '1900-01-01'), @hasta = COALESCE(p_hasta, '2999-12-31');
  PREPARE st_visitas_tabla FROM @sql;
  EXECUTE st_visitas_tabla USING @desde, @hasta;
  DEALLOCATE PREPARE st_visitas_tabla;
END //

-- ---------------------------------------------------------------------
-- Editar datos de una persona (participante o familiar)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_actualizar_persona(
  IN p_persona_id INT UNSIGNED, IN p_nombres VARCHAR(80), IN p_apellido_paterno VARCHAR(60), IN p_apellido_materno VARCHAR(60),
  IN p_fecha_nacimiento DATE, IN p_genero CHAR(1), IN p_curp CHAR(18), IN p_telefono VARCHAR(20), IN p_correo VARCHAR(120),
  IN p_tipo_sangre VARCHAR(12))
MODIFIES SQL DATA
BEGIN
  IF NOT EXISTS (SELECT 1 FROM persona WHERE id = p_persona_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe esa persona.';
  END IF;
  UPDATE persona SET
    nombres = p_nombres, apellido_paterno = p_apellido_paterno, apellido_materno = p_apellido_materno,
    fecha_nacimiento = p_fecha_nacimiento, fecha_nac_aprox = FALSE, genero = p_genero, curp = p_curp,
    telefono = p_telefono, correo = fn_texto(p_correo),
    tipo_sangre_id = (SELECT id FROM cat_tipo_sangre WHERE nombre = p_tipo_sangre)
  WHERE id = p_persona_id;
END //

-- Agregar o editar un familiar (p_persona_id NULL = nuevo)
CREATE PROCEDURE sp_guardar_familiar(
  IN p_familia_id INT UNSIGNED, IN p_persona_id INT UNSIGNED, IN p_nombre_completo VARCHAR(200), IN p_parentesco VARCHAR(40),
  IN p_es_tutor BOOLEAN, IN p_fecha_nacimiento DATE, IN p_genero CHAR(1), IN p_telefono VARCHAR(20),
  IN p_ocupacion VARCHAR(80), IN p_escolaridad_clave VARCHAR(10), IN p_estado_civil VARCHAR(30),
  OUT p_id INT UNSIGNED)
MODIFIES SQL DATA
BEGIN
  DECLARE v_par TINYINT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  SET v_par = (SELECT id FROM cat_parentesco WHERE nombre = p_parentesco);
  IF v_par IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Elija un parentesco de la lista.'; END IF;
  IF p_es_tutor AND NOT (SELECT puede_ser_tutor FROM cat_parentesco WHERE id = v_par) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ese parentesco no puede registrarse como tutor.';
  END IF;
  START TRANSACTION;
  IF p_persona_id IS NULL THEN
    INSERT INTO persona (nombres, fecha_nacimiento, genero, telefono) VALUES (p_nombre_completo, p_fecha_nacimiento, p_genero, p_telefono);
    SET p_persona_id = LAST_INSERT_ID();
  ELSE
    UPDATE persona SET nombres = p_nombre_completo, apellido_paterno = NULL, apellido_materno = NULL,
                       fecha_nacimiento = p_fecha_nacimiento, genero = p_genero, telefono = p_telefono WHERE id = p_persona_id;
  END IF;
  UPDATE persona SET ocupacion_id = fn_ocupacion(p_ocupacion),
                     escolaridad_nivel_id = (SELECT id FROM cat_nivel_educativo WHERE clave = p_escolaridad_clave),
                     estado_civil_id = (SELECT id FROM cat_estado_civil WHERE nombre = p_estado_civil)
   WHERE id = p_persona_id;
  INSERT INTO familia_integrante (familia_id, persona_id, parentesco_id, es_tutor) VALUES (p_familia_id, p_persona_id, v_par, COALESCE(p_es_tutor, FALSE))
  ON DUPLICATE KEY UPDATE parentesco_id = VALUES(parentesco_id), es_tutor = VALUES(es_tutor);
  COMMIT;
  SET p_id = p_persona_id;
END //

-- Escuela y grado de un ciclo escolar (si ya existe el ciclo, se actualiza)
CREATE PROCEDURE sp_guardar_escolaridad(
  IN p_participante_id INT UNSIGNED, IN p_ciclo CHAR(9), IN p_nivel_clave VARCHAR(10), IN p_grado TINYINT,
  IN p_escuela VARCHAR(150), IN p_turno VARCHAR(20), IN p_grupo VARCHAR(12), IN p_carrera VARCHAR(120))
MODIFIES SQL DATA
BEGIN
  DECLARE v_ciclo SMALLINT UNSIGNED;
  SET v_ciclo = COALESCE((SELECT id FROM cat_ciclo_escolar WHERE nombre = p_ciclo), fn_ciclo(CURDATE()));
  IF fn_texto(p_escuela) IS NOT NULL THEN INSERT IGNORE INTO cat_escuela (nombre) VALUES (fn_texto(p_escuela)); END IF;
  IF fn_texto(p_carrera) IS NOT NULL THEN INSERT IGNORE INTO cat_carrera (nombre) VALUES (fn_texto(p_carrera)); END IF;
  INSERT INTO participante_escolaridad (participante_id, ciclo_id, escuela_id, nivel_id, grado, carrera_id, grupo, turno_id)
  VALUES (p_participante_id, v_ciclo, (SELECT id FROM cat_escuela WHERE nombre = fn_texto(p_escuela)),
          (SELECT id FROM cat_nivel_educativo WHERE clave = p_nivel_clave), p_grado,
          (SELECT id FROM cat_carrera WHERE nombre = fn_texto(p_carrera)), fn_texto(p_grupo),
          (SELECT id FROM cat_turno WHERE nombre = p_turno))
  ON DUPLICATE KEY UPDATE escuela_id = VALUES(escuela_id), nivel_id = VALUES(nivel_id), grado = VALUES(grado),
                          carrera_id = VALUES(carrera_id), grupo = VALUES(grupo), turno_id = VALUES(turno_id);
END //

-- Eliminar una visita (por id de la base o por el id que le dio el teléfono)
CREATE PROCEDURE sp_eliminar_visita(IN p_visita_id INT UNSIGNED, IN p_uuid VARCHAR(40))
MODIFIES SQL DATA
BEGIN
  DELETE FROM visita WHERE id = p_visita_id OR (p_uuid IS NOT NULL AND uuid_cliente = p_uuid);
  IF ROW_COUNT() = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se encontró la visita.'; END IF;
END //

DELIMITER ;

-- =====================================================================
--  05_triggers.sql — reglas que ninguna restricción declarativa cubre
--
--  Criterio: primero llaves, UNIQUE, NOT NULL y CHECK (01_esquema.sql).
--  Aquí solo va lo que necesita la fecha de hoy, mirar otros renglones
--  o dejar rastro en la bitácora. Durante la carga masiva desde Excel se
--  puede apagar la bitácora con  SET @importando = 1;
--  La aplicación debe fijar quién trabaja:  SET @usuario_id = <id>;
-- =====================================================================
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;   -- misma intercalación que la base

DROP TRIGGER IF EXISTS trg_persona_bi;
DROP TRIGGER IF EXISTS trg_persona_bu;
DROP TRIGGER IF EXISTS trg_persona_ai;
DROP TRIGGER IF EXISTS trg_persona_au;
DROP TRIGGER IF EXISTS trg_inscripcion_bi;
DROP TRIGGER IF EXISTS trg_inscripcion_bu;
DROP TRIGGER IF EXISTS trg_inscripcion_ai;
DROP TRIGGER IF EXISTS trg_inscripcion_au;
DROP TRIGGER IF EXISTS trg_inscripcion_ad;
DROP TRIGGER IF EXISTS trg_respuesta_bi;
DROP TRIGGER IF EXISTS trg_visita_bi;
DROP TRIGGER IF EXISTS trg_visita_bu;
DROP TRIGGER IF EXISTS trg_visita_au;
DROP TRIGGER IF EXISTS trg_visita_ad;
DROP PROCEDURE IF EXISTS _validar_persona;
DROP PROCEDURE IF EXISTS _validar_inscripcion;
DROP PROCEDURE IF EXISTS _validar_visita;

DELIMITER //

-- ---------------------------------------------------------------------
-- Personas: limpiar texto y validar fecha de nacimiento
-- ---------------------------------------------------------------------
CREATE PROCEDURE _validar_persona(INOUT p_nombres VARCHAR(80), INOUT p_ap VARCHAR(60), INOUT p_am VARCHAR(60),
                                  INOUT p_curp CHAR(18), INOUT p_tel VARCHAR(15), IN p_nac DATE)
BEGIN
  SET p_nombres = TRIM(REGEXP_REPLACE(p_nombres, '[[:space:]]+', ' '));
  SET p_ap = NULLIF(TRIM(REGEXP_REPLACE(p_ap, '[[:space:]]+', ' ')), '');
  SET p_am = NULLIF(TRIM(REGEXP_REPLACE(p_am, '[[:space:]]+', ' ')), '');
  SET p_curp = NULLIF(UPPER(TRIM(p_curp)), '');
  SET p_tel = NULLIF(REGEXP_REPLACE(p_tel, '[^0-9]', ''), '');          -- "44-33-67-12-07" → 4433671207
  IF p_nac > CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de nacimiento no puede ser posterior a hoy.';
  END IF;
  IF p_nac < '1900-01-01' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de nacimiento es demasiado antigua; revísela.';
  END IF;
END //

CREATE TRIGGER trg_persona_bi BEFORE INSERT ON persona FOR EACH ROW
BEGIN
  CALL _validar_persona(NEW.nombres, NEW.apellido_paterno, NEW.apellido_materno, NEW.curp, NEW.telefono, NEW.fecha_nacimiento);
END //

CREATE TRIGGER trg_persona_bu BEFORE UPDATE ON persona FOR EACH ROW
BEGIN
  CALL _validar_persona(NEW.nombres, NEW.apellido_paterno, NEW.apellido_materno, NEW.curp, NEW.telefono, NEW.fecha_nacimiento);
END //

-- ---------------------------------------------------------------------
-- Periodos en MESE: fechas no futuras y sin encimarse con otros periodos
-- ---------------------------------------------------------------------
CREATE PROCEDURE _validar_inscripcion(IN p_id INT UNSIGNED, IN p_part INT UNSIGNED, IN p_ing DATE, IN p_baja DATE)
BEGIN
  IF p_ing IS NULL THEN SET p_ing = '1000-01-01'; END IF;   -- histórico sin fechas: no se compara
  IF p_ing > CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de ingreso no puede ser posterior a hoy.';
  END IF;
  IF p_baja > CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de baja no puede ser posterior a hoy.';
  END IF;
  IF EXISTS (SELECT 1 FROM inscripcion i
              WHERE i.participante_id = p_part AND i.id <> COALESCE(p_id, 0) AND NOT i.sin_fechas AND p_ing > '1000-01-01'
                AND i.fecha_ingreso < COALESCE(p_baja, '9999-12-31')        -- puede salir y volver a entrar el mismo día
                AND COALESCE(i.fecha_baja, '9999-12-31') > p_ing) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este periodo se encima con otro periodo del mismo participante (¿ya está activo?).';
  END IF;
END //

CREATE TRIGGER trg_inscripcion_bi BEFORE INSERT ON inscripcion FOR EACH ROW
BEGIN
  CALL _validar_inscripcion(NULL, NEW.participante_id, NEW.fecha_ingreso, NEW.fecha_baja);
END //

CREATE TRIGGER trg_inscripcion_bu BEFORE UPDATE ON inscripcion FOR EACH ROW
BEGIN
  CALL _validar_inscripcion(OLD.id, NEW.participante_id, NEW.fecha_ingreso, NEW.fecha_baja);
END //

-- ---------------------------------------------------------------------
-- Respuestas: una sola opción en preguntas de respuesta única,
-- y "Otro" solo donde la pregunta lo permite
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_respuesta_bi BEFORE INSERT ON visita_respuesta FOR EACH ROW
BEGIN
  DECLARE v_tipo VARCHAR(8); DECLARE v_otro BOOLEAN; DECLARE v_texto VARCHAR(160);
  SELECT tipo, permite_otro, texto INTO v_tipo, v_otro, v_texto FROM cat_pregunta WHERE id = NEW.pregunta_id;
  IF v_tipo = 'UNICA' AND EXISTS (SELECT 1 FROM visita_respuesta WHERE visita_id = NEW.visita_id AND pregunta_id = NEW.pregunta_id) THEN
    SET v_texto = CONCAT('La pregunta "', LEFT(v_texto, 80), '" admite una sola respuesta.');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_texto;
  END IF;
  IF NEW.opcion_id IS NULL AND NOT v_otro AND (SELECT clave FROM cat_pregunta WHERE id = NEW.pregunta_id) <> 'adi_o' THEN
    SET v_texto = CONCAT('La pregunta "', LEFT(v_texto, 80), '" no acepta respuestas escritas ("Otro").');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_texto;
  END IF;
END //

-- ---------------------------------------------------------------------
-- Visitas: fecha no futura y el participante debe ser de esa familia
-- ---------------------------------------------------------------------
CREATE PROCEDURE _validar_visita(IN p_fecha DATE, IN p_fam INT UNSIGNED, IN p_part INT UNSIGNED)
BEGIN
  IF p_fecha > CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de la visita no puede ser posterior a hoy.';
  END IF;
  IF p_part IS NOT NULL AND NOT EXISTS (SELECT 1 FROM participante WHERE persona_id = p_part AND familia_id = p_fam) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El participante de la visita no pertenece a esa familia.';
  END IF;
END //

CREATE TRIGGER trg_visita_bi BEFORE INSERT ON visita FOR EACH ROW
BEGIN
  CALL _validar_visita(NEW.fecha, NEW.familia_id, NEW.participante_id);
END //

CREATE TRIGGER trg_visita_bu BEFORE UPDATE ON visita FOR EACH ROW
BEGIN
  CALL _validar_visita(NEW.fecha, NEW.familia_id, NEW.participante_id);
END //

-- ---------------------------------------------------------------------
-- Bitácora: quién cambió qué y cuándo (personas, periodos y visitas)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_persona_ai AFTER INSERT ON persona FOR EACH ROW
BEGIN
  IF COALESCE(@importando, 0) = 0 THEN
    INSERT INTO bitacora (tabla, registro_id, accion, usuario_id, despues)
    VALUES ('persona', NEW.id, 'INSERT', @usuario_id, JSON_OBJECT('nombre', NEW.nombre_completo, 'nacimiento', NEW.fecha_nacimiento, 'curp', NEW.curp));
  END IF;
END //

CREATE TRIGGER trg_persona_au AFTER UPDATE ON persona FOR EACH ROW
BEGIN
  IF COALESCE(@importando, 0) = 0 THEN
    INSERT INTO bitacora (tabla, registro_id, accion, usuario_id, antes, despues)
    VALUES ('persona', NEW.id, 'UPDATE', @usuario_id,
            JSON_OBJECT('nombre', OLD.nombre_completo, 'nacimiento', OLD.fecha_nacimiento, 'curp', OLD.curp, 'telefono', OLD.telefono),
            JSON_OBJECT('nombre', NEW.nombre_completo, 'nacimiento', NEW.fecha_nacimiento, 'curp', NEW.curp, 'telefono', NEW.telefono));
  END IF;
END //

CREATE TRIGGER trg_inscripcion_ai AFTER INSERT ON inscripcion FOR EACH ROW
BEGIN
  IF COALESCE(@importando, 0) = 0 THEN
    INSERT INTO bitacora (tabla, registro_id, accion, usuario_id, despues)
    VALUES ('inscripcion', NEW.id, 'INSERT', @usuario_id, JSON_OBJECT('participante', NEW.participante_id, 'ingreso', NEW.fecha_ingreso, 'baja', NEW.fecha_baja));
  END IF;
END //

CREATE TRIGGER trg_inscripcion_au AFTER UPDATE ON inscripcion FOR EACH ROW
BEGIN
  IF COALESCE(@importando, 0) = 0 THEN
    INSERT INTO bitacora (tabla, registro_id, accion, usuario_id, antes, despues)
    VALUES ('inscripcion', NEW.id, 'UPDATE', @usuario_id,
            JSON_OBJECT('ingreso', OLD.fecha_ingreso, 'baja', OLD.fecha_baja, 'causa', OLD.causa_baja_id),
            JSON_OBJECT('ingreso', NEW.fecha_ingreso, 'baja', NEW.fecha_baja, 'causa', NEW.causa_baja_id));
  END IF;
END //

CREATE TRIGGER trg_inscripcion_ad AFTER DELETE ON inscripcion FOR EACH ROW
BEGIN
  IF COALESCE(@importando, 0) = 0 THEN
  INSERT INTO bitacora (tabla, registro_id, accion, usuario_id, antes)
  VALUES ('inscripcion', OLD.id, 'DELETE', @usuario_id, JSON_OBJECT('participante', OLD.participante_id, 'ingreso', OLD.fecha_ingreso, 'baja', OLD.fecha_baja));
  END IF;
END //

CREATE TRIGGER trg_visita_au AFTER UPDATE ON visita FOR EACH ROW
BEGIN
  IF COALESCE(@importando, 0) = 0 AND (OLD.estado <> NEW.estado OR OLD.fecha <> NEW.fecha OR NOT (OLD.familia_id <=> NEW.familia_id)) THEN
    INSERT INTO bitacora (tabla, registro_id, accion, usuario_id, antes, despues)
    VALUES ('visita', NEW.id, 'UPDATE', @usuario_id,
            JSON_OBJECT('estado', OLD.estado, 'fecha', OLD.fecha), JSON_OBJECT('estado', NEW.estado, 'fecha', NEW.fecha));
  END IF;
END //

CREATE TRIGGER trg_visita_ad AFTER DELETE ON visita FOR EACH ROW
BEGIN
  IF COALESCE(@importando, 0) = 0 THEN
  INSERT INTO bitacora (tabla, registro_id, accion, usuario_id, antes)
  VALUES ('visita', OLD.id, 'DELETE', @usuario_id, JSON_OBJECT('familia', OLD.familia_id, 'fecha', OLD.fecha, 'estado', OLD.estado));
  END IF;
END //

DELIMITER ;

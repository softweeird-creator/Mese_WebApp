-- =====================================================================
--  MESE Vasco de Quiroga I.A.P. · Base de datos
--  01_esquema.sql — tablas, llaves, restricciones e índices
--  Motor: MySQL 8.0.16 o superior (InnoDB, utf8mb4)
--
--  Ideas clave del diseño
--  * Una persona se guarda UNA sola vez (persona). Participante, tutor e
--    integrante de la familia son papeles que una persona tiene.
--  * Los datos de la casa y la situación económica cambian con el tiempo:
--    se guardan por visita (estudio socioeconómico) con su fecha. La
--    "situación actual" de una familia es su visita terminada más reciente.
--  * La permanencia en MESE se guarda como periodos (inscripcion): fecha de
--    ingreso y, si salió, fecha y causa de baja. Activos, bajas e histórico
--    salen de la misma tabla; no hay datos copiados entre hojas.
--  * Nada que se pueda calcular se guarda (edad, años de permanencia,
--    ingreso total, ingreso por integrante): lo calculan las vistas.
--  * Las listas de opciones son tablas (cat_*), no texto libre, para que
--    "UNIÓN LIBRE", "UNION LIBRE" y "UNIÓN LINRE" sean un solo valor.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS mese
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;   -- sin distinguir acentos ni mayúsculas al buscar
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS bitacora, visita_firma, visita_antecedente, visita_monto, visita_vacuna,
  visita_respuesta, visita_integrante, visita, cat_opcion, cat_pregunta, cat_seccion,
  participante_beca, participante_escolaridad, inscripcion_riesgo, inscripcion, participante,
  familia_integrante, familia, persona, usuario, cat_rango_edad, cat_concepto_monto, cat_vacuna,
  cat_tipo_riesgo, cat_nivel_riesgo, cat_certificado, cat_caso_exito, cat_causa_baja_estadistica,
  cat_causa_baja, cat_patrocinador, cat_turno, cat_ciclo_escolar, cat_carrera, cat_escuela,
  cat_nivel_grado, cat_nivel_educativo, cat_tipo_sangre, cat_estado_civil, cat_ocupacion,
  cat_parentesco, cat_colonia, cat_municipio, cat_alias;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 1. Catálogos
-- ---------------------------------------------------------------------
CREATE TABLE cat_municipio (
  id      SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(80) NOT NULL,
  estado  VARCHAR(40) NOT NULL DEFAULT 'Michoacán',
  UNIQUE KEY uq_municipio (nombre, estado)
) ENGINE=InnoDB;

CREATE TABLE cat_colonia (
  id             SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre         VARCHAR(100) NOT NULL,
  codigo_postal  CHAR(5) NULL,
  municipio_id   SMALLINT UNSIGNED NOT NULL,
  UNIQUE KEY uq_colonia (nombre, municipio_id),
  CONSTRAINT ck_colonia_cp CHECK (codigo_postal REGEXP '^[0-9]{5}$'),
  CONSTRAINT fk_colonia_municipio FOREIGN KEY (municipio_id) REFERENCES cat_municipio(id)
) ENGINE=InnoDB;

CREATE TABLE cat_parentesco (
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(40) NOT NULL UNIQUE,          -- Madre, Padre, Hermano, Abuela...
  puede_ser_tutor BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;

CREATE TABLE cat_ocupacion (
  id      SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(80) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_estado_civil (
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(30) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_tipo_sangre (
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(12) NOT NULL UNIQUE           -- O+, O−, A+ ... No sabe
) ENGINE=InnoDB;

CREATE TABLE cat_nivel_educativo (
  id          TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clave       VARCHAR(10) NOT NULL UNIQUE,      -- PREESC, PRIM, SEC, PREPA, TEC, OFICIO, LIC...
  nombre      VARCHAR(40) NOT NULL UNIQUE,
  grados      TINYINT UNSIGNED NOT NULL,        -- grados que tiene el nivel
  orden       TINYINT UNSIGNED NOT NULL,
  CONSTRAINT ck_nivel_grados CHECK (grados BETWEEN 1 AND 6)
) ENGINE=InnoDB;

-- Grados válidos por nivel (Primaria 1–6, Secundaria 1–3, ...).
-- Las llaves foráneas (nivel, grado) hacia esta tabla impiden "Secundaria 5°" sin triggers.
CREATE TABLE cat_nivel_grado (
  nivel_id  TINYINT UNSIGNED NOT NULL,
  grado     TINYINT UNSIGNED NOT NULL,
  PRIMARY KEY (nivel_id, grado),
  CONSTRAINT fk_nivelgrado_nivel FOREIGN KEY (nivel_id) REFERENCES cat_nivel_educativo(id)
) ENGINE=InnoDB;

CREATE TABLE cat_escuela (
  id        SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre    VARCHAR(150) NOT NULL UNIQUE,
  nivel_id  TINYINT UNSIGNED NULL,
  cct       VARCHAR(12) NULL UNIQUE,            -- clave de centro de trabajo SEP, si se conoce
  CONSTRAINT fk_escuela_nivel FOREIGN KEY (nivel_id) REFERENCES cat_nivel_educativo(id)
) ENGINE=InnoDB;

CREATE TABLE cat_carrera (                      -- carrera, bachillerato u oficio
  id      SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(120) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_ciclo_escolar (
  id      SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  CHAR(9) NOT NULL UNIQUE,              -- 2025-2026
  inicio  DATE NOT NULL,
  fin     DATE NOT NULL,
  CONSTRAINT ck_ciclo_fechas CHECK (fin > inicio),
  CONSTRAINT ck_ciclo_nombre CHECK (nombre REGEXP '^[0-9]{4}-[0-9]{4}$')
) ENGINE=InnoDB;

CREATE TABLE cat_turno (
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(20) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_patrocinador (                 -- quién paga la beca: Repsol, Soriana, Bécalos, MESE...
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(60) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_causa_baja (
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(80) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_causa_baja_estadistica (       -- qué pasó con el menor al salir
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(60) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_caso_exito (                   -- nivel con el que concluyó (para la estadística)
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(60) NOT NULL UNIQUE,
  orden   TINYINT UNSIGNED NOT NULL
) ENGINE=InnoDB;

CREATE TABLE cat_certificado (
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(80) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_nivel_riesgo (
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(10) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_tipo_riesgo (
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(20) NOT NULL UNIQUE            -- Económico, Emocional, Educativo
) ENGINE=InnoDB;

CREATE TABLE cat_vacuna (
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(40) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_concepto_monto (               -- ingreso declarado, apoyos gubernamentales y egresos del hogar
  id      TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  clave   VARCHAR(10) NOT NULL UNIQUE,          -- la misma clave que usa la página web (ap_bj, eg_renta...)
  tipo    VARCHAR(7) NOT NULL,
  nombre  VARCHAR(90) NOT NULL,
  orden   TINYINT UNSIGNED NOT NULL,
  UNIQUE KEY uq_concepto (tipo, nombre),
  CONSTRAINT ck_concepto_tipo CHECK (tipo IN ('INGRESO','APOYO','EGRESO'))
) ENGINE=InnoDB;

-- Rangos de edad de la hoja de estadísticas: son datos, no código.
-- Si MESE cambia un rango, se edita aquí y todos los reportes cambian.
CREATE TABLE cat_rango_edad (
  id        TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  grupo     VARCHAR(20) NOT NULL,               -- DIRECTOS, TUTORES, RANGOS_TUTORES, INDIRECTOS
  etiqueta  VARCHAR(15) NOT NULL,
  edad_min  TINYINT UNSIGNED NOT NULL,
  edad_max  TINYINT UNSIGNED NOT NULL,
  orden     TINYINT UNSIGNED NOT NULL,
  UNIQUE KEY uq_rango (grupo, etiqueta),
  CONSTRAINT ck_rango CHECK (edad_max >= edad_min)
) ENGINE=InnoDB;

-- Equivalencias para limpiar texto escrito a mano al importar desde Excel
-- (p. ej. 'UNIÓN LINRE' → Unión libre; 'IMMS-BIENESTAR' → IMSS Bienestar).
CREATE TABLE cat_alias (
  dominio  VARCHAR(30)  NOT NULL,               -- estado_civil, ocupacion, opcion:casa ...
  texto    VARCHAR(150) NOT NULL,               -- como viene en Excel (normalizado sin acentos)
  valor    VARCHAR(150) NOT NULL,               -- valor correcto del catálogo
  PRIMARY KEY (dominio, texto)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. Usuarios del sistema (trabajadoras sociales, coordinación)
-- ---------------------------------------------------------------------
CREATE TABLE usuario (
  id        SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre    VARCHAR(100) NOT NULL,
  correo    VARCHAR(120) NULL UNIQUE,
  rol       VARCHAR(20)  NOT NULL DEFAULT 'TRABAJO_SOCIAL',
  activo    BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT ck_usuario_rol CHECK (rol IN ('TRABAJO_SOCIAL','COORDINACION','ADMIN'))
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. Personas y familias
-- ---------------------------------------------------------------------
CREATE TABLE persona (
  id                 INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombres            VARCHAR(80)  NOT NULL,
  apellido_paterno   VARCHAR(60)  NULL,
  apellido_materno   VARCHAR(60)  NULL,
  fecha_nacimiento   DATE NULL,
  fecha_nac_aprox    BOOLEAN NOT NULL DEFAULT FALSE,   -- TRUE si solo se sabía la edad
  genero             CHAR(1) NULL,
  curp               CHAR(18) NULL,
  tipo_sangre_id     TINYINT UNSIGNED NULL,
  estado_civil_id    TINYINT UNSIGNED NULL,
  ocupacion_id       SMALLINT UNSIGNED NULL,
  escolaridad_nivel_id TINYINT UNSIGNED NULL,          -- último nivel cursado (adultos)
  escolaridad_grado  TINYINT UNSIGNED NULL,
  escolaridad_nota   VARCHAR(120) NULL,                -- "trunca", "INEA", "carrera técnica en..."
  telefono           VARCHAR(15) NULL,
  correo             VARCHAR(120) NULL,
  nombre_completo    VARCHAR(210) AS (CONCAT_WS(' ', nombres, apellido_paterno, apellido_materno)) STORED,
  creado_en          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modificado_en      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_persona_curp (curp),
  KEY ix_persona_apellidos (apellido_paterno, apellido_materno, nombres),
  KEY ix_persona_nombre_completo (nombre_completo),
  KEY ix_persona_nacimiento (fecha_nacimiento),
  CONSTRAINT ck_persona_genero CHECK (genero IN ('F','M')),
  CONSTRAINT ck_persona_curp CHECK (curp = UPPER(curp) AND curp REGEXP '^[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[0-9A-Z][0-9]$'),
  CONSTRAINT ck_persona_tel CHECK (telefono REGEXP '^[0-9]{10}$'),
  CONSTRAINT ck_persona_correo CHECK (correo LIKE '%_@_%._%'),
  CONSTRAINT ck_persona_nombre CHECK (TRIM(nombres) <> ''),
  CONSTRAINT fk_persona_sangre FOREIGN KEY (tipo_sangre_id) REFERENCES cat_tipo_sangre(id),
  CONSTRAINT fk_persona_civil FOREIGN KEY (estado_civil_id) REFERENCES cat_estado_civil(id),
  CONSTRAINT fk_persona_ocupacion FOREIGN KEY (ocupacion_id) REFERENCES cat_ocupacion(id),
  CONSTRAINT fk_persona_escolaridad FOREIGN KEY (escolaridad_nivel_id, escolaridad_grado) REFERENCES cat_nivel_grado(nivel_id, grado),
  CONSTRAINT fk_persona_nivel FOREIGN KEY (escolaridad_nivel_id) REFERENCES cat_nivel_educativo(id)
) ENGINE=InnoDB;

CREATE TABLE familia (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  folio            VARCHAR(20) NULL UNIQUE,            -- folio de la sábana de familias
  calle            VARCHAR(120) NULL,
  numero_ext       VARCHAR(15) NULL,
  numero_int       VARCHAR(15) NULL,
  colonia_id       SMALLINT UNSIGNED NULL,
  referencias      VARCHAR(200) NULL,
  entre_calles     VARCHAR(200) NULL,
  latitud          DECIMAL(9,6) NULL,
  longitud         DECIMAL(9,6) NULL,
  telefono         VARCHAR(15) NULL,                   -- teléfono de la casa / familiar
  correo           VARCHAR(120) NULL,
  aviso_privacidad DATE NULL,                          -- fecha en que firmaron el aviso
  creado_en        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modificado_en    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY ix_familia_colonia (colonia_id),
  CONSTRAINT ck_familia_tel CHECK (telefono REGEXP '^[0-9]{10}$'),
  CONSTRAINT ck_familia_gps CHECK (latitud BETWEEN -90 AND 90 AND longitud BETWEEN -180 AND 180),
  CONSTRAINT fk_familia_colonia FOREIGN KEY (colonia_id) REFERENCES cat_colonia(id)
) ENGINE=InnoDB;

-- Personas que viven con el participante o son sus tutores (todas menos los participantes).
CREATE TABLE familia_integrante (
  familia_id     INT UNSIGNED NOT NULL,
  persona_id     INT UNSIGNED NOT NULL,
  parentesco_id  TINYINT UNSIGNED NOT NULL,           -- respecto a los participantes de la familia
  es_tutor       BOOLEAN NOT NULL DEFAULT FALSE,
  vive_en_casa   BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (familia_id, persona_id),
  KEY ix_integrante_persona (persona_id),
  CONSTRAINT fk_integrante_familia FOREIGN KEY (familia_id) REFERENCES familia(id) ON DELETE CASCADE,
  CONSTRAINT fk_integrante_persona FOREIGN KEY (persona_id) REFERENCES persona(id),
  CONSTRAINT fk_integrante_parentesco FOREIGN KEY (parentesco_id) REFERENCES cat_parentesco(id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. Participantes, permanencia, escolaridad y becas
-- ---------------------------------------------------------------------
CREATE TABLE participante (
  persona_id       INT UNSIGNED PRIMARY KEY,           -- subtipo 1:1 de persona
  familia_id       INT UNSIGNED NOT NULL,
  numero_becado    TINYINT UNSIGNED NULL,              -- 1er, 2º... hermano becado de la familia
  grupo_beca       TINYINT UNSIGNED NULL,
  trabajadora_id   SMALLINT UNSIGNED NULL,             -- trabajadora social asignada
  KEY ix_participante_familia (familia_id),
  CONSTRAINT ck_participante_grupo CHECK (grupo_beca BETWEEN 1 AND 9),
  CONSTRAINT fk_participante_persona FOREIGN KEY (persona_id) REFERENCES persona(id),
  CONSTRAINT fk_participante_familia FOREIGN KEY (familia_id) REFERENCES familia(id),
  CONSTRAINT fk_participante_ts FOREIGN KEY (trabajadora_id) REFERENCES usuario(id)
) ENGINE=InnoDB;

-- Cada periodo en MESE. Activo = periodo sin fecha de baja.
CREATE TABLE inscripcion (
  id                      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  participante_id         INT UNSIGNED NOT NULL,
  fecha_ingreso           DATE NULL,                   -- NULL solo en registros históricos sin fechas
  fecha_baja              DATE NULL,
  sin_fechas              BOOLEAN NOT NULL DEFAULT FALSE,  -- salió de MESE pero no se registró cuándo
  causa_baja_id           TINYINT UNSIGNED NULL,
  causa_estadistica_id    TINYINT UNSIGNED NULL,
  motivo                  TEXT NULL,                   -- explicación escrita por trabajo social
  caso_exito_id           TINYINT UNSIGNED NULL,
  caso_exito_detalle      VARCHAR(150) NULL,           -- "Oficio en belleza", "Lic. en Derecho"
  certificado_id          TINYINT UNSIGNED NULL,
  nivel_inicial_id        TINYINT UNSIGNED NULL,
  grado_inicial           TINYINT UNSIGNED NULL,
  nivel_final_id          TINYINT UNSIGNED NULL,
  grado_final             TINYINT UNSIGNED NULL,
  riesgo_ingreso_id       TINYINT UNSIGNED NULL,
  riesgo_egreso_id        TINYINT UNSIGNED NULL,
  -- 1 cuando el periodo está abierto, NULL cuando está cerrado. Con la llave única de abajo,
  -- la base impide que alguien tenga dos periodos abiertos a la vez (sin trigger).
  abierta                 TINYINT AS (IF(fecha_baja IS NULL AND NOT sin_fechas, 1, NULL)) STORED,
  creado_en               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_un_periodo_abierto (participante_id, abierta),
  KEY ix_inscripcion_fechas (fecha_ingreso, fecha_baja),
  KEY ix_inscripcion_baja (fecha_baja),
  CONSTRAINT ck_insc_fechas CHECK (fecha_baja IS NULL OR fecha_baja >= fecha_ingreso),
  CONSTRAINT ck_insc_ingreso CHECK (fecha_ingreso IS NOT NULL OR (sin_fechas AND fecha_baja IS NULL)),
  CONSTRAINT ck_insc_causa CHECK (fecha_baja IS NOT NULL OR sin_fechas OR (causa_baja_id IS NULL AND causa_estadistica_id IS NULL AND caso_exito_id IS NULL)),
  CONSTRAINT fk_insc_participante FOREIGN KEY (participante_id) REFERENCES participante(persona_id),
  CONSTRAINT fk_insc_causa FOREIGN KEY (causa_baja_id) REFERENCES cat_causa_baja(id),
  CONSTRAINT fk_insc_causa_est FOREIGN KEY (causa_estadistica_id) REFERENCES cat_causa_baja_estadistica(id),
  CONSTRAINT fk_insc_exito FOREIGN KEY (caso_exito_id) REFERENCES cat_caso_exito(id),
  CONSTRAINT fk_insc_certificado FOREIGN KEY (certificado_id) REFERENCES cat_certificado(id),
  CONSTRAINT fk_insc_esc_inicial FOREIGN KEY (nivel_inicial_id, grado_inicial) REFERENCES cat_nivel_grado(nivel_id, grado),
  CONSTRAINT fk_insc_esc_final FOREIGN KEY (nivel_final_id, grado_final) REFERENCES cat_nivel_grado(nivel_id, grado),
  CONSTRAINT fk_insc_riesgo_in FOREIGN KEY (riesgo_ingreso_id) REFERENCES cat_nivel_riesgo(id),
  CONSTRAINT fk_insc_riesgo_out FOREIGN KEY (riesgo_egreso_id) REFERENCES cat_nivel_riesgo(id)
) ENGINE=InnoDB;

CREATE TABLE inscripcion_riesgo (                     -- "ECONÓMICO/EMOCIONAL" = dos filas
  inscripcion_id  INT UNSIGNED NOT NULL,
  momento         CHAR(7) NOT NULL,
  tipo_riesgo_id  TINYINT UNSIGNED NOT NULL,
  PRIMARY KEY (inscripcion_id, momento, tipo_riesgo_id),
  CONSTRAINT ck_riesgo_momento CHECK (momento IN ('INGRESO','EGRESO')),
  CONSTRAINT fk_riesgo_insc FOREIGN KEY (inscripcion_id) REFERENCES inscripcion(id) ON DELETE CASCADE,
  CONSTRAINT fk_riesgo_tipo FOREIGN KEY (tipo_riesgo_id) REFERENCES cat_tipo_riesgo(id)
) ENGINE=InnoDB;

-- Escuela y grado por ciclo escolar (historial completo, no solo el actual).
CREATE TABLE participante_escolaridad (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  participante_id  INT UNSIGNED NOT NULL,
  ciclo_id         SMALLINT UNSIGNED NOT NULL,
  escuela_id       SMALLINT UNSIGNED NULL,
  nivel_id         TINYINT UNSIGNED NOT NULL,
  grado            TINYINT UNSIGNED NOT NULL,
  carrera_id       SMALLINT UNSIGNED NULL,
  grupo            VARCHAR(12) NULL,
  turno_id         TINYINT UNSIGNED NULL,
  UNIQUE KEY uq_escolaridad_ciclo (participante_id, ciclo_id),
  KEY ix_escolaridad_nivel (nivel_id, grado),
  CONSTRAINT fk_esc_participante FOREIGN KEY (participante_id) REFERENCES participante(persona_id) ON DELETE CASCADE,
  CONSTRAINT fk_esc_ciclo FOREIGN KEY (ciclo_id) REFERENCES cat_ciclo_escolar(id),
  CONSTRAINT fk_esc_escuela FOREIGN KEY (escuela_id) REFERENCES cat_escuela(id),
  CONSTRAINT fk_esc_nivel_grado FOREIGN KEY (nivel_id, grado) REFERENCES cat_nivel_grado(nivel_id, grado),
  CONSTRAINT fk_esc_carrera FOREIGN KEY (carrera_id) REFERENCES cat_carrera(id),
  CONSTRAINT fk_esc_turno FOREIGN KEY (turno_id) REFERENCES cat_turno(id)
) ENGINE=InnoDB;

-- "REPSOL/BÉCALOS" = dos becas a la vez: dos filas.
CREATE TABLE participante_beca (
  participante_id  INT UNSIGNED NOT NULL,
  patrocinador_id  TINYINT UNSIGNED NOT NULL,
  desde            DATE NOT NULL,
  hasta            DATE NULL,
  PRIMARY KEY (participante_id, patrocinador_id, desde),
  CONSTRAINT ck_beca_fechas CHECK (hasta IS NULL OR hasta >= desde),
  CONSTRAINT fk_beca_participante FOREIGN KEY (participante_id) REFERENCES participante(persona_id) ON DELETE CASCADE,
  CONSTRAINT fk_beca_patrocinador FOREIGN KEY (patrocinador_id) REFERENCES cat_patrocinador(id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. Cuestionario de seguimiento familiar (visitas domiciliarias)
--    Las preguntas de opción viven en catálogos: si MESE agrega o cambia
--    una pregunta del formato, se insertan filas; no se modifica la tabla.
-- ---------------------------------------------------------------------
CREATE TABLE cat_seccion (
  id      TINYINT UNSIGNED PRIMARY KEY,         -- 0 = valoración de trabajo social, 1–10 = formato
  nombre  VARCHAR(80) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cat_pregunta (
  id           SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  seccion_id   TINYINT UNSIGNED NOT NULL,
  clave        VARCHAR(20) NOT NULL UNIQUE,     -- la misma clave que usa la página web (casa, serv, piso...)
  texto        VARCHAR(160) NOT NULL,
  tipo         VARCHAR(8) NOT NULL,             -- UNICA = una respuesta, MULTIPLE = varias
  permite_otro BOOLEAN NOT NULL DEFAULT FALSE,
  orden        SMALLINT UNSIGNED NOT NULL,
  activa       BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT ck_pregunta_tipo CHECK (tipo IN ('UNICA','MULTIPLE')),
  CONSTRAINT fk_pregunta_seccion FOREIGN KEY (seccion_id) REFERENCES cat_seccion(id)
) ENGINE=InnoDB;

CREATE TABLE cat_opcion (
  id           SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  pregunta_id  SMALLINT UNSIGNED NOT NULL,
  etiqueta     VARCHAR(60) NOT NULL,
  orden        TINYINT UNSIGNED NOT NULL,
  UNIQUE KEY uq_opcion (pregunta_id, etiqueta),
  UNIQUE KEY uq_opcion_pregunta (id, pregunta_id),      -- permite la llave foránea compuesta de abajo
  CONSTRAINT fk_opcion_pregunta FOREIGN KEY (pregunta_id) REFERENCES cat_pregunta(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE visita (
  id                    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid_cliente          VARCHAR(40) NULL UNIQUE,  -- id creado en el teléfono (sincronizar sin duplicar)
  familia_id            INT UNSIGNED NOT NULL,
  participante_id       INT UNSIGNED NULL,
  usuario_id            SMALLINT UNSIGNED NULL,   -- trabajadora social que la hizo
  fecha                 DATE NOT NULL,
  folio_seguimiento     VARCHAR(20) NULL,
  cuadrante             VARCHAR(20) NULL,
  estado                VARCHAR(9) NOT NULL DEFAULT 'BORRADOR',
  verificada_en         VARCHAR(9) NULL,
  origen                VARCHAR(10) NOT NULL DEFAULT 'WEB',
  recamaras             TINYINT UNSIGNED NULL,
  banos                 TINYINT UNSIGNED NULL,
  num_integrantes       TINYINT UNSIGNED NULL,    -- solo si no se capturó la lista (datos importados)
  actividad_comunitaria VARCHAR(200) NULL,
  actividad_fisica      VARCHAR(200) NULL,
  actividad_productiva  VARCHAR(200) NULL,
  huerto_motivo         VARCHAR(200) NULL,
  huerto_beneficio      VARCHAR(200) NULL,
  deudas_detalle        VARCHAR(200) NULL,
  necesidad_material    VARCHAR(300) NULL,
  documentos_obs        VARCHAR(300) NULL,
  mejora_condiciones    TEXT NULL,
  hacinamiento_obs      TEXT NULL,
  diagnostico_social    TEXT NULL,
  notas                 TEXT NULL,                -- observaciones libres (p. ej. texto de Excel que no encaja en una opción)
  latitud               DECIMAL(9,6) NULL,
  longitud              DECIMAL(9,6) NULL,
  creado_en             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modificado_en         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY ix_visita_familia_fecha (familia_id, fecha),
  KEY ix_visita_fecha (fecha),
  KEY ix_visita_usuario (usuario_id, fecha),
  CONSTRAINT ck_visita_estado CHECK (estado IN ('BORRADOR','COMPLETA')),
  CONSTRAINT ck_visita_verif CHECK (verificada_en IN ('DOMICILIO','OFICINA')),
  CONSTRAINT ck_visita_origen CHECK (origen IN ('WEB','EXCEL','OFICINA')),
  CONSTRAINT ck_visita_gps CHECK (latitud BETWEEN -90 AND 90 AND longitud BETWEEN -180 AND 180),
  CONSTRAINT fk_visita_familia FOREIGN KEY (familia_id) REFERENCES familia(id),
  CONSTRAINT fk_visita_participante FOREIGN KEY (participante_id) REFERENCES participante(persona_id),
  CONSTRAINT fk_visita_usuario FOREIGN KEY (usuario_id) REFERENCES usuario(id)
) ENGINE=InnoDB;

-- Respuestas de opción. La llave compuesta (opcion_id, pregunta_id) garantiza que la opción
-- pertenece a esa pregunta: no se puede contestar "Vitropiso" a "¿Cuántas comidas al día?".
CREATE TABLE visita_respuesta (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  visita_id    INT UNSIGNED NOT NULL,
  pregunta_id  SMALLINT UNSIGNED NOT NULL,
  opcion_id    SMALLINT UNSIGNED NULL,          -- NULL cuando la respuesta es "Otro" escrito
  texto_otro   VARCHAR(120) NULL,
  UNIQUE KEY uq_respuesta (visita_id, pregunta_id, opcion_id),
  KEY ix_respuesta_opcion (opcion_id),
  CONSTRAINT ck_respuesta_valor CHECK (opcion_id IS NOT NULL OR texto_otro IS NOT NULL),
  CONSTRAINT fk_resp_visita FOREIGN KEY (visita_id) REFERENCES visita(id) ON DELETE CASCADE,
  CONSTRAINT fk_resp_pregunta FOREIGN KEY (pregunta_id) REFERENCES cat_pregunta(id),
  CONSTRAINT fk_resp_opcion FOREIGN KEY (opcion_id, pregunta_id) REFERENCES cat_opcion(id, pregunta_id)
) ENGINE=InnoDB;

-- Quién vive en la casa al momento de la visita y cuánto gana (sección 2).
CREATE TABLE visita_integrante (
  visita_id        INT UNSIGNED NOT NULL,
  persona_id       INT UNSIGNED NOT NULL,
  parentesco_id    TINYINT UNSIGNED NULL,
  ocupacion_id     SMALLINT UNSIGNED NULL,
  ingreso_mensual  DECIMAL(10,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (visita_id, persona_id),
  CONSTRAINT ck_vi_ingreso CHECK (ingreso_mensual >= 0),
  CONSTRAINT fk_vi_visita FOREIGN KEY (visita_id) REFERENCES visita(id) ON DELETE CASCADE,
  CONSTRAINT fk_vi_persona FOREIGN KEY (persona_id) REFERENCES persona(id),
  CONSTRAINT fk_vi_parentesco FOREIGN KEY (parentesco_id) REFERENCES cat_parentesco(id),
  CONSTRAINT fk_vi_ocupacion FOREIGN KEY (ocupacion_id) REFERENCES cat_ocupacion(id)
) ENGINE=InnoDB;

-- Ingreso familiar declarado (cuando no hay detalle por persona), apoyos (sección 3) y egresos (sección 10).
CREATE TABLE visita_monto (
  visita_id    INT UNSIGNED NOT NULL,
  concepto_id  TINYINT UNSIGNED NOT NULL,
  monto        DECIMAL(10,2) NOT NULL,
  detalle      VARCHAR(100) NULL,               -- "Otro apoyo: ..."
  PRIMARY KEY (visita_id, concepto_id),
  CONSTRAINT ck_monto CHECK (monto >= 0),
  CONSTRAINT fk_monto_visita FOREIGN KEY (visita_id) REFERENCES visita(id) ON DELETE CASCADE,
  CONSTRAINT fk_monto_concepto FOREIGN KEY (concepto_id) REFERENCES cat_concepto_monto(id)
) ENGINE=InnoDB;

CREATE TABLE visita_vacuna (                      -- COVID-19 y sarampión, participante y tutor
  visita_id   INT UNSIGNED NOT NULL,
  vacuna_id   TINYINT UNSIGNED NOT NULL,
  rol         VARCHAR(12) NOT NULL,
  aplicada    BOOLEAN NOT NULL,
  dosis       TINYINT UNSIGNED NULL,
  PRIMARY KEY (visita_id, vacuna_id, rol),
  CONSTRAINT ck_vacuna_rol CHECK (rol IN ('PARTICIPANTE','TUTOR')),
  CONSTRAINT ck_vacuna_dosis CHECK (dosis <= 10 AND (aplicada OR dosis IS NULL OR dosis = 0)),
  CONSTRAINT fk_vac_visita FOREIGN KEY (visita_id) REFERENCES visita(id) ON DELETE CASCADE,
  CONSTRAINT fk_vac_vacuna FOREIGN KEY (vacuna_id) REFERENCES cat_vacuna(id)
) ENGINE=InnoDB;

CREATE TABLE visita_antecedente (                 -- antecedentes médicos familiares (sección 8)
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  visita_id        INT UNSIGNED NOT NULL,
  persona_id       INT UNSIGNED NULL,
  nombre_completo  VARCHAR(160) NULL,
  parentesco_id    TINYINT UNSIGNED NULL,
  enfermedad       VARCHAR(150) NOT NULL,
  atencion_medica  VARCHAR(100) NULL,
  CONSTRAINT fk_ant_visita FOREIGN KEY (visita_id) REFERENCES visita(id) ON DELETE CASCADE,
  CONSTRAINT fk_ant_persona FOREIGN KEY (persona_id) REFERENCES persona(id),
  CONSTRAINT fk_ant_parentesco FOREIGN KEY (parentesco_id) REFERENCES cat_parentesco(id)
) ENGINE=InnoDB;

CREATE TABLE visita_firma (                       -- separado para que la tabla visita sea ligera
  visita_id  INT UNSIGNED NOT NULL,
  rol        VARCHAR(12) NOT NULL,
  nombre     VARCHAR(160) NULL,
  imagen     MEDIUMBLOB NULL,                     -- PNG de la firma hecha con el dedo
  PRIMARY KEY (visita_id, rol),
  CONSTRAINT ck_firma_rol CHECK (rol IN ('TRABAJADORA','TUTOR')),
  CONSTRAINT fk_firma_visita FOREIGN KEY (visita_id) REFERENCES visita(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. Bitácora de cambios (la llenan los triggers de 05_triggers.sql)
-- ---------------------------------------------------------------------
CREATE TABLE bitacora (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tabla       VARCHAR(40) NOT NULL,
  registro_id VARCHAR(40) NOT NULL,
  accion      CHAR(6) NOT NULL,
  usuario_id  SMALLINT UNSIGNED NULL,            -- @usuario_id que fija la aplicación al conectarse
  fecha       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  antes       JSON NULL,
  despues     JSON NULL,
  KEY ix_bitacora_registro (tabla, registro_id),
  KEY ix_bitacora_fecha (fecha),
  CONSTRAINT ck_bitacora_accion CHECK (accion IN ('INSERT','UPDATE','DELETE'))
) ENGINE=InnoDB;

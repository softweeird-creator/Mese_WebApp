-- =====================================================================
--  06_carga_excel.sql — pasar los Excel actuales a la base (todo en SQL)
--
--  Pasos:
--   1. En Excel, guardar cada hoja como "CSV UTF-8 (delimitado por comas)":
--        10. OCTUBRE.xlsx  → hoja BASE      → base.csv
--        8. BDI AGOSTO.xlsx → hoja B-DATOS  → bdi.csv
--        BASE DE DATOS HISTORICA.xls → hoja DATOS → historica.csv
--   2. Correr este archivo (crea tablas de paso, funciones y equivalencias).
--   3. Cargar los CSV a las tablas de paso (ver ejemplo al final, LOAD DATA).
--   4. CALL sp_carga_todo('2026-09-30');   -- fecha de corte de la BASE
--   5. Revisar  SELECT * FROM carga_pendiente;  (valores que no se pudieron
--      reconocer). Se agregan equivalencias a cat_alias y se vuelve a correr.
--
--  La carga es repetible: sp_carga_todo borra lo cargado antes desde Excel.
-- =====================================================================
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;   -- misma intercalación que la base

-- Formato de fecha con que Excel guardó el CSV (México: día/mes/año)
SET @formato_fecha = COALESCE(@formato_fecha, '%d/%m/%Y');

-- ---------------------------------------------------------------------
-- Tablas de paso: una columna de texto por cada columna de la hoja
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS _crear_stg;
DELIMITER //
CREATE PROCEDURE _crear_stg(IN p_tabla VARCHAR(30), IN p_cols TINYINT)
BEGIN
  DECLARE i TINYINT DEFAULT 1; DECLARE v TEXT DEFAULT '';
  WHILE i <= p_cols DO SET v = CONCAT(v, ', c', LPAD(i, 2, '0'), ' TEXT NULL'); SET i = i + 1; END WHILE;
  SET @s = CONCAT('DROP TABLE IF EXISTS ', p_tabla); PREPARE x FROM @s; EXECUTE x; DEALLOCATE PREPARE x;
  SET @s = CONCAT('CREATE TABLE ', p_tabla, ' (fila INT UNSIGNED AUTO_INCREMENT PRIMARY KEY', v, ') ENGINE=InnoDB');
  PREPARE x FROM @s; EXECUTE x; DEALLOCATE PREPARE x;
END //
DELIMITER ;
CALL _crear_stg('stg_base', 78);
CALL _crear_stg('stg_bdi', 62);
CALL _crear_stg('stg_historica', 26);
DROP PROCEDURE _crear_stg;

-- Relación renglón de Excel → registro creado (para enlazar hojas entre sí)
CREATE TABLE IF NOT EXISTS carga_mapa (   -- se conserva para poder deshacer cargas anteriores
 
  hoja   VARCHAR(12) NOT NULL,
  fila   INT UNSIGNED NOT NULL,
  rol    VARCHAR(12) NOT NULL,          -- PARTICIPANTE, MADRE, PADRE, FAMILIA, VISITA
  id     INT UNSIGNED NOT NULL,
  clave  VARCHAR(200) NULL,             -- nombre normalizado tal como venía en Excel
  PRIMARY KEY (hoja, fila, rol),
  KEY ix_mapa_clave (hoja, rol, clave)
) ENGINE=InnoDB;

-- Valores que no se pudieron reconocer, para revisarlos
CREATE TABLE IF NOT EXISTS carga_pendiente (   -- se conserva para poder deshacer cargas anteriores
 
  id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  hoja     VARCHAR(12) NOT NULL,
  fila     INT UNSIGNED NULL,
  columna  VARCHAR(40) NOT NULL,
  valor    VARCHAR(300) NULL,
  problema VARCHAR(200) NOT NULL
) ENGINE=InnoDB;

-- Qué columna de la hoja BASE alimenta qué pregunta del cuestionario
DROP TABLE IF EXISTS carga_columna;
CREATE TABLE carga_columna (
  hoja         VARCHAR(12) NOT NULL,
  columna      CHAR(3) NOT NULL,         -- c05, c39 ...
  titulo       VARCHAR(60) NOT NULL,     -- encabezado en Excel (para los reportes)
  clave        VARCHAR(20) NOT NULL,     -- cat_pregunta.clave
  opcion_fija  VARCHAR(60) NULL,         -- para columnas SI/NO que equivalen a una opción (AGUA → "Agua")
  PRIMARY KEY (hoja, columna, clave)
) ENGINE=InnoDB;
INSERT INTO carga_columna VALUES
 ('BASE','c05','NIVEL DE POBREZA','nivel_pobreza',NULL), ('BASE','c39','DESPENSA','despensa',NULL),
 ('BASE','c48','DX. NUTRICIONAL','dx_nutricional',NULL), ('BASE','c49','HACINAMIENTO','hacinamiento',NULL),
 ('BASE','c58','TERRENO','terreno',NULL),                ('BASE','c72','SERVICIOS EN LA COLONIA','serv_colonia',NULL),
 ('BASE','c59','CASA','casa',NULL),                      ('BASE','c60','CONSTRUCCION','car',NULL),
 ('BASE','c62','PISO','piso',NULL),                      ('BASE','c63','TECHO','techo',NULL),
 ('BASE','c64','AGUA','serv','Agua'),                    ('BASE','c65','LUZ','serv','Luz'),
 ('BASE','c66','DRENAJE','serv','Drenaje'),              ('BASE','c69','INTERNET','serv','Internet'),
 ('BASE','c70','COMPUTADORA','serv','Computadora'),      ('BASE','c67','COMBUSTIBLE','comb',NULL),
 ('BASE','c68','VEHÍCULO','auto',NULL),                  ('BASE','c71','HUERTO','huerto',NULL),
 ('BASE','c51','DOCUMENTOS FAMILIARES','docs',NULL),     ('BASE','c50','HIGIENE DEL HOGAR','hig',NULL),
 ('BASE','c46','ALIMENTACIÓN','alim',NULL),              ('BASE','c47','COMIDAS AL DÍA','comidas',NULL),
 ('BASE','c41','SERVICIO DE SALUD','med',NULL),          ('BASE','c43','CARTILLA DE VACUNACIÓN','cartilla',NULL),
 ('BASE','c30','METODO ANTICONCEPTIVO','anti_m',NULL),   ('BASE','c30','METODO ANTICONCEPTIVO','anti',NULL),
 ('BASE','c53','ACTIVIDAD COMUNITARIA','com',NULL),      ('BASE','c52','ACTIVIDAD FÍSICA DEL BECADO','fis',NULL),
 ('BASE','c22','TURNO','turno',NULL);

-- ---------------------------------------------------------------------
-- Equivalencias de texto (se comparan sin acentos ni mayúsculas)
-- Valor '-' = ignorar sin reportar (N/A, vacío, etc.)
-- ---------------------------------------------------------------------
DELETE FROM cat_alias;
INSERT INTO cat_alias (dominio, texto, valor) VALUES
 ('opcion:*','N/A','-'),('opcion:*','NA','-'),('opcion:*','NO REGISTRO','-'),('opcion:*','PENDIENTE','-'),('opcion:*','NO APLICA','-'),('opcion:*','SIN DATO','-'),
 ('opcion:dx_nutricional','SANA','Sano'),('opcion:dx_nutricional','SALUDABLE','Sano'),('opcion:dx_nutricional','SANA CON RIESGO','Sano con riesgo'),
 ('opcion:dx_nutricional','NO','-'),
 ('opcion:hacinamiento','NO','Nulo'),
 ('opcion:terreno','PROPIO','Regular'),
 ('opcion:serv_colonia','SI','Completos'),
 ('opcion:car','TRERMINADA','Terminada'),('opcion:car','MATERIAL OBRA NEGRA','Obra negra'),('opcion:car','OBRANEGRA','Obra negra'),
 ('opcion:car','MIXTO','Mixta'),('opcion:car','MADERA','Lámina y madera'),('opcion:car','LAMINA FIERRO','Lámina y madera'),
 ('opcion:car','LAMINA DE CARTON Y MADERA','Lámina y madera'),('opcion:car','LAMINA','Lámina y madera'),('opcion:car','LAMINA DE CARTON','Lámina y madera'),
 ('opcion:piso','CONCRETO','Cemento'),
 ('opcion:techo','LAMINA DE FIERRO','Lámina'),('opcion:techo','TINACO','-'),
 ('opcion:auto','VEHICULO','Propio'),('opcion:auto','SI','Propio'),('opcion:auto','CAMIONETA','Propio'),('opcion:auto','MOTO','Motocicleta'),
 ('opcion:auto','SI MOTO','Motocicleta'),('opcion:auto','VEHICULO PROPIO','Propio'),
 ('opcion:hig','BUENO','Buena'),
 ('opcion:alim','BUENA','Bueno'),('opcion:alim','EQUILIBRADA','Bueno'),
 ('opcion:comidas','5','Cinco o más'),('opcion:comidas','4','Cuatro'),('opcion:comidas','3','Tres'),('opcion:comidas','2','Dos o menos'),
 ('opcion:comidas','1','Dos o menos'),('opcion:comidas','2 O MENOS','Dos o menos'),
 ('opcion:med','IMSS-BIENESTAR','IMSS Bienestar'),('opcion:med','IMMS-BIENESTAR','IMSS Bienestar'),
 ('opcion:cartilla','ENTREGADA','Sí'),('opcion:cartilla','FALTA','No'),('opcion:cartilla','PENDIENTE','No'),
 ('opcion:anti_m','SALPINCOCLASIA','Salpingoclasia'),('opcion:anti_m','NINGUNO','-'),('opcion:anti_m','INYECCION','Inyecciones'),
 ('opcion:anti_m','PERDIDA DE MENARCA','-'),('opcion:anti_m','METODO BILLING','-'),
 ('opcion:anti','NINGUNO','No'),
 ('opcion:com','NINGUNA','No'),('opcion:fis','NINGUNA','No'),
 ('opcion:turno','MAT.','Matutino'),('opcion:turno','VES.','Vespertino'),('opcion:turno','COM.','Tiempo completo'),
 ('estado_civil','CASADOS','Casado(a)'),('estado_civil','CASADA','Casado(a)'),('estado_civil','CASADO','Casado(a)'),('estado_civil','CASADOS IGLESIA','Casado(a)'),
 ('estado_civil','CIVIL','Casado(a)'),('estado_civil','UNION LIBRE','Unión libre'),('estado_civil','UNION LINRE','Unión libre'),
 ('estado_civil','SEPARADOS','Separado(a)'),('estado_civil','SEPARADA','Separado(a)'),('estado_civil','DIVORCIADOS','Divorciado(a)'),
 ('estado_civil','VIUDA','Viudo(a)'),('estado_civil','VIUDO','Viudo(a)'),('estado_civil','MAMA SOLTERA','Soltero(a)'),('estado_civil','SOLTERA','Soltero(a)'),
 ('tipo_sangre','O +','O+'),('tipo_sangre','O -','O-'),('tipo_sangre','A +','A+'),('tipo_sangre','A -','A-'),('tipo_sangre','B +','B+'),
 ('tipo_sangre','B -','B-'),('tipo_sangre','AB +','AB+'),('tipo_sangre','AB -','AB-'),('tipo_sangre','NO LO SABE','No sabe'),('tipo_sangre','NO SABE','No sabe'),
 ('patrocinador','REPSOL','Repsol'),('patrocinador','SORIANA','Soriana'),('patrocinador','BECALOS','Bécalos'),('patrocinador','MESE','MESE'),('patrocinador','GENERAL','General'),
 ('causa_baja','ABANDONO ESTUDIOS','Abandono de estudios'),('causa_baja','ABANDONO ESTUDIOS POR ENFERMEDAD','Enfermedad'),
 ('causa_baja','DESINTERES POR EL APOYO','Desinterés por el apoyo'),('causa_baja','CONCLUYO ESTUDIOS','Concluyó estudios'),
 ('causa_baja','CAMBIO DE RESIDENCIA','Cambio de domicilio'),('causa_baja','CAMBIO DE RECIDENCIA','Cambio de domicilio'),
 ('causa_baja','MEJORO LA SITUACION ECONOMICA','Mejoró la situación económica'),('causa_baja','INASISTENCIA POR DISTANCIA','Inasistencia por distancia'),
 ('causa_baja','FALTA DE TIEMPO Y TUTOR RESPONSABLE','Falta de tiempo y tutor responsable'),('causa_baja','SE CASO','Se casó'),
 ('causa_baja','EDUCACION ESPECIAL','Educación especial'),('causa_baja','DESERCION ESCOLAR/VIDA LABORAL','Abandono de estudios'),
 ('causa_baja','ABANDONO ESTUDIOS/DESINTERES POR EL APOYO','Abandono de estudios'),('causa_baja','DESINTERES POR EL APOYO Y ABANDONO ESTUDIOS','Desinterés por el apoyo'),
 ('causa_baja','DESINTERES POR EL APOYO Y CAMBIO DE DOMICILIO AL NORTE DE LA CIUDAD.','Desinterés por el apoyo'),('causa_baja','DESINTERES POR EL APOYO/ EDUCACION ESPECIAL','Desinterés por el apoyo'),
 ('causa_baja','FALTA DE APOYO DEL TUTOR','Falta de tiempo y tutor responsable'),('causa_baja','REPROBO EL CICLO ESCOLAR','Abandono de estudios'),
 ('causa_baja','CAMBIO DE BECA','Otro'),('causa_baja','CASO ESPECIAL','Otro'),('causa_baja','NO REGISTRO','Sin registro'),('causa_baja','CONTINUA ESTUDIANDO','Otro'),
 ('causa_estadistica','CONTINUA ESTUDIANDO','Continúa estudiando'),('causa_estadistica','DESERCION ESCOLAR/VIDA LABORAL','Deserción escolar / vida laboral'),
 ('causa_estadistica','VIDA LABORAL','Deserción escolar / vida laboral'),('causa_estadistica','EGRESO INSTITUCIONAL','Egreso institucional'),
 ('causa_estadistica','EMBARAZO','Embarazo'),('causa_estadistica','UNION LIBRE','Unión libre'),('causa_estadistica','FINADO','Finado'),
 ('causa_estadistica','CAMBIO DE RESIDENCIA','Cambio de residencia'),('causa_estadistica','NO REGISTRO','Sin registro'),('causa_estadistica','N/A','-');

DROP FUNCTION IF EXISTS fn_norm;
DROP FUNCTION IF EXISTS fn_clave;
DROP FUNCTION IF EXISTS fn_titulo;
DROP FUNCTION IF EXISTS fn_nombre_parte;
DROP FUNCTION IF EXISTS fn_fecha;
DROP FUNCTION IF EXISTS fn_tel;
DROP FUNCTION IF EXISTS fn_nivel;
DROP FUNCTION IF EXISTS fn_grado;
DROP FUNCTION IF EXISTS fn_alias;
DROP FUNCTION IF EXISTS fn_curp;
DROP PROCEDURE IF EXISTS _mapear_respuestas;
DROP PROCEDURE IF EXISTS sp_carga_limpiar;
DROP PROCEDURE IF EXISTS sp_carga_base;
DROP PROCEDURE IF EXISTS sp_carga_bdi;
DROP PROCEDURE IF EXISTS sp_carga_historica;
DROP PROCEDURE IF EXISTS sp_carga_todo;

DELIMITER //
-- Mayúsculas, sin espacios dobles
CREATE FUNCTION fn_norm(p TEXT) RETURNS VARCHAR(300) DETERMINISTIC NO SQL
RETURN NULLIF(UPPER(TRIM(REGEXP_REPLACE(COALESCE(p, ''), '[[:space:]]+', ' '))), '') //

-- Igual que fn_norm pero sin acentos (para comparar con patrones REGEXP)
CREATE FUNCTION fn_clave(p TEXT) RETURNS VARCHAR(300) DETERMINISTIC NO SQL
RETURN REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(fn_norm(p),
  'Á','A'),'É','E'),'Í','I'),'Ó','O'),'Ú','U'),'Ü','U'),'À','A'),'Ò','O') //

-- "PEREZ DE LA CRUZ ANA SOFIA" → "Perez de la Cruz Ana Sofia" (de, del, la... en minúscula)
CREATE FUNCTION fn_titulo(p TEXT) RETURNS VARCHAR(300) DETERMINISTIC NO SQL
BEGIN
  DECLARE r VARCHAR(300) DEFAULT ''; DECLARE w VARCHAR(100); DECLARE s VARCHAR(300) DEFAULT LOWER(fn_norm(p));
  IF s IS NULL THEN RETURN NULL; END IF;
  WHILE s <> '' DO
    SET w = SUBSTRING_INDEX(s, ' ', 1);
    SET s = IF(LOCATE(' ', s) > 0, SUBSTRING(s, LOCATE(' ', s) + 1), '');
    SET r = CONCAT(r, IF(r = '', '', ' '),
                   IF(r <> '' AND w IN ('de','del','la','las','los','y','e','van','von'), w, CONCAT(UPPER(LEFT(w, 1)), SUBSTRING(w, 2))));
  END WHILE;
  RETURN r;
END //

-- Parte de un nombre escrito "APELLIDO_P APELLIDO_M NOMBRES" (P, M o N).
-- Junta partículas: "DE LA CRUZ", "DEL RÍO", "SAN JUAN".
CREATE FUNCTION fn_nombre_parte(p TEXT, parte CHAR(1)) RETURNS VARCHAR(120) DETERMINISTIC NO SQL
BEGIN
  DECLARE s VARCHAR(300) DEFAULT fn_norm(REPLACE(p, ',', ' ')); DECLARE w VARCHAR(100); DECLARE buf VARCHAR(200) DEFAULT '';
  DECLARE palabras VARCHAR(400) DEFAULT ''; DECLARE n TINYINT DEFAULT 0;
  IF s IS NULL THEN RETURN NULL; END IF;
  WHILE s <> '' DO
    SET w = SUBSTRING_INDEX(s, ' ', 1);
    SET s = IF(LOCATE(' ', s) > 0, SUBSTRING(s, LOCATE(' ', s) + 1), '');
    IF w IN ('DE','DEL','LA','LAS','LOS','SAN','SANTA','MC','VAN','VON') AND s <> '' THEN
      SET buf = CONCAT(buf, w, ' ');
    ELSE
      SET palabras = CONCAT(palabras, IF(n = 0, '', '|'), buf, w); SET buf = ''; SET n = n + 1;
    END IF;
  END WHILE;
  IF n = 1 THEN RETURN IF(parte = 'N', fn_titulo(palabras), NULL); END IF;
  IF n = 2 THEN RETURN fn_titulo(CASE parte WHEN 'P' THEN SUBSTRING_INDEX(palabras, '|', 1) WHEN 'N' THEN SUBSTRING_INDEX(palabras, '|', -1) END); END IF;
  RETURN fn_titulo(CASE parte
    WHEN 'P' THEN SUBSTRING_INDEX(palabras, '|', 1)
    WHEN 'M' THEN SUBSTRING_INDEX(SUBSTRING_INDEX(palabras, '|', 2), '|', -1)
    ELSE REPLACE(SUBSTRING(palabras, LENGTH(SUBSTRING_INDEX(palabras, '|', 2)) + 2), '|', ' ') END);
END //

-- Fecha de un CSV de Excel: según @formato_fecha, o AAAA-MM-DD, o número de serie de Excel
CREATE FUNCTION fn_fecha(p TEXT) RETURNS DATE DETERMINISTIC NO SQL
BEGIN
  DECLARE s VARCHAR(40) DEFAULT TRIM(COALESCE(p, '')); DECLARE d DATE;
  IF s REGEXP '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}' THEN SET d = STR_TO_DATE(LEFT(s, 10), '%Y-%m-%d');
  ELSEIF s REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' THEN SET d = STR_TO_DATE(s, COALESCE(@formato_fecha, '%d/%m/%Y'));
  ELSEIF s REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$' THEN SET d = STR_TO_DATE(s, REPLACE(COALESCE(@formato_fecha, '%d/%m/%Y'), '%Y', '%y'));
  ELSEIF s REGEXP '^[0-9]{4,5}$' THEN SET d = DATE_ADD('1899-12-30', INTERVAL CAST(s AS UNSIGNED) DAY);
  END IF;
  RETURN IF(YEAR(d) BETWEEN 1900 AND 2100, d, NULL);
END //

-- Teléfono: solo dígitos; si hay dos números juntos se toma el primero
CREATE FUNCTION fn_tel(p TEXT) RETURNS VARCHAR(15) DETERMINISTIC NO SQL
BEGIN
  DECLARE s VARCHAR(60) DEFAULT REGEXP_REPLACE(COALESCE(p, ''), '[^0-9]', '');
  RETURN IF(LENGTH(s) >= 10, LEFT(s, 10), NULL);
END //

CREATE FUNCTION fn_curp(p TEXT) RETURNS CHAR(18) DETERMINISTIC NO SQL
BEGIN
  DECLARE s VARCHAR(40) DEFAULT UPPER(TRIM(COALESCE(p, '')));
  RETURN IF(s REGEXP '^[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[0-9A-Z][0-9]$', s, NULL);
END //

-- Nivel escolar a partir de "PRIM. 5° AÑO", "SECUNDARIA 3", "PREPA 1", "CPTM", "OFICIO CONCLUIDO"...
CREATE FUNCTION fn_nivel(p TEXT) RETURNS VARCHAR(10) DETERMINISTIC NO SQL
BEGIN
  DECLARE s VARCHAR(300) DEFAULT fn_clave(p);
  RETURN CASE
    WHEN s IS NULL THEN NULL
    WHEN s REGEXP '^(PRE ?ESC|PRESC|KINDER|JARDIN)' THEN 'PREESC'
    WHEN s REGEXP '^PRIM' THEN 'PRIM'
    WHEN s REGEXP '^SEC.*ABIERTA|^SECA' THEN 'SECA'
    WHEN s REGEXP '^(SEC|TELESEC)' THEN 'SEC'
    WHEN s REGEXP '^PREP.*ABIERTA' THEN 'PREPAA'
    WHEN s REGEXP '^(PREP|PRPA|BACH|CBT|CETIS|COBAEM|CECYTE|EMSAD|TELEBACH)' THEN 'PREPA'
    WHEN s REGEXP '^(TEC|CARRERA TEC|CPTM|CONALEP|CAR\\.? TEC|AUX)' THEN 'TEC'
    WHEN s REGEXP '^(OFICIO|CECATI|ICATMI)' THEN 'OFICIO'
    WHEN s REGEXP '^(LIC|UNIV|ING)' THEN 'LIC'
    WHEN s REGEXP '^INEA' THEN 'INEA'
    WHEN s REGEXP '^(ESP|EDUCACION ESP|CAM)' THEN 'ESP'
  END;
END //

CREATE FUNCTION fn_grado(p TEXT) RETURNS TINYINT DETERMINISTIC NO SQL
BEGIN
  DECLARE s VARCHAR(10) DEFAULT REGEXP_SUBSTR(COALESCE(p, ''), '[1-6]');
  RETURN IF(s = '', NULL, CAST(s AS UNSIGNED));
END //

-- Valor de catálogo para un texto de Excel usando cat_alias (o el texto mismo)
CREATE FUNCTION fn_alias(p_dominio VARCHAR(30), p TEXT) RETURNS VARCHAR(150) DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE s VARCHAR(300) DEFAULT fn_norm(p);
  IF s IS NULL THEN RETURN NULL; END IF;
  RETURN COALESCE((SELECT valor FROM cat_alias WHERE dominio = p_dominio AND texto = s LIMIT 1), s);
END //

-- Pasa las columnas de opción de una hoja a visita_respuesta (usa carga_columna y cat_alias).
-- Separa valores combinados: "CEMENTO/TIERRA", "IMSS, SIMI", "CONCRETO Y LAMINA".
CREATE PROCEDURE _mapear_respuestas(IN p_hoja VARCHAR(12), IN p_tabla VARCHAR(30))
BEGIN
  DECLARE v_col CHAR(3); DECLARE v_clave VARCHAR(20); DECLARE v_fija VARCHAR(60); DECLARE v_tipo VARCHAR(8); DECLARE v_tit VARCHAR(60);
  DECLARE v_fin BOOLEAN DEFAULT FALSE;
  DECLARE cur CURSOR FOR SELECT c.columna, c.clave, c.opcion_fija, q.tipo, c.titulo FROM carga_columna c JOIN cat_pregunta q ON q.clave = c.clave WHERE c.hoja = p_hoja;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = TRUE;

  DROP TEMPORARY TABLE IF EXISTS t_tok;
  CREATE TEMPORARY TABLE t_tok (visita_id INT UNSIGNED, fila INT UNSIGNED, n TINYINT, tok VARCHAR(150)) ;
  OPEN cur;
  ciclo: LOOP
    FETCH cur INTO v_col, v_clave, v_fija, v_tipo, v_tit;
    IF v_fin THEN LEAVE ciclo; END IF;
    TRUNCATE t_tok;
    -- Separa el texto en partes (JSON_TABLE convierte la lista en renglones)
    SET @s = CONCAT(
      'INSERT INTO t_tok SELECT m.id, s.fila, j.n, TRIM(j.tok) FROM ', p_tabla, ' s ',
      'JOIN carga_mapa m ON m.hoja = ? AND m.fila = s.fila AND m.rol = ''VISITA'' ',
      'JOIN JSON_TABLE(CONCAT(''["'', REGEXP_REPLACE(REPLACE(REPLACE(REPLACE(fn_norm(s.', v_col, '), ''N/A'', ''NA''), ''\\\\'', ''''), ''"'', ''''), ',
      IF(v_fija IS NULL, '''[[:space:]]*(/|,|;| Y | E )[[:space:]]*''', '''^$'''),
      ', ''","''), ''"]''), ''$[*]'' COLUMNS (n FOR ORDINALITY, tok VARCHAR(150) PATH ''$'')) j ',
      'WHERE fn_norm(s.', v_col, ') IS NOT NULL');
    SET @h = p_hoja;
    PREPARE st_mapear FROM @s; EXECUTE st_mapear USING @h; DEALLOCATE PREPARE st_mapear;

    IF v_fija IS NOT NULL THEN
      -- Columna SI/NO: "SI", "PIPA", "PROVISIONAL" o "PASAN" cuentan como que sí tienen el servicio
      INSERT IGNORE INTO visita_respuesta (visita_id, pregunta_id, opcion_id)
      SELECT t.visita_id, o.pregunta_id, o.id FROM t_tok t
      JOIN cat_pregunta q ON q.clave = v_clave JOIN cat_opcion o ON o.pregunta_id = q.id AND o.etiqueta = v_fija
      WHERE t.tok IN ('SI', 'SI TIENE', 'PIPA', 'PROVISIONAL', 'PASAN')
        AND NOT EXISTS (SELECT 1 FROM visita_respuesta r WHERE r.visita_id = t.visita_id AND r.opcion_id = o.id);
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema)
      SELECT p_hoja, t.fila, v_tit, t.tok, 'Se esperaba SI o NO' FROM t_tok t WHERE t.tok NOT IN ('SI','SI TIENE','PIPA','PROVISIONAL','PASAN','NO','NO TIENE','N/A','NA');
    ELSE
      -- Cada parte se busca como opción, primero con su equivalencia
      INSERT INTO visita_respuesta (visita_id, pregunta_id, opcion_id)
      SELECT x.visita_id, x.pregunta_id, x.opcion_id FROM (
        SELECT t.visita_id, o.pregunta_id, o.id AS opcion_id, ROW_NUMBER() OVER (PARTITION BY t.visita_id ORDER BY t.n) AS rn,
               ROW_NUMBER() OVER (PARTITION BY t.visita_id, o.id ORDER BY t.n) AS rep
        FROM t_tok t
        JOIN cat_pregunta q ON q.clave = v_clave
        LEFT JOIN cat_alias a  ON a.dominio = CONCAT('opcion:', v_clave) AND a.texto = t.tok
        LEFT JOIN cat_alias a2 ON a2.dominio = 'opcion:*' AND a2.texto = t.tok
        JOIN cat_opcion o ON o.pregunta_id = q.id
         AND o.etiqueta = CASE WHEN v_clave IN ('anti', 'com', 'fis') AND COALESCE(a.valor, t.tok) NOT IN ('No', 'NO', '-')
                               THEN 'Sí' ELSE COALESCE(a.valor, t.tok) END
        WHERE COALESCE(a.valor, a2.valor, '') <> '-'
      ) x
      WHERE x.rep = 1 AND (v_tipo = 'MULTIPLE' OR x.rn = 1)
        AND NOT EXISTS (SELECT 1 FROM visita_respuesta r WHERE r.visita_id = x.visita_id AND r.pregunta_id = x.pregunta_id AND (v_tipo = 'UNICA' OR r.opcion_id = x.opcion_id));
      -- Lo que no se reconoció queda para revisión
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema)
      SELECT p_hoja, t.fila, v_tit, t.tok, CONCAT('No coincide con ninguna opción de "', v_clave, '"')
      FROM t_tok t
      JOIN cat_pregunta q ON q.clave = v_clave
      LEFT JOIN cat_alias a  ON a.dominio = CONCAT('opcion:', v_clave) AND a.texto = t.tok
      LEFT JOIN cat_alias a2 ON a2.dominio = 'opcion:*' AND a2.texto = t.tok
      WHERE COALESCE(a.valor, a2.valor, '') <> '-'
        AND v_clave NOT IN ('anti', 'com', 'fis')
        AND NOT EXISTS (SELECT 1 FROM cat_opcion o WHERE o.pregunta_id = q.id AND o.etiqueta = COALESCE(a.valor, t.tok));
    END IF;
  END LOOP;
  CLOSE cur;
  DROP TEMPORARY TABLE IF EXISTS t_tok;
END //

-- Borra lo que se haya cargado antes desde Excel (para poder repetir la carga)
CREATE PROCEDURE sp_carga_limpiar()
BEGIN
  SET @importando = 1;
  DELETE FROM visita WHERE origen = 'EXCEL';
  DELETE FROM participante_beca WHERE participante_id IN (SELECT id FROM carga_mapa WHERE rol = 'PARTICIPANTE');
  DELETE FROM participante_escolaridad WHERE participante_id IN (SELECT id FROM carga_mapa WHERE rol = 'PARTICIPANTE');
  DELETE FROM inscripcion WHERE participante_id IN (SELECT id FROM carga_mapa WHERE rol = 'PARTICIPANTE');
  DELETE FROM participante WHERE persona_id IN (SELECT id FROM carga_mapa WHERE rol = 'PARTICIPANTE');
  DELETE FROM familia_integrante WHERE familia_id IN (SELECT id FROM carga_mapa WHERE rol = 'FAMILIA');
  DELETE FROM persona WHERE id IN (SELECT id FROM carga_mapa WHERE rol IN ('PARTICIPANTE', 'MADRE', 'PADRE', 'INDIRECTO'));
  DELETE FROM familia WHERE id IN (SELECT id FROM carga_mapa WHERE rol = 'FAMILIA');
  TRUNCATE carga_mapa; TRUNCATE carga_pendiente;
  SET @importando = 0;
END //

-- ---------------------------------------------------------------------
-- Hoja BASE (participantes activos, sus tutores y su estudio socioeconómico)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_carga_base(IN p_fecha_corte DATE)
BEGIN
  DECLARE v_fin BOOLEAN DEFAULT FALSE;
  DECLARE v_fila INT UNSIGNED; DECLARE v_nombre, v_madre, v_padre, v_dom, v_col, v_clave_fam, v_clave_dom VARCHAR(300);
  DECLARE v_fam, v_per, v_tut, v_vis INT UNSIGNED; DECLARE v_nivel VARCHAR(10); DECLARE v_grado TINYINT;
  DECLARE r_becado, r_nac, r_ing, r_grupobeca, r_beca, r_gen, r_sangre, r_curp, r_esc, r_gradotxt, r_carrera, r_grupo, r_turno,
          r_ocm, r_escm, r_ocp, r_escp, r_civil, r_integr, r_apoyo, r_monto, r_ingreso, r_enf, r_adic, r_viol, r_activ_com, r_activ_fis,
          r_activ_prod, r_neces, r_cp, r_telm, r_telp, r_telpart, r_telfam, r_correo, r_aviso, r_sabana, r_ts, r_liconsa, r_covid TEXT;
  DECLARE cur CURSOR FOR
    SELECT fila, c02, c23, c26, c55, c56, c04, c07, c09, c13, c14, c15, c16, c17, c18, c19, c20, c21, c22, c24, c25, c27, c28, c29,
           c32, c34, c35, c36, c42, c45, c33, c53, c52, c54, c61, c57, c73, c74, c75, c76, c77, c78, c03, c08, c40, c44
    FROM stg_base WHERE fn_norm(c02) IS NOT NULL AND fn_norm(c02) NOT LIKE 'NOMBRE%' ORDER BY fila;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = TRUE;

  SET @importando = 1;
  OPEN cur;
  leer: LOOP
    FETCH cur INTO v_fila, v_nombre, v_madre, v_padre, v_dom, v_col, r_becado, r_nac, r_ing, r_grupobeca, r_beca, r_gen, r_sangre, r_curp,
      r_esc, r_gradotxt, r_carrera, r_grupo, r_turno, r_ocm, r_escm, r_ocp, r_escp, r_civil, r_integr, r_apoyo, r_monto, r_ingreso,
      r_enf, r_adic, r_viol, r_activ_com, r_activ_fis, r_activ_prod, r_neces, r_cp, r_telm, r_telp, r_telpart, r_telfam, r_correo, r_aviso, r_sabana, r_ts, r_liconsa, r_covid;
    IF v_fin THEN LEAVE leer; END IF;

    -- Familia: los hermanos comparten madre (o padre, o domicilio)
    SET v_clave_fam = COALESCE(IF(fn_norm(v_madre) IN ('AUSENTE', 'NO TIENE'), NULL, fn_norm(v_madre)),
                               IF(fn_norm(v_padre) IN ('AUSENTE', 'NO TIENE'), NULL, fn_norm(v_padre)),
                               CONCAT(fn_norm(v_dom), '|', fn_norm(v_col)));
    SET v_fam = (SELECT id FROM carga_mapa WHERE hoja = 'BASE' AND rol = 'FAMILIA' AND clave = v_clave_fam LIMIT 1);
    -- Segunda regla: mismo domicilio y mismo apellido paterno = hermanos, aunque el nombre de la
    -- madre esté escrito distinto ("Z" por "S", una letra de más...)
    SET v_clave_dom = CONCAT('DOM|', fn_clave(v_dom), '|', fn_clave(v_col), '|', fn_clave(fn_nombre_parte(v_nombre, 'P')));
    IF v_fam IS NULL AND fn_norm(v_dom) IS NOT NULL THEN
      SET v_fam = (SELECT id FROM carga_mapa WHERE hoja = 'BASE' AND rol = 'FAMDOM' AND clave = v_clave_dom LIMIT 1);
      IF v_fam IS NOT NULL THEN
        INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema)
        VALUES ('BASE', v_fila, 'NOMBRE DE LA MADRE O TUTOR', v_madre, 'Mismo domicilio y apellido que otro becado pero la madre está escrita distinto; se unieron como hermanos');
      END IF;
    END IF;
    IF v_fam IS NULL THEN
      INSERT INTO familia (calle, colonia_id, telefono, correo, aviso_privacidad)
      VALUES (fn_titulo(v_dom), fn_colonia(fn_titulo(v_col), REGEXP_SUBSTR(r_cp, '[0-9]{5}')),
              fn_tel(r_telfam), IF(fn_norm(r_correo) LIKE '%@%', LOWER(TRIM(r_correo)), NULL),
              IF(fn_norm(r_aviso) IN ('FIRMADO', 'SI'), p_fecha_corte, NULL));
      SET v_fam = LAST_INSERT_ID();
      INSERT INTO carga_mapa VALUES ('BASE', v_fila, 'FAMILIA', v_fam, v_clave_fam);
      INSERT INTO carga_mapa VALUES ('BASE', v_fila, 'FAMDOM', v_fam, v_clave_dom);

      -- Madre y padre (o tutores)
      IF fn_norm(v_madre) IS NOT NULL AND fn_norm(v_madre) NOT IN ('AUSENTE', 'NO TIENE', 'PENDIENTE') THEN
        INSERT INTO persona (nombres, apellido_paterno, apellido_materno, genero, telefono, ocupacion_id, estado_civil_id, escolaridad_nivel_id, escolaridad_nota)
        -- los nombres de los tutores vienen como "NOMBRES APELLIDO_P APELLIDO_M": se guardan completos en "nombres"
        VALUES (fn_titulo(v_madre), NULL, NULL, 'F', fn_tel(r_telm), fn_ocupacion(fn_titulo(r_ocm)),
                (SELECT id FROM cat_estado_civil WHERE nombre = fn_alias('estado_civil', r_civil)),
                (SELECT id FROM cat_nivel_educativo WHERE clave = fn_nivel(r_escm)), fn_texto(r_escm));
        SET v_tut = LAST_INSERT_ID();
        INSERT INTO familia_integrante (familia_id, persona_id, parentesco_id, es_tutor) SELECT v_fam, v_tut, id, TRUE FROM cat_parentesco WHERE nombre = 'Madre';
        INSERT INTO carga_mapa VALUES ('BASE', v_fila, 'MADRE', v_tut, fn_norm(v_madre));
      END IF;
      IF fn_norm(v_padre) IS NOT NULL AND fn_norm(v_padre) NOT IN ('AUSENTE', 'NO TIENE', 'PENDIENTE') AND fn_norm(r_ocp) <> 'AUSENTE' THEN
        INSERT INTO persona (nombres, genero, telefono, ocupacion_id, estado_civil_id, escolaridad_nivel_id, escolaridad_nota)
        VALUES (fn_titulo(v_padre), 'M', fn_tel(r_telp), fn_ocupacion(fn_titulo(r_ocp)),
                (SELECT id FROM cat_estado_civil WHERE nombre = fn_alias('estado_civil', r_civil)),
                (SELECT id FROM cat_nivel_educativo WHERE clave = fn_nivel(r_escp)), fn_texto(r_escp));
        SET v_tut = LAST_INSERT_ID();
        INSERT INTO familia_integrante (familia_id, persona_id, parentesco_id, es_tutor) SELECT v_fam, v_tut, id, TRUE FROM cat_parentesco WHERE nombre = 'Padre';
        INSERT INTO carga_mapa VALUES ('BASE', v_fila, 'PADRE', v_tut, fn_norm(v_padre));
      END IF;

      -- Estudio socioeconómico de la familia (una visita con fecha de corte, origen EXCEL)
      INSERT INTO visita (familia_id, fecha, estado, origen, usuario_id, num_integrantes, actividad_comunitaria, actividad_fisica,
                          actividad_productiva, necesidad_material, notas)
      VALUES (v_fam, p_fecha_corte, 'COMPLETA', 'EXCEL', 1, fn_num(r_integr),
              IF(fn_norm(r_activ_com) IN ('NINGUNA', 'N/A'), NULL, fn_titulo(r_activ_com)),
              IF(fn_norm(r_activ_fis) IN ('NINGUNA', 'N/A'), NULL, fn_titulo(r_activ_fis)),
              IF(fn_norm(r_activ_prod) IN ('NINGUNA', 'N/A'), NULL, fn_titulo(r_activ_prod)),
              IF(fn_norm(r_neces) IN ('NINGUNA', 'N/A'), NULL, fn_titulo(r_neces)),
              NULLIF(CONCAT_WS(' · ',
                IF(fn_norm(r_viol) IN ('N/A', 'NINGUNA', 'NO'), NULL, CONCAT('Violencia intrafamiliar: ', fn_texto(r_viol))),
                IF(fn_norm(r_adic) IN ('NINGUNA', 'N/A', 'NO'), NULL, CONCAT('Adicciones: ', fn_texto(r_adic))),
                IF(fn_texto(r_sabana) IS NULL, NULL, CONCAT('Sábana: ', fn_texto(r_sabana)))), ''));
      SET v_vis = LAST_INSERT_ID();
      INSERT INTO carga_mapa VALUES ('BASE', v_fila, 'VISITA', v_vis, NULL);
      IF fn_num(r_ingreso) > 0 THEN
        INSERT INTO visita_monto (visita_id, concepto_id, monto) SELECT v_vis, id, fn_num(r_ingreso) FROM cat_concepto_monto WHERE clave = 'ing_fam';
      END IF;
      IF fn_num(r_monto) > 0 THEN
        INSERT INTO visita_monto (visita_id, concepto_id, monto, detalle)
        SELECT v_vis, id, fn_num(r_monto), IF(clave = 'ap_ot', fn_titulo(r_apoyo), NULL) FROM cat_concepto_monto
        WHERE clave = CASE WHEN fn_norm(r_apoyo) REGEXP 'BENITO|RITA' THEN 'ap_bj' WHEN fn_norm(r_apoyo) REGEXP '60|ADULTO' THEN 'ap_am'
                           WHEN fn_norm(r_apoyo) REGEXP 'DISCAPACIDAD' THEN 'ap_dis' ELSE 'ap_ot' END;
      END IF;
      -- Liconsa: el Excel solo dice si recibe (SI / NO TIENE), sin monto
      IF fn_clave(r_liconsa) REGEXP '^SI' THEN
        INSERT IGNORE INTO visita_monto (visita_id, concepto_id, monto, detalle)
        SELECT v_vis, id, 0, 'Recibe (monto no registrado en Excel)' FROM cat_concepto_monto WHERE clave = 'ap_lic';
      END IF;
      -- Vacunas COVID del participante: "COMPLETAS", "2 DOSIS", "INCOMPLETAS", "NINGUNA"...
      IF fn_clave(r_covid) IS NOT NULL AND fn_clave(r_covid) NOT IN ('N/A', 'PENDIENTE') THEN
        INSERT IGNORE INTO visita_vacuna (visita_id, vacuna_id, rol, aplicada, dosis)
        SELECT v_vis, id, 'PARTICIPANTE', NOT (fn_clave(r_covid) REGEXP '^(NINGUNA|NO)'),
               IF(fn_clave(r_covid) REGEXP '^(NINGUNA|NO)', NULL, LEAST(10, CAST(NULLIF(REGEXP_SUBSTR(r_covid, '[0-9]+'), '') AS UNSIGNED)))
        FROM cat_vacuna WHERE nombre = 'COVID-19';
      END IF;
      IF fn_norm(r_enf) IS NOT NULL AND fn_norm(r_enf) NOT IN ('NINGUNA', 'N/A', 'NO') THEN
        INSERT INTO visita_antecedente (visita_id, enfermedad) VALUES (v_vis, LEFT(fn_texto(r_enf), 150));
      END IF;
    ELSE
      -- hermano de alguien ya cargado: la visita de su familia ya existe
      INSERT INTO carga_mapa SELECT 'BASE', v_fila, 'VISITA', id, NULL FROM carga_mapa WHERE hoja = 'BASE' AND rol = 'VISITA'
        AND fila = (SELECT fila FROM carga_mapa WHERE hoja = 'BASE' AND rol = 'FAMILIA' AND id = v_fam LIMIT 1);
      IF fn_tel(r_telfam) IS NOT NULL THEN UPDATE familia SET telefono = COALESCE(telefono, fn_tel(r_telfam)) WHERE id = v_fam; END IF;
    END IF;

    -- Participante
    IF fn_texto(r_curp) IS NOT NULL AND fn_curp(r_curp) IS NULL THEN
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('BASE', v_fila, 'CURP', r_curp, 'CURP con formato inválido; no se guardó');
    END IF;
    IF fn_curp(r_curp) IS NOT NULL AND EXISTS (SELECT 1 FROM persona WHERE curp = fn_curp(r_curp)) THEN
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('BASE', v_fila, 'CURP', r_curp, 'CURP repetida; no se guardó en el segundo registro');
      SET r_curp = NULL;
    END IF;
    INSERT INTO persona (nombres, apellido_paterno, apellido_materno, fecha_nacimiento, genero, curp, tipo_sangre_id, telefono)
    VALUES (COALESCE(fn_nombre_parte(v_nombre, 'N'), fn_titulo(v_nombre)), fn_nombre_parte(v_nombre, 'P'), fn_nombre_parte(v_nombre, 'M'),
            fn_fecha(r_nac), IF(fn_norm(r_gen) IN ('F', 'M'), fn_norm(r_gen), NULL), fn_curp(r_curp),
            (SELECT id FROM cat_tipo_sangre WHERE nombre = fn_alias('tipo_sangre', r_sangre)), fn_tel(r_telpart));
    SET v_per = LAST_INSERT_ID();
    INSERT INTO carga_mapa VALUES ('BASE', v_fila, 'PARTICIPANTE', v_per, fn_norm(v_nombre));
    INSERT INTO participante (persona_id, familia_id, numero_becado, grupo_beca, trabajadora_id)
    VALUES (v_per, v_fam, fn_num(r_becado), IF(fn_num(r_grupobeca) BETWEEN 1 AND 9, fn_num(r_grupobeca), NULL),
            IF(fn_norm(r_ts) IN ('N/A', 'PENDIENTE', 'NO TIENE'), NULL, fn_usuario(fn_titulo(r_ts))));
    IF fn_fecha(r_ing) IS NULL THEN
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('BASE', v_fila, 'INGRESO A MESE', r_ing, 'Sin fecha de ingreso; se usó la fecha de corte');
    END IF;
    INSERT INTO inscripcion (participante_id, fecha_ingreso) VALUES (v_per, LEAST(COALESCE(fn_fecha(r_ing), p_fecha_corte), CURDATE()));

    SET v_nivel = fn_nivel(r_gradotxt), v_grado = fn_grado(r_gradotxt);
    IF v_nivel IS NOT NULL AND EXISTS (SELECT 1 FROM cat_nivel_grado ng JOIN cat_nivel_educativo ne ON ne.id = ng.nivel_id WHERE ne.clave = v_nivel AND ng.grado = v_grado) THEN
      IF fn_texto(r_esc) IS NOT NULL THEN INSERT IGNORE INTO cat_escuela (nombre) VALUES (fn_texto(r_esc)); END IF;
      IF fn_texto(r_carrera) IS NOT NULL AND fn_norm(r_carrera) <> 'EDUCACION BASICA' THEN INSERT IGNORE INTO cat_carrera (nombre) VALUES (fn_titulo(r_carrera)); END IF;
      INSERT INTO participante_escolaridad (participante_id, ciclo_id, escuela_id, nivel_id, grado, carrera_id, grupo, turno_id)
      VALUES (v_per, fn_ciclo(p_fecha_corte), (SELECT id FROM cat_escuela WHERE nombre = fn_texto(r_esc)),
              (SELECT id FROM cat_nivel_educativo WHERE clave = v_nivel), v_grado,
              (SELECT id FROM cat_carrera WHERE nombre = fn_titulo(r_carrera)),
              IF(fn_norm(r_grupo) = 'PENDIENTE', NULL, LEFT(fn_norm(r_grupo), 12)),
              (SELECT id FROM cat_turno WHERE nombre = fn_alias('opcion:turno', r_turno)));
    ELSE
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('BASE', v_fila, 'GRADO', r_gradotxt, 'No se reconoció el nivel y grado escolar');
    END IF;

    -- Becas: "REPSOL/BÉCALOS" son dos
    INSERT IGNORE INTO participante_beca (participante_id, patrocinador_id, desde)
    SELECT v_per, cp.id, COALESCE(fn_fecha(r_ing), p_fecha_corte)
    FROM JSON_TABLE(CONCAT('["', REPLACE(REPLACE(COALESCE(fn_norm(r_beca), ''), '"', ''), '/', '","'), '"]'), '$[*]' COLUMNS (b VARCHAR(60) PATH '$')) j
    JOIN cat_patrocinador cp ON cp.nombre = fn_alias('patrocinador', j.b);
  END LOOP;
  CLOSE cur;

  CALL _mapear_respuestas('BASE', 'stg_base');
  SET @importando = 0;
END //

-- ---------------------------------------------------------------------
-- Hoja B-DATOS (BDI): edad y fecha de nacimiento de los familiares.
-- MAMÁ y PAPÁ completan a los tutores; los demás son participantes indirectos.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_carga_bdi()
BEGIN
  DECLARE i TINYINT DEFAULT 3;
  DECLARE v_titulo VARCHAR(30);
  SET @importando = 1;
  -- Columnas en parejas (nombre del pariente → edad, fecha) a partir de la columna 3
  DROP TEMPORARY TABLE IF EXISTS t_rel;
  CREATE TEMPORARY TABLE t_rel (fila INT UNSIGNED, participante_id INT UNSIGNED, familia_id INT UNSIGNED, col TINYINT, parentesco VARCHAR(30),
                                edad TEXT, nacimiento TEXT);
  WHILE i <= 61 DO
    SET v_titulo = ELT((i - 1) DIV 2, 'Madre','Padre','Hermano','Hermano','Hermano','Hermano','Hermana','Hermana','Hermana','Hermana',
                       'Sobrino','Sobrino','Sobrina','Sobrina','Tío','Tío','Tío','Tía','Tía','Tía','Cuñado','Cuñado','Cuñada','Cuñada',
                       'Primo','Primo','Prima','Abuelo','Bisabuela','Abuela');
    SET @s = CONCAT('INSERT INTO t_rel SELECT s.fila, m.id, p.familia_id, ', i, ', ?, s.c', LPAD(i, 2, '0'), ', s.c', LPAD(i + 1, 2, '0'),
                    ' FROM stg_bdi s JOIN carga_mapa m ON m.hoja = ''BASE'' AND m.rol = ''PARTICIPANTE'' AND m.clave = fn_norm(s.c02)',
                    ' JOIN participante p ON p.persona_id = m.id',
                    ' WHERE fn_num(s.c', LPAD(i, 2, '0'), ') IS NOT NULL OR fn_fecha(s.c', LPAD(i + 1, 2, '0'), ') IS NOT NULL');
    SET @t = v_titulo;
    PREPARE st_bdi FROM @s; EXECUTE st_bdi USING @t; DEALLOCATE PREPARE st_bdi;
    SET i = i + 2;
  END WHILE;

  -- Primer renglón de cada pariente por familia (tabla aparte: MySQL no permite leer
  -- la misma tabla temporal dos veces en una consulta)
  DROP TEMPORARY TABLE IF EXISTS t_rel_min;
  CREATE TEMPORARY TABLE t_rel_min (PRIMARY KEY (familia_id, parentesco)) AS
  SELECT familia_id, parentesco, MIN(fila) AS fila FROM t_rel GROUP BY familia_id, parentesco;

  -- Participantes de BDI que no aparecen en BASE
  INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema)
  SELECT 'BDI', s.fila, 'NOMBRE', s.c02, 'No se encontró este participante en la hoja BASE'
  FROM stg_bdi s WHERE fn_norm(s.c02) IS NOT NULL AND fn_norm(s.c02) NOT LIKE 'NOMBRE%'
    AND NOT EXISTS (SELECT 1 FROM carga_mapa m WHERE m.hoja = 'BASE' AND m.rol = 'PARTICIPANTE' AND m.clave = fn_norm(s.c02));

  -- Madre y padre: se completa la fecha de nacimiento del tutor ya registrado
  UPDATE persona p
  JOIN familia_integrante fi ON fi.persona_id = p.id
  JOIN cat_parentesco pa ON pa.id = fi.parentesco_id
  JOIN t_rel r ON r.familia_id = fi.familia_id AND r.parentesco = pa.nombre AND r.parentesco IN ('Madre', 'Padre')
  SET p.fecha_nacimiento = COALESCE(fn_fecha(r.nacimiento), MAKEDATE(YEAR(CURDATE()) - fn_num(r.edad), 1)),
      p.fecha_nac_aprox = fn_fecha(r.nacimiento) IS NULL
  WHERE p.fecha_nacimiento IS NULL;

  -- Madre o padre que no venía en BASE: se registra como tutor sin nombre
  INSERT INTO persona (nombres, genero, fecha_nacimiento, fecha_nac_aprox)
  SELECT CONCAT(r.parentesco, ' (sin nombre)'), IF(r.parentesco = 'Madre', 'F', 'M'),
         COALESCE(fn_fecha(r.nacimiento), MAKEDATE(YEAR(CURDATE()) - fn_num(r.edad), 1)), fn_fecha(r.nacimiento) IS NULL
  FROM t_rel r JOIN t_rel_min mn ON mn.familia_id = r.familia_id AND mn.parentesco = r.parentesco AND mn.fila = r.fila
  WHERE r.parentesco IN ('Madre', 'Padre')
    AND NOT EXISTS (SELECT 1 FROM familia_integrante fi JOIN cat_parentesco pa ON pa.id = fi.parentesco_id
                     WHERE fi.familia_id = r.familia_id AND pa.nombre = r.parentesco);
  -- (se enlazan abajo junto con los indirectos)

  -- Indirectos: un familiar por familia, sin repetir al mismo pariente que listan dos hermanos
  -- (mismo parentesco y misma fecha) y sin contar a los hermanos que también son participantes.
  DROP TEMPORARY TABLE IF EXISTS t_ind;
  CREATE TEMPORARY TABLE t_ind AS
  SELECT r.familia_id, r.parentesco, MIN(r.fila) AS fila, MIN(r.col) AS col,
         COALESCE(fn_fecha(r.nacimiento), MAKEDATE(YEAR(CURDATE()) - fn_num(r.edad), 1)) AS nac,
         MAX(fn_fecha(r.nacimiento) IS NULL) AS aprox
  FROM t_rel r
  WHERE r.parentesco NOT IN ('Madre', 'Padre')
  GROUP BY r.familia_id, r.parentesco, COALESCE(fn_fecha(r.nacimiento), MAKEDATE(YEAR(CURDATE()) - fn_num(r.edad), 1));
  DELETE t FROM t_ind t
  WHERE t.parentesco IN ('Hermano', 'Hermana')
    AND EXISTS (SELECT 1 FROM participante pt JOIN persona p ON p.id = pt.persona_id
                 WHERE pt.familia_id = t.familia_id AND p.fecha_nacimiento = t.nac);

  INSERT INTO persona (nombres, genero, fecha_nacimiento, fecha_nac_aprox)
  SELECT CONCAT(t.parentesco, ' (sin nombre) · familia ', t.familia_id, ' · ', t.col),
         CASE WHEN t.parentesco IN ('Hermana','Sobrina','Tía','Cuñada','Prima','Bisabuela','Abuela') THEN 'F' ELSE 'M' END, t.nac, t.aprox
  FROM t_ind t;
  -- Enlazar a sus familias (madres/padres sin nombre y los indirectos)
  INSERT INTO familia_integrante (familia_id, persona_id, parentesco_id, es_tutor)
  SELECT CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(p.nombres, ' · familia ', -1), ' · ', 1) AS UNSIGNED), p.id, pa.id, FALSE
  FROM persona p JOIN cat_parentesco pa ON pa.nombre = SUBSTRING_INDEX(p.nombres, ' (sin nombre)', 1)
  WHERE p.nombres LIKE '% (sin nombre) · familia %'
    AND NOT EXISTS (SELECT 1 FROM familia_integrante fi WHERE fi.persona_id = p.id);
  INSERT INTO carga_mapa (hoja, fila, rol, id, clave)
  SELECT 'BDI', p.id, 'INDIRECTO', p.id, NULL FROM persona p WHERE p.nombres LIKE '% (sin nombre) · familia %'
    AND NOT EXISTS (SELECT 1 FROM carga_mapa m WHERE m.rol = 'INDIRECTO' AND m.id = p.id);
  UPDATE persona SET nombres = SUBSTRING_INDEX(nombres, ' · familia ', 1) WHERE nombres LIKE '% (sin nombre) · familia %';

  -- Madres/padres "sin nombre": se enlazan a la familia del participante del renglón
  INSERT INTO familia_integrante (familia_id, persona_id, parentesco_id, es_tutor)
  SELECT r.familia_id, p.id, pa.id, TRUE
  FROM persona p
  JOIN cat_parentesco pa ON pa.nombre = SUBSTRING_INDEX(p.nombres, ' (sin nombre)', 1) AND pa.nombre IN ('Madre', 'Padre')
  JOIN t_rel r ON r.parentesco = pa.nombre AND COALESCE(fn_fecha(r.nacimiento), MAKEDATE(YEAR(CURDATE()) - fn_num(r.edad), 1)) = p.fecha_nacimiento
  JOIN t_rel_min mn ON mn.familia_id = r.familia_id AND mn.parentesco = r.parentesco AND mn.fila = r.fila
  WHERE p.nombres IN ('Madre (sin nombre)', 'Padre (sin nombre)')
    AND NOT EXISTS (SELECT 1 FROM familia_integrante fi WHERE fi.persona_id = p.id);
  INSERT INTO carga_mapa (hoja, fila, rol, id, clave)
  SELECT 'BDI', p.id, 'INDIRECTO', p.id, NULL FROM persona p WHERE p.nombres IN ('Madre (sin nombre)', 'Padre (sin nombre)')
    AND NOT EXISTS (SELECT 1 FROM carga_mapa m WHERE m.rol = 'INDIRECTO' AND m.id = p.id);

  DROP TEMPORARY TABLE IF EXISTS t_rel, t_ind, t_rel_min;
  SET @importando = 0;
END //

-- ---------------------------------------------------------------------
-- Hoja DATOS de la base histórica: quienes ya salieron de MESE
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_carga_historica()
BEGIN
  DECLARE v_fin BOOLEAN DEFAULT FALSE;
  DECLARE v_fila INT UNSIGNED; DECLARE v_fam, v_per, v_insc INT UNSIGNED;
  DECLARE v_ent, v_sal DATE; DECLARE v_sin BOOLEAN; DECLARE v_clave_fam VARCHAR(300);
  DECLARE r_nombre, r_gen, r_ent, r_sal, r_meses, r_edad_ent, r_esc_ini, r_esc_fin, r_exito, r_cert, r_riesgo_in, r_nivel_in,
          r_riesgo_out, r_nivel_out, r_causa, r_causa_est, r_motivo, r_dir, r_col, r_tel, r_escuela, r_ciclo TEXT;
  DECLARE cur CURSOR FOR
    SELECT fila, c04, c05, c06, c07, c08, c10, c12, c13, c15, c16, c17, c18, c19, c20, c21, c22, c23, c24, c25, c26, c14, c01
    FROM stg_historica WHERE fn_norm(c04) IS NOT NULL AND fn_norm(c04) <> 'NOMBRE' ORDER BY fila;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = TRUE;

  SET @importando = 1;
  OPEN cur;
  leer: LOOP
    FETCH cur INTO v_fila, r_nombre, r_gen, r_ent, r_sal, r_meses, r_edad_ent, r_esc_ini, r_esc_fin, r_exito, r_cert, r_riesgo_in, r_nivel_in,
      r_riesgo_out, r_nivel_out, r_causa, r_causa_est, r_motivo, r_dir, r_col, r_tel, r_escuela, r_ciclo;
    IF v_fin THEN LEAVE leer; END IF;

    SET v_ent = fn_fecha(r_ent), v_sal = fn_fecha(r_sal), v_sin = FALSE;
    IF v_ent IS NULL AND v_sal IS NOT NULL AND fn_num(r_meses) IS NOT NULL THEN
      SET v_ent = v_sal - INTERVAL fn_num(r_meses) MONTH;      -- se reconstruye con los meses de permanencia
    END IF;
    IF v_ent IS NULL AND REGEXP_SUBSTR(COALESCE(r_ciclo, ''), '^(19|20)[0-9]{2}') <> '' THEN
      SET v_ent = MAKEDATE(CAST(REGEXP_SUBSTR(r_ciclo, '^(19|20)[0-9]{2}') AS UNSIGNED), 1) + INTERVAL 7 MONTH;   -- inicio del ciclo escolar
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('HISTORICA', v_fila, 'FECHA DE ENTRADA', r_ent, CONCAT('Sin fecha de entrada; se usó el inicio del ciclo ', r_ciclo));
    END IF;
    IF v_ent IS NULL AND v_sal IS NOT NULL THEN
      SET v_ent = v_sal;
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('HISTORICA', v_fila, 'FECHA DE ENTRADA', r_ent, 'Sin fecha de entrada; se usó la fecha de salida');
    END IF;
    IF v_ent IS NULL THEN
      SET v_sin = TRUE;
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('HISTORICA', v_fila, 'FECHA DE ENTRADA', r_ent, 'Sin fechas: se cargó como salida sin fecha registrada');
    END IF;
    IF v_sal IS NULL AND NOT v_sin THEN
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('HISTORICA', v_fila, 'FECHA DE SALIDA', r_sal, 'Sin fecha de salida; se usó la fecha de entrada');
      SET v_sal = v_ent;
    END IF;
    IF v_sal < v_ent THEN
      INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('HISTORICA', v_fila, 'FECHA DE SALIDA', r_sal, 'La salida es anterior a la entrada; se intercambiaron');
      SET @tmp = v_ent, v_ent = v_sal, v_sal = @tmp;
    END IF;

    -- Familia por domicilio (en la base histórica no hay nombre de tutores)
    SET v_clave_fam = CONCAT('H|', COALESCE(fn_norm(r_dir), CONCAT('fila', v_fila)), '|', COALESCE(fn_norm(r_col), ''));
    SET v_fam = (SELECT id FROM carga_mapa WHERE hoja = 'HISTORICA' AND rol = 'FAMILIA' AND clave = v_clave_fam LIMIT 1);
    IF v_fam IS NULL THEN
      INSERT INTO familia (calle, colonia_id, telefono) VALUES (fn_titulo(r_dir), fn_colonia(fn_titulo(r_col), NULL), fn_tel(r_tel));
      SET v_fam = LAST_INSERT_ID();
      INSERT INTO carga_mapa VALUES ('HISTORICA', v_fila, 'FAMILIA', v_fam, v_clave_fam);
    END IF;

    INSERT INTO persona (nombres, apellido_paterno, apellido_materno, genero, fecha_nacimiento, fecha_nac_aprox)
    VALUES (COALESCE(fn_nombre_parte(r_nombre, 'N'), fn_titulo(r_nombre)), fn_nombre_parte(r_nombre, 'P'), fn_nombre_parte(r_nombre, 'M'),
            IF(fn_norm(r_gen) IN ('F', 'M'), fn_norm(r_gen), NULL),
            IF(v_ent IS NOT NULL AND fn_num(r_edad_ent) BETWEEN 1 AND 30, MAKEDATE(YEAR(v_ent) - fn_num(r_edad_ent), 1), NULL),
            COALESCE(v_ent IS NOT NULL AND fn_num(r_edad_ent) BETWEEN 1 AND 30, FALSE));
    SET v_per = LAST_INSERT_ID();
    INSERT INTO carga_mapa VALUES ('HISTORICA', v_fila, 'PARTICIPANTE', v_per, fn_norm(r_nombre));
    INSERT INTO participante (persona_id, familia_id) VALUES (v_per, v_fam);

    BEGIN
      INSERT INTO inscripcion (participante_id, sin_fechas, fecha_ingreso, fecha_baja, causa_baja_id, causa_estadistica_id, motivo,
                               caso_exito_id, caso_exito_detalle, certificado_id, nivel_inicial_id, grado_inicial, nivel_final_id, grado_final,
                               riesgo_ingreso_id, riesgo_egreso_id)
      VALUES (v_per, v_sin, LEAST(v_ent, CURDATE()), LEAST(v_sal, CURDATE()),
        COALESCE((SELECT id FROM cat_causa_baja WHERE nombre = fn_alias('causa_baja', r_causa)),
                 IF(fn_norm(r_causa) IS NULL, NULL, (SELECT id FROM cat_causa_baja WHERE nombre = 'Otro'))),
        (SELECT id FROM cat_causa_baja_estadistica WHERE nombre = fn_alias('causa_estadistica', r_causa_est)),
        fn_texto(r_motivo),
        (SELECT id FROM cat_caso_exito WHERE nombre = CASE
            WHEN fn_norm(r_exito) IS NULL OR fn_norm(r_exito) IN ('N/A', 'NO') THEN NULL
            WHEN fn_clave(r_exito) REGEXP 'TECNICA.*BACH' THEN 'Carrera técnica con bachillerato'
            WHEN fn_clave(r_exito) REGEXP '^(CARRERA|CARRETA|TEC|CAR\\.)' THEN 'Carrera técnica'
            WHEN fn_clave(r_exito) REGEXP '^OFICIO' THEN 'Oficio'
            WHEN fn_clave(r_exito) REGEXP '^(LIC|LICENCIATURA|ING)' THEN 'Licenciatura'
            WHEN fn_clave(r_exito) REGEXP '^(PREP|BACH)' THEN 'Preparatoria'
            WHEN fn_clave(r_exito) REGEXP '^SEC' THEN 'Secundaria' END),
        IF(fn_norm(r_exito) IN ('N/A', 'NO'), NULL, LEFT(fn_titulo(r_exito), 150)),
        (SELECT id FROM cat_certificado WHERE nombre = CASE
            WHEN fn_clave(r_cert) REGEXP '^CERTIFICADO (DE )?SEC' THEN 'Certificado de secundaria'
            WHEN fn_clave(r_cert) REGEXP '^BOLETA' THEN 'Boleta final de secundaria'
            WHEN fn_clave(r_cert) REGEXP 'TERMINACION SEC' THEN 'Constancia de terminación de secundaria'
            WHEN fn_clave(r_cert) REGEXP 'TERMINACION OFICIO' THEN 'Constancia de terminación de oficio'
            WHEN fn_clave(r_cert) REGEXP 'TERMINACION CARRERA' THEN 'Constancia de terminación de carrera técnica'
            WHEN fn_clave(r_cert) REGEXP 'TERMINACION LIC' THEN 'Constancia de terminación de licenciatura'
            WHEN fn_clave(r_cert) REGEXP '^CERTIFICADO PREP' THEN 'Certificado de preparatoria'
            WHEN fn_clave(r_cert) REGEXP '^CERTIFICADO LIC' THEN 'Certificado de licenciatura'
            WHEN fn_clave(r_cert) REGEXP '^CERTIFICADO CARRERA' THEN 'Certificado de carrera técnica'
            WHEN fn_norm(r_cert) = 'PENDIENTE' THEN 'Pendiente' END),
        (SELECT ng.nivel_id FROM cat_nivel_grado ng JOIN cat_nivel_educativo ne ON ne.id = ng.nivel_id WHERE ne.clave = fn_nivel(r_esc_ini) AND ng.grado = COALESCE(fn_grado(r_esc_ini), 1)),
        (SELECT ng.grado FROM cat_nivel_grado ng JOIN cat_nivel_educativo ne ON ne.id = ng.nivel_id WHERE ne.clave = fn_nivel(r_esc_ini) AND ng.grado = COALESCE(fn_grado(r_esc_ini), 1)),
        (SELECT ng.nivel_id FROM cat_nivel_grado ng JOIN cat_nivel_educativo ne ON ne.id = ng.nivel_id WHERE ne.clave = fn_nivel(r_esc_fin) AND ng.grado = COALESCE(fn_grado(r_esc_fin), ne.grados)),
        (SELECT ng.grado FROM cat_nivel_grado ng JOIN cat_nivel_educativo ne ON ne.id = ng.nivel_id WHERE ne.clave = fn_nivel(r_esc_fin) AND ng.grado = COALESCE(fn_grado(r_esc_fin), ne.grados)),
        (SELECT id FROM cat_nivel_riesgo WHERE nombre = CASE WHEN fn_norm(r_nivel_in) LIKE 'ALT%' THEN 'Alto' WHEN fn_norm(r_nivel_in) LIKE 'MED%' THEN 'Medio' WHEN fn_norm(r_nivel_in) LIKE 'BAJ%' THEN 'Bajo' END),
        (SELECT id FROM cat_nivel_riesgo WHERE nombre = CASE WHEN fn_norm(r_nivel_out) LIKE 'ALT%' THEN 'Alto' WHEN fn_norm(r_nivel_out) LIKE 'MED%' THEN 'Medio' WHEN fn_norm(r_nivel_out) LIKE 'BAJ%' THEN 'Bajo' END));
      SET v_insc = LAST_INSERT_ID();
      INSERT IGNORE INTO inscripcion_riesgo (inscripcion_id, momento, tipo_riesgo_id)
      SELECT v_insc, x.m, tr.id FROM (SELECT 'INGRESO' AS m, fn_norm(r_riesgo_in) AS t UNION ALL SELECT 'EGRESO', fn_norm(r_riesgo_out)) x
      JOIN cat_tipo_riesgo tr ON x.t LIKE CONCAT('%', UPPER(LEFT(tr.nombre, 6)), '%');
      -- Escuela donde estaba al salir (escolaridad del ciclo de salida)
      IF fn_texto(r_escuela) IS NOT NULL AND fn_norm(r_escuela) NOT IN ('N/A', 'PENDIENTE', 'NO HAY REGISTRO', 'SIN REGISTRO') THEN
        INSERT IGNORE INTO cat_escuela (nombre) VALUES (fn_texto(r_escuela));
        INSERT IGNORE INTO participante_escolaridad (participante_id, ciclo_id, escuela_id, nivel_id, grado)
        SELECT v_per, fn_ciclo(COALESCE(v_sal, v_ent)), (SELECT id FROM cat_escuela WHERE nombre = fn_texto(r_escuela)), i.nivel_final_id, i.grado_final
        FROM inscripcion i WHERE i.id = v_insc AND i.nivel_final_id IS NOT NULL AND fn_ciclo(COALESCE(v_sal, v_ent)) IS NOT NULL;
        IF ROW_COUNT() = 0 THEN
          INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema)
          VALUES ('HISTORICA', v_fila, 'ESCUELA', r_escuela, 'No se guardó la escuela: falta la escolaridad final o la fecha');
        END IF;
      END IF;
      IF fn_texto(r_esc_fin) IS NOT NULL AND fn_nivel(r_esc_fin) IS NULL AND fn_clave(r_esc_fin) NOT IN ('NO HAY REGISTRO','NO REGISTRO','PENDIENTE','N/A') THEN
        INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('HISTORICA', v_fila, 'ESCOLARIDAD FINAL', r_esc_fin, 'No se reconoció el nivel escolar');
      END IF;
      IF fn_norm(r_causa) IS NOT NULL AND (SELECT id FROM cat_causa_baja WHERE nombre = fn_alias('causa_baja', r_causa)) IS NULL THEN
        INSERT INTO carga_pendiente (hoja, fila, columna, valor, problema) VALUES ('HISTORICA', v_fila, 'CAUSA DE BAJA', r_causa, 'Causa no reconocida; se guardó como "Otro" (el texto queda en el motivo)');
        UPDATE inscripcion SET motivo = CONCAT_WS(' · ', CONCAT('Causa: ', fn_texto(r_causa)), motivo) WHERE id = v_insc;
      END IF;
    END;
  END LOOP;
  CLOSE cur;
  SET @importando = 0;
END //

CREATE PROCEDURE sp_carga_todo(IN p_fecha_corte DATE)
BEGIN
  CALL sp_carga_limpiar();
  CALL sp_carga_base(p_fecha_corte);
  CALL sp_carga_bdi();
  CALL sp_carga_historica();
  SELECT 'Participantes activos' AS concepto, COUNT(*) AS total FROM v_activo
  UNION ALL SELECT 'Familias activas', COUNT(DISTINCT familia_id) FROM v_activo
  UNION ALL SELECT 'Tutores', COUNT(*) FROM v_familiar WHERE es_tutor
  UNION ALL SELECT 'Familiares indirectos', COUNT(*) FROM v_familiar WHERE NOT es_tutor
  UNION ALL SELECT 'Base histórica (periodos cerrados)', COUNT(*) FROM inscripcion WHERE fecha_baja IS NOT NULL
  UNION ALL SELECT 'Valores por revisar (carga_pendiente)', COUNT(*) FROM carga_pendiente;
END //
DELIMITER ;

-- ---------------------------------------------------------------------
-- Ejemplo de carga de los CSV (ajuste la ruta). En MySQL debe habilitarse
-- local_infile en el servidor y en el cliente (mysql --local-infile=1).
-- La hoja BASE tiene 5 renglones de encabezado; BDI 5; la histórica 2.
-- ---------------------------------------------------------------------
-- SET @formato_fecha = '%d/%m/%Y';
-- TRUNCATE stg_base;
-- LOAD DATA LOCAL INFILE 'C:/mese/base.csv' INTO TABLE stg_base CHARACTER SET utf8mb4
--   FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\r\n' IGNORE 5 LINES
--   (c01,c02,c03,c04,c05,c06,c07,c08,c09,c10,c11,c12,c13,c14,c15,c16,c17,c18,c19,c20,c21,c22,c23,c24,c25,c26,c27,c28,c29,c30,
--    c31,c32,c33,c34,c35,c36,c37,c38,c39,c40,c41,c42,c43,c44,c45,c46,c47,c48,c49,c50,c51,c52,c53,c54,c55,c56,c57,c58,c59,c60,
--    c61,c62,c63,c64,c65,c66,c67,c68,c69,c70,c71,c72,c73,c74,c75,c76,c77,c78);
-- (igual para stg_bdi con c01..c62 e IGNORE 5 LINES, y stg_historica con c01..c26 e IGNORE 2 LINES)
-- CALL sp_carga_todo('2026-09-30');
-- SELECT columna, valor, problema, COUNT(*) veces FROM carga_pendiente GROUP BY columna, valor, problema ORDER BY veces DESC;

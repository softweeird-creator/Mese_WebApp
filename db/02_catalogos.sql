-- =====================================================================
--  02_catalogos.sql — valores iniciales de los catálogos
--  Se puede volver a correr: primero vacía los catálogos.
-- =====================================================================
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;   -- misma intercalación que la base

-- Ayudante temporal: crea una pregunta y sus opciones a partir de 'A|B|C'.
DROP PROCEDURE IF EXISTS _pregunta;
DELIMITER //
CREATE PROCEDURE _pregunta(IN p_sec TINYINT, IN p_clave VARCHAR(20), IN p_texto VARCHAR(160),
                           IN p_tipo VARCHAR(8), IN p_otro BOOLEAN, IN p_orden SMALLINT, IN p_opciones TEXT)
BEGIN
  DECLARE v_id SMALLINT; DECLARE v_i TINYINT DEFAULT 1; DECLARE v_resto TEXT DEFAULT p_opciones; DECLARE v_op VARCHAR(60);
  INSERT INTO cat_pregunta (seccion_id, clave, texto, tipo, permite_otro, orden) VALUES (p_sec, p_clave, p_texto, p_tipo, p_otro, p_orden);
  SET v_id = LAST_INSERT_ID();
  WHILE v_resto <> '' DO
    SET v_op = TRIM(SUBSTRING_INDEX(v_resto, '|', 1));
    SET v_resto = IF(LOCATE('|', v_resto) > 0, SUBSTRING(v_resto, LOCATE('|', v_resto) + 1), '');
    INSERT INTO cat_opcion (pregunta_id, etiqueta, orden) VALUES (v_id, v_op, v_i);
    SET v_i = v_i + 1;
  END WHILE;
END //
DELIMITER ;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE cat_opcion; TRUNCATE cat_pregunta; TRUNCATE cat_seccion; TRUNCATE cat_rango_edad;
TRUNCATE cat_concepto_monto; TRUNCATE cat_vacuna; TRUNCATE cat_tipo_riesgo; TRUNCATE cat_nivel_riesgo;
TRUNCATE cat_certificado; TRUNCATE cat_caso_exito; TRUNCATE cat_causa_baja_estadistica; TRUNCATE cat_causa_baja;
TRUNCATE cat_patrocinador; TRUNCATE cat_turno; TRUNCATE cat_ciclo_escolar; TRUNCATE cat_nivel_grado;
TRUNCATE cat_nivel_educativo; TRUNCATE cat_tipo_sangre; TRUNCATE cat_estado_civil; TRUNCATE cat_parentesco;
TRUNCATE cat_municipio;
SET FOREIGN_KEY_CHECKS = 1;

INSERT INTO cat_municipio (nombre) VALUES ('Morelia');

INSERT INTO cat_parentesco (nombre, puede_ser_tutor) VALUES
 ('Madre',TRUE),('Padre',TRUE),('Tutor(a)',TRUE),('Abuela',TRUE),('Abuelo',TRUE),('Tía',TRUE),('Tío',TRUE),
 ('Madrastra',TRUE),('Padrastro',TRUE),('Hermana',FALSE),('Hermano',FALSE),('Bisabuela',FALSE),('Bisabuelo',FALSE),
 ('Prima',FALSE),('Primo',FALSE),('Sobrina',FALSE),('Sobrino',FALSE),('Cuñada',FALSE),('Cuñado',FALSE),
 ('Hija',FALSE),('Hijo',FALSE),('Otro',FALSE);

INSERT INTO cat_estado_civil (nombre) VALUES
 ('Soltero(a)'),('Casado(a)'),('Unión libre'),('Separado(a)'),('Divorciado(a)'),('Viudo(a)');

INSERT INTO cat_tipo_sangre (nombre) VALUES ('O+'),('O-'),('A+'),('A-'),('B+'),('B-'),('AB+'),('AB-'),('No sabe');

INSERT INTO cat_nivel_educativo (clave, nombre, grados, orden) VALUES
 ('PREESC','Preescolar',3,1),('PRIM','Primaria',6,2),('SEC','Secundaria',3,3),('SECA','Secundaria abierta',3,4),
 ('TEC','Carrera técnica',3,5),('OFICIO','Oficio',3,6),('PREPA','Preparatoria',3,7),('PREPAA','Preparatoria abierta',3,8),
 ('LIC','Licenciatura',5,9),('POSG','Posgrado',3,10),('INEA','INEA',3,11),('ESP','Educación especial',6,12);

-- Un renglón por cada grado válido de cada nivel (Primaria 1..6, Secundaria 1..3, ...)
INSERT INTO cat_nivel_grado (nivel_id, grado)
WITH RECURSIVE g(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM g WHERE n < 6)
SELECT ne.id, g.n FROM cat_nivel_educativo ne JOIN g ON g.n <= ne.grados;

INSERT INTO cat_ciclo_escolar (nombre, inicio, fin)
WITH RECURSIVE a(y) AS (SELECT 1995 UNION ALL SELECT y + 1 FROM a WHERE y < 2035)
SELECT CONCAT(y, '-', y + 1), MAKEDATE(y, 1) + INTERVAL 7 MONTH, MAKEDATE(y + 1, 1) + INTERVAL 6 MONTH + INTERVAL 30 DAY FROM a;
-- (cada ciclo va del 1 de agosto al 31 de julio)

INSERT INTO cat_turno (nombre) VALUES ('Matutino'),('Vespertino'),('Tiempo completo'),('Mixto');

INSERT INTO cat_patrocinador (nombre) VALUES ('Repsol'),('Soriana'),('Bécalos'),('MESE'),('General');

INSERT INTO cat_causa_baja (nombre) VALUES
 ('Abandono de estudios'),('Desinterés por el apoyo'),('Concluyó estudios'),('Cambio de domicilio'),
 ('Mejoró la situación económica'),('Inasistencia por distancia'),('Falta de asistencia'),
 ('Falta de tiempo y tutor responsable'),('Se casó'),('Embarazo'),('Educación especial'),('Enfermedad'),
 ('Otro'),('Sin registro');

INSERT INTO cat_causa_baja_estadistica (nombre) VALUES
 ('Continúa estudiando'),('Deserción escolar / vida laboral'),('Egreso institucional'),('Embarazo'),
 ('Unión libre'),('Finado'),('Cambio de residencia'),('Sin registro');

INSERT INTO cat_caso_exito (nombre, orden) VALUES
 ('Secundaria',1),('Oficio',2),('Carrera técnica',3),('Carrera técnica con bachillerato',4),
 ('Preparatoria',5),('Licenciatura',6);

INSERT INTO cat_certificado (nombre) VALUES
 ('Certificado de secundaria'),('Boleta final de secundaria'),('Constancia de terminación de secundaria'),
 ('Certificado de preparatoria'),('Certificado de carrera técnica'),('Constancia de terminación de carrera técnica'),
 ('Constancia de terminación de oficio'),('Certificado de licenciatura'),('Constancia de terminación de licenciatura'),
 ('Pendiente');

INSERT INTO cat_nivel_riesgo (nombre) VALUES ('Bajo'),('Medio'),('Alto');
INSERT INTO cat_tipo_riesgo (nombre) VALUES ('Económico'),('Emocional'),('Educativo');
INSERT INTO cat_vacuna (nombre) VALUES ('COVID-19'),('Sarampión');

INSERT INTO cat_concepto_monto (clave, tipo, nombre, orden) VALUES
 ('ing_fam','INGRESO','Ingreso mensual familiar (total declarado)',1),
 ('ap_bj','APOYO','Becas Benito Juárez / Rita Cetina',1),('ap_am','APOYO','Pensión para el Bienestar de las Personas Adultas Mayores',2),
 ('ap_dis','APOYO','Pensión para el Bienestar de las Personas con Discapacidad',3),('ap_lic','APOYO','Liconsa',4),('ap_ot','APOYO','Otro apoyo',5),
 ('eg_renta','EGRESO','Renta',1),('eg_alim','EGRESO','Alimentación',2),('eg_serv','EGRESO','Servicios (agua, luz, gas)',3),('eg_trans','EGRESO','Transporte',4),
 ('eg_edu','EGRESO','Educación',5),('eg_vest','EGRESO','Vestido y calzado',6),('eg_int','EGRESO','Internet',7),('eg_tel','EGRESO','Teléfono / celular',8),
 ('eg_med','EGRESO','Atención médica',9),('eg_ot','EGRESO','Otros',10);

-- Rangos de la hoja "ESTADÍSTICAS" (Participantes directos, Padres y/o tutores, Rangos tutores, Indirectos)
INSERT INTO cat_rango_edad (grupo, etiqueta, edad_min, edad_max, orden) VALUES
 ('DIRECTOS','0 a 5',0,5,1),('DIRECTOS','6 a 12',6,12,2),('DIRECTOS','13 a 18',13,18,3),('DIRECTOS','19 a 25',19,25,4),
 ('TUTORES','18 a 29',18,29,1),('TUTORES','30 a 59',30,59,2),('TUTORES','60 +',60,120,3),
 ('RANGOS_TUTORES','18-24',18,24,1),('RANGOS_TUTORES','25-49',25,49,2),('RANGOS_TUTORES','50-64',50,64,3),('RANGOS_TUTORES','65 +',65,120,4),
 ('INDIRECTOS','0 a 2',0,2,1),('INDIRECTOS','3 a 5',3,5,2),('INDIRECTOS','6 a 12',6,12,3),('INDIRECTOS','13 a 18',13,18,4),
 ('INDIRECTOS','19 a 25',19,25,5),('INDIRECTOS','26 +',26,120,6);

-- ---------------------------------------------------------------------
-- Cuestionario: las claves son las mismas que usa el formulario de la página web.
-- ---------------------------------------------------------------------
INSERT INTO cat_seccion (id, nombre) VALUES
 (0,'Valoración de trabajo social'),(1,'Información del participante'),(2,'Integrantes de la familia e ingresos'),
 (3,'Apoyos gubernamentales'),(4,'Vivienda'),(5,'Servicios públicos'),(6,'Hábitos alimenticios y estilo de vida'),
 (7,'Huertos familiares'),(8,'Salud'),(9,'Dinámica y comunicación familiar asertiva'),(10,'Economía familiar');

CALL _pregunta(0,'nivel_pobreza','Nivel de pobreza','UNICA',FALSE,1,'Pobreza extrema|Pobreza|Media');
CALL _pregunta(0,'despensa','Despensa asignada','UNICA',FALSE,2,'SIMI 1|SIMI 2');
CALL _pregunta(0,'dx_nutricional','Diagnóstico nutricional del participante','UNICA',FALSE,3,'Sano|Sano con riesgo|Bajo peso|Sobrepeso|Obesidad|Desnutrición|Desnutrición moderada|Desnutrición severa');
CALL _pregunta(0,'hacinamiento','Nivel de hacinamiento','UNICA',FALSE,4,'Nulo|Bajo|Medio|Alto');
CALL _pregunta(0,'terreno','Situación del terreno','UNICA',FALSE,5,'Regular|Irregular|Ejido');
CALL _pregunta(0,'serv_colonia','Servicios en la colonia','UNICA',FALSE,6,'Completos|Incompletos');
CALL _pregunta(1,'turno','Turno escolar','UNICA',FALSE,1,'Matutino|Vespertino|Tiempo completo|Mixto');
CALL _pregunta(1,'beca','Tipo de beca','MULTIPLE',FALSE,2,'MESE|BBVA|Especial|No tengo');
CALL _pregunta(4,'casa','Su casa es','UNICA',FALSE,1,'Propia|Rentada|Prestada|Irregular|Compartida');
CALL _pregunta(4,'serv','¿Cuenta con los siguientes servicios o equipamiento?','MULTIPLE',FALSE,2,'Agua|Luz|Drenaje|Computadora|Internet');
CALL _pregunta(4,'car','Características de la casa','MULTIPLE',TRUE,3,'Obra negra|Terminada|Mixta|Lámina y madera|Comedor|Cocina|Patio|Cochera');
CALL _pregunta(4,'piso','El piso es','MULTIPLE',TRUE,4,'Tierra|Cemento|Vitropiso|Mosaico');
CALL _pregunta(4,'techo','El techo es','MULTIPLE',TRUE,5,'Ladrillo|Concreto|Lámina|Cartón|Madera');
CALL _pregunta(4,'comb','Tipo de combustible','MULTIPLE',TRUE,6,'Gas|Leña|Carbón');
CALL _pregunta(4,'auto','Vehículo','MULTIPLE',FALSE,7,'Propio|Prestado|Motocicleta|No tiene');
CALL _pregunta(4,'docs','Documentos importantes','MULTIPLE',FALSE,8,'Completos|Ordenados|Incompletos|Desordenados');
CALL _pregunta(4,'hig','Higiene de la vivienda','UNICA',FALSE,9,'Buena|Regular|Deficiente');
CALL _pregunta(5,'sp','En la zona cuentan con','MULTIPLE',FALSE,1,'Escuela|Centro de salud|Pavimento|Alumbrado público|Transporte público');
CALL _pregunta(5,'com','¿Participan en actividades comunitarias?','UNICA',FALSE,2,'Sí|No');
CALL _pregunta(6,'alim','¿Cómo evalúa los hábitos alimenticios de su familia?','UNICA',FALSE,1,'Excelente|Bueno|Regular|Deficiente');
CALL _pregunta(6,'comidas','¿Cuántas comidas realizan al día?','UNICA',FALSE,2,'Cinco o más|Cuatro|Tres|Dos o menos');
CALL _pregunta(6,'fis','¿Algún miembro de la familia practica actividad física?','UNICA',FALSE,3,'Sí|No');
CALL _pregunta(7,'huerto','¿Cuentan con huerto familiar?','UNICA',FALSE,1,'Sí|No|Me gustaría|No me interesa');
CALL _pregunta(8,'med','Cuando requiere asistencia médica, asiste a','MULTIPLE',FALSE,1,'IMSS|IMSS Bienestar|SIMI|MESE|Particular|Ninguno');
CALL _pregunta(8,'cartilla','Cartilla de vacunación actualizada entregada a MESE','UNICA',FALSE,2,'Sí|No');
CALL _pregunta(8,'anti','¿Utiliza algún método anticonceptivo?','UNICA',FALSE,3,'Sí|No');
CALL _pregunta(8,'anti_pl','¿Planea utilizarlo?','UNICA',FALSE,4,'Sí|No');
CALL _pregunta(8,'anti_m','Método anticonceptivo','MULTIPLE',TRUE,5,'DIU|Inyecciones|Preservativo|Coito interrumpido|Vasectomía|Implante|Parches|Anillo vaginal|Salpingoclasia|Pastillas anticonceptivas');
CALL _pregunta(8,'adi_p','Adicciones: participante','MULTIPLE',FALSE,6,'Alcoholismo|Tabaquismo|Drogadicción|Ninguno');
CALL _pregunta(8,'adi_t','Adicciones: tutor','MULTIPLE',FALSE,7,'Alcoholismo|Tabaquismo|Drogadicción|Ninguno');
CALL _pregunta(8,'adi_o','Adicciones: otro familiar','MULTIPLE',TRUE,8,'Alcoholismo|Tabaquismo|Drogadicción|Ninguno');
CALL _pregunta(9,'v_fis','Violencia física','MULTIPLE',FALSE,1,'Madre|Padre|Ambos|Hijos|Ninguno');
CALL _pregunta(9,'v_psi','Violencia psicológica','MULTIPLE',FALSE,2,'Madre|Padre|Ambos|Hijos|Ninguno');
CALL _pregunta(9,'v_ver','Violencia verbal','MULTIPLE',FALSE,3,'Madre|Padre|Ambos|Hijos|Ninguno');
CALL _pregunta(9,'v_eco','Violencia económica','MULTIPLE',FALSE,4,'Madre|Padre|Ambos|Hijos|Ninguno');
CALL _pregunta(9,'bull','Bullying','UNICA',FALSE,5,'Sí|No');
CALL _pregunta(9,'riesgo','Factores de riesgo','MULTIPLE',FALSE,6,'Violencia|Adicciones|Pandillas');
CALL _pregunta(9,'prot','Factores protectores','MULTIPLE',FALSE,7,'MESE|Alianzas');
CALL _pregunta(10,'deu','¿Tiene deudas?','UNICA',FALSE,1,'Sí|No');

DROP PROCEDURE _pregunta;

-- Usuario genérico para registros importados o sin trabajadora social identificada
INSERT IGNORE INTO usuario (id, nombre, rol) VALUES (1, 'Sistema (importación)', 'ADMIN');

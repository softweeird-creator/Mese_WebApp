-- =====================================================================
--  pruebas/pruebas_carga.sql — pruebas de 06_carga_excel.sql con datos
--  FICTICIOS (pruebas/datos/*.csv). Las corre probar_todo.sh después de
--  cargar los CSV a las tablas de paso.
--
--  ¡Solo en una base de prueba! sp_carga_todo borra lo que se haya cargado
--  antes desde Excel, y al final este archivo vuelve a borrar la carga.
-- =====================================================================
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;   -- misma intercalación que la base

DROP TABLE IF EXISTS prueba_carga_resultado;
CREATE TABLE prueba_carga_resultado (
  n INT AUTO_INCREMENT PRIMARY KEY, prueba VARCHAR(160), esperado VARCHAR(200), obtenido VARCHAR(200),
  paso BOOLEAN AS (esperado <=> obtenido) STORED
) ENGINE=InnoDB;

DROP PROCEDURE IF EXISTS _afirmar_carga;
DROP PROCEDURE IF EXISTS _pruebas_carga;
DELIMITER //
CREATE PROCEDURE _afirmar_carga(IN p_nombre VARCHAR(160), IN p_esperado VARCHAR(200), IN p_obtenido VARCHAR(200))
BEGIN
  INSERT INTO prueba_carga_resultado (prueba, esperado, obtenido) VALUES (p_nombre, p_esperado, p_obtenido);
END //

CREATE PROCEDURE _pruebas_carga()
BEGIN
  DECLARE v_luis, v_ana, v_pedro, v_maria, v_fam, v_fam2, v_vis INT UNSIGNED;
  DECLARE v_n1, v_n2 INT;

  CALL sp_carga_todo('2026-09-30');
  SET v_n1 = (SELECT COUNT(*) FROM persona);
  CALL sp_carga_todo('2026-09-30');              -- repetir la carga no debe duplicar nada
  SET v_n2 = (SELECT COUNT(*) FROM persona);
  CALL _afirmar_carga('Repetir la carga no duplica personas', v_n1, v_n2);

  SET v_luis  = (SELECT persona_id FROM v_activo WHERE nombre_completo = 'Luis Angel Prueba Gomez');
  SET v_ana   = (SELECT persona_id FROM v_activo WHERE nombre_completo = 'Ana Sofia Prueba Gomez');
  SET v_pedro = (SELECT persona_id FROM v_activo WHERE nombre_completo = 'Pedro Prueba Gomez');
  SET v_maria = (SELECT persona_id FROM v_activo WHERE nombre_completo = 'Maria Jose De la Cruz Perez');
  SET v_fam   = (SELECT familia_id FROM participante WHERE persona_id = v_luis);
  SET v_fam2  = (SELECT familia_id FROM participante WHERE persona_id = v_maria);
  SET v_vis   = (SELECT id FROM visita WHERE familia_id = v_fam AND origen = 'EXCEL');

  -- ---- Hoja BASE ----
  CALL _afirmar_carga('BASE: 4 participantes activos', '4', (SELECT COUNT(*) FROM v_activo));
  CALL _afirmar_carga('BASE: 2 familias', '2', (SELECT COUNT(DISTINCT familia_id) FROM v_activo));
  CALL _afirmar_carga('Nombre "APELLIDO APELLIDO NOMBRES" se separa bien', 'Luis Angel|Prueba|Gomez',
                      (SELECT CONCAT_WS('|', nombres, apellido_paterno, apellido_materno) FROM persona WHERE id = v_luis));
  CALL _afirmar_carga('Partículas del apellido ("DE LA CRUZ")', 'De la Cruz', (SELECT apellido_paterno FROM persona WHERE id = v_maria));
  CALL _afirmar_carga('Hermanos con la misma madre quedan en la misma familia', v_fam, (SELECT familia_id FROM participante WHERE persona_id = v_ana));
  CALL _afirmar_carga('Madre escrita distinto, mismo domicilio y apellido: misma familia', v_fam, (SELECT familia_id FROM participante WHERE persona_id = v_pedro));
  CALL _afirmar_carga('Fecha dd/mm/aaaa', '2015-03-15', (SELECT fecha_nacimiento FROM persona WHERE id = v_luis));
  CALL _afirmar_carga('Fecha como número de serie de Excel (45200)', '2023-10-01', (SELECT fecha_ingreso FROM inscripcion WHERE participante_id = v_maria));
  CALL _afirmar_carga('Sin fecha de ingreso se usa la fecha de corte', '2026-09-30', (SELECT fecha_ingreso FROM inscripcion WHERE participante_id = v_ana));
  CALL _afirmar_carga('CURP válida se guarda', 'PUGL150315HMNGML09', (SELECT curp FROM persona WHERE id = v_luis));
  CALL _afirmar_carga('CURP inválida no se guarda', NULL, (SELECT curp FROM persona WHERE id = v_ana));
  CALL _afirmar_carga('Tipo de sangre "O +" → O+', 'O+', (SELECT ts.nombre FROM persona p JOIN cat_tipo_sangre ts ON ts.id = p.tipo_sangre_id WHERE p.id = v_luis));
  CALL _afirmar_carga('"REPSOL/BÉCALOS" son dos becas', 'Bécalos,Repsol',
                      (SELECT GROUP_CONCAT(cp.nombre ORDER BY cp.nombre) FROM participante_beca b JOIN cat_patrocinador cp ON cp.id = b.patrocinador_id WHERE b.participante_id = v_luis));
  CALL _afirmar_carga('Escolaridad "PRIM. 5° AÑO" y turno "MAT."', 'PRIM 5 Matutino',
                      (SELECT CONCAT_WS(' ', nivel_clave, grado, turno) FROM v_escolaridad_actual WHERE participante_id = v_luis));
  CALL _afirmar_carga('Grado no reconocido ("QUINTO") no crea escolaridad', '0', (SELECT COUNT(*) FROM participante_escolaridad WHERE participante_id = v_maria));
  CALL _afirmar_carga('No. BECADO fuera de rango no detiene la carga', NULL, (SELECT numero_becado FROM participante WHERE persona_id = v_pedro));
  CALL _afirmar_carga('Familia: colonia y código postal', 'Colonia Ficticia 58000',
                      (SELECT CONCAT_WS(' ', c.nombre, c.codigo_postal) FROM familia f JOIN cat_colonia c ON c.id = f.colonia_id WHERE f.id = v_fam));
  CALL _afirmar_carga('Familia: teléfono solo dígitos, correo y aviso firmado', '4437778899 familia.prueba@example.com 2026-09-30',
                      (SELECT CONCAT_WS(' ', telefono, correo, aviso_privacidad) FROM familia WHERE id = v_fam));
  CALL _afirmar_carga('Tutores de la familia 1 (madre y padre)', 'Madre:Rosa Gomez Prueba,Padre:Juan Prueba Lopez',
                      (SELECT GROUP_CONCAT(CONCAT(parentesco, ':', nombre_completo) ORDER BY parentesco) FROM v_familiar WHERE familia_id = v_fam AND es_tutor));
  CALL _afirmar_carga('Madre "AUSENTE" no se registra', 'Padre', (SELECT GROUP_CONCAT(pa.nombre) FROM familia_integrante fi JOIN cat_parentesco pa ON pa.id = fi.parentesco_id
                      JOIN persona p ON p.id = fi.persona_id WHERE fi.familia_id = v_fam2 AND p.nombres NOT LIKE '%(sin nombre)%'));
  CALL _afirmar_carga('Estado civil "UNION LINRE" → Unión libre', 'Unión libre', (SELECT estado_civil FROM v_familiar WHERE nombre_completo = 'Rosa Gomez Prueba'));
  CALL _afirmar_carga('Una sola visita por familia (no una por hermano)', '1', (SELECT COUNT(*) FROM visita WHERE familia_id = v_fam AND origen = 'EXCEL'));
  CALL _afirmar_carga('Ingreso "$6,500" y apoyo Benito Juárez "1,900"', 'ap_bj:1900.00,ing_fam:6500.00',
                      (SELECT GROUP_CONCAT(CONCAT(c.clave, ':', m.monto) ORDER BY c.clave) FROM visita_monto m JOIN cat_concepto_monto c ON c.id = m.concepto_id WHERE m.visita_id = v_vis));
  CALL _afirmar_carga('Enfermedad pasa a antecedentes', 'ASMA', (SELECT enfermedad FROM visita_antecedente WHERE visita_id = v_vis));

  -- ---- Respuestas del cuestionario ----
  CALL _afirmar_carga('"CEMENTO/TIERRA" son dos respuestas de piso', 'Tierra,Cemento', (SELECT GROUP_CONCAT(respuesta ORDER BY orden) FROM v_respuesta WHERE visita_id = v_vis AND clave = 'piso'));
  CALL _afirmar_carga('Columnas SI/NO de servicios', 'Agua,Luz,Internet', (SELECT GROUP_CONCAT(respuesta ORDER BY orden) FROM v_respuesta WHERE visita_id = v_vis AND clave = 'serv'));
  CALL _afirmar_carga('"IMSS, SIMI" son dos servicios de salud', 'IMSS,SIMI', (SELECT GROUP_CONCAT(respuesta ORDER BY orden) FROM v_respuesta WHERE visita_id = v_vis AND clave = 'med'));
  CALL _afirmar_carga('Equivalencias: "TRERMINADA", "MOTO", "BUENO", "3"', 'Terminada|Motocicleta|Buena|Tres',
                      (SELECT CONCAT_WS('|', MAX(IF(clave = 'car', respuesta, NULL)), MAX(IF(clave = 'auto', respuesta, NULL)),
                                             MAX(IF(clave = 'hig', respuesta, NULL)), MAX(IF(clave = 'comidas', respuesta, NULL)))
                       FROM v_respuesta WHERE visita_id = v_vis));
  CALL _afirmar_carga('Actividad física "FUTBOL" cuenta como Sí', 'Sí', (SELECT respuesta FROM v_respuesta WHERE visita_id = v_vis AND clave = 'fis'));
  CALL _afirmar_carga('Respuesta única: casa de la familia 2 es Propia', 'Propia',
                      (SELECT respuesta FROM v_respuesta r JOIN visita v ON v.id = r.visita_id WHERE v.familia_id = v_fam2 AND r.clave = 'casa'));

  -- ---- Hoja BDI ----
  CALL _afirmar_carga('BDI completa la fecha de nacimiento de la madre', '1988-01-10',
                      (SELECT p.fecha_nacimiento FROM persona p WHERE CONCAT_WS(' ', p.nombres) = 'Rosa Gomez Prueba'));
  CALL _afirmar_carga('Solo edad: fecha aproximada', '1', (SELECT fecha_nac_aprox FROM persona WHERE nombres = 'Juan Prueba Lopez'));
  CALL _afirmar_carga('La abuela listada por dos hermanos se registra una vez', '1',
                      (SELECT COUNT(*) FROM v_familiar WHERE familia_id = v_fam AND parentesco = 'Abuela'));
  CALL _afirmar_carga('Hermana que también es participante no se duplica', '0',
                      (SELECT COUNT(*) FROM v_familiar WHERE familia_id = v_fam AND parentesco = 'Hermana'));
  CALL _afirmar_carga('Madre que solo viene en BDI queda como tutora sin nombre', 'Madre (sin nombre)',
                      (SELECT nombre_completo FROM v_familiar WHERE familia_id = v_fam2 AND parentesco = 'Madre' AND es_tutor));

  -- ---- Hoja histórica ----
  CALL _afirmar_carga('Histórica: 3 periodos cerrados', '3', (SELECT COUNT(*) FROM inscripcion WHERE fecha_baja IS NOT NULL));
  CALL _afirmar_carga('Caso de éxito y escolaridad final', 'Caso de éxito|Preparatoria|Secundaria 3°',
                      (SELECT CONCAT_WS('|', resultado, caso_exito, escolaridad_final) FROM v_historico WHERE nombre_completo = 'Antigua Prueba Ramirez'));
  CALL _afirmar_carga('Riesgos de ingreso y egreso', 'EGRESO:Educativo,INGRESO:Económico',
                      (SELECT GROUP_CONCAT(CONCAT(ir.momento, ':', tr.nombre) ORDER BY ir.momento) FROM inscripcion_riesgo ir JOIN cat_tipo_riesgo tr ON tr.id = ir.tipo_riesgo_id
                       JOIN inscripcion i ON i.id = ir.inscripcion_id JOIN persona p ON p.id = i.participante_id WHERE p.nombres = 'Antigua'));
  CALL _afirmar_carga('Sin fecha de entrada: se reconstruye con los meses', '2019-06-30 2020-06-30',
                      (SELECT CONCAT_WS(' ', fecha_entrada, fecha_salida) FROM v_historico WHERE nombre_completo = 'Viejo Prueba Soto'));
  CALL _afirmar_carga('Causa desconocida → "Otro" con el texto en el motivo', 'Otro|Causa: SE FUE A VIVIR A MARTE',
                      (SELECT CONCAT_WS('|', cb.nombre, i.motivo) FROM inscripcion i JOIN cat_causa_baja cb ON cb.id = i.causa_baja_id
                       JOIN persona p ON p.id = i.participante_id WHERE p.nombres = 'Viejo'));
  CALL _afirmar_carga('Salida anterior a la entrada: se intercambian', '2020-09-01 2022-09-01',
                      (SELECT CONCAT_WS(' ', fecha_entrada, fecha_salida) FROM v_historico WHERE nombre_completo = 'Pasado Prueba Luna'));
  CALL _afirmar_carga('Causa "CAMBIO DE RECIDENCIA" (mal escrita) se reconoce', 'Cambio de domicilio',
                      (SELECT cb.nombre FROM inscripcion i JOIN cat_causa_baja cb ON cb.id = i.causa_baja_id JOIN persona p ON p.id = i.participante_id WHERE p.nombres = 'Pasado'));

  -- ---- Lo que queda para revisar ----
  CALL _afirmar_carga('carga_pendiente tiene exactamente los 9 avisos esperados', '9', (SELECT COUNT(*) FROM carga_pendiente));
  CALL _afirmar_carga('Avisos por columna', 'CAUSA DE BAJA,CURP,FECHA DE SALIDA,GRADO,INGRESO A MESE,No. BECADO,NOMBRE,NOMBRE DE LA MADRE O TUTOR,TECHO',
                      (SELECT GROUP_CONCAT(columna ORDER BY columna) FROM carga_pendiente));

  -- ---- Limpieza: borra la carga ficticia ----
  CALL sp_carga_limpiar();
  CALL _afirmar_carga('sp_carga_limpiar deja la base sin participantes', '0', (SELECT COUNT(*) FROM participante));
  CALL _afirmar_carga('sp_carga_limpiar borra las visitas de Excel', '0', (SELECT COUNT(*) FROM visita WHERE origen = 'EXCEL'));
END //
DELIMITER ;

CALL _pruebas_carga();
SELECT n, prueba, IF(paso, 'PASÓ', '*** FALLÓ ***') AS resultado, esperado, obtenido FROM prueba_carga_resultado ORDER BY n;
SELECT SUM(paso) AS pasaron, SUM(NOT paso) AS fallaron FROM prueba_carga_resultado;
DROP PROCEDURE _afirmar_carga; DROP PROCEDURE _pruebas_carga;

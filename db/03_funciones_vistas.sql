-- =====================================================================
--  03_funciones_vistas.sql — cálculos y vistas de consulta
--  Las vistas son lo que la aplicación lee: SELECT * FROM v_activo ...
--  Todo lo derivado (edad, permanencia, totales) se calcula aquí.
-- =====================================================================
USE mese;
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;   -- misma intercalación que la base

DROP FUNCTION IF EXISTS fn_edad;
DROP FUNCTION IF EXISTS fn_ciclo;
DROP FUNCTION IF EXISTS fn_puede;
DROP FUNCTION IF EXISTS fn_permisos;
DROP FUNCTION IF EXISTS fn_ve_todos;
DROP FUNCTION IF EXISTS fn_ve_participante;
DROP FUNCTION IF EXISTS fn_ve_familia;

DELIMITER //
-- Edad cumplida en una fecha dada (para estadísticas de meses pasados)
CREATE FUNCTION fn_edad(p_nacimiento DATE, p_al DATE) RETURNS SMALLINT
DETERMINISTIC NO SQL
BEGIN
  RETURN IF(p_nacimiento IS NULL, NULL, TIMESTAMPDIFF(YEAR, p_nacimiento, p_al));
END //

-- Ciclo escolar que corresponde a una fecha
CREATE FUNCTION fn_ciclo(p_fecha DATE) RETURNS SMALLINT UNSIGNED
READS SQL DATA
BEGIN
  RETURN (SELECT id FROM cat_ciclo_escolar WHERE p_fecha BETWEEN inicio AND fin LIMIT 1);
END //
DELIMITER ;

-- ---------------------------------------------------------------------
-- Permisos: qué puede ver o hacer cada usuario
-- ---------------------------------------------------------------------
DELIMITER //
-- ¿El usuario (activo) tiene este permiso? La administración principal siempre.
CREATE FUNCTION fn_puede(p_usuario_id SMALLINT UNSIGNED, p_permiso VARCHAR(20)) RETURNS BOOLEAN
READS SQL DATA
RETURN EXISTS (SELECT 1 FROM usuario u WHERE u.id = p_usuario_id AND u.activo
               AND (u.rol = 'ADMIN' OR EXISTS (SELECT 1 FROM usuario_permiso x WHERE x.usuario_id = u.id AND x.permiso = p_permiso))) //

-- Lista de permisos separada por comas, en el orden del catálogo
CREATE FUNCTION fn_permisos(p_usuario_id SMALLINT UNSIGNED) RETURNS VARCHAR(400)
READS SQL DATA
RETURN (SELECT GROUP_CONCAT(c.clave ORDER BY c.orden) FROM cat_permiso c WHERE fn_puede(p_usuario_id, c.clave)) //

-- ¿Ve a todos los participantes o solo a los asignados?
CREATE FUNCTION fn_ve_todos(p_usuario_id SMALLINT UNSIGNED) RETURNS BOOLEAN
READS SQL DATA
RETURN EXISTS (SELECT 1 FROM usuario WHERE id = p_usuario_id AND (rol = 'ADMIN' OR alcance = 'TODOS')) //

CREATE FUNCTION fn_ve_participante(p_usuario_id SMALLINT UNSIGNED, p_participante_id INT UNSIGNED) RETURNS BOOLEAN
READS SQL DATA
RETURN fn_ve_todos(p_usuario_id)
    OR EXISTS (SELECT 1 FROM participante WHERE persona_id = p_participante_id AND trabajadora_id = p_usuario_id) //

-- Una familia se ve si alguno de sus participantes está asignado al usuario
CREATE FUNCTION fn_ve_familia(p_usuario_id SMALLINT UNSIGNED, p_familia_id INT UNSIGNED) RETURNS BOOLEAN
READS SQL DATA
RETURN fn_ve_todos(p_usuario_id)
    OR EXISTS (SELECT 1 FROM participante WHERE familia_id = p_familia_id AND trabajadora_id = p_usuario_id) //
DELIMITER ;

-- ---------------------------------------------------------------------
-- Escolaridad más reciente y periodo más reciente de cada participante
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_escolaridad_actual AS
SELECT x.participante_id, x.ciclo, x.nivel, x.nivel_clave, x.nivel_orden, x.grado, x.escuela, x.carrera, x.grupo, x.turno
FROM (
  SELECT pe.participante_id, c.nombre AS ciclo, ne.nombre AS nivel, ne.clave AS nivel_clave, ne.orden AS nivel_orden,
         pe.grado, es.nombre AS escuela, ca.nombre AS carrera, pe.grupo, t.nombre AS turno,
         ROW_NUMBER() OVER (PARTITION BY pe.participante_id ORDER BY c.inicio DESC) AS rn
  FROM participante_escolaridad pe
  JOIN cat_ciclo_escolar c   ON c.id = pe.ciclo_id
  JOIN cat_nivel_educativo ne ON ne.id = pe.nivel_id
  LEFT JOIN cat_escuela es   ON es.id = pe.escuela_id
  LEFT JOIN cat_carrera ca   ON ca.id = pe.carrera_id
  LEFT JOIN cat_turno t      ON t.id = pe.turno_id
) x WHERE x.rn = 1;

CREATE OR REPLACE VIEW v_inscripcion_actual AS
SELECT x.* FROM (
  SELECT i.*, ROW_NUMBER() OVER (PARTITION BY i.participante_id ORDER BY i.fecha_ingreso DESC, i.id DESC) AS rn,
         MIN(i.fecha_ingreso) OVER (PARTITION BY i.participante_id) AS primer_ingreso,
         COUNT(*) OVER (PARTITION BY i.participante_id) AS periodos
  FROM inscripcion i
) x WHERE x.rn = 1;

-- Tutor principal de cada familia (madre primero, luego padre, luego otros tutores)
CREATE OR REPLACE VIEW v_tutor_principal AS
SELECT x.familia_id, x.persona_id, x.nombre_completo, x.parentesco, x.telefono FROM (
  SELECT fi.familia_id, p.id AS persona_id, p.nombre_completo, pa.nombre AS parentesco, p.telefono,
         ROW_NUMBER() OVER (PARTITION BY fi.familia_id ORDER BY FIELD(pa.nombre,'Madre','Padre') = 0, FIELD(pa.nombre,'Madre','Padre'), p.id) AS rn
  FROM familia_integrante fi
  JOIN persona p ON p.id = fi.persona_id
  JOIN cat_parentesco pa ON pa.id = fi.parentesco_id
  WHERE fi.es_tutor
) x WHERE x.rn = 1;

-- ---------------------------------------------------------------------
-- Participantes (todos) con su situación actual
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_participante AS
SELECT
  p.id                    AS persona_id,
  p.nombre_completo,
  p.nombres, p.apellido_paterno, p.apellido_materno,
  p.genero,
  p.fecha_nacimiento,
  fn_edad(p.fecha_nacimiento, CURDATE()) AS edad,
  p.curp,
  ts.nombre               AS tipo_sangre,
  pt.familia_id,
  pt.numero_becado,
  pt.grupo_beca,
  pt.trabajadora_id,
  u.nombre                AS trabajadora_social,
  p.telefono,
  f.correo                AS correo_familia,
  f.aviso_privacidad,
  col.nombre              AS colonia,
  col.codigo_postal,
  CONCAT_WS(' ', f.calle, f.numero_ext) AS domicilio,
  tp.nombre_completo      AS tutor,
  tp.parentesco           AS parentesco_tutor,
  COALESCE(tp.telefono, f.telefono) AS telefono_tutor,
  ea.nivel, ea.nivel_clave, ea.grado, ea.escuela, ea.carrera, ea.grupo, ea.turno, ea.ciclo,
  ia.primer_ingreso,
  ia.fecha_ingreso,
  ia.fecha_baja,
  ia.periodos,
  CASE WHEN ia.participante_id IS NULL THEN 'CANDIDATO'
       WHEN ia.fecha_baja IS NULL AND NOT ia.sin_fechas THEN 'ACTIVO' ELSE 'BAJA' END AS estado,
  TIMESTAMPDIFF(MONTH, ia.fecha_ingreso, COALESCE(ia.fecha_baja, CURDATE())) AS meses_permanencia,
  TIMESTAMPDIFF(YEAR,  ia.fecha_ingreso, COALESCE(ia.fecha_baja, CURDATE())) AS anios_permanencia,
  (SELECT GROUP_CONCAT(cp.nombre ORDER BY cp.nombre SEPARATOR ' / ')
     FROM participante_beca pb JOIN cat_patrocinador cp ON cp.id = pb.patrocinador_id
    WHERE pb.participante_id = pt.persona_id AND (pb.hasta IS NULL OR pb.hasta >= CURDATE())) AS becas
FROM participante pt
JOIN persona p                 ON p.id = pt.persona_id
JOIN familia f                 ON f.id = pt.familia_id
LEFT JOIN cat_colonia col      ON col.id = f.colonia_id
LEFT JOIN cat_tipo_sangre ts   ON ts.id = p.tipo_sangre_id
LEFT JOIN usuario u            ON u.id = pt.trabajadora_id
LEFT JOIN v_tutor_principal tp ON tp.familia_id = pt.familia_id
LEFT JOIN v_escolaridad_actual ea ON ea.participante_id = pt.persona_id
LEFT JOIN v_inscripcion_actual ia ON ia.participante_id = pt.persona_id;

-- Panel "Participantes activos"
CREATE OR REPLACE VIEW v_activo AS
SELECT * FROM v_participante WHERE estado = 'ACTIVO';

-- Panel "Bajas": su periodo más reciente está cerrado
CREATE OR REPLACE VIEW v_baja AS
SELECT vp.persona_id, vp.nombre_completo, vp.genero, vp.edad, vp.nivel, vp.grado, vp.colonia,
       ia.fecha_ingreso, ia.fecha_baja, cb.nombre AS causa_baja, ce.nombre AS causa_estadistica, ia.motivo,
       ia.id AS inscripcion_id, vp.familia_id, vp.trabajadora_id, vp.trabajadora_social,
       cx.nombre AS caso_exito, ct.nombre AS certificado, nr.nombre AS nivel_riesgo_egreso
FROM v_participante vp
JOIN v_inscripcion_actual ia ON ia.participante_id = vp.persona_id
LEFT JOIN cat_causa_baja cb ON cb.id = ia.causa_baja_id
LEFT JOIN cat_causa_baja_estadistica ce ON ce.id = ia.causa_estadistica_id
LEFT JOIN cat_caso_exito cx ON cx.id = ia.caso_exito_id
LEFT JOIN cat_certificado ct ON ct.id = ia.certificado_id
LEFT JOIN cat_nivel_riesgo nr ON nr.id = ia.riesgo_egreso_id
WHERE vp.estado = 'BAJA';

-- Panel "Registro histórico": todas las personas que han pasado por MESE
-- (una sola agregación por participante; sin subconsultas por renglón)
CREATE OR REPLACE VIEW v_historico AS
SELECT
  p.id AS persona_id, p.nombre_completo, p.genero,
  a.fecha_entrada,
  IF(a.abiertos > 0, NULL, a.fecha_salida) AS fecha_salida,
  a.meses_permanencia,
  fn_edad(p.fecha_nacimiento, a.fecha_entrada) AS edad_al_entrar,
  fn_edad(p.fecha_nacimiento, IF(a.abiertos > 0, CURDATE(), a.fecha_salida)) AS edad_al_salir,
  CASE WHEN a.abiertos > 0 THEN 'Sigue activo'
       WHEN a.exito_orden IS NOT NULL THEN 'Caso de éxito'
       ELSE 'No concluyó' END AS resultado,
  ce.nombre AS caso_exito,
  CONCAT(ne.nombre, ' ', u.grado_final, '°') AS escolaridad_final,
  ne.nombre AS nivel_final, u.grado_final, ni.nombre AS nivel_inicial, u.grado_inicial,
  cb.nombre AS causa_baja, cbe.nombre AS causa_estadistica, u.motivo, ct.nombre AS certificado,
  ri.nombre AS nivel_riesgo_ingreso, re.nombre AS nivel_riesgo_egreso,
  col.nombre AS colonia, CONCAT_WS(' ', f.calle, f.numero_ext) AS domicilio, f.telefono,
  pt.familia_id, pt.trabajadora_id
FROM (
  SELECT i.participante_id,
         MIN(i.fecha_ingreso) AS fecha_entrada,
         MAX(i.fecha_baja) AS fecha_salida,
         SUM(i.abierta IS NOT NULL) AS abiertos,
         SUM(TIMESTAMPDIFF(MONTH, i.fecha_ingreso, COALESCE(i.fecha_baja, IF(i.sin_fechas, NULL, CURDATE())))) AS meses_permanencia,
         MAX(c.orden) AS exito_orden
  FROM inscripcion i LEFT JOIN cat_caso_exito c ON c.id = i.caso_exito_id
  GROUP BY i.participante_id
) a
JOIN participante pt ON pt.persona_id = a.participante_id
JOIN persona p ON p.id = pt.persona_id
JOIN familia f ON f.id = pt.familia_id
LEFT JOIN cat_colonia col ON col.id = f.colonia_id
LEFT JOIN cat_caso_exito ce ON ce.orden = a.exito_orden
LEFT JOIN v_inscripcion_actual u ON u.participante_id = a.participante_id
LEFT JOIN cat_nivel_educativo ne ON ne.id = u.nivel_final_id
LEFT JOIN cat_nivel_educativo ni ON ni.id = u.nivel_inicial_id
LEFT JOIN cat_causa_baja cb ON cb.id = u.causa_baja_id
LEFT JOIN cat_causa_baja_estadistica cbe ON cbe.id = u.causa_estadistica_id
LEFT JOIN cat_certificado ct ON ct.id = u.certificado_id
LEFT JOIN cat_nivel_riesgo ri ON ri.id = u.riesgo_ingreso_id
LEFT JOIN cat_nivel_riesgo re ON re.id = u.riesgo_egreso_id;

-- Panel "Familiares": tutores e integrantes de la familia
CREATE OR REPLACE VIEW v_familiar AS
SELECT p.id AS persona_id, p.nombre_completo, p.genero, p.fecha_nacimiento, fn_edad(p.fecha_nacimiento, CURDATE()) AS edad,
       pa.nombre AS parentesco, fi.es_tutor, fi.vive_en_casa, fi.familia_id,
       oc.nombre AS ocupacion, ne.nombre AS escolaridad, p.escolaridad_grado, ec.nombre AS estado_civil, p.telefono,
       (SELECT GROUP_CONCAT(pp.nombres ORDER BY pp.nombres SEPARATOR ', ')
          FROM participante x JOIN persona pp ON pp.id = x.persona_id WHERE x.familia_id = fi.familia_id) AS participantes
FROM familia_integrante fi
JOIN persona p ON p.id = fi.persona_id
JOIN cat_parentesco pa ON pa.id = fi.parentesco_id
LEFT JOIN cat_ocupacion oc ON oc.id = p.ocupacion_id
LEFT JOIN cat_nivel_educativo ne ON ne.id = p.escolaridad_nivel_id
LEFT JOIN cat_estado_civil ec ON ec.id = p.estado_civil_id;

-- ---------------------------------------------------------------------
-- Visitas domiciliarias
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_visita_resumen AS
SELECT
  v.id AS visita_id, v.uuid_cliente, v.fecha, v.estado, v.familia_id, v.participante_id,
  p.nombre_completo AS participante,
  u.nombre AS trabajadora_social,
  col.nombre AS colonia,
  COALESCE(ing.ingreso, 0) + COALESCE(mon.ingreso_declarado, 0) AS ingreso_total,
  COALESCE(mon.apoyos, 0)  AS apoyos_total,
  COALESCE(mon.egresos, 0) AS egreso_total,
  COALESCE(ing.ingreso, 0) + COALESCE(mon.ingreso_declarado, 0) + COALESCE(mon.apoyos, 0) - COALESCE(mon.egresos, 0) AS balance,
  COALESCE(NULLIF(ing.integrantes, 0), v.num_integrantes) AS integrantes,
  ROUND((COALESCE(ing.ingreso, 0) + COALESCE(mon.ingreso_declarado, 0) + COALESCE(mon.apoyos, 0)) / NULLIF(COALESCE(NULLIF(ing.integrantes, 0), v.num_integrantes), 0) / 30, 2) AS ingreso_diario_por_integrante
FROM visita v
JOIN familia f ON f.id = v.familia_id
LEFT JOIN cat_colonia col ON col.id = f.colonia_id
LEFT JOIN persona p ON p.id = v.participante_id
LEFT JOIN usuario u ON u.id = v.usuario_id
LEFT JOIN (SELECT visita_id, SUM(ingreso_mensual) AS ingreso, COUNT(*) AS integrantes FROM visita_integrante GROUP BY visita_id) ing ON ing.visita_id = v.id
LEFT JOIN (SELECT vm.visita_id, SUM(IF(c.tipo = 'INGRESO', vm.monto, 0)) AS ingreso_declarado, SUM(IF(c.tipo = 'APOYO', vm.monto, 0)) AS apoyos, SUM(IF(c.tipo = 'EGRESO', vm.monto, 0)) AS egresos
             FROM visita_monto vm JOIN cat_concepto_monto c ON c.id = vm.concepto_id GROUP BY vm.visita_id) mon ON mon.visita_id = v.id;

-- Respuestas en forma legible (una fila por respuesta)
CREATE OR REPLACE VIEW v_respuesta AS
SELECT r.visita_id, q.seccion_id, s.nombre AS seccion, q.clave, q.texto AS pregunta,
       COALESCE(o.etiqueta, CONCAT('Otro: ', r.texto_otro)) AS respuesta, o.orden
FROM visita_respuesta r
JOIN cat_pregunta q ON q.id = r.pregunta_id
JOIN cat_seccion s  ON s.id = q.seccion_id
LEFT JOIN cat_opcion o ON o.id = r.opcion_id;

-- Situación actual de cada familia = su visita terminada más reciente
CREATE OR REPLACE VIEW v_familia_actual AS
SELECT vr.*,
  (SELECT GROUP_CONCAT(x.respuesta ORDER BY x.orden SEPARATOR ', ') FROM v_respuesta x WHERE x.visita_id = vr.visita_id AND x.clave = 'nivel_pobreza') AS nivel_pobreza,
  (SELECT GROUP_CONCAT(x.respuesta ORDER BY x.orden SEPARATOR ', ') FROM v_respuesta x WHERE x.visita_id = vr.visita_id AND x.clave = 'casa')          AS casa,
  (SELECT GROUP_CONCAT(x.respuesta ORDER BY x.orden SEPARATOR ', ') FROM v_respuesta x WHERE x.visita_id = vr.visita_id AND x.clave = 'serv')          AS servicios,
  (SELECT GROUP_CONCAT(x.respuesta ORDER BY x.orden SEPARATOR ', ') FROM v_respuesta x WHERE x.visita_id = vr.visita_id AND x.clave = 'hacinamiento')  AS hacinamiento,
  (SELECT GROUP_CONCAT(x.respuesta ORDER BY x.orden SEPARATOR ', ') FROM v_respuesta x WHERE x.visita_id = vr.visita_id AND x.clave = 'med')           AS servicio_medico
FROM v_visita_resumen vr
JOIN (SELECT familia_id, MAX(fecha) AS fecha FROM visita WHERE estado = 'COMPLETA' GROUP BY familia_id) ult
  ON ult.familia_id = vr.familia_id AND ult.fecha = vr.fecha
WHERE vr.estado = 'COMPLETA'
  AND vr.visita_id = (SELECT MAX(v2.id) FROM visita v2 WHERE v2.familia_id = vr.familia_id AND v2.fecha = vr.fecha AND v2.estado = 'COMPLETA');

-- ---------------------------------------------------------------------
-- Usuarios de la página (sin contraseñas) para la pantalla de administración
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_usuario AS
-- Incluye a las trabajadoras que llegaron con el Excel y aún no tienen acceso (login NULL).
-- El usuario 1 es "Sistema (importación)" y no es una persona.
SELECT u.id, u.nombre, u.correo, u.rol, IF(u.rol = 'ADMIN', 'TODOS', u.alcance) AS alcance, u.activo,
       a.login, a.usuario_id IS NOT NULL AS tiene_acceso, COALESCE(a.debe_cambiar, FALSE) AS debe_cambiar,
       a.ultimo_acceso, COALESCE(a.bloqueado_hasta > NOW(), FALSE) AS bloqueado,
       (SELECT COUNT(*) FROM sesion s WHERE s.usuario_id = u.id AND s.cerrada_en IS NULL) AS sesiones_abiertas,
       (SELECT COUNT(*) FROM participante pt JOIN v_inscripcion_actual ia ON ia.participante_id = pt.persona_id
         WHERE pt.trabajadora_id = u.id AND ia.fecha_baja IS NULL AND NOT ia.sin_fechas) AS asignados,
       fn_permisos(u.id) AS permisos
FROM usuario u
LEFT JOIN usuario_acceso a ON a.usuario_id = u.id
WHERE u.id > 1;

-- Roles con sus permisos sugeridos, para la pantalla de usuarios
CREATE OR REPLACE VIEW v_rol AS
SELECT r.clave, r.nombre, r.alcance, r.orden,
       (SELECT GROUP_CONCAT(c.clave ORDER BY c.orden) FROM cat_rol_permiso rp JOIN cat_permiso c ON c.clave = rp.permiso
         WHERE rp.rol = r.clave) AS permisos
FROM cat_rol r;

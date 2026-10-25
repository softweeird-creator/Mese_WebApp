import type { FastifyInstance } from 'fastify';
import { llamar, type Fila } from '../db.js';
import { requiereSesion } from '../sesion.js';

// Secciones de la página y el permiso que pide cada una. sp_panel vuelve a revisar el
// permiso y filtra por alcance (todos o solo los asignados), así que la regla vive en la base.
const PANELES = { activos: 'VER_ACTIVOS', historico: 'VER_HISTORICO', familiares: 'VER_FAMILIARES', bajas: 'VER_BAJAS' } as const;
type Panel = keyof typeof PANELES;

// La página usa las mismas palabras que el Excel; la base guarda los catálogos completos.
const NIVEL: Record<string, string> = { Preparatoria: 'Bachillerato', 'Preparatoria abierta': 'Bachillerato', 'Secundaria abierta': 'Secundaria' };
const PARENTESCO: Record<string, string> = {
  'Tutor(a)': 'Tutor', Abuela: 'Abuelo(a)', Abuelo: 'Abuelo(a)', Bisabuela: 'Bisabuelo(a)', Bisabuelo: 'Bisabuelo(a)',
  Tía: 'Tío(a)', Tío: 'Tío(a)', Hermana: 'Hermano(a)', Hermano: 'Hermano(a)', Prima: 'Primo(a)', Primo: 'Primo(a)',
  Sobrina: 'Sobrino(a)', Sobrino: 'Sobrino(a)', Cuñada: 'Cuñado(a)', Cuñado: 'Cuñado(a)',
};
const HASTA_PRIMARIA = ['Preescolar', 'Primaria', 'INEA', 'Educación especial'];

const t = (v: unknown) => (v == null ? '' : String(v));
const n = (v: unknown) => (v == null || v === '' ? '' : Number(v));
const genero = (v: unknown) => (v === 'F' ? 'Mujer' : v === 'M' ? 'Hombre' : '');
const nivel = (v: unknown) => (v == null ? '' : NIVEL[String(v)] ?? String(v));
const anio = (f: unknown) => (f ? Number(String(f).slice(0, 4)) : '');
const mes = (f: unknown) => (f ? Number(String(f).slice(5, 7)) : '');
const sangre = (v: unknown) => t(v).replace('-', '−');
const escolaridad = (v: unknown) => (v == null ? '' : HASTA_PRIMARIA.includes(String(v)) ? 'Hasta primaria' : String(v).startsWith('Secundaria') ? 'Secundaria' : 'Preparatoria o más');

/** Renglones de la base → las claves cortas que usa la página (las mismas del modo demostración). */
const MAPEO: Record<Panel, (f: Fila) => Record<string, unknown>> = {
  activos: (f) => ({
    id: Number(f.persona_id), n: t(f.nombre_completo), g: genero(f.genero), ed: n(f.edad), nv: nivel(f.nivel), gr: n(f.grado),
    y: anio(f.fecha_ingreso), m: mes(f.fecha_ingreso), col: t(f.colonia), esc: t(f.escuela), mad: t(f.tutor), tel: t(f.telefono_tutor),
    curp: t(f.curp), fn: t(f.fecha_nacimiento), sangre: sangre(f.tipo_sangre), car: t(f.carrera), grp: t(f.grupo), tur: t(f.turno),
    ts: t(f.trabajadora_social), tsid: f.trabajadora_id == null ? null : Number(f.trabajadora_id), nb: n(f.numero_becado), gb: n(f.grupo_beca),
    pat: t(f.becas), telp: t(f.telefono), mail: t(f.correo_familia), av: f.aviso_privacidad ? 'Firmado' : 'Pendiente',
  }),
  historico: (f) => ({
    id: Number(f.persona_id), n: t(f.nombre_completo), g: genero(f.genero), nv: nivel(f.nivel_final), gr: n(f.grado_final),
    nvi: nivel(f.nivel_inicial), gri: n(f.grado_inicial), y: anio(f.fecha_entrada), fe: t(f.fecha_entrada), fs: t(f.fecha_salida),
    eei: n(f.edad_al_entrar), ees: n(f.edad_al_salir), res: t(f.resultado), cx: t(f.caso_exito), ct: t(f.certificado),
    cb: t(f.causa_baja), ce: t(f.causa_estadistica), mo: t(f.motivo), rni: t(f.nivel_riesgo_ingreso), rne: t(f.nivel_riesgo_egreso),
    rti: t(f.tipo_riesgo_ingreso), rte: t(f.tipo_riesgo_egreso),
    dir: t(f.domicilio), col: t(f.colonia), tel: t(f.telefono),
  }),
  familiares: (f) => ({
    id: Number(f.persona_id), n: t(f.nombre_completo), par: PARENTESCO[t(f.parentesco)] ?? t(f.parentesco), tutor: Boolean(f.es_tutor),
    hijo: t(f.participantes), esl: escolaridad(f.escolaridad), oc: t(f.ocupacion), ing: '', tel: t(f.telefono),
    g: genero(f.genero), fn: t(f.fecha_nacimiento), ed: n(f.edad),
  }),
  bajas: (f) => ({
    id: Number(f.persona_id), n: t(f.nombre_completo), g: genero(f.genero), nv: nivel(f.nivel), gr: n(f.grado),
    mot: t(f.causa_baja), ce: t(f.causa_estadistica), cx: t(f.caso_exito), ct: t(f.certificado), rne: t(f.nivel_riesgo_egreso),
    mo: t(f.motivo), fb: t(f.fecha_baja), mb: mes(f.fecha_baja), y: anio(f.fecha_baja), col: t(f.colonia), ts: t(f.trabajadora_social),
  }),
};

export async function rutasDatos(app: FastifyInstance) {
  // Todas las secciones que la persona puede ver, en una sola petición. Las que no puede ver no vienen.
  app.get('/api/datos', { preHandler: requiereSesion }, async (req) => {
    const u = req.usuario!;
    const datos: Partial<Record<Panel, Record<string, unknown>[]>> = {};
    for (const [panel, permiso] of Object.entries(PANELES) as [Panel, string][]) {
      if (!u.permisos.includes(permiso)) continue;
      datos[panel] = (await llamar(app.db, 'sp_panel', [u.id, panel], u.id)).map(MAPEO[panel]);
    }
    return { alcance: u.alcance, ...datos };
  });
}

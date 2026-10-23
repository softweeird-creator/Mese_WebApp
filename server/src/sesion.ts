import { createHash, randomBytes } from 'node:crypto';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { config } from './config.js';
import { llamar } from './db.js';

export const COOKIE = 'mese_sesion';
export const ROLES = ['TRABAJO_SOCIAL', 'COORDINACION', 'CONSULTA', 'ADMIN'] as const;
export type Rol = (typeof ROLES)[number];

export interface Usuario {
  id: number;
  nombre: string;
  rol: Rol;
  login: string;
  debeCambiar: boolean;
  /** TODOS = ve a todos los participantes; ASIGNADOS = solo a los suyos y sus familias */
  alcance: 'TODOS' | 'ASIGNADOS';
  /** Claves de cat_permiso: VER_ACTIVOS, EDITAR... (la administración principal tiene todas) */
  permisos: string[];
}

/** Lista "A,B,C" de la base a arreglo */
export const lista = (v: unknown) => (v ? String(v).split(',').filter(Boolean) : []);

/** Renglón de sp_acceso_buscar o sp_sesion_validar → usuario para la página */
export const aUsuario = (f: Record<string, unknown>): Usuario => ({
  id: Number(f.id),
  nombre: String(f.nombre),
  rol: f.rol as Rol,
  login: String(f.login),
  debeCambiar: Boolean(f.debe_cambiar),
  alcance: f.alcance === 'ASIGNADOS' ? 'ASIGNADOS' : 'TODOS',
  permisos: lista(f.permisos),
});

declare module 'fastify' {
  interface FastifyRequest {
    usuario?: Usuario;
    tokenHash?: string;
  }
}

/** Valor que va en la cookie. En la base solo se guarda su SHA-256. */
export const nuevoToken = () => randomBytes(32).toString('base64url');
export const hashToken = (t: string) => createHash('sha256').update(t).digest('hex');

export function ponerCookie(reply: FastifyReply, token: string) {
  // Sin fecha de vencimiento en la base: la sesión dura hasta salir. La cookie se guarda 10 años.
  reply.setCookie(COOKIE, token, {
    path: '/',
    httpOnly: true,
    sameSite: 'strict',
    secure: config.produccion,
    maxAge: 60 * 60 * 24 * 365 * 10,
  });
}

export function quitarCookie(reply: FastifyReply) {
  reply.clearCookie(COOKIE, { path: '/' });
}

/** Lee la cookie y deja en req.usuario a quien está conectado (o nada). */
export async function leerSesion(req: FastifyRequest) {
  const token = req.cookies[COOKIE];
  if (!token) return;
  const tokenHash = hashToken(token);
  const [f] = await llamar(req.server.db, 'sp_sesion_validar', [tokenHash]);
  if (!f) return;
  req.tokenHash = tokenHash;
  req.usuario = aUsuario(f);
}

/** Para rutas que piden haber entrado. Con contraseña temporal solo se permite cambiarla. */
export async function requiereSesion(req: FastifyRequest, reply: FastifyReply) {
  if (!req.usuario) return reply.code(401).send({ error: 'Inicie sesión para continuar.' });
  if (req.usuario.debeCambiar && req.routeOptions.url !== '/api/clave') {
    return reply.code(403).send({ error: 'Primero cambie su contraseña temporal.', debeCambiar: true });
  }
}

export async function requiereAdmin(req: FastifyRequest, reply: FastifyReply) {
  await requiereSesion(req, reply);
  if (reply.sent) return;
  if (req.usuario!.rol !== 'ADMIN') return reply.code(403).send({ error: 'Solo la administración puede hacer esto.' });
}

/** Para rutas que piden un permiso (la base lo vuelve a revisar en sp_panel). */
export const requierePermiso = (permiso: string) => async (req: FastifyRequest, reply: FastifyReply) => {
  await requiereSesion(req, reply);
  if (reply.sent) return;
  if (!req.usuario!.permisos.includes(permiso)) return reply.code(403).send({ error: 'No tiene permiso para esto. Hable con la administración de MESE.' });
};

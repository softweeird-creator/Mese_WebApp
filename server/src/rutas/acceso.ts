import argon2 from 'argon2';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { ErrorUsuario, llamar } from '../db.js';
import { aUsuario, hashToken, nuevoToken, ponerCookie, quitarCookie, requiereSesion } from '../sesion.js';

export const claveNueva = z.string().min(6, 'La contraseña debe tener al menos 6 caracteres.').max(200, 'La contraseña es demasiado larga.');

// Se compara contra este hash cuando el usuario no existe, para tardar lo mismo y no revelar qué usuarios hay.
const HASH_FALSO = await argon2.hash('no-es-una-contrasena');

export async function rutasAcceso(app: FastifyInstance) {
  const datosEntrada = z.object({
    usuario: z.string().trim().min(1, 'Escriba su usuario.').max(40),
    clave: z.string().min(1, 'Escriba su contraseña.').max(200),
  });

  app.post('/api/entrar', { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (req, reply) => {
    const { usuario, clave } = datosEntrada.parse(req.body);
    const [u] = await llamar(app.db, 'sp_acceso_buscar', [usuario]);
    const correcta = await argon2.verify(u ? String(u.clave_hash) : HASH_FALSO, clave);
    if (!u) throw new ErrorUsuario('Usuario o contraseña incorrectos.', 401);
    if (u.bloqueado) throw new ErrorUsuario('Demasiados intentos fallidos. Espere 15 minutos e intente de nuevo.', 429);
    if (!correcta) {
      await llamar(app.db, 'sp_acceso_registrar', [u.id, false, null, null, null]);
      throw new ErrorUsuario('Usuario o contraseña incorrectos.', 401);
    }
    if (!u.activo) throw new ErrorUsuario('Su usuario está desactivado. Hable con la administración de MESE.', 403);
    const token = nuevoToken();
    await llamar(app.db, 'sp_acceso_registrar', [u.id, true, hashToken(token), req.headers['user-agent'] ?? null, req.ip], Number(u.id));
    ponerCookie(reply, token);
    return { usuario: aUsuario(u) };
  });

  app.post('/api/salir', async (req, reply) => {
    if (req.tokenHash) await llamar(app.db, 'sp_sesion_cerrar', [req.tokenHash], req.usuario?.id ?? null);
    quitarCookie(reply);
    return { ok: true };
  });

  // Quién está conectado. 401 = hay servidor pero falta iniciar sesión.
  app.get('/api/yo', async (req, reply) => {
    if (!req.usuario) return reply.code(401).send({ error: 'Inicie sesión para continuar.' });
    return { usuario: req.usuario };
  });

  const datosClave = z.object({ actual: z.string().min(1, 'Escriba su contraseña actual.').max(200), nueva: claveNueva });

  // Cambiar la propia contraseña (también la temporal del primer ingreso). Las demás sesiones se cierran.
  app.post('/api/clave', { preHandler: requiereSesion, config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (req) => {
    const { actual, nueva } = datosClave.parse(req.body);
    const u = req.usuario!;
    const [f] = await llamar(app.db, 'sp_acceso_buscar', [u.login]);
    if (!f || !(await argon2.verify(String(f.clave_hash), actual))) throw new ErrorUsuario('La contraseña actual no es correcta.');
    if (actual === nueva) throw new ErrorUsuario('La nueva contraseña debe ser distinta de la actual.');
    await llamar(app.db, 'sp_usuario_clave', [u.id, await argon2.hash(nueva), false, req.tokenHash], u.id);
    return { usuario: { ...u, debeCambiar: false } };
  });
}

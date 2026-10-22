import argon2 from 'argon2';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { consultar, llamar, llamarConSalida } from '../db.js';
import { ROLES, requiereAdmin } from '../sesion.js';
import { claveNueva } from './acceso.js';

/** Administración de usuarios de la página (solo rol ADMIN). */
export async function rutasUsuarios(app: FastifyInstance) {
  const id = z.object({ id: z.coerce.number().int().positive() });
  const datos = z.object({
    nombre: z.string().trim().min(1, 'Escriba el nombre de la persona.').max(100),
    usuario: z.string().trim().toLowerCase().min(3, 'El usuario debe tener al menos 3 letras.').max(40),
    correo: z.string().trim().email('El correo no es válido.').max(120).nullish().or(z.literal('')),
    rol: z.enum(ROLES, { errorMap: () => ({ message: 'Elija un rol de la lista.' }) }),
  });

  app.addHook('preHandler', requiereAdmin);

  app.get('/api/usuarios', async () => ({
    usuarios: await consultar(app.db, 'SELECT * FROM v_usuario ORDER BY activo DESC, nombre'),
  }));

  app.post('/api/usuarios', async (req, reply) => {
    const d = datos.extend({ clave: claveNueva }).parse(req.body);
    const nuevo = await llamarConSalida(app.db, 'sp_usuario_guardar',
      [null, d.nombre, d.usuario, d.correo || null, d.rol, await argon2.hash(d.clave)], req.usuario!.id);
    return reply.code(201).send({ id: Number(nuevo) });
  });

  app.put('/api/usuarios/:id', async (req) => {
    const { id: uid } = id.parse(req.params);
    const d = datos.extend({ clave: claveNueva.optional() }).parse(req.body);
    await llamarConSalida(app.db, 'sp_usuario_guardar',
      [uid, d.nombre, d.usuario, d.correo || null, d.rol, d.clave ? await argon2.hash(d.clave) : null], req.usuario!.id);
    return { ok: true };
  });

  // Contraseña temporal: la persona tendrá que cambiarla al entrar. Cierra todas sus sesiones.
  app.post('/api/usuarios/:id/clave', async (req) => {
    const { id: uid } = id.parse(req.params);
    const { clave } = z.object({ clave: claveNueva }).parse(req.body);
    await llamar(app.db, 'sp_usuario_clave', [uid, await argon2.hash(clave), true, null], req.usuario!.id);
    return { ok: true };
  });

  app.post('/api/usuarios/:id/activo', async (req) => {
    const { id: uid } = id.parse(req.params);
    const { activo } = z.object({ activo: z.boolean() }).parse(req.body);
    await llamar(app.db, 'sp_usuario_activar', [uid, activo], req.usuario!.id);
    return { ok: true };
  });

  app.post('/api/usuarios/:id/cerrar-sesiones', async (req) => {
    const { id: uid } = id.parse(req.params);
    await llamar(app.db, 'sp_usuario_cerrar_sesiones', [uid], req.usuario!.id);
    return { ok: true };
  });
}

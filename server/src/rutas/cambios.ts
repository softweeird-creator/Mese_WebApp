import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { llamar, llamarConSalida } from '../db.js';
import { requiereSesion } from '../sesion.js';

// Agregar, editar, dar de baja y reactivar desde la página (fase 3). El servidor solo pasa lo
// capturado: los procedimientos sp_pagina_* revisan permiso y alcance y validan cada dato.
const SECCION = { activos: 'sp_pagina_activo', familiares: 'sp_pagina_familiar', historico: 'sp_pagina_historico' } as const;

const id = z.object({ id: z.coerce.number().int().positive() });
const seccion = z.object({ seccion: z.enum(['activos', 'familiares', 'historico'], { errorMap: () => ({ message: 'Esa sección no existe.' }) }) });
// Mismas claves cortas que usa la página (n, curp, nv...): textos, números o vacío
const registro = z.record(z.string().regex(/^[a-z]{1,6}$/), z.union([z.string().max(2000), z.number(), z.boolean(), z.null()]))
  .refine((r) => Object.keys(r).length <= 60, 'Demasiados datos.');

export async function rutasCambios(app: FastifyInstance) {
  app.addHook('preHandler', requiereSesion);

  app.post('/api/:seccion', async (req, reply) => {
    const { seccion: s } = seccion.parse(req.params);
    const datos = registro.parse(req.body);
    const nuevo = await llamarConSalida(app.db, SECCION[s], [req.usuario!.id, null, JSON.stringify(datos)], req.usuario!.id);
    return reply.code(201).send({ id: Number(nuevo) });
  });

  app.put('/api/:seccion/:id', async (req) => {
    const { seccion: s } = seccion.parse(req.params);
    const { id: pid } = id.parse(req.params);
    const datos = registro.parse(req.body);
    await llamarConSalida(app.db, SECCION[s], [req.usuario!.id, pid, JSON.stringify(datos)], req.usuario!.id);
    return { id: pid };
  });

  app.post('/api/activos/:id/baja', async (req) => {
    const { id: pid } = id.parse(req.params);
    await llamar(app.db, 'sp_pagina_baja', [req.usuario!.id, pid, JSON.stringify(registro.parse(req.body))], req.usuario!.id);
    return { ok: true };
  });

  app.post('/api/bajas/:id/reactivar', async (req) => {
    const { id: pid } = id.parse(req.params);
    await llamar(app.db, 'sp_pagina_reactivar', [req.usuario!.id, pid], req.usuario!.id);
    return { ok: true };
  });
}

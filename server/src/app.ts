import cookie from '@fastify/cookie';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import fstatic from '@fastify/static';
import Fastify, { type FastifyInstance } from 'fastify';
import type { Pool } from 'mysql2/promise';
import { ZodError } from 'zod';
import { config } from './config.js';
import { ErrorUsuario } from './db.js';
import { rutasAcceso } from './rutas/acceso.js';
import { rutasCambios } from './rutas/cambios.js';
import { rutasDatos } from './rutas/datos.js';
import { rutasUsuarios } from './rutas/usuarios.js';
import { leerSesion } from './sesion.js';

declare module 'fastify' {
  interface FastifyInstance {
    db: Pool;
  }
}

// Únicos archivos públicos: la página y lo que necesita para instalarse en el teléfono.
const ARCHIVOS: Record<string, string> = {
  '/': 'index.html',
  '/index.html': 'index.html',
  '/sw.js': 'sw.js',
  '/manifest.webmanifest': 'manifest.webmanifest',
  '/icon-192.png': 'icon-192.png',
  '/icon-512.png': 'icon-512.png',
  '/logo.png': 'logo.png',
};

export async function crearApp(db: Pool, opciones: { registro?: boolean } = {}): Promise<FastifyInstance> {
  const app = Fastify({ logger: opciones.registro ?? false, trustProxy: config.detrasDeProxy, bodyLimit: 10 * 1024 * 1024 });
  app.decorate('db', db);

  // La página usa estilos y scripts dentro del mismo archivo; por eso no se activa la política de contenido.
  await app.register(helmet, { contentSecurityPolicy: false, crossOriginEmbedderPolicy: false });
  await app.register(cookie);
  await app.register(rateLimit, { global: false });
  await app.register(fstatic, { root: config.raizPagina, serve: false });

  // Peticiones que cambian datos solo desde la misma página (además de la cookie SameSite=Strict)
  app.addHook('onRequest', async (req, reply) => {
    if (!req.url.startsWith('/api/')) return;
    const origen = req.headers.origin;
    if (origen && !['GET', 'HEAD'].includes(req.method)) {
      let host = '';
      try { host = new URL(origen).host; } catch { /* origen inválido */ }
      if (host !== req.headers.host) return reply.code(403).send({ error: 'Petición rechazada: no viene de la página de MESE.' });
    }
    await leerSesion(req);
  });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof ErrorUsuario) return reply.code(err.status).send({ error: err.message });
    if (err instanceof ZodError) return reply.code(400).send({ error: err.issues[0]?.message ?? 'Datos inválidos.' });
    const e = err as { statusCode?: number; message: string };
    if (e.statusCode && e.statusCode < 500) return reply.code(e.statusCode).send({ error: e.statusCode === 429 ? 'Demasiados intentos. Espere un minuto.' : e.message });
    req.log.error(err);
    return reply.code(500).send({ error: 'Ocurrió un error en el servidor. Intente de nuevo.' });
  });

  await app.register(rutasAcceso);
  await app.register(rutasUsuarios);
  await app.register(rutasDatos);
  await app.register(rutasCambios);

  for (const [ruta, archivo] of Object.entries(ARCHIVOS)) {
    app.get(ruta, (_req, reply) => {
      if (archivo === 'sw.js' || archivo === 'index.html') reply.header('Cache-Control', 'no-cache');
      return reply.sendFile(archivo);
    });
  }
  app.setNotFoundHandler((req, reply) => reply.code(404).send({ error: 'No existe: ' + req.url }));
  return app;
}

import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const archivoEnv = resolve(aqui, '..', '.env');
if (existsSync(archivoEnv)) process.loadEnvFile(archivoEnv);

const e = process.env;

export const config = {
  puerto: Number(e.PUERTO ?? 3000),
  produccion: e.MODO === 'produccion',
  // Solo si hay un proxy con HTTPS delante (nginx, Caddy...): así se ve la IP real de cada teléfono.
  detrasDeProxy: e.PROXY === 'si',
  db: {
    host: e.DB_HOST ?? '127.0.0.1',
    port: Number(e.DB_PUERTO ?? 3306),
    user: e.DB_USUARIO ?? 'mese_app',
    password: e.DB_CLAVE ?? '',
    database: e.DB_NOMBRE ?? 'mese',
  },
  // Carpeta con index.html (la raíz del repositorio)
  raizPagina: resolve(aqui, '..', '..'),
};

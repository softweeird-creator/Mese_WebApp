import { crearApp } from './app.js';
import { config } from './config.js';
import { crearPool } from './db.js';

const app = await crearApp(crearPool(), { registro: true });
await app.listen({ port: config.puerto, host: '0.0.0.0' });

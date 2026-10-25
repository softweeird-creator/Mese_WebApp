// Pruebas contra una base MySQL real con db/01..05 y 08 instalados (usa los datos de .env).
import type { FastifyInstance } from 'fastify';
import type { Pool } from 'mysql2/promise';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { crearApp } from '../src/app.js';
import { crearPool, consultar } from '../src/db.js';

let app: FastifyInstance;
// Nombre único por corrida: la aplicación no puede borrar usuarios, solo desactivarlos.
const LOGIN = 'zzprueba' + Date.now().toString(36);
let pool: Pool;
const cookieDe = (r: { cookies: { name: string; value: string }[] }) => {
  const c = r.cookies.find((x) => x.name === 'mese_sesion');
  return c ? `mese_sesion=${c.value}` : '';
};
const entrar = (usuario: string, clave: string) => app.inject({ method: 'POST', url: '/api/entrar', payload: { usuario, clave } });

beforeAll(async () => {
  pool = crearPool();
  app = await crearApp(pool);
});
afterAll(async () => {
  await app.close();
  await pool.end();
});

describe('acceso', () => {
  let cookieAdmin = '';
  let idPrueba = 0;

  it('sin sesión /api/yo responde 401', async () => {
    const r = await app.inject({ url: '/api/yo' });
    expect(r.statusCode).toBe(401);
  });

  it('contraseña incorrecta se rechaza sin decir si el usuario existe', async () => {
    const a = await entrar('admin', 'equivocada');
    const b = await entrar('no-existe', 'equivocada');
    expect(a.statusCode).toBe(401);
    expect(a.json().error).toBe(b.json().error);
  });

  it('el administrador genérico entra y debe cambiar su contraseña', async () => {
    const r = await entrar('admin', 'mese2026');
    expect(r.statusCode).toBe(200);
    expect(r.json().usuario).toMatchObject({ login: 'admin', rol: 'ADMIN', debeCambiar: true });
    cookieAdmin = cookieDe(r);
    const c = r.cookies.find((x) => x.name === 'mese_sesion')!;
    expect(c.httpOnly).toBe(true);
    expect(c.sameSite).toBe('Strict');
  });

  it('con contraseña temporal no puede hacer otra cosa que cambiarla', async () => {
    const r = await app.inject({ url: '/api/usuarios', headers: { cookie: cookieAdmin } });
    expect(r.statusCode).toBe(403);
    expect(r.json().debeCambiar).toBe(true);
  });

  it('cambia su contraseña y sigue conectado', async () => {
    const r = await app.inject({ method: 'POST', url: '/api/clave', headers: { cookie: cookieAdmin }, payload: { actual: 'mese2026', nueva: 'mese2027' } });
    expect(r.statusCode).toBe(200);
    const yo = await app.inject({ url: '/api/yo', headers: { cookie: cookieAdmin } });
    expect(yo.json().usuario.debeCambiar).toBe(false);
  });

  it('crea una trabajadora social con contraseña temporal', async () => {
    const r = await app.inject({ method: 'POST', url: '/api/usuarios', headers: { cookie: cookieAdmin },
      payload: { nombre: 'Zzprueba Servidor', usuario: LOGIN, correo: '', rol: 'TRABAJO_SOCIAL', clave: 'temporal1' } });
    expect(r.statusCode).toBe(201);
    idPrueba = r.json().id;
    const repetido = await app.inject({ method: 'POST', url: '/api/usuarios', headers: { cookie: cookieAdmin },
      payload: { nombre: 'Otra', usuario: LOGIN, rol: 'TRABAJO_SOCIAL', clave: 'temporal1' } });
    expect(repetido.statusCode).toBe(400);
    expect(repetido.json().error).toMatch(/ya existe/);
  });

  it('la trabajadora social no puede administrar usuarios', async () => {
    const r = await entrar(LOGIN, 'temporal1');
    const ck = cookieDe(r);
    await app.inject({ method: 'POST', url: '/api/clave', headers: { cookie: ck }, payload: { actual: 'temporal1', nueva: 'propia123' } });
    const lista = await app.inject({ url: '/api/usuarios', headers: { cookie: ck } });
    expect(lista.statusCode).toBe(403);
  });

  it('desactivar a un usuario cierra su sesión al momento', async () => {
    const r = await entrar(LOGIN, 'propia123');
    const ck = cookieDe(r);
    await app.inject({ method: 'POST', url: `/api/usuarios/${idPrueba}/activo`, headers: { cookie: cookieAdmin }, payload: { activo: false } });
    expect((await app.inject({ url: '/api/yo', headers: { cookie: ck } })).statusCode).toBe(401);
    expect((await entrar(LOGIN, 'propia123')).statusCode).toBe(403);
  });

  it('salir cierra la sesión', async () => {
    const r = await app.inject({ method: 'POST', url: '/api/salir', headers: { cookie: cookieAdmin } });
    expect(r.statusCode).toBe(200);
    expect((await app.inject({ url: '/api/yo', headers: { cookie: cookieAdmin } })).statusCode).toBe(401);
  });

  it('rechaza peticiones que vienen de otro sitio', async () => {
    const r = await app.inject({ method: 'POST', url: '/api/entrar', headers: { origin: 'https://otro-sitio.com' }, payload: { usuario: 'admin', clave: 'x' } });
    expect(r.statusCode).toBe(403);
  });

  it('entrega la página pero no los archivos del servidor ni de la base', async () => {
    expect((await app.inject({ url: '/' })).statusCode).toBe(200);
    expect((await app.inject({ url: '/db/01_esquema.sql' })).statusCode).toBe(404);
    expect((await app.inject({ url: '/server/.env' })).statusCode).toBe(404);
  });

  afterAll(async () => {
    // Deja al administrador como estaba (mese2026, temporal) y borra la usuaria de prueba
    const { default: argon2 } = await import('argon2');
    const [a] = await consultar(pool, "SELECT id FROM v_usuario WHERE login = 'admin'");
    const cn = await pool.getConnection();
    await cn.query('CALL sp_usuario_clave(?, ?, TRUE, NULL)', [a.id, await argon2.hash('mese2026')]);
    cn.release();
    if (idPrueba) await pool.query('CALL sp_usuario_activar(?, FALSE)', [idPrueba]);
  });
});

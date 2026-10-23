// Permisos y alcance de /api/datos, contra la base de .env (con los Excel cargados o vacía).
import argon2 from 'argon2';
import type { FastifyInstance } from 'fastify';
import type { Pool } from 'mysql2/promise';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { crearApp } from '../src/app.js';
import { consultar, crearPool, llamar, llamarConSalida } from '../src/db.js';

let app: FastifyInstance;
let pool: Pool;
const sufijo = Date.now().toString(36);
const creados: number[] = [];

/** Crea un usuario con contraseña ya definitiva y devuelve su cookie de sesión. */
async function usuario(rol: string, alcance: string | null, permisos: string | null) {
  const login = `zzdatos${creados.length}${sufijo}`;
  const id = Number(await llamarConSalida(pool, 'sp_usuario_guardar',
    [null, 'Zzprueba Datos', login, null, rol, alcance, permisos, await argon2.hash('clave123')], null));
  creados.push(id);
  await llamar(pool, 'sp_usuario_clave', [id, await argon2.hash('clave123'), false, null]);
  const r = await app.inject({ method: 'POST', url: '/api/entrar', payload: { usuario: login, clave: 'clave123' } });
  const c = r.cookies.find((x) => x.name === 'mese_sesion')!;
  return { id, cookie: `mese_sesion=${c.value}`, usuario: r.json().usuario };
}
const datos = (cookie: string) => app.inject({ url: '/api/datos', headers: { cookie } });

beforeAll(async () => {
  pool = crearPool();
  app = await crearApp(pool);
});
afterAll(async () => {
  for (const id of creados) {
    await llamar(pool, 'sp_usuario_asignar', [id, '']);
    await llamar(pool, 'sp_usuario_activar', [id, false]);
  }
  await app.close();
  await pool.end();
});

describe('datos según permisos', () => {
  it('sin sesión no entrega datos', async () => {
    expect((await app.inject({ url: '/api/datos' })).statusCode).toBe(401);
  });

  it('coordinación ve a todos los participantes activos', async () => {
    const u = await usuario('COORDINACION', null, null);
    expect(u.usuario).toMatchObject({ rol: 'COORDINACION', alcance: 'TODOS' });
    expect(u.usuario.permisos).not.toContain('BORRAR');
    const [{ total }] = await consultar(pool, 'SELECT COUNT(*) AS total FROM v_activo');
    const r = await datos(u.cookie);
    expect(r.statusCode).toBe(200);
    expect(r.json().activos).toHaveLength(Number(total));
    expect(Object.keys(r.json())).toEqual(expect.arrayContaining(['activos', 'historico', 'familiares', 'bajas']));
  });

  it('solo consulta recibe únicamente las secciones que se le dieron', async () => {
    const u = await usuario('CONSULTA', 'TODOS', 'VER_ACTIVOS');
    const r = (await datos(u.cookie)).json();
    expect(r.activos).toBeDefined();
    expect(r.bajas).toBeUndefined();
    expect(r.familiares).toBeUndefined();
    expect((await app.inject({ url: '/api/usuarios', headers: { cookie: u.cookie } })).statusCode).toBe(403);
  });

  it('trabajo social ve solo a sus participantes asignados y sus familias', async () => {
    const u = await usuario('TRABAJO_SOCIAL', null, null);
    expect(u.usuario.alcance).toBe('ASIGNADOS');
    expect((await datos(u.cookie)).json().activos).toHaveLength(0);

    const dos = await consultar(pool, 'SELECT persona_id, familia_id FROM v_activo ORDER BY persona_id LIMIT 2');
    if (dos.length < 2) return; // base sin datos cargados: no hay a quién asignar
    await llamar(pool, 'sp_usuario_asignar', [u.id, dos.map((x) => x.persona_id).join(',')]);
    const r = (await datos(u.cookie)).json();
    expect(r.activos.map((x: { id: number }) => x.id).sort()).toEqual(dos.map((x) => Number(x.persona_id)).sort());
    const familias = await consultar(pool, `SELECT COUNT(*) AS total FROM v_familiar WHERE familia_id IN (${dos.map(() => '?').join(',')})`,
      dos.map((x) => x.familia_id));
    expect(r.familiares).toHaveLength(Number(familias[0].total));
  });

  it('un permiso quitado se aplica al momento, sin volver a entrar', async () => {
    const u = await usuario('CONSULTA', null, null);
    expect((await datos(u.cookie)).json().bajas).toBeDefined();
    await llamarConSalida(pool, 'sp_usuario_guardar', [u.id, 'Zzprueba Datos', u.usuario.login, null, 'CONSULTA', 'TODOS', 'VER_ACTIVOS', null], null);
    expect((await datos(u.cookie)).json().bajas).toBeUndefined();
  });
});

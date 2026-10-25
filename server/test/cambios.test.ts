// Guardar desde la página (fase 3), contra la base de .env con db/09_pagina.sql instalado.
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

async function usuario(rol: string, alcance: string | null, permisos: string | null) {
  const login = `zzcambios${creados.length}${sufijo}`;
  const id = Number(await llamarConSalida(pool, 'sp_usuario_guardar',
    [null, `Zzprueba Cambios ${creados.length}${sufijo}`, login, null, rol, alcance, permisos, await argon2.hash('clave123')], null));
  creados.push(id);
  await llamar(pool, 'sp_usuario_clave', [id, await argon2.hash('clave123'), false, null]);
  const r = await app.inject({ method: 'POST', url: '/api/entrar', payload: { usuario: login, clave: 'clave123' } });
  return { id, cookie: `mese_sesion=${r.cookies.find((x) => x.name === 'mese_sesion')!.value}` };
}
const pedir = (cookie: string, method: 'POST' | 'PUT', url: string, payload: object = {}) =>
  app.inject({ method, url, payload, headers: { cookie } });
const activo = async (id: number) => (await consultar(pool, 'SELECT * FROM v_activo WHERE persona_id = ?', [id]))[0];

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

describe('guardar desde la página', () => {
  it('sin sesión no guarda nada', async () => {
    const r = await app.inject({ method: 'POST', url: '/api/activos', payload: { n: 'Zz Sin Sesion' } });
    expect(r.statusCode).toBe(401);
  });

  it('coordinación agrega, edita, da de baja y reactiva', async () => {
    const u = await usuario('COORDINACION', null, null);
    const alta = await pedir(u.cookie, 'POST', '/api/activos', {
      n: `Mario ${sufijo} Zzcambios`, g: 'Hombre', fn: '2014-05-06', nv: 'Primaria', gr: 6, esc: 'Escuela Zzcambios', y: 2025, m: 1,
      mad: 'Rosa Zzcambios', tel: '4439998877', pat: 'Soriana', av: 'Firmado', col: 'Colonia Zzcambios',
    });
    expect(alta.statusCode).toBe(201);
    const id = alta.json().id as number;
    expect(await activo(id)).toMatchObject({ nivel: 'Primaria', grado: 6, tutor: 'Rosa Zzcambios', becas: 'Soriana' });

    const edit = await pedir(u.cookie, 'PUT', `/api/activos/${id}`, { n: `Mario ${sufijo} Zzcambios`, g: 'Hombre', fn: '2014-05-06', nv: 'Secundaria', gr: 1 });
    expect(edit.statusCode).toBe(200);
    expect(await activo(id)).toMatchObject({ nivel: 'Secundaria', grado: 1 });

    const baja = await pedir(u.cookie, 'POST', `/api/activos/${id}/baja`, { fb: '2025-12-01', mot: 'Cambio de domicilio', mo: 'Prueba' });
    expect(baja.statusCode).toBe(200);
    expect(await activo(id)).toBeUndefined();
    const datos = (await app.inject({ url: '/api/datos', headers: { cookie: u.cookie } })).json();
    expect(datos.bajas.find((b: { id: number }) => b.id === id)).toMatchObject({ mot: 'Cambio de domicilio', fb: '2025-12-01' });

    expect((await pedir(u.cookie, 'POST', `/api/bajas/${id}/reactivar`)).statusCode).toBe(200);
    expect(await activo(id)).toBeDefined();
  });

  it('los errores de la base llegan en español y sin guardar', async () => {
    const u = await usuario('COORDINACION', null, null);
    const r = await pedir(u.cookie, 'POST', '/api/activos', { n: 'Zz Grado Malo', nv: 'Secundaria', gr: 5 });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toBe('Escuela: Secundaria no tiene 5° grado.');
    const r2 = await pedir(u.cookie, 'POST', '/api/otra', { n: 'x' });
    expect(r2.statusCode).toBe(400);
  });

  it('solo consulta no puede guardar', async () => {
    const u = await usuario('CONSULTA', null, null);
    const r = await pedir(u.cookie, 'POST', '/api/familiares', { n: 'Zz Nadie', par: 'Madre', hijo: 'Zz' });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toContain('No tiene permiso');
  });

  it('trabajo social: lo que agrega queda asignado a ella y no toca a otros', async () => {
    const u = await usuario('TRABAJO_SOCIAL', null, null);
    const alta = await pedir(u.cookie, 'POST', '/api/activos', { n: `Lucía ${sufijo} Zzcambios`, g: 'Mujer', ed: 9, nv: 'Primaria', gr: 3 });
    expect(alta.statusCode).toBe(201);
    const id = alta.json().id as number;
    expect((await activo(id)).trabajadora_id).toBe(u.id);
    const datos = (await app.inject({ url: '/api/datos', headers: { cookie: u.cookie } })).json();
    expect(datos.activos.map((a: { id: number }) => a.id)).toContain(id);

    const [otro] = await consultar(pool, 'SELECT persona_id FROM v_activo WHERE trabajadora_id IS NULL OR trabajadora_id <> ? LIMIT 1', [u.id]);
    if (!otro) return;
    const r = await pedir(u.cookie, 'PUT', `/api/activos/${otro.persona_id}`, { n: 'Zz Intento' });
    expect(r.json().error).toBe('Ese participante no está entre los que usted atiende.');
  });

  it('familiar y registro histórico', async () => {
    const u = await usuario('COORDINACION', null, null);
    const alta = await pedir(u.cookie, 'POST', '/api/activos', { n: `Diego ${sufijo} Zzcambios`, nv: 'Primaria', gr: 2 });
    const fam = await pedir(u.cookie, 'POST', '/api/familiares', { n: 'Pedro Zzcambios', par: 'Padre', hijo: `Diego ${sufijo} Zzcambios`, g: 'Hombre', ed: 40 });
    expect(fam.statusCode).toBe(201);
    const [f] = await consultar(pool, 'SELECT * FROM v_familiar WHERE persona_id = ?', [fam.json().id]);
    expect(f).toMatchObject({ parentesco: 'Padre', familia_id: (await activo(alta.json().id)).familia_id });

    const h = await pedir(u.cookie, 'POST', '/api/historico', {
      n: `Paola ${sufijo} Zzcambios`, g: 'Mujer', fe: '2018-08-20', fs: '2022-07-01', res: 'Caso de éxito', cx: 'Secundaria', cb: 'Concluyó estudios',
    });
    expect(h.statusCode).toBe(201);
    const [r] = await consultar(pool, 'SELECT * FROM v_historico WHERE persona_id = ?', [h.json().id]);
    expect(r).toMatchObject({ resultado: 'Caso de éxito', fecha_salida: '2022-07-01' });
  });
});

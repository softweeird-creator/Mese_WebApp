import mysql, { type Pool, type RowDataPacket } from 'mysql2/promise';
import { config } from './config.js';

/** Error con un mensaje para mostrar tal cual (los SIGNAL '45000' de la base ya vienen en español). */
export class ErrorUsuario extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}

export type Fila = Record<string, unknown>;

export function crearPool(): Pool {
  return mysql.createPool({ ...config.db, charset: 'utf8mb4', connectionLimit: 10, dateStrings: true });
}

/**
 * Llama un procedimiento almacenado y devuelve el primer conjunto de renglones.
 * Fija @usuario_id para que la bitácora de la base sepa quién hizo el cambio.
 */
export async function llamar(pool: Pool, proc: string, params: unknown[] = [], usuarioId: number | null = null): Promise<Fila[]> {
  if (!/^sp_[a-z_]+$/.test(proc)) throw new Error('Nombre de procedimiento inválido: ' + proc);
  const cn = await pool.getConnection();
  try {
    await cn.query('SET @usuario_id = ?', [usuarioId]);
    const [res] = await cn.query(`CALL ${proc}(${params.map(() => '?').join(', ')})`, params);
    const primero = Array.isArray(res) ? res[0] : undefined;
    return Array.isArray(primero) ? (primero as RowDataPacket[]) : [];
  } catch (err) {
    throw traducir(err);
  } finally {
    cn.release();
  }
}

/** Igual que llamar, pero para procedimientos con un parámetro OUT al final; devuelve su valor. */
export async function llamarConSalida(pool: Pool, proc: string, params: unknown[], usuarioId: number | null): Promise<unknown> {
  if (!/^sp_[a-z_]+$/.test(proc)) throw new Error('Nombre de procedimiento inválido: ' + proc);
  const cn = await pool.getConnection();
  try {
    await cn.query('SET @usuario_id = ?, @salida = NULL', [usuarioId]);
    await cn.query(`CALL ${proc}(${params.map(() => '?').join(', ')}, @salida)`, params);
    const [[fila]] = await cn.query<RowDataPacket[]>('SELECT @salida AS salida');
    return fila?.salida;
  } catch (err) {
    throw traducir(err);
  } finally {
    cn.release();
  }
}

export async function consultar(pool: Pool, sql: string, params: unknown[] = []): Promise<Fila[]> {
  const [filas] = await pool.query<RowDataPacket[]>(sql, params);
  return filas;
}

function traducir(err: unknown): unknown {
  const e = err as { sqlState?: string; sqlMessage?: string };
  if (e?.sqlState === '45000' && e.sqlMessage) return new ErrorUsuario(e.sqlMessage);
  return err;
}

// Poner una contraseña desde la consola del servidor (por ejemplo, si se olvidó la del administrador):
//   npm run clave -- admin NuevaClave
import argon2 from 'argon2';
import { crearPool, llamar } from './db.js';

const [login, clave] = process.argv.slice(2);
if (!login || !clave || clave.length < 6) {
  console.error('Uso: npm run clave -- <usuario> <contraseña de al menos 6 caracteres>');
  process.exit(1);
}
const pool = crearPool();
try {
  const [u] = await llamar(pool, 'sp_acceso_buscar', [login]);
  if (!u) throw new Error(`No existe el usuario "${login}".`);
  await llamar(pool, 'sp_usuario_clave', [u.id, await argon2.hash(clave), false, null]);
  console.log(`Listo: ${u.nombre} (${login}) ya puede entrar con la nueva contraseña. Sus sesiones abiertas se cerraron.`);
} catch (e) {
  console.error((e as Error).message);
  process.exitCode = 1;
} finally {
  await pool.end();
}

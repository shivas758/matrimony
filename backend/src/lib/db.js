import pg from 'pg';
import { config } from './config.js';

export const pool = new pg.Pool({ connectionString: config.databaseUrl });

export function query(text, params) {
  return pool.query(text, params);
}

/** Returns the first row or null. */
export async function one(text, params) {
  const { rows } = await pool.query(text, params);
  return rows[0] || null;
}

/** Returns all rows. */
export async function many(text, params) {
  const { rows } = await pool.query(text, params);
  return rows;
}

/** Runs fn inside a transaction, rolling back on throw. */
export async function tx(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

import knex from 'knex';
import { config } from '../config/env.js';

export const db = knex({
  client: 'mysql2',
  connection: {
    host: config.DB_HOST,
    port: config.DB_PORT,
    user: config.DB_USER,
    password: config.DB_PASSWORD,
    database: config.DB_NAME,
    charset: 'utf8mb4',
    connectTimeout: 30000,
    ssl: config.DB_SSL ? { minVersion: 'TLSv1.2' } : undefined,
  },
  pool: {
    min: 0,
    max: 5,
    acquireTimeoutMillis: 30000,
  },
  migrations: {
    directory: './dist/db/migrations',
    extension: 'js',
    loadExtensions: ['.js'],
  },
});


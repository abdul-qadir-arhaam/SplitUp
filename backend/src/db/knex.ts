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
    timezone: 'UTC',
    charset: 'utf8mb4',
  },
  pool: {
    min: 2,
    max: 10,
  },
  migrations: {
    directory: './dist/db/migrations',
    extension: 'js',
  },
});

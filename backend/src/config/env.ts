import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(4000),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  DB_HOST: z.string().default('127.0.0.1'),
  DB_PORT: z.coerce.number().default(3306),
  DB_USER: z.string().default('splitup'),
  DB_PASSWORD: z.string().default('splitup_secret'),
  DB_NAME: z.string().default('splitup'),
  DB_SSL: z.coerce.boolean().default(false),
  AUTH_STUB_MODE: z.coerce.boolean().default(true), // Dev/Test stub
});

export const config = envSchema.parse(process.env);

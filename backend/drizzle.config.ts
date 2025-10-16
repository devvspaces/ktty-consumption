import { defineConfig } from 'drizzle-kit';
import * as dotenv from 'dotenv';

dotenv.config();

export default defineConfig({
  schema: './src/database/schema.ts',
  out: './drizzle/migrations',
  dialect: 'postgresql',
  dbCredentials: {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    user: process.env.DB_USERNAME || 'ktty_user',
    password: process.env.DB_PASSWORD || 'secure_password',
    database: process.env.DB_NAME || 'ktty_companions',
  },
  verbose: true,
  strict: true,
});
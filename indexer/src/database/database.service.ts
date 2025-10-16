import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { drizzle, NodePgDatabase } from 'drizzle-orm/node-postgres';
import postgres, { Sql } from 'postgres';
import * as schema from './schema';

@Injectable()
export class DatabaseService implements OnModuleInit {
  private readonly logger = new Logger(DatabaseService.name);
  private client: Sql;
  private _db: NodePgDatabase<typeof schema>;

  constructor(private configService: ConfigService) {}

  async onModuleInit() {
    await this.connect();
  }

  private async connect() {
    const connectionConfig = {
      host: this.configService.get<string>('database.host'),
      port: this.configService.get<number>('database.port'),
      user: this.configService.get<string>('database.username'),
      password: this.configService.get<string>('database.password'),
      database: this.configService.get<string>('database.name'),
      max: 20,
      idle_timeout: 20,
      max_lifetime: 60 * 30,
    };

    this.logger.log(`Connecting to database: ${connectionConfig.host}:${connectionConfig.port}/${connectionConfig.database}`);


    const DB_URL = `postgres://${connectionConfig.user}:${connectionConfig.password}@${connectionConfig.host}:${connectionConfig.port}/${connectionConfig.database}`;
    this._db = drizzle(DB_URL, { schema });

    // Test connection
  }

  get db(): NodePgDatabase<typeof schema> {
    if (!this._db) {
      throw new Error('Database not initialized. Call connect() first.');
    }
    return this._db;
  }

  async disconnect() {
    if (this.client) {
      await this.client.end();
      this.logger.log('Database connection closed');
    }
  }

  async isHealthy(): Promise<boolean> {
    try {
      await this.client`SELECT 1`;
      return true;
    } catch (error) {
      this.logger.error('Database health check failed:', error);
      return false;
    }
  }
}
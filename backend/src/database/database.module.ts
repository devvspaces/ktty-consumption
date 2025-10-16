import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { DatabaseService } from './database.service';

export const DATABASE_CONNECTION = 'DATABASE_CONNECTION';

@Module({
  imports: [ConfigModule],
  providers: [
    {
      provide: DATABASE_CONNECTION,
      inject: [ConfigService],
      useFactory: async (configService: ConfigService) => {
        const connectionString = `postgres://${configService.get('DB_USERNAME')}:${configService.get('DB_PASSWORD')}@${configService.get('DB_HOST')}:${configService.get('DB_PORT')}/${configService.get('DB_NAME')}`;
        
        const client = postgres(connectionString, {
          max: configService.get('DB_MAX_CONNECTIONS', 20),
          idle_timeout: 20,
          connect_timeout: 10,
        });
        
        return drizzle(client);
      },
    },
    DatabaseService,
  ],
  exports: [DATABASE_CONNECTION, DatabaseService],
})
export class DatabaseModule {}
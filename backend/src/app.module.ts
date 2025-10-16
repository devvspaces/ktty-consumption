import { Module } from '@nestjs/common';
import { ConfigModule } from './config/config.module';
import { DatabaseModule } from './database/database.module';
import { BlockchainModule } from './modules/blockchain/blockchain.module';
import { HealthModule } from './modules/health/health.module';

@Module({
  imports: [
    ConfigModule,
    DatabaseModule,
    BlockchainModule,
    HealthModule,
  ],
})
export class AppModule {}
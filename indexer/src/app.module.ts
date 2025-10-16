import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { TerminusModule } from '@nestjs/terminus';
import { BullModule } from '@nestjs/bullmq';
import configuration from './config/configuration';
import { validationSchema } from './config/validation';
import { DatabaseModule } from './database/database.module';
import { EventListenerService } from './services/event-listener.service';
import { TransferProcessorService } from './services/transfer-processor.service';
import { MetadataService } from './services/metadata.service';
import { MetadataQueueService } from './services/metadata-queue.service';
import { MetadataQueueProcessor } from './services/metadata-queue.processor';
import { MetadataProcessorService } from './services/metadata-processor.service';
import { SyncService } from './services/sync.service';
import { BullBoardService } from './dashboard/bull-board.service';
import { NftController } from './controllers/nft.controller';
import { HealthController } from './controllers/health.controller';
import { IndexerController } from './controllers/indexer.controller';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
      validationSchema,
      validationOptions: {
        allowUnknown: true,
        abortEarly: true,
      },
    }),
    ScheduleModule.forRoot(),
    TerminusModule,
    DatabaseModule,
    BullModule.forRootAsync({
      useFactory: async (configService: ConfigService) => ({
        connection: {
          host: configService.get('redis.host', 'localhost'),
          port: configService.get('redis.port', 6379),
          password: configService.get('redis.password'),
          db: configService.get('redis.db', 0),
        },
        defaultJobOptions: {
          removeOnComplete: 100,
          removeOnFail: 50,
        },
      }),
      inject: [ConfigService],
    }),
    BullModule.registerQueue({
      name: 'metadata',
    }),
  ],
  controllers: [
    NftController,
    HealthController,
    IndexerController,
  ],
  providers: [
    EventListenerService,
    TransferProcessorService,
    MetadataService,
    MetadataQueueService,
    MetadataQueueProcessor,
    MetadataProcessorService,
    SyncService,
    BullBoardService,
  ],
})
export class AppModule {}
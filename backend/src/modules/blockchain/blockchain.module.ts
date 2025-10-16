import { Module } from '@nestjs/common';
import { ConfigModule } from '../../config/config.module';
import { DatabaseModule } from '../../database/database.module';
import { ContractService } from './services/contract.service';
import { TokenMapperService } from './services/token-mapper.service';
import { BatchProcessorService } from './services/batch-processor.service';
import { EventListenerService } from './services/event-listener.service';
import { BlockchainController } from './blockchain.controller';

@Module({
  imports: [ConfigModule, DatabaseModule],
  providers: [
    ContractService,
    TokenMapperService,
    BatchProcessorService,
    EventListenerService,
  ],
  controllers: [BlockchainController],
  exports: [
    ContractService,
    TokenMapperService,
    BatchProcessorService,
    EventListenerService,
  ],
})
export class BlockchainModule {}
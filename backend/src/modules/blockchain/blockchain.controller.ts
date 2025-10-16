import { Controller, Get, Post, Logger } from '@nestjs/common';
import { ContractService } from './services/contract.service';
import { TokenMapperService } from './services/token-mapper.service';
import { BatchProcessorService } from './services/batch-processor.service';
import { EventListenerService } from './services/event-listener.service';
import { DatabaseService } from '../../database/database.service';

@Controller('blockchain')
export class BlockchainController {
  private readonly logger = new Logger(BlockchainController.name);

  constructor(
    private readonly contractService: ContractService,
    private readonly tokenMapperService: TokenMapperService,
    private readonly batchProcessorService: BatchProcessorService,
    private readonly eventListenerService: EventListenerService,
    private readonly databaseService: DatabaseService,
  ) {}

  /**
   * Basic health check endpoint
   */
  @Get('health')
  async health() {
    try {
      const [
        contractHealth,
        databaseHealth,
        eventListenerHealth
      ] = await Promise.all([
        this.contractService.healthCheck(),
        this.databaseService.healthCheck(),
        this.eventListenerService.healthCheck(),
      ]);

      const healthy = contractHealth && databaseHealth && eventListenerHealth;

      return {
        status: healthy ? 'healthy' : 'unhealthy',
        timestamp: new Date().toISOString(),
        services: {
          contract: contractHealth ? 'healthy' : 'unhealthy',
          database: databaseHealth ? 'healthy' : 'unhealthy',
          eventListener: eventListenerHealth ? 'healthy' : 'unhealthy',
        },
      };
    } catch (error) {
      this.logger.error('Health check failed:', error);
      return {
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        error: error.message,
      };
    }
  }

  /**
   * Detailed status endpoint
   */
  @Get('status')
  async status() {
    try {
      const [
        currentBlock,
        lastProcessedBlock,
        walletAddress,
        mappingCount,
        batchStats,
        eventListenerStatus,
      ] = await Promise.all([
        this.contractService.getCurrentBlock(),
        this.databaseService.getLastProcessedBlock(),
        Promise.resolve(this.contractService.getWalletAddress()),
        Promise.resolve(this.tokenMapperService.getMappingCount()),
        Promise.resolve(this.batchProcessorService.getStats()),
        Promise.resolve(this.eventListenerService.getStatus()),
      ]);

      return {
        timestamp: new Date().toISOString(),
        blockchain: {
          currentBlock,
          lastProcessedBlock,
          blocksBehind: currentBlock - lastProcessedBlock,
        },
        contract: {
          address: this.contractService.getContract().target,
          walletAddress,
        },
        tokenMapping: {
          totalMappings: mappingCount,
        },
        batchProcessor: {
          pendingTokens: batchStats.pendingTokens,
          processingActive: batchStats.processingActive,
          hasTimer: batchStats.hasTimer,
        },
        eventListener: {
          isListening: eventListenerStatus.isListening,
          reconnectAttempts: eventListenerStatus.reconnectAttempts,
          catchupInProgress: eventListenerStatus.catchupInProgress,
        },
      };
    } catch (error) {
      this.logger.error('Status check failed:', error);
      return {
        timestamp: new Date().toISOString(),
        error: error.message,
      };
    }
  }

  /**
   * Get processing metrics
   */
  @Get('metrics')
  async metrics() {
    try {
      // Get some basic metrics from database
      // Note: In a production system, you'd want to implement proper metrics collection
      
      return {
        timestamp: new Date().toISOString(),
        message: 'Metrics endpoint - to be implemented with proper metrics collection (Prometheus, etc.)',
        placeholder: {
          totalEventsProcessed: 'TBD',
          averageProcessingTime: 'TBD',
          errorRate: 'TBD',
          batchesProcessed: 'TBD',
        },
      };
    } catch (error) {
      this.logger.error('Metrics collection failed:', error);
      return {
        timestamp: new Date().toISOString(),
        error: error.message,
      };
    }
  }

  /**
   * Force manual catchup (admin endpoint)
   */
  @Post('catchup')
  async forceCatchup() {
    try {
      this.logger.log('Manual catchup requested via API');
      await this.eventListenerService.forceCatchup();
      
      return {
        success: true,
        message: 'Manual catchup completed',
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      this.logger.error('Manual catchup failed:', error);
      return {
        success: false,
        message: 'Manual catchup failed',
        error: error.message,
        timestamp: new Date().toISOString(),
      };
    }
  }

  /**
   * Force process current batch (admin endpoint)
   */
  @Post('process-batch')
  async forceProcessBatch() {
    try {
      this.logger.log('Manual batch processing requested via API');
      await this.batchProcessorService.forceProcessBatch();
      
      return {
        success: true,
        message: 'Batch processing completed',
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      this.logger.error('Manual batch processing failed:', error);
      return {
        success: false,
        message: 'Batch processing failed',
        error: error.message,
        timestamp: new Date().toISOString(),
      };
    }
  }
}
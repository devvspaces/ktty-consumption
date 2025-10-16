import { Controller, Get, Post, Logger } from '@nestjs/common';
import { SyncService } from '../services/sync.service';
import { TransferProcessorService } from '../services/transfer-processor.service';
import { MetadataService } from '../services/metadata.service';
import { EventListenerService } from '../services/event-listener.service';

@Controller('indexer')
export class IndexerController {
  private readonly logger = new Logger(IndexerController.name);

  constructor(
    private syncService: SyncService,
    private transferProcessor: TransferProcessorService,
    private metadataService: MetadataService,
    private eventListener: EventListenerService,
  ) {}

  @Get('status')
  async getStatus() {
    try {
      const [
        syncStatus,
        processingStats,
        metadataStats,
        performanceMetrics,
        eventListenerStatus
      ] = await Promise.all([
        this.syncService.getSyncStatus(),
        this.transferProcessor.getProcessingStats(),
        this.metadataService.getMetadataStats(),
        this.syncService.getPerformanceMetrics(),
        this.eventListener.getStatus(),
      ]);

      return {
        timestamp: new Date().toISOString(),
        sync: syncStatus,
        processing: processingStats,
        metadata: metadataStats,
        performance: performanceMetrics,
        eventListener: eventListenerStatus,
        overall: {
          healthy: syncStatus.isHealthy && syncStatus.blocksBehind <= 10,
          caughtUp: syncStatus.blocksBehind <= 5,
          indexingActive: eventListenerStatus.isListening && !syncStatus.isSyncing,
        },
      };
    } catch (error) {
      this.logger.error('Failed to get indexer status:', error);
      return {
        timestamp: new Date().toISOString(),
        error: 'Failed to retrieve status',
        overall: {
          healthy: false,
          caughtUp: false,
          indexingActive: false,
        },
      };
    }
  }

  @Post('catchup')
  async forceCatchup() {
    try {
      this.logger.log('Force catchup requested via API');
      const result = await this.syncService.forceCatchup();
      return result;
    } catch (error) {
      this.logger.error('Force catchup failed:', error);
      return {
        message: `Catchup failed: ${error.message}`,
        status: await this.syncService.getSyncStatus(),
      };
    }
  }

  @Post('retry-failed')
  async retryFailedOperations() {
    try {
      this.logger.log('Retry failed operations requested via API');
      
      await Promise.all([
        this.transferProcessor.retryFailedOperations(),
        // Note: metadata retry is handled by scheduled jobs, but we could add a manual trigger here
      ]);

      const stats = await this.transferProcessor.getProcessingStats();
      
      return {
        message: 'Retry operations completed',
        failedOperations: stats.failedOperations,
      };
    } catch (error) {
      this.logger.error('Retry failed operations failed:', error);
      return {
        message: `Retry failed: ${error.message}`,
      };
    }
  }

  @Get('metrics')
  async getMetrics() {
    try {
      const [
        processingStats,
        metadataStats,
        performanceMetrics,
        syncStatus
      ] = await Promise.all([
        this.transferProcessor.getProcessingStats(),
        this.metadataService.getMetadataStats(),
        this.syncService.getPerformanceMetrics(),
        this.syncService.getSyncStatus(),
      ]);

      return {
        timestamp: new Date().toISOString(),
        blockchain: {
          currentBlock: syncStatus.currentBlock,
          lastProcessedBlock: syncStatus.lastProcessedBlock,
          blocksBehind: syncStatus.blocksBehind,
          processingRate: {
            transfersPerHour: performanceMetrics.transfersLastHour,
            transfersPerDay: performanceMetrics.transfersLast24Hours,
          },
        },
        database: {
          totalNfts: processingStats.totalNfts,
          totalTransfers: processingStats.totalTransfers,
          failedOperations: processingStats.failedOperations,
        },
        metadata: {
          nftsWithMetadata: metadataStats.nftsWithMetadata,
          metadataPercentage: metadataStats.metadataPercentage,
          cacheSize: metadataStats.cacheSize,
          staleMetadata: metadataStats.staleMetadata,
        },
        performance: {
          averageProcessingDelaySeconds: performanceMetrics.averageProcessingDelaySeconds,
          healthScore: this.calculateHealthScore(syncStatus, processingStats, metadataStats),
        },
      };
    } catch (error) {
      this.logger.error('Failed to get metrics:', error);
      return {
        timestamp: new Date().toISOString(),
        error: 'Failed to retrieve metrics',
      };
    }
  }

  @Get('health')
  async getHealth() {
    try {
      const syncStatus = await this.syncService.getSyncStatus();
      const eventListenerStatus = this.eventListener.getStatus();
      
      const isHealthy = syncStatus.isHealthy && 
                       syncStatus.blocksBehind <= 10 && 
                       eventListenerStatus.isListening;

      return {
        status: isHealthy ? 'healthy' : 'unhealthy',
        timestamp: new Date().toISOString(),
        checks: {
          sync: {
            healthy: syncStatus.isHealthy,
            blocksBehind: syncStatus.blocksBehind,
            lastSync: syncStatus.lastSyncAt,
          },
          eventListener: {
            healthy: eventListenerStatus.isListening,
            provider: eventListenerStatus.currentProvider,
            reconnectAttempts: eventListenerStatus.reconnectAttempts,
          },
          database: {
            healthy: true, // Database service would have thrown if unhealthy
          },
        },
        overall: isHealthy,
      };
    } catch (error) {
      this.logger.error('Health check failed:', error);
      return {
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        error: error.message,
        overall: false,
      };
    }
  }

  private calculateHealthScore(syncStatus: any, processingStats: any, metadataStats: any): number {
    let score = 100;
    
    // Deduct points for being behind
    if (syncStatus.blocksBehind > 5) {
      score -= Math.min(30, syncStatus.blocksBehind * 2);
    }
    
    // Deduct points for failed operations
    if (processingStats.failedOperations > 0) {
      score -= Math.min(20, processingStats.failedOperations * 2);
    }
    
    // Deduct points for low metadata coverage
    if (metadataStats.metadataPercentage < 90) {
      score -= (90 - metadataStats.metadataPercentage) * 0.5;
    }
    
    // Deduct points if not syncing
    if (!syncStatus.isHealthy) {
      score -= 25;
    }
    
    return Math.max(0, Math.round(score));
  }
}
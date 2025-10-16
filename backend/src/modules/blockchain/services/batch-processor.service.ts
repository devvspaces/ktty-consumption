import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../../database/database.service';
import { TokenMapperService } from './token-mapper.service';
import { ContractService } from './contract.service';

export interface PendingToken {
  tokenId: number;
  blockNumber: number;
  transactionHash: string;
  logIndex: number;
  queuedAt: Date;
}

@Injectable()
export class BatchProcessorService implements OnModuleDestroy {
  private readonly logger = new Logger(BatchProcessorService.name);
  private pendingTokens: Map<number, PendingToken> = new Map();
  private batchTimer: NodeJS.Timeout | null = null;
  private processingActive = false;
  private shutdownRequested = false;

  private readonly maxBatchSize: number;
  private readonly batchTimeoutMs: number;
  private readonly processingIntervalMs: number;
  private readonly maxRetries: number;
  private readonly retryDelayMs: number;
  private readonly exponentialBackoff: boolean;

  constructor(
    private readonly configService: ConfigService,
    private readonly databaseService: DatabaseService,
    private readonly tokenMapperService: TokenMapperService,
    private readonly contractService: ContractService,
  ) {
    this.maxBatchSize = this.configService.get<number>('batch.maxBatchSize');
    this.batchTimeoutMs = this.configService.get<number>('batch.batchTimeoutMs');
    this.processingIntervalMs = this.configService.get<number>('batch.processingIntervalMs');
    this.maxRetries = this.configService.get<number>('batch.maxRetries');
    this.retryDelayMs = this.configService.get<number>('batch.retryDelayMs');
    this.exponentialBackoff = this.configService.get<boolean>('batch.exponentialBackoff');
  }

  async onModuleDestroy() {
    this.shutdownRequested = true;
    await this.gracefulShutdown();
  }

  /**
   * Add a token to the processing queue
   */
  async queueToken(pendingToken: PendingToken): Promise<void> {
    if (this.shutdownRequested) {
      this.logger.warn(`Rejecting token ${pendingToken.tokenId} due to shutdown`);
      return;
    }

    // Check if already processed
    const isProcessed = await this.databaseService.isEventProcessed(pendingToken.tokenId);
    if (isProcessed) {
      this.logger.debug(`Token ${pendingToken.tokenId} already processed, skipping`);
      return;
    }

    // Check if token mapping exists
    if (!this.tokenMapperService.hasMapping(pendingToken.tokenId)) {
      this.logger.error(`No mapping found for token ${pendingToken.tokenId}, skipping`);
      return;
    }

    this.pendingTokens.set(pendingToken.tokenId, pendingToken);
    this.logger.debug(`Queued token ${pendingToken.tokenId} for batch processing`);

    // Add to database queue
    const randomCode = this.tokenMapperService.getRandomCode(pendingToken.tokenId);
    await this.databaseService.addToQueue({
      tokenId: pendingToken.tokenId,
      blockNumber: pendingToken.blockNumber,
      transactionHash: pendingToken.transactionHash,
      logIndex: pendingToken.logIndex,
      randomCode,
    });

    // Start timer if not already running
    if (!this.batchTimer && !this.processingActive) {
      this.startBatchTimer();
    }

    // Process immediately if batch size reached
    if (this.pendingTokens.size >= this.maxBatchSize && !this.processingActive) {
      this.clearBatchTimer();
      await this.processBatch('size_limit');
    }
  }

  /**
   * Start the batch processing timer
   */
  private startBatchTimer(): void {
    this.batchTimer = setTimeout(async () => {
      if (this.pendingTokens.size > 0 && !this.processingActive) {
        await this.processBatch('timeout');
      }
    }, this.batchTimeoutMs);

    this.logger.debug(`Started batch timer for ${this.batchTimeoutMs}ms`);
  }

  /**
   * Clear the batch processing timer
   */
  private clearBatchTimer(): void {
    if (this.batchTimer) {
      clearTimeout(this.batchTimer);
      this.batchTimer = null;
      this.logger.debug('Cleared batch timer');
    }
  }

  /**
   * Process the current batch
   */
  private async processBatch(trigger: 'timeout' | 'size_limit' | 'shutdown'): Promise<void> {
    if (this.processingActive || this.pendingTokens.size === 0) {
      return;
    }

    this.processingActive = true;
    this.clearBatchTimer();

    try {
      const batchSize = Math.min(this.pendingTokens.size, this.maxBatchSize);
      const batch = Array.from(this.pendingTokens.values()).slice(0, batchSize);
      
      this.logger.log(`Processing batch of ${batch.length} tokens (trigger: ${trigger})`);

      await this.processBatchWithRetry(batch);

      // Remove processed tokens from pending
      batch.forEach(token => this.pendingTokens.delete(token.tokenId));

    } catch (error) {
      this.logger.error('Batch processing failed:', error);
    } finally {
      this.processingActive = false;

      // Schedule next batch if more tokens pending and not shutting down
      if (this.pendingTokens.size > 0 && !this.shutdownRequested) {
        setTimeout(() => this.processBatch('timeout'), 0);
      }
    }
  }

  /**
   * Process a batch with retry logic
   */
  private async processBatchWithRetry(batch: PendingToken[], attempt = 1): Promise<void> {
    const tokenIds = batch.map(token => token.tokenId);
    
    try {
      // Get random codes for all tokens
      const tokenMappings = this.tokenMapperService.getRandomCodes(tokenIds);
      const tokenCodesArray = tokenMappings.map(mapping => mapping.randomCode);

      // Create batch transaction record
      const batchTransaction = await this.databaseService.createBatchTransaction({
        tokenIds,
        tokenCodes: tokenCodesArray,
        status: 'pending',
      });

      this.logger.debug(`Created batch transaction ${batchTransaction.id} for tokens: ${tokenIds.join(', ')}`);

      // Execute blockchain transaction
      const txResponse = await this.contractService.setBulkTokenCodes(tokenIds, tokenCodesArray);
      
      // Update batch transaction with transaction hash
      await this.databaseService.updateBatchTransaction(batchTransaction.id, {
        transactionHash: txResponse.hash,
        nonce: txResponse.nonce,
        status: 'submitted',
      });

      // Wait for transaction confirmation
      const receipt = await txResponse.wait();
      
      // Update batch transaction with final status
      await this.databaseService.updateBatchTransaction(batchTransaction.id, {
        gasUsed: Number(receipt.gasUsed),
        gasPrice: Number(receipt.gasPrice || 0),
        completedAt: new Date(),
        status: 'completed',
      });

      // Mark queue items as processed
      const queueItems = await this.databaseService.getPendingQueueItems(batch.length);
      const queueItemIds = queueItems
        .filter(item => tokenIds.includes(item.tokenId))
        .map(item => item.id);
      
      await this.databaseService.markQueueItemsAsProcessed(queueItemIds, batchTransaction.id);

      // Mark individual events as processed
      for (const token of batch) {
        await this.databaseService.markEventAsProcessed({
          tokenId: token.tokenId,
          blockNumber: token.blockNumber,
          transactionHash: token.transactionHash,
          logIndex: token.logIndex,
          status: 'completed',
        });
      }

      this.logger.log(`Successfully processed batch of ${batch.length} tokens in tx ${receipt.hash}`);

    } catch (error) {
      this.logger.error(`Batch processing attempt ${attempt} failed:`, error);

      if (attempt < this.maxRetries) {
        const delay = this.exponentialBackoff 
          ? this.retryDelayMs * Math.pow(2, attempt - 1)
          : this.retryDelayMs;

        this.logger.warn(`Retrying batch in ${delay}ms (attempt ${attempt + 1}/${this.maxRetries})`);
        
        await new Promise(resolve => setTimeout(resolve, delay));
        return this.processBatchWithRetry(batch, attempt + 1);
      } else {
        this.logger.error(`Batch processing failed after ${this.maxRetries} attempts`);
        
        // Mark as failed in database
        for (const token of batch) {
          await this.databaseService.markEventAsProcessed({
            tokenId: token.tokenId,
            blockNumber: token.blockNumber,
            transactionHash: token.transactionHash,
            logIndex: token.logIndex,
            status: 'failed',
            errorMessage: error.message,
            retryCount: this.maxRetries,
          });
        }
        
        throw error;
      }
    }
  }

  /**
   * Get current batch processing statistics
   */
  getStats(): {
    pendingTokens: number;
    processingActive: boolean;
    hasTimer: boolean;
  } {
    return {
      pendingTokens: this.pendingTokens.size,
      processingActive: this.processingActive,
      hasTimer: this.batchTimer !== null,
    };
  }

  /**
   * Force process current batch (for testing/admin)
   */
  async forceProcessBatch(): Promise<void> {
    if (this.pendingTokens.size === 0) {
      this.logger.warn('No pending tokens to process');
      return;
    }

    this.logger.log('Force processing current batch');
    await this.processBatch('size_limit');
  }

  /**
   * Graceful shutdown - process remaining tokens
   */
  private async gracefulShutdown(): Promise<void> {
    this.logger.log('Starting graceful shutdown of batch processor');
    
    this.clearBatchTimer();

    // Wait for current processing to finish
    const maxWaitTime = 30000; // 30 seconds
    const startTime = Date.now();

    while (this.processingActive && (Date.now() - startTime) < maxWaitTime) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    // Process remaining tokens if any
    if (this.pendingTokens.size > 0) {
      this.logger.log(`Processing remaining ${this.pendingTokens.size} tokens before shutdown`);
      try {
        await this.processBatch('shutdown');
      } catch (error) {
        this.logger.error('Failed to process remaining tokens during shutdown:', error);
      }
    }

    this.logger.log('Batch processor graceful shutdown completed');
  }
}
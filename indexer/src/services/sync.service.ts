import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { eq, desc, sql } from 'drizzle-orm';
import { ethers } from 'ethers';
import { DatabaseService } from '../database/database.service';
import { syncState, transferEvents } from '../database/schema';
import { TransferProcessorService } from './transfer-processor.service';
import { MetadataUpdatedEventData, TransferEventData } from './event-listener.service';
import { KttyWorldCompanions__factory, KttyWorldCompanions } from '../types';
import { MetadataProcessorService } from './metadata-processor.service';
import { TypedContractEvent, TypedEventLog } from '@/types/common';
import { MetadataUpdatedEvent } from '@/types/KttyWorldCompanions';

@Injectable()
export class SyncService implements OnModuleInit {
  private readonly logger = new Logger(SyncService.name);
  private provider: ethers.JsonRpcProvider;
  private contract: KttyWorldCompanions;
  private contractAddress: string;
  private deploymentBlock: number;
  private isSyncing = false;

  constructor(
    private configService: ConfigService,
    private databaseService: DatabaseService,
    private transferProcessor: TransferProcessorService,
    private metadataProcessor: MetadataProcessorService,

  ) {
    this.initializeContract();
  }

  async onModuleInit() {
    await this.initializeSyncState();
  }

  private initializeContract() {
    const rpcUrl = this.configService.get<string>('blockchain.rpcUrl');
    this.contractAddress = this.configService.get<string>('blockchain.contractAddress');
    this.deploymentBlock = this.configService.get<number>('blockchain.deploymentBlock');

    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.contract = KttyWorldCompanions__factory.connect(this.contractAddress, this.provider);
  }

  private async initializeSyncState(): Promise<void> {
    const db = this.databaseService.db;

    try {
      // Check if sync state exists for this contract
      const existingState = await db
        .select()
        .from(syncState)
        .where(eq(syncState.contractAddress, this.contractAddress.toLowerCase()))
        .limit(1);

      if (existingState.length === 0) {
        // Initialize sync state with deployment block
        await db.insert(syncState).values({
          contractAddress: this.contractAddress.toLowerCase(),
          lastProcessedBlock: this.deploymentBlock,
          lastProcessedTimestamp: new Date(0), // Epoch time
          isHealthy: true,
        });

        this.logger.log(`Initialized sync state for contract ${this.contractAddress} at block ${this.deploymentBlock}`);
      } else {
        this.logger.log(`Existing sync state found. Last processed block: ${existingState[0].lastProcessedBlock}`);
      }
    } catch (error) {
      this.logger.error('Failed to initialize sync state:', error);
      throw error;
    }
  }

  async getLastProcessedBlock(): Promise<number> {
    const db = this.databaseService.db;

    try {
      const state = await db
        .select()
        .from(syncState)
        .where(eq(syncState.contractAddress, this.contractAddress.toLowerCase()))
        .limit(1);

      return state.length > 0 ? state[0].lastProcessedBlock : this.deploymentBlock;
    } catch (error) {
      this.logger.error('Failed to get last processed block:', error);
      return this.deploymentBlock;
    }
  }

  async updateLastProcessedBlock(blockNumber: number): Promise<void> {
    const db = this.databaseService.db;

    try {
      await db
        .update(syncState)
        .set({
          lastProcessedBlock: blockNumber,
          lastProcessedTimestamp: new Date(),
          isHealthy: true,
          errorMessage: null,
        })
        .where(eq(syncState.contractAddress, this.contractAddress.toLowerCase()));

    } catch (error) {
      this.logger.error('Failed to update last processed block:', error);
      throw error;
    }
  }

  async catchUpMissedEvents(): Promise<void> {
    if (this.isSyncing) {
      this.logger.warn('Sync already in progress, skipping catchup');
      return;
    }

    this.isSyncing = true;

    try {
      const currentBlock = await this.provider.getBlockNumber();
      const lastProcessedBlock = await this.getLastProcessedBlock();

      if (currentBlock <= lastProcessedBlock) {
        this.logger.log('No missed events to catch up on');
        return;
      }

      const blocksBehind = currentBlock - lastProcessedBlock;
      this.logger.log(`Catching up on ${blocksBehind} blocks (${lastProcessedBlock + 1} to ${currentBlock})`);

      await this.processBlockRange(lastProcessedBlock + 1, currentBlock);

      this.logger.log(`Successfully caught up to block ${currentBlock}`);

    } catch (error) {
      this.logger.error('Failed to catch up on missed events:', error);
      await this.markSyncUnhealthy(error);
      throw error;
    } finally {
      this.isSyncing = false;
    }
  }

  async processBlockRange(fromBlock: number, toBlock: number): Promise<void> {
    const maxBlocksPerBatch = this.configService.get<number>('indexer.maxBlocksPerBatch');

    let currentFromBlock = fromBlock;

    while (currentFromBlock <= toBlock) {
      const currentToBlock = Math.min(currentFromBlock + maxBlocksPerBatch - 1, toBlock);

      this.logger.log(`Processing blocks ${currentFromBlock} to ${currentToBlock}`);

      try {
        await this.processBlockBatch(currentFromBlock, currentToBlock);
        await this.updateLastProcessedBlock(currentToBlock);

        // Small delay to avoid overwhelming the RPC
        await new Promise(resolve => setTimeout(resolve, 100));

      } catch (error) {
        this.logger.error(`Failed to process blocks ${currentFromBlock} to ${currentToBlock}:`, error);

        // If batch fails, try smaller batches or individual blocks
        if (currentToBlock - currentFromBlock > 0) {
          this.logger.log('Retrying with smaller batch size');
          await this.processBlocksIndividually(currentFromBlock, currentToBlock);
        } else {
          throw error;
        }
      }

      currentFromBlock = currentToBlock + 1;
    }
  }

  private async processBlockBatch(fromBlock: number, toBlock: number): Promise<void> {
    try {
      // Query Transfer events for this block range
      const filter = this.contract.filters.Transfer();
      const transferEvents = await this.contract.queryFilter(filter, fromBlock, toBlock);

      this.logger.debug(`Found ${transferEvents.length} Transfer events in blocks ${fromBlock}-${toBlock}`);

      // Query MetadataUpdated events for this block range
      const filter2 = this.contract.filters.MetadataUpdated();
      const metadataEvents = await this.contract.queryFilter(filter2, fromBlock, toBlock);

      this.logger.debug(`Found ${metadataEvents.length} MetadataUpdated events in blocks ${fromBlock}-${toBlock}`);

      // Process transfer events in chunks to avoid database limits
      if (transferEvents.length > 0) {
        const maxBatchSize = this.configService.get<number>('indexer.maxTransferBatchSize') || 1000;
        
        for (let i = 0; i < transferEvents.length; i += maxBatchSize) {
          const chunk = transferEvents.slice(i, i + maxBatchSize);
          this.logger.debug(`Processing transfer events chunk ${Math.floor(i / maxBatchSize) + 1}/${Math.ceil(transferEvents.length / maxBatchSize)} (${chunk.length} events)`);
          
          try {
            await this.transferProcessor.processTransferEventsBatch(chunk);
          } catch (error) {
            this.logger.error(`Failed to process transfer events chunk starting at index ${i}:`, error);
            
            // If chunk fails, fall back to individual processing for this chunk
            this.logger.log(`Falling back to individual processing for chunk starting at index ${i}`);
            for (const event of chunk) {
              try {
                await this.processTransferEvent(event);
              } catch (individualError) {
                this.logger.error(`Failed to process individual event in chunk fallback:`, individualError);
                // Continue with other events even if one fails
              }
            }
          }
        }
      }

      // Process metadata events individually (existing logic)
      for (const event of metadataEvents) {
        try {
          await this.processMetadataUpdatedEvent(event);
        } catch (error) {
          this.logger.error(`Failed to process MetadataUpdated event at block ${event.blockNumber}:`, error);
          // Continue processing other events even if one fails
        }
      }

    } catch (error) {
      this.logger.error(`Failed to fetch events for blocks ${fromBlock}-${toBlock}:`, error);
      throw error;
    }
  }

  private async processMetadataUpdatedEvent(
    event: TypedEventLog<TypedContractEvent<MetadataUpdatedEvent.InputTuple, MetadataUpdatedEvent.OutputTuple, MetadataUpdatedEvent.OutputObject>>,
  ) {
    try {
      // Get additional event details
      const block = await event.getBlock();

      const metadataEventData: MetadataUpdatedEventData = {
        tokenId: event.args.tokenId,
        transactionHash: event.transactionHash,
        blockNumber: event.blockNumber,
        blockHash: event.blockHash,
        logIndex: event.index,
        timestamp: block.timestamp,
        contractAddress: this.configService.get<string>('blockchain.contractAddress'),
      };

      await this.metadataProcessor.processMetadataUpdatedEvent(metadataEventData);

      const eventType = event.args.tokenId === BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
        ? 'bulk refresh'
        : `token ${event.args.tokenId}`;
      this.logger.log(
        `Processed MetadataUpdated: ${eventType} (block ${event.blockNumber})`
      );
    } catch (error) {
      this.logger.error(`Failed to handle MetadataUpdated event for token ${event.args.tokenId}:`, error);
      throw error;
    }
  }

  private async processBlocksIndividually(fromBlock: number, toBlock: number): Promise<void> {
    for (let block = fromBlock; block <= toBlock; block++) {
      try {
        await this.processBlockBatch(block, block);
        await this.updateLastProcessedBlock(block);
      } catch (error) {
        this.logger.error(`Failed to process individual block ${block}:`, error);
        // Mark this block as problematic but continue
        await this.markSyncUnhealthy(error);
      }
    }
  }

  private async processTransferEvent(event: any): Promise<void> {
    try {
      // Extract event arguments
      const [from, to, tokenId] = event.args;

      // Get block and transaction details
      const block = await event.getBlock();
      const transaction = await event.getTransaction();

      const transferData: TransferEventData = {
        from,
        to,
        tokenId,
        transactionHash: event.transactionHash,
        blockNumber: event.blockNumber,
        blockHash: event.blockHash,
        logIndex: event.index,
        gasUsed: transaction.gasLimit,
        gasPrice: transaction.gasPrice,
        timestamp: block.timestamp,
        contractAddress: this.contractAddress.toLowerCase(),
      };

      await this.transferProcessor.processTransferEvent(transferData);

    } catch (error) {
      this.logger.error(`Failed to process Transfer event:`, error);
      throw error;
    }
  }

  private async markSyncUnhealthy(error: any): Promise<void> {
    const db = this.databaseService.db;

    try {
      await db
        .update(syncState)
        .set({
          isHealthy: false,
          errorMessage: error.message || 'Unknown sync error',
          updatedAt: new Date(),
        })
        .where(eq(syncState.contractAddress, this.contractAddress.toLowerCase()));
    } catch (dbError) {
      this.logger.error('Failed to mark sync as unhealthy:', dbError);
    }
  }

  // Scheduled sync check every 5 minutes
  // @Cron(CronExpression.EVERY_5_MINUTES)
  // async scheduledSync(): Promise<void> {
  //   if (this.isSyncing) {
  //     this.logger.debug('Sync already in progress, skipping scheduled sync');
  //     return;
  //   }

  //   try {
  //     await this.catchUpMissedEvents();
  //   } catch (error) {
  //     this.logger.error('Scheduled sync failed:', error);
  //   }
  // }

  // Retry failed operations every 10 minutes
  @Cron(CronExpression.EVERY_10_MINUTES)
  async retryFailedOperations(): Promise<void> {
    try {
      await this.transferProcessor.retryFailedOperations();
    } catch (error) {
      this.logger.error('Failed to retry failed operations:', error);
    }
  }

  async getSyncStatus() {
    const db = this.databaseService.db;

    try {
      const currentBlock = await this.provider.getBlockNumber();
      const lastProcessedBlock = await this.getLastProcessedBlock();

      const state = await db
        .select()
        .from(syncState)
        .where(eq(syncState.contractAddress, this.contractAddress.toLowerCase()))
        .limit(1);

      const syncStateRecord = state.length > 0 ? state[0] : null;

      // Get latest transfer processed
      const latestTransfer = await db
        .select()
        .from(transferEvents)
        .where(eq(transferEvents.contractAddress, this.contractAddress.toLowerCase()))
        .orderBy(desc(transferEvents.blockNumber))
        .limit(1);

      return {
        currentBlock,
        lastProcessedBlock,
        blocksBehind: currentBlock - lastProcessedBlock,
        isSyncing: this.isSyncing,
        isHealthy: syncStateRecord?.isHealthy ?? false,
        lastSyncAt: syncStateRecord?.lastProcessedTimestamp,
        errorMessage: syncStateRecord?.errorMessage,
        latestTransferBlock: latestTransfer.length > 0 ? latestTransfer[0].blockNumber : null,
        contractAddress: this.contractAddress,
        deploymentBlock: this.deploymentBlock,
      };
    } catch (error) {
      this.logger.error('Failed to get sync status:', error);
      return {
        currentBlock: 0,
        lastProcessedBlock: 0,
        blocksBehind: 0,
        isSyncing: this.isSyncing,
        isHealthy: false,
        lastSyncAt: null,
        errorMessage: error.message,
        latestTransferBlock: null,
        contractAddress: this.contractAddress,
        deploymentBlock: this.deploymentBlock,
      };
    }
  }

  async forceCatchup(): Promise<{ message: string; status: any }> {
    if (this.isSyncing) {
      return {
        message: 'Sync already in progress',
        status: await this.getSyncStatus(),
      };
    }

    try {
      this.logger.log('Force catchup requested via API');
      await this.catchUpMissedEvents();

      return {
        message: 'Catchup completed successfully',
        status: await this.getSyncStatus(),
      };
    } catch (error) {
      return {
        message: `Catchup failed: ${error.message}`,
        status: await this.getSyncStatus(),
      };
    }
  }

  // Utility method to check if indexer is caught up
  async isCaughtUp(toleranceBlocks: number = 5): Promise<boolean> {
    try {
      const status = await this.getSyncStatus();
      return status.blocksBehind <= toleranceBlocks;
    } catch (error) {
      return false;
    }
  }

  // Method to get processing performance metrics
  async getPerformanceMetrics() {
    const db = this.databaseService.db;

    try {
      // Get transfers processed in last hour
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
      const [recentTransfers] = await db
        .select({ count: sql`count(*)` })
        .from(transferEvents)
        .where(sql`processed_at > ${oneHourAgo}`);

      // Get transfers processed in last 24 hours
      const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
      const [dailyTransfers] = await db
        .select({ count: sql`count(*)` })
        .from(transferEvents)
        .where(sql`processed_at > ${oneDayAgo}`);

      // Get average processing time
      const avgProcessingTime = await db
        .select({
          avgTime: sql`AVG(EXTRACT(EPOCH FROM (processed_at - timestamp)))`,
        })
        .from(transferEvents)
        .where(sql`processed_at > ${oneDayAgo}`);

      return {
        transfersLastHour: Number(recentTransfers.count),
        transfersLast24Hours: Number(dailyTransfers.count),
        averageProcessingDelaySeconds: avgProcessingTime[0]?.avgTime ?
          Math.round(Number(avgProcessingTime[0].avgTime)) : 0,
      };
    } catch (error) {
      this.logger.error('Failed to get performance metrics:', error);
      return {
        transfersLastHour: 0,
        transfersLast24Hours: 0,
        averageProcessingDelaySeconds: 0,
      };
    }
  }
}
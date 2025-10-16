import { Injectable, Logger } from '@nestjs/common';
import { eq, and, gt, sql } from 'drizzle-orm';
import { DatabaseService } from '../database/database.service';
import { nfts, transferEvents, failedOperations, FailedOperation } from '../database/schema';
import { TransferEventData } from './event-listener.service';
import { TransferEvent } from '@/types/KttyWorldCompanions';
import { TypedContractEvent, TypedEventLog } from '@/types/common';

@Injectable()
export class TransferProcessorService {
  private readonly logger = new Logger(TransferProcessorService.name);
  private readonly ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

  constructor(
    private databaseService: DatabaseService,
  ) {}

  async processTransferEventsBatch(events: TypedEventLog<TypedContractEvent<TransferEvent.InputTuple, TransferEvent.OutputTuple, TransferEvent.OutputObject>>[]): Promise<void> {
    if (events.length === 0) return;

    const db = this.databaseService.db;
    
    try {
      // Convert all events to transfer data
      const transferDataPromises = events.map(async (event) => {
        const [from, to, tokenId] = event.args;
        const block = await event.getBlock();
        const transaction = await event.getTransaction();

        return {
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
          contractAddress: event.address.toLowerCase(),
        };
      });

      const allTransferData = await Promise.all(transferDataPromises);

      // Check for already processed events
      const existingEventKeys = new Set();
      if (allTransferData.length > 0) {
        const existing = await db
          .select({ 
            transactionHash: transferEvents.transactionHash, 
            logIndex: transferEvents.logIndex 
          })
          .from(transferEvents)
          .where(
            sql`(transaction_hash, log_index) IN ${sql.raw(
              `(${allTransferData.map(t => `('${t.transactionHash}', ${t.logIndex})`).join(', ')})`
            )}`
          );

        existing.forEach(e => {
          existingEventKeys.add(`${e.transactionHash}:${e.logIndex}`);
        });
      }

      // Filter out already processed events
      const newTransferData = allTransferData.filter(transferData => 
        !existingEventKeys.has(`${transferData.transactionHash}:${transferData.logIndex}`)
      );

      if (newTransferData.length === 0) {
        this.logger.debug('All transfer events in batch already processed');
        return;
      }

      // Separate by operation type for optimized processing
      const mintEvents = newTransferData.filter(t => t.from.toLowerCase() === this.ZERO_ADDRESS);
      const burnEvents = newTransferData.filter(t => t.to.toLowerCase() === this.ZERO_ADDRESS);
      const transferOnlyEvents = newTransferData.filter(t => 
        t.from.toLowerCase() !== this.ZERO_ADDRESS && t.to.toLowerCase() !== this.ZERO_ADDRESS
      );

      // Process all events in a single transaction
      await db.transaction(async (tx) => {
        // Bulk insert all transfer events
        if (newTransferData.length > 0) {
          const transferEventRecords = newTransferData.map(transferData => ({
            transactionHash: transferData.transactionHash,
            blockNumber: transferData.blockNumber,
            blockHash: transferData.blockHash,
            logIndex: transferData.logIndex,
            tokenId: Number(transferData.tokenId),
            fromAddress: transferData.from.toLowerCase(),
            toAddress: transferData.to.toLowerCase(),
            contractAddress: transferData.contractAddress.toLowerCase(),
            gasUsed: transferData.gasUsed ? Number(transferData.gasUsed) : null,
            gasPrice: transferData.gasPrice ? Number(transferData.gasPrice) : null,
            timestamp: new Date(transferData.timestamp * 1000),
          }));

          await tx.insert(transferEvents).values(transferEventRecords);
        }

        // Bulk insert mint NFTs
        if (mintEvents.length > 0) {
          const nftRecords = mintEvents.map(transferData => ({
            tokenId: Number(transferData.tokenId),
            currentOwner: transferData.to.toLowerCase(),
            contractAddress: transferData.contractAddress.toLowerCase(),
            createdAt: new Date(transferData.timestamp * 1000),
            updatedAt: new Date(transferData.timestamp * 1000),
          }));

          await tx.insert(nfts).values(nftRecords);
        }

        // Process burns and transfers individually (since they need updates)
        for (const transferData of [...burnEvents, ...transferOnlyEvents]) {
          const tokenId = Number(transferData.tokenId);
          const isBurn = transferData.to.toLowerCase() === this.ZERO_ADDRESS;

          if (isBurn) {
            await this.handleBurn(tx, tokenId, transferData);
          } else {
            await this.handleTransfer(tx, tokenId, transferData);
          }
        }
      });

      this.logger.log(
        `Successfully processed batch: ${mintEvents.length} mints, ${burnEvents.length} burns, ${transferOnlyEvents.length} transfers`
      );

    } catch (error) {
      this.logger.error(`Failed to process transfer events batch:`, error);
      
      // Fallback to individual processing for failed batch
      this.logger.log('Falling back to individual event processing');
      for (const event of events) {
        try {
          await this.processTransferEventLegacy(event);
        } catch (individualError) {
          this.logger.error(`Failed to process individual event in fallback:`, individualError);
        }
      }
      
      throw error;
    }
  }

  async processTransferEvent(transferData: TransferEventData): Promise<void> {
    const db = this.databaseService.db;
    
    try {
      // Check if this transfer event has already been processed
      const existingTransfer = await db
        .select()
        .from(transferEvents)
        .where(
          and(
            eq(transferEvents.transactionHash, transferData.transactionHash),
            eq(transferEvents.logIndex, transferData.logIndex)
          )
        )
        .limit(1);

      if (existingTransfer.length > 0) {
        this.logger.debug(`Transfer event already processed: ${transferData.transactionHash}:${transferData.logIndex}`);
        return;
      }

      // Process the transfer in a transaction
      await db.transaction(async (tx) => {
        // Insert transfer event record
        await tx.insert(transferEvents).values({
          transactionHash: transferData.transactionHash,
          blockNumber: transferData.blockNumber,
          blockHash: transferData.blockHash,
          logIndex: transferData.logIndex,
          tokenId: Number(transferData.tokenId),
          fromAddress: transferData.from.toLowerCase(),
          toAddress: transferData.to.toLowerCase(),
          contractAddress: transferData.contractAddress.toLowerCase(),
          gasUsed: transferData.gasUsed ? Number(transferData.gasUsed) : null,
          gasPrice: transferData.gasPrice ? Number(transferData.gasPrice) : null,
          timestamp: new Date(transferData.timestamp * 1000),
        });

        // Handle NFT record creation/update
        const tokenId = Number(transferData.tokenId);
        const isMint = transferData.from.toLowerCase() === this.ZERO_ADDRESS;
        const isBurn = transferData.to.toLowerCase() === this.ZERO_ADDRESS;

        if (isMint) {
          await this.handleMint(tx, tokenId, transferData);
        } else if (isBurn) {
          await this.handleBurn(tx, tokenId, transferData);
        } else {
          await this.handleTransfer(tx, tokenId, transferData);
        }
      });

      this.logger.log(
        `Successfully processed ${this.getTransferType(transferData)}: token ${transferData.tokenId} from ${transferData.from} to ${transferData.to}`
      );

    } catch (error) {
      this.logger.error(`Failed to process transfer event for token ${transferData.tokenId}:`, error);
      
      // Record failed operation for retry
      await this.recordFailedOperation('transfer_event', transferData, error);
      throw error;
    }
  }

  private async processTransferEventLegacy(event: any): Promise<void> {
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
        contractAddress: event.address.toLowerCase(),
      };

      await this.processTransferEvent(transferData);

    } catch (error) {
      this.logger.error(`Failed to process Transfer event in legacy mode:`, error);
      throw error;
    }
  }

  private async handleMint(tx: any, tokenId: number, transferData: TransferEventData): Promise<void> {
    // Create new NFT record
    const newNft = {
      tokenId,
      currentOwner: transferData.to.toLowerCase(),
      contractAddress: transferData.contractAddress.toLowerCase(),
      createdAt: new Date(transferData.timestamp * 1000),
      updatedAt: new Date(transferData.timestamp * 1000),
    };

    await tx.insert(nfts).values(newNft);

    this.logger.log(`Minted token ${tokenId} to ${transferData.to}`);
  }

  private async handleBurn(tx: any, tokenId: number, transferData: TransferEventData): Promise<void> {
    // Update NFT record to reflect burn
    const updated = await tx
      .update(nfts)
      .set({
        currentOwner: this.ZERO_ADDRESS,
        updatedAt: new Date(transferData.timestamp * 1000),
      })
      .where(eq(nfts.tokenId, tokenId))
      .returning();

    if (updated.length === 0) {
      this.logger.warn(`Attempted to burn non-existent token ${tokenId}`);
    } else {
      this.logger.log(`Burned token ${tokenId} from ${transferData.from}`);
    }
  }

  private async handleTransfer(tx: any, tokenId: number, transferData: TransferEventData): Promise<void> {
    // Update NFT owner
    const updated = await tx
      .update(nfts)
      .set({
        currentOwner: transferData.to.toLowerCase(),
        updatedAt: new Date(transferData.timestamp * 1000),
      })
      .where(eq(nfts.tokenId, tokenId))
      .returning();

    if (updated.length === 0) {
      // This shouldn't happen in normal circumstances - token should exist before transfer
      this.logger.error(`Attempted to transfer non-existent token ${tokenId}`);
      
      // Create the NFT record anyway (might be a recovery scenario)
      await tx.insert(nfts).values({
        tokenId,
        currentOwner: transferData.to.toLowerCase(),
        contractAddress: transferData.contractAddress.toLowerCase(),
        createdAt: new Date(transferData.timestamp * 1000),
        updatedAt: new Date(transferData.timestamp * 1000),
      });

      this.logger.warn(`Created missing NFT record for token ${tokenId} during transfer`);
    }

    this.logger.log(`Transferred token ${tokenId} from ${transferData.from} to ${transferData.to}`);
  }

  private getTransferType(transferData: TransferEventData): string {
    if (transferData.from.toLowerCase() === this.ZERO_ADDRESS) return 'MINT';
    if (transferData.to.toLowerCase() === this.ZERO_ADDRESS) return 'BURN';
    return 'TRANSFER';
  }

  private async recordFailedOperation(
    operationType: string,
    transferData: TransferEventData,
    error: any
  ): Promise<void> {
    try {
      const db = this.databaseService.db;
      
      // Get current owner for validation during retry
      let lastKnownOwner: string | null = null;
      try {
        const nft = await db
          .select({ currentOwner: nfts.currentOwner })
          .from(nfts)
          .where(eq(nfts.tokenId, Number(transferData.tokenId)))
          .limit(1);
        
        lastKnownOwner = nft.length > 0 ? nft[0].currentOwner : null;
      } catch (nftError) {
        this.logger.warn(`Could not get current owner for token ${transferData.tokenId}:`, nftError);
      }

      await db.insert(failedOperations).values({
        operationType,
        entityId: `${transferData.transactionHash}:${transferData.logIndex}`,
        tokenId: Number(transferData.tokenId),
        blockNumber: transferData.blockNumber,
        timestamp: new Date(transferData.timestamp * 1000),
        errorMessage: error.message || 'Unknown error',
        errorStack: error.stack,
        data: transferData,
        lastKnownOwner,
      });
    } catch (dbError) {
      this.logger.error('Failed to record failed operation:', dbError);
    }
  }

  async retryFailedOperations(): Promise<void> {
    const db = this.databaseService.db;
    
    try {
      // Get unresolved, non-superseded failed operations for transfer events
      // Order by blockNumber to ensure chronological processing
      const failedTransfers = await db
        .select()
        .from(failedOperations)
        .where(
          and(
            eq(failedOperations.operationType, 'transfer_event'),
            eq(failedOperations.resolved, false),
            eq(failedOperations.superseded, false)
          )
        )
        .orderBy(failedOperations.blockNumber, failedOperations.lastAttemptAt)
        .limit(10); // Process up to 10 at a time

      for (const failed of failedTransfers) {
        try {
          // Exponential backoff: don't retry if last attempt was too recent
          const timeSinceLastAttempt = Date.now() - failed.lastAttemptAt.getTime();
          const minDelay = Math.pow(2, failed.attempts) * 1000; // 2^attempts seconds
          
          if (timeSinceLastAttempt < minDelay) {
            continue;
          }

          // Check if this operation should be superseded by newer transfers
          const shouldSupersede = await this.checkIfSuperseded(failed);
          if (shouldSupersede) {
            await this.markSuperseded(failed.id, 'Newer transfers found for this token');
            continue;
          }

          // Safe to retry
          await this.processTransferEvent(failed.data as TransferEventData);
          
          // Mark as resolved
          await db
            .update(failedOperations)
            .set({
              resolved: true,
              resolvedAt: new Date(),
            })
            .where(eq(failedOperations.id, failed.id));

          this.logger.log(`Successfully retried failed transfer operation: ${failed.entityId}`);
          
        } catch (error) {
          // Update attempt count
          await db
            .update(failedOperations)
            .set({
              attempts: failed.attempts + 1,
              lastAttemptAt: new Date(),
              errorMessage: error.message || 'Unknown error',
              errorStack: error.stack,
            })
            .where(eq(failedOperations.id, failed.id));

          this.logger.error(`Retry failed for operation ${failed.entityId}:`, error);
        }
      }
    } catch (error) {
      this.logger.error('Error during retry of failed operations:', error);
    }
  }

  async getProcessingStats() {
    const db = this.databaseService.db;
    
    try {
      const [nftCount] = await db.select({ count: sql`count(*)` }).from(nfts);
      const [transferCount] = await db.select({ count: sql`count(*)` }).from(transferEvents);
      const [failedCount] = await db
        .select({ count: sql`count(*)` })
        .from(failedOperations)
        .where(eq(failedOperations.resolved, false));

      return {
        totalNfts: Number(nftCount.count),
        totalTransfers: Number(transferCount.count),
        failedOperations: Number(failedCount.count),
      };
    } catch (error) {
      this.logger.error('Error getting processing stats:', error);
      return {
        totalNfts: 0,
        totalTransfers: 0,
        failedOperations: 0,
      };
    }
  }

  /**
   * Check if a failed operation should be superseded by newer transfers
   */
  private async checkIfSuperseded(failedOp: FailedOperation): Promise<boolean> {
    if (!failedOp.tokenId || !failedOp.blockNumber) {
      return false; // Can't check without token ID and block number
    }

    const db = this.databaseService.db;
    
    try {
      // Look for newer transfers for the same token
      const newerTransfers = await db
        .select({ count: sql`count(*)` })
        .from(transferEvents)
        .where(
          and(
            eq(transferEvents.tokenId, failedOp.tokenId),
            gt(transferEvents.blockNumber, failedOp.blockNumber)
          )
        );

      const hasNewerTransfers = Number(newerTransfers[0].count) > 0;
      
      if (hasNewerTransfers) {
        this.logger.log(
          `Found newer transfers for token ${failedOp.tokenId} after block ${failedOp.blockNumber}`
        );
        return true;
      }

      // Also check for transfers in the same block but with higher log index
      if (failedOp.data && typeof failedOp.data === 'object' && 'logIndex' in failedOp.data) {
        const sameBlockNewerLogs = await db
          .select({ count: sql`count(*)` })
          .from(transferEvents)
          .where(
            and(
              eq(transferEvents.tokenId, failedOp.tokenId),
              eq(transferEvents.blockNumber, failedOp.blockNumber),
              gt(transferEvents.logIndex, (failedOp.data as any).logIndex)
            )
          );

        return Number(sameBlockNewerLogs[0].count) > 0;
      }

      return false;
    } catch (error) {
      this.logger.error(`Error checking supersession for operation ${failedOp.id}:`, error);
      return false; // Conservative: don't supersede on error
    }
  }

  /**
   * Mark a failed operation as superseded
   */
  private async markSuperseded(operationId: number, reason: string): Promise<void> {
    const db = this.databaseService.db;
    
    try {
      await db
        .update(failedOperations)
        .set({
          superseded: true,
          errorMessage: reason,
          resolvedAt: new Date(),
        })
        .where(eq(failedOperations.id, operationId));

      this.logger.log(`Marked operation ${operationId} as superseded: ${reason}`);
    } catch (error) {
      this.logger.error(`Error marking operation ${operationId} as superseded:`, error);
    }
  }
}
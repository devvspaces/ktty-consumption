import { Injectable, Inject, Logger } from '@nestjs/common';
import { DrizzleDB } from 'drizzle-orm/postgres-js';
import { eq, and, inArray } from 'drizzle-orm';
import {
  processedEvents,
  batchTransactions,
  systemState,
  eventProcessingQueue,
  ProcessedEvent,
  NewProcessedEvent,
  BatchTransaction,
  NewBatchTransaction,
  SystemState,
  NewSystemState,
  EventProcessingQueue,
  NewEventProcessingQueue,
} from './schema';
import { DATABASE_CONNECTION } from './database.module';

@Injectable()
export class DatabaseService {
  private readonly logger = new Logger(DatabaseService.name);

  constructor(
    @Inject(DATABASE_CONNECTION) private readonly db: DrizzleDB<any>,
  ) {}

  // System State Management
  async getSystemState(key: string): Promise<SystemState | null> {
    try {
      const result = await this.db
        .select()
        .from(systemState)
        .where(eq(systemState.key, key))
        .limit(1);

      return result[0] || null;
    } catch (error) {
      this.logger.error(`Failed to get system state for key ${key}:`, error);
      throw error;
    }
  }

  async setSystemState(key: string, value: string): Promise<void> {
    try {
      await this.db
        .insert(systemState)
        .values({ key, value })
        .onConflictDoUpdate({
          target: systemState.key,
          set: { value, updatedAt: new Date() },
        });
    } catch (error) {
      this.logger.error(`Failed to set system state for key ${key}:`, error);
      throw error;
    }
  }

  async getLastProcessedBlock(): Promise<number> {
    const state = await this.getSystemState('lastProcessedBlock');
    return state ? parseInt(state.value) : 0;
  }

  async setLastProcessedBlock(blockNumber: number): Promise<void> {
    await this.setSystemState('lastProcessedBlock', blockNumber.toString());
  }

  // Processed Events Management
  async isEventProcessed(tokenId: number): Promise<boolean> {
    try {
      const result = await this.db
        .select()
        .from(processedEvents)
        .where(eq(processedEvents.tokenId, tokenId))
        .limit(1);

      return result.length > 0;
    } catch (error) {
      this.logger.error(`Failed to check if event is processed for token ${tokenId}:`, error);
      throw error;
    }
  }

  async markEventAsProcessed(event: NewProcessedEvent): Promise<void> {
    try {
      await this.db.insert(processedEvents).values(event);
      this.logger.debug(`Marked event as processed for token ${event.tokenId}`);
    } catch (error) {
      this.logger.error(`Failed to mark event as processed for token ${event.tokenId}:`, error);
      throw error;
    }
  }

  // Event Processing Queue Management
  async addToQueue(queueItem: NewEventProcessingQueue): Promise<void> {
    try {
      await this.db.insert(eventProcessingQueue).values(queueItem);
      this.logger.debug(`Added token ${queueItem.tokenId} to processing queue`);
    } catch (error) {
      this.logger.error(`Failed to add token ${queueItem.tokenId} to queue:`, error);
      throw error;
    }
  }

  async getPendingQueueItems(limit: number): Promise<EventProcessingQueue[]> {
    try {
      return await this.db
        .select()
        .from(eventProcessingQueue)
        .where(eq(eventProcessingQueue.processed, false))
        .orderBy(eventProcessingQueue.queuedAt)
        .limit(limit);
    } catch (error) {
      this.logger.error('Failed to get pending queue items:', error);
      throw error;
    }
  }

  async markQueueItemsAsProcessed(
    ids: number[],
    batchTransactionId: number,
  ): Promise<void> {
    try {
      await this.db
        .update(eventProcessingQueue)
        .set({ processed: true, batchTransactionId })
        .where(inArray(eventProcessingQueue.id, ids));
    } catch (error) {
      this.logger.error('Failed to mark queue items as processed:', error);
      throw error;
    }
  }

  // Batch Transaction Management
  async createBatchTransaction(
    batchData: NewBatchTransaction,
  ): Promise<BatchTransaction> {
    try {
      const result = await this.db
        .insert(batchTransactions)
        .values(batchData)
        .returning();

      const batch = result[0];
      this.logger.debug(`Created batch transaction with ${batch.tokenIds.length} tokens`);
      return batch;
    } catch (error) {
      this.logger.error('Failed to create batch transaction:', error);
      throw error;
    }
  }

  async updateBatchTransaction(
    id: number,
    updates: Partial<BatchTransaction>,
  ): Promise<void> {
    try {
      await this.db
        .update(batchTransactions)
        .set(updates)
        .where(eq(batchTransactions.id, id));
    } catch (error) {
      this.logger.error(`Failed to update batch transaction ${id}:`, error);
      throw error;
    }
  }

  async getPendingBatchTransactions(): Promise<BatchTransaction[]> {
    try {
      return await this.db
        .select()
        .from(batchTransactions)
        .where(eq(batchTransactions.status, 'pending'));
    } catch (error) {
      this.logger.error('Failed to get pending batch transactions:', error);
      throw error;
    }
  }

  // Health Check
  async healthCheck(): Promise<boolean> {
    try {
      await this.db.select().from(systemState).limit(1);
      return true;
    } catch (error) {
      this.logger.error('Database health check failed:', error);
      return false;
    }
  }
}
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { eq, and } from 'drizzle-orm';
import { DatabaseService } from '../database/database.service';
import { metadataEvents, failedOperations } from '../database/schema';
import { MetadataQueueService } from './metadata-queue.service';

export interface MetadataUpdatedEventData {
  tokenId: bigint;
  transactionHash: string;
  blockNumber: number;
  blockHash: string;
  logIndex: number;
  timestamp: number;
  contractAddress: string;
}

@Injectable()
export class MetadataProcessorService {
  private readonly logger = new Logger(MetadataProcessorService.name);
  private readonly MAX_UINT256 = BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff');

  constructor(
    private databaseService: DatabaseService,
    private metadataQueueService: MetadataQueueService,
    private configService: ConfigService,
  ) { }

  async processMetadataUpdatedEvent(eventData: MetadataUpdatedEventData): Promise<void> {
    const db = this.databaseService.db;

    // Check if this event has already been processed
    const existingEvent = await db
      .select()
      .from(metadataEvents)
      .where(
        and(
          eq(metadataEvents.transactionHash, eventData.transactionHash),
          eq(metadataEvents.logIndex, eventData.logIndex)
        )
      )
      .limit(1);

    if (existingEvent.length > 0) {
      this.logger.debug(`MetadataUpdated event already processed: ${eventData.transactionHash}:${eventData.logIndex}`);
      return;
    }

    // Process the event in a transaction
    await db.transaction(async (tx) => {
      // Determine if this is a bulk refresh or single token update
      const isBulkRefresh = eventData.tokenId === this.MAX_UINT256;

      // Insert metadata event record
      await tx.insert(metadataEvents).values({
        transactionHash: eventData.transactionHash,
        blockNumber: eventData.blockNumber,
        blockHash: eventData.blockHash,
        logIndex: eventData.logIndex,
        tokenId: isBulkRefresh ? -1 : Number(eventData.tokenId), // Use -1 to represent max uint256
        contractAddress: eventData.contractAddress.toLowerCase(),
        timestamp: new Date(eventData.timestamp * 1000),
      });

      if (isBulkRefresh) {
        // Bulk refresh - queue job to refresh all tokens
        this.logger.log('MetadataUpdated event with max uint256 - triggering bulk metadata refresh');
        await this.metadataQueueService.addBulkRefreshJob('metadata_updated_all');
      } else {
        // Single token refresh
        const tokenId = Number(eventData.tokenId);
        this.logger.log(`MetadataUpdated event for token ${tokenId} - queuing metadata fetch`);
        await this.metadataQueueService.addSingleTokenJob(tokenId, 3, 'metadata_updated'); // Medium-high priority
      }
    });

    const eventType = eventData.tokenId === this.MAX_UINT256 ? 'bulk refresh' : `token ${eventData.tokenId}`;
    this.logger.log(`Successfully processed MetadataUpdated event for ${eventType}`);
  }

  async getProcessingStats() {
    const db = this.databaseService.db;

    try {
      const [eventCount] = await db.select({ count: sql`count(*)` }).from(metadataEvents);
      const [failedCount] = await db
        .select({ count: sql`count(*)` })
        .from(failedOperations)
        .where(
          and(
            eq(failedOperations.operationType, 'metadata_event'),
            eq(failedOperations.resolved, false)
          )
        );

      const queueStats = this.metadataQueueService.getQueueStats();

      return {
        totalMetadataEvents: Number(eventCount.count),
        failedMetadataEvents: Number(failedCount.count),
        ...queueStats,
      };
    } catch (error) {
      this.logger.error('Error getting metadata processing stats:', error);
      return {
        totalMetadataEvents: 0,
        failedMetadataEvents: 0,
        queueSize: 0,
        processing: 0,
        deadLetterQueue: 0,
        maxConcurrent: 0,
      };
    }
  }
}

import { sql } from 'drizzle-orm';
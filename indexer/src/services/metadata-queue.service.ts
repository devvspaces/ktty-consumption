import { Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue, Job } from 'bullmq';
import { DatabaseService } from '../database/database.service';
import { nfts } from '../database/schema';
import { ConfigService } from '@nestjs/config';

export interface SingleTokenJobData {
  tokenId: number;
  priority?: number;
  reason: 'metadata_updated' | 'retry' | 'manual';
}

export interface BulkRefreshJobData {
  reason: 'metadata_updated_all' | 'manual';
  batchSize?: number;
}

@Injectable()
export class MetadataQueueService {
  private readonly logger = new Logger(MetadataQueueService.name);

  constructor(
    @InjectQueue('metadata') private metadataQueue: Queue,
    private databaseService: DatabaseService,
    private configService: ConfigService,
  ) {}

  async addSingleTokenJob(
    tokenId: number, 
    priority: number = 5,
    reason: SingleTokenJobData['reason'] = 'metadata_updated'
  ): Promise<string> {
    const jobData: SingleTokenJobData = {
      tokenId,
      priority,
      reason,
    };

    // Remove any existing jobs for this token to avoid duplicates
    await this.removeDuplicateTokenJobs(tokenId);

    const job = await this.metadataQueue.add(
      'fetch-single-token',
      jobData,
      {
        priority: priority,
        attempts: this.configService.get<number>('metadata.metadataRetryAttempts', 3),
        backoff: {
          type: 'exponential',
          delay: 2000,
        },
        removeOnComplete: 100, // Keep last 100 completed jobs
        removeOnFail: 50, // Keep last 50 failed jobs
        jobId: `token-${tokenId}`, // Use deterministic ID to prevent duplicates
      }
    );

    this.logger.debug(`Added single token job for token ${tokenId} with priority ${priority}`);
    return job.id!;
  }

  async addBulkRefreshJob(
    reason: BulkRefreshJobData['reason'] = 'metadata_updated_all',
    batchSize: number = 50
  ): Promise<string> {
    const jobData: BulkRefreshJobData = {
      reason,
      batchSize,
    };

    // Remove any existing bulk refresh jobs to avoid duplicates
    await this.removeBulkRefreshJobs();

    const job = await this.metadataQueue.add(
      'fetch-all-tokens',
      jobData,
      {
        priority: 1, // High priority
        attempts: this.configService.get<number>('metadata.metadataRetryAttempts', 3),
        backoff: {
          type: 'exponential',
          delay: 5000,
        },
        removeOnComplete: 10,
        removeOnFail: 10,
        jobId: `bulk-refresh-${Date.now()}`,
      }
    );

    this.logger.log(`Added bulk refresh job for reason: ${reason}`);
    return job.id!;
  }

  private async removeDuplicateTokenJobs(tokenId: number): Promise<void> {
    try {
      // Get all waiting and delayed jobs
      const waitingJobs = await this.metadataQueue.getWaiting();
      const delayedJobs = await this.metadataQueue.getDelayed();
      const allJobs = [...waitingJobs, ...delayedJobs];

      for (const job of allJobs) {
        if (
          job.name === 'fetch-single-token' && 
          job.data?.tokenId === tokenId
        ) {
          await job.remove();
        }
      }
    } catch (error) {
      this.logger.warn(`Failed to remove duplicate jobs for token ${tokenId}:`, error);
    }
  }

  private async removeBulkRefreshJobs(): Promise<void> {
    try {
      // Get all waiting and delayed jobs
      const waitingJobs = await this.metadataQueue.getWaiting();
      const delayedJobs = await this.metadataQueue.getDelayed();
      const allJobs = [...waitingJobs, ...delayedJobs];

      for (const job of allJobs) {
        if (job.name === 'fetch-all-tokens') {
          await job.remove();
        }
      }
    } catch (error) {
      this.logger.warn('Failed to remove duplicate bulk refresh jobs:', error);
    }
  }

  async processBulkRefreshJob(job: Job<BulkRefreshJobData>): Promise<void> {
    const { batchSize = 50 } = job.data;
    const db = this.databaseService.db;
    
    // Get all existing NFTs
    const allNfts = await db.select({ tokenId: nfts.tokenId }).from(nfts);
    
    this.logger.log(`Processing bulk refresh for ${allNfts.length} tokens in batches of ${batchSize}`);
    
    // Process in batches to avoid overwhelming the queue
    for (let i = 0; i < allNfts.length; i += batchSize) {
      const batch = allNfts.slice(i, i + batchSize);
      
      // Add individual jobs for each token with lower priority
      const batchPromises = batch.map(nft => 
        this.addSingleTokenJob(nft.tokenId, 8, 'metadata_updated') // Lower priority for bulk jobs
      );
      
      await Promise.all(batchPromises);
      
      // Update job progress
      const progress = Math.round((i + batch.length) / allNfts.length * 100);
      await job.updateProgress(progress);
      
      this.logger.debug(`Queued batch ${Math.floor(i / batchSize) + 1}, progress: ${progress}%`);
    }
    
    this.logger.log(`Successfully queued ${allNfts.length} individual metadata jobs from bulk refresh`);
  }

  async getQueueStats() {
    try {
      const waiting = await this.metadataQueue.getWaiting();
      const active = await this.metadataQueue.getActive();
      const completed = await this.metadataQueue.getCompleted();
      const failed = await this.metadataQueue.getFailed();
      const delayed = await this.metadataQueue.getDelayed();

      return {
        waiting: waiting.length,
        active: active.length,
        completed: completed.length,
        failed: failed.length,
        delayed: delayed.length,
        total: waiting.length + active.length + delayed.length,
      };
    } catch (error) {
      this.logger.error('Error getting queue stats:', error);
      return {
        waiting: 0,
        active: 0,
        completed: 0,
        failed: 0,
        delayed: 0,
        total: 0,
      };
    }
  }

  async pauseQueue(): Promise<void> {
    await this.metadataQueue.pause();
    this.logger.log('Metadata queue paused');
  }

  async resumeQueue(): Promise<void> {
    await this.metadataQueue.resume();
    this.logger.log('Metadata queue resumed');
  }

  async clearQueue(): Promise<void> {
    await this.metadataQueue.drain();
    this.logger.log('Metadata queue cleared');
  }

  async retryAllFailedJobs(): Promise<void> {
    const failedJobs = await this.metadataQueue.getFailed();
    
    for (const job of failedJobs) {
      await job.retry();
    }
    
    this.logger.log(`Retried ${failedJobs.length} failed jobs`);
  }
}
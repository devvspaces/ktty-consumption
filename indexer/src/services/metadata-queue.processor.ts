import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { MetadataService } from './metadata.service';
import { MetadataQueueService, SingleTokenJobData, BulkRefreshJobData } from './metadata-queue.service';

@Processor('metadata')
export class MetadataQueueProcessor extends WorkerHost {
  private readonly logger = new Logger(MetadataQueueProcessor.name);

  constructor(
    private metadataService: MetadataService,
    private metadataQueueService: MetadataQueueService,
  ) {
    super();
  }

  async process(job: Job<SingleTokenJobData | BulkRefreshJobData>): Promise<any> {
    try {
      if (job.name === 'fetch-single-token') {
        return await this.processSingleTokenJob(job as Job<SingleTokenJobData>);
      } else if (job.name === 'fetch-all-tokens') {
        return await this.processBulkRefreshJob(job as Job<BulkRefreshJobData>);
      } else {
        throw new Error(`Unknown job type: ${job.name}`);
      }
    } catch (error) {
      this.logger.error(`Job ${job.id} (${job.name}) failed:`, error);
      throw error;
    }
  }

  private async processSingleTokenJob(job: Job<SingleTokenJobData>): Promise<void> {
    const { tokenId, reason } = job.data;
    
    this.logger.debug(`Processing single token job for token ${tokenId} (reason: ${reason})`);
    
    // Update job progress
    await job.updateProgress(50);
    
    await this.metadataService.fetchAndCacheMetadata(tokenId);
    
    // Complete job progress
    await job.updateProgress(100);
    
    this.logger.debug(`Successfully processed metadata for token ${tokenId}`);
  }

  private async processBulkRefreshJob(job: Job<BulkRefreshJobData>): Promise<void> {
    const { reason } = job.data;
    
    this.logger.log(`Processing bulk refresh job (reason: ${reason})`);
    
    await this.metadataQueueService.processBulkRefreshJob(job);
    
    this.logger.log(`Successfully processed bulk refresh job`);
  }
}
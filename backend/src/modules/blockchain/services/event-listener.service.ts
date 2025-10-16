import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { EventLog, Log, WebSocketProvider } from 'ethers';
import { ContractService } from './contract.service';
import { BatchProcessorService, PendingToken } from './batch-processor.service';
import { DatabaseService } from '../../../database/database.service';
import { KttyWorldCompanions } from '../../../types';

interface TokenRevealedEvent {
  tokenId: bigint;
  blockNumber: number;
  transactionHash: string;
  logIndex: number;
}

@Injectable()
export class EventListenerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(EventListenerService.name);
  private contract: KttyWorldCompanions;
  private isListening = false;
  private shutdownRequested = false;
  private reconnectAttempts = 0;
  private catchupInProgress = false;

  private readonly deploymentBlock: number;
  private readonly maxReconnectAttempts: number;
  private readonly reconnectDelayMs: number;
  private readonly blockRangeLimit: number;
  private readonly catchupBatchSize: number;
  private readonly pollingIntervalMs: number;

  constructor(
    private readonly configService: ConfigService,
    private readonly contractService: ContractService,
    private readonly batchProcessorService: BatchProcessorService,
    private readonly databaseService: DatabaseService,
  ) {
    this.deploymentBlock = this.configService.get<number>('blockchain.deploymentBlock');
    this.maxReconnectAttempts = this.configService.get<number>('events.maxReconnectAttempts');
    this.reconnectDelayMs = this.configService.get<number>('events.reconnectDelayMs');
    this.blockRangeLimit = this.configService.get<number>('events.blockRangeLimit');
    this.catchupBatchSize = this.configService.get<number>('events.catchupBatchSize');
    this.pollingIntervalMs = this.configService.get<number>('events.pollingIntervalMs');
  }

  async onModuleInit() {
    await this.initializeEventListener();
  }

  async onModuleDestroy() {
    this.shutdownRequested = true;
    await this.stopListening();
  }

  /**
   * Initialize event listener with catchup and real-time listening
   */
  private async initializeEventListener(): Promise<void> {
    try {
      this.contract = this.contractService.getContract();
      
      // First, catch up on any missed events
      await this.performCatchup();
      
      // Then start real-time listening
      await this.startListening();
      
    } catch (error) {
      this.logger.error('Failed to initialize event listener:', error);
      throw error;
    }
  }

  /**
   * Perform catchup for missed TokenRevealed events
   */
  private async performCatchup(): Promise<void> {
    if (this.catchupInProgress) {
      this.logger.warn('Catchup already in progress');
      return;
    }

    this.catchupInProgress = true;
    this.logger.log('Starting catchup for missed TokenRevealed events');

    try {
      const currentBlock = await this.contractService.getCurrentBlock();
      const lastProcessedBlock = await this.databaseService.getLastProcessedBlock();
      const startBlock = Math.max(lastProcessedBlock + 1, this.deploymentBlock);

      if (startBlock > currentBlock) {
        this.logger.log('No catchup needed, already up to date');
        this.catchupInProgress = false;
        return;
      }

      this.logger.log(`Catching up from block ${startBlock} to ${currentBlock} (${currentBlock - startBlock + 1} blocks)`);

      // Process in chunks to avoid RPC limits
      for (let fromBlock = startBlock; fromBlock <= currentBlock; fromBlock += this.blockRangeLimit) {
        if (this.shutdownRequested) break;

        const toBlock = Math.min(fromBlock + this.blockRangeLimit - 1, currentBlock);
        await this.processCatchupRange(fromBlock, toBlock);

        // Update progress
        await this.databaseService.setLastProcessedBlock(toBlock);
      }

      this.logger.log(`Catchup completed. Processed up to block ${currentBlock}`);

    } catch (error) {
      this.logger.error('Catchup failed:', error);
      throw error;
    } finally {
      this.catchupInProgress = false;
    }
  }

  /**
   * Process a specific block range for catchup
   */
  private async processCatchupRange(fromBlock: number, toBlock: number): Promise<void> {
    try {
      this.logger.debug(`Processing catchup range: ${fromBlock} to ${toBlock}`);

      const filter = this.contract.filters.TokenRevealed();
      const events = await this.contract.queryFilter(filter, fromBlock, toBlock);

      this.logger.debug(`Found ${events.length} TokenRevealed events in range ${fromBlock}-${toBlock}`);

      // Process events in smaller batches to avoid overwhelming the system
      for (let i = 0; i < events.length; i += this.catchupBatchSize) {
        if (this.shutdownRequested) break;

        const batch = events.slice(i, i + this.catchupBatchSize);
        await Promise.all(batch.map(event => this.processTokenRevealedEvent(event as EventLog)));

        // Small delay between batches to prevent overwhelming
        if (i + this.catchupBatchSize < events.length) {
          await new Promise(resolve => setTimeout(resolve, 100));
        }
      }

    } catch (error) {
      this.logger.error(`Failed to process catchup range ${fromBlock}-${toBlock}:`, error);
      throw error;
    }
  }

  /**
   * Start real-time event listening
   */
  private async startListening(): Promise<void> {
    if (this.isListening) {
      this.logger.warn('Event listener already running');
      return;
    }

    try {
      this.logger.log('Starting real-time event listener');

      // Check if we have WebSocket provider for real-time events
      const provider = this.contractService.getProvider();
      if (provider instanceof WebSocketProvider) {
        await this.startWebSocketListening();
      } else {
        await this.startPollingListening();
      }

      this.isListening = true;
      this.reconnectAttempts = 0;
      this.logger.log('Event listener started successfully');

    } catch (error) {
      this.logger.error('Failed to start event listener:', error);
      await this.handleConnectionError(error);
    }
  }

  /**
   * Start WebSocket-based event listening
   */
  private async startWebSocketListening(): Promise<void> {
    const provider = this.contractService.getProvider() as WebSocketProvider;

    // Set up event handler
    this.contract.on('TokenRevealed', async (tokenId: bigint, event: Log) => {
      if (!this.shutdownRequested) {
        await this.processTokenRevealedEvent(event as EventLog);
      }
    });

    // Set up connection error handlers
    provider.on('error', async (error: Error) => {
      this.logger.error('WebSocket provider error:', error);
      await this.handleConnectionError(error);
    });

    provider.websocket?.on('close', async (code: number, reason: string) => {
      this.logger.warn(`WebSocket connection closed: ${code} - ${reason}`);
      if (!this.shutdownRequested) {
        await this.handleConnectionError(new Error('WebSocket connection closed'));
      }
    });

    this.logger.log('WebSocket event listening established');
  }

  /**
   * Start polling-based event listening for HTTP providers
   */
  private async startPollingListening(): Promise<void> {
    this.logger.log('Starting polling-based event listening');
    
    const poll = async () => {
      if (this.shutdownRequested || !this.isListening) return;

      try {
        const currentBlock = await this.contractService.getCurrentBlock();
        const lastProcessedBlock = await this.databaseService.getLastProcessedBlock();
        
        if (currentBlock > lastProcessedBlock) {
          const fromBlock = lastProcessedBlock + 1;
          const toBlock = Math.min(fromBlock + this.blockRangeLimit - 1, currentBlock);
          
          await this.processCatchupRange(fromBlock, toBlock);
          await this.databaseService.setLastProcessedBlock(toBlock);
        }

      } catch (error) {
        this.logger.error('Polling error:', error);
        await this.handleConnectionError(error);
      }

      // Schedule next poll
      if (!this.shutdownRequested && this.isListening) {
        setTimeout(poll, this.pollingIntervalMs);
      }
    };

    // Start polling
    setTimeout(poll, this.pollingIntervalMs);
  }

  /**
   * Process a TokenRevealed event
   */
  private async processTokenRevealedEvent(event: EventLog): Promise<void> {
    try {
      const tokenId = BigInt(event.args[0]);
      const blockNumber = event.blockNumber;
      const transactionHash = event.transactionHash;
      const logIndex = event.index;

      this.logger.debug(`Processing TokenRevealed event: token ${tokenId}, block ${blockNumber}, tx ${transactionHash}`);

      // Check if already processed
      const isProcessed = await this.databaseService.isEventProcessed(Number(tokenId));
      if (isProcessed) {
        this.logger.debug(`Token ${tokenId} already processed, skipping`);
        return;
      }

      // Create pending token for batch processing
      const pendingToken: PendingToken = {
        tokenId: Number(tokenId),
        blockNumber,
        transactionHash,
        logIndex,
        queuedAt: new Date(),
      };

      // Queue for batch processing
      await this.batchProcessorService.queueToken(pendingToken);

      this.logger.debug(`Queued token ${tokenId} for batch processing`);

    } catch (error) {
      this.logger.error('Failed to process TokenRevealed event:', error);
    }
  }

  /**
   * Handle connection errors with retry logic
   */
  private async handleConnectionError(error: Error): Promise<void> {
    this.isListening = false;

    if (this.shutdownRequested) {
      return;
    }

    this.reconnectAttempts++;
    
    if (this.reconnectAttempts > this.maxReconnectAttempts) {
      this.logger.error(`Max reconnection attempts (${this.maxReconnectAttempts}) exceeded. Giving up.`);
      return;
    }

    const delay = this.reconnectDelayMs * Math.pow(2, this.reconnectAttempts - 1);
    this.logger.warn(`Connection error. Attempting to reconnect in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`);

    setTimeout(async () => {
      if (!this.shutdownRequested) {
        try {
          await this.startListening();
        } catch (retryError) {
          this.logger.error('Reconnection attempt failed:', retryError);
          await this.handleConnectionError(retryError as Error);
        }
      }
    }, delay);
  }

  /**
   * Stop event listening
   */
  private async stopListening(): Promise<void> {
    this.logger.log('Stopping event listener');
    this.isListening = false;

    if (this.contract) {
      try {
        // Remove all listeners
        this.contract.removeAllListeners('TokenRevealed');
        this.logger.log('Removed all event listeners');
      } catch (error) {
        this.logger.warn('Error removing event listeners:', error);
      }
    }
  }

  /**
   * Get listener status
   */
  getStatus(): {
    isListening: boolean;
    reconnectAttempts: number;
    catchupInProgress: boolean;
  } {
    return {
      isListening: this.isListening,
      reconnectAttempts: this.reconnectAttempts,
      catchupInProgress: this.catchupInProgress,
    };
  }

  /**
   * Force a manual catchup (for admin/testing)
   */
  async forceCatchup(): Promise<void> {
    this.logger.log('Manual catchup requested');
    await this.performCatchup();
  }

  /**
   * Health check for event listener
   */
  async healthCheck(): Promise<boolean> {
    try {
      // Check if contract is accessible
      await this.contractService.getCurrentBlock();
      return this.isListening && !this.catchupInProgress;
    } catch (error) {
      this.logger.error('Event listener health check failed:', error);
      return false;
    }
  }
}
import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ethers } from 'ethers';
import { KttyWorldCompanions } from '../types';
import { TransferEvent, MetadataUpdatedEvent } from '../types/KttyWorldCompanions';
import { TypedContractEvent, TypedEventLog } from '../types/common';
import { TransferProcessorService } from './transfer-processor.service';
import { MetadataProcessorService } from './metadata-processor.service';
import { SyncService } from './sync.service';

export interface TransferEventData {
  from: string;
  to: string;
  tokenId: bigint;
  transactionHash: string;
  blockNumber: number;
  blockHash: string;
  logIndex: number;
  gasUsed?: bigint;
  gasPrice?: bigint;
  timestamp: number;
  contractAddress: string;
}

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
export class EventListenerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(EventListenerService.name);
  private provider: ethers.JsonRpcProvider | ethers.WebSocketProvider;
  private contract: KttyWorldCompanions;
  private isListening = false;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private reconnectDelayMs = 5000;
  private currentProvider: 'websocket' | 'http' = 'websocket';

  constructor(
    private configService: ConfigService,
    private transferProcessor: TransferProcessorService,
    private metadataProcessor: MetadataProcessorService,
    private syncService: SyncService,
  ) {}

  async onModuleInit() {
    await this.initializeProvider();
    this.startListening();
  }

  async onModuleDestroy() {
    await this.stopListening();
  }

  private async initializeProvider() {
    const rpcUrl = this.configService.get<string>('blockchain.rpcUrl');
    const rpcUrlFallback = this.configService.get<string>('blockchain.rpcUrlFallback');
    const contractAddress = this.configService.get<string>('blockchain.contractAddress');


    try {
      // Try WebSocket first
      if (rpcUrl.startsWith('ws')) {
        this.provider = new ethers.WebSocketProvider(rpcUrl);
        this.currentProvider = 'websocket';
        this.logger.log('Initialized WebSocket provider');
      } else {
        this.provider = new ethers.JsonRpcProvider(rpcUrl);
        this.currentProvider = 'http';
        this.logger.log('Initialized HTTP provider');
      }

      // Initialize contract
      this.contract = KttyWorldCompanions__factory.connect(contractAddress, this.provider);
      
      // Test connection
      await this.provider.getBlockNumber();
      this.logger.log(`Connected to ${this.currentProvider} provider successfully`);
      
    } catch (error) {
      this.logger.error('Failed to initialize provider:', error);
      await this.switchToFallbackProvider(rpcUrlFallback);
    }
  }

  private async switchToFallbackProvider(rpcUrlFallback: string) {
    if (!rpcUrlFallback) {
      this.logger.error('No fallback RPC URL configured');
      throw new Error('No fallback RPC URL configured');
    }

    this.logger.warn('Switching to fallback HTTP provider');

    if (rpcUrlFallback.startsWith('ws')) {
      this.provider = new ethers.WebSocketProvider(rpcUrlFallback);
      this.currentProvider = 'websocket';
    } else {
      this.provider = new ethers.JsonRpcProvider(rpcUrlFallback);
      this.currentProvider = 'http';
    }

    const contractAddress = this.configService.get<string>('blockchain.contractAddress');
    this.contract = KttyWorldCompanions__factory.connect(contractAddress, this.provider);
    
    await this.provider.getBlockNumber();
    this.logger.log('Successfully switched to fallback provider');
  }

  async startListening() {
    if (this.isListening) {
      this.logger.warn('Already listening for events');
      return;
    }

    try {
      // First, catch up on any missed events
      await this.syncService.catchUpMissedEvents();

      // Start listening for new events
      if (this.currentProvider === 'websocket') {
        await this.startWebSocketListening();
      } else {
        await this.startPollingListening();
      }

      this.isListening = true;
      this.reconnectAttempts = 0;
      this.logger.log('Started listening for Transfer events');
      
    } catch (error) {
      this.logger.error('Failed to start listening:', error);
      await this.handleConnectionError();
    }
  }

  private async startWebSocketListening() {
    // Listen for Transfer events
    this.contract.on(this.contract.filters.Transfer(), async (from, to, tokenId, event) => {
      try {
        await this.handleTransferEvent(from, to, tokenId, event);
        await this.syncService.updateLastProcessedBlock(event.blockNumber);
      } catch (error) {
        this.logger.error('Error handling Transfer event:', error);
        // Don't throw here to avoid stopping the listener
      }
    });

    // Listen for MetadataUpdated events
    this.contract.on(this.contract.filters.MetadataUpdated(), async (tokenId, event) => {
      try {
        await this.handleMetadataUpdatedEvent(tokenId, event);
        await this.syncService.updateLastProcessedBlock(event.blockNumber);
      } catch (error) {
        this.logger.error('Error handling MetadataUpdated event:', error);
        // Don't throw here to avoid stopping the listener
      }
    });

    // Handle WebSocket errors
    if (this.provider instanceof ethers.WebSocketProvider) {
      (this.provider.websocket as any).on('error', async (error: any) => {
        this.logger.error('WebSocket error:', error);
        await this.handleConnectionError();
      });

      (this.provider.websocket as any).on('close', async () => {
        this.logger.warn('WebSocket connection closed');
        await this.handleConnectionError();
      });
    }
  }

  private async startPollingListening() {
    // For HTTP providers, we need to poll for new blocks
    const pollForEvents = async () => {
      try {
        if (!this.isListening) return;

        const currentBlock = await this.provider.getBlockNumber();
        const lastProcessedBlock = await this.syncService.getLastProcessedBlock();
        
        if (currentBlock > lastProcessedBlock) {
          await this.syncService.processBlockRange(lastProcessedBlock + 1, currentBlock);
        }
      } catch (error) {
        this.logger.error('Error polling for events:', error);
      }
    };

    // Poll every 10 seconds
    setInterval(pollForEvents, 10000);
    this.logger.log('Started polling for events every 10 seconds');
  }

  private async handleTransferEvent(
    from: string,
    to: string,
    tokenId: bigint,
    event: TypedEventLog<TypedContractEvent<TransferEvent.InputTuple, TransferEvent.OutputTuple, TransferEvent.OutputObject>>,
  ) {
    try {
      // Get additional transaction details
      const transaction = await event.getTransaction();
      const block = await event.getBlock();
      
      const transferData: TransferEventData = {
        from,
        to,
        tokenId,
        transactionHash: event.transactionHash,
        blockNumber: event.blockNumber,
        blockHash: event.blockHash,
        logIndex: event.index,
        gasUsed: transaction.gasLimit, // Will be receipt.gasUsed in actual transaction
        gasPrice: transaction.gasPrice,
        timestamp: block.timestamp,
        contractAddress: this.configService.get<string>('blockchain.contractAddress'),
      };

      await this.transferProcessor.processTransferEvent(transferData);
      
      this.logger.log(
        `Processed Transfer: token ${tokenId} from ${from} to ${to} (block ${event.blockNumber})`
      );
      
    } catch (error) {
      this.logger.error(`Failed to handle Transfer event for token ${tokenId}:`, error);
      throw error;
    }
  }

  private async handleMetadataUpdatedEvent(
    tokenId: bigint,
    event: TypedEventLog<TypedContractEvent<MetadataUpdatedEvent.InputTuple, MetadataUpdatedEvent.OutputTuple, MetadataUpdatedEvent.OutputObject>>,
  ) {
    try {
      // Get additional event details
      const block = await event.getBlock();
      
      const metadataEventData: MetadataUpdatedEventData = {
        tokenId,
        transactionHash: event.transactionHash,
        blockNumber: event.blockNumber,
        blockHash: event.blockHash,
        logIndex: event.index,
        timestamp: block.timestamp,
        contractAddress: this.configService.get<string>('blockchain.contractAddress'),
      };

      await this.metadataProcessor.processMetadataUpdatedEvent(metadataEventData);
      
      const eventType = tokenId === BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff') 
        ? 'bulk refresh' 
        : `token ${tokenId}`;
      this.logger.log(
        `Processed MetadataUpdated: ${eventType} (block ${event.blockNumber})`
      );
      
    } catch (error) {
      this.logger.error(`Failed to handle MetadataUpdated event for token ${tokenId}:`, error);
      throw error;
    }
  }

  private async handleConnectionError() {
    this.isListening = false;
    
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      this.logger.error('Max reconnection attempts reached. Stopping.');
      return;
    }

    this.reconnectAttempts++;
    const delay = this.reconnectDelayMs * Math.pow(2, this.reconnectAttempts - 1); // Exponential backoff
    
    this.logger.warn(
      `Connection lost. Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`
    );

    setTimeout(async () => {
      try {
        // Try to switch to fallback if using WebSocket
        if (this.currentProvider === 'websocket' && this.configService.get<string>('blockchain.rpcUrlFallback')) {
          await this.switchToFallbackProvider(this.configService.get<string>('blockchain.rpcUrlFallback'));
        } else {
          await this.initializeProvider();
        }
        
        await this.startListening();
      } catch (error) {
        this.logger.error('Reconnection failed:', error);
        await this.handleConnectionError();
      }
    }, delay);
  }

  async stopListening() {
    this.isListening = false;
    
    if (this.contract) {
      await this.contract.removeAllListeners();
    }
    
    if (this.provider && 'destroy' in this.provider) {
      await this.provider.destroy();
    }
    
    this.logger.log('Stopped listening for events');
  }

  getStatus() {
    return {
      isListening: this.isListening,
      currentProvider: this.currentProvider,
      reconnectAttempts: this.reconnectAttempts,
    };
  }
}

// Import the TypeChain factory
import { KttyWorldCompanions__factory } from '../types';
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ethers, Wallet, JsonRpcProvider, WebSocketProvider, TransactionResponse, Contract } from 'ethers';
import { KttyWorldCompanions } from '../../../types';
import { KttyWorldCompanions__factory } from '../../../types/factories';

@Injectable()
export class ContractService implements OnModuleInit {
  private readonly logger = new Logger(ContractService.name);
  private provider: JsonRpcProvider | WebSocketProvider;
  private wallet: Wallet;
  private contract: KttyWorldCompanions;

  private readonly contractAddress: string;
  private readonly ownerPrivateKey: string;
  private readonly rpcUrl: string;
  private readonly wsUrl: string;
  private readonly maxGasPrice: string;
  private readonly gasMultiplier: number;
  private readonly confirmationsRequired: number;

  constructor(private readonly configService: ConfigService) {
    this.contractAddress = this.configService.get<string>('blockchain.contractAddress');
    this.ownerPrivateKey = this.configService.get<string>('blockchain.ownerPrivateKey');
    this.rpcUrl = this.configService.get<string>('blockchain.rpcUrl');
    this.wsUrl = this.configService.get<string>('blockchain.wsUrl');
    this.maxGasPrice = this.configService.get<string>('batch.maxGasPrice');
    this.gasMultiplier = this.configService.get<number>('batch.gasMultiplier');
    this.confirmationsRequired = this.configService.get<number>('blockchain.confirmationsRequired');
  }

  async onModuleInit() {
    await this.initializeProvider();
    this.initializeWallet();
    this.initializeContract();
    await this.validateContract();
  }

  /**
   * Initialize the Ethereum provider (HTTP + WebSocket if available)
   */
  private async initializeProvider(): Promise<void> {
    try {
      // Try WebSocket first for event listening, fallback to HTTP
      if (this.wsUrl) {
        this.logger.log('Initializing WebSocket provider...');
        this.provider = new WebSocketProvider(this.wsUrl);
        
        // Test connection
        await this.provider.getBlockNumber();
        this.logger.log('WebSocket provider initialized successfully');
      } else {
        this.logger.log('Initializing HTTP provider...');
        this.provider = new JsonRpcProvider(this.rpcUrl);
        
        // Test connection
        await this.provider.getBlockNumber();
        this.logger.log('HTTP provider initialized successfully');
      }

      // Log network info
      const network = await this.provider.getNetwork();
      this.logger.log(`Connected to network: ${network.name} (Chain ID: ${network.chainId})`);

    } catch (error) {
      this.logger.error('Failed to initialize provider:', error);
      throw error;
    }
  }

  /**
   * Initialize the wallet for signing transactions
   */
  private initializeWallet(): void {
    try {
      this.wallet = new Wallet(this.ownerPrivateKey, this.provider);
      this.logger.log(`Wallet initialized: ${this.wallet.address}`);
    } catch (error) {
      this.logger.error('Failed to initialize wallet:', error);
      throw error;
    }
  }

  /**
   * Initialize the contract instance
   */
  private initializeContract(): void {
    try {
      this.contract = KttyWorldCompanions__factory.connect(this.contractAddress, this.wallet);
      this.logger.log(`Contract initialized: ${this.contractAddress}`);
    } catch (error) {
      this.logger.error('Failed to initialize contract:', error);
      throw error;
    }
  }

  /**
   * Validate contract and owner permissions
   */
  private async validateContract(): Promise<void> {
    try {
      // Check if contract exists
      const code = await this.provider.getCode(this.contractAddress);
      if (code === '0x') {
        throw new Error('Contract not found at the specified address');
      }

      // Check if wallet is the contract owner
      const contractOwner = await this.contract.owner();
      if (contractOwner.toLowerCase() !== this.wallet.address.toLowerCase()) {
        throw new Error(`Wallet ${this.wallet.address} is not the contract owner. Owner: ${contractOwner}`);
      }

      // Get contract info
      const name = await this.contract.name();
      const symbol = await this.contract.symbol();
      const totalSupply = await this.contract.totalSupply();

      this.logger.log(`Contract validation passed:`);
      this.logger.log(`  Name: ${name}`);
      this.logger.log(`  Symbol: ${symbol}`);
      this.logger.log(`  Total Supply: ${totalSupply}`);
      this.logger.log(`  Owner: ${contractOwner}`);

    } catch (error) {
      this.logger.error('Contract validation failed:', error);
      throw error;
    }
  }

  /**
   * Execute setBulkTokenCodes transaction
   */
  async setBulkTokenCodes(tokenIds: number[], codes: string[]): Promise<TransactionResponse> {
    if (tokenIds.length !== codes.length) {
      throw new Error('Token IDs and codes arrays must have the same length');
    }

    if (tokenIds.length === 0) {
      throw new Error('Cannot process empty batch');
    }

    try {
      this.logger.debug(`Setting bulk token codes for ${tokenIds.length} tokens`);

      // Estimate gas
      const gasEstimate = await this.contract.setBulkTokenCodes.estimateGas(tokenIds, codes);
      const gasLimit = BigInt(Math.ceil(Number(gasEstimate) * this.gasMultiplier));

      // Get current gas price
      const feeData = await this.provider.getFeeData();
      let gasPrice = feeData.gasPrice;
      
      // Cap gas price if configured
      if (gasPrice && this.maxGasPrice) {
        const maxPrice = BigInt(this.maxGasPrice);
        if (gasPrice > maxPrice) {
          this.logger.warn(`Gas price ${gasPrice} exceeds max ${maxPrice}, using max`);
          gasPrice = maxPrice;
        }
      }

      this.logger.debug(`Gas estimate: ${gasEstimate}, limit: ${gasLimit}, price: ${gasPrice}`);

      // Execute transaction
      const tx = await this.contract.setBulkTokenCodes(tokenIds, codes, {
        gasLimit,
        gasPrice,
      });

      this.logger.log(`Submitted setBulkTokenCodes transaction: ${tx.hash}`);
      this.logger.debug(`Token IDs: [${tokenIds.join(', ')}]`);
      
      return tx;

    } catch (error) {
      this.logger.error('Failed to execute setBulkTokenCodes:', error);
      throw error;
    }
  }

  /**
   * Get contract instance for event listening
   */
  getContract(): KttyWorldCompanions {
    return this.contract;
  }

  /**
   * Get provider instance
   */
  getProvider(): JsonRpcProvider | WebSocketProvider {
    return this.provider;
  }

  /**
   * Get wallet address
   */
  getWalletAddress(): string {
    return this.wallet.address;
  }

  /**
   * Check if a specific token ID exists
   */
  async tokenExists(tokenId: number): Promise<boolean> {
    try {
      return await this.contract.exists(tokenId);
    } catch (error) {
      this.logger.error(`Failed to check if token ${tokenId} exists:`, error);
      return false;
    }
  }

  /**
   * Get token code for a specific token ID
   */
  async getTokenCode(tokenId: number): Promise<string> {
    try {
      return await this.contract.getTokenCode(tokenId);
    } catch (error) {
      this.logger.error(`Failed to get token code for token ${tokenId}:`, error);
      throw error;
    }
  }

  /**
   * Check if token is revealed
   */
  async isTokenRevealed(tokenId: number): Promise<boolean> {
    try {
      return await this.contract.isTokenRevealed(tokenId);
    } catch (error) {
      this.logger.error(`Failed to check if token ${tokenId} is revealed:`, error);
      return false;
    }
  }

  /**
   * Get current block number
   */
  async getCurrentBlock(): Promise<number> {
    try {
      return await this.provider.getBlockNumber();
    } catch (error) {
      this.logger.error('Failed to get current block number:', error);
      throw error;
    }
  }

  /**
   * Health check for provider connection
   */
  async healthCheck(): Promise<boolean> {
    try {
      await this.provider.getBlockNumber();
      return true;
    } catch (error) {
      this.logger.error('Provider health check failed:', error);
      return false;
    }
  }
}
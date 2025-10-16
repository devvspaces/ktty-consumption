import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { isAddress } from 'ethers';

@Injectable()
export class ConfigValidationService implements OnModuleInit {
  private readonly logger = new Logger(ConfigValidationService.name);

  constructor(private readonly configService: ConfigService) {}

  async onModuleInit() {
    this.validateConfig();
  }

  private validateConfig() {
    const errors: string[] = [];

    // Validate required blockchain configuration
    const contractAddress = this.configService.get<string>('blockchain.contractAddress');
    if (!contractAddress) {
      errors.push('CONTRACT_ADDRESS is required');
    } else if (!isAddress(contractAddress)) {
      errors.push('CONTRACT_ADDRESS must be a valid Ethereum address');
    }

    const ownerPrivateKey = this.configService.get<string>('blockchain.ownerPrivateKey');
    if (!ownerPrivateKey) {
      errors.push('OWNER_PRIVATE_KEY is required');
    } else if (!ownerPrivateKey.match(/^0x[a-fA-F0-9]{64}$/)) {
      errors.push('OWNER_PRIVATE_KEY must be a valid 64-character hex string with 0x prefix');
    }

    const rpcUrl = this.configService.get<string>('blockchain.rpcUrl');
    if (!rpcUrl || (!rpcUrl.startsWith('http://') && !rpcUrl.startsWith('https://'))) {
      errors.push('RPC_URL must be a valid HTTP/HTTPS URL');
    }

    // Validate database configuration
    const dbUsername = this.configService.get<string>('database.username');
    const dbPassword = this.configService.get<string>('database.password');
    const dbName = this.configService.get<string>('database.name');

    if (!dbUsername) errors.push('DB_USERNAME is required');
    if (!dbPassword) errors.push('DB_PASSWORD is required');
    if (!dbName) errors.push('DB_NAME is required');

    // Validate batch processing configuration
    const maxBatchSize = this.configService.get<number>('batch.maxBatchSize');
    const batchTimeoutMs = this.configService.get<number>('batch.batchTimeoutMs');

    if (maxBatchSize <= 0 || maxBatchSize > 100) {
      errors.push('MAX_BATCH_SIZE must be between 1 and 100');
    }

    if (batchTimeoutMs < 1000 || batchTimeoutMs > 60000) {
      errors.push('BATCH_TIMEOUT_MS must be between 1000 and 60000');
    }

    // Validate deployment block
    const deploymentBlock = this.configService.get<number>('blockchain.deploymentBlock');
    if (deploymentBlock < 0) {
      errors.push('DEPLOYMENT_BLOCK must be a non-negative integer');
    }

    if (errors.length > 0) {
      this.logger.error('Configuration validation failed:');
      errors.forEach((error) => this.logger.error(`  - ${error}`));
      throw new Error(`Configuration validation failed: ${errors.join(', ')}`);
    }

    this.logger.log('Configuration validation passed');
    this.logImportantSettings();
  }

  private logImportantSettings() {
    const contractAddress = this.configService.get<string>('blockchain.contractAddress');
    const deploymentBlock = this.configService.get<number>('blockchain.deploymentBlock');
    const maxBatchSize = this.configService.get<number>('batch.maxBatchSize');
    const batchTimeoutMs = this.configService.get<number>('batch.batchTimeoutMs');
    const environment = this.configService.get<string>('app.environment');

    this.logger.log(`Environment: ${environment}`);
    this.logger.log(`Contract Address: ${contractAddress}`);
    this.logger.log(`Deployment Block: ${deploymentBlock}`);
    this.logger.log(`Batch Size: ${maxBatchSize} tokens`);
    this.logger.log(`Batch Timeout: ${batchTimeoutMs}ms`);
  }

  getConnectionString(): string {
    const { host, port, username, password, name } = this.configService.get('database');
    return `postgres://${username}:${password}@${host}:${port}/${name}`;
  }
}
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as fs from 'fs';
import * as path from 'path';

export interface TokenMapping {
  [tokenId: string]: string;
}

@Injectable()
export class TokenMapperService implements OnModuleInit {
  private readonly logger = new Logger(TokenMapperService.name);
  private tokenMapping: TokenMapping = {};
  private filePath: string;

  constructor(private readonly configService: ConfigService) {
    this.filePath = this.configService.get<string>('tokenMapping.filePath');
  }

  async onModuleInit() {
    await this.loadTokenMapping();
    
    const reloadOnChange = this.configService.get<boolean>('tokenMapping.reloadOnChange');
    if (reloadOnChange) {
      this.watchForFileChanges();
    }
  }

  private async loadTokenMapping(): Promise<void> {
    try {
      const absolutePath = path.resolve(this.filePath);
      
      if (!fs.existsSync(absolutePath)) {
        throw new Error(`Token mapping file not found: ${absolutePath}`);
      }

      const fileContent = fs.readFileSync(absolutePath, 'utf8');
      this.tokenMapping = JSON.parse(fileContent);

      const mappingCount = Object.keys(this.tokenMapping).length;
      this.logger.log(`Loaded token mapping with ${mappingCount} entries`);
      
      // Validate mapping format
      this.validateMapping();
    } catch (error) {
      this.logger.error('Failed to load token mapping:', error);
      throw new Error(`Failed to load token mapping: ${error.message}`);
    }
  }

  private validateMapping(): void {
    const errors: string[] = [];

    for (const [tokenId, randomCode] of Object.entries(this.tokenMapping)) {
      // Validate token ID is a positive integer
      const tokenIdNum = parseInt(tokenId, 10);
      if (isNaN(tokenIdNum) || tokenIdNum <= 0) {
        errors.push(`Invalid token ID: ${tokenId}`);
      }

      // Validate random code format (IPFS hash)
      if (!randomCode || typeof randomCode !== 'string') {
        errors.push(`Invalid random code for token ${tokenId}: ${randomCode}`);
      } else if (!randomCode.match(/^bafk[a-z0-9]{51}$/)) {
        this.logger.warn(`Token ${tokenId} has unexpected random code format: ${randomCode}`);
      }
    }

    if (errors.length > 0) {
      throw new Error(`Token mapping validation failed: ${errors.join(', ')}`);
    }

    this.logger.log('Token mapping validation passed');
  }

  private watchForFileChanges(): void {
    try {
      const absolutePath = path.resolve(this.filePath);
      fs.watchFile(absolutePath, { interval: 5000 }, async (curr, prev) => {
        if (curr.mtime > prev.mtime) {
          this.logger.log('Token mapping file changed, reloading...');
          try {
            await this.loadTokenMapping();
            this.logger.log('Token mapping reloaded successfully');
          } catch (error) {
            this.logger.error('Failed to reload token mapping:', error);
          }
        }
      });
      
      this.logger.log('Watching token mapping file for changes');
    } catch (error) {
      this.logger.warn('Failed to setup file watcher:', error);
    }
  }

  /**
   * Get random code for a specific token ID
   */
  getRandomCode(tokenId: number): string | null {
    const code = this.tokenMapping[tokenId.toString()];
    if (!code) {
      this.logger.warn(`No random code found for token ID: ${tokenId}`);
      return null;
    }
    return code;
  }

  /**
   * Get random codes for multiple token IDs
   */
  getRandomCodes(tokenIds: number[]): { tokenId: number; randomCode: string }[] {
    const results: { tokenId: number; randomCode: string }[] = [];
    const missingTokens: number[] = [];

    for (const tokenId of tokenIds) {
      const randomCode = this.getRandomCode(tokenId);
      if (randomCode) {
        results.push({ tokenId, randomCode });
      } else {
        missingTokens.push(tokenId);
      }
    }

    if (missingTokens.length > 0) {
      this.logger.error(`Missing random codes for token IDs: ${missingTokens.join(', ')}`);
      throw new Error(`Missing random codes for ${missingTokens.length} tokens`);
    }

    return results;
  }

  /**
   * Check if all token IDs have random codes
   */
  validateTokenIds(tokenIds: number[]): boolean {
    const missingTokens = tokenIds.filter(id => !this.tokenMapping[id.toString()]);
    if (missingTokens.length > 0) {
      this.logger.error(`Missing random codes for token IDs: ${missingTokens.join(', ')}`);
      return false;
    }
    return true;
  }

  /**
   * Get total number of token mappings
   */
  getMappingCount(): number {
    return Object.keys(this.tokenMapping).length;
  }

  /**
   * Get all mapped token IDs
   */
  getMappedTokenIds(): number[] {
    return Object.keys(this.tokenMapping).map(id => parseInt(id, 10));
  }

  /**
   * Check if a specific token ID has a mapping
   */
  hasMapping(tokenId: number): boolean {
    return this.tokenMapping.hasOwnProperty(tokenId.toString());
  }
}
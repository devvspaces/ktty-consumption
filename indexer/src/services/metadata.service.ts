import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { eq, and, sql, lt, desc } from 'drizzle-orm';
import axios, { AxiosResponse } from 'axios';
import { ethers } from 'ethers';
import { DatabaseService } from '../database/database.service';
import { nfts, metadataCache, failedOperations } from '../database/schema';
import { KttyWorldCompanions__factory, KttyWorldCompanions } from '../types';

export interface NftMetadata {
  name?: string;
  description?: string;
  image?: string;
  animation_url?: string;
  external_url?: string;
  attributes?: Array<{
    trait_type: string;
    value: string | number;
    display_type?: string;
  }>;
  [key: string]: any;
}

@Injectable()
export class MetadataService {
  private readonly logger = new Logger(MetadataService.name);
  private provider: ethers.JsonRpcProvider;
  private contract: KttyWorldCompanions;
  private readonly httpClient = axios.create({
    timeout: 0, // Set by individual requests
    headers: {
      'User-Agent': 'KTTY-Companions-Indexer/1.0',
    },
  });

  constructor(
    private configService: ConfigService,
    private databaseService: DatabaseService,
  ) {
    this.initializeContract();
  }

  private initializeContract() {
    const rpcUrl = this.configService.get<string>('blockchain.rpcUrl');
    const contractAddress = this.configService.get<string>('blockchain.contractAddress');

    this.provider = new ethers.JsonRpcProvider(rpcUrl);
    this.contract = KttyWorldCompanions__factory.connect(contractAddress, this.provider);
  }

  async fetchAndCacheMetadata(tokenId: number): Promise<void> {
    const db = this.databaseService.db;

    // Get current NFT record
    const nft = await db
      .select()
      .from(nfts)
      .where(eq(nfts.tokenId, tokenId))
      .limit(1);

    if (nft.length === 0) {
      this.logger.warn(`NFT with token ID ${tokenId} not found in database`);
      return;
    }

    // Fetch token URI from contract
    const tokenUri = await this.contract.tokenURI(tokenId);
    this.logger.debug(`Token URI for ${tokenId}: ${tokenUri}`);

    // Update NFT record with token URI
    await db
      .update(nfts)
      .set({ tokenUri })
      .where(eq(nfts.tokenId, tokenId));

    // Check cache first
    const cachedMetadata = await this.getCachedMetadata(tokenUri);
    if (cachedMetadata && !cachedMetadata.isStale) {
      await this.updateNftWithMetadata(tokenId, cachedMetadata.metadata);
      this.logger.debug(`Used cached metadata for token ${tokenId}`);
      return;
    }

    // Fetch metadata from URI
    const metadata = await this.fetchMetadataFromUri(tokenUri);

    // Cache the metadata
    await this.cacheMetadata(tokenUri, metadata);

    // Update NFT record with metadata
    await this.updateNftWithMetadata(tokenId, metadata);

    this.logger.log(`Successfully fetched and cached metadata for token ${tokenId}`);
  }

  private async fetchMetadataFromUri(tokenUri: string): Promise<NftMetadata> {
    const timeoutMs = this.configService.get<number>('indexer.metadataFetchTimeoutMs');

    try {
      // Handle IPFS URIs
      const httpUri = this.normalizeMetadataUri(tokenUri);

      const response: AxiosResponse<NftMetadata> = await this.httpClient.get(httpUri, {
        timeout: timeoutMs,
        validateStatus: (status) => status < 500, // Don't throw on 4xx errors
      });

      if (response.status >= 400) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      // Validate that response is JSON
      if (!response.data || typeof response.data !== 'object') {
        throw new Error('Invalid metadata format - not a JSON object');
      }

      return response.data;

    } catch (error) {
      if (error.code === 'ECONNABORTED') {
        throw new Error(`Timeout fetching metadata from ${tokenUri}`);
      }
      throw error;
    }
  }

  private normalizeMetadataUri(uri: string): string {
    // Convert IPFS URIs to HTTP gateway URLs
    if (uri.startsWith('ipfs://')) {
      const hash = uri.replace('ipfs://', '');
      return `https://ipfs.io/ipfs/${hash}`;
    }

    // Handle ipfs hash without protocol
    if (uri.match(/^Qm[1-9A-HJ-NP-Za-km-z]{44}$/)) {
      return `https://ipfs.io/ipfs/${uri}`;
    }

    return uri;
  }

  private async getCachedMetadata(tokenUri: string) {
    const db = this.databaseService.db;

    const cached = await db
      .select()
      .from(metadataCache)
      .where(eq(metadataCache.tokenUri, tokenUri))
      .limit(1);

    return cached.length > 0 ? cached[0] : null;
  }

  private async cacheMetadata(tokenUri: string, metadata: NftMetadata): Promise<void> {
    const db = this.databaseService.db;

    try {
      await db
        .insert(metadataCache)
        .values({
          tokenUri,
          metadata,
          httpStatus: 200,
        })
        .onConflictDoUpdate({
          target: metadataCache.tokenUri,
          set: {
            metadata,
            httpStatus: 200,
            fetchedAt: new Date(),
            refreshAttempts: 0,
            isStale: false,
          },
        });
    } catch (error) {
      this.logger.error(`Failed to cache metadata for URI ${tokenUri}:`, error);
    }
  }

  private async updateNftWithMetadata(tokenId: number, metadata: NftMetadata): Promise<void> {
    const db = this.databaseService.db;

    await db
      .update(nfts)
      .set({
        metadata,
        metadataFetchedAt: new Date(),
        metadataFetchAttempts: 0,
      })
      .where(eq(nfts.tokenId, tokenId));
  }

  async getMetadataStats() {
    const db = this.databaseService.db;

    try {
      const [nftsWithMetadata] = await db
        .select({ count: sql`count(*)` })
        .from(nfts)
        .where(sql`metadata IS NOT NULL`);

      const [totalNfts] = await db
        .select({ count: sql`count(*)` })
        .from(nfts);

      const [cacheSize] = await db
        .select({ count: sql`count(*)` })
        .from(metadataCache);

      const [staleCount] = await db
        .select({ count: sql`count(*)` })
        .from(metadataCache)
        .where(eq(metadataCache.isStale, true));

      return {
        nftsWithMetadata: Number(nftsWithMetadata.count),
        totalNfts: Number(totalNfts.count),
        cacheSize: Number(cacheSize.count),
        staleMetadata: Number(staleCount.count),
        metadataPercentage: Number(totalNfts.count) > 0
          ? Math.round((Number(nftsWithMetadata.count) / Number(totalNfts.count)) * 100)
          : 0,
      };
    } catch (error) {
      this.logger.error('Error getting metadata stats:', error);
      return {
        nftsWithMetadata: 0,
        totalNfts: 0,
        cacheSize: 0,
        staleMetadata: 0,
        metadataPercentage: 0,
      };
    }
  }
}
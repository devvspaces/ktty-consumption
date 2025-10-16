import { 
  Controller, 
  Get, 
  Param, 
  Query, 
  NotFoundException, 
  BadRequestException,
  Logger 
} from '@nestjs/common';
import { eq, and, or, sql, desc, asc } from 'drizzle-orm';
import { DatabaseService } from '../database/database.service';
import { nfts, transferEvents } from '../database/schema';
import { 
  GetNftsQueryDto, 
  GetTransfersQueryDto, 
  NftResponseDto, 
  TransferEventResponseDto,
  PaginatedResponse 
} from '../dto/nft.dto';

@Controller('nfts')
export class NftController {
  private readonly logger = new Logger(NftController.name);
  private readonly ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

  constructor(private databaseService: DatabaseService) {}

  @Get()
  async getNfts(@Query() query: GetNftsQueryDto): Promise<PaginatedResponse<NftResponseDto>> {
    const db = this.databaseService.db;
    
    try {
      // Build where conditions
      const whereConditions = [];
      
      if (query.owner) {
        if (!this.isValidAddress(query.owner)) {
          throw new BadRequestException('Invalid owner address format');
        }
        whereConditions.push(eq(nfts.currentOwner, query.owner.toLowerCase()));
      }

      // Add sorting
      const sortColumn = query.sortBy === 'createdAt' ? nfts.createdAt :
                        query.sortBy === 'updatedAt' ? nfts.updatedAt :
                        nfts.tokenId;

      // Build where clause
      const whereClause = whereConditions.length > 0 ? and(...whereConditions) : undefined;

      // Get total count
      const countResult = await db
        .select({ count: sql`count(*)` })
        .from(nfts)
        .where(whereClause);
      
      const total = Number(countResult[0].count);

      // Build and execute main query
      let mainQuery;
      
      if (whereClause) {
        mainQuery = db.select().from(nfts).where(whereClause);
      } else {
        mainQuery = db.select().from(nfts);
      }

      if (query.sortOrder === 'desc') {
        mainQuery = mainQuery.orderBy(desc(sortColumn));
      } else {
        mainQuery = mainQuery.orderBy(asc(sortColumn));
      }

      const results = await mainQuery
        .limit(query.limit)
        .offset(query.offset);

      // Transform to response format
      const data: NftResponseDto[] = results.map(nft => ({
        tokenId: nft.tokenId,
        currentOwner: nft.currentOwner,
        contractAddress: nft.contractAddress,
        tokenUri: nft.tokenUri || undefined,
        metadata: query.withMetadata ? nft.metadata : undefined,
        isRevealed: nft.isRevealed,
        createdAt: nft.createdAt.toISOString(),
        updatedAt: nft.updatedAt.toISOString(),
      }));

      return {
        data,
        pagination: {
          limit: query.limit,
          offset: query.offset,
          total,
          hasMore: query.offset + query.limit < total,
        },
      };

    } catch (error) {
      this.logger.error('Failed to fetch NFTs:', error);
      if (error instanceof BadRequestException) {
        throw error;
      }
      throw new BadRequestException('Failed to fetch NFTs');
    }
  }

  @Get(':tokenId')
  async getNft(@Param('tokenId') tokenId: string): Promise<NftResponseDto> {
    const db = this.databaseService.db;
    
    try {
      const tokenIdNum = parseInt(tokenId);
      if (isNaN(tokenIdNum) || tokenIdNum < 0) {
        throw new BadRequestException('Invalid token ID');
      }

      const result = await db
        .select()
        .from(nfts)
        .where(eq(nfts.tokenId, tokenIdNum))
        .limit(1);

      if (result.length === 0) {
        throw new NotFoundException(`NFT with token ID ${tokenId} not found`);
      }

      const nft = result[0];
      
      return {
        tokenId: nft.tokenId,
        currentOwner: nft.currentOwner,
        contractAddress: nft.contractAddress,
        tokenUri: nft.tokenUri || undefined,
        metadata: nft.metadata,
        isRevealed: nft.isRevealed,
        createdAt: nft.createdAt.toISOString(),
        updatedAt: nft.updatedAt.toISOString(),
      };

    } catch (error) {
      this.logger.error(`Failed to fetch NFT ${tokenId}:`, error);
      if (error instanceof NotFoundException || error instanceof BadRequestException) {
        throw error;
      }
      throw new BadRequestException('Failed to fetch NFT');
    }
  }

  @Get('/owners/:address')
  async getOwnerNfts(
    @Param('address') address: string,
    @Query() query: GetNftsQueryDto
  ): Promise<PaginatedResponse<NftResponseDto>> {
    if (!this.isValidAddress(address)) {
      throw new BadRequestException('Invalid address format');
    }

    // Override the query owner parameter
    query.owner = address;
    return this.getNfts(query);
  }

  private isValidAddress(address: string): boolean {
    return /^0x[a-fA-F0-9]{40}$/.test(address);
  }
}
import { IsOptional, IsString, IsNumber, Min, Max } from 'class-validator';
import { Transform, Type } from 'class-transformer';

export class GetNftsQueryDto {
  @IsOptional()
  @IsString()
  owner?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  @Max(100)
  limit?: number = 20;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  offset?: number = 0;

  @IsOptional()
  @IsString()
  sortBy?: 'tokenId' | 'createdAt' | 'updatedAt' = 'tokenId';

  @IsOptional()
  @IsString()
  sortOrder?: 'asc' | 'desc' = 'asc';

  @IsOptional()
  @Transform(({ value }) => value === 'true')
  withMetadata?: boolean = true;
}

export class GetTransfersQueryDto {
  @IsOptional()
  @IsString()
  tokenId?: string;

  @IsOptional()
  @IsString()
  fromAddress?: string;

  @IsOptional()
  @IsString()
  toAddress?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  @Max(100)
  limit?: number = 20;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  offset?: number = 0;

  @IsOptional()
  @IsString()
  sortOrder?: 'asc' | 'desc' = 'desc';
}

export interface NftResponseDto {
  tokenId: number;
  currentOwner: string;
  contractAddress: string;
  tokenUri?: string;
  metadata?: any;
  isRevealed: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface TransferEventResponseDto {
  id: number;
  transactionHash: string;
  blockNumber: number;
  blockHash: string;
  logIndex: number;
  tokenId: number;
  fromAddress: string;
  toAddress: string;
  contractAddress: string;
  gasUsed?: number;
  gasPrice?: number;
  timestamp: string;
  transferType: 'MINT' | 'TRANSFER' | 'BURN';
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    limit: number;
    offset: number;
    total: number;
    hasMore: boolean;
  };
}
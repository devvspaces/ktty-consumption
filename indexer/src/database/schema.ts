import {
  pgTable,
  serial,
  varchar,
  integer,
  bigint,
  timestamp,
  boolean,
  text,
  jsonb,
  index,
  unique,
} from 'drizzle-orm/pg-core';

// NFTs table - stores current state of each NFT
export const nfts = pgTable('nfts', {
  id: serial('id').primaryKey(),
  tokenId: integer('token_id').notNull().unique(),
  currentOwner: varchar('current_owner', { length: 42 }).notNull(), // Ethereum address
  contractAddress: varchar('contract_address', { length: 42 }).notNull(),
  tokenUri: text('token_uri'),
  metadata: jsonb('metadata'), // Cached metadata JSON
  metadataFetchedAt: timestamp('metadata_fetched_at'),
  metadataFetchAttempts: integer('metadata_fetch_attempts').notNull().default(0),
  isRevealed: boolean('is_revealed').notNull().default(false),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => ([
  index('nfts_current_owner_idx').on(table.currentOwner),
  index('nfts_contract_address_idx').on(table.contractAddress),
  index('nfts_token_id_contract_idx').on(table.tokenId, table.contractAddress),
]));

// Transfer events table - complete history of all transfers
export const transferEvents = pgTable('transfer_events', {
  id: serial('id').primaryKey(),
  transactionHash: varchar('transaction_hash', { length: 66 }).notNull(),
  blockNumber: bigint('block_number', { mode: 'number' }).notNull(),
  blockHash: varchar('block_hash', { length: 66 }).notNull(),
  logIndex: integer('log_index').notNull(),
  tokenId: integer('token_id').notNull(),
  fromAddress: varchar('from_address', { length: 42 }).notNull(), // 0x0000... for mints
  toAddress: varchar('to_address', { length: 42 }).notNull(),
  contractAddress: varchar('contract_address', { length: 42 }).notNull(),
  gasUsed: bigint('gas_used', { mode: 'number' }),
  gasPrice: bigint('gas_price', { mode: 'number' }),
  timestamp: timestamp('timestamp').notNull(),
  processedAt: timestamp('processed_at').defaultNow().notNull(),
}, (table) => ([
  unique('transfer_events_tx_hash_log_idx').on(table.transactionHash, table.logIndex),
  index('transfer_events_token_id_idx').on(table.tokenId),
  index('transfer_events_from_address_idx').on(table.fromAddress),
  index('transfer_events_to_address_idx').on(table.toAddress),
  index('transfer_events_block_number_idx').on(table.blockNumber),
  index('transfer_events_timestamp_idx').on(table.timestamp),
]));

// Sync state table - tracks indexing progress
export const syncState = pgTable('sync_state', {
  id: serial('id').primaryKey(),
  contractAddress: varchar('contract_address', { length: 42 }).notNull().unique(),
  lastProcessedBlock: bigint('last_processed_block', { mode: 'number' }).notNull(),
  lastProcessedTimestamp: timestamp('last_processed_timestamp').notNull(),
  isHealthy: boolean('is_healthy').notNull().default(true),
  errorMessage: text('error_message'),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

// Metadata cache table - stores metadata with refresh tracking
export const metadataCache = pgTable('metadata_cache', {
  id: serial('id').primaryKey(),
  tokenUri: text('token_uri').notNull().unique(),
  metadata: jsonb('metadata').notNull(),
  httpStatus: integer('http_status').notNull(),
  fetchedAt: timestamp('fetched_at').defaultNow().notNull(),
  refreshAttempts: integer('refresh_attempts').notNull().default(0),
  lastRefreshAt: timestamp('last_refresh_at'),
  isStale: boolean('is_stale').notNull().default(false),
}, (table) => ([
  index('metadata_cache_fetched_at_idx').on(table.fetchedAt),
  index('metadata_cache_stale_idx').on(table.isStale),
]));

// Failed operations table - for retry logic and monitoring
export const failedOperations = pgTable('failed_operations', {
  id: serial('id').primaryKey(),
  operationType: varchar('operation_type', { length: 50 }).notNull(), // 'transfer_event', 'metadata_fetch', etc.
  entityId: varchar('entity_id', { length: 200 }).notNull(), // tokenId, transactionHash, etc.
  tokenId: integer('token_id'), // For transfer events, to check for newer transfers
  blockNumber: bigint('block_number', { mode: 'number' }), // Block number for chronological ordering
  timestamp: timestamp('timestamp'), // Event timestamp for chronological ordering
  errorMessage: text('error_message').notNull(),
  errorStack: text('error_stack'),
  data: jsonb('data'), // Original data that failed to process
  attempts: integer('attempts').notNull().default(1),
  lastAttemptAt: timestamp('last_attempt_at').defaultNow().notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  resolved: boolean('resolved').notNull().default(false),
  resolvedAt: timestamp('resolved_at'),
  superseded: boolean('superseded').notNull().default(false), // True if newer events make this irrelevant
  lastKnownOwner: varchar('last_known_owner', { length: 42 }), // Expected owner before retry
}, (table) => ([
  index('failed_operations_operation_type_idx').on(table.operationType),
  index('failed_operations_resolved_idx').on(table.resolved),
  index('failed_operations_last_attempt_idx').on(table.lastAttemptAt),
  index('failed_operations_token_id_idx').on(table.tokenId),
  index('failed_operations_block_number_idx').on(table.blockNumber),
  index('failed_operations_superseded_idx').on(table.superseded),
]));

// Metadata events table - tracks MetadataUpdated events from the contract
export const metadataEvents = pgTable('metadata_events', {
  id: serial('id').primaryKey(),
  transactionHash: varchar('transaction_hash', { length: 66 }).notNull(),
  blockNumber: bigint('block_number', { mode: 'number' }).notNull(),
  blockHash: varchar('block_hash', { length: 66 }).notNull(),
  logIndex: integer('log_index').notNull(),
  tokenId: integer('token_id').notNull(), // Note: type(uint256).max = -1 in integer, handled in service logic
  contractAddress: varchar('contract_address', { length: 42 }).notNull(),
  timestamp: timestamp('timestamp').notNull(),
  processedAt: timestamp('processed_at').defaultNow().notNull(),
}, (table) => ([
  unique('metadata_events_tx_hash_log_idx').on(table.transactionHash, table.logIndex),
  index('metadata_events_token_id_idx').on(table.tokenId),
  index('metadata_events_block_number_idx').on(table.blockNumber),
  index('metadata_events_timestamp_idx').on(table.timestamp),
]));

// Type exports for use in services
export type Nft = typeof nfts.$inferSelect;
export type NewNft = typeof nfts.$inferInsert;

export type TransferEvent = typeof transferEvents.$inferSelect;
export type NewTransferEvent = typeof transferEvents.$inferInsert;

export type SyncState = typeof syncState.$inferSelect;
export type NewSyncState = typeof syncState.$inferInsert;

export type MetadataCache = typeof metadataCache.$inferSelect;
export type NewMetadataCache = typeof metadataCache.$inferInsert;

export type FailedOperation = typeof failedOperations.$inferSelect;
export type NewFailedOperation = typeof failedOperations.$inferInsert;

export type MetadataEvent = typeof metadataEvents.$inferSelect;
export type NewMetadataEvent = typeof metadataEvents.$inferInsert;
import {
  pgTable,
  serial,
  varchar,
  integer,
  bigint,
  timestamp,
  boolean,
  text,
} from 'drizzle-orm/pg-core';

export const processedEvents = pgTable('processed_events', {
  id: serial('id').primaryKey(),
  tokenId: integer('token_id').notNull().unique(),
  blockNumber: bigint('block_number', { mode: 'number' }).notNull(),
  transactionHash: varchar('transaction_hash', { length: 66 }).notNull(),
  logIndex: integer('log_index').notNull(),
  processedAt: timestamp('processed_at').defaultNow().notNull(),
  status: varchar('status', { length: 20 }).notNull().default('completed'),
  errorMessage: text('error_message'),
  retryCount: integer('retry_count').notNull().default(0),
});

export const batchTransactions = pgTable('batch_transactions', {
  id: serial('id').primaryKey(),
  transactionHash: varchar('transaction_hash', { length: 66 }),
  tokenIds: integer('token_ids').array().notNull(),
  tokenCodes: varchar('token_codes', { length: 100 }).array().notNull(),
  gasUsed: bigint('gas_used', { mode: 'number' }),
  gasPrice: bigint('gas_price', { mode: 'number' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  completedAt: timestamp('completed_at'),
  status: varchar('status', { length: 20 }).notNull().default('pending'),
  errorMessage: text('error_message'),
  retryCount: integer('retry_count').notNull().default(0),
  nonce: integer('nonce'),
});

export const systemState = pgTable('system_state', {
  key: varchar('key', { length: 50 }).primaryKey(),
  value: varchar('value', { length: 500 }).notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export const eventProcessingQueue = pgTable('event_processing_queue', {
  id: serial('id').primaryKey(),
  tokenId: integer('token_id').notNull(),
  blockNumber: bigint('block_number', { mode: 'number' }).notNull(),
  transactionHash: varchar('transaction_hash', { length: 66 }).notNull(),
  logIndex: integer('log_index').notNull(),
  randomCode: varchar('random_code', { length: 100 }).notNull(),
  queuedAt: timestamp('queued_at').defaultNow().notNull(),
  processed: boolean('processed').notNull().default(false),
  batchTransactionId: integer('batch_transaction_id').references(
    () => batchTransactions.id,
  ),
});

export type ProcessedEvent = typeof processedEvents.$inferSelect;
export type NewProcessedEvent = typeof processedEvents.$inferInsert;

export type BatchTransaction = typeof batchTransactions.$inferSelect;
export type NewBatchTransaction = typeof batchTransactions.$inferInsert;

export type SystemState = typeof systemState.$inferSelect;
export type NewSystemState = typeof systemState.$inferInsert;

export type EventProcessingQueue = typeof eventProcessingQueue.$inferSelect;
export type NewEventProcessingQueue = typeof eventProcessingQueue.$inferInsert;
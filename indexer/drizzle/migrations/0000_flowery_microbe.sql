CREATE TABLE "failed_operations" (
	"id" serial PRIMARY KEY NOT NULL,
	"operation_type" varchar(50) NOT NULL,
	"entity_id" varchar(200) NOT NULL,
	"token_id" integer,
	"block_number" bigint,
	"timestamp" timestamp,
	"error_message" text NOT NULL,
	"error_stack" text,
	"data" jsonb,
	"attempts" integer DEFAULT 1 NOT NULL,
	"last_attempt_at" timestamp DEFAULT now() NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"resolved" boolean DEFAULT false NOT NULL,
	"resolved_at" timestamp,
	"superseded" boolean DEFAULT false NOT NULL,
	"last_known_owner" varchar(42)
);
--> statement-breakpoint
CREATE TABLE "metadata_cache" (
	"id" serial PRIMARY KEY NOT NULL,
	"token_uri" text NOT NULL,
	"metadata" jsonb NOT NULL,
	"http_status" integer NOT NULL,
	"fetched_at" timestamp DEFAULT now() NOT NULL,
	"refresh_attempts" integer DEFAULT 0 NOT NULL,
	"last_refresh_at" timestamp,
	"is_stale" boolean DEFAULT false NOT NULL,
	CONSTRAINT "metadata_cache_token_uri_unique" UNIQUE("token_uri")
);
--> statement-breakpoint
CREATE TABLE "metadata_events" (
	"id" serial PRIMARY KEY NOT NULL,
	"transaction_hash" varchar(66) NOT NULL,
	"block_number" bigint NOT NULL,
	"block_hash" varchar(66) NOT NULL,
	"log_index" integer NOT NULL,
	"token_id" integer NOT NULL,
	"contract_address" varchar(42) NOT NULL,
	"timestamp" timestamp NOT NULL,
	"processed_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "metadata_events_tx_hash_log_idx" UNIQUE("transaction_hash","log_index")
);
--> statement-breakpoint
CREATE TABLE "nfts" (
	"id" serial PRIMARY KEY NOT NULL,
	"token_id" integer NOT NULL,
	"current_owner" varchar(42) NOT NULL,
	"contract_address" varchar(42) NOT NULL,
	"token_uri" text,
	"metadata" jsonb,
	"metadata_fetched_at" timestamp,
	"metadata_fetch_attempts" integer DEFAULT 0 NOT NULL,
	"is_revealed" boolean DEFAULT false NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "nfts_token_id_unique" UNIQUE("token_id")
);
--> statement-breakpoint
CREATE TABLE "sync_state" (
	"id" serial PRIMARY KEY NOT NULL,
	"contract_address" varchar(42) NOT NULL,
	"last_processed_block" bigint NOT NULL,
	"last_processed_timestamp" timestamp NOT NULL,
	"is_healthy" boolean DEFAULT true NOT NULL,
	"error_message" text,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "sync_state_contract_address_unique" UNIQUE("contract_address")
);
--> statement-breakpoint
CREATE TABLE "transfer_events" (
	"id" serial PRIMARY KEY NOT NULL,
	"transaction_hash" varchar(66) NOT NULL,
	"block_number" bigint NOT NULL,
	"block_hash" varchar(66) NOT NULL,
	"log_index" integer NOT NULL,
	"token_id" integer NOT NULL,
	"from_address" varchar(42) NOT NULL,
	"to_address" varchar(42) NOT NULL,
	"contract_address" varchar(42) NOT NULL,
	"gas_used" bigint,
	"gas_price" bigint,
	"timestamp" timestamp NOT NULL,
	"processed_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "transfer_events_tx_hash_log_idx" UNIQUE("transaction_hash","log_index")
);
--> statement-breakpoint
CREATE INDEX "failed_operations_operation_type_idx" ON "failed_operations" USING btree ("operation_type");--> statement-breakpoint
CREATE INDEX "failed_operations_resolved_idx" ON "failed_operations" USING btree ("resolved");--> statement-breakpoint
CREATE INDEX "failed_operations_last_attempt_idx" ON "failed_operations" USING btree ("last_attempt_at");--> statement-breakpoint
CREATE INDEX "failed_operations_token_id_idx" ON "failed_operations" USING btree ("token_id");--> statement-breakpoint
CREATE INDEX "failed_operations_block_number_idx" ON "failed_operations" USING btree ("block_number");--> statement-breakpoint
CREATE INDEX "failed_operations_superseded_idx" ON "failed_operations" USING btree ("superseded");--> statement-breakpoint
CREATE INDEX "metadata_cache_fetched_at_idx" ON "metadata_cache" USING btree ("fetched_at");--> statement-breakpoint
CREATE INDEX "metadata_cache_stale_idx" ON "metadata_cache" USING btree ("is_stale");--> statement-breakpoint
CREATE INDEX "metadata_events_token_id_idx" ON "metadata_events" USING btree ("token_id");--> statement-breakpoint
CREATE INDEX "metadata_events_block_number_idx" ON "metadata_events" USING btree ("block_number");--> statement-breakpoint
CREATE INDEX "metadata_events_timestamp_idx" ON "metadata_events" USING btree ("timestamp");--> statement-breakpoint
CREATE INDEX "nfts_current_owner_idx" ON "nfts" USING btree ("current_owner");--> statement-breakpoint
CREATE INDEX "nfts_contract_address_idx" ON "nfts" USING btree ("contract_address");--> statement-breakpoint
CREATE INDEX "nfts_token_id_contract_idx" ON "nfts" USING btree ("token_id","contract_address");--> statement-breakpoint
CREATE INDEX "transfer_events_token_id_idx" ON "transfer_events" USING btree ("token_id");--> statement-breakpoint
CREATE INDEX "transfer_events_from_address_idx" ON "transfer_events" USING btree ("from_address");--> statement-breakpoint
CREATE INDEX "transfer_events_to_address_idx" ON "transfer_events" USING btree ("to_address");--> statement-breakpoint
CREATE INDEX "transfer_events_block_number_idx" ON "transfer_events" USING btree ("block_number");--> statement-breakpoint
CREATE INDEX "transfer_events_timestamp_idx" ON "transfer_events" USING btree ("timestamp");
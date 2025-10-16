-- Initialize database with proper extensions and settings
-- This file is run when the postgres container starts for the first time

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create database user if not exists (already created by POSTGRES_USER env var)
-- The database and user are already created by the postgres image

-- Set proper timezone
SET timezone = 'UTC';

-- Create any additional settings or indexes here if needed
-- The actual schema will be created by Drizzle migrations

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON DATABASE ktty_indexer TO ktty_indexer;
GRANT ALL ON SCHEMA public TO ktty_indexer;
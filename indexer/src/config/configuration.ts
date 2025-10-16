export default () => ({
  app: {
    name: process.env.APP_NAME || 'ktty-companions-indexer',
    port: parseInt(process.env.PORT || '3001', 10),
    environment: process.env.NODE_ENV || 'development',
    gracefulShutdownTimeoutMs: parseInt(process.env.GRACEFUL_SHUTDOWN_TIMEOUT_MS || '30000', 10),
  },
  database: {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    username: process.env.DB_USERNAME || 'ktty_indexer',
    password: process.env.DB_PASSWORD || 'secure_password',
    name: process.env.DB_NAME || 'ktty_indexer',
  },
  blockchain: {
    rpcUrl: process.env.RPC_URL || 'https://mainnet.infura.io/v3/YOUR_INFURA_KEY',
    rpcUrlFallback: process.env.RPC_URL_FALLBACK,
    contractAddress: process.env.CONTRACT_ADDRESS || '0x0000000000000000000000000000000000000000',
    deploymentBlock: parseInt(process.env.DEPLOYMENT_BLOCK || '0', 10),
    network: process.env.NETWORK || 'mainnet',
  },
  indexer: {
    maxBlocksPerBatch: parseInt(process.env.MAX_BLOCKS_PER_BATCH || '10000', 10),
    metadataFetchTimeoutMs: parseInt(process.env.METADATA_FETCH_TIMEOUT_MS || '10000', 10),
    metadataRetryAttempts: parseInt(process.env.METADATA_RETRY_ATTEMPTS || '5', 10),
  },
  redis: {
    host: process.env.REDIS_HOST || 'localhost',
    port: parseInt(process.env.REDIS_PORT || '6379', 10),
    password: process.env.REDIS_PASSWORD,
    db: parseInt(process.env.REDIS_DB || '0', 10),
  },
});
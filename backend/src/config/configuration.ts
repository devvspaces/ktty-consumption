export default () => ({
  // Database Configuration
  database: {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT, 10) || 5432,
    username: process.env.DB_USERNAME || 'ktty_user',
    password: process.env.DB_PASSWORD || 'secure_password',
    name: process.env.DB_NAME || 'ktty_companions',
    maxConnections: parseInt(process.env.DB_MAX_CONNECTIONS, 10) || 20,
  },

  // Blockchain Configuration
  blockchain: {
    rpcUrl: process.env.RPC_URL || 'http://localhost:8545',
    wsUrl: process.env.WS_URL,
    contractAddress: process.env.CONTRACT_ADDRESS,
    ownerPrivateKey: process.env.OWNER_PRIVATE_KEY,
    deploymentBlock: parseInt(process.env.DEPLOYMENT_BLOCK, 10) || 0,
    confirmationsRequired: parseInt(process.env.CONFIRMATIONS_REQUIRED, 10) || 1,
    retryAttempts: parseInt(process.env.RPC_RETRY_ATTEMPTS, 10) || 3,
    retryDelayMs: parseInt(process.env.RPC_RETRY_DELAY_MS, 10) || 1000,
    timeoutMs: parseInt(process.env.RPC_TIMEOUT_MS, 10) || 30000,
  },

  // Batch Processing Configuration
  batch: {
    maxBatchSize: parseInt(process.env.MAX_BATCH_SIZE, 10) || 10,
    batchTimeoutMs: parseInt(process.env.BATCH_TIMEOUT_MS, 10) || 2000,
    processingIntervalMs: parseInt(process.env.PROCESSING_INTERVAL_MS, 10) || 100,
    maxRetries: parseInt(process.env.MAX_RETRIES, 10) || 3,
    retryDelayMs: parseInt(process.env.RETRY_DELAY_MS, 10) || 5000,
    exponentialBackoff: process.env.EXPONENTIAL_BACKOFF !== 'false',
    maxGasPrice: process.env.MAX_GAS_PRICE || '100000000000', // 100 gwei
    gasMultiplier: parseFloat(process.env.GAS_MULTIPLIER) || 1.2,
  },

  // Event Processing Configuration
  events: {
    blockRangeLimit: parseInt(process.env.BLOCK_RANGE_LIMIT, 10) || 1000,
    catchupBatchSize: parseInt(process.env.CATCHUP_BATCH_SIZE, 10) || 100,
    pollingIntervalMs: parseInt(process.env.POLLING_INTERVAL_MS, 10) || 5000,
    reconnectDelayMs: parseInt(process.env.RECONNECT_DELAY_MS, 10) || 1000,
    maxReconnectAttempts: parseInt(process.env.MAX_RECONNECT_ATTEMPTS, 10) || 10,
  },

  // Application Configuration
  app: {
    port: parseInt(process.env.PORT, 10) || 3000,
    environment: process.env.NODE_ENV || 'development',
    logLevel: process.env.LOG_LEVEL || 'info',
    gracefulShutdownTimeoutMs: parseInt(process.env.GRACEFUL_SHUTDOWN_TIMEOUT_MS, 10) || 10000,
  },

  // Token Mapping Configuration
  tokenMapping: {
    filePath: process.env.TOKEN_MAPPING_FILE_PATH || './src/data/tokenMapping.json',
    reloadOnChange: process.env.RELOAD_MAPPING_ON_CHANGE !== 'false',
  },

  // Monitoring Configuration
  monitoring: {
    healthCheckIntervalMs: parseInt(process.env.HEALTH_CHECK_INTERVAL_MS, 10) || 30000,
    metricsEnabled: process.env.METRICS_ENABLED !== 'false',
    alertThresholds: {
      consecutiveFailures: parseInt(process.env.ALERT_CONSECUTIVE_FAILURES, 10) || 5,
      processingDelayMs: parseInt(process.env.ALERT_PROCESSING_DELAY_MS, 10) || 60000,
    },
  },
});
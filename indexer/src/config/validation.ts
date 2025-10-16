import * as Joi from 'joi';

export const validationSchema = Joi.object({
  NODE_ENV: Joi.string().valid('development', 'production', 'test').default('development'),
  PORT: Joi.number().port().default(3001),
  
  // Database
  DB_HOST: Joi.string().required(),
  DB_PORT: Joi.number().port().default(5432),
  DB_USERNAME: Joi.string().required(),
  DB_PASSWORD: Joi.string().required(),
  DB_NAME: Joi.string().required(),
  
  // Blockchain
  RPC_URL: Joi.string().uri().required(),
  RPC_URL_FALLBACK: Joi.string().uri().optional(),
  CONTRACT_ADDRESS: Joi.string().pattern(/^0x[a-fA-F0-9]{40}$/).required(),
  DEPLOYMENT_BLOCK: Joi.number().integer().min(0).required(),
  NETWORK: Joi.string().valid('mainnet', 'goerli', 'sepolia', 'polygon', 'mumbai', 'arbitrum').default('mainnet'),
  
  // Indexer configuration
  MAX_BLOCKS_PER_BATCH: Joi.number().integer().min(1).max(10000).default(1000),
  METADATA_FETCH_TIMEOUT_MS: Joi.number().integer().min(1000).max(60000).default(10000),
  METADATA_RETRY_ATTEMPTS: Joi.number().integer().min(1).max(10).default(3),
});
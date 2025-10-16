# KTTY Companions Backend

A robust NestJS backend service that listens to `TokenRevealed` events from the KTTY World Companions NFT contract and automatically sets random token codes using intelligent batch processing.

## Features

- 🔊 **Event Listening**: Real-time WebSocket + HTTP fallback event monitoring
- ⚡ **Smart Batching**: Time + length based batching (2s timeout OR 10 tokens)
- 🔄 **Auto Recovery**: Automatic catchup for missed events after restarts
- 🛡️ **Resilient**: Exponential backoff, retry logic, graceful shutdowns
- 🏥 **Health Monitoring**: Comprehensive health checks and status endpoints
- 🐳 **Production Ready**: Docker support with PostgreSQL and Drizzle ORM

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Event Listener │───▶│  Batch Processor │───▶│ Contract Service│
│                 │    │                  │    │                 │
│ - WebSocket     │    │ - Time batching  │    │ - setBulkCodes  │
│ - HTTP fallback │    │ - Size batching  │    │ - Gas optimization│
│ - Auto recovery │    │ - Queue mgmt     │    │ - Retry logic   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│    Database     │    │  Token Mapper    │    │ Health Monitors │
│                 │    │                  │    │                 │
│ - Event tracking│    │ - JSON mapping   │    │ - /health       │
│ - Block state   │    │ - File watching  │    │ - /status       │
│ - Audit trail   │    │ - Validation     │    │ - /metrics      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Quick Start

### 1. Prerequisites

- Node.js 18+
- PostgreSQL 15+
- Ethereum RPC endpoint (Infura, Alchemy, etc.)

### 2. Installation

```bash
# Clone and install dependencies
npm install

# Generate TypeChain types
npm run typechain

# Set up environment
cp .env.example .env
# Edit .env with your configuration
```

### 3. Database Setup

```bash
# Generate migration files
npm run db:generate

# Run migrations
npm run db:migrate

# Optional: View database in Drizzle Studio
npm run db:studio
```

### 4. Configuration

Edit `.env` with your settings:

```env
# Required: Blockchain Configuration
RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY
CONTRACT_ADDRESS=0x1234567890123456789012345678901234567890
OWNER_PRIVATE_KEY=0x1234567890123456789012345678901234567890123456789012345678901234
DEPLOYMENT_BLOCK=18000000

# Required: Database Configuration
DB_HOST=localhost
DB_USERNAME=ktty_user
DB_PASSWORD=secure_password
DB_NAME=ktty_companions

# Optional: Batch Processing Tuning
MAX_BATCH_SIZE=10        # Max tokens per batch
BATCH_TIMEOUT_MS=2000    # Max wait time (2 seconds)
```

### 5. Token Mapping

Update `src/data/tokenMapping.json` with your token ID → random code mappings:

```json
{
  "1": "bafkreibs72f53tpj5u7ne6ztz7ckwolzdexyi7wghqo4hnx4mlqdy47wde",
  "2": "bafkreiabcdef1234567890abcdef1234567890abcdef1234567890abcdef",
  "3": "bafkreighijkl9876543210ghijkl9876543210ghijkl9876543210ghijkl"
}
```

### 6. Run

```bash
# Development mode
npm run start:dev

# Production build
npm run build && npm start
```

## Docker Deployment

### Using Docker Compose (Recommended)

```bash
# Start PostgreSQL + Backend
docker-compose up -d

# View logs
docker-compose logs -f backend

# Stop services
docker-compose down
```

### Manual Docker Build

```bash
# Build image
docker build -t ktty-companions-backend .

# Run container
docker run -d \
  --name ktty-backend \
  -p 3000:3000 \
  -e RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY \
  -e CONTRACT_ADDRESS=0x... \
  -e OWNER_PRIVATE_KEY=0x... \
  ktty-companions-backend
```

## Batch Processing Logic

The service uses intelligent batching to optimize UX and gas costs:

```typescript
// Fast single reveals: Process immediately if 2 seconds elapsed
setTimeout(() => processBatch(), 2000)

// Efficient bulk reveals: Process immediately when 10 tokens queued  
if (pendingTokens.length >= 10) processBatch()

// High-intensity scenarios: Process multiple batches of 10
while (pendingTokens.length > 0) {
  processBatch(pendingTokens.slice(0, 10))
}
```

## API Endpoints

### Health & Status
- `GET /health` - Overall health check
- `GET /health/ready` - Readiness probe (K8s)
- `GET /health/live` - Liveness probe (K8s)
- `GET /blockchain/status` - Detailed service status
- `GET /blockchain/metrics` - Processing metrics

### Admin Operations
- `POST /blockchain/catchup` - Force manual event catchup
- `POST /blockchain/process-batch` - Force process current batch

## Monitoring

### Health Check Response
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "services": {
    "contract": "healthy",
    "database": "healthy", 
    "eventListener": "healthy"
  }
}
```

### Status Response
```json
{
  "timestamp": "2024-01-15T10:30:00.000Z",
  "blockchain": {
    "currentBlock": 18500000,
    "lastProcessedBlock": 18499995,
    "blocksBehind": 5
  },
  "batchProcessor": {
    "pendingTokens": 3,
    "processingActive": false,
    "hasTimer": true
  },
  "eventListener": {
    "isListening": true,
    "reconnectAttempts": 0,
    "catchupInProgress": false
  }
}
```

## Recovery & Resilience

### Startup Recovery
1. Queries last processed block from database
2. Scans for missed `TokenRevealed` events since last block
3. Processes backlog before starting real-time listening
4. Validates existing token codes against mapping

### Error Handling
- **RPC Failures**: Exponential backoff with WebSocket → HTTP fallback
- **Transaction Failures**: Retry with dynamic gas price adjustment  
- **Database Issues**: Connection pooling with automatic reconnection
- **Event Processing**: Idempotent processing prevents duplicates

### Graceful Shutdown
1. Stops accepting new events
2. Completes current batch processing
3. Processes remaining queued tokens
4. Updates database state
5. Closes connections cleanly

## Development

```bash
# Watch mode
npm run start:dev

# Lint code
npm run lint

# Run tests
npm run test

# Generate new migration
npm run db:generate

# Reset database
docker-compose down -v
docker-compose up -d postgres
npm run db:migrate
```

## Production Considerations

### Scaling
- **Horizontal**: Deploy multiple instances with database coordination
- **Database**: Use PostgreSQL read replicas for metrics/status endpoints
- **Caching**: Add Redis for frequently accessed data

### Security
- Store private keys in secure key management (AWS KMS, HashiCorp Vault)
- Use read-only RPC endpoints where possible
- Implement API rate limiting and authentication
- Regular security updates for dependencies

### Monitoring
- Integrate with Prometheus/Grafana for metrics
- Set up alerts for consecutive failures, processing delays
- Log aggregation with ELK stack or similar
- APM monitoring (New Relic, DataDog)

## Troubleshooting

### Common Issues

**Event listener not starting**
```bash
# Check RPC connection
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC_URL
```

**Database connection issues**
```bash
# Test PostgreSQL connection
psql postgres://ktty_user:secure_password@localhost:5432/ktty_companions -c "SELECT 1"
```

**Missing token mappings**
- Check `tokenMapping.json` file exists and is valid JSON
- Verify all expected token IDs have corresponding random codes
- Review application logs for validation errors

**Gas price too high**
- Adjust `MAX_GAS_PRICE` in environment variables
- Monitor gas prices and adjust `GAS_MULTIPLIER`

### Logs

Important log patterns to watch:

```bash
# Successful batch processing
grep "Successfully processed batch" logs/

# Event processing errors  
grep "Failed to process TokenRevealed" logs/

# Connection issues
grep "reconnect\|WebSocket.*error\|Provider.*error" logs/
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see LICENSE file for details.
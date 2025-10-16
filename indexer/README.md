# KTTY Companions Indexer

A resilient, fault-tolerant NestJS indexer service that tracks Transfer events from the KttyWorldCompanions NFT contract, maintains ownership records, and pre-fetches metadata for efficient querying.

## 🚀 Features

- **🔊 Event Indexing**: Real-time Transfer event monitoring with WebSocket + HTTP fallback
- **📊 NFT Tracking**: Complete ownership history and current state for each NFT
- **🖼️ Metadata Caching**: Automatic tokenURI fetching and IPFS gateway support
- **🔄 Fault Tolerance**: Automatic recovery, retry logic, and block catchup
- **⚡ Fast Queries**: Pre-indexed data for instant NFT and ownership lookups
- **🏥 Health Monitoring**: Comprehensive health checks and metrics
- **🐳 Production Ready**: Docker deployment with PostgreSQL

## 📋 Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Event Listener │───▶│  Transfer Parser │───▶│ Metadata Fetcher│
│                 │    │                  │    │                 │
│ - WebSocket RPC │    │ - Extract owners │    │ - Fetch tokenURI│
│ - HTTP fallback │    │ - Detect mints   │    │ - Cache metadata│
│ - Block recovery│    │ - Track transfers│    │ - Parse JSON    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   PostgreSQL    │    │   NFT Records    │    │   API Endpoints │
│                 │    │                  │    │                 │
│ - nfts table    │    │ - token_id       │    │ - GET /nfts/:id │
│ - transfers     │    │ - current_owner  │    │ - GET /nfts     │
│ - metadata      │    │ - metadata_json  │    │ - GET /owners/X │
│ - sync_state    │    │ - created_at     │    │ - Health checks │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🏁 Quick Start

### Prerequisites

- Node.js 18+
- PostgreSQL 15+ (or use Docker Compose)
- Ethereum RPC endpoint (Infura, Alchemy, etc.)

### Option 1: Docker Compose (Recommended)

1. **Clone and configure**:
   ```bash
   # Create environment file
   cp .env.example .env
   
   # Edit .env with your configuration
   nano .env
   ```

2. **Required Environment Variables**:
   ```env
   RPC_URL=https://mainnet.infura.io/v3/YOUR_INFURA_KEY
   CONTRACT_ADDRESS=0x1234567890123456789012345678901234567890
   DEPLOYMENT_BLOCK=18000000
   ```

3. **Start services**:
   ```bash
   docker-compose up -d
   ```

4. **Run database migrations**:
   ```bash
   # Generate and run migrations
   docker-compose exec indexer npm run db:generate
   docker-compose exec indexer npm run db:migrate
   ```

5. **Monitor logs**:
   ```bash
   docker-compose logs -f indexer
   ```

### Option 2: Manual Setup

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Generate TypeChain types**:
   ```bash
   npm run typechain
   ```

3. **Setup database**:
   ```bash
   # Make sure PostgreSQL is running
   createdb ktty_indexer
   
   # Run migrations
   npm run db:generate
   npm run db:migrate
   ```

4. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

5. **Start development server**:
   ```bash
   npm run start:dev
   ```

## 🔧 Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RPC_URL` | ✅ | - | Primary Ethereum RPC endpoint |
| `RPC_URL_FALLBACK` | ❌ | - | Fallback RPC endpoint |
| `CONTRACT_ADDRESS` | ✅ | - | KttyWorldCompanions contract address |
| `DEPLOYMENT_BLOCK` | ✅ | - | Block number when contract was deployed |
| `DB_HOST` | ✅ | localhost | PostgreSQL host |
| `DB_PORT` | ❌ | 5432 | PostgreSQL port |
| `DB_USERNAME` | ✅ | ktty_indexer | Database username |
| `DB_PASSWORD` | ✅ | - | Database password |
| `DB_NAME` | ✅ | ktty_indexer | Database name |
| `MAX_BLOCKS_PER_BATCH` | ❌ | 1000 | Max blocks to process in one batch |
| `METADATA_FETCH_TIMEOUT_MS` | ❌ | 10000 | Timeout for metadata requests |

### Database Schema

The indexer creates these main tables:

- **`nfts`**: Current state of each NFT (owner, metadata, etc.)
- **`transfer_events`**: Complete transfer history
- **`metadata_cache`**: Cached tokenURI metadata
- **`sync_state`**: Tracks indexing progress
- **`failed_operations`**: Failed operations for retry

## 📡 API Endpoints

### NFT Data
- `GET /nfts` - List NFTs with pagination and filtering
- `GET /nfts/:tokenId` - Get specific NFT details
- `GET /nfts/:tokenId/transfers` - Get transfer history for token
- `GET /nfts/owners/:address` - Get NFTs owned by address
- `GET /nfts/transfers/all` - Get all transfers with filtering

### Monitoring
- `GET /health` - Comprehensive health check
- `GET /health/ready` - Kubernetes readiness probe
- `GET /health/live` - Kubernetes liveness probe
- `GET /indexer/status` - Detailed indexer status
- `GET /indexer/metrics` - Performance metrics

### Admin Operations
- `POST /indexer/catchup` - Force manual catchup
- `POST /indexer/retry-failed` - Retry failed operations

## 📊 Example API Responses

### Get NFT Details
```bash
curl http://localhost:3001/nfts/123
```

```json
{
  "tokenId": 123,
  "currentOwner": "0x742d35Cc6634C0532925a3b8D0E8A29d2C6E2D8F",
  "contractAddress": "0x...",
  "tokenUri": "https://ipfs.io/ipfs/Qm...",
  "metadata": {
    "name": "KTTY Companion #123",
    "description": "A loyal companion in the KTTY world",
    "image": "https://ipfs.io/ipfs/Qm.../123.png",
    "attributes": [...]
  },
  "isRevealed": true,
  "createdAt": "2024-01-01T00:00:00.000Z",
  "updatedAt": "2024-01-01T00:00:00.000Z"
}
```

### Get NFTs by Owner
```bash
curl "http://localhost:3001/nfts?owner=0x742d35Cc6634C0532925a3b8D0E8A29d2C6E2D8F&limit=10"
```

### Get Indexer Status
```bash
curl http://localhost:3001/indexer/status
```

```json
{
  "timestamp": "2024-01-15T10:30:00.000Z",
  "sync": {
    "currentBlock": 18500000,
    "lastProcessedBlock": 18499995,
    "blocksBehind": 5,
    "isSyncing": false,
    "isHealthy": true
  },
  "processing": {
    "totalNfts": 1500,
    "totalTransfers": 3200,
    "failedOperations": 0
  },
  "metadata": {
    "nftsWithMetadata": 1450,
    "metadataPercentage": 97,
    "cacheSize": 1450,
    "staleMetadata": 20
  },
  "overall": {
    "healthy": true,
    "caughtUp": true,
    "indexingActive": true
  }
}
```

## 🔄 Recovery & Resilience

### Startup Recovery
1. Queries last processed block from database
2. Scans for missed Transfer events since last block
3. Processes backlog before starting real-time listening
4. Validates and fetches missing metadata

### Error Handling
- **RPC Failures**: Exponential backoff with WebSocket → HTTP fallback
- **Metadata Failures**: Retry with exponential backoff, IPFS gateway rotation
- **Database Issues**: Connection pooling with automatic reconnection
- **Event Processing**: Idempotent processing prevents duplicates

### Monitoring & Alerts

The indexer provides comprehensive monitoring:

```bash
# Check if caught up (< 5 blocks behind)
curl http://localhost:3001/health/ready

# Get performance metrics
curl http://localhost:3001/indexer/metrics

# Monitor logs
docker-compose logs -f indexer | grep -E "(ERROR|WARN|Successfully processed)"
```

## 🛠️ Development

### Running Tests
```bash
npm run test
npm run test:watch
npm run test:cov
```

### Database Management
```bash
# Generate new migration
npm run db:generate

# Apply migrations
npm run db:migrate

# Open Drizzle Studio
npm run db:studio
```

### Linting & Formatting
```bash
npm run lint
npm run format
```

## 🚀 Production Deployment

### Docker Production Build
```bash
# Build production image
docker build -t ktty-indexer:latest .

# Run with production settings
docker run -d \
  --name ktty-indexer \
  -p 3001:3001 \
  -e NODE_ENV=production \
  -e RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY \
  -e CONTRACT_ADDRESS=0x... \
  -e DEPLOYMENT_BLOCK=18000000 \
  ktty-indexer:latest
```

### Kubernetes Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ktty-indexer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ktty-indexer
  template:
    metadata:
      labels:
        app: ktty-indexer
    spec:
      containers:
      - name: indexer
        image: ktty-indexer:latest
        ports:
        - containerPort: 3001
        env:
        - name: RPC_URL
          valueFrom:
            secretKeyRef:
              name: indexer-secrets
              key: rpc-url
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 3001
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health/live
            port: 3001
          initialDelaySeconds: 60
          periodSeconds: 30
```

## 🔍 Troubleshooting

### Common Issues

**Indexer not starting**
```bash
# Check logs
docker-compose logs indexer

# Verify environment variables
docker-compose exec indexer env | grep -E "(RPC_URL|CONTRACT_ADDRESS|DB_)"
```

**High blocks behind**
```bash
# Check RPC connection
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  $RPC_URL

# Force catchup
curl -X POST http://localhost:3001/indexer/catchup
```

**Missing metadata**
```bash
# Check metadata stats
curl http://localhost:3001/indexer/metrics

# Check failed operations
docker-compose exec indexer npm run db:studio
# Navigate to failed_operations table
```

### Log Patterns
```bash
# Successful processing
grep "Successfully processed" logs/

# Event processing errors
grep "Failed to process Transfer" logs/

# Connection issues
grep -E "reconnect|WebSocket.*error|Provider.*error" logs/
```

## 📄 License

MIT License - see LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
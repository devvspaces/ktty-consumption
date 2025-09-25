# KTTY World Test Environment Setup

## Prerequisites

- Node.js v18+
- Foundry installed
- Private key with deployment funds

## 1. Install Dependencies

```bash
npm install ethers dotenv
```

## 2. Environment Configuration

Create `.env` file:

```env
PRIVATE_KEY=0x...
RPC_URL=https://...
```

## 3. Generate Test Data

```bash
# Generate companion metadata (60 NFTs)
node scripts/generateCompanionMetadata.js

# Aggregate companion data
node scripts/aggregateCompanionMetadata.js

# Select 10 NFTs for airdrop, leave 50 for books
node scripts/selectTestNFTs.js

# Generate 50 books with proper distribution
node scripts/generateBooks.js
```

## 4. Deploy Contracts

```bash
# Deploy NFT contracts first
forge script script/DeployNFTs.s.sol --rpc-url rpc_url --broadcast -vvv

# Copy addresses from output and update DeployMinting.s.sol constants:
# COMPANIONS_ADDRESS, TOOLS_ADDRESS, COLLECTIBLES_ADDRESS

# Deploy minting contract and mint all NFTs to it
forge script script/DeployMinting.s.sol --rpc-url rpc_url --broadcast -vvv

# Upgrade minting contract
forge script script/UpgradeMinting.s.sol --rpc-url rpc_url --broadcast -vvv

# Upgrade minting contract
forge script script/UpgradeBooks.s.sol --rpc-url rpc_url --broadcast -vvv
```

## Verify contracts

```bash
forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0x096A4ea0F0fca1B89e1cA79e9462470924fE89B9" dependencies/@openzeppelin-contracts-5.4.0/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy


forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0x905fc59bb45cebacC80B79dD4B01921233E39272" src/KttyWorldCompanions.sol:DummyCompanions


forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0x26b5ebc57D0eF13dadd41A52Ba32B28Ee06D7Fae" src/KttyWorldBooks.sol:DummyBooks


forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0xD5BA8E6bEB096954804B61220F91dC73714c33E0" src/KttyWorldTools.sol:DummyTools


forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0xc2612b4eCDa1BfA7A5860Fdb36f7211983443dBa" src/KttyWorldCollectibles.sol:DummyCollectibles


```

## 5. Update Environment

Add minting contract address to `.env`:

```env
MINTING_CONTRACT_ADDRESS=0x...
```

## 6. Load Books and Distributions

```bash
# Load all 50 books into minting contract (batched)
node scripts/loadBooks.js

# Load pool and bucket distributions
node scripts/loadDistributions.js
```

## 7. Additional Configuration (Optional)

- Set whitelist allowances for rounds 1-2
- Set merkle root for round 3
- Update round timestamps if needed

## Files Generated

- `metadata/companions/` - 60 companion metadata files
- `metadata/tools/` - 5 tool metadata files
- `metadata/collectibles/` - 1 golden ticket file
- `scripts/airdrop-nfts.json` - 10 NFTs for manual airdrop
- `scripts/remaining-nfts.json` - 50 NFTs for books
- `scripts/all-books.json` - All 50 books data
- `scripts/book-distributions.json` - Pool/bucket assignments
- `scripts/books-loaded-progress.json` - Loading progress tracker
- `scripts/distributions-loaded-progress.json` - Distribution progress tracker

## Result

- 60 companion NFTs minted to minting contract
- 300 tools (60 each × 5 types) minted to minting contract
- 16 golden tickets minted to minting contract
- 50 books loaded and distributed across pools/buckets
- Ready for minting tests and operations

```bash

0xd8C4E87473bc36B6d1A22e4fbB5Bf3681c26B3C1
0xA0Ca70DFB6Fb79fD5EF160D3EAc677868547ffEF

cast call \
$MINTING_CONTRACT_ADDRESS \
"setWhitelistAllowances(uint256,address[],uint256[])" \
1 \
"[0xd8C4E87473bc36B6d1A22e4fbB5Bf3681c26B3C1, \
0xC792F91084F131e18adcBE28045737b94ac5C922, \
0x0DE92325AC09eC459Fe02625c144Ee07B3115dA1, \
0x2E9eB05347148Ad9bf7bc001092a8fD353D774cf, \
0xA0Ca70DFB6Fb79fD5EF160D3EAc677868547ffEF]" \
"[3,3,3,3,3]" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"setWhitelistAllowances(uint256,address[],uint256[])" \
2 \
"[0xd8C4E87473bc36B6d1A22e4fbB5Bf3681c26B3C1, \
0xC792F91084F131e18adcBE28045737b94ac5C922, \
0x0DE92325AC09eC459Fe02625c144Ee07B3115dA1, \
0x2E9eB05347148Ad9bf7bc001092a8fD353D774cf, \
0xA0Ca70DFB6Fb79fD5EF160D3EAc677868547ffEF]" \
"[10,10,10,10,10]" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY


cast call \
$MINTING_CONTRACT_ADDRESS \
"setRound3MerkleRoot(bytes32)" \
0x2aa757b2803ce74ce3676de8eb505f07bc5f289dfa94fa7001f6c4232aee1050 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast send \
$MINTING_CONTRACT_ADDRESS \
"configureRound(uint256,uint256,uint256)" \
4 \
1758585600 \
1758844800 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"setTreasuryWallet(address)" \
0xA0Ca70DFB6Fb79fD5EF160D3EAc677868547ffEF \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"configurePayment(uint256,uint8,uint56,uint256)" \
1 \
0 \
100000000000000 \
0 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"configurePayment(uint256,uint8,uint56,uint256)" \
1 \
1 \
100000000000000 \
1000000000000000000 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$BOOKS_ADDRESS \
"setRevealed(bool)" \
true \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY


cast call \
$BOOKS_ADDRESS \
"tokenURI(uint256)(string)" \
21 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"distributeSpilloverToBuckets()" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"getPoolAndBucketStatus()(uint256,uint256,uint256,uint256,uint256,uint256[2][8])" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

```
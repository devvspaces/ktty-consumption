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

# Upgrade minting contract
forge script script/UpgradeCompanions.s.sol --rpc-url rpc_url --broadcast -vvv
```

## Verify contracts

```bash
forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0x93cc76578E049C338D666DcfcE91929dfBB3033a" dependencies/@openzeppelin-contracts-5.4.0/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy


forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0xe79860E645d2d546fe7Bd1A81FDe3D6C3FdAF506" src/KttyWorldCompanions.sol:KttyWorldCompanions


forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0x9C0e11C0581453531B5e32d6cBa6bfb77D3D0EB6" src/KttyWorldBooks.sol:KttyWorldBooks


forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0xa71132f3251187e82A4B430fe10Ba800C9e29f7f" src/KttyWorldTools.sol:KttyWorldTools


forge verify-contract --verifier sourcify --verifier-url https://sourcify.roninchain.com/server/ --chain-id 2020 "0x0171fe2cd9bC95096022307B8855F052A0c93127" src/KttyWorldCollectibles.sol:KttyWorldCollectibles


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

cast send \
$MINTING_CONTRACT_ADDRESS \
"setWhitelistAllowances(uint256,address[],uint256[])" \
1 \
"[0xA0Ca70DFB6Fb79fD5EF160D3EAc677868547ffEF, \
0xA0Ca70DFB6Fb79fD5EF160D3EAc677868547ffEF]" \
"[3,3]" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast send \
$MINTING_CONTRACT_ADDRESS \
"setWhitelistAllowances(uint256,address[],uint256[])" \
2 \
"[0xd8C4E87473bc36B6d1A22e4fbB5Bf3681c26B3C1, \
0xC792F91084F131e18adcBE28045737b94ac5C922, \
0x6cCEE92AA207C7CA81fe8B63D30A2FCDb7f0089E, \
0x9B100F221b1975230DD007D1E5e59accF9e7b911, \
0xa021a0Dd5073AEb3d2D5cd39B7A0a7710Ef18977, \
0x36987b91dd3e3455EecF5C3306147B81CF51Ac77, \
0xA0Ca70DFB6Fb79fD5EF160D3EAc677868547ffEF]" \
"[10,10,10,10,10,10,10]" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY


cast send \
$MINTING_CONTRACT_ADDRESS \
"setRound3MerkleRoot(bytes32)" \
0xa56aeba8878f1cf3991c0347a322b8059f20178cdade199a30e1847dedbd46c6 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast send \
"0x8A9b145124b9783d4f9a5262847bcD6eF20B8D1C" \
"configureRound(uint256,uint256,uint256)" \
3 \
1759440531 \
1759440531 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast send \
$MINTING_CONTRACT_ADDRESS \
"configureRound(uint256,uint256,uint256)" \
4 \
1759440531 \
1854158400 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"setTreasuryWallet(address)" \
"0x3A60dB98166D138BEA5d182E1238F3AE9f6C88cD" \
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
$COMPANIONS_ADDRESS \
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
"distributePool1SpilloverToBuckets(uint256)" \
200 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"getPool1SpilloverProgress()(uint256,uint256,uint256)" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"distributeSpilloverToBuckets()" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY \
--gas-limit 20000000 \
--priority-gas-price 20000000000 \  # 2 gwei priority fee
--max-fee-per-gas 50000000000      # 50 gwei max fee

cast call \
$MINTING_CONTRACT_ADDRESS \
"distributeSpilloverToBuckets()" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$MINTING_CONTRACT_ADDRESS \
"mint(uint256,uint8,bytes32[])" \
1 \
1 \
"[]" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY \
--value 25000000000000000000

cast call \
$MINTING_CONTRACT_ADDRESS \
"getPoolAndBucketStatus()(uint256,uint256,uint256,uint256,uint256,uint256[2][8])" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY


cast call \
$MINTING_CONTRACT_ADDRESS \
"mint(uint256,uint8,bytes32[])" \
1 \
1 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY


cast call \
$BOOKS_ADDRESS \
"name()(string)" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY


cast call \
$BOOKS_ADDRESS \
"updateName(string)" \
"Ktty World Books" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$BOOKS_ADDRESS \
"ownerOf(uint256)(address)" \
1813 \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$COMPANIONS_ADDRESS \
"setHiddenMetadataUri(string)" \
"https://amber-eligible-dragon-276.mypinata.cloud/ipfs/bafybeihduimd3hoobarsx26ti42ehsf2hee3l5gt3wimv52iqit7uexyqi/" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY


cast call \
$MINTING_CONTRACT_ADDRESS \
"setTreasuryWallet(address)" \
"0x3A60dB98166D138BEA5d182E1238F3AE9f6C88cD" \
--rpc-url rpc_url --private-key $PRIVATE_KEY

80, 76 70 61 55 53 50 45 42 40 38 34 21 19

cast send \
"0x33099daa3a4a8d876be198e312be675b0614610e" \
"transferFrom(address,address,uint256)" \
0xA0Ca70DFB6Fb79fD5EF160D3EAc677868547ffEF \
0xa021a0Dd5073AEb3d2D5cd39B7A0a7710Ef18977 \
19 \
--rpc-url rpc_url --private-key $PRIVATE_KEY

# base url companions 

cast call \
$COMPANIONS_ADDRESS \
"setBaseTokenUri(string)" \
"https://amber-eligible-dragon-276.mypinata.cloud/ipfs/" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

cast call \
$COMPANIONS_ADDRESS \
"baseTokenUri()(string)" \
--rpc-url rpc_url \
--private-key $PRIVATE_KEY

```
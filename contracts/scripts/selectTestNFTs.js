const fs = require('fs');
const path = require('path');

/**
 * Shuffle array using Fisher-Yates algorithm
 */
function shuffleArray(array) {
    const shuffled = [...array];
    for (let i = shuffled.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
    return shuffled;
}

/**
 * Select test NFTs for airdrop and separate remaining for book generation
 */
function selectTestNFTs() {
    console.log('🎯 Selecting Test NFTs for Round 0 Airdrop...\n');
    
    // Input file
    const inputFile = path.join(__dirname, 'aggregated-companions.json');
    if (!fs.existsSync(inputFile)) {
        throw new Error(`Input file not found: ${inputFile}`);
    }
    
    // Output files
    const airdropFile = path.join(__dirname, 'airdrop-nfts.json');
    const remainingFile = path.join(__dirname, 'remaining-nfts.json');
    
    console.log(`📖 Reading aggregated companions from: ${inputFile}`);
    
    // Read and parse input data
    const inputData = JSON.parse(fs.readFileSync(inputFile, 'utf8'));
    
    console.log(`📊 Input data summary:`);
    console.log(`   - Total NFTs: ${inputData.length}`);
    
    // Analyze current distribution
    const typeCounts = {};
    inputData.forEach(nft => {
        typeCounts[nft.type] = (typeCounts[nft.type] || 0) + 1;
    });
    
    console.log(`   - Type distribution:`);
    Object.entries(typeCounts).forEach(([type, count]) => {
        console.log(`     • ${type}: ${count}`);
    });
    
    // Filter NULL NFTs
    const nullNFTs = inputData.filter(nft => nft.type === "Null KTTY");
    const nonNullNFTs = inputData.filter(nft => nft.type !== "Null KTTY");
    
    console.log(`\n🔍 Filtering NULL NFTs:`);
    console.log(`   - NULL NFTs found: ${nullNFTs.length}`);
    console.log(`   - Non-NULL NFTs: ${nonNullNFTs.length}`);
    
    // Validate we have enough NULL NFTs
    if (nullNFTs.length < 10) {
        throw new Error(`Not enough NULL NFTs found. Need 10, found ${nullNFTs.length}`);
    }
    
    // Randomly select 10 NULL NFTs for airdrop
    console.log(`\n🎲 Randomly selecting 10 NULL NFTs for airdrop...`);
    const shuffledNullNFTs = shuffleArray(nullNFTs);
    const selectedForAirdrop = shuffledNullNFTs.slice(0, 10);
    const remainingNullNFTs = shuffledNullNFTs.slice(10);
    
    console.log(`   - Selected for airdrop: ${selectedForAirdrop.length}`);
    console.log(`   - Remaining NULL NFTs: ${remainingNullNFTs.length}`);
    
    // Combine remaining NULL NFTs with non-NULL NFTs
    const remainingNFTs = [...remainingNullNFTs, ...nonNullNFTs];
    
    // Sort both arrays by token ID for consistency
    selectedForAirdrop.sort((a, b) => a.tokenId - b.tokenId);
    remainingNFTs.sort((a, b) => a.tokenId - b.tokenId);
    
    console.log(`\n📋 Final distribution:`);
    console.log(`   - Airdrop NFTs: ${selectedForAirdrop.length}`);
    console.log(`   - Remaining NFTs: ${remainingNFTs.length}`);
    
    // Validate final counts
    if (selectedForAirdrop.length !== 10) {
        throw new Error(`Expected 10 airdrop NFTs, got ${selectedForAirdrop.length}`);
    }
    
    if (remainingNFTs.length !== 50) {
        throw new Error(`Expected 50 remaining NFTs, got ${remainingNFTs.length}`);
    }
    
    // Analyze remaining distribution
    const remainingTypeCounts = {};
    remainingNFTs.forEach(nft => {
        remainingTypeCounts[nft.type] = (remainingTypeCounts[nft.type] || 0) + 1;
    });
    
    console.log(`   - Remaining type distribution:`);
    Object.entries(remainingTypeCounts).forEach(([type, count]) => {
        console.log(`     • ${type}: ${count}`);
    });
    
    // Write airdrop NFTs file
    fs.writeFileSync(airdropFile, JSON.stringify(selectedForAirdrop, null, 2));
    console.log(`\n💾 Saved airdrop NFTs to: ${airdropFile}`);
    
    // Write remaining NFTs file
    fs.writeFileSync(remainingFile, JSON.stringify(remainingNFTs, null, 2));
    console.log(`💾 Saved remaining NFTs to: ${remainingFile}`);
    
    // Show samples
    console.log(`\n📋 Airdrop NFTs sample (first 3):`);
    selectedForAirdrop.slice(0, 3).forEach(nft => {
        console.log(`   - Token ${nft.tokenId}: ${nft.name} (${nft.type})`);
    });
    
    console.log(`\n📋 Remaining NFTs sample (first 3):`);
    remainingNFTs.slice(0, 3).forEach(nft => {
        console.log(`   - Token ${nft.tokenId}: ${nft.name} (${nft.type})`);
    });
    
    // Validation check
    const allTokenIds = [...selectedForAirdrop, ...remainingNFTs].map(nft => nft.tokenId);
    const uniqueTokenIds = new Set(allTokenIds);
    
    if (uniqueTokenIds.size !== 60) {
        throw new Error(`Token ID validation failed. Expected 60 unique IDs, got ${uniqueTokenIds.size}`);
    }
    
    console.log(`\n✅ Validation passed: All 60 NFTs accounted for with no duplicates`);
    console.log(`🎉 Successfully separated NFTs for airdrop and book generation!`);
    
    return {
        airdropFile,
        remainingFile,
        airdropCount: selectedForAirdrop.length,
        remainingCount: remainingNFTs.length,
        remainingTypeCounts
    };
}

// Run the script if called directly
if (require.main === module) {
    try {
        selectTestNFTs();
    } catch (error) {
        console.error('❌ Error selecting test NFTs:', error);
        process.exit(1);
    }
}

module.exports = { selectTestNFTs };
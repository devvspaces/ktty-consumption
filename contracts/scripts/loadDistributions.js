const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// Configuration
const DISTRIBUTIONS_FILE = path.join(__dirname, 'book-distributions.json');
const PROGRESS_FILE = path.join(__dirname, 'distributions-loaded-progress.json');

// Contract ABI for the methods we need
const MINTING_ABI = [
    "function loadPool1(uint256[] calldata bookIds) external",
    "function loadPool2(uint256[] calldata bookIds) external", 
    "function loadBucket(uint256 bucketIndex, uint256[] calldata bookIds, uint256 nullCount, uint256 oneOfOneCount, uint256 goldenTicketCount, uint256 basicCount) external",
    "function getBook(uint256 bookId) external view returns (tuple(uint256 nftId, uint256[3] toolIds, uint256 goldenTicketId, bool hasGoldenTicket, string nftType))",
    "function getPoolAndBucketStatus() external view returns (uint256 pool1Remaining, uint256 pool2Remaining, uint256 currentBucket, uint256[8] memory bucketRemaining)",
    "function owner() external view returns (address)"
];

/**
 * Sleep for specified milliseconds
 */
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve));
}

/**
 * Load progress from file or create new progress
 */
function loadProgress() {
    if (fs.existsSync(PROGRESS_FILE)) {
        try {
            const progress = JSON.parse(fs.readFileSync(PROGRESS_FILE, 'utf8'));
            console.log('📋 Loaded existing progress:', progress);
            return progress;
        } catch (error) {
            console.warn('⚠️  Error reading progress file, starting fresh:', error.message);
        }
    }
    
    return {
        pool1Loaded: false,
        pool2Loaded: false,
        bucketsLoaded: {
            bucket1: false,
            bucket2: false,
            bucket3: false,
            bucket4: false,
            bucket5: false,
            bucket6: false,
            bucket7: false,
            bucket8: false
        },
        lastTransactionHash: null,
        timestamp: new Date().toISOString(),
        status: 'not_started'
    };
}

/**
 * Save progress to file
 */
function saveProgress(progress) {
    progress.timestamp = new Date().toISOString();
    fs.writeFileSync(PROGRESS_FILE, JSON.stringify(progress, null, 2));
    console.log('💾 Progress saved');
}

/**
 * Validate that all book IDs exist in the contract
 */
async function validateBookIds(contract, bookIds, description) {
    console.log(`🔍 Validating ${bookIds.length} book IDs for ${description}...`);
    
    for (const bookId of bookIds) {
        try {
            const book = await contract.getBook(bookId);
            if (book.nftId === 0) {
                throw new Error(`Book ${bookId} not found in contract`);
            }
        } catch (error) {
            throw new Error(`Validation failed for book ${bookId} in ${description}: ${error.message}`);
        }
    }
    
    console.log(`✅ All book IDs validated for ${description}`);
}

/**
 * Calculate distribution statistics for buckets
 */
function calculateBucketStats(bookIds, allBooks) {
    const stats = {
        nullCount: 0,
        oneOfOneCount: 0,
        goldenTicketCount: 0,
        basicCount: 0
    };
    
    for (const bookId of bookIds) {
        const book = allBooks.find(b => b.bookId === bookId);
        if (!book) {
            throw new Error(`Book ${bookId} not found in all-books.json`);
        }
        
        switch (book.nftType) {
            case "Null KTTY":
                stats.nullCount++;
                break;
            case "1/1 KTTY":
                stats.oneOfOneCount++;
                break;
            case "Core KTTY":
                stats.basicCount++;
                break;
            default:
                throw new Error(`Unknown NFT type: ${book.nftType} for book ${bookId}`);
        }
        
        if (book.hasGoldenTicket) {
            stats.goldenTicketCount++;
        }
    }
    
    return stats;
}

/**
 * Load pool with retry logic
 */
async function loadPoolWithRetry(contract, poolNumber, bookIds, maxRetries = 3) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            console.log(`📤 Loading Pool ${poolNumber} (attempt ${attempt}/${maxRetries})...`);
            console.log(`📚 Book IDs: [${bookIds.join(', ')}]`);
            
            const methodName = `loadPool${poolNumber}`;
            const tx = await contract[methodName](bookIds, {
                gasLimit: 1000000 // Adjust as needed
            });
            
            console.log(`⏳ Transaction sent: ${tx.hash}`);
            console.log('⏳ Waiting for confirmation...');
            
            const receipt = await tx.wait();
            
            if (receipt.status === 1) {
                console.log(`✅ Pool ${poolNumber} loaded successfully! Gas used: ${receipt.gasUsed.toString()}`);
                return { success: true, hash: tx.hash, gasUsed: receipt.gasUsed.toString() };
            } else {
                throw new Error('Transaction failed');
            }
            
        } catch (error) {
            console.error(`❌ Pool ${poolNumber} attempt ${attempt} failed:`, error.message);
            
            if (attempt === maxRetries) {
                return { success: false, error: error.message };
            }
            
            // Exponential backoff
            const delayMs = Math.pow(2, attempt) * 1000;
            console.log(`⏳ Retrying in ${delayMs / 1000} seconds...`);
            await sleep(delayMs);
        }
    }
}

/**
 * Load bucket with retry logic
 */
async function loadBucketWithRetry(contract, bucketIndex, bookIds, stats, maxRetries = 3) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            console.log(`📤 Loading Bucket ${bucketIndex + 1} (attempt ${attempt}/${maxRetries})...`);
            console.log(`📚 Book IDs: [${bookIds.join(', ')}]`);
            console.log(`📊 Stats: NULL=${stats.nullCount}, 1/1=${stats.oneOfOneCount}, Golden=${stats.goldenTicketCount}, Basic=${stats.basicCount}`);
            
            const tx = await contract.loadBucket(
                bucketIndex,
                bookIds,
                stats.nullCount,
                stats.oneOfOneCount,
                stats.goldenTicketCount,
                stats.basicCount,
                {
                    gasLimit: 1000000 // Adjust as needed
                }
            );
            
            console.log(`⏳ Transaction sent: ${tx.hash}`);
            console.log('⏳ Waiting for confirmation...');
            
            const receipt = await tx.wait();
            
            if (receipt.status === 1) {
                console.log(`✅ Bucket ${bucketIndex + 1} loaded successfully! Gas used: ${receipt.gasUsed.toString()}`);
                return { success: true, hash: tx.hash, gasUsed: receipt.gasUsed.toString() };
            } else {
                throw new Error('Transaction failed');
            }
            
        } catch (error) {
            console.error(`❌ Bucket ${bucketIndex + 1} attempt ${attempt} failed:`, error.message);
            
            if (attempt === maxRetries) {
                return { success: false, error: error.message };
            }
            
            // Exponential backoff
            const delayMs = Math.pow(2, attempt) * 1000;
            console.log(`⏳ Retrying in ${delayMs / 1000} seconds...`);
            await sleep(delayMs);
        }
    }
}

/**
 * Main function to load distributions
 */
async function loadDistributions() {
    console.log('🗂️  Starting KTTY World Distributions Loading...\n');
    
    // Validate environment
    if (!process.env.PRIVATE_KEY) {
        throw new Error('PRIVATE_KEY not found in environment variables');
    }
    
    if (!process.env.RPC_URL) {
        throw new Error('RPC_URL not found in environment variables');
    }
    
    if (!process.env.MINTING_CONTRACT_ADDRESS) {
        throw new Error('MINTING_CONTRACT_ADDRESS not found in environment variables');
    }
    
    // Load distributions data
    if (!fs.existsSync(DISTRIBUTIONS_FILE)) {
        throw new Error(`Distributions file not found: ${DISTRIBUTIONS_FILE}`);
    }
    
    const distributions = JSON.parse(fs.readFileSync(DISTRIBUTIONS_FILE, 'utf8'));
    console.log(`📖 Loaded distributions from ${DISTRIBUTIONS_FILE}`);
    
    // Load all books for statistics calculation
    const allBooksFile = path.join(__dirname, 'all-books.json');
    if (!fs.existsSync(allBooksFile)) {
        throw new Error(`All books file not found: ${allBooksFile}`);
    }
    
    const allBooks = JSON.parse(fs.readFileSync(allBooksFile, 'utf8'));
    console.log(`📚 Loaded ${allBooks.length} books for statistics calculation`);
    
    // Load progress
    const progress = loadProgress();
    
    // Setup provider and contract
    const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const contract = new ethers.Contract(process.env.MINTING_CONTRACT_ADDRESS, MINTING_ABI, wallet);
    
    console.log(`🔗 Connected to RPC: ${process.env.RPC_URL}`);
    console.log(`👤 Wallet address: ${wallet.address}`);
    console.log(`📄 Contract address: ${process.env.MINTING_CONTRACT_ADDRESS}`);
    
    // Check if we're the owner
    try {
        const owner = await contract.owner();
        if (owner.toLowerCase() !== wallet.address.toLowerCase()) {
            throw new Error(`Wallet ${wallet.address} is not the contract owner ${owner}`);
        }
        console.log('✅ Confirmed wallet is contract owner');
    } catch (error) {
        throw new Error(`Failed to verify ownership: ${error.message}`);
    }
    
    progress.status = 'in_progress';
    
    // Load Pool 1
    if (!progress.pool1Loaded) {
        console.log('\n--- Loading Pool 1 ---');
        
        await validateBookIds(contract, distributions.pool1, 'Pool 1');
        
        const result = await loadPoolWithRetry(contract, 1, distributions.pool1);
        
        if (result.success) {
            progress.pool1Loaded = true;
            progress.lastTransactionHash = result.hash;
            saveProgress(progress);
            console.log('✅ Pool 1 loaded successfully');
        } else {
            progress.status = 'failed';
            progress.error = result.error;
            saveProgress(progress);
            throw new Error(`Failed to load Pool 1: ${result.error}`);
        }
        
        await sleep(2000); // Wait between operations
    } else {
        console.log('⏭️  Pool 1 already loaded, skipping');
    }
    
    // Load Pool 2
    if (!progress.pool2Loaded) {
        console.log('\n--- Loading Pool 2 ---');
        
        await validateBookIds(contract, distributions.pool2, 'Pool 2');
        
        const result = await loadPoolWithRetry(contract, 2, distributions.pool2);
        
        if (result.success) {
            progress.pool2Loaded = true;
            progress.lastTransactionHash = result.hash;
            saveProgress(progress);
            console.log('✅ Pool 2 loaded successfully');
        } else {
            progress.status = 'failed';
            progress.error = result.error;
            saveProgress(progress);
            throw new Error(`Failed to load Pool 2: ${result.error}`);
        }
        
        await sleep(2000); // Wait between operations
    } else {
        console.log('⏭️  Pool 2 already loaded, skipping');
    }
    
    // Load Buckets
    for (let bucketIndex = 0; bucketIndex < 8; bucketIndex++) {
        const bucketKey = `bucket${bucketIndex + 1}`;
        const bucketName = `Bucket ${bucketIndex + 1}`;
        
        if (!progress.bucketsLoaded[bucketKey]) {
            console.log(`\n--- Loading ${bucketName} ---`);
            
            const bucketBookIds = distributions.pool3[bucketKey];
            
            if (!bucketBookIds || !Array.isArray(bucketBookIds)) {
                throw new Error(`Invalid bucket data for ${bucketName}`);
            }
            
            await validateBookIds(contract, bucketBookIds, bucketName);
            
            // Calculate statistics for this bucket
            const stats = calculateBucketStats(bucketBookIds, allBooks);
            
            const result = await loadBucketWithRetry(contract, bucketIndex, bucketBookIds, stats);
            
            if (result.success) {
                progress.bucketsLoaded[bucketKey] = true;
                progress.lastTransactionHash = result.hash;
                saveProgress(progress);
                console.log(`✅ ${bucketName} loaded successfully`);
            } else {
                progress.status = 'failed';
                progress.error = result.error;
                saveProgress(progress);
                throw new Error(`Failed to load ${bucketName}: ${result.error}`);
            }
            
            if (bucketIndex < 7) { // Don't wait after the last bucket
                await sleep(2000); // Wait between operations
            }
            
        } else {
            console.log(`⏭️  ${bucketName} already loaded, skipping`);
        }
    }
    
    // Final validation
    console.log('\n🔍 Final validation...');
    
    try {
        const status = await contract.getPoolAndBucketStatus();
        console.log('📊 Final pool and bucket status:');
        console.log(`   - Pool 1 remaining: ${status.pool1Remaining}`);
        console.log(`   - Pool 2 remaining: ${status.pool2Remaining}`);
        console.log(`   - Current bucket: ${status.currentBucket}`);
        console.log('   - Bucket remaining:', status.bucketRemaining.map(r => r.toString()));
        
        // Validate that pools and buckets have the expected counts
        const expectedPool1Size = distributions.pool1.length;
        const expectedPool2Size = distributions.pool2.length;
        
        if (status.pool1Remaining.toString() !== expectedPool1Size.toString()) {
            throw new Error(`Pool 1 size mismatch: expected ${expectedPool1Size}, got ${status.pool1Remaining}`);
        }
        
        if (status.pool2Remaining.toString() !== expectedPool2Size.toString()) {
            throw new Error(`Pool 2 size mismatch: expected ${expectedPool2Size}, got ${status.pool2Remaining}`);
        }
        
        for (let i = 0; i < 8; i++) {
            const expectedBucketSize = distributions.pool3[`bucket${i + 1}`].length;
            if (status.bucketRemaining[i].toString() !== expectedBucketSize.toString()) {
                throw new Error(`Bucket ${i + 1} size mismatch: expected ${expectedBucketSize}, got ${status.bucketRemaining[i]}`);
            }
        }
        
        console.log('✅ All pool and bucket sizes validated successfully');
        
    } catch (error) {
        throw new Error(`Final validation failed: ${error.message}`);
    }
    
    // Mark as completed
    progress.status = 'completed';
    saveProgress(progress);
    
    console.log('\n🎉 All distributions loaded successfully!');
    console.log(`📊 Final stats:`);
    console.log(`   - Pool 1: ${distributions.pool1.length} books`);
    console.log(`   - Pool 2: ${distributions.pool2.length} books`);
    console.log(`   - Pool 3: 8 buckets with ${Object.values(distributions.pool3).reduce((sum, bucket) => sum + bucket.length, 0)} total books`);
    console.log(`   - Last transaction: ${progress.lastTransactionHash}`);
}

// Run the script
if (require.main === module) {
    loadDistributions()
        .then(() => {
            console.log('\n✅ Script completed successfully');
            process.exit(0);
        })
        .catch((error) => {
            console.error('\n❌ Script failed:', error.message);
            console.error(error.stack);
            process.exit(1);
        });
}

module.exports = { loadDistributions };
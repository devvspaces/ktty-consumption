const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const COMPANIONS_ABI = require("./../out/KttyWorldCompanions.sol/KttyWorldCompanions.json").abi;
require('dotenv').config();

// Configuration
const BATCH_SIZE = 250; // Token codes per transaction
const REVEAL_FILE = path.join(__dirname, 'reveal.json');
const PROGRESS_FILE = path.join(__dirname, 'token-codes-progress.json');

/**
 * Sleep for specified milliseconds
 */
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
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
        lastProcessedTokenId: 0,
        totalTokens: 0,
        batchesCompleted: 0,
        batchesRemaining: 0,
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
 * Set token codes with retry logic
 */
async function setTokenCodesWithRetry(contract, tokenIds, codes, batchNumber, maxRetries = 3) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            console.log(`📤 Sending batch ${batchNumber} (attempt ${attempt}/${maxRetries})...`);
            console.log(`🎯 Setting codes for ${tokenIds.length} tokens: ${tokenIds[0]} - ${tokenIds[tokenIds.length - 1]}`);

            const tx = await contract.setBulkTokenCodes(tokenIds, codes, {
                gasLimit: 20000000, // Adjust as needed for batch size
                maxPriorityFeePerGas: ethers.utils.parseUnits("20", "gwei"),
                maxFeePerGas: ethers.utils.parseUnits("50", "gwei")
            });

            console.log(`⏳ Transaction sent: ${tx.hash}`);
            console.log('⏳ Waiting for confirmation...');

            const receipt = await tx.wait();

            if (receipt.status === 1) {
                console.log(`✅ Batch ${batchNumber} successful! Gas used: ${receipt.gasUsed.toString()}`);
                return { success: true, hash: tx.hash, gasUsed: receipt.gasUsed.toString() };
            } else {
                throw new Error('Transaction failed');
            }

        } catch (error) {
            console.error(`❌ Batch ${batchNumber} attempt ${attempt} failed:`, error.message);

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
 * Check if a token code is already set
 */
async function isTokenCodeSet(contract, tokenId) {
    try {
        const code = await contract.getTokenCode(tokenId);
        return code && code.length > 0;
    } catch (error) {
        return false;
    }
}

/**
 * Main function to set token codes
 */
async function setTokenCodes() {
    console.log('🐱 Starting KTTY World Companions Token Codes Setting...\n');

    // Validate environment
    if (!process.env.PRIVATE_KEY) {
        throw new Error('PRIVATE_KEY not found in environment variables');
    }

    if (!process.env.RPC_URL) {
        throw new Error('RPC_URL not found in environment variables');
    }

    if (!process.env.COMPANIONS_ADDRESS) {
        throw new Error('COMPANIONS_ADDRESS not found in environment variables');
    }

    // Load reveal data
    if (!fs.existsSync(REVEAL_FILE)) {
        throw new Error(`Reveal file not found: ${REVEAL_FILE}`);
    }

    const revealData = JSON.parse(fs.readFileSync(REVEAL_FILE, 'utf8'));
    console.log(`🔍 Loaded reveal data for ${Object.keys(revealData).length} tokens`);

    // Convert to arrays for processing
    const tokenEntries = Object.entries(revealData).map(([tokenId, code]) => ({
        tokenId: parseInt(tokenId),
        code: code
    }));

    // Sort by token ID to ensure consistent processing order
    tokenEntries.sort((a, b) => a.tokenId - b.tokenId);

    // Load progress
    const progress = loadProgress();
    progress.totalTokens = tokenEntries.length;

    // Setup provider and contract
    const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const contract = new ethers.Contract(process.env.COMPANIONS_ADDRESS, COMPANIONS_ABI, wallet);

    console.log(`🔗 Connected to RPC: ${process.env.RPC_URL}`);
    console.log(`👤 Wallet address: ${wallet.address}`);
    console.log(`🐱 Companions address: ${process.env.COMPANIONS_ADDRESS}`);

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

    // Determine starting point
    const tokensToProcess = tokenEntries.filter(entry => entry.tokenId > progress.lastProcessedTokenId);

    if (tokensToProcess.length === 0) {
        console.log('🎉 All token codes already set!');
        progress.status = 'completed';
        saveProgress(progress);
        return;
    }

    console.log(`\n📋 Processing status:`);
    console.log(`   - Last processed token ID: ${progress.lastProcessedTokenId}`);
    console.log(`   - Tokens remaining: ${tokensToProcess.length}`);

    // Process in batches
    progress.status = 'in_progress';
    const batches = [];
    for (let i = 0; i < tokensToProcess.length; i += BATCH_SIZE) {
        batches.push(tokensToProcess.slice(i, i + BATCH_SIZE));
    }

    progress.batchesRemaining = batches.length;
    console.log(`📦 Will process ${batches.length} batches of up to ${BATCH_SIZE} tokens each\n`);

    // Process each batch
    for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        const batch = batches[batchIndex];
        const batchNumber = progress.batchesCompleted + batchIndex + 1;

        console.log(`\n🔄 Processing batch ${batchNumber}/${progress.batchesCompleted + batches.length}`);
        console.log(`🎯 Token IDs in this batch: ${batch[0].tokenId} - ${batch[batch.length - 1].tokenId}`);

        // Check if any tokens in this batch already have codes set
        const tokensToSet = [];
        for (const entry of batch) {
            // const isSet = await isTokenCodeSet(contract, entry.tokenId);
            // if (!isSet) {
                tokensToSet.push(entry);
            // } else {
            //     console.log(`⏭️  Token ${entry.tokenId} already has code set, skipping`);
            // }
        }

        if (tokensToSet.length === 0) {
            console.log('⏭️  All tokens in this batch already have codes set, moving to next batch');
            progress.batchesCompleted++;
            progress.lastProcessedTokenId = Math.max(...batch.map(entry => entry.tokenId));
            saveProgress(progress);
            continue;
        }

        // Prepare arrays for contract call
        const tokenIds = tokensToSet.map(entry => entry.tokenId);
        const codes = tokensToSet.map(entry => entry.code);

        // Set token codes with retry
        const result = await setTokenCodesWithRetry(contract, tokenIds, codes, batchNumber);

        if (result.success) {
            progress.batchesCompleted++;
            progress.lastProcessedTokenId = Math.max(...batch.map(entry => entry.tokenId));
            progress.lastTransactionHash = result.hash;
            progress.batchesRemaining = batches.length - batchIndex - 1;
            saveProgress(progress);

            console.log(`✅ Batch ${batchNumber} completed successfully`);
            console.log(`📊 Progress: ${progress.batchesCompleted}/${progress.batchesCompleted + progress.batchesRemaining} batches`);

        } else {
            progress.status = 'failed';
            progress.error = result.error;
            saveProgress(progress);

            console.error(`\n❌ Batch ${batchNumber} failed: ${result.error}`);
            console.error('💾 Progress saved. You can re-run this script to continue from where it left off.');
            process.exit(1);
        }

        // Add delay between batches to avoid rate limiting
        if (batchIndex < batches.length - 1) {
            // console.log('⏳ Waiting 2 seconds before next batch...');
            // await sleep(2000);
        }
    }

    // Final validation
    console.log('\n🔍 Final validation...');
    let allSet = true;
    let validatedCount = 0;
    
    for (const entry of tokenEntries) {
        const isSet = await isTokenCodeSet(contract, entry.tokenId);
        if (!isSet) {
            console.error(`❌ Token ${entry.tokenId} does not have code set in contract`);
            allSet = false;
        } else {
            validatedCount++;
        }
        
        // Log progress every 100 tokens
        if (validatedCount % 100 === 0) {
            console.log(`🔍 Validated ${validatedCount}/${tokenEntries.length} tokens...`);
        }
    }

    if (allSet) {
        progress.status = 'completed';
        console.log('\n🎉 All token codes set successfully!');
        console.log(`📊 Final stats:`);
        console.log(`   - Total tokens processed: ${progress.totalTokens}`);
        console.log(`   - Batches completed: ${progress.batchesCompleted}`);
        console.log(`   - Last transaction: ${progress.lastTransactionHash}`);
    } else {
        progress.status = 'validation_failed';
        console.error('\n❌ Final validation failed! Some token codes are missing.');
    }

    saveProgress(progress);
}

// Run the script
if (require.main === module) {
    setTokenCodes()
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

module.exports = { setTokenCodes };
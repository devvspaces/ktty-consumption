const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const COMPANIONS_ABI = require("./../out/KttyWorldCompanions.sol/KttyWorldCompanions.json").abi;
require('dotenv').config();

// Configuration
const MINT_BATCH_SIZE = 100; // Companions per transaction
const PROGRESS_FILE = path.join(__dirname, 'companions-minted-progress.json');

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
        totalMinted: 0,
        targetSupply: 0,
        currentSupply: 0,
        batchesCompleted: 0,
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
 * Mint companions with retry logic
 */
async function mintCompanionsWithRetry(contract, to, quantity, batchNumber, maxRetries = 3) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            console.log(`📤 Sending batch ${batchNumber} (attempt ${attempt}/${maxRetries})...`);
            console.log(`🎯 Minting ${quantity} companions to ${to}`);

            const tx = await contract.mintAll(to, quantity, {
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
 * Main function to mint all companions
 */
async function mintCompanions() {
    console.log('🐱 Starting KTTY World Companions Minting...\n');

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

    if (!process.env.MINTING_CONTRACT_ADDRESS) {
        throw new Error('MINTING_CONTRACT_ADDRESS not found in environment variables');
    }

    // Load progress
    const progress = loadProgress();

    // Setup provider and contract
    const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const contract = new ethers.Contract(process.env.COMPANIONS_ADDRESS, COMPANIONS_ABI, wallet);

    console.log(`🔗 Connected to RPC: ${process.env.RPC_URL}`);
    console.log(`👤 Wallet address: ${wallet.address}`);
    console.log(`🐱 Companions address: ${process.env.COMPANIONS_ADDRESS}`);
    console.log(`🏭 Minting contract address: ${process.env.MINTING_CONTRACT_ADDRESS}`);

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

    // Get current supply and max supply
    const currentSupply = await contract.totalSupply();
    const maxSupply = await contract.maxSupply();
    
    console.log(`\n📊 Current companion supply: ${currentSupply.toString()}/${maxSupply.toString()}`);
    
    progress.currentSupply = currentSupply.toNumber();
    progress.targetSupply = maxSupply.toNumber();

    // Check if all companions are already minted
    if (currentSupply.gte(maxSupply)) {
        console.log('🎉 All companions already minted!');
        progress.status = 'completed';
        saveProgress(progress);
        return;
    }

    const companionsToMint = maxSupply.sub(currentSupply);
    console.log(`🎯 Companions to mint: ${companionsToMint.toString()}`);

    // Calculate batches
    const batches = [];
    let remaining = companionsToMint.toNumber();
    let batchNumber = progress.batchesCompleted + 1;

    while (remaining > 0) {
        const batchSize = Math.min(MINT_BATCH_SIZE, remaining);
        batches.push({ size: batchSize, number: batchNumber });
        remaining -= batchSize;
        batchNumber++;
    }

    console.log(`📦 Will process ${batches.length} batches of up to ${MINT_BATCH_SIZE} companions each\n`);

    // Process each batch
    progress.status = 'in_progress';
    
    for (const batch of batches) {
        console.log(`\n🔄 Processing batch ${batch.number} (${batch.size} companions)`);

        const result = await mintCompanionsWithRetry(
            contract, 
            process.env.MINTING_CONTRACT_ADDRESS, 
            batch.size, 
            batch.number
        );

        if (result.success) {
            progress.batchesCompleted++;
            progress.totalMinted += batch.size;
            progress.lastTransactionHash = result.hash;
            
            // Update current supply
            const newSupply = await contract.totalSupply();
            progress.currentSupply = newSupply.toNumber();
            
            saveProgress(progress);

            console.log(`✅ Batch ${batch.number} completed successfully`);
            console.log(`📊 Progress: ${progress.currentSupply}/${progress.targetSupply} companions minted`);
            console.log(`📦 Batches completed: ${progress.batchesCompleted}`);

        } else {
            progress.status = 'failed';
            progress.error = result.error;
            saveProgress(progress);

            console.error(`\n❌ Batch ${batch.number} failed: ${result.error}`);
            console.error('💾 Progress saved. You can re-run this script to continue from where it left off.');
            process.exit(1);
        }

        // Add delay between batches to avoid rate limiting
        if (batch !== batches[batches.length - 1]) {
            console.log('⏳ Waiting 2 seconds before next batch...');
            await sleep(2000);
        }
    }

    // Final validation
    console.log('\n🔍 Final validation...');
    const finalSupply = await contract.totalSupply();
    const finalMaxSupply = await contract.maxSupply();
    
    console.log(`📊 Final supply: ${finalSupply.toString()}/${finalMaxSupply.toString()}`);

    if (finalSupply.gte(finalMaxSupply)) {
        progress.status = 'completed';
        progress.currentSupply = finalSupply.toNumber();
        console.log('\n🎉 All companions minted successfully!');
        console.log(`📊 Final stats:`);
        console.log(`   - Total companions minted: ${progress.totalMinted}`);
        console.log(`   - Batches completed: ${progress.batchesCompleted}`);
        console.log(`   - Last transaction: ${progress.lastTransactionHash}`);
    } else {
        progress.status = 'validation_failed';
        console.error('\n❌ Final validation failed! Not all companions were minted.');
    }

    saveProgress(progress);
}

// Run the script
if (require.main === module) {
    mintCompanions()
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

module.exports = { mintCompanions };
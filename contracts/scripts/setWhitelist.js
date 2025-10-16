const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const csv = require('csv-parser');
const MINTING_ABI = require("./../out/KttyWorldMinting.sol/KttyWorldMinting.json").abi;
require('dotenv').config();

// Configuration
const BATCH_SIZE = 20; // Addresses per transaction - configurable
const PROGRESS_FILE_TEMPLATE = 'whitelist-round{round}-progress.json';

/**
 * Sleep for specified milliseconds
 */
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Load progress from file or create new progress
 */
function loadProgress(round) {
    const progressFile = path.join(__dirname, PROGRESS_FILE_TEMPLATE.replace('{round}', round));
    
    if (fs.existsSync(progressFile)) {
        try {
            const progress = JSON.parse(fs.readFileSync(progressFile, 'utf8'));
            console.log(`📋 Loaded existing progress for round ${round}:`, progress);
            return progress;
        } catch (error) {
            console.warn('⚠️  Error reading progress file, starting fresh:', error.message);
        }
    }

    return {
        round: round,
        lastProcessedIndex: -1,
        totalAddresses: 0,
        batchesCompleted: 0,
        batchesRemaining: 0,
        lastTransactionHash: null,
        timestamp: new Date().toISOString(),
        status: 'not_started',
        processedAddresses: []
    };
}

/**
 * Save progress to file
 */
function saveProgress(progress) {
    const progressFile = path.join(__dirname, PROGRESS_FILE_TEMPLATE.replace('{round}', progress.round));
    progress.timestamp = new Date().toISOString();
    fs.writeFileSync(progressFile, JSON.stringify(progress, null, 2));
    console.log('💾 Progress saved');
}

/**
 * Read and parse CSV file
 */
function readCSV(csvPath) {
    return new Promise((resolve, reject) => {
        const results = [];
        
        if (!fs.existsSync(csvPath)) {
            reject(new Error(`CSV file not found: ${csvPath}`));
            return;
        }

        fs.createReadStream(csvPath)
            .pipe(csv())
            .on('data', (data) => {
                // Validate required fields
                if (!data.current_owner || !data.count) {
                    console.warn('⚠️  Skipping row with missing data:', data);
                    return;
                }

                // Validate Ethereum address
                if (!ethers.utils.isAddress(data.current_owner)) {
                    console.warn('⚠️  Invalid address, skipping:', data.current_owner);
                    return;
                }

                // Validate count is a positive number
                const count = parseInt(data.count);
                if (isNaN(count) || count <= 0) {
                    console.warn('⚠️  Invalid count, skipping:', data.count);
                    return;
                }

                results.push({
                    address: ethers.utils.getAddress(data.current_owner), // Normalize address
                    allowance: count
                });
            })
            .on('end', () => {
                console.log(`📄 Successfully parsed ${results.length} entries from CSV`);
                resolve(results);
            })
            .on('error', (error) => {
                reject(error);
            });
    });
}

/**
 * Check if an address already has allowance set in the contract
 */
async function getExistingAllowance(contract, round, address) {
    try {
        const [allowance, minted] = await contract.getWhitelistStatus(round, address);
        return { allowance: allowance.toNumber(), minted: minted.toNumber() };
    } catch (error) {
        console.warn(`⚠️  Error checking allowance for ${address}:`, error.message);
        return { allowance: 0, minted: 0 };
    }
}

/**
 * Set whitelist with retry logic
 */
async function setWhitelistWithRetry(contract, round, addresses, allowances, batchNumber, maxRetries = 3) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            console.log(`📤 Sending batch ${batchNumber} (attempt ${attempt}/${maxRetries})...`);
            console.log(`   - Addresses: ${addresses.slice(0, 3).join(', ')}${addresses.length > 3 ? '...' : ''}`);
            console.log(`   - Total addresses: ${addresses.length}`);

            // Estimate gas first
            const estimatedGas = await contract.estimateGas.setWhitelistAllowances(
                round,
                addresses,
                allowances
            );

            const tx = await contract.setWhitelistAllowances(
                round,
                addresses,
                allowances,
                {
                    gasLimit: estimatedGas.mul(120).div(100), // Add 20% buffer
                    maxPriorityFeePerGas: ethers.utils.parseUnits("20", "gwei"),
                    maxFeePerGas: ethers.utils.parseUnits("50", "gwei")
                }
            );

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
 * Main function to set whitelist
 */
async function setWhitelist(round) {
    console.log(`🎯 Starting KTTY World Whitelist Setup for Round ${round}...\n`);

    // Validate round
    if (round !== 1 && round !== 2) {
        throw new Error('Round must be 1 or 2');
    }

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

    // Load CSV data
    const csvPath = path.join(__dirname, `round${round}.csv`);
    const whitelistData = await readCSV(csvPath);
    
    if (whitelistData.length === 0) {
        throw new Error('No valid whitelist entries found in CSV');
    }

    console.log(`📊 Loaded ${whitelistData.length} whitelist entries for round ${round}`);

    // Load progress
    const progress = loadProgress(round);
    progress.totalAddresses = whitelistData.length;

    // Setup provider and contract
    const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const contract = new ethers.Contract(process.env.MINTING_CONTRACT_ADDRESS, MINTING_ABI, wallet);

    console.log(`🔗 Connected to RPC: ${process.env.RPC_URL}`);
    console.log(`👤 Wallet address: ${wallet.address}`);
    console.log(`📄 Minting contract: ${process.env.MINTING_CONTRACT_ADDRESS}`);

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
    let startIndex = progress.lastProcessedIndex + 1;
    const addressesToProcess = whitelistData.slice(startIndex);

    if (addressesToProcess.length === 0) {
        console.log('🎉 All addresses already processed!');
        progress.status = 'completed';
        saveProgress(progress);
        return;
    }

    console.log(`\n📋 Processing status:`);
    console.log(`   - Last processed index: ${progress.lastProcessedIndex}`);
    console.log(`   - Starting from index: ${startIndex}`);
    console.log(`   - Addresses remaining: ${addressesToProcess.length}`);

    // Check for existing allowances (optional verification)
    console.log('\n🔍 Checking existing allowances...');
    let alreadySetCount = 0;
    const toProcess = [];
    
    for (let i = 0; i < addressesToProcess.length; i++) {
        const entry = addressesToProcess[i];
        const existing = await getExistingAllowance(contract, round, entry.address);
        
        if (existing.allowance > 0) {
            console.log(`⏭️  ${entry.address} already has allowance ${existing.allowance}, skipping`);
            alreadySetCount++;
            progress.lastProcessedIndex = startIndex + i;
            progress.processedAddresses.push(entry.address);
        } else {
            toProcess.push(entry);
        }
    }

    if (alreadySetCount > 0) {
        console.log(`⏭️  ${alreadySetCount} addresses already have allowances set`);
        saveProgress(progress);
    }

    if (toProcess.length === 0) {
        console.log('🎉 All remaining addresses already have allowances!');
        progress.status = 'completed';
        saveProgress(progress);
        return;
    }

    // Process in batches
    progress.status = 'in_progress';
    const batches = [];
    for (let i = 0; i < toProcess.length; i += BATCH_SIZE) {
        batches.push(toProcess.slice(i, i + BATCH_SIZE));
    }

    progress.batchesRemaining = batches.length;
    console.log(`📦 Will process ${batches.length} batches of up to ${BATCH_SIZE} addresses each\n`);

    // Process each batch
    for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        const batch = batches[batchIndex];
        const batchNumber = progress.batchesCompleted + batchIndex + 1;

        console.log(`\n🔄 Processing batch ${batchNumber}/${progress.batchesCompleted + batches.length}`);

        // Prepare batch data
        const addresses = batch.map(entry => entry.address);
        const allowances = batch.map(entry => entry.allowance);

        // Set whitelist with retry
        const result = await setWhitelistWithRetry(contract, round, addresses, allowances, batchNumber);

        if (result.success) {
            progress.batchesCompleted++;
            progress.lastProcessedIndex = startIndex + (batchIndex + 1) * BATCH_SIZE - 1;
            progress.lastTransactionHash = result.hash;
            progress.batchesRemaining = batches.length - batchIndex - 1;
            
            // Track processed addresses
            addresses.forEach(addr => progress.processedAddresses.push(addr));
            
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
            console.log('⏳ Waiting 2 seconds before next batch...');
            await sleep(2000);
        }
    }

    // Final validation
    console.log('\n🔍 Final validation...');
    let allSet = true;
    for (const entry of whitelistData) {
        const existing = await getExistingAllowance(contract, round, entry.address);
        if (existing.allowance !== entry.allowance) {
            console.error(`❌ ${entry.address} expected ${entry.allowance}, got ${existing.allowance}`);
            allSet = false;
        }
    }

    if (allSet) {
        progress.status = 'completed';
        console.log('\n🎉 All whitelist allowances set successfully!');
        console.log(`📊 Final stats:`);
        console.log(`   - Total addresses: ${progress.totalAddresses}`);
        console.log(`   - Batches completed: ${progress.batchesCompleted}`);
        console.log(`   - Last transaction: ${progress.lastTransactionHash}`);
    } else {
        progress.status = 'validation_failed';
        console.error('\n❌ Final validation failed! Some allowances are incorrect.');
    }

    saveProgress(progress);
}

// Main execution
if (require.main === module) {
    // Get round from command line argument
    const round = parseInt(process.argv[2]);
    
    if (!round || (round !== 1 && round !== 2)) {
        console.error('Usage: node setWhitelist.js <round>');
        console.error('Example: node setWhitelist.js 1');
        console.error('         node setWhitelist.js 2');
        process.exit(1);
    }

    setWhitelist(round)
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

module.exports = { setWhitelist };
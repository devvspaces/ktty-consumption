const { ethers } = require('ethers');
const MINTING_ABI = require("./../out/KttyWorldMinting.sol/KttyWorldMinting.json").abi;
require('dotenv').config();

// =============================================
// CONFIGURATION - EDIT THESE VALUES
// =============================================

// Minting quantity (number of books to mint)
const QUANTITY = 1; // Change this to the number of books you want to mint

// Payment Type: 0 = NATIVE_ONLY, 1 = HYBRID
const PAYMENT_TYPE = 1; // Change to 1 for HYBRID payment

// Merkle proof for Round 3 (leave empty array for other rounds)
// For Round 3, you need to provide the merkle proof to verify whitelist status
const MERKLE_PROOF = []; // Example: ["0x123...", "0x456..."]

// Optional: Override gas settings (set to null to use default)
const GAS_SETTINGS = {
    gasLimit: 500000, // Adjust as needed
    maxPriorityFeePerGas: ethers.utils.parseUnits("20", "gwei"),
    maxFeePerGas: ethers.utils.parseUnits("200", "gwei")
};

// =============================================
// SCRIPT LOGIC - DON'T EDIT BELOW THIS LINE
// =============================================

/**
 * Mint books using the KttyWorldMinting contract
 */
async function mintBooks() {
    console.log('📚 Starting KTTY World Book Minting...\n');

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

    // Validate configuration
    if (QUANTITY <= 0) {
        throw new Error('QUANTITY must be greater than 0');
    }

    if (PAYMENT_TYPE !== 0 && PAYMENT_TYPE !== 1) {
        throw new Error('PAYMENT_TYPE must be 0 (NATIVE_ONLY) or 1 (HYBRID)');
    }

    // Setup provider and contract
    const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const contract = new ethers.Contract(process.env.MINTING_CONTRACT_ADDRESS, MINTING_ABI, wallet);

    console.log(`🔗 Connected to RPC: ${process.env.RPC_URL}`);
    console.log(`👤 Wallet address: ${wallet.address}`);
    console.log(`📄 Minting contract: ${process.env.MINTING_CONTRACT_ADDRESS}`);

    // Get current round and payment info
    try {
        const currentRound = await contract.getCurrentRound();
        console.log(`🎯 Current round: ${currentRound}`);

        if (currentRound.toString() === '0') {
            throw new Error('No active round. Minting is not available in manual round (0).');
        }

        // Get payment configuration for current round
        const paymentConfig = await contract.getPaymentConfig(currentRound);
        
        let paymentOption;
        let paymentTypeString;
        
        if (PAYMENT_TYPE === 0) {
            paymentOption = paymentConfig.nativeOnly;
            paymentTypeString = 'NATIVE_ONLY';
        } else {
            paymentOption = paymentConfig.hybrid;
            paymentTypeString = 'HYBRID';
        }

        const totalNativeRequired = paymentOption.nativeAmount.mul(QUANTITY);
        const totalErc20Required = paymentOption.erc20Amount.mul(QUANTITY);

        console.log('\n💰 Payment Information:');
        console.log(`   - Payment Type: ${paymentTypeString}`);
        console.log(`   - Quantity: ${QUANTITY}`);
        console.log(`   - Native per book: ${ethers.utils.formatEther(paymentOption.nativeAmount)} ETH`);
        console.log(`   - Total Native: ${ethers.utils.formatEther(totalNativeRequired)} ETH`);
        
        if (PAYMENT_TYPE === 1) {
            console.log(`   - ERC20 per book: ${paymentOption.erc20Amount.toString()}`);
            console.log(`   - Total ERC20: ${totalErc20Required.toString()}`);
        }

        // Check wallet balance
        const balance = await wallet.getBalance();
        console.log(`\n💳 Wallet balance: ${ethers.utils.formatEther(balance)} ETH`);

        if (balance.lt(totalNativeRequired)) {
            throw new Error(`Insufficient ETH balance. Required: ${ethers.utils.formatEther(totalNativeRequired)} ETH`);
        }

        // Check whitelist status for rounds 1, 2, and 3
        if (currentRound.toString() === '1' || currentRound.toString() === '2') {
            const whitelistStatus = await contract.getWhitelistStatus(currentRound, wallet.address);
            const allowance = whitelistStatus.allowance;
            const minted = whitelistStatus.minted;
            
            console.log(`\n🎫 Whitelist Status (Round ${currentRound}):`);
            console.log(`   - Allowance: ${allowance.toString()}`);
            console.log(`   - Already minted: ${minted.toString()}`);
            console.log(`   - Remaining: ${allowance.sub(minted).toString()}`);

            if (allowance.isZero()) {
                throw new Error(`Not whitelisted for round ${currentRound}`);
            }

            if (minted.add(QUANTITY).gt(allowance)) {
                throw new Error(`Insufficient allowance. Trying to mint ${QUANTITY}, but only ${allowance.sub(minted).toString()} remaining`);
            }
        } else if (currentRound.toString() === '3' && MERKLE_PROOF.length > 0) {
            const isWhitelisted = await contract.isWhitelistedForRound3(wallet.address, MERKLE_PROOF);
            console.log(`\n🎫 Round 3 Whitelist Status: ${isWhitelisted ? '✅ Whitelisted' : '❌ Not whitelisted'}`);
            
            if (!isWhitelisted) {
                throw new Error('Invalid merkle proof for round 3');
            }
        }

        console.log('\n🔄 Simulating mint transaction...');

        // Prepare transaction options for simulation
        const txOptions = {
            value: totalNativeRequired,
            ...GAS_SETTINGS
        };

        try {
            // Simulate the transaction using callStatic (this won't send the transaction)
            await contract.callStatic.mint(
                QUANTITY,
                PAYMENT_TYPE,
                MERKLE_PROOF,
                txOptions
            );

            console.log(`✅ Transaction simulation successful!`);
            console.log(`📊 The mint call would succeed with these parameters`);

            // Estimate gas for the transaction
            const gasEstimate = await contract.estimateGas.mint(
                QUANTITY,
                PAYMENT_TYPE,
                MERKLE_PROOF,
                txOptions
            );

            console.log(`⛽ Estimated gas: ${gasEstimate.toString()}`);
            console.log(`💰 Estimated gas cost: ${ethers.utils.formatEther(gasEstimate.mul(txOptions.maxFeePerGas || ethers.utils.parseUnits("100", "gwei")))} ETH`);

        } catch (simulationError) {
            console.error(`❌ Transaction simulation failed: ${simulationError.message}`);
            
            // Try to extract more specific error information
            if (simulationError.reason) {
                console.error(`🔍 Revert reason: ${simulationError.reason}`);
            }
            
            if (simulationError.code) {
                console.error(`🔢 Error code: ${simulationError.code}`);
            }
            
            throw simulationError;
        }

    } catch (error) {
        console.error('❌ Minting failed:', error.message);
        throw error;
    }
}

// Run the script
if (require.main === module) {
    mintBooks()
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

module.exports = { mintBooks };
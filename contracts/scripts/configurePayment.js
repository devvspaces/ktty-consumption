const { ethers } = require('ethers');
const MINTING_ABI = require("./../out/KttyWorldMinting.sol/KttyWorldMinting.json").abi;
require('dotenv').config();

// =============================================
// CONFIGURATION - EDIT THESE VALUES
// =============================================

const ROUND_NUMBER = 2; // Change this to the round you want to configure (1-4)

// Payment Type: 0 = NATIVE_ONLY, 1 = HYBRID
const PAYMENT_TYPE = 0; // Change to 1 for HYBRID payment

// Native payment amount in ETH (will be converted to wei)
const NATIVE_AMOUNT_ETH = "0.0001"; // Change this value

// ERC20 payment amount (only used for HYBRID payment type)
// This should be in the token's base units (e.g., if token has 18 decimals, 1 = 1e18 base units)
const ERC20_AMOUNT = "1"; // Change this value, will be converted based on token decimals

// Token decimals (only needed for HYBRID payment)
const TOKEN_DECIMALS = 18; // Change if your token has different decimals

// =============================================
// SCRIPT LOGIC - DON'T EDIT BELOW THIS LINE
// =============================================

/**
 * Configure payment for a specific round
 */
async function configurePayment() {
    console.log('💰 Starting KTTY World Payment Configuration...\n');

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
    if (ROUND_NUMBER < 1 || ROUND_NUMBER > 4) {
        throw new Error('ROUND_NUMBER must be between 1 and 4');
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

    // Prepare payment amounts
    const nativeAmountWei = ethers.utils.parseEther(NATIVE_AMOUNT_ETH);
    const erc20AmountTokens = PAYMENT_TYPE === 1 ? 
        ethers.utils.parseUnits(ERC20_AMOUNT, TOKEN_DECIMALS) : 
        ethers.BigNumber.from("0");

    // Display configuration
    console.log('\n📋 Payment Configuration:');
    console.log(`   - Round Number: ${ROUND_NUMBER}`);
    console.log(`   - Payment Type: ${PAYMENT_TYPE === 0 ? 'NATIVE_ONLY' : 'HYBRID'}`);
    console.log(`   - Native Amount: ${NATIVE_AMOUNT_ETH} ETH (${nativeAmountWei.toString()} wei)`);
    
    if (PAYMENT_TYPE === 1) {
        console.log(`   - ERC20 Amount: ${ERC20_AMOUNT} tokens (${erc20AmountTokens.toString()} base units)`);
        console.log(`   - Token Decimals: ${TOKEN_DECIMALS}`);
    }

    console.log('\n🔄 Configuring payment...');

    try {
        // Call configurePayment function
        const tx = await contract.configurePayment(
            ROUND_NUMBER,
            PAYMENT_TYPE,
            nativeAmountWei,
            erc20AmountTokens,
            {
                gasLimit: 3000000, // Adjust as needed
                maxPriorityFeePerGas: ethers.utils.parseUnits("20", "gwei"),
                maxFeePerGas: ethers.utils.parseUnits("200", "gwei")
            }
        );

        console.log(`📤 Transaction sent: ${tx.hash}`);
        console.log('⏳ Waiting for confirmation...');

        const receipt = await tx.wait();

        if (receipt.status === 1) {
            console.log(`✅ Payment configuration successful!`);
            console.log(`📊 Gas used: ${receipt.gasUsed.toString()}`);
            console.log(`🔗 Transaction hash: ${tx.hash}`);
            
            // Verify the configuration
            console.log('\n🔍 Verifying configuration...');
            const paymentConfig = await contract.getPaymentConfig(ROUND_NUMBER);
            
            console.log('\n📋 Current Payment Configuration:');
            console.log(`   - Native Only Payment:`);
            console.log(`     • Native: ${ethers.utils.formatEther(paymentConfig.nativeOnly.nativeAmount)} ETH`);
            console.log(`     • ERC20: ${paymentConfig.nativeOnly.erc20Amount.toString()}`);
            console.log(`   - Hybrid Payment:`);
            console.log(`     • Native: ${ethers.utils.formatEther(paymentConfig.hybrid.nativeAmount)} ETH`);
            console.log(`     • ERC20: ${paymentConfig.hybrid.erc20Amount.toString()}`);
            
        } else {
            throw new Error('Transaction failed');
        }

    } catch (error) {
        console.error('❌ Payment configuration failed:', error.message);
        throw error;
    }
}

// Run the script
if (require.main === module) {
    configurePayment()
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

module.exports = { configurePayment };
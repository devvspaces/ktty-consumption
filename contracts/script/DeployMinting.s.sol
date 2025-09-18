// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {KttyWorldMinting} from "../src/KttyWorldMinting.sol";
import {KttyWorldCompanions} from "../src/KttyWorldCompanions.sol";
import {KttyWorldTools} from "../src/KttyWorldTools.sol";
import {KttyWorldCollectibles} from "../src/KttyWorldCollectibles.sol";

contract DeployMinting is Script {
    // NFT contract addresses (UPDATE THESE FROM DeployNFTs.s.sol OUTPUT)
    address constant COMPANIONS_ADDRESS = 0x0000000000000000000000000000000000000000; // UPDATE
    address constant TOOLS_ADDRESS = 0x0000000000000000000000000000000000000000; // UPDATE
    address constant COLLECTIBLES_ADDRESS = 0x0000000000000000000000000000000000000000; // UPDATE
    
    // Configuration constants
    address constant TREASURY_WALLET = 0x0000000000000000000000000000000000000000; // Update as needed
    address constant KTTY_TOKEN = 0x0000000000000000000000000000000000000000; // Update with actual KTTY token
    uint256 constant MAX_MINT_PER_TX = 10;
    
    // Payment configuration
    uint256 constant NATIVE_ONLY_PRICE = 1 ether;
    uint256 constant HYBRID_NATIVE_PRICE = 0.5 ether;
    uint256 constant HYBRID_KTTY_PRICE = 100 * 10**18; // 100 KTTY tokens
    
    // Round timing configuration (timestamps - UPDATE AS NEEDED)
    uint256 constant ROUND1_START = 1703980800; // Jan 1, 2024 00:00:00 UTC - UPDATE
    uint256 constant ROUND1_END = 1704067200;   // Jan 2, 2024 00:00:00 UTC - UPDATE
    uint256 constant ROUND2_START = 1704153600; // Jan 3, 2024 00:00:00 UTC - UPDATE
    uint256 constant ROUND2_END = 1704240000;   // Jan 4, 2024 00:00:00 UTC - UPDATE
    uint256 constant ROUND3_START = 1704326400; // Jan 5, 2024 00:00:00 UTC - UPDATE
    uint256 constant ROUND3_END = 1704412800;   // Jan 6, 2024 00:00:00 UTC - UPDATE
    uint256 constant ROUND4_START = 1704499200; // Jan 7, 2024 00:00:00 UTC - UPDATE
    uint256 constant ROUND4_END = 1704585600;   // Jan 8, 2024 00:00:00 UTC - UPDATE
    
    // Tool and collectible quantities for test environment
    uint256 constant TOOLS_PER_TYPE = 60;
    uint256 constant GOLDEN_TICKET_SUPPLY = 16;
    uint256 constant COMPANION_SUPPLY = 60;
    
    // Deployment results
    struct DeploymentResult {
        address mintingImpl;
        address mintingProxy;
        uint256 companionsMinted;
        uint256 toolsMinted;
        uint256 collectiblesMinted;
    }

    function run() external {
        // Validate NFT addresses are set
        require(COMPANIONS_ADDRESS != address(0), "COMPANIONS_ADDRESS not set");
        require(TOOLS_ADDRESS != address(0), "TOOLS_ADDRESS not set");
        require(COLLECTIBLES_ADDRESS != address(0), "COLLECTIBLES_ADDRESS not set");
        
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== KTTY World Minting Contract Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Using NFT contracts:");
        console.log("  Companions:", COMPANIONS_ADDRESS);
        console.log("  Tools:", TOOLS_ADDRESS);
        console.log("  Collectibles:", COLLECTIBLES_ADDRESS);
        
        vm.startBroadcast(deployerPrivateKey);
        
        DeploymentResult memory result = deployMintingContract(deployer);
        
        vm.stopBroadcast();
        
        // Print deployment results
        printDeploymentResults(result);
    }
    
    function deployMintingContract(address owner) internal returns (DeploymentResult memory result) {
        console.log("\n--- Deploying Minting Contract ---");
        
        // Deploy Minting Contract
        KttyWorldMinting mintingImpl = new KttyWorldMinting();
        console.log("Minting Implementation:", address(mintingImpl));
        
        bytes memory mintingInitData = abi.encodeCall(
            KttyWorldMinting.initialize,
            (
                owner,
                COMPANIONS_ADDRESS,
                TOOLS_ADDRESS,
                COLLECTIBLES_ADDRESS,
                KTTY_TOKEN,
                TREASURY_WALLET,
                MAX_MINT_PER_TX
            )
        );
        
        ERC1967Proxy mintingProxy = new ERC1967Proxy(address(mintingImpl), mintingInitData);
        console.log("Minting Proxy:", address(mintingProxy));
        
        KttyWorldMinting minting = KttyWorldMinting(address(mintingProxy));
        
        // Configure payment options
        console.log("\n--- Configuring Payment Options ---");
        minting.configurePayment(KttyWorldMinting.PaymentType.NATIVE_ONLY, NATIVE_ONLY_PRICE, 0);
        console.log("Native-only payment configured:", NATIVE_ONLY_PRICE, "wei");
        
        minting.configurePayment(KttyWorldMinting.PaymentType.HYBRID, HYBRID_NATIVE_PRICE, HYBRID_KTTY_PRICE);
        console.log("Hybrid payment configured:", HYBRID_NATIVE_PRICE, "wei +");
        console.log(HYBRID_KTTY_PRICE, "KTTY");
        
        // Configure rounds
        console.log("\n--- Configuring Rounds ---");
        minting.configureRound(1, ROUND1_START, ROUND1_END);
        console.log("Round 1 configured: Start", ROUND1_START, "End", ROUND1_END);
        
        minting.configureRound(2, ROUND2_START, ROUND2_END);
        console.log("Round 2 configured: Start", ROUND2_START, "End", ROUND2_END);
        
        minting.configureRound(3, ROUND3_START, ROUND3_END);
        console.log("Round 3 configured: Start", ROUND3_START, "End", ROUND3_END);
        
        minting.configureRound(4, ROUND4_START, ROUND4_END);
        console.log("Round 4 configured: Start", ROUND4_START, "End", ROUND4_END);
        
        // Mint all NFTs to minting contract
        console.log("\n--- Minting All NFTs to Minting Contract ---");
        
        // Get NFT contract instances
        KttyWorldCompanions companions = KttyWorldCompanions(COMPANIONS_ADDRESS);
        KttyWorldTools tools = KttyWorldTools(TOOLS_ADDRESS);
        KttyWorldCollectibles collectibles = KttyWorldCollectibles(COLLECTIBLES_ADDRESS);
        
        // Mint all companions
        console.log("Minting companions...");
        uint256 companionsBefore = companions.totalSupply();
        companions.mintAll(address(minting));
        uint256 companionsAfter = companions.totalSupply();
        uint256 companionsMinted = companionsAfter - companionsBefore;
        console.log("Companions minted:", companionsMinted, "Total supply:", companionsAfter);
        require(companionsMinted == COMPANION_SUPPLY, "Incorrect companions minted");
        
        // Mint tools (60 of each type, 5 types = 300 total)
        console.log("Minting tools...");
        uint256[] memory toolIds = new uint256[](5);
        uint256[] memory toolAmounts = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            toolIds[i] = i + 1; // Tool IDs are 1-5
            toolAmounts[i] = TOOLS_PER_TYPE;
        }
        tools.batchMint(address(minting), toolIds, toolAmounts);
        console.log("Tools minted: 5 types x", TOOLS_PER_TYPE, "= 300 total");
        
        // Verify tool minting
        uint256 totalToolsMinted = 0;
        for (uint256 i = 0; i < 5; i++) {
            uint256 balance = tools.balanceOf(address(minting), i + 1);
            totalToolsMinted += balance;
            console.log("Tool ID", i + 1, "balance:", balance);
        }
        require(totalToolsMinted == TOOLS_PER_TYPE * 5, "Incorrect tools minted");
        
        // Mint golden tickets
        console.log("Minting golden tickets...");
        uint256[] memory collectibleIds = new uint256[](1);
        uint256[] memory collectibleAmounts = new uint256[](1);
        collectibleIds[0] = 1; // Golden ticket token ID
        collectibleAmounts[0] = GOLDEN_TICKET_SUPPLY;
        collectibles.batchMint(address(minting), collectibleIds, collectibleAmounts);
        
        uint256 goldenTicketBalance = collectibles.balanceOf(address(minting), 1);
        console.log("Golden tickets minted:", goldenTicketBalance);
        require(goldenTicketBalance == GOLDEN_TICKET_SUPPLY, "Incorrect golden tickets minted");
        
        // Final validation
        console.log("\n--- Final Validation ---");
        require(minting.getCurrentRound() == 0, "Should be in manual round initially");
        console.log("Current round:", minting.getCurrentRound(), "(Manual round)");
        
        // Check payment configuration
        (KttyWorldMinting.PaymentOption memory nativeOnly, KttyWorldMinting.PaymentOption memory hybrid) = minting.getPaymentConfig();
        require(nativeOnly.nativeAmount == NATIVE_ONLY_PRICE, "Invalid native-only price");
        require(hybrid.nativeAmount == HYBRID_NATIVE_PRICE, "Invalid hybrid native price");
        require(hybrid.erc20Amount == HYBRID_KTTY_PRICE, "Invalid hybrid ERC20 price");
        console.log("Payment configuration validated");
        
        console.log("All validations passed");
        
        return DeploymentResult({
            mintingImpl: address(mintingImpl),
            mintingProxy: address(mintingProxy),
            companionsMinted: companionsMinted,
            toolsMinted: totalToolsMinted,
            collectiblesMinted: goldenTicketBalance
        });
    }
    
    function printDeploymentResults(DeploymentResult memory result) internal pure {
        console.log("\n=== MINTING CONTRACT DEPLOYMENT COMPLETE ===");
        
        console.log("\n--- Contract Addresses ---");
        console.log("Minting Implementation:", result.mintingImpl);
        console.log("Minting Proxy:", result.mintingProxy);
        
        console.log("\n--- NFT Contract Addresses ---");
        console.log("Companions:", COMPANIONS_ADDRESS);
        console.log("Tools:", TOOLS_ADDRESS);
        console.log("Collectibles:", COLLECTIBLES_ADDRESS);
        
        console.log("\n--- Minted Quantities ---");
        console.log("Companions minted:", result.companionsMinted);
        console.log("Tools minted:", result.toolsMinted);
        console.log("Golden tickets minted:", result.collectiblesMinted);
        
        console.log("\n--- Payment Configuration ---");
        console.log("Native-only price:", NATIVE_ONLY_PRICE, "wei");
        console.log("Hybrid native price:", HYBRID_NATIVE_PRICE, "wei");
        console.log("Hybrid KTTY price:", HYBRID_KTTY_PRICE, "tokens");
        
        console.log("\n--- Round Configuration ---");
        console.log("Round 1:", ROUND1_START, "-", ROUND1_END);
        console.log("Round 2:", ROUND2_START, "-", ROUND2_END);
        console.log("Round 3:", ROUND3_START, "-", ROUND3_END);
        console.log("Round 4:", ROUND4_START, "-", ROUND4_END);
        
        console.log("\n--- Next Steps ---");
        console.log("1. Update round timestamps if needed using configureRound()");
        console.log("2. Set up whitelist allowances for rounds 1 & 2 using setWhitelistAllowances()");
        console.log("3. Set merkle root for round 3 using setRound3MerkleRoot()");
        console.log("4. Run JavaScript script to load book distributions");
        console.log("5. Use minting contract at:", result.mintingProxy);
        
        console.log("\n=== DEPLOYMENT SUCCESS ===");
    }
}
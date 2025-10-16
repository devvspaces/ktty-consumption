// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {KttyWorldMinting} from "../src/KttyWorldMinting.sol";
import {KttyWorldBooks} from "../src/KttyWorldBooks.sol";
import {KttyWorldCompanions} from "../src/KttyWorldCompanions.sol";
import {KttyWorldTools} from "../src/KttyWorldTools.sol";
import {KttyWorldCollectibles} from "../src/KttyWorldCollectibles.sol";

contract DeployMinting is Script {
    // NFT contract addresses (UPDATE THESE FROM DeployNFTs.s.sol OUTPUT)
    address COMPANIONS_ADDRESS = vm.envAddress("COMPANIONS_ADDRESS"); // UPDATE
    address TOOLS_ADDRESS = vm.envAddress("TOOLS_ADDRESS"); // UPDATE
    address COLLECTIBLES_ADDRESS = vm.envAddress("COLLECTIBLES_ADDRESS"); // UPDATE
    address BOOKS_ADDRESS = vm.envAddress("BOOKS_ADDRESS"); // UPDATE

    // Configuration constants
    address TREASURY_WALLET = vm.envAddress("TREASURY_WALLET"); // Update as needed
    address KTTY_TOKEN = vm.envAddress("KTTY_TOKEN"); // Update with actual KTTY token
    uint256 constant MAX_MINT_PER_TX = 10;
    
    // Payment configuration for round 1 - 4
    uint256 NATIVE_ONLY_PRICE_1 = 0.001 ether;
    uint256 HYBRID_NATIVE_PRICE_1 = 0.001 ether;
    uint256 HYBRID_KTTY_PRICE_1 = 1 * 10**18; // 100 KTTY tokens
    uint256 NATIVE_ONLY_PRICE_2 = 0.001 ether;
    uint256 HYBRID_NATIVE_PRICE_2 = 0.001 ether;
    uint256 HYBRID_KTTY_PRICE_2 = 1 * 10**18; // 100 KTTY tokens
    uint256 NATIVE_ONLY_PRICE_3 = 0.001 ether;
    uint256 HYBRID_NATIVE_PRICE_3 = 0.001 ether;
    uint256 HYBRID_KTTY_PRICE_3 = 1 * 10**18; // 100 KTTY tokens
    uint256 NATIVE_ONLY_PRICE_4 = 0.001 ether;
    uint256 HYBRID_NATIVE_PRICE_4 = 0.001 ether;
    uint256 HYBRID_KTTY_PRICE_4 = 1 * 10**18; // 100 KTTY tokens
    
    // Round timing configuration (timestamps - UPDATE AS NEEDED)
    uint256 constant ROUND1_START = 1758672000; // Sep 24, 2025 00:00:00 UTC
    uint256 constant ROUND1_END = 1758844800;   // Sep 26, 2025 00:00:00 UTC

    uint256 constant ROUND2_START = 1758844800; // Sep 26, 2025 00:00:00 UTC
    uint256 constant ROUND2_END = 1759017600;   // Sep 28, 2025 00:00:00 UTC

    uint256 constant ROUND3_START = 1759017600; // Sep 28, 2025 00:00:00 UTC
    uint256 constant ROUND3_END = 1759190400;   // Sep 30, 2025 00:00:00 UTC

    uint256 constant ROUND4_START = 1759190400; // Sep 30, 2025 00:00:00 UTC
    uint256 constant ROUND4_END = 1759363200;   // Oct 2, 2025 00:00:00 UTC

    // Tool and collectible quantities for test environment
    uint256 constant TOOLS_PER_TYPE = 300;
    uint256 constant GOLDEN_TICKET_SUPPLY = 100;
    
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
        require(BOOKS_ADDRESS != address(0), "BOOKS_ADDRESS not set");
        
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
        console.log("  Books:", BOOKS_ADDRESS);
        
        vm.startBroadcast(deployerPrivateKey);
        
        DeploymentResult memory result = deployMintingContract(deployer);
        
        vm.stopBroadcast();
        
        // Print deployment results
        // printDeploymentResults(result);
    }
    
    function deployMintingContract(address owner) internal returns (DeploymentResult memory result) {
        // Get NFT contract instances
        KttyWorldCompanions companions = KttyWorldCompanions(COMPANIONS_ADDRESS);
        KttyWorldTools tools = KttyWorldTools(TOOLS_ADDRESS);
        KttyWorldCollectibles collectibles = KttyWorldCollectibles(COLLECTIBLES_ADDRESS);
        KttyWorldBooks books = KttyWorldBooks(BOOKS_ADDRESS);
        
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
                BOOKS_ADDRESS,
                KTTY_TOKEN,
                TREASURY_WALLET,
                MAX_MINT_PER_TX
            )
        );
        
        ERC1967Proxy mintingProxy = new ERC1967Proxy(address(mintingImpl), mintingInitData);
        console.log("Minting Proxy:", address(mintingProxy));
        
        // Set minting contract address on books contract
        books.setMintingContract(address(mintingProxy));
        companions.setMintingContract(address(mintingProxy));
        console.log("Books and Companions minting contract set to:", address(mintingProxy));
        
        KttyWorldMinting minting = KttyWorldMinting(address(mintingProxy));
        
        // Configure payment options for rounds 1-4
        console.log("\n--- Configuring Payment Options ---");
        minting.configurePayment(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, NATIVE_ONLY_PRICE_1, 0);
        minting.configurePayment(1, KttyWorldMinting.PaymentType.HYBRID, HYBRID_NATIVE_PRICE_1, HYBRID_KTTY_PRICE_1);
        minting.configurePayment(2, KttyWorldMinting.PaymentType.NATIVE_ONLY, NATIVE_ONLY_PRICE_2, 0);
        minting.configurePayment(2, KttyWorldMinting.PaymentType.HYBRID, HYBRID_NATIVE_PRICE_2, HYBRID_KTTY_PRICE_2);
        minting.configurePayment(3, KttyWorldMinting.PaymentType.NATIVE_ONLY, NATIVE_ONLY_PRICE_3, 0);
        minting.configurePayment(3, KttyWorldMinting.PaymentType.HYBRID, HYBRID_NATIVE_PRICE_3, HYBRID_KTTY_PRICE_3);
        minting.configurePayment(4, KttyWorldMinting.PaymentType.NATIVE_ONLY, NATIVE_ONLY_PRICE_4, 0);
        minting.configurePayment(4, KttyWorldMinting.PaymentType.HYBRID, HYBRID_NATIVE_PRICE_4, HYBRID_KTTY_PRICE_4);
        console.log("Payment options configured for rounds 1-4");
        
        // Configure rounds
        console.log("\n--- Configuring Rounds ---");
        minting.configureRound(1, ROUND1_START, ROUND1_END);
        minting.configureRound(2, ROUND2_START, ROUND2_END);
        minting.configureRound(3, ROUND3_START, ROUND3_END);
        minting.configureRound(4, ROUND4_START, ROUND4_END);

        // Mint all NFTs to minting contract
        console.log("\n--- Minting All NFTs to Minting Contract ---");
        
        // Mint all companions
        console.log("Minting companions...");
        uint256 companionSupply = companions.totalSupply();
        uint256 maxCompanions = companions.maxSupply();
        uint256 mintBatchSize = 100;
        console.log("Current companion supply:", companionSupply, "/", maxCompanions);
        while (companionSupply < maxCompanions) {
            companions.mintAll(address(minting), mintBatchSize);
            companionSupply = companions.totalSupply();
        }
        console.log("New Companion supply:", companionSupply, "/", maxCompanions);
        
        // Mint tools to minting contract
        console.log("Minting tools...");
        uint256[] memory toolIds = new uint256[](15);
        uint256[] memory toolAmounts = new uint256[](15);
        for (uint256 i = 0; i < 15; i++) {
            toolIds[i] = i + 1;
            toolAmounts[i] = TOOLS_PER_TYPE;
        }
        tools.batchMint(address(minting), toolIds, toolAmounts);
        
        // Mint golden tickets
        console.log("Minting golden tickets...");
        uint256[] memory collectibleIds = new uint256[](1);
        uint256[] memory collectibleAmounts = new uint256[](1);
        collectibleIds[0] = 1; // Golden ticket token ID
        collectibleAmounts[0] = GOLDEN_TICKET_SUPPLY;
        collectibles.batchMint(address(minting), collectibleIds, collectibleAmounts);
        
        // Final validation
        console.log("\n--- Final Validation ---");

        return DeploymentResult({
            mintingImpl: address(mintingImpl),
            mintingProxy: address(mintingProxy),
            companionsMinted: 0,
            toolsMinted: 0,
            collectiblesMinted: 0
        });
    }
    
    function printDeploymentResults(DeploymentResult memory result) internal view {
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
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {KttyWorldCompanions} from "../src/KttyWorldCompanions.sol";
import {KttyWorldTools} from "../src/KttyWorldTools.sol";
import {KttyWorldCollectibles} from "../src/KttyWorldCollectibles.sol";

contract DeployNFTs is Script {
    // Configuration constants
    uint256 constant COMPANION_SUPPLY = 60; // Test environment
    string constant HIDDEN_URI = "https://hidden.example.com/hidden.json";
    string constant BASE_URI_COMPANIONS = "https://metadata.kttyworld.com/companions/";
    string constant BASE_URI_TOOLS = "https://metadata.kttyworld.com/tools/";
    string constant BASE_URI_COLLECTIBLES = "https://metadata.kttyworld.com/collectibles/";
    
    // Tool configuration
    uint256 constant TOOLS_PER_TYPE = 60;
    string[5] TOOL_URIS = [
        "https://metadata.kttyworld.com/tools/1.json", // Anvil
        "https://metadata.kttyworld.com/tools/2.json", // Hammer
        "https://metadata.kttyworld.com/tools/3.json", // Tong
        "https://metadata.kttyworld.com/tools/4.json", // Bellow
        "https://metadata.kttyworld.com/tools/5.json"  // Eternal Flame
    ];
    
    // Golden ticket configuration
    uint256 constant GOLDEN_TICKET_SUPPLY = 16;
    string constant GOLDEN_TICKET_URI = "https://metadata.kttyworld.com/collectibles/1.json";
    
    // Deployment results
    struct DeploymentResult {
        address companionsImpl;
        address companionsProxy;
        address toolsImpl;
        address toolsProxy;
        address collectiblesImpl;
        address collectiblesProxy;
        uint256[] toolTokenIds;
        uint256 goldenTicketTokenId;
    }

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== KTTY World NFTs Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        DeploymentResult memory result = deployAllNFTs(deployer);
        
        vm.stopBroadcast();
        
        // Print deployment results
        printDeploymentResults(result);
    }
    
    function deployAllNFTs(address owner) internal returns (DeploymentResult memory result) {
        console.log("\n--- Deploying Companions Contract ---");
        
        // Deploy Companions
        KttyWorldCompanions companionsImpl = new KttyWorldCompanions();
        console.log("Companions Implementation:", address(companionsImpl));
        
        bytes memory companionsInitData = abi.encodeCall(
            KttyWorldCompanions.initialize,
            (owner, "KTTY World Companions", "KWC", HIDDEN_URI, COMPANION_SUPPLY)
        );
        
        ERC1967Proxy companionsProxy = new ERC1967Proxy(address(companionsImpl), companionsInitData);
        console.log("Companions Proxy:", address(companionsProxy));
        
        KttyWorldCompanions companions = KttyWorldCompanions(address(companionsProxy));
        
        // Set base URI for companions
        companions.setBaseTokenUri(BASE_URI_COMPANIONS);
        console.log("Companions base URI set:", BASE_URI_COMPANIONS);
        
        console.log("\n--- Deploying Tools Contract ---");
        
        // Deploy Tools
        KttyWorldTools toolsImpl = new KttyWorldTools();
        console.log("Tools Implementation:", address(toolsImpl));
        
        bytes memory toolsInitData = abi.encodeCall(
            KttyWorldTools.initialize,
            (owner, HIDDEN_URI)
        );
        
        ERC1967Proxy toolsProxy = new ERC1967Proxy(address(toolsImpl), toolsInitData);
        console.log("Tools Proxy:", address(toolsProxy));
        
        KttyWorldTools tools = KttyWorldTools(address(toolsProxy));
        
        // Set base URI for tools
        tools.setBaseTokenUri(BASE_URI_TOOLS);
        console.log("Tools base URI set:", BASE_URI_TOOLS);
        
        // Add tool token types
        uint256[] memory toolTokenIds = new uint256[](5);
        string[5] memory toolNames = ["Anvil", "Hammer", "Tong", "Bellow", "Eternal Flame"];
        
        console.log("\n--- Adding Tool Token Types ---");
        for (uint256 i = 0; i < 5; i++) {
            uint256 tokenId = tools.addTokenType(TOOL_URIS[i]);
            toolTokenIds[i] = tokenId;
            console.log("Added tool token type:", toolNames[i], "ID:", tokenId);
        }
        
        console.log("\n--- Deploying Collectibles Contract ---");
        
        // Deploy Collectibles
        KttyWorldCollectibles collectiblesImpl = new KttyWorldCollectibles();
        console.log("Collectibles Implementation:", address(collectiblesImpl));
        
        bytes memory collectiblesInitData = abi.encodeCall(
            KttyWorldCollectibles.initialize,
            (owner, HIDDEN_URI)
        );
        
        ERC1967Proxy collectiblesProxy = new ERC1967Proxy(address(collectiblesImpl), collectiblesInitData);
        console.log("Collectibles Proxy:", address(collectiblesProxy));
        
        KttyWorldCollectibles collectibles = KttyWorldCollectibles(address(collectiblesProxy));
        
        // Set base URI for collectibles
        collectibles.setBaseTokenUri(BASE_URI_COLLECTIBLES);
        console.log("Collectibles base URI set:", BASE_URI_COLLECTIBLES);
        
        // Add golden ticket collectible type
        console.log("\n--- Adding Golden Ticket Collectible Type ---");
        uint256 goldenTicketTokenId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        console.log("Added Golden Ticket token type ID:", goldenTicketTokenId, "URI:", GOLDEN_TICKET_URI);
        
        // Validate deployments
        console.log("\n--- Validation ---");
        require(companions.maxSupply() == COMPANION_SUPPLY, "Invalid companion max supply");
        require(tools.getNextTokenId() == 6, "Invalid next tool token ID"); // Should be 6 (next after 1-5)
        require(collectibles.getNextTokenId() == 2, "Invalid next collectible token ID"); // Should be 2 (next after 1)
        console.log("All validations passed");
        
        return DeploymentResult({
            companionsImpl: address(companionsImpl),
            companionsProxy: address(companionsProxy),
            toolsImpl: address(toolsImpl),
            toolsProxy: address(toolsProxy),
            collectiblesImpl: address(collectiblesImpl),
            collectiblesProxy: address(collectiblesProxy),
            toolTokenIds: toolTokenIds,
            goldenTicketTokenId: goldenTicketTokenId
        });
    }
    
    function printDeploymentResults(DeploymentResult memory result) internal pure {
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("\n--- Contract Addresses ---");
        console.log("Companions Implementation:", result.companionsImpl);
        console.log("Companions Proxy:", result.companionsProxy);
        console.log("Tools Implementation:", result.toolsImpl);
        console.log("Tools Proxy:", result.toolsProxy);
        console.log("Collectibles Implementation:", result.collectiblesImpl);
        console.log("Collectibles Proxy:", result.collectiblesProxy);
        
        console.log("\n--- Token IDs ---");
        console.log("Tool Token IDs:");
        string[5] memory toolNames = ["Anvil", "Hammer", "Tong", "Bellow", "Eternal Flame"];
        for (uint256 i = 0; i < result.toolTokenIds.length; i++) {
            console.log("  ", toolNames[i], "ID:", result.toolTokenIds[i]);
        }
        console.log("Golden Ticket Token ID:", result.goldenTicketTokenId);
        
        console.log("\n--- Configuration ---");
        console.log("Companion Max Supply:", COMPANION_SUPPLY);
        console.log("Tools Per Type:", TOOLS_PER_TYPE);
        console.log("Golden Ticket Supply:", GOLDEN_TICKET_SUPPLY);
        
        console.log("\n--- Next Steps ---");
        console.log("1. Use these addresses in DeployMinting.s.sol:");
        console.log("   COMPANIONS_ADDRESS =", result.companionsProxy);
        console.log("   TOOLS_ADDRESS =", result.toolsProxy);
        console.log("   COLLECTIBLES_ADDRESS =", result.collectiblesProxy);
        console.log("2. Run DeployMinting.s.sol to deploy minting contract and mint all tokens");
        
        console.log("\n=== DEPLOYMENT SUCCESS ===");
    }
}
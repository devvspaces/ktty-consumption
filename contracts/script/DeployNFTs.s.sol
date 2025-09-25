// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DummyCompanions} from "../src/KttyWorldCompanions.sol";
import {DummyBooks} from "../src/KttyWorldBooks.sol";
import {DummyTools} from "../src/KttyWorldTools.sol";
import {DummyCollectibles} from "../src/KttyWorldCollectibles.sol";

contract DeployNFTs is Script {
    // Configuration constants
    uint256 constant COMPANION_SUPPLY = 100; // Max supply for companions
    uint256 constant BOOKS_SUPPLY = 100; // Max supply for books
    string constant HIDDEN_URI = "https://indigo-neat-flyingfish-41.mypinata.cloud/ipfs/bafybeibkiqzjz6iiuxxqaurbnb3ouspmgg55rzbxjvvhbp2lk2tqajrasa/tools/2.json";
    string constant BASE_URI_COMPANIONS = "https://black-reasonable-ocelot-529.mypinata.cloud/ipfs/bafybeiflwlojpcexy7gw6oebwee4446k7w6fvh3ysymlxisww6bgq32te4/";
    string constant BASE_URI_BOOKS = "https://black-reasonable-ocelot-529.mypinata.cloud/ipfs/bafybeihyvdjafbutsmslfex4bu3ss7tynbwxub7fr2p2tpmptbyugtccf4/";
    string constant BASE_URI_TOOLS = "https://black-reasonable-ocelot-529.mypinata.cloud/ipfs/bafybeibpnxv2jfbjvvwyyeasopoxuyvee6msi4ywg73o6m2nmwax5qtaum/";
    string constant BASE_URI_COLLECTIBLES = "https://black-reasonable-ocelot-529.mypinata.cloud/ipfs/bafybeia46jm6vblurem5ddvtng6whyywoj3ar2bbpejfg5vrusafseapq4/";
    
    // Tool configuration - Now supports 15 tools
    uint256 constant TOOLS_PER_TYPE = 300;
    uint256 constant TOTAL_TOOL_TYPES = 15;
    
    // Golden ticket configuration
    uint256 constant GOLDEN_TICKET_SUPPLY = 100;
    string constant GOLDEN_TICKET_URI = "https://black-reasonable-ocelot-529.mypinata.cloud/ipfs/bafybeia46jm6vblurem5ddvtng6whyywoj3ar2bbpejfg5vrusafseapq4/1.json";

    // Deployment results
    struct DeploymentResult {
        address companionsImpl;
        address companionsProxy;
        address booksImpl;
        address booksProxy;
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
        string memory COMPANION_NAME = "Dummy Companions";
        string memory BOOK_NAME = "Dummy Books";

        console.log("\n--- Deploying Companions Contract ---");
        
        // Deploy Companions
        DummyCompanions companionsImpl = new DummyCompanions();
        console.log("Companions Implementation:", address(companionsImpl));
        
        bytes memory companionsInitData = abi.encodeCall(
            DummyCompanions.initialize,
            (owner, COMPANION_NAME, "KWC", HIDDEN_URI, COMPANION_SUPPLY)
        );
        
        ERC1967Proxy companionsProxy = new ERC1967Proxy(address(companionsImpl), companionsInitData);
        console.log("Companions Proxy:", address(companionsProxy));
        
        DummyCompanions companions = DummyCompanions(address(companionsProxy));
        
        // Set base URI for companions
        companions.setBaseTokenUri(BASE_URI_COMPANIONS);
        console.log("Companions base URI set:", BASE_URI_COMPANIONS);
        
        console.log("\n--- Deploying Books Contract ---");
        
        // Deploy Books
        DummyBooks booksImpl = new DummyBooks();
        console.log("Books Implementation:", address(booksImpl));
        
        bytes memory booksInitData = abi.encodeCall(
            DummyBooks.initialize,
            (owner, BOOK_NAME, "KWB", BOOKS_SUPPLY, HIDDEN_URI, address(0))
        );
        
        ERC1967Proxy booksProxy = new ERC1967Proxy(address(booksImpl), booksInitData);
        console.log("Books Proxy:", address(booksProxy));
        
        DummyBooks books = DummyBooks(address(booksProxy));
        
        // Set base URI for books
        books.setBaseTokenURI(BASE_URI_BOOKS);
        console.log("Books base URI set:", BASE_URI_BOOKS);
        
        console.log("\n--- Deploying Tools Contract ---");
        
        // Deploy Tools
        DummyTools toolsImpl = new DummyTools();
        console.log("Tools Implementation:", address(toolsImpl));
        
        bytes memory toolsInitData = abi.encodeCall(
            DummyTools.initialize,
            (owner, HIDDEN_URI)
        );
        
        ERC1967Proxy toolsProxy = new ERC1967Proxy(address(toolsImpl), toolsInitData);
        console.log("Tools Proxy:", address(toolsProxy));
        
        DummyTools tools = DummyTools(address(toolsProxy));
        
        // Set base URI for tools
        tools.setBaseTokenUri(BASE_URI_TOOLS);
        console.log("Tools base URI set:", BASE_URI_TOOLS);
        
        // Add tool token types
        uint256[] memory toolTokenIds = new uint256[](TOTAL_TOOL_TYPES);
        
        console.log("\n--- Adding Tool Token Types ---");
        for (uint256 i = 0; i < TOTAL_TOOL_TYPES; i++) {
            // Use base URI + token ID + .json pattern
            string memory tokenURI = string(abi.encodePacked(BASE_URI_TOOLS, vm.toString(i + 1), ".json"));
            uint256 tokenId = tools.addTokenType(tokenURI);
            toolTokenIds[i] = tokenId;
        }
        
        console.log("\n--- Deploying Collectibles Contract ---");
        
        // Deploy Collectibles
        DummyCollectibles collectiblesImpl = new DummyCollectibles();
        console.log("Collectibles Implementation:", address(collectiblesImpl));
        
        bytes memory collectiblesInitData = abi.encodeCall(
            DummyCollectibles.initialize,
            (owner, HIDDEN_URI)
        );
        
        ERC1967Proxy collectiblesProxy = new ERC1967Proxy(address(collectiblesImpl), collectiblesInitData);
        console.log("Collectibles Proxy:", address(collectiblesProxy));
        
        DummyCollectibles collectibles = DummyCollectibles(address(collectiblesProxy));
        
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
        require(books.maxSupply() == BOOKS_SUPPLY, "Invalid books max supply");
        require(tools.getNextTokenId() == TOTAL_TOOL_TYPES + 1, "Invalid next tool token ID");
        require(collectibles.getNextTokenId() == 2, "Invalid next collectible token ID"); // Should be 2 (next after 1)
        console.log("All validations passed");
        
        return DeploymentResult({
            companionsImpl: address(companionsImpl),
            companionsProxy: address(companionsProxy),
            booksImpl: address(booksImpl),
            booksProxy: address(booksProxy),
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
        console.log("Books Implementation:", result.booksImpl);
        console.log("Books Proxy:", result.booksProxy);
        console.log("Tools Implementation:", result.toolsImpl);
        console.log("Tools Proxy:", result.toolsProxy);
        console.log("Collectibles Implementation:", result.collectiblesImpl);
        console.log("Collectibles Proxy:", result.collectiblesProxy);
        
        console.log("\n--- Configuration ---");
        console.log("Companion Max Supply:", COMPANION_SUPPLY);
        console.log("Books Max Supply:", BOOKS_SUPPLY);
        console.log("Total Tool Types:", TOTAL_TOOL_TYPES);
        console.log("Tools Per Type:", TOOLS_PER_TYPE);
        console.log("Golden Ticket Supply:", GOLDEN_TICKET_SUPPLY);
        
        console.log("\n--- Next Steps ---");
        console.log("1. Use these addresses in DeployMinting.s.sol:");
        console.log("   COMPANIONS_ADDRESS =", result.companionsProxy);
        console.log("   BOOKS_ADDRESS =", result.booksProxy);
        console.log("   TOOLS_ADDRESS =", result.toolsProxy);
        console.log("   COLLECTIBLES_ADDRESS =", result.collectiblesProxy);
        console.log("2. Run DeployMinting.s.sol to deploy minting contract and mint all tokens");
        
        console.log("\n=== DEPLOYMENT SUCCESS ===");
    }
}
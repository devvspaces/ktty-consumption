// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DummyCollectibles} from "src/KttyWorldCollectibles.sol";

contract KttyWorldCollectiblesTest is Test {
    DummyCollectibles public collectibles;
    
    address public owner;
    address public mintContract;
    address public user;
    
    string constant HIDDEN_URI = "https://hidden.example.com/collectibles.json";
    string constant BASE_URI = "https://revealed.example.com/collectibles/";
    string constant GOLDEN_TICKET_URI = "https://api.example.com/golden-ticket.json";
    string constant RARE_COLLECTIBLE_URI = "https://api.example.com/rare-collectible.json";
    string constant SPECIAL_COLLECTIBLE_URI = "https://api.example.com/special-collectible.json";
    
    event Revealed(bool revealed);
    event HiddenMetadataUriUpdated(string hiddenMetadataUri);
    event BaseTokenUriUpdated(string baseTokenUri);
    event CollectibleTypeAdded(uint256 indexed tokenId, string tokenUri);
    event TokenUriUpdated(uint256 indexed tokenId, string tokenUri);
    event BatchMinted(uint256[] tokenIds, uint256[] amounts, address indexed to);

    function setUp() public {
        owner = makeAddr("owner");
        mintContract = makeAddr("mintContract");
        user = makeAddr("user");
        
        // Deploy implementation
        DummyCollectibles implementation = new DummyCollectibles();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            DummyCollectibles.initialize,
            (owner, HIDDEN_URI)
        );
        
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Cast proxy to interface
        collectibles = DummyCollectibles(address(proxy));
    }

    function test_Initialize() public view {
        assertEq(collectibles.owner(), owner);
        assertFalse(collectibles.isRevealed());
        assertEq(collectibles.hiddenMetadataUri(), HIDDEN_URI);
        assertEq(collectibles.getNextTokenId(), 1);
    }

    function test_AddCollectibleType() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit CollectibleTypeAdded(1, GOLDEN_TICKET_URI);
        
        uint256 tokenId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        
        assertEq(tokenId, 1);
        assertTrue(collectibles.exists(1));
        assertEq(collectibles.getTokenUri(1), GOLDEN_TICKET_URI);
        assertEq(collectibles.getNextTokenId(), 2);
        
        vm.stopPrank();
    }

    function test_AddMultipleCollectibleTypes() public {
        vm.startPrank(owner);
        
        uint256 goldenTicketId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        uint256 rareCollectibleId = collectibles.addCollectibleType(RARE_COLLECTIBLE_URI);
        uint256 specialCollectibleId = collectibles.addCollectibleType(SPECIAL_COLLECTIBLE_URI);
        
        assertEq(goldenTicketId, 1);
        assertEq(rareCollectibleId, 2);
        assertEq(specialCollectibleId, 3);
        
        assertTrue(collectibles.exists(1));
        assertTrue(collectibles.exists(2));
        assertTrue(collectibles.exists(3));
        assertFalse(collectibles.exists(4));
        
        assertEq(collectibles.getTokenUri(1), GOLDEN_TICKET_URI);
        assertEq(collectibles.getTokenUri(2), RARE_COLLECTIBLE_URI);
        assertEq(collectibles.getTokenUri(3), SPECIAL_COLLECTIBLE_URI);
        
        vm.stopPrank();
    }

    function test_RevertWhen_AddCollectibleTypeNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert();
        collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        
        vm.stopPrank();
    }

    function test_Mint() public {
        vm.startPrank(owner);
        
        uint256 tokenId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        collectibles.mint(mintContract, tokenId, 500);
        
        assertEq(collectibles.balanceOf(mintContract, tokenId), 500);
        assertEq(collectibles.totalSupply(tokenId), 500);
        
        vm.stopPrank();
    }

    function test_BatchMint() public {
        vm.startPrank(owner);
        
        // Add collectible types
        uint256 goldenTicketId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        uint256 rareCollectibleId = collectibles.addCollectibleType(RARE_COLLECTIBLE_URI);
        uint256 specialCollectibleId = collectibles.addCollectibleType(SPECIAL_COLLECTIBLE_URI);
        
        uint256[] memory tokenIds = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        
        tokenIds[0] = goldenTicketId;
        tokenIds[1] = rareCollectibleId;
        tokenIds[2] = specialCollectibleId;
        amounts[0] = 500;
        amounts[1] = 100;
        amounts[2] = 50;
        
        vm.expectEmit(true, true, true, true);
        emit BatchMinted(tokenIds, amounts, mintContract);
        
        collectibles.batchMint(mintContract, tokenIds, amounts);
        
        assertEq(collectibles.balanceOf(mintContract, goldenTicketId), 500);
        assertEq(collectibles.balanceOf(mintContract, rareCollectibleId), 100);
        assertEq(collectibles.balanceOf(mintContract, specialCollectibleId), 50);
        
        assertEq(collectibles.totalSupply(goldenTicketId), 500);
        assertEq(collectibles.totalSupply(rareCollectibleId), 100);
        assertEq(collectibles.totalSupply(specialCollectibleId), 50);
        
        vm.stopPrank();
    }

    function test_RevertWhen_BatchMintArrayLengthMismatch() public {
        vm.startPrank(owner);
        
        uint256 tokenId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](2);
        
        tokenIds[0] = tokenId;
        amounts[0] = 100;
        amounts[1] = 200;
        
        vm.expectRevert(DummyCollectibles.ArrayLengthMismatch.selector);
        collectibles.batchMint(mintContract, tokenIds, amounts);
        
        vm.stopPrank();
    }

    function test_RevertWhen_BatchMintTokenNotExists() public {
        vm.startPrank(owner);
        
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        
        tokenIds[0] = 999; // Non-existent token
        amounts[0] = 100;
        
        vm.expectRevert(DummyCollectibles.TokenNotExists.selector);
        collectibles.batchMint(mintContract, tokenIds, amounts);
        
        vm.stopPrank();
    }

    function test_RevertWhen_BatchMintZeroQuantity() public {
        vm.startPrank(owner);
        
        uint256 tokenId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        
        tokenIds[0] = tokenId;
        amounts[0] = 0;
        
        vm.expectRevert(DummyCollectibles.ZeroQuantity.selector);
        collectibles.batchMint(mintContract, tokenIds, amounts);
        
        vm.stopPrank();
    }

    function test_RevertWhen_MintNotOwner() public {
        vm.startPrank(owner);
        uint256 tokenId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        vm.stopPrank();
        
        vm.startPrank(user);
        
        vm.expectRevert();
        collectibles.mint(mintContract, tokenId, 100);
        
        vm.stopPrank();
    }

    function test_SetRevealed() public {
        vm.startPrank(owner);
        
        assertFalse(collectibles.isRevealed());
        
        vm.expectEmit(true, true, true, true);
        emit Revealed(true);
        
        collectibles.setRevealed(true);
        assertTrue(collectibles.isRevealed());
        
        collectibles.setRevealed(false);
        assertFalse(collectibles.isRevealed());
        
        vm.stopPrank();
    }

    function test_RevertWhen_SetRevealedNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert();
        collectibles.setRevealed(true);
        
        vm.stopPrank();
    }

    function test_SetHiddenMetadataUri() public {
        vm.startPrank(owner);
        
        string memory newHiddenUri = "https://new-hidden.example.com/collectibles.json";
        
        vm.expectEmit(true, true, true, true);
        emit HiddenMetadataUriUpdated(newHiddenUri);
        
        collectibles.setHiddenMetadataUri(newHiddenUri);
        assertEq(collectibles.hiddenMetadataUri(), newHiddenUri);
        
        vm.stopPrank();
    }

    function test_SetBaseTokenUri() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit BaseTokenUriUpdated(BASE_URI);
        
        collectibles.setBaseTokenUri(BASE_URI);
        assertEq(collectibles.baseTokenUri(), BASE_URI);
        
        vm.stopPrank();
    }

    function test_SetTokenUri() public {
        vm.startPrank(owner);
        
        uint256 tokenId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        string memory newUri = "https://updated.example.com/golden-ticket.json";
        
        vm.expectEmit(true, true, true, true);
        emit TokenUriUpdated(tokenId, newUri);
        
        collectibles.setTokenUri(tokenId, newUri);
        assertEq(collectibles.getTokenUri(tokenId), newUri);
        
        vm.stopPrank();
    }

    function test_RevertWhen_SetTokenUriNotExists() public {
        vm.startPrank(owner);
        
        vm.expectRevert(DummyCollectibles.TokenNotExists.selector);
        collectibles.setTokenUri(999, "new-uri");
        
        vm.stopPrank();
    }

    function test_URI_Hidden() public {
        vm.startPrank(owner);
        
        uint256 tokenId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        
        string memory uri = collectibles.uri(tokenId);
        assertEq(uri, HIDDEN_URI);
        
        vm.stopPrank();
    }

    function test_URI_RevealedWithSpecificURI() public {
        vm.startPrank(owner);
        
        uint256 tokenId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        collectibles.setRevealed(true);
        
        string memory uri = collectibles.uri(tokenId);
        assertEq(uri, GOLDEN_TICKET_URI);
        
        vm.stopPrank();
    }

    function test_URI_RevealedWithBaseURI() public {
        vm.startPrank(owner);
        
        uint256 tokenId = collectibles.addCollectibleType(""); // Empty specific URI
        collectibles.setBaseTokenUri(BASE_URI);
        collectibles.setRevealed(true);
        
        string memory uri = collectibles.uri(tokenId);
        assertEq(uri, string(abi.encodePacked(BASE_URI, "1.json")));
        
        vm.stopPrank();
    }

    function test_RevertWhen_URITokenNotExists() public {
        vm.expectRevert(DummyCollectibles.TokenNotExists.selector);
        collectibles.uri(999);
    }

    function test_GoldenTicketsScenario() public {
        vm.startPrank(owner);
        
        // Add Golden Tickets as the first collectible type
        uint256 goldenTicketId = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        
        // Mint 500 Golden Tickets (as mentioned in original requirements)
        collectibles.mint(mintContract, goldenTicketId, 500);
        
        // Verify
        assertEq(goldenTicketId, 1);
        assertEq(collectibles.balanceOf(mintContract, goldenTicketId), 500);
        assertEq(collectibles.totalSupply(goldenTicketId), 500);
        
        // Add more collectible types for the future
        uint256 rareCollectibleId = collectibles.addCollectibleType(RARE_COLLECTIBLE_URI);
        uint256 specialCollectibleId = collectibles.addCollectibleType(SPECIAL_COLLECTIBLE_URI);
        
        // Mint some of the new collectibles
        collectibles.mint(mintContract, rareCollectibleId, 100);
        collectibles.mint(mintContract, specialCollectibleId, 50);
        
        // Verify all types exist and have correct supplies
        assertEq(collectibles.totalSupply(goldenTicketId), 500);
        assertEq(collectibles.totalSupply(rareCollectibleId), 100);
        assertEq(collectibles.totalSupply(specialCollectibleId), 50);
        
        vm.stopPrank();
    }

    function testFuzz_AddCollectibleTypes(uint8 count) public {
        count = uint8(bound(count, 1, 50)); // Limit to reasonable number for gas
        
        vm.startPrank(owner);
        
        for (uint256 i = 0; i < count; i++) {
            string memory uri = string(abi.encodePacked("https://api.com/collectible", _toString(i), ".json"));
            uint256 tokenId = collectibles.addCollectibleType(uri);
            
            assertEq(tokenId, i + 1);
            assertTrue(collectibles.exists(tokenId));
            assertEq(collectibles.getTokenUri(tokenId), uri);
        }
        
        assertEq(collectibles.getNextTokenId(), count + 1);
        
        vm.stopPrank();
    }

    function testFuzz_BatchMint(uint96 amount1, uint96 amount2, uint96 amount3) public {
        amount1 = uint96(bound(amount1, 1, 1000000));
        amount2 = uint96(bound(amount2, 1, 1000000));
        amount3 = uint96(bound(amount3, 1, 1000000));
        
        vm.startPrank(owner);
        
        uint256 tokenId1 = collectibles.addCollectibleType(GOLDEN_TICKET_URI);
        uint256 tokenId2 = collectibles.addCollectibleType(RARE_COLLECTIBLE_URI);
        uint256 tokenId3 = collectibles.addCollectibleType(SPECIAL_COLLECTIBLE_URI);
        
        uint256[] memory tokenIds = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        tokenIds[2] = tokenId3;
        amounts[0] = amount1;
        amounts[1] = amount2;
        amounts[2] = amount3;
        
        collectibles.batchMint(mintContract, tokenIds, amounts);
        
        assertEq(collectibles.balanceOf(mintContract, tokenId1), amount1);
        assertEq(collectibles.balanceOf(mintContract, tokenId2), amount2);
        assertEq(collectibles.balanceOf(mintContract, tokenId3), amount3);
        
        assertEq(collectibles.totalSupply(tokenId1), amount1);
        assertEq(collectibles.totalSupply(tokenId2), amount2);
        assertEq(collectibles.totalSupply(tokenId3), amount3);
        
        vm.stopPrank();
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

contract KttyWorldCollectiblesInvariantTest is Test {
    DummyCollectibles public collectibles;
    KttyWorldCollectiblesHandler public handler;
    
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        
        // Deploy implementation
        DummyCollectibles implementation = new DummyCollectibles();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            DummyCollectibles.initialize,
            (owner, "https://hidden.com/")
        );
        
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Cast proxy to interface
        collectibles = DummyCollectibles(address(proxy));
        handler = new KttyWorldCollectiblesHandler(collectibles, owner);
        
        targetContract(address(handler));
    }

    function invariant_CollectibleTypesIncremental() public view {
        uint256 nextId = collectibles.getNextTokenId();
        
        // All token IDs from 1 to nextId-1 should exist
        for (uint256 i = 1; i < nextId; i++) {
            assertTrue(collectibles.exists(i));
        }
        
        // Token ID at nextId should not exist
        if (nextId > 1) {
            assertFalse(collectibles.exists(nextId));
        }
    }

    function invariant_TotalSupplyConsistent() public view {
        assertEq(handler.ghost_totalMinted(), handler.calculateActualTotalSupply());
    }
}

contract KttyWorldCollectiblesHandler is Test {
    DummyCollectibles public collectibles;
    address public owner;
    
    uint256 public ghost_totalMinted;
    address[] public actors;
    uint256[] public tokenIds;

    constructor(DummyCollectibles _collectibles, address _owner) {
        collectibles = _collectibles;
        owner = _owner;
        
        for (uint i = 0; i < 5; i++) {
            actors.push(makeAddr(string(abi.encode("actor", i))));
        }
    }

    function addCollectibleType(uint256 seed) external {
        vm.startPrank(owner);
        
        string memory uri = string(abi.encodePacked("https://api.com/collectible", _toString(seed), ".json"));
        uint256 tokenId = collectibles.addCollectibleType(uri);
        tokenIds.push(tokenId);
        
        vm.stopPrank();
    }

    function mintCollectibles(uint96 amount, uint256 actorSeed, uint256 tokenSeed) external {
        if (tokenIds.length == 0) return;
        
        amount = uint96(bound(amount, 1, 10000));
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 tokenId = tokenIds[bound(tokenSeed, 0, tokenIds.length - 1)];
        
        vm.startPrank(owner);
        
        collectibles.mint(actor, tokenId, amount);
        ghost_totalMinted += amount;
        
        vm.stopPrank();
    }

    function setRevealed(bool revealed) external {
        vm.startPrank(owner);
        collectibles.setRevealed(revealed);
        vm.stopPrank();
    }

    function calculateActualTotalSupply() external view returns (uint256 total) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            total += collectibles.totalSupply(tokenIds[i]);
        }
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
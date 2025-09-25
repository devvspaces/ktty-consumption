// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DummyTools} from "src/KttyWorldTools.sol";

contract KttyWorldToolsTest is Test {
    DummyTools public tools;
    
    address public owner;
    address public mintContract;
    address public user;
    
    string constant HIDDEN_URI = "https://hidden.example.com/tools.json";
    string constant BASE_URI = "https://revealed.example.com/tools/";
    string constant TOOL1_URI = "https://api.example.com/tool1.json";
    string constant TOOL2_URI = "https://api.example.com/tool2.json";
    string constant TOOL3_URI = "https://api.example.com/tool3.json";
    
    event Revealed(bool revealed);
    event HiddenMetadataUriUpdated(string hiddenMetadataUri);
    event BaseTokenUriUpdated(string baseTokenUri);
    event TokenTypeAdded(uint256 indexed tokenId, string tokenUri);
    event TokenUriUpdated(uint256 indexed tokenId, string tokenUri);
    event BatchMinted(uint256[] tokenIds, uint256[] amounts, address indexed to);

    function setUp() public {
        owner = makeAddr("owner");
        mintContract = makeAddr("mintContract");
        user = makeAddr("user");
        
        // Deploy implementation
        DummyTools implementation = new DummyTools();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            DummyTools.initialize,
            (owner, HIDDEN_URI)
        );
        
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Cast proxy to interface
        tools = DummyTools(address(proxy));
    }

    function test_Initialize() public view {
        assertEq(tools.owner(), owner);
        assertFalse(tools.isRevealed());
        assertEq(tools.hiddenMetadataUri(), HIDDEN_URI);
        assertEq(tools.getNextTokenId(), 1);
    }

    function test_AddTokenType() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit TokenTypeAdded(1, TOOL1_URI);
        
        uint256 tokenId = tools.addTokenType(TOOL1_URI);
        
        assertEq(tokenId, 1);
        assertTrue(tools.exists(1));
        assertEq(tools.getTokenUri(1), TOOL1_URI);
        assertEq(tools.getNextTokenId(), 2);
        
        vm.stopPrank();
    }

    function test_AddMultipleTokenTypes() public {
        vm.startPrank(owner);
        
        uint256 tokenId1 = tools.addTokenType(TOOL1_URI);
        uint256 tokenId2 = tools.addTokenType(TOOL2_URI);
        uint256 tokenId3 = tools.addTokenType(TOOL3_URI);
        
        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(tokenId3, 3);
        
        assertTrue(tools.exists(1));
        assertTrue(tools.exists(2));
        assertTrue(tools.exists(3));
        assertFalse(tools.exists(4));
        
        assertEq(tools.getTokenUri(1), TOOL1_URI);
        assertEq(tools.getTokenUri(2), TOOL2_URI);
        assertEq(tools.getTokenUri(3), TOOL3_URI);
        
        vm.stopPrank();
    }

    function test_RevertWhen_AddTokenTypeNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert();
        tools.addTokenType(TOOL1_URI);
        
        vm.stopPrank();
    }

    function test_Mint() public {
        vm.startPrank(owner);
        
        uint256 tokenId = tools.addTokenType(TOOL1_URI);
        tools.mint(mintContract, tokenId, 100);
        
        assertEq(tools.balanceOf(mintContract, tokenId), 100);
        assertEq(tools.totalSupply(tokenId), 100);
        
        vm.stopPrank();
    }

    function test_BatchMint() public {
        vm.startPrank(owner);
        
        // Add token types
        uint256 tokenId1 = tools.addTokenType(TOOL1_URI);
        uint256 tokenId2 = tools.addTokenType(TOOL2_URI);
        uint256 tokenId3 = tools.addTokenType(TOOL3_URI);
        
        uint256[] memory tokenIds = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        tokenIds[2] = tokenId3;
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;
        
        vm.expectEmit(true, true, true, true);
        emit BatchMinted(tokenIds, amounts, mintContract);
        
        tools.batchMint(mintContract, tokenIds, amounts);
        
        assertEq(tools.balanceOf(mintContract, tokenId1), 100);
        assertEq(tools.balanceOf(mintContract, tokenId2), 200);
        assertEq(tools.balanceOf(mintContract, tokenId3), 300);
        
        assertEq(tools.totalSupply(tokenId1), 100);
        assertEq(tools.totalSupply(tokenId2), 200);
        assertEq(tools.totalSupply(tokenId3), 300);
        
        vm.stopPrank();
    }

    function test_RevertWhen_BatchMintArrayLengthMismatch() public {
        vm.startPrank(owner);
        
        uint256 tokenId = tools.addTokenType(TOOL1_URI);
        
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](2);
        
        tokenIds[0] = tokenId;
        amounts[0] = 100;
        amounts[1] = 200;
        
        vm.expectRevert(DummyTools.ArrayLengthMismatch.selector);
        tools.batchMint(mintContract, tokenIds, amounts);
        
        vm.stopPrank();
    }

    function test_RevertWhen_BatchMintTokenNotExists() public {
        vm.startPrank(owner);
        
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        
        tokenIds[0] = 999; // Non-existent token
        amounts[0] = 100;
        
        vm.expectRevert(DummyTools.TokenNotExists.selector);
        tools.batchMint(mintContract, tokenIds, amounts);
        
        vm.stopPrank();
    }

    function test_RevertWhen_BatchMintZeroQuantity() public {
        vm.startPrank(owner);
        
        uint256 tokenId = tools.addTokenType(TOOL1_URI);
        
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        
        tokenIds[0] = tokenId;
        amounts[0] = 0;
        
        vm.expectRevert(DummyTools.ZeroQuantity.selector);
        tools.batchMint(mintContract, tokenIds, amounts);
        
        vm.stopPrank();
    }

    function test_RevertWhen_MintNotOwner() public {
        vm.startPrank(owner);
        uint256 tokenId = tools.addTokenType(TOOL1_URI);
        vm.stopPrank();
        
        vm.startPrank(user);
        
        vm.expectRevert();
        tools.mint(mintContract, tokenId, 100);
        
        vm.stopPrank();
    }

    function test_SetRevealed() public {
        vm.startPrank(owner);
        
        assertFalse(tools.isRevealed());
        
        vm.expectEmit(true, true, true, true);
        emit Revealed(true);
        
        tools.setRevealed(true);
        assertTrue(tools.isRevealed());
        
        tools.setRevealed(false);
        assertFalse(tools.isRevealed());
        
        vm.stopPrank();
    }

    function test_RevertWhen_SetRevealedNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert();
        tools.setRevealed(true);
        
        vm.stopPrank();
    }

    function test_SetHiddenMetadataUri() public {
        vm.startPrank(owner);
        
        string memory newHiddenUri = "https://new-hidden.example.com/tools.json";
        
        vm.expectEmit(true, true, true, true);
        emit HiddenMetadataUriUpdated(newHiddenUri);
        
        tools.setHiddenMetadataUri(newHiddenUri);
        assertEq(tools.hiddenMetadataUri(), newHiddenUri);
        
        vm.stopPrank();
    }

    function test_SetBaseTokenUri() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit BaseTokenUriUpdated(BASE_URI);
        
        tools.setBaseTokenUri(BASE_URI);
        assertEq(tools.baseTokenUri(), BASE_URI);
        
        vm.stopPrank();
    }

    function test_SetTokenUri() public {
        vm.startPrank(owner);
        
        uint256 tokenId = tools.addTokenType(TOOL1_URI);
        string memory newUri = "https://updated.example.com/tool1.json";
        
        vm.expectEmit(true, true, true, true);
        emit TokenUriUpdated(tokenId, newUri);
        
        tools.setTokenUri(tokenId, newUri);
        assertEq(tools.getTokenUri(tokenId), newUri);
        
        vm.stopPrank();
    }

    function test_RevertWhen_SetTokenUriNotExists() public {
        vm.startPrank(owner);
        
        vm.expectRevert(DummyTools.TokenNotExists.selector);
        tools.setTokenUri(999, "new-uri");
        
        vm.stopPrank();
    }

    function test_URI_Hidden() public {
        vm.startPrank(owner);
        
        uint256 tokenId = tools.addTokenType(TOOL1_URI);
        
        string memory uri = tools.uri(tokenId);
        assertEq(uri, HIDDEN_URI);
        
        vm.stopPrank();
    }

    function test_URI_RevealedWithSpecificURI() public {
        vm.startPrank(owner);
        
        uint256 tokenId = tools.addTokenType(TOOL1_URI);
        tools.setRevealed(true);
        
        string memory uri = tools.uri(tokenId);
        assertEq(uri, TOOL1_URI);
        
        vm.stopPrank();
    }

    function test_URI_RevealedWithBaseURI() public {
        vm.startPrank(owner);
        
        uint256 tokenId = tools.addTokenType(""); // Empty specific URI
        tools.setBaseTokenUri(BASE_URI);
        tools.setRevealed(true);
        
        string memory uri = tools.uri(tokenId);
        assertEq(uri, string(abi.encodePacked(BASE_URI, "1.json")));
        
        vm.stopPrank();
    }

    function test_RevertWhen_URITokenNotExists() public {
        vm.expectRevert(DummyTools.TokenNotExists.selector);
        tools.uri(999);
    }

    function testFuzz_AddTokenTypes(uint8 count) public {
        count = uint8(bound(count, 1, 50)); // Limit to reasonable number for gas
        
        vm.startPrank(owner);
        
        for (uint256 i = 0; i < count; i++) {
            string memory uri = string(abi.encodePacked("https://api.com/token", _toString(i), ".json"));
            uint256 tokenId = tools.addTokenType(uri);
            
            assertEq(tokenId, i + 1);
            assertTrue(tools.exists(tokenId));
            assertEq(tools.getTokenUri(tokenId), uri);
        }
        
        assertEq(tools.getNextTokenId(), count + 1);
        
        vm.stopPrank();
    }

    function testFuzz_BatchMint(uint96 amount1, uint96 amount2, uint96 amount3) public {
        amount1 = uint96(bound(amount1, 1, 1000000));
        amount2 = uint96(bound(amount2, 1, 1000000));
        amount3 = uint96(bound(amount3, 1, 1000000));
        
        vm.startPrank(owner);
        
        uint256 tokenId1 = tools.addTokenType(TOOL1_URI);
        uint256 tokenId2 = tools.addTokenType(TOOL2_URI);
        uint256 tokenId3 = tools.addTokenType(TOOL3_URI);
        
        uint256[] memory tokenIds = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        tokenIds[2] = tokenId3;
        amounts[0] = amount1;
        amounts[1] = amount2;
        amounts[2] = amount3;
        
        tools.batchMint(mintContract, tokenIds, amounts);
        
        assertEq(tools.balanceOf(mintContract, tokenId1), amount1);
        assertEq(tools.balanceOf(mintContract, tokenId2), amount2);
        assertEq(tools.balanceOf(mintContract, tokenId3), amount3);
        
        assertEq(tools.totalSupply(tokenId1), amount1);
        assertEq(tools.totalSupply(tokenId2), amount2);
        assertEq(tools.totalSupply(tokenId3), amount3);
        
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

contract KttyWorldToolsInvariantTest is Test {
    DummyTools public tools;
    KttyWorldToolsHandler public handler;
    
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        
        // Deploy implementation
        DummyTools implementation = new DummyTools();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            DummyTools.initialize,
            (owner, "https://hidden.com/")
        );
        
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Cast proxy to interface
        tools = DummyTools(address(proxy));
        handler = new KttyWorldToolsHandler(tools, owner);
        
        targetContract(address(handler));
    }

    function invariant_TokenTypesIncremental() public view {
        uint256 nextId = tools.getNextTokenId();
        
        // All token IDs from 1 to nextId-1 should exist
        for (uint256 i = 1; i < nextId; i++) {
            assertTrue(tools.exists(i));
        }
        
        // Token ID at nextId should not exist
        if (nextId > 1) {
            assertFalse(tools.exists(nextId));
        }
    }

    function invariant_TotalSupplyConsistent() public view {
        assertEq(handler.ghost_totalMinted(), handler.calculateActualTotalSupply());
    }
}

contract KttyWorldToolsHandler is Test {
    DummyTools public tools;
    address public owner;
    
    uint256 public ghost_totalMinted;
    address[] public actors;
    uint256[] public tokenIds;

    constructor(DummyTools _tools, address _owner) {
        tools = _tools;
        owner = _owner;
        
        for (uint i = 0; i < 5; i++) {
            actors.push(makeAddr(string(abi.encode("actor", i))));
        }
    }

    function addTokenType(uint256 seed) external {
        vm.startPrank(owner);
        
        string memory uri = string(abi.encodePacked("https://api.com/token", _toString(seed), ".json"));
        uint256 tokenId = tools.addTokenType(uri);
        tokenIds.push(tokenId);
        
        vm.stopPrank();
    }

    function mintTokens(uint96 amount, uint256 actorSeed, uint256 tokenSeed) external {
        if (tokenIds.length == 0) return;
        
        amount = uint96(bound(amount, 1, 10000));
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 tokenId = tokenIds[bound(tokenSeed, 0, tokenIds.length - 1)];
        
        vm.startPrank(owner);
        
        tools.mint(actor, tokenId, amount);
        ghost_totalMinted += amount;
        
        vm.stopPrank();
    }

    function setRevealed(bool revealed) external {
        vm.startPrank(owner);
        tools.setRevealed(revealed);
        vm.stopPrank();
    }

    function calculateActualTotalSupply() external view returns (uint256 total) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            total += tools.totalSupply(tokenIds[i]);
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
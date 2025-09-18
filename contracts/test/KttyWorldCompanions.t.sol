// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {KttyWorldCompanions} from "src/KttyWorldCompanions.sol";

contract KttyWorldCompanionsTest is Test {
    KttyWorldCompanions public companions;
    
    address public owner;
    address public mintContract;
    address public user;
    
    string constant NAME = "KTTY World Companions";
    string constant SYMBOL = "KWC";
    string constant HIDDEN_URI = "https://hidden.example.com/metadata.json";
    string constant BASE_URI = "https://revealed.example.com/metadata/";
    uint256 constant MAX_SUPPLY = 10000;
    
    event Revealed(bool revealed);
    event HiddenMetadataUriUpdated(string hiddenMetadataUri);
    event BaseTokenUriUpdated(string baseTokenUri);
    event BatchMinted(address indexed to, uint256 startTokenId, uint256 quantity);

    function setUp() public {
        owner = makeAddr("owner");
        mintContract = makeAddr("mintContract");
        user = makeAddr("user");
        
        // Deploy implementation
        KttyWorldCompanions implementation = new KttyWorldCompanions();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            KttyWorldCompanions.initialize,
            (owner, NAME, SYMBOL, HIDDEN_URI, MAX_SUPPLY)
        );
        
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Cast proxy to interface
        companions = KttyWorldCompanions(address(proxy));
    }

    function test_Initialize() public view {
        assertEq(companions.name(), NAME);
        assertEq(companions.symbol(), SYMBOL);
        assertEq(companions.owner(), owner);
        assertEq(companions.maxSupply(), MAX_SUPPLY);
        assertEq(companions.totalSupply(), 0);
        assertFalse(companions.isRevealed());
        assertEq(companions.hiddenMetadataUri(), HIDDEN_URI);
    }

    function test_BatchMint() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit BatchMinted(mintContract, 1, 100);
        
        companions.batchMint(mintContract, 100);
        
        assertEq(companions.totalSupply(), 100);
        assertEq(companions.balanceOf(mintContract), 100);
        assertEq(companions.ownerOf(1), mintContract);
        assertEq(companions.ownerOf(100), mintContract);
        assertTrue(companions.exists(1));
        assertTrue(companions.exists(100));
        assertFalse(companions.exists(101));
        
        vm.stopPrank();
    }

    function test_RevertWhen_BatchMintZeroQuantity() public {
        vm.startPrank(owner);
        
        vm.expectRevert(KttyWorldCompanions.BatchSizeZero.selector);
        companions.batchMint(mintContract, 0);
        
        vm.stopPrank();
    }

    function test_RevertWhen_BatchMintExceedsMaxSupply() public {
        vm.startPrank(owner);
        
        vm.expectRevert(KttyWorldCompanions.ExceedsMaxSupply.selector);
        companions.batchMint(mintContract, MAX_SUPPLY + 1);
        
        vm.stopPrank();
    }

    function test_RevertWhen_BatchMintNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert();
        companions.batchMint(mintContract, 100);
        
        vm.stopPrank();
    }

    function test_MintAll() public {
        vm.startPrank(owner);
        
        companions.mintAll(mintContract);
        
        assertEq(companions.totalSupply(), MAX_SUPPLY);
        assertEq(companions.balanceOf(mintContract), MAX_SUPPLY);
        assertTrue(companions.exists(1));
        assertTrue(companions.exists(MAX_SUPPLY));
        
        vm.stopPrank();
    }

    function test_RevertWhen_MintAllAlreadyMaxed() public {
        vm.startPrank(owner);
        
        companions.mintAll(mintContract);
        
        vm.expectRevert(KttyWorldCompanions.MaxSupplyReached.selector);
        companions.mintAll(mintContract);
        
        vm.stopPrank();
    }

    function test_SetRevealed() public {
        vm.startPrank(owner);
        
        assertFalse(companions.isRevealed());
        
        vm.expectEmit(true, true, true, true);
        emit Revealed(true);
        
        companions.setRevealed(true);
        assertTrue(companions.isRevealed());
        
        companions.setRevealed(false);
        assertFalse(companions.isRevealed());
        
        vm.stopPrank();
    }

    function test_RevertWhen_SetRevealedNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert();
        companions.setRevealed(true);
        
        vm.stopPrank();
    }

    function test_SetHiddenMetadataUri() public {
        vm.startPrank(owner);
        
        string memory newHiddenUri = "https://new-hidden.example.com/metadata.json";
        
        vm.expectEmit(true, true, true, true);
        emit HiddenMetadataUriUpdated(newHiddenUri);
        
        companions.setHiddenMetadataUri(newHiddenUri);
        assertEq(companions.hiddenMetadataUri(), newHiddenUri);
        
        vm.stopPrank();
    }

    function test_RevertWhen_SetHiddenMetadataUriNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert();
        companions.setHiddenMetadataUri("new-uri");
        
        vm.stopPrank();
    }

    function test_SetBaseTokenUri() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit BaseTokenUriUpdated(BASE_URI);
        
        companions.setBaseTokenUri(BASE_URI);
        assertEq(companions.baseTokenUri(), BASE_URI);
        
        vm.stopPrank();
    }

    function test_RevertWhen_SetBaseTokenUriNotOwner() public {
        vm.startPrank(user);
        
        vm.expectRevert();
        companions.setBaseTokenUri(BASE_URI);
        
        vm.stopPrank();
    }

    function test_TokenURI_Hidden() public {
        vm.startPrank(owner);
        
        companions.batchMint(mintContract, 1);
        
        string memory uri = companions.tokenURI(1);
        assertEq(uri, HIDDEN_URI);
        
        vm.stopPrank();
    }

    function test_TokenURI_Revealed() public {
        vm.startPrank(owner);
        
        companions.batchMint(mintContract, 1);
        companions.setBaseTokenUri(BASE_URI);
        companions.setRevealed(true);
        
        string memory uri = companions.tokenURI(1);
        assertEq(uri, string(abi.encodePacked(BASE_URI, "1.json")));
        
        vm.stopPrank();
    }

    function test_RevertWhen_TokenURIInvalidToken() public {
        vm.expectRevert(KttyWorldCompanions.InvalidTokenId.selector);
        companions.tokenURI(1);
    }

    function testFuzz_BatchMint(uint96 quantity, uint256 actorSeed) public {
        address actor = _boundActor(actorSeed);
        quantity = uint96(bound(quantity, 1, MAX_SUPPLY));
        
        vm.startPrank(owner);
        
        companions.batchMint(actor, quantity);
        
        assertEq(companions.totalSupply(), quantity);
        assertEq(companions.balanceOf(actor), quantity);
        assertTrue(companions.exists(1));
        assertTrue(companions.exists(quantity));
        
        vm.stopPrank();
    }

    function testFuzz_MultipleBatchMints(uint96 quantity1, uint96 quantity2, uint256 actorSeed) public {
        address actor = _boundActor(actorSeed);
        quantity1 = uint96(bound(quantity1, 1, MAX_SUPPLY / 2));
        quantity2 = uint96(bound(quantity2, 1, MAX_SUPPLY - quantity1));
        
        vm.startPrank(owner);
        
        companions.batchMint(actor, quantity1);
        companions.batchMint(actor, quantity2);
        
        assertEq(companions.totalSupply(), quantity1 + quantity2);
        assertEq(companions.balanceOf(actor), quantity1 + quantity2);
        assertTrue(companions.exists(1));
        assertTrue(companions.exists(quantity1));
        assertTrue(companions.exists(quantity1 + 1));
        assertTrue(companions.exists(quantity1 + quantity2));
        
        vm.stopPrank();
    }

    function testFuzz_TokenURI(uint96 quantity, uint256 tokenIdSeed) public {
        quantity = uint96(bound(quantity, 1, 1000));
        
        vm.startPrank(owner);
        
        companions.batchMint(mintContract, quantity);
        companions.setBaseTokenUri(BASE_URI);
        
        uint256 tokenId = bound(tokenIdSeed, 1, quantity);
        
        // Test hidden state
        string memory hiddenUri = companions.tokenURI(tokenId);
        assertEq(hiddenUri, HIDDEN_URI);
        
        // Test revealed state
        companions.setRevealed(true);
        string memory revealedUri = companions.tokenURI(tokenId);
        assertEq(revealedUri, string(abi.encodePacked(BASE_URI, _toString(tokenId), ".json")));
        
        vm.stopPrank();
    }

    function _boundActor(uint256 seed) internal pure returns (address) {
        return address(uint160(bound(seed, 1, type(uint160).max)));
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

contract KttyWorldCompanionsInvariantTest is Test {
    KttyWorldCompanions public companions;
    KttyWorldCompanionsHandler public handler;
    
    address public owner;
    uint256 constant MAX_SUPPLY = 10000;

    function setUp() public {
        owner = makeAddr("owner");
        
        // Deploy implementation
        KttyWorldCompanions implementation = new KttyWorldCompanions();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            KttyWorldCompanions.initialize,
            (owner, "KTTY World Companions", "KWC", "https://hidden.com/", MAX_SUPPLY)
        );
        
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        
        // Cast proxy to interface
        companions = KttyWorldCompanions(address(proxy));
        handler = new KttyWorldCompanionsHandler(companions, owner);
        
        targetContract(address(handler));
    }

    function invariant_TotalSupplyNeverExceedsMaxSupply() public view {
        assertLe(companions.totalSupply(), companions.maxSupply());
    }

    function invariant_BalancesEqualTotalSupply() public view {
        assertEq(handler.ghost_totalBalance(), companions.totalSupply());
    }

    function invariant_TokenExistenceConsistent() public view {
        uint256 totalSupply = companions.totalSupply();
        
        if (totalSupply > 0) {
            assertTrue(companions.exists(1));
            assertTrue(companions.exists(totalSupply));
        }
        
        if (totalSupply < companions.maxSupply()) {
            assertFalse(companions.exists(totalSupply + 1));
        }
    }
}

contract KttyWorldCompanionsHandler is Test {
    KttyWorldCompanions public companions;
    address public owner;
    
    uint256 public ghost_totalBalance;
    address[] public actors;

    constructor(KttyWorldCompanions _companions, address _owner) {
        companions = _companions;
        owner = _owner;
        
        for (uint i = 0; i < 5; i++) {
            actors.push(makeAddr(string(abi.encode("actor", i))));
        }
    }

    function batchMint(uint96 quantity, uint256 actorSeed) external {
        quantity = uint96(bound(quantity, 1, min(1000, companions.maxSupply() - companions.totalSupply())));
        
        if (quantity == 0 || companions.totalSupply() >= companions.maxSupply()) {
            return;
        }
        
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        
        vm.startPrank(owner);
        
        uint256 balanceBefore = companions.balanceOf(actor);
        companions.batchMint(actor, quantity);
        uint256 balanceAfter = companions.balanceOf(actor);
        
        ghost_totalBalance += (balanceAfter - balanceBefore);
        
        vm.stopPrank();
    }

    function setRevealed(bool revealed) external {
        vm.startPrank(owner);
        companions.setRevealed(revealed);
        vm.stopPrank();
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
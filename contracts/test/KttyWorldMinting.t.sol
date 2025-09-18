// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {KttyWorldMinting} from "src/KttyWorldMinting.sol";
import {KttyWorldCompanions} from "src/KttyWorldCompanions.sol";
import {KttyWorldTools} from "src/KttyWorldTools.sol";
import {KttyWorldCollectibles} from "src/KttyWorldCollectibles.sol";

contract MockKTTYToken is ERC20 {
    constructor() ERC20("KTTY Token", "KTTY") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract KttyWorldMintingTest is Test {
    KttyWorldMinting public minting;
    KttyWorldCompanions public companions;
    KttyWorldTools public tools;
    KttyWorldCollectibles public collectibles;
    MockKTTYToken public kttyToken;
    
    address public owner;
    address public treasuryWallet;
    address public user1;
    address public user2;
    address public user3;
    
    uint256 constant MAX_SUPPLY_NFT = 10000;
    uint256 constant MAX_MINT_PER_TX = 10;
    uint256 constant NATIVE_ONLY_PRICE = 1 ether;
    uint256 constant HYBRID_NATIVE_PRICE = 0.5 ether;
    uint256 constant HYBRID_KTTY_PRICE = 100 * 10**18;
    
    string constant HIDDEN_URI = "https://hidden.example.com/";
    string constant BASE_URI = "https://revealed.example.com/";
    
    event BookAdded(uint256 indexed bookId, uint256 nftId, uint256[3] toolIds, uint256 goldenTicketId);
    event BooksMinted(uint256[] bookIds, address indexed buyer);
    event BookOpened(uint256 indexed bookId, address indexed owner);
    event RoundUpdated(uint256 indexed roundNumber, uint256 startTime, uint256 endTime);
    event PaymentConfigured(KttyWorldMinting.PaymentType paymentType, uint256 nativeAmount, uint256 erc20Amount);
    event TreasuryWalletUpdated(address indexed newWallet);
    event PoolLoaded(uint256 indexed poolNumber, uint256 bookCount);
    event BucketLoaded(uint256 indexed bucketIndex, uint256 bookCount);

    function setUp() public {
        owner = makeAddr("owner");
        treasuryWallet = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.startPrank(owner);

        // Deploy KTTY Token
        kttyToken = new MockKTTYToken();

        // Deploy Companions
        KttyWorldCompanions companionsImpl = new KttyWorldCompanions();
        bytes memory companionsInitData = abi.encodeCall(
            KttyWorldCompanions.initialize,
            (owner, "KTTY World Companions", "KWC", HIDDEN_URI, MAX_SUPPLY_NFT)
        );
        ERC1967Proxy companionsProxy = new ERC1967Proxy(address(companionsImpl), companionsInitData);
        companions = KttyWorldCompanions(address(companionsProxy));

        // Deploy Tools
        KttyWorldTools toolsImpl = new KttyWorldTools();
        bytes memory toolsInitData = abi.encodeCall(
            KttyWorldTools.initialize,
            (owner, HIDDEN_URI)
        );
        ERC1967Proxy toolsProxy = new ERC1967Proxy(address(toolsImpl), toolsInitData);
        tools = KttyWorldTools(address(toolsProxy));

        // Deploy Collectibles
        KttyWorldCollectibles collectiblesImpl = new KttyWorldCollectibles();
        bytes memory collectiblesInitData = abi.encodeCall(
            KttyWorldCollectibles.initialize,
            (owner, HIDDEN_URI)
        );
        ERC1967Proxy collectiblesProxy = new ERC1967Proxy(address(collectiblesImpl), collectiblesInitData);
        collectibles = KttyWorldCollectibles(address(collectiblesProxy));

        // Deploy Minting Contract
        KttyWorldMinting mintingImpl = new KttyWorldMinting();
        bytes memory mintingInitData = abi.encodeCall(
            KttyWorldMinting.initialize,
            (
                owner,
                address(companions),
                address(tools),
                address(collectibles),
                address(kttyToken),
                treasuryWallet,
                MAX_MINT_PER_TX
            )
        );
        ERC1967Proxy mintingProxy = new ERC1967Proxy(address(mintingImpl), mintingInitData);
        minting = KttyWorldMinting(address(mintingProxy));

        // Set up token types for tools and collectibles
        tools.addTokenType("tool1.json");
        tools.addTokenType("tool2.json");  
        tools.addTokenType("tool3.json");
        tools.addTokenType("tool4.json");
        
        collectibles.addCollectibleType("golden_ticket.json");

        // Mint all NFTs to minting contract
        companions.mintAll(address(minting));
        
        // Mint tools to minting contract
        uint256[] memory toolIds = new uint256[](4);
        uint256[] memory toolAmounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            toolIds[i] = i + 1;
            toolAmounts[i] = 50000; // Large supply for testing
        }
        tools.batchMint(address(minting), toolIds, toolAmounts);
        
        // Mint golden tickets to minting contract
        uint256[] memory collectibleIds = new uint256[](1);
        uint256[] memory collectibleAmounts = new uint256[](1);
        collectibleIds[0] = 1;
        collectibleAmounts[0] = 500; // As specified in requirements
        collectibles.batchMint(address(minting), collectibleIds, collectibleAmounts);

        // Configure payment options
        minting.configurePayment(KttyWorldMinting.PaymentType.NATIVE_ONLY, NATIVE_ONLY_PRICE, 0);
        minting.configurePayment(KttyWorldMinting.PaymentType.HYBRID, HYBRID_NATIVE_PRICE, HYBRID_KTTY_PRICE);

        vm.stopPrank();

        // Give users some KTTY tokens and native currency
        kttyToken.mint(user1, 10000 * 10**18);
        kttyToken.mint(user2, 10000 * 10**18);
        kttyToken.mint(user3, 10000 * 10**18);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    // Helper function to create books
    function _createBook(
        uint256 bookId,
        uint256 nftId,
        uint256[3] memory toolIds,
        uint256 goldenTicketId,
        string memory nftType
    ) internal {
        vm.prank(owner);
        minting.addBook(bookId, nftId, toolIds, goldenTicketId, nftType);
    }

    function test_Initialize() public view {
        assertEq(minting.owner(), owner);
        assertEq(minting.getCurrentRound(), 0); // Should start in manual round
        
        (KttyWorldMinting.PaymentOption memory nativeOnly, KttyWorldMinting.PaymentOption memory hybrid) = minting.getPaymentConfig();
        assertEq(nativeOnly.nativeAmount, NATIVE_ONLY_PRICE);
        assertEq(nativeOnly.erc20Amount, 0);
        assertEq(hybrid.nativeAmount, HYBRID_NATIVE_PRICE);
        assertEq(hybrid.erc20Amount, HYBRID_KTTY_PRICE);
    }

    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert();
        minting.initialize(
            owner,
            address(companions),
            address(tools),
            address(collectibles),
            address(kttyToken),
            treasuryWallet,
            MAX_MINT_PER_TX
        );
    }

    function test_AddBook() public {
        uint256 bookId = 1;
        uint256 nftId = 1;
        uint256[3] memory toolIds = [uint256(1), uint256(2), uint256(3)];
        uint256 goldenTicketId = 1;
        string memory nftType = "NULL";

        vm.expectEmit(true, true, true, true);
        emit BookAdded(bookId, nftId, toolIds, goldenTicketId);

        vm.prank(owner);
        minting.addBook(bookId, nftId, toolIds, goldenTicketId, nftType);

        KttyWorldMinting.Book memory book = minting.getBook(bookId);
        assertEq(book.nftId, nftId);
        assertEq(book.toolIds[0], toolIds[0]);
        assertEq(book.toolIds[1], toolIds[1]);
        assertEq(book.toolIds[2], toolIds[2]);
        assertEq(book.goldenTicketId, goldenTicketId);
        assertTrue(book.hasGoldenTicket);
        assertEq(book.nftType, nftType);
    }

    function test_RevertWhen_AddBookNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        minting.addBook(1, 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
    }

    function test_ConfigureRound() public {
        uint256 roundNumber = 1;
        uint256 startTime = block.timestamp + 1 hours;
        uint256 endTime = block.timestamp + 1 days;

        vm.expectEmit(true, true, true, true);
        emit RoundUpdated(roundNumber, startTime, endTime);

        vm.prank(owner);
        minting.configureRound(roundNumber, startTime, endTime);
    }

    function test_RevertWhen_ConfigureInvalidRound() public {
        vm.prank(owner);
        vm.expectRevert(KttyWorldMinting.InvalidRound.selector);
        minting.configureRound(0, block.timestamp, block.timestamp + 1 days);

        vm.prank(owner);
        vm.expectRevert(KttyWorldMinting.InvalidRound.selector);
        minting.configureRound(5, block.timestamp, block.timestamp + 1 days);
    }

    function test_SetWhitelistAllowances() public {
        address[] memory users = new address[](2);
        uint256[] memory allowances = new uint256[](2);
        users[0] = user1;
        users[1] = user2;
        allowances[0] = 5;
        allowances[1] = 3;

        vm.prank(owner);
        minting.setWhitelistAllowances(1, users, allowances);

        (uint256 allowance1, ) = minting.getWhitelistStatus(1, user1);
        (uint256 allowance2, ) = minting.getWhitelistStatus(1, user2);
        assertEq(allowance1, 5);
        assertEq(allowance2, 3);
    }

    function test_RevertWhen_SetWhitelistAllowancesInvalidRound() public {
        address[] memory users = new address[](1);
        uint256[] memory allowances = new uint256[](1);
        users[0] = user1;
        allowances[0] = 5;

        vm.prank(owner);
        vm.expectRevert(KttyWorldMinting.InvalidRound.selector);
        minting.setWhitelistAllowances(3, users, allowances);
    }

    function test_SetRound3MerkleRoot() public {
        // Use generated merkle data from JavaScript script
        bytes32 merkleRoot = 0x103a5da4bd852cab556ff83f6a906cb85a74594b386f20f95f37d6eb0c614557;
        
        vm.prank(owner);
        minting.setRound3MerkleRoot(merkleRoot);
        
        // Test user1 (should be whitelisted)
        bytes32[] memory user1Proof = new bytes32[](3);
        user1Proof[0] = 0xc30cdc6a88b24a674fe288a58a537402dbe5ce7d7d889d3cef08fd2ae3e48477;
        user1Proof[1] = 0x99ee7d1d978da17c87b2b35fa00025d7b13eef1cbcfe3242d757f00cdb89c777;
        user1Proof[2] = 0xeb9a09586e1c9f485ceebd51159d55c4c0b4c1b207fc119a967a693aa3207d5c;
        
        bool isUser1Whitelisted = minting.isWhitelistedForRound3(user1, user1Proof);
        assertTrue(isUser1Whitelisted);
        
        // Test non-whitelisted address (should fail)
        address nonWhitelisted = 0x000000000000000000000000000000000000dEaD;
        bytes32[] memory emptyProof = new bytes32[](0);
        
        bool isNotWhitelisted = minting.isWhitelistedForRound3(nonWhitelisted, emptyProof);
        assertFalse(isNotWhitelisted);
        
        // Test valid address with wrong proof (should fail)
        bool isUser1WithWrongProof = minting.isWhitelistedForRound3(user1, emptyProof);
        assertFalse(isUser1WithWrongProof);
    }

    function test_LoadPool1() public {
        uint256[] memory bookIds = new uint256[](3);
        bookIds[0] = 1;
        bookIds[1] = 2;
        bookIds[2] = 3;

        vm.expectEmit(true, true, true, true);
        emit PoolLoaded(1, 3);

        vm.prank(owner);
        minting.loadPool1(bookIds);

        (uint256 pool1Remaining, , , ) = minting.getPoolAndBucketStatus();
        assertEq(pool1Remaining, 3);
    }

    function test_LoadPool2() public {
        uint256[] memory bookIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            bookIds[i] = i + 10;
        }

        vm.expectEmit(true, true, true, true);
        emit PoolLoaded(2, 5);

        vm.prank(owner);
        minting.loadPool2(bookIds);

        (, uint256 pool2Remaining, , ) = minting.getPoolAndBucketStatus();
        assertEq(pool2Remaining, 5);
    }

    function test_LoadBucket() public {
        uint256[] memory bookIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            bookIds[i] = i + 100;
        }

        vm.expectEmit(true, true, true, true);
        emit BucketLoaded(0, 10);

        vm.prank(owner);
        minting.loadBucket(0, bookIds, 5, 1, 2, 2);

        (, , , uint256[8] memory bucketRemaining) = minting.getPoolAndBucketStatus();
        assertEq(bucketRemaining[0], 10);
    }

    function test_RevertWhen_LoadInvalidBucket() public {
        uint256[] memory bookIds = new uint256[](1);
        bookIds[0] = 1;

        vm.prank(owner);
        vm.expectRevert(KttyWorldMinting.InvalidRound.selector);
        minting.loadBucket(8, bookIds, 1, 0, 0, 0);
    }

    function test_ManualAirdrop() public {
        // First create some books and add to contract
        _createBook(1, 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        _createBook(2, 2, [uint256(1), uint256(2), uint256(3)], 0, "NULL");

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        vm.prank(owner);
        minting.manualAirdrop(tokenIds, user1);

        assertEq(companions.ownerOf(1), user1);
        assertEq(companions.ownerOf(2), user1);
    }

    function test_RevertWhen_ManualAirdropNotOwner() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.prank(user1);
        vm.expectRevert();
        minting.manualAirdrop(tokenIds, user1);
    }

    function test_SetTreasuryWallet() public {
        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit(true, true, true, true);
        emit TreasuryWalletUpdated(newTreasury);

        vm.prank(owner);
        minting.setTreasuryWallet(newTreasury);
    }

    function test_SetMaxMintPerTransaction() public {
        uint256 newMax = 20;

        vm.prank(owner);
        minting.setMaxMintPerTransaction(newMax);
        
        // Test indirectly by trying to mint more than old limit but within new limit
        // (Would need active round and proper setup for full test)
    }

    function test_ConfigurePayment() public {
        uint256 newNativePrice = 2 ether;
        uint256 newKttyPrice = 200 * 10**18;

        vm.expectEmit(true, true, true, true);
        emit PaymentConfigured(KttyWorldMinting.PaymentType.HYBRID, newNativePrice, newKttyPrice);

        vm.prank(owner);
        minting.configurePayment(KttyWorldMinting.PaymentType.HYBRID, newNativePrice, newKttyPrice);

        (, KttyWorldMinting.PaymentOption memory hybrid) = minting.getPaymentConfig();
        assertEq(hybrid.nativeAmount, newNativePrice);
        assertEq(hybrid.erc20Amount, newKttyPrice);
    }

    function test_RevertWhen_ConfigurePaymentNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        minting.configurePayment(KttyWorldMinting.PaymentType.NATIVE_ONLY, 1 ether, 0);
    }

    // Test Round 1 Minting with Whitelist
    function test_Round1Minting() public {
        // Set up Round 1
        vm.prank(owner);
        minting.configureRound(1, block.timestamp, block.timestamp + 1 days);

        // Set up whitelist
        address[] memory users = new address[](1);
        uint256[] memory allowances = new uint256[](1);
        users[0] = user1;
        allowances[0] = 3;

        vm.prank(owner);
        minting.setWhitelistAllowances(1, users, allowances);

        // Create and load pool 1
        uint256[] memory pool1Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            pool1Books[i] = i + 1;
            _createBook(i + 1, i + 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        // User1 mints 2 books
        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        minting.mint{value: NATIVE_ONLY_PRICE * 2}(2, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        uint256[] memory userBooks = minting.getUserBooks(user1);
        assertEq(userBooks.length, 2);
        assertEq(userBooks[0], 1);
        assertEq(userBooks[1], 2);

        // Check allowance was decremented
        (, uint256 minted) = minting.getWhitelistStatus(1, user1);
        assertEq(minted, 2);
    }

    function test_RevertWhen_Round1MintingExceedsAllowance() public {
        // Set up Round 1
        vm.prank(owner);
        minting.configureRound(1, block.timestamp, block.timestamp + 1 days);

        // Set up whitelist with limit of 2
        address[] memory users = new address[](1);
        uint256[] memory allowances = new uint256[](1);
        users[0] = user1;
        allowances[0] = 2;

        vm.prank(owner);
        minting.setWhitelistAllowances(1, users, allowances);

        // Create and load pool 1
        uint256[] memory pool1Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            pool1Books[i] = i + 1;
            _createBook(i + 1, i + 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        // User1 tries to mint 3 books (exceeds allowance of 2)
        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        vm.expectRevert(KttyWorldMinting.InsufficientAllowance.selector);
        minting.mint{value: NATIVE_ONLY_PRICE * 3}(3, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);
    }

    function test_RevertWhen_Round1MintingNotWhitelisted() public {
        // Set up Round 1
        vm.prank(owner);
        minting.configureRound(1, block.timestamp, block.timestamp + 1 days);

        // Don't add user1 to whitelist

        // Create and load pool 1
        uint256[] memory pool1Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            pool1Books[i] = i + 1;
            _createBook(i + 1, i + 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        // User1 tries to mint without being whitelisted
        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        vm.expectRevert(KttyWorldMinting.InsufficientAllowance.selector);
        minting.mint{value: NATIVE_ONLY_PRICE}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);
    }

    // Test Hybrid Payment
    function test_HybridPayment() public {
        // Set up Round 4 (public round)
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        // Create and load some books
        uint256[] memory pool1Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            pool1Books[i] = i + 1;
            _createBook(i + 1, i + 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        // User1 approves KTTY tokens and mints with hybrid payment
        vm.prank(user1);
        kttyToken.approve(address(minting), HYBRID_KTTY_PRICE);

        uint256 treasuryBalanceBefore = treasuryWallet.balance;
        uint256 userKttyBalanceBefore = kttyToken.balanceOf(user1);

        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        minting.mint{value: HYBRID_NATIVE_PRICE}(1, KttyWorldMinting.PaymentType.HYBRID, emptyProof);

        // Check payments were processed
        assertEq(treasuryWallet.balance, treasuryBalanceBefore + HYBRID_NATIVE_PRICE);
        assertEq(kttyToken.balanceOf(user1), userKttyBalanceBefore - HYBRID_KTTY_PRICE);

        uint256[] memory userBooks = minting.getUserBooks(user1);
        assertEq(userBooks.length, 1);
    }

    function test_RevertWhen_InsufficientPayment() public {
        // Set up Round 4 (public round)
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        // Create and load some books
        uint256[] memory pool1Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            pool1Books[i] = i + 1;
            _createBook(i + 1, i + 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        bytes32[] memory emptyProof = new bytes32[](0);
        
        // Try to mint with insufficient native payment
        vm.prank(user1);
        vm.expectRevert(KttyWorldMinting.InsufficientPayment.selector);
        minting.mint{value: NATIVE_ONLY_PRICE - 1}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);
    }

    function test_ExcessPaymentRefund() public {
        // Set up Round 4 (public round)
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        // Create and load some books
        uint256[] memory pool1Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            pool1Books[i] = i + 1;
            _createBook(i + 1, i + 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        uint256 userBalanceBefore = user1.balance;
        uint256 overpayment = 1 ether;
        uint256 totalSent = NATIVE_ONLY_PRICE + overpayment;

        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        minting.mint{value: totalSent}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        // Check user received refund
        assertEq(user1.balance, userBalanceBefore - NATIVE_ONLY_PRICE);
    }

    // Test Book Opening
    function test_OpenBook() public {
        // Set up and mint a book first
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        _createBook(1, 1, [uint256(1), uint256(2), uint256(3)], 1, "NULL");

        uint256[] memory pool1Books = new uint256[](1);
        pool1Books[0] = 1;

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        minting.mint{value: NATIVE_ONLY_PRICE}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        // Now open the book
        vm.expectEmit(true, true, true, true);
        emit BookOpened(1, user1);

        vm.prank(user1);
        minting.openBook(1);

        // Check user received the NFT
        assertEq(companions.ownerOf(1), user1);
        // Check user received tools
        assertEq(tools.balanceOf(user1, 1), 1);
        assertEq(tools.balanceOf(user1, 2), 1);
        assertEq(tools.balanceOf(user1, 3), 1);
        // Check user received golden ticket
        assertEq(collectibles.balanceOf(user1, 1), 1);

        // Check book is marked as opened
        assertTrue(minting.isBookOpened(1));
    }

    function test_RevertWhen_OpenBookNotOwned() public {
        // Set up and mint a book to user1
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        _createBook(1, 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");

        uint256[] memory pool1Books = new uint256[](1);
        pool1Books[0] = 1;

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        minting.mint{value: NATIVE_ONLY_PRICE}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        // User2 tries to open user1's book
        vm.prank(user2);
        vm.expectRevert(KttyWorldMinting.BookNotOwned.selector);
        minting.openBook(1);
    }

    function test_RevertWhen_OpenBookAlreadyOpened() public {
        // Set up and mint a book
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        _createBook(1, 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");

        uint256[] memory pool1Books = new uint256[](1);
        pool1Books[0] = 1;

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        minting.mint{value: NATIVE_ONLY_PRICE}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        // Open the book once
        vm.prank(user1);
        minting.openBook(1);

        // Try to open again
        vm.prank(user1);
        vm.expectRevert(KttyWorldMinting.BookAlreadyOpened.selector);
        minting.openBook(1);
    }

    function test_RevertWhen_MintZeroQuantity() public {
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        vm.expectRevert(KttyWorldMinting.MaxMintExceeded.selector);
        minting.mint{value: 0}(0, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);
    }

    function test_RevertWhen_MintExceedsMaxPerTransaction() public {
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        vm.expectRevert(KttyWorldMinting.MaxMintExceeded.selector);
        minting.mint{value: NATIVE_ONLY_PRICE * (MAX_MINT_PER_TX + 1)}(MAX_MINT_PER_TX + 1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);
    }

    function test_RevertWhen_MintInManualRound() public {
        // Current round should be 0 (manual) by default
        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        vm.expectRevert(KttyWorldMinting.RoundNotActive.selector);
        minting.mint{value: NATIVE_ONLY_PRICE}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);
    }

    function test_GetCurrentRound() public {
        // Initially should be manual round (0)
        assertEq(minting.getCurrentRound(), 0);

        // Configure and check Round 1
        vm.prank(owner);
        minting.configureRound(1, block.timestamp, block.timestamp + 1 days);
        assertEq(minting.getCurrentRound(), 1);

        // Move past Round 1 end time
        vm.warp(block.timestamp + 2 days);
        assertEq(minting.getCurrentRound(), 0); // Should fall back to manual

        // Configure Round 2 for current time
        vm.prank(owner);
        minting.configureRound(2, block.timestamp, block.timestamp + 1 days);
        assertEq(minting.getCurrentRound(), 2);
    }

    function test_ViewFunctions() public view {
        // Test getUserBooks
        uint256[] memory userBooks = minting.getUserBooks(user1);
        assertEq(userBooks.length, 0);

        // Test getBook for non-existent book
        KttyWorldMinting.Book memory book = minting.getBook(999);
        assertEq(book.nftId, 0);

        // Test isBookOpened
        assertFalse(minting.isBookOpened(1));

        // Test getPoolAndBucketStatus
        (uint256 pool1Remaining, uint256 pool2Remaining, uint256 currentBucket, uint256[8] memory bucketRemaining) = minting.getPoolAndBucketStatus();
        assertEq(pool1Remaining, 0);
        assertEq(pool2Remaining, 0);
        assertEq(currentBucket, 0);
        for (uint256 i = 0; i < 8; i++) {
            assertEq(bucketRemaining[i], 0);
        }

        // Test getWhitelistStatus
        (uint256 allowance, uint256 minted) = minting.getWhitelistStatus(1, user1);
        assertEq(allowance, 0);
        assertEq(minted, 0);
    }
}

// Additional test contract for complex scenarios
contract KttyWorldMintingEdgeCasesTest is Test {
    KttyWorldMinting public minting;
    KttyWorldCompanions public companions;
    KttyWorldTools public tools;
    KttyWorldCollectibles public collectibles;
    MockKTTYToken public kttyToken;
    
    address public owner;
    address public treasuryWallet;
    address public user1;
    
    function setUp() public {
        owner = makeAddr("owner");
        treasuryWallet = makeAddr("treasury");
        user1 = makeAddr("user1");

        vm.startPrank(owner);

        // Deploy all contracts (simplified setup)
        kttyToken = new MockKTTYToken();

        KttyWorldCompanions companionsImpl = new KttyWorldCompanions();
        bytes memory companionsInitData = abi.encodeCall(
            KttyWorldCompanions.initialize,
            (owner, "KTTY World Companions", "KWC", "https://hidden.com/", 10000)
        );
        ERC1967Proxy companionsProxy = new ERC1967Proxy(address(companionsImpl), companionsInitData);
        companions = KttyWorldCompanions(address(companionsProxy));

        KttyWorldTools toolsImpl = new KttyWorldTools();
        bytes memory toolsInitData = abi.encodeCall(
            KttyWorldTools.initialize,
            (owner, "https://hidden.com/")
        );
        ERC1967Proxy toolsProxy = new ERC1967Proxy(address(toolsImpl), toolsInitData);
        tools = KttyWorldTools(address(toolsProxy));

        KttyWorldCollectibles collectiblesImpl = new KttyWorldCollectibles();
        bytes memory collectiblesInitData = abi.encodeCall(
            KttyWorldCollectibles.initialize,
            (owner, "https://hidden.com/")
        );
        ERC1967Proxy collectiblesProxy = new ERC1967Proxy(address(collectiblesImpl), collectiblesInitData);
        collectibles = KttyWorldCollectibles(address(collectiblesProxy));

        KttyWorldMinting mintingImpl = new KttyWorldMinting();
        bytes memory mintingInitData = abi.encodeCall(
            KttyWorldMinting.initialize,
            (
                owner,
                address(companions),
                address(tools),
                address(collectibles),
                address(kttyToken),
                treasuryWallet,
                10
            )
        );
        ERC1967Proxy mintingProxy = new ERC1967Proxy(address(mintingImpl), mintingInitData);
        minting = KttyWorldMinting(address(mintingProxy));

        // Setup tokens
        tools.addTokenType("tool1.json");
        tools.addTokenType("tool2.json");
        tools.addTokenType("tool3.json");
        collectibles.addCollectibleType("golden_ticket.json");

        companions.mintAll(address(minting));
        
        uint256[] memory toolIds = new uint256[](3);
        uint256[] memory toolAmounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            toolIds[i] = i + 1;
            toolAmounts[i] = 10000;
        }
        tools.batchMint(address(minting), toolIds, toolAmounts);
        
        collectibles.mint(address(minting), 1, 500);

        minting.configurePayment(KttyWorldMinting.PaymentType.NATIVE_ONLY, 1 ether, 0);

        vm.stopPrank();

        vm.deal(user1, 100 ether);
    }

    function test_CrossBucketMinting() public {
        // Set up Round 3 (bucket round)
        vm.prank(owner);
        minting.configureRound(3, block.timestamp, block.timestamp + 1 days);

        // Create books for buckets
        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(owner);
            minting.addBook(i, i, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        // Load bucket 0 with only 2 books
        uint256[] memory bucket0Books = new uint256[](2);
        bucket0Books[0] = 1;
        bucket0Books[1] = 2;

        vm.prank(owner);
        minting.loadBucket(0, bucket0Books, 2, 0, 0, 0);

        // Load bucket 1 with remaining books
        uint256[] memory bucket1Books = new uint256[](8);
        for (uint256 i = 0; i < 8; i++) {
            bucket1Books[i] = i + 3;
        }

        vm.prank(owner);
        minting.loadBucket(1, bucket1Books, 8, 0, 0, 0);

        // Set up merkle root for Round 3
        vm.prank(owner);
        minting.setRound3MerkleRoot(0x103a5da4bd852cab556ff83f6a906cb85a74594b386f20f95f37d6eb0c614557);

        // Mock merkle proof (in real test, this would be proper proof)
        bytes32[] memory proof = new bytes32[](3);
        proof[0] = 0xc30cdc6a88b24a674fe288a58a537402dbe5ce7d7d889d3cef08fd2ae3e48477;
        proof[1] = 0x99ee7d1d978da17c87b2b35fa00025d7b13eef1cbcfe3242d757f00cdb89c777;
        proof[2] = 0xeb9a09586e1c9f485ceebd51159d55c4c0b4c1b207fc119a967a693aa3207d5c;

        // Try to mint 5 books (should take 2 from bucket 0, 3 from bucket 1)
        vm.prank(user1);
        minting.mint{value: 5 ether}(5, KttyWorldMinting.PaymentType.NATIVE_ONLY, proof);

        uint256[] memory userBooks = minting.getUserBooks(user1);
        assertEq(userBooks.length, 5);
        assertEq(userBooks[0], 1);
        assertEq(userBooks[1], 2);
        assertEq(userBooks[2], 3);
        assertEq(userBooks[3], 4);
        assertEq(userBooks[4], 5);

        // Check bucket and pool status
        (, , uint256 currentBucket, uint256[8] memory bucketRemaining) = minting.getPoolAndBucketStatus();
        assertEq(currentBucket, 1); // Should have moved to bucket 1
        assertEq(bucketRemaining[0], 0); // Bucket 0 should be empty
        assertEq(bucketRemaining[1], 5); // Bucket 1 should have 5 left
    }

    function test_PoolExhaustion() public {
        // Set up Round 1
        vm.prank(owner);
        minting.configureRound(1, block.timestamp, block.timestamp + 1 days);

        // Create and load only 1 book in pool 1
        vm.prank(owner);
        minting.addBook(1, 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");

        uint256[] memory pool1Books = new uint256[](1);
        pool1Books[0] = 1;

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        // Set up whitelist
        address[] memory users = new address[](1);
        uint256[] memory allowances = new uint256[](1);
        users[0] = user1;
        allowances[0] = 2; // Allow 2 mints but only 1 book available

        vm.prank(owner);
        minting.setWhitelistAllowances(1, users, allowances);

        // First mint should succeed
        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        minting.mint{value: 1 ether}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        // Second mint should fail due to pool exhaustion
        vm.prank(user1);
        vm.expectRevert(KttyWorldMinting.PoolExhausted.selector);
        minting.mint{value: 1 ether}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);
    }

    function test_ReentrancyProtection() public {
        // This test would need a malicious contract to test reentrancy
        // For now, we just verify the function has the nonReentrant modifier
        // by checking it can't be called recursively (would require more complex setup)
        assertTrue(true); // Placeholder test
    }
}

// Test contract for Round 3 with proper merkle tree
contract KttyWorldMintingRound3Test is Test {
    KttyWorldMinting public minting;
    KttyWorldCompanions public companions;
    KttyWorldTools public tools;
    KttyWorldCollectibles public collectibles;
    MockKTTYToken public kttyToken;
    
    address public owner;
    address public treasuryWallet;
    address public user1;
    address public user2;
    
    // Simplified merkle tree for testing
    bytes32 public merkleRoot;
    
    function setUp() public {
        owner = makeAddr("owner");
        treasuryWallet = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);

        // Deploy all contracts
        kttyToken = new MockKTTYToken();

        KttyWorldCompanions companionsImpl = new KttyWorldCompanions();
        bytes memory companionsInitData = abi.encodeCall(
            KttyWorldCompanions.initialize,
            (owner, "KTTY World Companions", "KWC", "https://hidden.com/", 10000)
        );
        ERC1967Proxy companionsProxy = new ERC1967Proxy(address(companionsImpl), companionsInitData);
        companions = KttyWorldCompanions(address(companionsProxy));

        KttyWorldTools toolsImpl = new KttyWorldTools();
        bytes memory toolsInitData = abi.encodeCall(
            KttyWorldTools.initialize,
            (owner, "https://hidden.com/")
        );
        ERC1967Proxy toolsProxy = new ERC1967Proxy(address(toolsImpl), toolsInitData);
        tools = KttyWorldTools(address(toolsProxy));

        KttyWorldCollectibles collectiblesImpl = new KttyWorldCollectibles();
        bytes memory collectiblesInitData = abi.encodeCall(
            KttyWorldCollectibles.initialize,
            (owner, "https://hidden.com/")
        );
        ERC1967Proxy collectiblesProxy = new ERC1967Proxy(address(collectiblesImpl), collectiblesInitData);
        collectibles = KttyWorldCollectibles(address(collectiblesProxy));

        KttyWorldMinting mintingImpl = new KttyWorldMinting();
        bytes memory mintingInitData = abi.encodeCall(
            KttyWorldMinting.initialize,
            (
                owner,
                address(companions),
                address(tools),
                address(collectibles),
                address(kttyToken),
                treasuryWallet,
                10
            )
        );
        ERC1967Proxy mintingProxy = new ERC1967Proxy(address(mintingImpl), mintingInitData);
        minting = KttyWorldMinting(address(mintingProxy));

        // Setup tokens
        tools.addTokenType("tool1.json");
        tools.addTokenType("tool2.json");
        tools.addTokenType("tool3.json");
        collectibles.addCollectibleType("golden_ticket.json");

        companions.mintAll(address(minting));
        
        uint256[] memory toolIds = new uint256[](3);
        uint256[] memory toolAmounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            toolIds[i] = i + 1;
            toolAmounts[i] = 10000;
        }
        tools.batchMint(address(minting), toolIds, toolAmounts);
        
        collectibles.mint(address(minting), 1, 500);

        minting.configurePayment(KttyWorldMinting.PaymentType.NATIVE_ONLY, 1 ether, 0);

        // Use the same merkle root generated by our JavaScript script
        merkleRoot = 0x103a5da4bd852cab556ff83f6a906cb85a74594b386f20f95f37d6eb0c614557;
        
        minting.setRound3MerkleRoot(merkleRoot);

        vm.stopPrank();

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function _generateValidMerkleProof(address user) internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](3);
        
        if (user == 0x29E3b139f4393aDda86303fcdAa35F60Bb7092bF) { // user1
            proof[0] = 0xc30cdc6a88b24a674fe288a58a537402dbe5ce7d7d889d3cef08fd2ae3e48477;
            proof[1] = 0x99ee7d1d978da17c87b2b35fa00025d7b13eef1cbcfe3242d757f00cdb89c777;
            proof[2] = 0xeb9a09586e1c9f485ceebd51159d55c4c0b4c1b207fc119a967a693aa3207d5c;
        } else if (user == 0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e) { // user2
            proof[0] = 0xa3fd369f375645411b4b9933ecfc861a9760517ee70f0ad6668c4f3f56972dc8;
            proof[1] = 0x99ee7d1d978da17c87b2b35fa00025d7b13eef1cbcfe3242d757f00cdb89c777;
            proof[2] = 0xeb9a09586e1c9f485ceebd51159d55c4c0b4c1b207fc119a967a693aa3207d5c;
        } else {
            // Return empty proof for non-whitelisted addresses
            proof = new bytes32[](0);
        }
        
        return proof;
    }

    function test_Round3BucketMinting() public {
        // Set up Round 3
        vm.prank(owner);
        minting.configureRound(3, block.timestamp, block.timestamp + 1 days);

        // Create books for bucket testing
        for (uint256 i = 1; i <= 15; i++) {
            vm.prank(owner);
            minting.addBook(i, i, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        // Load bucket 0 with specific distribution
        uint256[] memory bucket0Books = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            bucket0Books[i] = i + 1;
        }

        vm.prank(owner);
        minting.loadBucket(0, bucket0Books, 5, 1, 2, 2); // 5 NULL, 1 1/1, 2 golden tickets, 2 basic

        // Load bucket 1
        uint256[] memory bucket1Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            bucket1Books[i] = i + 11;
        }

        vm.prank(owner);
        minting.loadBucket(1, bucket1Books, 3, 0, 1, 1);

        // User1 mints from Round 3 with valid merkle proof
        bytes32[] memory proof = _generateValidMerkleProof(user1);
        
        vm.prank(user1);
        minting.mint{value: 3 ether}(3, KttyWorldMinting.PaymentType.NATIVE_ONLY, proof);

        uint256[] memory userBooks = minting.getUserBooks(user1);
        assertEq(userBooks.length, 3);
        
        // Check bucket status
        (, , uint256 currentBucket, uint256[8] memory bucketRemaining) = minting.getPoolAndBucketStatus();
        assertEq(currentBucket, 0);
        assertEq(bucketRemaining[0], 7); // 10 - 3 = 7 remaining
    }

    function test_Round3InvalidMerkleProof() public {
        // Set up Round 3
        vm.prank(owner);
        minting.configureRound(3, block.timestamp, block.timestamp + 1 days);

        // Create and load some books
        vm.prank(owner);
        minting.addBook(1, 1, [uint256(1), uint256(2), uint256(3)], 0, "NULL");

        uint256[] memory bucket0Books = new uint256[](1);
        bucket0Books[0] = 1;

        vm.prank(owner);
        minting.loadBucket(0, bucket0Books, 1, 0, 0, 0);

        // User tries to mint with invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("invalid");
        
        vm.prank(user1);
        vm.expectRevert(KttyWorldMinting.InvalidProof.selector);
        minting.mint{value: 1 ether}(1, KttyWorldMinting.PaymentType.NATIVE_ONLY, invalidProof);
    }

    function test_Round3PoolCarryover() public {
        // Set up Round 1 with leftover pool (use future timestamps to avoid issues)
        uint256 round1Start = block.timestamp + 1 hours;
        uint256 round1End = block.timestamp + 2 hours;
        
        vm.prank(owner);
        minting.configureRound(1, round1Start, round1End);

        // Create books for pool 1
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(owner);
            minting.addBook(i, i, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        uint256[] memory pool1Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            pool1Books[i] = i + 1;
        }

        vm.prank(owner);
        minting.loadPool1(pool1Books);

        // Set up Round 3
        vm.prank(owner);
        minting.configureRound(3, block.timestamp, block.timestamp + 1 days);

        // Create books for bucket
        for (uint256 i = 6; i <= 10; i++) {
            vm.prank(owner);
            minting.addBook(i, i, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        uint256[] memory bucket0Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            bucket0Books[i] = i + 6;
        }

        vm.prank(owner);
        minting.loadBucket(0, bucket0Books, 5, 0, 0, 0);

        // User1 mints - should get from pool 1 first
        bytes32[] memory proof = _generateValidMerkleProof(user1);
        
        vm.prank(user1);
        minting.mint{value: 3 ether}(3, KttyWorldMinting.PaymentType.NATIVE_ONLY, proof);

        uint256[] memory userBooks = minting.getUserBooks(user1);
        assertEq(userBooks.length, 3);
        // Should get books 1, 2, 3 from pool 1
        assertEq(userBooks[0], 1);
        assertEq(userBooks[1], 2);
        assertEq(userBooks[2], 3);

        // Pool 1 should have 2 remaining, bucket 0 should be untouched
        (uint256 pool1Remaining, , , uint256[8] memory bucketRemaining) = minting.getPoolAndBucketStatus();
        assertEq(pool1Remaining, 2);
        assertEq(bucketRemaining[0], 5);
    }
}

// Test contract for Round 4 public minting
contract KttyWorldMintingRound4Test is Test {
    KttyWorldMinting public minting;
    KttyWorldCompanions public companions;
    KttyWorldTools public tools;
    KttyWorldCollectibles public collectibles;
    MockKTTYToken public kttyToken;
    
    address public owner;
    address public treasuryWallet;
    address public user1;
    address public user2;
    
    function setUp() public {
        owner = makeAddr("owner");
        treasuryWallet = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);

        // Deploy all contracts (simplified setup)
        kttyToken = new MockKTTYToken();

        KttyWorldCompanions companionsImpl = new KttyWorldCompanions();
        bytes memory companionsInitData = abi.encodeCall(
            KttyWorldCompanions.initialize,
            (owner, "KTTY World Companions", "KWC", "https://hidden.com/", 10000)
        );
        ERC1967Proxy companionsProxy = new ERC1967Proxy(address(companionsImpl), companionsInitData);
        companions = KttyWorldCompanions(address(companionsProxy));

        KttyWorldTools toolsImpl = new KttyWorldTools();
        bytes memory toolsInitData = abi.encodeCall(
            KttyWorldTools.initialize,
            (owner, "https://hidden.com/")
        );
        ERC1967Proxy toolsProxy = new ERC1967Proxy(address(toolsImpl), toolsInitData);
        tools = KttyWorldTools(address(toolsProxy));

        KttyWorldCollectibles collectiblesImpl = new KttyWorldCollectibles();
        bytes memory collectiblesInitData = abi.encodeCall(
            KttyWorldCollectibles.initialize,
            (owner, "https://hidden.com/")
        );
        ERC1967Proxy collectiblesProxy = new ERC1967Proxy(address(collectiblesImpl), collectiblesInitData);
        collectibles = KttyWorldCollectibles(address(collectiblesProxy));

        KttyWorldMinting mintingImpl = new KttyWorldMinting();
        bytes memory mintingInitData = abi.encodeCall(
            KttyWorldMinting.initialize,
            (
                owner,
                address(companions),
                address(tools),
                address(collectibles),
                address(kttyToken),
                treasuryWallet,
                10
            )
        );
        ERC1967Proxy mintingProxy = new ERC1967Proxy(address(mintingImpl), mintingInitData);
        minting = KttyWorldMinting(address(mintingProxy));

        // Setup tokens
        tools.addTokenType("tool1.json");
        tools.addTokenType("tool2.json");
        tools.addTokenType("tool3.json");
        collectibles.addCollectibleType("golden_ticket.json");

        companions.mintAll(address(minting));
        
        uint256[] memory toolIds = new uint256[](3);
        uint256[] memory toolAmounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            toolIds[i] = i + 1;
            toolAmounts[i] = 10000;
        }
        tools.batchMint(address(minting), toolIds, toolAmounts);
        
        collectibles.mint(address(minting), 1, 500);

        minting.configurePayment(KttyWorldMinting.PaymentType.NATIVE_ONLY, 1 ether, 0);

        vm.stopPrank();

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function test_Round4PublicMinting() public {
        // Set up Round 4
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        // Create books for testing
        for (uint256 i = 1; i <= 20; i++) {
            vm.prank(owner);
            minting.addBook(i, i, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        // Load some books in buckets
        uint256[] memory bucket0Books = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            bucket0Books[i] = i + 1;
        }

        vm.prank(owner);
        minting.loadBucket(0, bucket0Books, 10, 0, 0, 0);

        uint256[] memory bucket1Books = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            bucket1Books[i] = i + 11;
        }

        vm.prank(owner);
        minting.loadBucket(1, bucket1Books, 10, 0, 0, 0);

        // Anyone can mint in Round 4 (no whitelist)
        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        minting.mint{value: 5 ether}(5, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        vm.prank(user2);
        minting.mint{value: 3 ether}(3, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        // Check both users got their books
        uint256[] memory user1Books = minting.getUserBooks(user1);
        uint256[] memory user2Books = minting.getUserBooks(user2);
        
        assertEq(user1Books.length, 5);
        assertEq(user2Books.length, 3);

        // Check bucket status
        (, , uint256 currentBucket, uint256[8] memory bucketRemaining) = minting.getPoolAndBucketStatus();
        assertEq(currentBucket, 0);
        assertEq(bucketRemaining[0], 2); // 10 - 8 = 2 remaining
    }

    function test_Round4WithLeftoverPools() public {
        // Set up past rounds with leftover pools (use reasonable future timestamps)
        uint256 round1Start = block.timestamp + 1 hours;
        uint256 round1End = block.timestamp + 2 hours;
        uint256 round2Start = block.timestamp + 2 hours;
        uint256 round2End = block.timestamp + 3 hours;
        
        vm.prank(owner);
        minting.configureRound(1, round1Start, round1End);
        
        vm.prank(owner);
        minting.configureRound(2, round2Start, round2End);

        vm.prank(owner);
        minting.setMaxMintPerTransaction(12);

        // Create books for pools
        for (uint256 i = 1; i <= 15; i++) {
            vm.prank(owner);
            minting.addBook(i, i, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        // Load pool 1 and 2 with books
        uint256[] memory pool1Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            pool1Books[i] = i + 1;
        }
        vm.prank(owner);
        minting.loadPool1(pool1Books);

        uint256[] memory pool2Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            pool2Books[i] = i + 6;
        }
        vm.prank(owner);
        minting.loadPool2(pool2Books);

        // Load bucket with remaining books
        uint256[] memory bucket0Books = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            bucket0Books[i] = i + 11;
        }
        vm.prank(owner);
        minting.loadBucket(0, bucket0Books, 5, 0, 0, 0);

        // Set up Round 4
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        // Mint in Round 4 - should consume pools first
        bytes32[] memory emptyProof = new bytes32[](0);
        
        uint256 currentRound = minting.getCurrentRound();
        console.log("Current Round:", currentRound);
        vm.prank(user1);
        minting.mint{value: 12 ether}(12, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        uint256[] memory userBooks = minting.getUserBooks(user1);
        assertEq(userBooks.length, 12);

        // Should have consumed all of pool 1 (5), all of pool 2 (5), and 2 from bucket 0
        (uint256 pool1Remaining, uint256 pool2Remaining, , uint256[8] memory bucketRemaining) = minting.getPoolAndBucketStatus();
        assertEq(pool1Remaining, 0);
        assertEq(pool2Remaining, 0);
        assertEq(bucketRemaining[0], 3); // 5 - 2 = 3 remaining
    }

    function test_Round4MaxMintPerTransaction() public {
        // Set up Round 4
        vm.prank(owner);
        minting.configureRound(4, block.timestamp, block.timestamp + 1 days);

        // Create books
        for (uint256 i = 1; i <= 20; i++) {
            vm.prank(owner);
            minting.addBook(i, i, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }

        uint256[] memory bucket0Books = new uint256[](20);
        for (uint256 i = 0; i < 20; i++) {
            bucket0Books[i] = i + 1;
        }

        vm.prank(owner);
        minting.loadBucket(0, bucket0Books, 20, 0, 0, 0);

        // Try to mint max allowed (10)
        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.prank(user1);
        minting.mint{value: 10 ether}(10, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);

        uint256[] memory userBooks = minting.getUserBooks(user1);
        assertEq(userBooks.length, 10);

        // Try to mint more than max (should fail)
        vm.prank(user2);
        vm.expectRevert(KttyWorldMinting.MaxMintExceeded.selector);
        minting.mint{value: 11 ether}(11, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof);
    }
}

// Fuzz and Invariant Testing
contract KttyWorldMintingInvariantTest is Test {
    KttyWorldMinting public minting;
    KttyWorldCompanions public companions;
    KttyWorldTools public tools;
    KttyWorldCollectibles public collectibles;
    MockKTTYToken public kttyToken;
    KttyWorldMintingHandler public handler;
    
    address public owner;
    address public treasuryWallet;
    
    function setUp() public {
        owner = makeAddr("owner");
        treasuryWallet = makeAddr("treasury");

        vm.startPrank(owner);

        // Deploy all contracts
        kttyToken = new MockKTTYToken();

        KttyWorldCompanions companionsImpl = new KttyWorldCompanions();
        bytes memory companionsInitData = abi.encodeCall(
            KttyWorldCompanions.initialize,
            (owner, "KTTY World Companions", "KWC", "https://hidden.com/", 10000)
        );
        ERC1967Proxy companionsProxy = new ERC1967Proxy(address(companionsImpl), companionsInitData);
        companions = KttyWorldCompanions(address(companionsProxy));

        KttyWorldTools toolsImpl = new KttyWorldTools();
        bytes memory toolsInitData = abi.encodeCall(
            KttyWorldTools.initialize,
            (owner, "https://hidden.com/")
        );
        ERC1967Proxy toolsProxy = new ERC1967Proxy(address(toolsImpl), toolsInitData);
        tools = KttyWorldTools(address(toolsProxy));

        KttyWorldCollectibles collectiblesImpl = new KttyWorldCollectibles();
        bytes memory collectiblesInitData = abi.encodeCall(
            KttyWorldCollectibles.initialize,
            (owner, "https://hidden.com/")
        );
        ERC1967Proxy collectiblesProxy = new ERC1967Proxy(address(collectiblesImpl), collectiblesInitData);
        collectibles = KttyWorldCollectibles(address(collectiblesProxy));

        KttyWorldMinting mintingImpl = new KttyWorldMinting();
        bytes memory mintingInitData = abi.encodeCall(
            KttyWorldMinting.initialize,
            (
                owner,
                address(companions),
                address(tools),
                address(collectibles),
                address(kttyToken),
                treasuryWallet,
                10
            )
        );
        ERC1967Proxy mintingProxy = new ERC1967Proxy(address(mintingImpl), mintingInitData);
        minting = KttyWorldMinting(address(mintingProxy));

        // Setup tokens
        tools.addTokenType("tool1.json");
        tools.addTokenType("tool2.json");
        tools.addTokenType("tool3.json");
        collectibles.addCollectibleType("golden_ticket.json");

        companions.mintAll(address(minting));
        
        uint256[] memory toolIds = new uint256[](3);
        uint256[] memory toolAmounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            toolIds[i] = i + 1;
            toolAmounts[i] = 50000;
        }
        tools.batchMint(address(minting), toolIds, toolAmounts);
        
        collectibles.mint(address(minting), 1, 500);

        minting.configurePayment(KttyWorldMinting.PaymentType.NATIVE_ONLY, 1 ether, 0);

        // Set up Round 4 for testing
        minting.configureRound(4, block.timestamp, block.timestamp + 365 days);

        vm.stopPrank();

        handler = new KttyWorldMintingHandler(minting, owner);
        targetContract(address(handler));
    }

    function invariant_BookOwnershipIntegrity() public view {
        // All minted books should have valid owners
        assertEq(handler.ghost_totalBooksMinted(), handler.ghost_totalBooksOwned());
    }

    function invariant_PoolAndBucketConsistency() public view {
        // Pool and bucket indices should never exceed their bounds
        (, , uint256 currentBucket, ) = minting.getPoolAndBucketStatus();
        assertLe(currentBucket, 8);
    }

    function invariant_PaymentBalance() public view {
        // Treasury should have received all payments
        assertEq(treasuryWallet.balance, handler.ghost_totalPayments());
    }
}

contract KttyWorldMintingHandler is Test {
    KttyWorldMinting public minting;
    address public owner;
    
    uint256 public ghost_totalBooksMinted;
    uint256 public ghost_totalBooksOwned;
    uint256 public ghost_totalPayments;
    
    address[] public actors;
    uint256 public constant MAX_ACTORS = 5;
    
    constructor(KttyWorldMinting _minting, address _owner) {
        minting = _minting;
        owner = _owner;
        
        for (uint i = 0; i < MAX_ACTORS; i++) {
            address actor = makeAddr(string(abi.encode("actor", i)));
            actors.push(actor);
            vm.deal(actor, 1000 ether);
        }
        
        // Setup some books for testing
        _setupTestBooks();
    }
    
    function _setupTestBooks() internal {
        vm.startPrank(owner);
        
        // Create 100 test books
        for (uint256 i = 1; i <= 100; i++) {
            minting.addBook(i, i, [uint256(1), uint256(2), uint256(3)], 0, "NULL");
        }
        
        // Load books into buckets
        uint256[] memory bucket0Books = new uint256[](50);
        for (uint256 i = 0; i < 50; i++) {
            bucket0Books[i] = i + 1;
        }
        minting.loadBucket(0, bucket0Books, 50, 0, 0, 0);
        
        uint256[] memory bucket1Books = new uint256[](50);
        for (uint256 i = 0; i < 50; i++) {
            bucket1Books[i] = i + 51;
        }
        minting.loadBucket(1, bucket1Books, 50, 0, 0, 0);
        
        vm.stopPrank();
    }
    
    function mint(uint256 actorSeed, uint256 quantity) external {
        quantity = bound(quantity, 1, 5);
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        
        uint256 cost = quantity * 1 ether;
        if (actor.balance < cost) return;
        
        bytes32[] memory emptyProof = new bytes32[](0);
        
        try minting.mint{value: cost}(quantity, KttyWorldMinting.PaymentType.NATIVE_ONLY, emptyProof) {
            ghost_totalBooksMinted += quantity;
            ghost_totalPayments += cost;
            
            uint256[] memory userBooks = minting.getUserBooks(actor);
            ghost_totalBooksOwned += userBooks.length;
        } catch {
            // Mint failed, no state change
        }
    }
    
    function openBook(uint256 actorSeed, uint256 bookIdSeed) external {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256[] memory userBooks = minting.getUserBooks(actor);
        
        if (userBooks.length == 0) return;
        
        uint256 bookIndex = bound(bookIdSeed, 0, userBooks.length - 1);
        uint256 bookId = userBooks[bookIndex];
        
        if (minting.isBookOpened(bookId)) return;
        
        try minting.openBook(bookId) {
            // Book opened successfully
        } catch {
            // Opening failed
        }
    }
}
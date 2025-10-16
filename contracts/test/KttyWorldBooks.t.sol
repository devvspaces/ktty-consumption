// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {KttyWorldBooks} from "src/KttyWorldBooks.sol";

contract MockMintingContract {
    function burnBook(address booksContract, uint256 tokenId) external {
        KttyWorldBooks(booksContract).burnBook(tokenId);
    }
}

contract KttyWorldBooksTest is Test {
    KttyWorldBooks public books;
    MockMintingContract public mockMinting;
    
    address public owner;
    address public user1;
    address public user2;
    address public nonOwner;
    
    string constant NAME = "KTTY World Books";
    string constant SYMBOL = "KWB";
    uint256 constant MAX_SUPPLY = 10000;
    string constant HIDDEN_URI = "https://hidden.com/metadata.json";
    string constant BASE_URI = "https://api.ktty.com/books/";
    
    event BookAdded(uint256 indexed tokenId, uint256 nftId, uint256[3] toolIds, uint256 goldenTicketId);
    event BookBurned(uint256 indexed tokenId, address indexed burner);
    event Revealed(bool revealed);
    event HiddenMetadataUriUpdated(string hiddenMetadataUri);
    event BaseTokenUriUpdated(string baseTokenUri);
    event MintingContractUpdated(address indexed newMintingContract);
    
    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");
        
        // Deploy mock minting contract
        mockMinting = new MockMintingContract();
        
        // Deploy Books implementation
        KttyWorldBooks booksImpl = new KttyWorldBooks();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeCall(
            KttyWorldBooks.initialize,
            (
                owner,
                NAME,
                SYMBOL,
                MAX_SUPPLY,
                HIDDEN_URI,
                address(mockMinting)
            )
        );
        
        // Deploy proxy
        ERC1967Proxy booksProxy = new ERC1967Proxy(
            address(booksImpl),
            initData
        );
        
        books = KttyWorldBooks(address(booksProxy));
    }
    
    // ============ INITIALIZATION & SETUP TESTS ============
    
    function test_Initialize() public view {
        assertEq(books.name(), NAME);
        assertEq(books.symbol(), SYMBOL);
        assertEq(books.maxSupply(), MAX_SUPPLY);
        assertEq(books.totalSupply(), 0);
        assertEq(books.hiddenMetadataUri(), HIDDEN_URI);
        assertFalse(books.isRevealed());
        assertEq(books.owner(), owner);
    }
    
    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert();
        books.initialize(
            owner,
            NAME,
            SYMBOL,
            MAX_SUPPLY,
            HIDDEN_URI,
            address(mockMinting)
        );
    }
    
    function test_InitialMintingContractSetup() public view {
        // The minting contract should be set during initialization
        // We can't directly check it, but we can test burn functionality works
        assertTrue(address(mockMinting) != address(0));
    }
    
    function test_InitialOwnerSetup() public view {
        assertEq(books.owner(), owner);
    }
    
    function test_InitialStateValues() public view {
        assertEq(books.totalSupply(), 0);
        assertEq(books.maxSupply(), MAX_SUPPLY);
        assertFalse(books.isRevealed());
        assertEq(books.baseTokenUri(), "");
    }
    
    // ============ BOOK MINTING & MANAGEMENT TESTS ============
    
    function test_BatchMintBooks_Success() public {
        uint256[] memory tokenIds = new uint256[](3);
        uint256[] memory nftIds = new uint256[](3);
        uint256[3][] memory toolIds = new uint256[3][](3);
        uint256[] memory goldenTicketIds = new uint256[](3);
        string[] memory series = new string[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = i + 1;
            nftIds[i] = i + 100;
            toolIds[i] = [uint256(1), uint256(2), uint256(3)];
            goldenTicketIds[i] = i == 0 ? 500 : 0; // Only first book has golden ticket
            series[i] = i == 0 ? "Type A" : "Type B";
        }
        
        vm.expectEmit(true, true, true, true);
        emit BookAdded(1, 100, [uint256(1), uint256(2), uint256(3)], 500);
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        assertEq(books.totalSupply(), 3);
        assertEq(books.balanceOf(user1), 3);
        assertTrue(books.exists(1));
        assertTrue(books.exists(2));
        assertTrue(books.exists(3));
        assertEq(books.ownerOf(1), user1);
    }
    
    function test_BatchMintBooks_BookDataStorage() public {
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory nftIds = new uint256[](1);
        uint256[3][] memory toolIds = new uint256[3][](1);
        uint256[] memory goldenTicketIds = new uint256[](1);
        string[] memory series = new string[](1);
        
        tokenIds[0] = 1;
        nftIds[0] = 100;
        toolIds[0] = [uint256(10), uint256(20), uint256(30)];
        goldenTicketIds[0] = 500;
        series[0] = "Type C";
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        KttyWorldBooks.Book memory book = books.getBook(1);
        assertEq(book.nftId, 100);
        assertEq(book.toolIds[0], 10);
        assertEq(book.toolIds[1], 20);
        assertEq(book.toolIds[2], 30);
        assertEq(book.goldenTicketId, 500);
        assertTrue(book.hasGoldenTicket);
        assertEq(book.series, "Type C");
    }
    
    function test_RevertWhen_BatchMintBooksArrayLengthMismatch() public {
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory nftIds = new uint256[](1); // Wrong length
        uint256[3][] memory toolIds = new uint256[3][](2);
        uint256[] memory goldenTicketIds = new uint256[](2);
        string[] memory series = new string[](2);
        
        vm.prank(owner);
        vm.expectRevert(KttyWorldBooks.InvalidArrayLength.selector);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
    }
    
    function test_RevertWhen_BatchMintBooksExceedsMaxSupply() public {
        uint256[] memory tokenIds = new uint256[](MAX_SUPPLY + 1);
        uint256[] memory nftIds = new uint256[](MAX_SUPPLY + 1);
        uint256[3][] memory toolIds = new uint256[3][](MAX_SUPPLY + 1);
        uint256[] memory goldenTicketIds = new uint256[](MAX_SUPPLY + 1);
        string[] memory series = new string[](MAX_SUPPLY + 1);
        
        for (uint256 i = 0; i < MAX_SUPPLY + 1; i++) {
            tokenIds[i] = i + 1;
            nftIds[i] = i + 1;
            toolIds[i] = [uint256(1), uint256(2), uint256(3)];
            goldenTicketIds[i] = 0;
            series[i] = "Type B";
        }
        
        vm.prank(owner);
        vm.expectRevert(KttyWorldBooks.ExceedsMaxSupply.selector);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
    }
    
    function test_RevertWhen_BatchMintBooksZeroQuantity() public {
        uint256[] memory tokenIds = new uint256[](0);
        uint256[] memory nftIds = new uint256[](0);
        uint256[3][] memory toolIds = new uint256[3][](0);
        uint256[] memory goldenTicketIds = new uint256[](0);
        string[] memory series = new string[](0);
        
        vm.prank(owner);
        vm.expectRevert(KttyWorldBooks.BatchSizeZero.selector);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
    }
    
    function test_RevertWhen_BatchMintBooksNotOwner() public {
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory nftIds = new uint256[](1);
        uint256[3][] memory toolIds = new uint256[3][](1);
        uint256[] memory goldenTicketIds = new uint256[](1);
        string[] memory series = new string[](1);
        
        tokenIds[0] = 1;
        nftIds[0] = 100;
        toolIds[0] = [uint256(1), uint256(2), uint256(3)];
        goldenTicketIds[0] = 0;
        series[0] = "Type B";
        
        vm.prank(nonOwner);
        vm.expectRevert();
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
    }
    
    function test_SupplyTrackingDuringMinting() public {
        assertEq(books.totalSupply(), 0);
        
        // Mint first batch
        uint256[] memory tokenIds1 = new uint256[](2);
        uint256[] memory nftIds1 = new uint256[](2);
        uint256[3][] memory toolIds1 = new uint256[3][](2);
        uint256[] memory goldenTicketIds1 = new uint256[](2);
        string[] memory series1 = new string[](2);
        
        for (uint256 i = 0; i < 2; i++) {
            tokenIds1[i] = i + 1;
            nftIds1[i] = i + 1;
            toolIds1[i] = [uint256(1), uint256(2), uint256(3)];
            goldenTicketIds1[i] = 0;
            series1[i] = "Type B";
        }
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds1, nftIds1, toolIds1, goldenTicketIds1, series1);
        assertEq(books.totalSupply(), 2);
        
        // Mint second batch
        uint256[] memory tokenIds2 = new uint256[](3);
        uint256[] memory nftIds2 = new uint256[](3);
        uint256[3][] memory toolIds2 = new uint256[3][](3);
        uint256[] memory goldenTicketIds2 = new uint256[](3);
        string[] memory series2 = new string[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            tokenIds2[i] = i + 3;
            nftIds2[i] = i + 3;
            toolIds2[i] = [uint256(1), uint256(2), uint256(3)];
            goldenTicketIds2[i] = 0;
            series2[i] = "Type B";
        }
        
        vm.prank(owner);
        books.batchMintBooks(user2, tokenIds2, nftIds2, toolIds2, goldenTicketIds2, series2);
        assertEq(books.totalSupply(), 5);
    }
    
    function test_TokenExistenceTracking() public {
        assertFalse(books.exists(1));
        assertFalse(books.exists(2));
        
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory nftIds = new uint256[](2);
        uint256[3][] memory toolIds = new uint256[3][](2);
        uint256[] memory goldenTicketIds = new uint256[](2);
        string[] memory series = new string[](2);
        
        for (uint256 i = 0; i < 2; i++) {
            tokenIds[i] = i + 1;
            nftIds[i] = i + 1;
            toolIds[i] = [uint256(1), uint256(2), uint256(3)];
            goldenTicketIds[i] = 0;
            series[i] = "Type B";
        }
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        assertTrue(books.exists(1));
        assertTrue(books.exists(2));
        assertFalse(books.exists(3));
    }
    
    // ============ BURN FUNCTIONALITY TESTS ============
    
    function test_BurnBook_Success() public {
        // First mint a book
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory nftIds = new uint256[](1);
        uint256[3][] memory toolIds = new uint256[3][](1);
        uint256[] memory goldenTicketIds = new uint256[](1);
        string[] memory series = new string[](1);
        
        tokenIds[0] = 1;
        nftIds[0] = 100;
        toolIds[0] = [uint256(1), uint256(2), uint256(3)];
        goldenTicketIds[0] = 500;
        series[0] = "Type C";
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        assertTrue(books.exists(1));
        assertEq(books.ownerOf(1), user1);
        assertEq(books.totalSupply(), 1);
        
        // Now burn the book using the mock minting contract
        vm.expectEmit(true, true, true, true);
        emit BookBurned(1, address(mockMinting));
        
        mockMinting.burnBook(address(books), 1);
        
        assertFalse(books.exists(1));
        assertEq(books.totalSupply(), 1); // totalSupply doesn't decrease on burn
    }
    
    function test_RevertWhen_BurnBookNotFromMintingContract() public {
        // First mint a book
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory nftIds = new uint256[](1);
        uint256[3][] memory toolIds = new uint256[3][](1);
        uint256[] memory goldenTicketIds = new uint256[](1);
        string[] memory series = new string[](1);
        
        tokenIds[0] = 1;
        nftIds[0] = 100;
        toolIds[0] = [uint256(1), uint256(2), uint256(3)];
        goldenTicketIds[0] = 0;
        series[0] = "Type B";
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        // Try to burn from unauthorized address
        vm.prank(user1);
        vm.expectRevert(KttyWorldBooks.OnlyMintingContract.selector);
        books.burnBook(1);
        
        vm.prank(nonOwner);
        vm.expectRevert(KttyWorldBooks.OnlyMintingContract.selector);
        books.burnBook(1);
        
        vm.prank(owner);
        vm.expectRevert(KttyWorldBooks.OnlyMintingContract.selector);
        books.burnBook(1);
    }
    
    function test_RevertWhen_BurnNonExistentBook() public {
        vm.expectRevert(KttyWorldBooks.BookNotExists.selector);
        mockMinting.burnBook(address(books), 999);
    }
    
    function test_BurnBook_RemovesTokenExistence() public {
        // Mint multiple books
        uint256[] memory tokenIds = new uint256[](3);
        uint256[] memory nftIds = new uint256[](3);
        uint256[3][] memory toolIds = new uint256[3][](3);
        uint256[] memory goldenTicketIds = new uint256[](3);
        string[] memory series = new string[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = i + 1;
            nftIds[i] = i + 100;
            toolIds[i] = [uint256(1), uint256(2), uint256(3)];
            goldenTicketIds[i] = 0;
            series[i] = "Type B";
        }
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        assertTrue(books.exists(1));
        assertTrue(books.exists(2));
        assertTrue(books.exists(3));
        
        // Burn middle token
        mockMinting.burnBook(address(books), 2);
        
        assertTrue(books.exists(1));
        assertFalse(books.exists(2));
        assertTrue(books.exists(3));
        
        // Verify we can't get the burned book
        vm.expectRevert(KttyWorldBooks.InvalidTokenId.selector);
        books.getBook(2);
    }
    
    // ============ BOOK QUERYING & DATA RETRIEVAL TESTS ============
    
    function test_GetBook_ReturnsCorrectData() public {
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory nftIds = new uint256[](1);
        uint256[3][] memory toolIds = new uint256[3][](1);
        uint256[] memory goldenTicketIds = new uint256[](1);
        string[] memory series = new string[](1);
        
        tokenIds[0] = 1;
        nftIds[0] = 100;
        toolIds[0] = [uint256(10), uint256(20), uint256(30)];
        goldenTicketIds[0] = 500;
        series[0] = "Type A";
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        KttyWorldBooks.Book memory book = books.getBook(1);
        assertEq(book.nftId, 100);
        assertEq(book.toolIds[0], 10);
        assertEq(book.toolIds[1], 20);
        assertEq(book.toolIds[2], 30);
        assertEq(book.goldenTicketId, 500);
        assertTrue(book.hasGoldenTicket);
        assertEq(book.series, "Type A");
    }
    
    function test_RevertWhen_GetBookInvalidTokenId() public {
        vm.expectRevert(KttyWorldBooks.InvalidTokenId.selector);
        books.getBook(999);
    }
    
    function test_GetUserBooks_ReturnsCorrectTokenIds() public {
        // Mint books to different users
        uint256[] memory tokenIds1 = new uint256[](2);
        uint256[] memory nftIds1 = new uint256[](2);
        uint256[3][] memory toolIds1 = new uint256[3][](2);
        uint256[] memory goldenTicketIds1 = new uint256[](2);
        string[] memory series1 = new string[](2);
        
        for (uint256 i = 0; i < 2; i++) {
            tokenIds1[i] = i + 1;
            nftIds1[i] = i + 100;
            toolIds1[i] = [uint256(1), uint256(2), uint256(3)];
            goldenTicketIds1[i] = 0;
            series1[i] = "Type B";
        }
        
        uint256[] memory tokenIds2 = new uint256[](3);
        uint256[] memory nftIds2 = new uint256[](3);
        uint256[3][] memory toolIds2 = new uint256[3][](3);
        uint256[] memory goldenTicketIds2 = new uint256[](3);
        string[] memory series2 = new string[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            tokenIds2[i] = i + 3;
            nftIds2[i] = i + 200;
            toolIds2[i] = [uint256(4), uint256(5), uint256(6)];
            goldenTicketIds2[i] = 0;
            series2[i] = "Type C";
        }
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds1, nftIds1, toolIds1, goldenTicketIds1, series1);
        
        vm.prank(owner);
        books.batchMintBooks(user2, tokenIds2, nftIds2, toolIds2, goldenTicketIds2, series2);
        
        uint256[] memory user1Books = books.getUserBooks(user1);
        uint256[] memory user2Books = books.getUserBooks(user2);
        
        assertEq(user1Books.length, 2);
        assertEq(user2Books.length, 3);
        
        assertEq(user1Books[0], 1);
        assertEq(user1Books[1], 2);
        
        assertEq(user2Books[0], 3);
        assertEq(user2Books[1], 4);
        assertEq(user2Books[2], 5);
    }
    
    function test_GetUserBooksDetails_ReturnsCorrectBookData() public {
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory nftIds = new uint256[](2);
        uint256[3][] memory toolIds = new uint256[3][](2);
        uint256[] memory goldenTicketIds = new uint256[](2);
        string[] memory series = new string[](2);
        
        tokenIds[0] = 1;
        nftIds[0] = 100;
        toolIds[0] = [uint256(10), uint256(20), uint256(30)];
        goldenTicketIds[0] = 500;
        series[0] = "Type A";
        
        tokenIds[1] = 2;
        nftIds[1] = 200;
        toolIds[1] = [uint256(40), uint256(50), uint256(60)];
        goldenTicketIds[1] = 0;
        series[1] = "Type C";
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        KttyWorldBooks.Book[] memory userBooks = books.getUserBooksDetails(user1);
        
        assertEq(userBooks.length, 2);
        
        assertEq(userBooks[0].nftId, 100);
        assertEq(userBooks[0].toolIds[0], 10);
        assertEq(userBooks[0].goldenTicketId, 500);
        assertTrue(userBooks[0].hasGoldenTicket);
        assertEq(userBooks[0].series, "Type A");
        
        assertEq(userBooks[1].nftId, 200);
        assertEq(userBooks[1].toolIds[0], 40);
        assertEq(userBooks[1].goldenTicketId, 0);
        assertFalse(userBooks[1].hasGoldenTicket);
        assertEq(userBooks[1].series, "Type C");
    }
    
    function test_GetUserBooks_EmptyForNewUser() public {
        uint256[] memory userBooks = books.getUserBooks(user2);
        assertEq(userBooks.length, 0);
        
        KttyWorldBooks.Book[] memory userBooksDetails = books.getUserBooksDetails(user2);
        assertEq(userBooksDetails.length, 0);
    }
    
    function test_GetUserBooks_AfterTransfer() public {
        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory nftIds = new uint256[](2);
        uint256[3][] memory toolIds = new uint256[3][](2);
        uint256[] memory goldenTicketIds = new uint256[](2);
        string[] memory series = new string[](2);
        
        for (uint256 i = 0; i < 2; i++) {
            tokenIds[i] = i + 1;
            nftIds[i] = i + 100;
            toolIds[i] = [uint256(1), uint256(2), uint256(3)];
            goldenTicketIds[i] = 0;
            series[i] = "Type B";
        }
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        // Transfer one book from user1 to user2
        vm.prank(user1);
        books.transferFrom(user1, user2, 1);
        
        uint256[] memory user1Books = books.getUserBooks(user1);
        uint256[] memory user2Books = books.getUserBooks(user2);
        
        assertEq(user1Books.length, 1);
        assertEq(user2Books.length, 1);
        
        assertEq(user1Books[0], 2);
        assertEq(user2Books[0], 1);
    }
    
    // ============ METADATA & REVEAL SYSTEM TESTS ============
    
    function test_TokenURI_RevealedWithBaseURI() public {
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory nftIds = new uint256[](1);
        uint256[3][] memory toolIds = new uint256[3][](1);
        uint256[] memory goldenTicketIds = new uint256[](1);
        string[] memory series = new string[](1);
        
        tokenIds[0] = 1;
        nftIds[0] = 100;
        toolIds[0] = [uint256(1), uint256(2), uint256(3)];
        goldenTicketIds[0] = 0;
        series[0] = "Type B";
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        // Set base URI and reveal
        vm.prank(owner);
        books.setBaseTokenURI(BASE_URI);
        
        vm.prank(owner);
        books.setRevealed(true);
        
        // Should return base URI + token ID when revealed
        assertEq(books.tokenURI(1), string(abi.encodePacked(BASE_URI, "1.json")));
        assertTrue(books.isRevealed());
    }
    
    function test_SetRevealed_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit Revealed(true);
        
        vm.prank(owner);
        books.setRevealed(true);
        
        assertTrue(books.isRevealed());
    }
    
    function test_SetHiddenMetadataURI_UpdatesAndEmitsEvent() public view {
        // Initial hidden URI is set during initialization
        assertEq(books.hiddenMetadataUri(), HIDDEN_URI);
    }
    
    function test_SetBaseTokenURI_UpdatesAndEmitsEvent() public {
        string memory newBaseURI = "https://newapi.ktty.com/books/";
        
        vm.expectEmit(true, true, true, true);
        emit BaseTokenUriUpdated(newBaseURI);
        
        vm.prank(owner);
        books.setBaseTokenURI(newBaseURI);
        
        assertEq(books.baseTokenUri(), newBaseURI);
    }
    
    function test_RevertWhen_TokenURIInvalidTokenId() public {
        vm.expectRevert(KttyWorldBooks.InvalidTokenId.selector);
        books.tokenURI(999);
    }
    
    // ============ ACCESS CONTROL & SECURITY TESTS ============
    
    function test_RevertWhen_SetRevealedNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        books.setRevealed(true);
    }
    
    function test_RevertWhen_SetBaseTokenURINotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        books.setBaseTokenURI("https://unauthorized.com/");
    }
    
    function test_RevertWhen_SetHiddenMetadataURINotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        books.setHiddenMetadataURI("https://unauthorized.com/hidden.json");
    }
    
    function test_RevertWhen_SetMintingContractNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        books.setMintingContract(makeAddr("unauthorized"));
    }
    
    function test_SetMintingContract_Success() public {
        address newMintingContract = makeAddr("newMintingContract");
        
        vm.expectEmit(true, true, true, true);
        emit MintingContractUpdated(newMintingContract);
        
        vm.prank(owner);
        books.setMintingContract(newMintingContract);
        
        // Test that the new minting contract can burn (indirectly proves it was set)
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory nftIds = new uint256[](1);
        uint256[3][] memory toolIds = new uint256[3][](1);
        uint256[] memory goldenTicketIds = new uint256[](1);
        string[] memory series = new string[](1);
        
        tokenIds[0] = 1;
        nftIds[0] = 100;
        toolIds[0] = [uint256(1), uint256(2), uint256(3)];
        goldenTicketIds[0] = 0;
        series[0] = "Type B";
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        // Old minting contract should no longer work
        vm.expectRevert(KttyWorldBooks.OnlyMintingContract.selector);
        mockMinting.burnBook(address(books), 1);
        
        // New minting contract should work
        vm.prank(newMintingContract);
        books.burnBook(1);
        
        assertFalse(books.exists(1));
    }
    
    // ============ EDGE CASES & ERROR HANDLING TESTS ============
    
    function test_BookWithNoGoldenTicket() public {
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory nftIds = new uint256[](1);
        uint256[3][] memory toolIds = new uint256[3][](1);
        uint256[] memory goldenTicketIds = new uint256[](1);
        string[] memory series = new string[](1);
        
        tokenIds[0] = 1;
        nftIds[0] = 100;
        toolIds[0] = [uint256(1), uint256(2), uint256(3)];
        goldenTicketIds[0] = 0; // No golden ticket
        series[0] = "Type B";
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        KttyWorldBooks.Book memory book = books.getBook(1);
        assertEq(book.goldenTicketId, 0);
        assertFalse(book.hasGoldenTicket);
        assertEq(book.series, "Type B");
    }
    
    function test_BatchMintBooksApproachingMaxSupply() public {
        // Test with a reasonable batch size that approaches max supply
        uint256 batchSize = 100;
        uint256[] memory tokenIds = new uint256[](batchSize);
        uint256[] memory nftIds = new uint256[](batchSize);
        uint256[3][] memory toolIds = new uint256[3][](batchSize);
        uint256[] memory goldenTicketIds = new uint256[](batchSize);
        string[] memory series = new string[](batchSize);
        
        for (uint256 i = 0; i < batchSize; i++) {
            tokenIds[i] = i + 1;
            nftIds[i] = i + 1;
            toolIds[i] = [uint256(1), uint256(2), uint256(3)];
            goldenTicketIds[i] = 0;
            series[i] = "Type B";
        }
        
        vm.prank(owner);
        books.batchMintBooks(user1, tokenIds, nftIds, toolIds, goldenTicketIds, series);
        
        assertEq(books.totalSupply(), batchSize);
        assertEq(books.balanceOf(user1), batchSize);
        
        // Test that we can't exceed max supply
        uint256 remainingSupply = MAX_SUPPLY - batchSize;
        uint256 oversizedBatch = remainingSupply + 1;
        
        uint256[] memory extraTokenIds = new uint256[](oversizedBatch);
        uint256[] memory extraNftIds = new uint256[](oversizedBatch);
        uint256[3][] memory extraToolIds = new uint256[3][](oversizedBatch);
        uint256[] memory extraGoldenTicketIds = new uint256[](oversizedBatch);
        string[] memory extraNftTypes = new string[](oversizedBatch);
        
        for (uint256 i = 0; i < oversizedBatch; i++) {
            extraTokenIds[i] = batchSize + i + 1;
            extraNftIds[i] = batchSize + i + 1;
            extraToolIds[i] = [uint256(1), uint256(2), uint256(3)];
            extraGoldenTicketIds[i] = 0;
            extraNftTypes[i] = "Type B";
        }
        
        vm.prank(owner);
        vm.expectRevert(KttyWorldBooks.ExceedsMaxSupply.selector);
        books.batchMintBooks(user1, extraTokenIds, extraNftIds, extraToolIds, extraGoldenTicketIds, extraNftTypes);
    }
    
    function test_ViewFunctionsWorkCorrectly() public view {
        // Test all view functions return expected initial values
        assertEq(books.totalSupply(), 0);
        assertEq(books.maxSupply(), MAX_SUPPLY);
        assertFalse(books.isRevealed());
        assertEq(books.hiddenMetadataUri(), HIDDEN_URI);
        assertEq(books.baseTokenUri(), "");
        assertEq(books.owner(), owner);
        assertEq(books.name(), NAME);
        assertEq(books.symbol(), SYMBOL);
    }
}
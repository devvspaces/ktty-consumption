// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {KttyWorldCompanions} from "./KttyWorldCompanions.sol";
import {KttyWorldTools} from "./KttyWorldTools.sol";
import {KttyWorldCollectibles} from "./KttyWorldCollectibles.sol";

/// @title KttyWorldMinting
/// @notice Main minting contract for KTTY World summoning books with complex round and bucket system
/// @dev UUPS upgradeable contract with namespaced storage
contract KttyWorldMinting is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IERC1155Receiver {
    
    /// @custom:storage-location erc7201:ktty.storage.KttyWorldMinting
    struct KttyWorldMintingStorage {
        // Contract references
        KttyWorldCompanions companions;
        KttyWorldTools tools;
        KttyWorldCollectibles collectibles;
        IERC20 kttyToken;
        
        // Global state
        uint256 currentRound;
        uint256 maxMintPerTransaction;
        address treasuryWallet;
        
        // Round configuration
        mapping(uint256 => Round) rounds;
        
        // Pool and bucket state
        Pool pool1;
        Pool pool2;
        Bucket[8] buckets;
        uint256 currentBucketIndex;
        
        // Book system
        mapping(uint256 => Book) books;
        uint256 nextBookId;
        
        // User tracking
        mapping(address => uint256[]) userBooks;
        mapping(uint256 => address) bookOwners;
        mapping(uint256 => bool) openedBooks;
        
        // Round 1 & 2 whitelist allowances
        mapping(uint256 => mapping(address => uint256)) roundAllowances;
        mapping(uint256 => mapping(address => uint256)) roundMinted;
        
        // Round 3 merkle root
        bytes32 round3MerkleRoot;
        
        // Payment configuration
        PaymentOption nativeOnlyPayment;
        PaymentOption hybridPayment;
    }

    // keccak256(abi.encode(uint256(keccak256("ktty.storage.KttyWorldMinting")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KTTY_WORLD_MINTING_STORAGE_LOCATION = 
        0x7d8c6f4e3a9b5c8f2e1a7d4c9f6e3a0b5c8f2e1a7d4c9f6e3a0b5c8f2e1a7d00;

    /// @notice Represents a summoning book containing NFT and tools
    struct Book {
        uint256 nftId;
        uint256[3] toolIds; // Always 3 tools
        uint256 goldenTicketId; // 0 if no golden ticket
        bool hasGoldenTicket;
        string nftType; // "NULL", "BASIC", "1/1"
    }

    /// @notice Represents a round configuration
    struct Round {
        uint256 startTime;
        uint256 endTime;
        RoundType roundType;
        bool active;
    }

    /// @notice Pool containing an array of book IDs
    struct Pool {
        uint256[] bookIds;
        uint256 currentIndex;
        bool exhausted;
    }

    /// @notice Bucket containing specialized book distributions
    struct Bucket {
        uint256[] bookIds;
        uint256 currentIndex;
        bool exhausted;
        uint256 nullNftCount;
        uint256 oneOfOneNftCount;
        uint256 goldenTicketCount;
        uint256 basicNftCount;
    }

    /// @notice Payment configuration for different options
    struct PaymentOption {
        uint256 nativeAmount;
        uint256 erc20Amount;
    }

    /// @notice Round types
    enum RoundType {
        MANUAL,     // Round 0
        WHITELIST,  // Round 1 & 2
        BUCKET,     // Round 3
        PUBLIC      // Round 4
    }

    /// @notice Payment types
    enum PaymentType {
        NATIVE_ONLY,
        HYBRID
    }

    // Events
    event BookAdded(uint256 indexed bookId, uint256 nftId, uint256[3] toolIds, uint256 goldenTicketId);
    event BooksMinted(uint256[] bookIds, address indexed buyer);
    event BookOpened(uint256 indexed bookId, address indexed owner);
    event RoundUpdated(uint256 indexed roundNumber, uint256 startTime, uint256 endTime);
    event PaymentConfigured(PaymentType paymentType, uint256 nativeAmount, uint256 erc20Amount);
    event TreasuryWalletUpdated(address indexed newWallet);
    event PoolLoaded(uint256 indexed poolNumber, uint256 bookCount);
    event BucketLoaded(uint256 indexed bucketIndex, uint256 bookCount);

    // Errors
    error InvalidRound();
    error RoundNotActive();
    error InsufficientAllowance();
    error MaxMintExceeded();
    error InsufficientPayment();
    error BookNotOwned();
    error BookAlreadyOpened();
    error PoolExhausted();
    error InvalidProof();
    error InvalidPaymentType();
    error InvalidArrayLength();
    error TransferFailed();

    function _getKttyWorldMintingStorage() private pure returns (KttyWorldMintingStorage storage $) {
        assembly {
            $.slot := KTTY_WORLD_MINTING_STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _owner The owner of the contract
    /// @param _companions KttyWorldCompanions contract address
    /// @param _tools KttyWorldTools contract address
    /// @param _collectibles KttyWorldCollectibles contract address
    /// @param _kttyToken KTTY token contract address
    /// @param _treasuryWallet Wallet to receive payments
    function initialize(
        address _owner,
        address _companions,
        address _tools,
        address _collectibles,
        address _kttyToken,
        address _treasuryWallet,
        uint256 _maxMintPerTransaction
    ) public initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        $.companions = KttyWorldCompanions(_companions);
        $.tools = KttyWorldTools(_tools);
        $.collectibles = KttyWorldCollectibles(_collectibles);
        $.kttyToken = IERC20(_kttyToken);
        $.treasuryWallet = _treasuryWallet;
        $.maxMintPerTransaction = _maxMintPerTransaction;
        $.currentRound = 0;
        $.nextBookId = 1;

        // Pools are exhausted by default until loaded
        $.pool1.exhausted = true;
        $.pool2.exhausted = true;

        // Initialize rounds
        _initializeRounds();
    }

    /// @dev Initialize default round configuration
    function _initializeRounds() internal {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        // Round 0: Manual (always active for manual operations)
        $.rounds[0] = Round({
            startTime: block.timestamp,
            endTime: type(uint256).max,
            roundType: RoundType.MANUAL,
            active: true
        });

        // Rounds 1-4 will be configured by owner
        for (uint256 i = 1; i <= 4; i++) {
            $.rounds[i] = Round({
                startTime: 0,
                endTime: 0,
                roundType: i <= 2 ? RoundType.WHITELIST : (i == 3 ? RoundType.BUCKET : RoundType.PUBLIC),
                active: false
            });
        }
    }

    /// @notice Get current active round
    /// @return Current round number
    function getCurrentRound() public view returns (uint256) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        // Check rounds in order
        for (uint256 i = 1; i <= 4; i++) {
            Round memory round = $.rounds[i];
            if (round.active && block.timestamp >= round.startTime && block.timestamp <= round.endTime) {
                return i;
            }
        }
        
        return 0; // Default to manual round
    }

    /// @notice Check if an address is whitelisted for round 1 or 2
    /// @param round Round number (1 or 2)
    /// @param user User address
    /// @return allowance Number of mints allowed
    /// @return minted Number already minted
    function getWhitelistStatus(uint256 round, address user) external view returns (uint256 allowance, uint256 minted) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        allowance = $.roundAllowances[round][user];
        minted = $.roundMinted[round][user];
    }

    /// @notice Check if an address is whitelisted for round 3 using merkle proof
    /// @param user User address
    /// @param proof Merkle proof
    /// @return Whether user is whitelisted for round 3
    function isWhitelistedForRound3(address user, bytes32[] calldata proof) external view returns (bool) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        bytes32 leaf = keccak256(abi.encodePacked(user));
        return MerkleProof.verify(proof, $.round3MerkleRoot, leaf);
    }

    /// @notice Get books owned by a user
    /// @param user User address
    /// @return Array of book IDs owned by the user
    function getUserBooks(address user) external view returns (uint256[] memory) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.userBooks[user];
    }

    /// @notice Get book details
    /// @param bookId Book ID
    /// @return Book struct containing book details
    function getBook(uint256 bookId) external view returns (Book memory) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.books[bookId];
    }

    /// @notice Check if book has been opened
    /// @param bookId Book ID
    /// @return Whether the book has been opened
    function isBookOpened(uint256 bookId) external view returns (bool) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.openedBooks[bookId];
    }

    /// @notice Get current pool and bucket status
    /// @return pool1Remaining Number of books remaining in pool 1
    /// @return pool2Remaining Number of books remaining in pool 2
    /// @return currentBucket Current bucket index
    /// @return bucketRemaining Array of remaining books in each bucket
    function getPoolAndBucketStatus() external view returns (
        uint256 pool1Remaining,
        uint256 pool2Remaining,
        uint256 currentBucket,
        uint256[8] memory bucketRemaining
    ) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        pool1Remaining = $.pool1.exhausted ? 0 : $.pool1.bookIds.length - $.pool1.currentIndex;
        pool2Remaining = $.pool2.exhausted ? 0 : $.pool2.bookIds.length - $.pool2.currentIndex;
        currentBucket = $.currentBucketIndex;
        
        for (uint256 i = 0; i < 8; i++) {
            bucketRemaining[i] = $.buckets[i].exhausted ? 0 : $.buckets[i].bookIds.length - $.buckets[i].currentIndex;
        }
    }

    /// @notice Get payment configuration
    /// @return nativeOnly Native-only payment option configuration
    /// @return hybrid Hybrid payment option configuration
    function getPaymentConfig() external view returns (PaymentOption memory nativeOnly, PaymentOption memory hybrid) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        nativeOnly = $.nativeOnlyPayment;
        hybrid = $.hybridPayment;
    }

    /// @notice Configure round times and activation
    /// @param roundNumber Round number (1-4)
    /// @param startTime Round start timestamp
    /// @param endTime Round end timestamp
    function configureRound(uint256 roundNumber, uint256 startTime, uint256 endTime) external onlyOwner {
        if (roundNumber == 0 || roundNumber > 4) revert InvalidRound();
        
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        $.rounds[roundNumber].startTime = startTime;
        $.rounds[roundNumber].endTime = endTime;
        $.rounds[roundNumber].active = true;
        
        emit RoundUpdated(roundNumber, startTime, endTime);
    }

    /// @notice Set whitelist allowances for rounds 1 and 2
    /// @param round Round number (1 or 2)
    /// @param users Array of user addresses
    /// @param allowances Array of mint allowances
    function setWhitelistAllowances(
        uint256 round,
        address[] calldata users,
        uint256[] calldata allowances
    ) external onlyOwner {
        if (round != 1 && round != 2) revert InvalidRound();
        if (users.length != allowances.length) revert();
        
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        for (uint256 i = 0; i < users.length; i++) {
            $.roundAllowances[round][users[i]] = allowances[i];
        }
    }

    /// @notice Set merkle root for round 3 whitelist
    /// @param merkleRoot Merkle root hash
    function setRound3MerkleRoot(bytes32 merkleRoot) external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        $.round3MerkleRoot = merkleRoot;
    }

    /// @notice Configure payment options
    /// @param paymentType Payment type (NATIVE_ONLY or HYBRID)
    /// @param nativeAmount Native token amount required
    /// @param erc20Amount ERC20 token amount required (only for HYBRID)
    function configurePayment(
        PaymentType paymentType,
        uint256 nativeAmount,
        uint256 erc20Amount
    ) external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        if (paymentType == PaymentType.NATIVE_ONLY) {
            $.nativeOnlyPayment = PaymentOption(nativeAmount, 0);
        } else if (paymentType == PaymentType.HYBRID) {
            $.hybridPayment = PaymentOption(nativeAmount, erc20Amount);
        } else {
            revert InvalidPaymentType();
        }
        
        emit PaymentConfigured(paymentType, nativeAmount, erc20Amount);
    }

    /// @notice Set treasury wallet address
    /// @param newWallet New treasury wallet address
    function setTreasuryWallet(address newWallet) external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        $.treasuryWallet = newWallet;
        emit TreasuryWalletUpdated(newWallet);
    }

    /// @notice Set maximum mint per transaction
    /// @param maxMint New maximum mint per transaction
    function setMaxMintPerTransaction(uint256 maxMint) external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        $.maxMintPerTransaction = maxMint;
    }

    /// @notice Load pool 1 books
    /// @param bookIds Array of book IDs for pool 1
    function loadPool1(uint256[] calldata bookIds) external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        $.pool1.bookIds = bookIds;
        $.pool1.currentIndex = 0;
        $.pool1.exhausted = false;
        emit PoolLoaded(1, bookIds.length);
    }

    /// @notice Load pool 2 books
    /// @param bookIds Array of book IDs for pool 2
    function loadPool2(uint256[] calldata bookIds) external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        $.pool2.bookIds = bookIds;
        $.pool2.currentIndex = 0;
        $.pool2.exhausted = false;
        emit PoolLoaded(2, bookIds.length);
    }

    /// @notice Load bucket books
    /// @param bucketIndex Bucket index (0-7)
    /// @param bookIds Array of book IDs for the bucket
    /// @param nullCount Number of NULL NFTs in bucket
    /// @param oneOfOneCount Number of 1/1 NFTs in bucket  
    /// @param goldenTicketCount Number of golden tickets in bucket
    /// @param basicCount Number of basic NFTs in bucket
    function loadBucket(
        uint256 bucketIndex,
        uint256[] calldata bookIds,
        uint256 nullCount,
        uint256 oneOfOneCount,
        uint256 goldenTicketCount,
        uint256 basicCount
    ) external onlyOwner {
        if (bucketIndex >= 8) revert InvalidRound();
        
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        $.buckets[bucketIndex] = Bucket({
            bookIds: bookIds,
            currentIndex: 0,
            exhausted: false,
            nullNftCount: nullCount,
            oneOfOneNftCount: oneOfOneCount,
            goldenTicketCount: goldenTicketCount,
            basicNftCount: basicCount
        });
        
        emit BucketLoaded(bucketIndex, bookIds.length);
    }

    /// @notice Add a book to the system
    /// @param bookId Book ID
    /// @param nftId NFT token ID
    /// @param toolIds Array of 3 tool token IDs
    /// @param goldenTicketId Golden ticket ID (0 if none)
    /// @param nftType NFT type ("NULL", "BASIC", "1/1")
    function addBook(
        uint256 bookId,
        uint256 nftId,
        uint256[3] calldata toolIds,
        uint256 goldenTicketId,
        string calldata nftType
    ) external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        $.books[bookId] = Book({
            nftId: nftId,
            toolIds: toolIds,
            goldenTicketId: goldenTicketId,
            hasGoldenTicket: goldenTicketId != 0,
            nftType: nftType
        });
        
        emit BookAdded(bookId, nftId, toolIds, goldenTicketId);
    }

    /// @notice Batch add multiple books
    /// @param bookIds Array of book IDs
    /// @param nftIds Array of NFT token IDs
    /// @param toolIds Array of tool ID arrays (each containing 3 tool IDs)
    /// @param goldenTicketIds Array of golden ticket IDs (0 if none)
    /// @param nftTypes Array of NFT types ("NULL", "BASIC", "1/1")
    function batchAddBooks(
        uint256[] calldata bookIds,
        uint256[] calldata nftIds,
        uint256[3][] calldata toolIds,
        uint256[] calldata goldenTicketIds,
        string[] calldata nftTypes
    ) external onlyOwner {
        if (bookIds.length != nftIds.length || 
            bookIds.length != toolIds.length || 
            bookIds.length != goldenTicketIds.length || 
            bookIds.length != nftTypes.length) {
            revert InvalidArrayLength();
        }
        
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        for (uint256 i = 0; i < bookIds.length; i++) {
            $.books[bookIds[i]] = Book({
                nftId: nftIds[i],
                toolIds: toolIds[i],
                goldenTicketId: goldenTicketIds[i],
                hasGoldenTicket: goldenTicketIds[i] != 0,
                nftType: nftTypes[i]
            });
            
            emit BookAdded(bookIds[i], nftIds[i], toolIds[i], goldenTicketIds[i]);
        }
    }

    /// @notice Manual airdrop for round 0
    /// @param tokenIds Array of NFT token IDs to send
    /// @param recipient Recipient address
    function manualAirdrop(uint256[] calldata tokenIds, address recipient) external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            try $.companions.transferFrom(address(this), recipient, tokenIds[i]) {
                // Transfer successful
            } catch {
                revert TransferFailed();
            }
        }
    }

    /// @notice Main minting function
    /// @param quantity Number of books to mint
    /// @param paymentType Payment type (NATIVE_ONLY or HYBRID)
    /// @param merkleProof Merkle proof for round 3 (empty for other rounds)
    function mint(
        uint256 quantity,
        PaymentType paymentType,
        bytes32[] calldata merkleProof
    ) external payable nonReentrant {
        if (quantity == 0 || quantity > _getMaxMintPerTransaction()) revert MaxMintExceeded();
        
        uint256 currentRound = getCurrentRound();
        _validateMintPermission(currentRound, quantity, merkleProof);
        _processPayment(paymentType, quantity);
        
        uint256[] memory mintedBookIds = _mintBooks(currentRound, quantity);
        _trackUserBooks(msg.sender, mintedBookIds);
        
        emit BooksMinted(mintedBookIds, msg.sender);
    }

    /// @notice Open/summon a book to receive its contents
    /// @param bookId Book ID to open
    function openBook(uint256 bookId) external nonReentrant {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        if ($.bookOwners[bookId] != msg.sender) revert BookNotOwned();
        if ($.openedBooks[bookId]) revert BookAlreadyOpened();
        
        $.openedBooks[bookId] = true;
        
        Book memory book = $.books[bookId];
        
        // Transfer NFT
        try $.companions.transferFrom(address(this), msg.sender, book.nftId) {
            // Transfer successful
        } catch {
            revert TransferFailed();
        }
        
        // Transfer tools
        for (uint256 i = 0; i < 3; i++) {
            $.tools.safeTransferFrom(address(this), msg.sender, book.toolIds[i], 1, "");
        }
        
        // Transfer golden ticket if present
        if (book.hasGoldenTicket) {
            $.collectibles.safeTransferFrom(address(this), msg.sender, book.goldenTicketId, 1, "");
        }
        
        emit BookOpened(bookId, msg.sender);
    }

    /// @dev Validate mint permission based on current round
    function _validateMintPermission(
        uint256 currentRound,
        uint256 quantity,
        bytes32[] calldata merkleProof
    ) internal {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        if (currentRound == 0) {
            revert RoundNotActive(); // Manual round, use airdrop instead
        } else if (currentRound == 1 || currentRound == 2) {
            uint256 allowance = $.roundAllowances[currentRound][msg.sender];
            uint256 minted = $.roundMinted[currentRound][msg.sender];
            
            if (allowance == 0) revert InsufficientAllowance();
            if (minted + quantity > allowance) revert InsufficientAllowance();
            
            $.roundMinted[currentRound][msg.sender] += quantity;
        } else if (currentRound == 3) {
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
            if (!MerkleProof.verify(merkleProof, $.round3MerkleRoot, leaf)) {
                revert InvalidProof();
            }
        }
        // Round 4 (public) - no restrictions
    }

    /// @dev Process payment for minting
    function _processPayment(PaymentType paymentType, uint256 quantity) internal {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        PaymentOption memory payment;
        if (paymentType == PaymentType.NATIVE_ONLY) {
            payment = $.nativeOnlyPayment;
        } else if (paymentType == PaymentType.HYBRID) {
            payment = $.hybridPayment;
        } else {
            revert InvalidPaymentType();
        }
        
        uint256 totalNative = payment.nativeAmount * quantity;
        uint256 totalErc20 = payment.erc20Amount * quantity;
        
        // Check native payment
        if (msg.value < totalNative) revert InsufficientPayment();
        
        // Process ERC20 payment if required
        if (totalErc20 > 0) {
            bool success = $.kttyToken.transferFrom(msg.sender, $.treasuryWallet, totalErc20);
            if (!success) revert TransferFailed();
        }
        
        // Transfer native payment
        if (totalNative > 0) {
            (bool success, ) = $.treasuryWallet.call{value: totalNative}("");
            if (!success) revert TransferFailed();
        }
        
        // Refund excess native payment
        if (msg.value > totalNative) {
            (bool success, ) = msg.sender.call{value: msg.value - totalNative}("");
            if (!success) revert TransferFailed();
        }
    }

    /// @dev Mint books based on current round and pools/buckets
    function _mintBooks(uint256 currentRound, uint256 quantity) internal returns (uint256[] memory) {
        uint256[] memory bookIds = new uint256[](quantity);
        
        for (uint256 i = 0; i < quantity; i++) {
            bookIds[i] = _getNextBookId(currentRound);
        }
        
        return bookIds;
    }

    /// @dev Get next book ID based on round and pool/bucket logic
    function _getNextBookId(uint256 currentRound) internal returns (uint256) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        if (currentRound == 1) {
            return _getBookFromPool($.pool1);
        } else if (currentRound == 2) {
            return _getBookFromPool($.pool2);
        } else if (currentRound == 3) {
            // Check if pools 1 or 2 have remaining books first
            if (!$.pool1.exhausted) {
                return _getBookFromPool($.pool1);
            } else if (!$.pool2.exhausted) {
                return _getBookFromPool($.pool2);
            } else {
                // Use bucket system
                return _getBookFromCurrentBucket();
            }
        } else if (currentRound == 4) {
            // Public round - check pools first, then buckets
            if (!$.pool1.exhausted) {
                return _getBookFromPool($.pool1);
            } else if (!$.pool2.exhausted) {
                return _getBookFromPool($.pool2);
            } else {
                return _getBookFromCurrentBucket();
            }
        }
        
        revert PoolExhausted();
    }

    /// @dev Get book from a specific pool
    function _getBookFromPool(Pool storage pool) internal returns (uint256) {
        if (pool.exhausted || pool.currentIndex >= pool.bookIds.length) {
            pool.exhausted = true;
            revert PoolExhausted();
        }
        
        uint256 bookId = pool.bookIds[pool.currentIndex];
        pool.currentIndex++;
        
        if (pool.currentIndex >= pool.bookIds.length) {
            pool.exhausted = true;
        }
        
        return bookId;
    }

    /// @dev Get book from current bucket
    function _getBookFromCurrentBucket() internal returns (uint256) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        // Find next available bucket
        while ($.currentBucketIndex < 8 && $.buckets[$.currentBucketIndex].exhausted) {
            $.currentBucketIndex++;
        }
        
        if ($.currentBucketIndex >= 8) {
            revert PoolExhausted();
        }
        
        Bucket storage currentBucket = $.buckets[$.currentBucketIndex];
        
        if (currentBucket.currentIndex >= currentBucket.bookIds.length) {
            currentBucket.exhausted = true;
            $.currentBucketIndex++;
            return _getBookFromCurrentBucket(); // Recursive call to get from next bucket
        }
        
        uint256 bookId = currentBucket.bookIds[currentBucket.currentIndex];
        currentBucket.currentIndex++;
        
        if (currentBucket.currentIndex >= currentBucket.bookIds.length) {
            currentBucket.exhausted = true;
        }
        
        return bookId;
    }

    /// @dev Track books owned by user
    function _trackUserBooks(address user, uint256[] memory bookIds) internal {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        
        for (uint256 i = 0; i < bookIds.length; i++) {
            $.userBooks[user].push(bookIds[i]);
            $.bookOwners[bookIds[i]] = user;
        }
    }

    /// @dev Get maximum mint per transaction
    function _getMaxMintPerTransaction() internal view returns (uint256) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.maxMintPerTransaction;
    }

    /// @dev Required by UUPS pattern
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @dev Implementation of IERC1155Receiver to accept ERC1155 tokens
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @dev Implementation of IERC1155Receiver to accept batch ERC1155 tokens
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /// @dev Implementation of IERC165 to support interface detection
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
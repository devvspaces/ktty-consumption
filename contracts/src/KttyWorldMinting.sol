// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {DummyCompanions} from "./KttyWorldCompanions.sol";
import {DummyTools} from "./KttyWorldTools.sol";
import {DummyCollectibles} from "./KttyWorldCollectibles.sol";
import {DummyBooks} from "./KttyWorldBooks.sol";

/// @title KttyWorldMinting
/// @notice Main minting contract for KTTY World summoning books with complex round and bucket system
/// @dev UUPS upgradeable contract with namespaced storage
contract KttyWorldMinting is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC1155Receiver,
    IERC721Receiver
{
    /// @custom:storage-location erc7201:ktty.storage.KttyWorldMinting
    struct KttyWorldMintingStorage {
        // Contract references
        DummyCompanions companions;
        DummyTools tools;
        DummyCollectibles collectibles;
        DummyBooks books;
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
        // Book tracking (opened books only)
        mapping(uint256 => bool) openedBooks;
        // Round 1 & 2 whitelist allowances
        mapping(uint256 => mapping(address => uint256)) roundAllowances;
        mapping(uint256 => mapping(address => uint256)) roundMinted;
        // Round 3 merkle root
        bytes32 round3MerkleRoot;
        // Leaderboard tracking
        mapping(address => uint256) userTotalMints;
        address[] minters;
    }

    // keccak256(abi.encode(uint256(keccak256("ktty.storage.KttyWorldMinting")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KTTY_WORLD_MINTING_STORAGE_LOCATION =
        0x7d8c6f4e3a9b5c8f2e1a7d4c9f6e3a0b5c8f2e1a7d4c9f6e3a0b5c8f2e1a7d00;

    /// @notice Represents a round configuration
    struct Round {
        uint256 startTime;
        uint256 endTime;
        RoundType roundType;
        bool active;
        PaymentOption nativeOnlyPayment;
        PaymentOption hybridPayment;
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
        MANUAL, // Round 0
        WHITELIST, // Round 1 & 2
        BUCKET, // Round 3
        PUBLIC // Round 4
    }

    /// @notice Payment types
    enum PaymentType {
        NATIVE_ONLY,
        HYBRID
    }

    // Events
    event BookAdded(
        uint256 indexed bookId,
        uint256 nftId,
        uint256[3] toolIds,
        uint256 goldenTicketId
    );
    event BooksMinted(uint256[] bookIds, address indexed buyer);
    event BookOpened(uint256 indexed bookId, address indexed owner);
    event RoundUpdated(
        uint256 indexed roundNumber,
        uint256 startTime,
        uint256 endTime
    );
    event PaymentConfigured(
        uint256 indexed roundNumber,
        PaymentType paymentType,
        uint256 nativeAmount,
        uint256 erc20Amount
    );
    event TreasuryWalletUpdated(address indexed newWallet);
    event PoolLoaded(uint256 indexed poolNumber, uint256 bookCount);
    event BucketLoaded(uint256 indexed bucketIndex, uint256 bookCount);
    event MinterStatsUpdated(address indexed user, uint256 totalMints);
    event SpilloverDistributed(uint256 totalBooksDistributed);

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

    function _getKttyWorldMintingStorage()
        private
        pure
        returns (KttyWorldMintingStorage storage $)
    {
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
    /// @param _companions DummyCompanions contract address
    /// @param _tools DummyTools contract address
    /// @param _collectibles DummyCollectibles contract address
    /// @param _books DummyBooks contract address
    /// @param _kttyToken KTTY token contract address
    /// @param _treasuryWallet Wallet to receive payments
    function initialize(
        address _owner,
        address _companions,
        address _tools,
        address _collectibles,
        address _books,
        address _kttyToken,
        address _treasuryWallet,
        uint256 _maxMintPerTransaction
    ) public initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        $.companions = DummyCompanions(_companions);
        $.tools = DummyTools(_tools);
        $.collectibles = DummyCollectibles(_collectibles);
        $.books = DummyBooks(_books);
        $.kttyToken = IERC20(_kttyToken);
        $.treasuryWallet = _treasuryWallet;
        $.maxMintPerTransaction = _maxMintPerTransaction;
        $.currentRound = 0;

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
            active: true,
            nativeOnlyPayment: PaymentOption(0, 0),
            hybridPayment: PaymentOption(0, 0)
        });

        // Rounds 1-4 will be configured by owner
        for (uint256 i = 1; i <= 4; i++) {
            $.rounds[i] = Round({
                startTime: 0,
                endTime: 0,
                roundType: i <= 2
                    ? RoundType.WHITELIST
                    : (i == 3 ? RoundType.BUCKET : RoundType.PUBLIC),
                active: false,
                nativeOnlyPayment: PaymentOption(0, 0),
                hybridPayment: PaymentOption(0, 0)
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
            if (
                round.active &&
                block.timestamp >= round.startTime &&
                block.timestamp <= round.endTime
            ) {
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
    function getWhitelistStatus(
        uint256 round,
        address user
    ) external view returns (uint256 allowance, uint256 minted) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        allowance = $.roundAllowances[round][user];
        minted = $.roundMinted[round][user];
    }

    /// @notice Check if an address is whitelisted for round 3 using merkle proof
    /// @param user User address
    /// @param proof Merkle proof
    /// @return Whether user is whitelisted for round 3
    function isWhitelistedForRound3(
        address user,
        bytes32[] calldata proof
    ) external view returns (bool) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        bytes32 leaf = keccak256(abi.encodePacked(user));
        return MerkleProof.verify(proof, $.round3MerkleRoot, leaf);
    }

    /// @notice Get books owned by a user
    /// @param user User address
    /// @return Array of book token IDs owned by the user
    function getUserBooks(
        address user
    ) external view returns (uint256[] memory) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.books.getUserBooks(user);
    }

    /// @notice Get detailed book information for all books owned by a user
    /// @param user User address
    /// @return Array of Book structs containing full book details
    function getUserBooksDetails(
        address user
    ) external view returns (DummyBooks.Book[] memory) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.books.getUserBooksDetails(user);
    }

    /// @notice Get book details
    /// @param bookId Book token ID
    /// @return Book struct containing book details
    function getBook(
        uint256 bookId
    ) external view returns (DummyBooks.Book memory) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.books.getBook(bookId);
    }

    /// @notice Check if book has been opened
    /// @param bookId Book ID
    /// @return Whether the book has been opened
    function isBookOpened(uint256 bookId) external view returns (bool) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.openedBooks[bookId];
    }

    /// @notice Get current pool and bucket status
    /// @return pool1Length Total number of books in pool 1
    /// @return pool1Remaining Number of books remaining in pool 1
    /// @return pool2Length Total number of books in pool 2
    /// @return pool2Remaining Number of books remaining in pool 2
    /// @return currentBucket Current bucket index
    /// @return bucketStats Array of remaining books in each bucket
    function getPoolAndBucketStatus()
        external
        view
        returns (
            uint256 pool1Length,
            uint256 pool1Remaining,
            uint256 pool2Length,
            uint256 pool2Remaining,
            uint256 currentBucket,
            uint256[2][8] memory bucketStats
        )
    {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();

        pool1Length = $.pool1.exhausted
            ? $.pool1.currentIndex
            : $.pool1.bookIds.length;
        pool2Length = $.pool2.exhausted
            ? $.pool2.currentIndex
            : $.pool2.bookIds.length;
        pool1Remaining = $.pool1.exhausted
            ? 0
            : $.pool1.bookIds.length - $.pool1.currentIndex;
        pool2Remaining = $.pool2.exhausted
            ? 0
            : $.pool2.bookIds.length - $.pool2.currentIndex;
        currentBucket = $.currentBucketIndex;

        for (uint256 i = 0; i < 8; i++) {
            bucketStats[i][0] = $.buckets[i].exhausted
                ? 0
                : $.buckets[i].bookIds.length - $.buckets[i].currentIndex;
            bucketStats[i][1] = $.buckets[i].bookIds.length;
        }
    }

    /// @notice Get payment configuration for a specific round
    /// @param roundNumber Round number (1-4)
    /// @return nativeOnly Native-only payment option configuration
    /// @return hybrid Hybrid payment option configuration
    function getPaymentConfig(
        uint256 roundNumber
    )
        external
        view
        returns (PaymentOption memory nativeOnly, PaymentOption memory hybrid)
    {
        if (roundNumber == 0 || roundNumber > 4) revert InvalidRound();

        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        nativeOnly = $.rounds[roundNumber].nativeOnlyPayment;
        hybrid = $.rounds[roundNumber].hybridPayment;
    }

    /// @notice Get round configuration
    /// @param roundNumber Round number (1-4)
    /// @return Round configuration
    function getRound(
        uint256 roundNumber
    ) external view returns (Round memory) {
        if (roundNumber == 0 || roundNumber > 4) revert InvalidRound();

        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.rounds[roundNumber];
    }

    /// @notice Get all rounds configuration for UI
    /// @return allRounds Array of all rounds 1-4
    function getAllRounds() external view returns (Round[4] memory allRounds) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();

        for (uint256 i = 1; i <= 4; i++) {
            allRounds[i - 1] = $.rounds[i];
        }
    }

    /// @notice Get top 5 minters leaderboard
    /// @return wallets Array of top minter addresses (up to 5)
    /// @return mints Array of mint counts corresponding to wallets
    function getTopMintersLeaderboard()
        external
        view
        returns (address[] memory wallets, uint256[] memory mints)
    {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();

        uint256 totalMinters = $.minters.length;
        if (totalMinters == 0) {
            return (new address[](0), new uint256[](0));
        }

        // Determine how many to return (max 50)
        uint256 returnCount = totalMinters > 50 ? 50 : totalMinters;

        // Create arrays to store sorted results
        address[] memory sortedWallets = new address[](returnCount);
        uint256[] memory sortedMints = new uint256[](returnCount);

        // Create a temporary array of all minters with their mint counts
        address[] memory allMinters = $.minters;
        uint256[] memory allMintCounts = new uint256[](totalMinters);

        for (uint256 i = 0; i < totalMinters; i++) {
            allMintCounts[i] = $.userTotalMints[allMinters[i]];
        }

        // Find top minters using selection sort for the top 5
        for (uint256 i = 0; i < returnCount; i++) {
            uint256 maxIndex = i;

            // Find the minter with the highest mint count in remaining minters
            for (uint256 j = i + 1; j < totalMinters; j++) {
                if (
                    allMintCounts[j] > allMintCounts[maxIndex] ||
                    (allMintCounts[j] == allMintCounts[maxIndex] &&
                        allMinters[j] < allMinters[maxIndex])
                ) {
                    maxIndex = j;
                }
            }

            // Swap to bring the max to position i
            if (maxIndex != i) {
                (allMinters[i], allMinters[maxIndex]) = (
                    allMinters[maxIndex],
                    allMinters[i]
                );
                (allMintCounts[i], allMintCounts[maxIndex]) = (
                    allMintCounts[maxIndex],
                    allMintCounts[i]
                );
            }

            sortedWallets[i] = allMinters[i];
            sortedMints[i] = allMintCounts[i];
        }

        return (sortedWallets, sortedMints);
    }

    /// @notice Get total mints for a specific user
    /// @param user User address
    /// @return Total number of books minted by the user
    function getUserTotalMints(address user) external view returns (uint256) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.userTotalMints[user];
    }

    /// @notice Get total number of unique minters
    /// @return Total number of addresses that have minted at least one book
    function getTotalUniqueMinters() external view returns (uint256) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.minters.length;
    }

    /// @notice Configure round times and activation
    /// @param roundNumber Round number (1-4)
    /// @param startTime Round start timestamp
    /// @param endTime Round end timestamp
    function configureRound(
        uint256 roundNumber,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner {
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

    /// @notice Configure payment options for a specific round
    /// @param roundNumber Round number (1-4)
    /// @param paymentType Payment type (NATIVE_ONLY or HYBRID)
    /// @param nativeAmount Native token amount required
    /// @param erc20Amount ERC20 token amount required (only for HYBRID)
    function configurePayment(
        uint256 roundNumber,
        PaymentType paymentType,
        uint256 nativeAmount,
        uint256 erc20Amount
    ) external onlyOwner {
        if (roundNumber == 0 || roundNumber > 4) revert InvalidRound();

        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();

        if (paymentType == PaymentType.NATIVE_ONLY) {
            $.rounds[roundNumber].nativeOnlyPayment = PaymentOption(
                nativeAmount,
                0
            );
        } else if (paymentType == PaymentType.HYBRID) {
            $.rounds[roundNumber].hybridPayment = PaymentOption(
                nativeAmount,
                erc20Amount
            );
        } else {
            revert InvalidPaymentType();
        }

        emit PaymentConfigured(
            roundNumber,
            paymentType,
            nativeAmount,
            erc20Amount
        );
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

    /// @notice Manual airdrop for round 0
    /// @param tokenIds Array of NFT token IDs to send
    /// @param recipient Recipient address
    function manualAirdrop(
        uint256[] calldata tokenIds,
        address recipient
    ) external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            try
                $.companions.transferFrom(address(this), recipient, tokenIds[i])
            {
                // Transfer successful
            } catch {
                revert TransferFailed();
            }
        }
    }

    /// @notice Distribute remaining Pool 1 and Pool 2 books equally across Round 3 buckets
    /// @dev This function should be called after Rounds 1 and 2 end but before Round 3 starts
    function distributeSpilloverToBuckets() external onlyOwner {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();

        // Collect all remaining books from pools 1 and 2
        uint256[] memory spilloverBooks = new uint256[](0);
        uint256 totalSpillover = 0;

        // Collect remaining books from pool 1
        if (
            !$.pool1.exhausted && $.pool1.currentIndex < $.pool1.bookIds.length
        ) {
            uint256 pool1Remaining = $.pool1.bookIds.length -
                $.pool1.currentIndex;
            uint256[] memory temp = new uint256[](
                totalSpillover + pool1Remaining
            );

            // Copy existing spillover books
            for (uint256 i = 0; i < totalSpillover; i++) {
                temp[i] = spilloverBooks[i];
            }

            // Add pool 1 remaining books
            for (uint256 i = 0; i < pool1Remaining; i++) {
                temp[totalSpillover + i] = $.pool1.bookIds[
                    $.pool1.currentIndex + i
                ];
            }

            spilloverBooks = temp;
            totalSpillover += pool1Remaining;

            // Mark pool 1 as exhausted
            $.pool1.exhausted = true;
        }

        // Collect remaining books from pool 2
        if (
            !$.pool2.exhausted && $.pool2.currentIndex < $.pool2.bookIds.length
        ) {
            uint256 pool2Remaining = $.pool2.bookIds.length -
                $.pool2.currentIndex;
            uint256[] memory temp = new uint256[](
                totalSpillover + pool2Remaining
            );

            // Copy existing spillover books
            for (uint256 i = 0; i < totalSpillover; i++) {
                temp[i] = spilloverBooks[i];
            }

            // Add pool 2 remaining books
            for (uint256 i = 0; i < pool2Remaining; i++) {
                temp[totalSpillover + i] = $.pool2.bookIds[
                    $.pool2.currentIndex + i
                ];
            }

            spilloverBooks = temp;
            totalSpillover += pool2Remaining;

            // Mark pool 2 as exhausted
            $.pool2.exhausted = true;
        }

        // If no spillover books, return early
        if (totalSpillover == 0) {
            return;
        }

        // Calculate distribution across 8 buckets
        uint256 booksPerBucket = totalSpillover / 8;
        uint256 remainder = totalSpillover % 8;

        uint256 spilloverIndex = 0;

        // Distribute books to buckets
        for (uint256 bucketIdx = 0; bucketIdx < 8; bucketIdx++) {
            uint256 booksForThisBucket = booksPerBucket;
            if (bucketIdx < remainder) {
                booksForThisBucket += 1;
            }

            if (booksForThisBucket > 0) {
                _insertSpilloverIntoBucket(
                    bucketIdx,
                    spilloverBooks,
                    spilloverIndex,
                    booksForThisBucket
                );
                spilloverIndex += booksForThisBucket;
            }
        }

        emit SpilloverDistributed(totalSpillover);
    }

    /// @dev Insert spillover books randomly into a specific bucket
    function _insertSpilloverIntoBucket(
        uint256 bucketIndex,
        uint256[] memory spilloverBooks,
        uint256 startIndex,
        uint256 count
    ) internal {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        Bucket storage bucket = $.buckets[bucketIndex];

        // Create new array with increased size
        uint256 newSize = bucket.bookIds.length + count;
        uint256[] memory newBookIds = new uint256[](newSize);

        // Copy original books
        for (uint256 i = 0; i < bucket.bookIds.length; i++) {
            newBookIds[i] = bucket.bookIds[i];
        }

        // Insert spillover books at random positions
        for (uint256 i = 0; i < count; i++) {
            uint256 spilloverBookId = spilloverBooks[startIndex + i];

            // Generate pseudo-random position using block data and iteration
            uint256 randomPosition = _generateRandomPosition(
                bucketIndex,
                i,
                newSize - count + i + 1
            );

            // Shift books to make room for insertion
            for (uint256 j = newSize - count + i; j > randomPosition; j--) {
                newBookIds[j] = newBookIds[j - 1];
            }

            // Insert spillover book at random position
            newBookIds[randomPosition] = spilloverBookId;
        }

        // Update bucket with new book array
        bucket.bookIds = newBookIds;
    }

    /// @dev Generate pseudo-random position for spillover book insertion
    function _generateRandomPosition(
        uint256 bucketIndex,
        uint256 iteration,
        uint256 maxPosition
    ) internal view returns (uint256) {
        uint256 pseudoRandom = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    bucketIndex,
                    iteration,
                    msg.sender
                )
            )
        );

        return pseudoRandom % maxPosition;
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
        if (quantity == 0 || quantity > _getMaxMintPerTransaction())
            revert MaxMintExceeded();

        uint256 currentRound = getCurrentRound();
        _validateMintPermission(currentRound, quantity, merkleProof);
        _processPayment(paymentType, quantity, currentRound);

        uint256[] memory mintedBookIds = _mintBooks(currentRound, quantity);
        _transferBooksToUser(msg.sender, mintedBookIds);

        emit BooksMinted(mintedBookIds, msg.sender);
    }

    /// @notice Open/summon a book to receive its contents
    /// @param bookIds Book token IDs to open
    function openBooks(uint256[] memory bookIds) external nonReentrant {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();

        for (uint256 x = 0; x < bookIds.length; x++) {
            uint256 bookId = bookIds[x];

            // Check ownership via Books contract
            if ($.books.ownerOf(bookId) != msg.sender) revert BookNotOwned();
            if ($.openedBooks[bookId]) revert BookAlreadyOpened();

            $.openedBooks[bookId] = true;

            // Get book details from Books contract
            DummyBooks.Book memory book = $.books.getBook(bookId);

            // Transfer NFT
            try
                $.companions.transferFrom(address(this), msg.sender, book.nftId)
            {
                // Transfer successful
            } catch {
                revert TransferFailed();
            }

            // Reveal the NFT
            $.companions.revealToken(book.nftId);

            // Transfer tools
            for (uint256 i = 0; i < 3; i++) {
                $.tools.safeTransferFrom(
                    address(this),
                    msg.sender,
                    book.toolIds[i],
                    1,
                    ""
                );
            }

            // Transfer golden ticket if present
            if (book.hasGoldenTicket) {
                $.collectibles.safeTransferFrom(
                    address(this),
                    msg.sender,
                    book.goldenTicketId,
                    1,
                    ""
                );
            }

            // Burn the book NFT
            $.books.burnBook(bookId);

            emit BookOpened(bookId, msg.sender);
        }
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
    function _processPayment(
        PaymentType paymentType,
        uint256 quantity,
        uint256 currentRound
    ) internal {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();

        PaymentOption memory payment;
        if (paymentType == PaymentType.NATIVE_ONLY) {
            payment = $.rounds[currentRound].nativeOnlyPayment;
        } else if (paymentType == PaymentType.HYBRID) {
            payment = $.rounds[currentRound].hybridPayment;
        } else {
            revert InvalidPaymentType();
        }

        uint256 totalNative = payment.nativeAmount * quantity;
        uint256 totalErc20 = payment.erc20Amount * quantity;

        // Check native payment
        if (msg.value < totalNative) revert InsufficientPayment();

        // Process ERC20 payment if required
        if (totalErc20 > 0) {
            bool success = $.kttyToken.transferFrom(
                msg.sender,
                $.treasuryWallet,
                totalErc20
            );
            if (!success) revert TransferFailed();
        }

        // Transfer native payment
        if (totalNative > 0) {
            (bool success, ) = $.treasuryWallet.call{value: totalNative}("");
            if (!success) revert TransferFailed();
        }

        // Refund excess native payment
        if (msg.value > totalNative) {
            (bool success, ) = msg.sender.call{value: msg.value - totalNative}(
                ""
            );
            if (!success) revert TransferFailed();
        }
    }

    /// @dev Mint books based on current round and pools/buckets
    function _mintBooks(
        uint256 currentRound,
        uint256 quantity
    ) internal returns (uint256[] memory) {
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
            // Round 3 uses bucket system only (spillover must be manually distributed first)
            return _getBookFromCurrentBucket();
        } else if (currentRound == 4) {
            // Public round uses bucket system only (spillover already distributed)
            return _getBookFromCurrentBucket();
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
        while (
            $.currentBucketIndex < 8 &&
            $.buckets[$.currentBucketIndex].exhausted
        ) {
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

    /// @dev Transfer book NFTs to user and update leaderboard tracking
    function _transferBooksToUser(
        address user,
        uint256[] memory bookIds
    ) internal {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();

        // Check if this is the user's first mint
        bool isFirstMint = $.userTotalMints[user] == 0;

        // Transfer book NFTs to user
        for (uint256 i = 0; i < bookIds.length; i++) {
            $.books.transferFrom(address(this), user, bookIds[i]);
        }

        // Update leaderboard tracking
        $.userTotalMints[user] += bookIds.length;

        // Add to minters array if first mint
        if (isFirstMint) {
            $.minters.push(user);
        }

        emit MinterStatsUpdated(user, $.userTotalMints[user]);
    }

    /// @dev Get maximum mint per transaction
    function _getMaxMintPerTransaction() internal view returns (uint256) {
        KttyWorldMintingStorage storage $ = _getKttyWorldMintingStorage();
        return $.maxMintPerTransaction;
    }

    /// @dev Required by UUPS pattern
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

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

    /// @dev Implementation of IERC721Receiver to accept ERC721 tokens
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @dev Implementation of IERC165 to support interface detection
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title DummyBooks
/// @notice ERC721 contract for KTTY World summoning books with reveal mechanism
/// @dev UUPS upgradeable contract with namespaced storage
contract DummyBooks is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @custom:storage-location erc7201:ktty.storage.DummyBooks
    struct KttyWorldBooksStorage {
        uint256 totalSupply;
        uint256 maxSupply;
        bool revealed;
        string hiddenMetadataUri;
        string baseTokenUri;
        mapping(uint256 => bool) tokenExists;
        mapping(uint256 => Book) books;
        mapping(uint256 => bool) tokenRevealed;
        address mintingContract;
    }

    // keccak256(abi.encode(uint256(keccak256("ktty.storage.DummyBooks")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KTTY_WORLD_BOOKS_STORAGE_LOCATION =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a00;

    /// @notice Represents a summoning book containing NFT and tools
    struct Book {
        uint256 nftId;
        uint256[3] toolIds; // Always 3 tools
        uint256 goldenTicketId; // 0 if no golden ticket
        bool hasGoldenTicket;
        string series;
    }

    // Events
    event Revealed(bool revealed);
    event HiddenMetadataUriUpdated(string hiddenMetadataUri);
    event BaseTokenUriUpdated(string baseTokenUri);
    event BookAdded(
        uint256 indexed tokenId,
        uint256 nftId,
        uint256[3] toolIds,
        uint256 goldenTicketId
    );
    event BookBurned(uint256 indexed tokenId, address indexed burner);
    event MintingContractUpdated(address indexed newMintingContract);
    event TokenRevealed(uint256 indexed tokenId);
    event TokensRevealed(uint256[] tokenIds);
    event MetadataUpdated(uint256 tokenId);

    // Errors
    error MaxSupplyReached();
    error InvalidTokenId();
    error BatchSizeZero();
    error ExceedsMaxSupply();
    error OnlyMintingContract();
    error InvalidArrayLength();
    error BookNotExists();

    function _getKttyWorldBooksStorage()
        private
        pure
        returns (KttyWorldBooksStorage storage $)
    {
        assembly {
            $.slot := KTTY_WORLD_BOOKS_STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _owner The owner of the contract
    /// @param _name The name of the NFT collection
    /// @param _symbol The symbol of the NFT collection
    /// @param _maxSupply The maximum supply of books
    /// @param _hiddenMetadataUri The URI for hidden metadata
    /// @param _mintingContract The address of the minting contract
    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        string memory _hiddenMetadataUri,
        address _mintingContract
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        $.maxSupply = _maxSupply;
        $.hiddenMetadataUri = _hiddenMetadataUri;
        $.revealed = false;
        $.mintingContract = _mintingContract;
    }

    /// @notice Batch mint books to a specific address
    /// @param to Address to mint books to
    /// @param tokenIds Array of token IDs to mint
    /// @param nftIds Array of NFT IDs for each book
    /// @param toolIds Array of tool ID arrays (each containing 3 tool IDs)
    /// @param goldenTicketIds Array of golden ticket IDs (0 if none)
    /// @param series Array of series names for each book
    function batchMintBooks(
        address to,
        uint256[] calldata tokenIds,
        uint256[] calldata nftIds,
        uint256[3][] calldata toolIds,
        uint256[] calldata goldenTicketIds,
        string[] calldata series
    ) external onlyOwner {
        if (tokenIds.length == 0) revert BatchSizeZero();
        if (
            tokenIds.length != nftIds.length ||
            tokenIds.length != toolIds.length ||
            tokenIds.length != goldenTicketIds.length ||
            tokenIds.length != series.length
        ) {
            revert InvalidArrayLength();
        }

        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();

        if ($.totalSupply + tokenIds.length > $.maxSupply) {
            revert ExceedsMaxSupply();
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // Mint the NFT
            _mint(to, tokenId);

            // Store book data
            $.books[tokenId] = Book({
                nftId: nftIds[i],
                toolIds: toolIds[i],
                goldenTicketId: goldenTicketIds[i],
                hasGoldenTicket: goldenTicketIds[i] != 0,
                series: series[i]
            });

            $.tokenExists[tokenId] = true;

            emit BookAdded(tokenId, nftIds[i], toolIds[i], goldenTicketIds[i]);
        }

        $.totalSupply += tokenIds.length;
    }

    /// @notice Burn a book NFT (only callable by minting contract)
    /// @param tokenId The token ID to burn
    function burnBook(uint256 tokenId) external {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();

        if (msg.sender != $.mintingContract) revert OnlyMintingContract();
        if (!$.tokenExists[tokenId]) revert BookNotExists();

        _burn(tokenId);
        $.tokenExists[tokenId] = false;

        emit BookBurned(tokenId, msg.sender);
    }

    /// @notice Get book details by token ID
    /// @param tokenId The token ID
    /// @return Book struct containing book details
    function getBook(uint256 tokenId) external view returns (Book memory) {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        if (!$.tokenExists[tokenId]) revert InvalidTokenId();
        return $.books[tokenId];
    }

    /// @notice Get all book token IDs owned by a user
    /// @param user User address
    /// @return Array of token IDs owned by the user
    function getUserBooks(
        address user
    ) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(user);
        uint256[] memory userTokens = new uint256[](balance);
        uint256 currentIndex = 0;

        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();

        // Iterate through all tokens to find user's tokens
        for (uint256 i = 1; i <= $.totalSupply; i++) {
            if ($.tokenExists[i] && ownerOf(i) == user) {
                userTokens[currentIndex] = i;
                currentIndex++;
                if (currentIndex == balance) break;
            }
        }

        return userTokens;
    }

    /// @notice Get detailed book information for all books owned by a user
    /// @param user User address
    /// @return Array of Book structs containing full book details
    function getUserBooksDetails(
        address user
    ) external view returns (Book[] memory) {
        uint256 balance = balanceOf(user);
        Book[] memory userBooks = new Book[](balance);
        uint256 currentIndex = 0;

        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();

        // Iterate through all tokens to find user's books
        for (uint256 i = 1; i <= $.totalSupply; i++) {
            if ($.tokenExists[i] && ownerOf(i) == user) {
                userBooks[currentIndex] = $.books[i];
                currentIndex++;
                if (currentIndex == balance) break;
            }
        }

        return userBooks;
    }

    /// @notice Get total supply of minted books
    /// @return Total number of books minted
    function totalSupply() external view returns (uint256) {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        return $.totalSupply;
    }

    /// @notice Get maximum supply of books
    /// @return Maximum number of books that can be minted
    function maxSupply() external view returns (uint256) {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        return $.maxSupply;
    }

    /// @notice Check if book exists
    /// @param tokenId Token ID to check
    /// @return Whether the book exists
    function exists(uint256 tokenId) external view returns (bool) {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        return $.tokenExists[tokenId];
    }

    /// @notice Set the minting contract address
    /// @param _mintingContract New minting contract address
    function setMintingContract(address _mintingContract) external onlyOwner {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        $.mintingContract = _mintingContract;
        emit MintingContractUpdated(_mintingContract);
    }

    /// @notice Set the base token URI
    /// @param _baseTokenUri New base token URI
    function setBaseTokenURI(string calldata _baseTokenUri) external onlyOwner {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        $.baseTokenUri = _baseTokenUri;
        emit BaseTokenUriUpdated(_baseTokenUri);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Set the hidden metadata URI
    /// @param _hiddenMetadataUri New hidden metadata URI
    function setHiddenMetadataURI(
        string calldata _hiddenMetadataUri
    ) external onlyOwner {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        $.hiddenMetadataUri = _hiddenMetadataUri;
        emit HiddenMetadataUriUpdated(_hiddenMetadataUri);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Reveal the collection
    /// @param _revealed Whether the collection is revealed
    function setRevealed(bool _revealed) external onlyOwner {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        $.revealed = _revealed;
        emit Revealed(_revealed);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Reveal a specific token
    /// @param tokenId The token ID to reveal
    function revealToken(uint256 tokenId) external onlyOwner {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        if (!$.tokenExists[tokenId]) revert InvalidTokenId();

        $.tokenRevealed[tokenId] = true;
        emit TokenRevealed(tokenId);
        emit MetadataUpdated(tokenId); // Indicate all metadata updated
    }

    /// @notice Reveal multiple tokens in batch
    /// @param tokenIds Array of token IDs to reveal
    function batchRevealTokens(uint256[] calldata tokenIds) external onlyOwner {
        if (tokenIds.length == 0) revert BatchSizeZero();

        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (!$.tokenExists[tokenId]) revert InvalidTokenId();

            $.tokenRevealed[tokenId] = true;
        }

        emit TokensRevealed(tokenIds);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Check if a specific token is revealed
    /// @param tokenId The token ID to check
    /// @return Whether the token is revealed
    function isTokenRevealed(uint256 tokenId) external view returns (bool) {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        if (!$.tokenExists[tokenId]) revert InvalidTokenId();

        // Token is revealed if either globally revealed or individually revealed
        return $.revealed || $.tokenRevealed[tokenId];
    }

    /// @notice Get the token URI for a given token ID
    /// @param tokenId Token ID
    /// @return Token URI
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) revert InvalidTokenId();
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        return
            bytes($.baseTokenUri).length > 0
                ? string(
                    abi.encodePacked(
                        $.baseTokenUri,
                        _toString(tokenId),
                        ".json"
                    )
                )
                : "";
    }

    /// @notice Check if books are revealed
    /// @return Whether books are revealed
    function isRevealed() external view returns (bool) {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        return $.revealed;
    }

    /// @notice Get the hidden metadata URI
    /// @return The hidden metadata URI
    function hiddenMetadataUri() external view returns (string memory) {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        return $.hiddenMetadataUri;
    }

    /// @notice Get the base token URI
    /// @return The base token URI
    function baseTokenUri() external view returns (string memory) {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        return $.baseTokenUri;
    }

    /// @notice Check if a token exists
    /// @param tokenId Token ID to check
    /// @return Whether the token exists
    function _exists(uint256 tokenId) internal view returns (bool) {
        KttyWorldBooksStorage storage $ = _getKttyWorldBooksStorage();
        return $.tokenExists[tokenId];
    }

    /// @notice Convert uint256 to string
    /// @param value Value to convert
    /// @return String representation
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

    /// @dev Required by UUPS pattern
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}

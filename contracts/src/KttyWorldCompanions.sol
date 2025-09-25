// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title DummyCompanions
/// @notice ERC721 contract for KTTY World Companions NFTs with reveal mechanism
/// @dev UUPS upgradeable contract with namespaced storage
contract DummyCompanions is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @custom:storage-location erc7201:ktty.storage.DummyCompanions
    struct KttyWorldCompanionsStorage {
        uint256 totalSupply;
        uint256 maxSupply;
        bool revealed;
        string hiddenMetadataUri;
        string baseTokenUri;
        mapping(uint256 => bool) tokenExists;
        mapping(uint256 => bool) tokenRevealed;
        address mintingContract;
    }

    // keccak256(abi.encode(uint256(keccak256("ktty.storage.DummyCompanions")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KTTY_WORLD_COMPANIONS_STORAGE_LOCATION =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    event Revealed(bool revealed);
    event HiddenMetadataUriUpdated(string hiddenMetadataUri);
    event BaseTokenUriUpdated(string baseTokenUri);
    event BatchMinted(
        address indexed to,
        uint256 startTokenId,
        uint256 quantity
    );
    event MetadataUpdated(uint256 tokenId);
    event TokenRevealed(uint256 indexed tokenId);
    event TokensRevealed(uint256[] tokenIds);
    event MintingContractUpdated(address indexed newMintingContract);

    error MaxSupplyReached();
    error InvalidTokenId();
    error BatchSizeZero();
    error OnlyOwnerOrMintingContract();
    error ExceedsMaxSupply();

    function _getKttyWorldCompanionsStorage()
        private
        pure
        returns (KttyWorldCompanionsStorage storage $)
    {
        assembly {
            $.slot := KTTY_WORLD_COMPANIONS_STORAGE_LOCATION
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
    /// @param _hiddenMetadataUri The URI for hidden metadata
    /// @param _maxSupply The maximum supply of NFTs
    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol,
        string memory _hiddenMetadataUri,
        uint256 _maxSupply
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        $.maxSupply = _maxSupply;
        $.hiddenMetadataUri = _hiddenMetadataUri;
        $.revealed = false;
    }

    /// @notice Batch mint NFTs to a specific address
    /// @param to The address to mint NFTs to
    /// @param quantity The number of NFTs to mint
    function batchMint(address to, uint256 quantity) external onlyOwner {
        _batchMint(to, quantity);
    }

    /// @dev Internal batch mint function
    /// @param to The address to mint NFTs to
    /// @param quantity The number of NFTs to mint
    function _batchMint(address to, uint256 quantity) internal {
        if (quantity == 0) revert BatchSizeZero();

        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();

        if ($.totalSupply + quantity > $.maxSupply) revert ExceedsMaxSupply();

        uint256 startTokenId = $.totalSupply + 1;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = startTokenId + i;
            $.tokenExists[tokenId] = true;
            _mint(to, tokenId);
        }

        $.totalSupply += quantity;

        emit BatchMinted(to, startTokenId, quantity);
    }

    /// @notice Mint all remaining NFTs up to quantity to a specific address
    /// @param to The address to mint all NFTs to
    function mintAll(address to, uint256 quantity) external onlyOwner {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        uint256 remainingSupply = $.maxSupply - $.totalSupply;

        if (remainingSupply == 0) revert MaxSupplyReached();
        uint256 mintQuantity = quantity > remainingSupply
            ? remainingSupply
            : quantity;

        _batchMint(to, mintQuantity);
    }

    /// @notice Set the revealed state
    /// @param _revealed Whether the NFTs are revealed
    function setRevealed(bool _revealed) external onlyOwner {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        $.revealed = _revealed;
        emit Revealed(_revealed);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Reveal a specific token
    /// @param tokenId The token ID to reveal
    function revealToken(uint256 tokenId) external {
        _requireOwnerOrMintingContract();

        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        if (!$.tokenExists[tokenId]) revert InvalidTokenId();

        $.tokenRevealed[tokenId] = true;
        emit TokenRevealed(tokenId);
        emit MetadataUpdated(tokenId);
    }

    /// @notice Reveal multiple tokens in batch
    /// @param tokenIds Array of token IDs to reveal
    function batchRevealTokens(uint256[] calldata tokenIds) external {
        _requireOwnerOrMintingContract();

        if (tokenIds.length == 0) revert BatchSizeZero();

        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (!$.tokenExists[tokenId]) revert InvalidTokenId();

            $.tokenRevealed[tokenId] = true;
            emit MetadataUpdated(tokenId);
        }

        emit TokensRevealed(tokenIds);
    }

    /// @notice Check if a specific token is revealed
    /// @param tokenId The token ID to check
    /// @return Whether the token is revealed
    function isTokenRevealed(uint256 tokenId) external view returns (bool) {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        if (!$.tokenExists[tokenId]) revert InvalidTokenId();

        // Token is revealed if either globally revealed or individually revealed
        return $.revealed || $.tokenRevealed[tokenId];
    }

    /// @notice Set the hidden metadata URI
    /// @param _hiddenMetadataUri The new hidden metadata URI
    function setHiddenMetadataUri(
        string calldata _hiddenMetadataUri
    ) external onlyOwner {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        $.hiddenMetadataUri = _hiddenMetadataUri;
        emit HiddenMetadataUriUpdated(_hiddenMetadataUri);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Set the base token URI
    /// @param _baseTokenUri The new base token URI
    function setBaseTokenUri(string calldata _baseTokenUri) external onlyOwner {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        $.baseTokenUri = _baseTokenUri;
        emit BaseTokenUriUpdated(_baseTokenUri);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Get the token URI for a specific token
    /// @param tokenId The token ID
    /// @return The token URI
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();

        if (!$.tokenExists[tokenId]) revert InvalidTokenId();

        // Check if token is revealed (either globally or individually)
        if (!$.revealed && !$.tokenRevealed[tokenId]) {
            return $.hiddenMetadataUri;
        }

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

    /// @notice Get the total supply of NFTs
    /// @return The total supply
    function totalSupply() public view returns (uint256) {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        return $.totalSupply;
    }

    /// @notice Get the maximum supply of NFTs
    /// @return The maximum supply
    function maxSupply() public view returns (uint256) {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        return $.maxSupply;
    }

    /// @notice Check if NFTs are revealed
    /// @return Whether NFTs are revealed
    function isRevealed() public view returns (bool) {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        return $.revealed;
    }

    /// @notice Get the hidden metadata URI
    /// @return The hidden metadata URI
    function hiddenMetadataUri() public view returns (string memory) {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        return $.hiddenMetadataUri;
    }

    /// @notice Get the base token URI
    /// @return The base token URI
    function baseTokenUri() public view returns (string memory) {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        return $.baseTokenUri;
    }

    /// @notice Check if a token exists
    /// @param tokenId The token ID to check
    /// @return Whether the token exists
    function exists(uint256 tokenId) public view returns (bool) {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        return $.tokenExists[tokenId];
    }

    /// @notice Set the minting contract address
    /// @param _mintingContract The new minting contract address
    function setMintingContract(address _mintingContract) external onlyOwner {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        $.mintingContract = _mintingContract;
        emit MintingContractUpdated(_mintingContract);
    }

    /// @notice Get the minting contract address
    /// @return The minting contract address
    function mintingContract() external view returns (address) {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        return $.mintingContract;
    }

    /// @dev Require that the caller is either the owner or the minting contract
    function _requireOwnerOrMintingContract() internal view {
        KttyWorldCompanionsStorage storage $ = _getKttyWorldCompanionsStorage();
        if (msg.sender != owner() && msg.sender != $.mintingContract) {
            revert OnlyOwnerOrMintingContract();
        }
    }

    /// @dev Required by UUPS pattern
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @dev Convert uint256 to string
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

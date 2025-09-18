// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title KttyWorldCollectibles
/// @notice ERC1155 contract for KTTY World Collectibles (Golden Tickets and future collectibles) with dynamic token types and global reveal mechanism
/// @dev UUPS upgradeable contract with namespaced storage
contract KttyWorldCollectibles is Initializable, ERC1155Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:storage-location erc7201:ktty.storage.KttyWorldCollectibles
    struct KttyWorldCollectiblesStorage {
        uint256 nextTokenId;
        bool revealed;
        string hiddenMetadataUri;
        string baseTokenUri;
        mapping(uint256 => uint256) totalSupply;
        mapping(uint256 => bool) tokenExists;
        mapping(uint256 => string) tokenUris;
    }

    // keccak256(abi.encode(uint256(keccak256("ktty.storage.KttyWorldCollectibles")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KTTY_WORLD_COLLECTIBLES_STORAGE_LOCATION = 
        0x9b4d4c3f6e7d8a5b2c8f5e1a9d6c3f0e7a4b1c8e5f2a9b6c3f0d7a4b1c8e5f00;

    event Revealed(bool revealed);
    event HiddenMetadataUriUpdated(string hiddenMetadataUri);
    event BaseTokenUriUpdated(string baseTokenUri);
    event CollectibleTypeAdded(uint256 indexed tokenId, string tokenUri);
    event TokenUriUpdated(uint256 indexed tokenId, string tokenUri);
    event BatchMinted(uint256[] tokenIds, uint256[] amounts, address indexed to);
    event MetadataUpdated(uint256 tokenId);

    error TokenNotExists();
    error TokenAlreadyExists();
    error ArrayLengthMismatch();
    error ZeroQuantity();

    function _getKttyWorldCollectiblesStorage() private pure returns (KttyWorldCollectiblesStorage storage $) {
        assembly {
            $.slot := KTTY_WORLD_COLLECTIBLES_STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _owner The owner of the contract
    /// @param _hiddenMetadataUri The URI for hidden metadata
    function initialize(
        address _owner,
        string memory _hiddenMetadataUri
    ) public initializer {
        __ERC1155_init("");
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        $.hiddenMetadataUri = _hiddenMetadataUri;
        $.revealed = false;
        $.nextTokenId = 1;
    }

    /// @notice Add a new collectible type
    /// @param _tokenUri The URI for this collectible type's metadata
    /// @return tokenId The ID of the newly created collectible type
    function addCollectibleType(string calldata _tokenUri) external onlyOwner returns (uint256 tokenId) {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        
        tokenId = $.nextTokenId;
        $.nextTokenId++;
        $.tokenExists[tokenId] = true;
        $.tokenUris[tokenId] = _tokenUri;
        
        emit CollectibleTypeAdded(tokenId, _tokenUri);
    }

    /// @notice Batch mint collectibles to a specific address
    /// @param to The address to mint collectibles to
    /// @param tokenIds Array of token IDs to mint
    /// @param amounts Array of amounts to mint for each token ID
    function batchMint(
        address to,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external onlyOwner {
        _batchMint(to, tokenIds, amounts);
    }

    /// @notice Mint a single collectible type to a specific address
    /// @param to The address to mint collectibles to
    /// @param tokenId The token ID to mint
    /// @param amount The amount to mint
    function mint(
        address to,
        uint256 tokenId,
        uint256 amount
    ) external onlyOwner {
        _mint(to, tokenId, amount, "");
    }

    /// @notice Set the revealed state
    /// @param _revealed Whether the collectibles are revealed
    function setRevealed(bool _revealed) external onlyOwner {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        $.revealed = _revealed;
        emit Revealed(_revealed);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Set the hidden metadata URI
    /// @param _hiddenMetadataUri The new hidden metadata URI
    function setHiddenMetadataUri(string calldata _hiddenMetadataUri) external onlyOwner {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        $.hiddenMetadataUri = _hiddenMetadataUri;
        emit HiddenMetadataUriUpdated(_hiddenMetadataUri);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Set the base token URI
    /// @param _baseTokenUri The new base token URI
    function setBaseTokenUri(string calldata _baseTokenUri) external onlyOwner {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        $.baseTokenUri = _baseTokenUri;
        emit BaseTokenUriUpdated(_baseTokenUri);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Update URI for a specific collectible type
    /// @param tokenId The token ID to update
    /// @param _tokenUri The new token URI
    function setTokenUri(uint256 tokenId, string calldata _tokenUri) external onlyOwner {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        
        if (!$.tokenExists[tokenId]) revert TokenNotExists();
        
        $.tokenUris[tokenId] = _tokenUri;
        emit TokenUriUpdated(tokenId, _tokenUri);
        emit MetadataUpdated(type(uint256).max); // Indicate all metadata updated
    }

    /// @notice Get the URI for a specific token
    /// @param tokenId The token ID
    /// @return The token URI
    function uri(uint256 tokenId) public view override returns (string memory) {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        
        if (!$.tokenExists[tokenId]) revert TokenNotExists();

        if (!$.revealed) {
            return $.hiddenMetadataUri;
        }

        // If revealed, first check if there's a specific URI for this token
        if (bytes($.tokenUris[tokenId]).length > 0) {
            return $.tokenUris[tokenId];
        }

        // Fall back to base URI + token ID
        return bytes($.baseTokenUri).length > 0 
            ? string(abi.encodePacked($.baseTokenUri, _toString(tokenId), ".json"))
            : "";
    }

    /// @notice Get the total supply of a specific token ID
    /// @param tokenId The token ID
    /// @return The total supply
    function totalSupply(uint256 tokenId) public view returns (uint256) {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        return $.totalSupply[tokenId];
    }

    /// @notice Check if a collectible type exists
    /// @param tokenId The token ID to check
    /// @return Whether the collectible type exists
    function exists(uint256 tokenId) public view returns (bool) {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        return $.tokenExists[tokenId];
    }

    /// @notice Check if collectibles are revealed
    /// @return Whether collectibles are revealed
    function isRevealed() public view returns (bool) {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        return $.revealed;
    }

    /// @notice Get the hidden metadata URI
    /// @return The hidden metadata URI
    function hiddenMetadataUri() public view returns (string memory) {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        return $.hiddenMetadataUri;
    }

    /// @notice Get the base token URI
    /// @return The base token URI
    function baseTokenUri() public view returns (string memory) {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        return $.baseTokenUri;
    }

    /// @notice Get the next token ID that will be assigned
    /// @return The next token ID
    function getNextTokenId() public view returns (uint256) {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        return $.nextTokenId;
    }

    /// @notice Get the URI for a specific collectible type (even when hidden)
    /// @param tokenId The token ID
    /// @return The token URI
    function getTokenUri(uint256 tokenId) public view returns (string memory) {
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        
        if (!$.tokenExists[tokenId]) revert TokenNotExists();
        
        return $.tokenUris[tokenId];
    }

    /// @dev Internal batch mint function
    /// @param to The address to mint collectibles to
    /// @param tokenIds Array of token IDs to mint
    /// @param amounts Array of amounts to mint for each token ID
    function _batchMint(
        address to,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) internal {
        if (tokenIds.length != amounts.length) revert ArrayLengthMismatch();
        
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!$.tokenExists[tokenIds[i]]) revert TokenNotExists();
            if (amounts[i] == 0) revert ZeroQuantity();
        }
        
        _mintBatch(to, tokenIds, amounts, "");
        
        emit BatchMinted(tokenIds, amounts, to);
    }

    /// @dev Override to update total supply tracking
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override {
        super._update(from, to, ids, values);
        
        KttyWorldCollectiblesStorage storage $ = _getKttyWorldCollectiblesStorage();
        
        for (uint256 i = 0; i < ids.length; i++) {
            if (from == address(0)) {
                // Minting
                $.totalSupply[ids[i]] += values[i];
            } else if (to == address(0)) {
                // Burning
                $.totalSupply[ids[i]] -= values[i];
            }
        }
    }

    /// @dev Required by UUPS pattern
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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
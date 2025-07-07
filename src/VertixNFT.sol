// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Imports
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IVertixGovernance} from "./interfaces/IVertixGovernance.sol";

/**
 * @title VertixNFT
 * @dev NFT contract supporting single mints, collections, and royalties
 */
contract VertixNFT is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // Errors
    error VertixNFT__InvalidCollection();
    error VertixNFT__NotCollectionCreator();
    error VertixNFT__MaxSupplyReached();
    error VertixNFT__EmptyString();
    error VertixNFT__ZeroSupply();
    error VertixNFT__InvalidToken();
    error VertixNFT__ExceedsMaxCollectionSize();
    error VertixNFT__SocialMediaIdAlreadyUsed();
    error VertixNFT__InvalidSignature();
    error VertixNFT__InvalidRoyaltyPercentage();

    // Type declarations
    struct Collection {
        address creator;
        string name;
        string symbol;
        string image;
        uint16 maxSupply;
        uint16 currentSupply;
        uint256[] tokenIds;
    }

    // State variables
    IVertixGovernance public governanceContract;
    uint16 public constant MAX_COLLECTION_SIZE = 1000;
    uint256 public constant MAX_ROYALTY_BPS = 1000; // 10% max royalty
    uint256 private _nextTokenId;
    uint256 private _nextCollectionId;
    mapping(string => bool) public usedSocialMediaIds; // Prevent duplicate social media NFTs
    mapping(uint256 => Collection) public collections;
    mapping(uint256 => uint256) public tokenToCollection;
    mapping(uint256 => bytes32) public metadataHashes;

    // Events
    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed creator,
        string name,
        string symbol,
        string image,
        uint256 maxSupply
    );
    event NFTMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint256 collectionId,
        string uri,
        bytes32 metadataHash,
        address royaltyRecipient,
        uint96 royaltyBps
    );
    event SocialMediaNFTMinted(
        address indexed to,
        uint256 indexed tokenId,
        string socialMediaId,
        string uri,
        bytes32 metadataHash,
        address indexed royaltyRecipient,
        uint96 royaltyBps
    );

    // Constructor
    function initialize(address _verificationServer) public initializer {
        __ERC721_init("VertixNFT", "VNFT");
        __ERC721URIStorage_init();
        __ERC2981_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        _nextTokenId = 1;
        _nextCollectionId = 1;
        governanceContract = IVertixGovernance(_verificationServer);
    }

    // UUPS upgradeability
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // Public functions
    /**
     * @dev Create a new collection
     * @param name Collection name
     * @param symbol Collection symbol
     * @param image Collection image URI
     * @param maxSupply Maximum NFTs in collection
     */
    function createCollection(string calldata name, string calldata symbol, string calldata image, uint16 maxSupply)
        external
        returns (uint256)
    {
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert VertixNFT__EmptyString();
        if (maxSupply == 0) revert VertixNFT__ZeroSupply();
        if (maxSupply > MAX_COLLECTION_SIZE) revert VertixNFT__ExceedsMaxCollectionSize();

        uint256 collectionId = _nextCollectionId++;
        collections[collectionId] = Collection({
            creator: msg.sender,
            name: name,
            symbol: symbol,
            image: image,
            maxSupply: maxSupply,
            currentSupply: 0,
            tokenIds: new uint256[](0)
        });

        emit CollectionCreated(collectionId, msg.sender, name, symbol, image, maxSupply);
        return collectionId;
    }

    /**
     * @dev Mint NFT to a collection
     * @param to Recipient address
     * @param collectionId Collection ID
     * @param uri Token URI
     * @param metadataHash Metadata hash for verification
     * @param royaltyBps Royalty percentage in basis points (e.g., 500 = 5%)
     */
    function mintToCollection(
        address to,
        uint256 collectionId,
        string calldata uri,
        bytes32 metadataHash,
        uint96 royaltyBps
    ) external {
        Collection storage collection = collections[collectionId];
        if (collection.creator == address(0)) revert VertixNFT__InvalidCollection();
        if (msg.sender != collection.creator) revert VertixNFT__NotCollectionCreator();
        if (collection.currentSupply >= collection.maxSupply) revert VertixNFT__MaxSupplyReached();
        if (royaltyBps > MAX_ROYALTY_BPS) revert VertixNFT__InvalidRoyaltyPercentage();

        _mintNFT(to, collectionId, uri, metadataHash, collection.creator, royaltyBps);
        collection.currentSupply++;
    }

    /**
     * @dev Mint a single NFT (no collection)
     * @param to Recipient address
     * @param uri Token URI
     * @param metadataHash Metadata hash for verification
     * @param royaltyBps Royalty percentage in basis points (e.g., 500 = 5%)
     */
    function mintSingleNFT(address to, string calldata uri, bytes32 metadataHash, uint96 royaltyBps) external {
        if (royaltyBps > MAX_ROYALTY_BPS) revert VertixNFT__InvalidRoyaltyPercentage();
        _mintNFT(to, 0, uri, metadataHash, msg.sender, royaltyBps);
    }

    /**
     * @dev Mint social media connected NFT with signature verification
     * @param to Recipient address (must match signed message)
     * @param socialMediaId Verified social media identifier
     * @param uri Token URI
     * @param metadataHash Metadata hash for verification
     * @param royaltyBps Royalty percentage in basis points (e.g., 500 = 5%)
     * @param signature Server-signed proof of verification
     */
    function mintSocialMediaNFT(
        address to,
        string calldata socialMediaId,
        string calldata uri,
        bytes32 metadataHash,
        uint96 royaltyBps,
        bytes calldata signature
    ) external {
        if (usedSocialMediaIds[socialMediaId]) {
            revert VertixNFT__SocialMediaIdAlreadyUsed();
        }
        if (royaltyBps > MAX_ROYALTY_BPS) revert VertixNFT__InvalidRoyaltyPercentage();

        // Verify the signature
        _verifySignature(to, socialMediaId, signature);

        // Mint the NFT
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);
        metadataHashes[tokenId] = metadataHash;
        usedSocialMediaIds[socialMediaId] = true;
        _setTokenRoyalty(tokenId, to, royaltyBps);

        emit SocialMediaNFTMinted(to, tokenId, socialMediaId, uri, metadataHash, to, royaltyBps);
    }

    // Internal functions
    /**
     * @dev Internal mint function with common logic
     * @param to Recipient address
     * @param collectionId Collection ID (0 for single NFTs)
     * @param uri Token URI
     * @param metadataHash Metadata hash for verification
     * @param royaltyRecipient Royalty recipient address
     * @param royaltyBps Royalty percentage in basis points
     */
    function _mintNFT(
        address to,
        uint256 collectionId,
        string calldata uri,
        bytes32 metadataHash,
        address royaltyRecipient,
        uint96 royaltyBps
    ) internal {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);
        metadataHashes[tokenId] = metadataHash;
        _setTokenRoyalty(tokenId, royaltyRecipient, royaltyBps);

        if (collectionId > 0) {
            tokenToCollection[tokenId] = collectionId;
            collections[collectionId].tokenIds.push(tokenId);
        }

        emit NFTMinted(to, tokenId, collectionId, uri, metadataHash, royaltyRecipient, royaltyBps);
    }

    function _verifySignature(address to, string calldata socialMediaId, bytes calldata signature) internal view {
        address verificationServer = IVertixGovernance(governanceContract).getVerificationServer();
        bytes32 messageHash = keccak256(abi.encodePacked(to, socialMediaId));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);
        if (recoveredSigner != verificationServer) {
            revert VertixNFT__InvalidSignature();
        }
    }

    // View functions
    // /**
    //  * @dev Get collection tokens
    //  * @param collectionId Collection ID
    //  */
    // function getCollectionTokens(uint256 collectionId) external view returns (uint256[] memory) {
    //     if (collections[collectionId].creator == address(0)) revert VertixNFT__InvalidCollection();
    //     return collections[collectionId].tokenIds;
    // }

    // /**
    //  * @dev Get collection details
    //  * @param collectionId Collection ID
    //  */
    // function getCollectionDetails(uint256 collectionId)
    //     external
    //     view
    //     returns (
    //         address creator,
    //         string memory name,
    //         string memory symbol,
    //         string memory image,
    //         uint256 maxSupply,
    //         uint256 currentSupply
    //     )
    // {
    //     Collection memory collection = collections[collectionId];
    //     if (collection.creator == address(0)) revert VertixNFT__InvalidCollection();

    //     return (
    //         collection.creator,
    //         collection.name,
    //         collection.symbol,
    //         collection.image,
    //         collection.maxSupply,
    //         collection.currentSupply
    //     );
    // }

    function getUsedSocialMediaIds(string calldata socialMediaId) external view returns (bool) {
        return usedSocialMediaIds[socialMediaId];
    }

    // Overrides
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

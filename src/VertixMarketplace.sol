// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Imports
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ChainlinkClient} from "@chainlink/contracts/src/v0.8/operatorforwarder/ChainlinkClient.sol";
import {Chainlink} from "@chainlink/contracts/src/v0.8/operatorforwarder/Chainlink.sol";
import {IVertixEscrow} from "./interfaces/IVertixEscrow.sol";
import {IVertixAssetVerifier} from "./interfaces/IVertixAssetVerifier.sol";
import {IChainlinkConsumer} from "./interfaces/IChainlinkConsumer.sol";

interface IERC721Collection {
    function initialize(string memory name, string memory symbol) external;
    function safeMint(address to, uint256 tokenId, string memory tokenURI) external;
}

interface IERC1155Collection {
    function initialize(string memory uri) external;
    function safeMint(address to, uint256 tokenId, uint256 amount, string memory tokenURI) external;
}

contract VertixMarketplace is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, ERC721URIStorageUpgradeable {
    // Errors
    error VertixMarketplace__NotOwner();
    error VertixMarketplace__InvalidPrice();
    error VertixMarketplace__InvalidBuyer();
    error VertixMarketplace__NotListed();
    error VertixMarketplace__InsufficientFunds();
    error VertixMarketplace__TransferFailed();
    error VertixMarketplace__InvalidTokenStandard();
    error VertixMarketplace__Unauthorized();
    error VertixMarketplace__InvalidCollection();
    error VertixMarketplace__CollectionNotFound();
    error VertixMarketplace__OracleRequestPending();
    error VertixMarketplace__InvalidPlatform();
    error VertixMarketplace__InvalidAsset();
    error VertixMarketplace__NotAssetOwner();

    // Type Declarations
    struct Listing {
        address seller;
        address tokenAddress;
        uint256 tokenId;
        uint256 amount;
        uint256 price;
        bool isERC721;
        bool isActive;
    }

    struct SocialMediaNFT {
        string platform;
        string accountId;
        uint256 value;
        address owner;
    }

    struct Collection {
        address collectionAddress;
        address owner;
        bool isERC721;
        string name;
        string symbol;
        string baseURI;
    }

    struct OracleRequest {
        string platform;
        string accountId;
        address requester;
        bool isPending;
    }

    // State Variables
    uint256 private _listingId;
    uint256 private _collectionId;
    IVertixAssetVerifier public verifierContract;
    IERC20 public paymentToken;
    uint256 public platformFee;
    IVertixEscrow public escrowContract;
    address public erc721Template;
    address public erc1155Template;
    address public chainlinkConsumer;

    mapping(string => bool) public validPlatforms; // Valid social media platforms
    mapping(uint256 => Listing) public listings;
    mapping(address => mapping(string => SocialMediaNFT)) public socialMediaNFTs;
    mapping(uint256 => Collection) public collections;
    mapping(address => uint256) public collectionAddressToId;
    mapping(bytes32 => OracleRequest) public oracleRequests;

    // Events
    event NFTListed(uint256 indexed listingId, address indexed seller, address tokenAddress, uint256 tokenId, uint256 price, bool isERC721);
    event NFTPurchased(uint256 indexed listingId, address indexed buyer, address tokenAddress, uint256 tokenId, uint256 price);
    event SocialMediaNFTMinted(address indexed owner, string platform, string accountId, uint256 value);
    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed owner,
        address collectionAddress,
        bool isERC721,
        string name,
        string symbol,
        string baseURI
    );
    event NFTMintedToCollection(
        uint256 indexed collectionId,
        address indexed owner,
        address collectionAddress,
        uint256 tokenId,
        uint256 amount,
        string tokenURI
    );
    event SocialMediaValueRequested(bytes32 indexed requestId, string platform, string accountId, address requester);
    event SocialMediaValueFulfilled(bytes32 indexed requestId, uint256 value);
    event NonNFTSaleCreated(
        uint256 indexed escrowId,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        bytes32 assetHash,
        string assetType,
        string assetId
    );

    // Modifiers
    modifier onlyListingOwner(uint256 listingId) {
        if (listings[listingId].seller != msg.sender) revert VertixMarketplace__NotOwner();
        _;
    }

    modifier onlyCollectionOwner(uint256 collectionId) {
        if (collections[collectionId].owner != msg.sender) revert VertixMarketplace__NotOwner();
        _;
    }

    // Functions
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _verifierContract,
        address _paymentToken,
        uint256 _platformFee,
        address _escrowContract,
        address _erc721Template,
        address _erc1155Template,
        address _chainlinkConsumer
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __ERC721_init("VertixSocialNFT", "VSNFT");

        verifierContract = IVertixAssetVerifier(_verifierContract);
        paymentToken = IERC20(_paymentToken);
        platformFee = _platformFee;
        escrowContract = IVertixEscrow(_escrowContract);
        erc721Template = _erc721Template;
        erc1155Template = _erc1155Template;
        chainlinkConsumer = _chainlinkConsumer;
        _listingId = 0;
        _collectionId = 0;

        // Initialize valid social media platforms
        validPlatforms["x"] = true;
        validPlatforms["instagram"] = true;
        validPlatforms["twitch"] = true;
        validPlatforms["facebook"] = true;
    }

    // External Functions
    function createCollection(
        bool isERC721,
        string calldata name,
        string calldata symbol,
        string calldata baseURI
    ) external nonReentrant returns (uint256) {
        address template = isERC721 ? erc721Template : erc1155Template;
        address collectionAddress = Clones.clone(template);

        if (isERC721) {
            IERC721Collection(collectionAddress).initialize(name, symbol);
            OwnableUpgradeable(collectionAddress).transferOwnership(msg.sender);
        } else {
            IERC1155Collection(collectionAddress).initialize(baseURI);
            OwnableUpgradeable(collectionAddress).transferOwnership(msg.sender);
        }

        uint256 collectionId = _collectionId++;
        collections[collectionId] = Collection({
            collectionAddress: collectionAddress,
            owner: msg.sender,
            isERC721: isERC721,
            name: name,
            symbol: symbol,
            baseURI: baseURI
        });
        collectionAddressToId[collectionAddress] = collectionId;

        emit CollectionCreated(collectionId, msg.sender, collectionAddress, isERC721, name, symbol, baseURI);
        return collectionId;
    }

    function mintNFTToCollection(
        uint256 collectionId,
        uint256 tokenId,
        uint256 amount,
        string calldata tokenURI
    ) external nonReentrant onlyCollectionOwner(collectionId) {
        Collection memory collection = collections[collectionId];
        if (collection.collectionAddress == address(0)) revert VertixMarketplace__CollectionNotFound();

        if (collection.isERC721) {
            if (amount != 1) revert VertixMarketplace__InvalidTokenStandard();
            IERC721Collection(collection.collectionAddress).safeMint(msg.sender, tokenId, tokenURI);
        } else {
            IERC1155Collection(collection.collectionAddress).safeMint(msg.sender, tokenId, amount, tokenURI);
        }

        emit NFTMintedToCollection(collectionId, msg.sender, collection.collectionAddress, tokenId, amount, tokenURI);
    }

    function listNFT(
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        bool isERC721
    ) external nonReentrant {
        if (price == 0) revert VertixMarketplace__InvalidPrice();

     // Verify collection exists (optional: restrict to marketplace-created collections)
        if (collectionAddressToId[tokenAddress] == 0 && tokenAddress != address(this)) {
             // Allow external collections, but we can add stricter checks
        }

        uint256 listingId = _listingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            tokenAddress: tokenAddress,
            tokenId: tokenId,
            amount: isERC721 ? 1 : amount,
            price: price,
            isERC721: isERC721,
            isActive: true
        });

        if (isERC721) {
            IERC721(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenId);
        } else {
            IERC1155(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        }

        emit NFTListed(listingId, msg.sender, tokenAddress, tokenId, price, isERC721);
    }

    function cancelListing(uint256 listingId) external onlyListingOwner(listingId) nonReentrant {
        Listing memory listing = listings[listingId];
        if (!listing.isActive) revert VertixMarketplace__NotListed();

        listings[listingId].isActive = false;

        if (listing.isERC721) {
            IERC721(listing.tokenAddress).safeTransferFrom(address(this), msg.sender, listing.tokenId);
        } else {
            IERC1155(listing.tokenAddress).safeTransferFrom(address(this), msg.sender, listing.tokenId, listing.amount, "");
        }
    }

    function buyNFT(uint256 listingId) external nonReentrant {
        Listing memory listing = listings[listingId];
        if (!listing.isActive) revert VertixMarketplace__NotListed();

        uint256 fee = (listing.price * platformFee) / 10000;
        uint256 sellerProceeds = listing.price - fee;

        if (!paymentToken.transferFrom(msg.sender, address(this), fee)) revert VertixMarketplace__TransferFailed();
        if (!paymentToken.transferFrom(msg.sender, listing.seller, sellerProceeds)) revert VertixMarketplace__TransferFailed();

        if (listing.isERC721) {
            IERC721(listing.tokenAddress).safeTransferFrom(address(this), msg.sender, listing.tokenId);
        } else {
            IERC1155(listing.tokenAddress).safeTransferFrom(address(this), msg.sender, listing.tokenId, listing.amount, "");
        }

        listings[listingId].isActive = false;
        emit NFTPurchased(listingId, msg.sender, listing.tokenAddress, listing.tokenId, listing.price);
    }

    function mintSocialMediaNFT(
        string calldata platform,
        string calldata accountId
    ) external nonReentrant {
        if (!validPlatforms[platform]) revert VertixMarketplace__InvalidPlatform();
        if (bytes(accountId).length == 0) revert VertixMarketplace__InvalidAsset();
        if (!IVertixAssetVerifier(verifierContract).verifyAsset(msg.sender, "social_media", accountId)) {
            revert VertixMarketplace__Unauthorized();
        }

        bytes32 requestId = IChainlinkConsumer(chainlinkConsumer).requestAssetValue("social_media", accountId);
        oracleRequests[requestId] = OracleRequest({
            platform: platform,
            accountId: accountId,
            requester: msg.sender,
            isPending: true
        });

        emit SocialMediaValueRequested(requestId, platform, accountId, msg.sender);
    }

    function fulfillSocialMediaValue(
        bytes32 requestId,
        string calldata profilePicURI,
        bool autoList
    ) external {
        OracleRequest memory request = oracleRequests[requestId];
        if (!request.isPending) revert VertixMarketplace__OracleRequestPending();
        if (msg.sender != request.requester) revert VertixMarketplace__Unauthorized();

        uint256 value = IChainlinkConsumer(chainlinkConsumer).getValue(requestId);

        uint256 tokenId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp)));
        _mint(request.requester, tokenId);
        _setTokenURI(tokenId, profilePicURI);

        socialMediaNFTs[request.requester][request.platform] = SocialMediaNFT({
            platform: request.platform,
            accountId: request.accountId,
            value: value,
            owner: request.requester
        });

        oracleRequests[requestId].isPending = false;
        emit SocialMediaValueFulfilled(requestId, value);
        emit SocialMediaNFTMinted(request.requester, request.platform, request.accountId, value);

        if (autoList && value > 0) {
            uint256 listingId = _listingId++;
            listings[listingId] = Listing({
                seller: msg.sender,
                tokenAddress: address(this),
                tokenId: tokenId,
                amount: 1,
                price: value,
                isERC721: true,
                isActive: true
            });
            IERC721(address(this)).safeTransferFrom(msg.sender, address(this), tokenId);
            emit NFTListed(listingId, msg.sender, address(this), tokenId, value, true);
        }
    }

    function createNonNFTSale(
        address buyer,
        uint256 price,
        bytes32 assetHash,
        uint256 duration,
        string calldata assetType,
        string calldata assetId
    ) external nonReentrant returns (uint256) {
        if (price == 0) revert VertixMarketplace__InvalidPrice();
        if (buyer == address(0)) revert VertixMarketplace__InvalidBuyer();
        if (bytes(assetType).length == 0 || bytes(assetId).length == 0) revert VertixMarketplace__InvalidAsset();
        if (!IVertixAssetVerifier(verifierContract).verifyAsset(msg.sender, assetType, assetId)) {
            revert VertixMarketplace__NotAssetOwner();
        }
        if (keccak256(abi.encodePacked(assetType, assetId)) != assetHash) revert VertixMarketplace__InvalidAsset();

        uint256 escrowId = IVertixEscrow(escrowContract).createEscrow(buyer, price, assetHash, duration, assetType, assetId);

        emit NonNFTSaleCreated(escrowId, msg.sender, buyer, price, assetHash, assetType, assetId);
        return escrowId;
    }

    // Internal Functions
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // View & Pure Functions
    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getCollection(uint256 collectionId) external view returns (Collection memory) {
        return collections[collectionId];
    }

    function getCollectionIdByAddress(address collectionAddress) external view returns (uint256) {
        return collectionAddressToId[collectionAddress];
    }

    function isValidPlatform(string calldata platform) external view returns (bool) {
        return validPlatforms[platform];
    }
}
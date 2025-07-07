// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {VertixUtils} from "./libraries/VertixUtils.sol";
import {IVertixNFT} from "./interfaces/IVertixNFT.sol";
import {IMarketplaceStorage} from "./interfaces/IMarketplaceStorage.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MarketplaceStorage
 * @dev Centralized storage contract for all marketplace data
 */
contract MarketplaceStorage is ReentrancyGuard, IMarketplaceStorage {

    /*//////////////////////////////////////////////////////////////
                    STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct NFTListing {
        address seller;
        address nftContract;
        uint96 price;            // supports up to ~79B ETH
        uint256 tokenId;
        uint8 flags;             // 1 byte: bit 0=active, bit 1=listedForAuction
    }

    struct NonNFTListing {
        address seller;
        uint96 price;            // supports up to ~79B ETH
        uint8 assetType;
        uint8 flags;             // bit 0=active, bit 1=listedForAuction
        string assetId;
        string metadata;
        bytes32 verificationHash;
    }

    struct AuctionDetails {
        address seller;
        address highestBidder;
        uint96 highestBid;
        uint96 startingPrice;
        uint64 startTime;
        uint24 duration;         // supports up to 194 days
        uint8 flags;             // bit 0=active, bit 1=isNFT
        uint256 tokenIdOrListingId;
        uint256 auctionId;
        address nftContract;
        VertixUtils.AssetType assetType;
        string assetId;          // Dynamic (for non-NFT only)
    }

    struct Bid {
        uint96 bidAmount;
        uint32 bidId;
        address bidder;
    }

    struct TokenListing {
        address seller;
        address tokenContract;
        uint256 tokenId;
        uint256 quantity;
        uint96 pricePerToken;
        uint8 flags;             // 1 byte: bit 0=active, bit 1=listedForAuction
    }

    struct TokenListingView {
        address seller;
        address tokenContract;
        uint256 tokenId;
        uint256 quantity;
        uint96 pricePerToken;
        bool active;
        bool auctionListed;
    }

    struct AuctionDetailsView {
        bool active;
        bool isNFT;
        uint256 startTime;
        uint24 duration;
        address seller;
        address highestBidder;
        uint256 highestBid;
        uint256 tokenIdOrListingId;
        uint256 startingPrice;
        address nftContractAddr;
        uint8 assetType;
        string assetId;
    }


    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IVertixNFT public vertixNFTContract;
    address public governanceContract;
    address public escrowContract;

    uint256 public listingIdCounter = 1;
    uint256 public auctionIdCounter = 1;

    uint24 public constant MIN_AUCTION_DURATION = 1 hours;
    uint24 public constant MAX_AUCTION_DURATION = 7 days;


    mapping(uint256 => NFTListing) public nftListings;
    mapping(uint256 => NonNFTListing) public nonNFTListings;
    mapping(uint256 => AuctionDetails) public auctionListings;
    mapping(uint256 => Bid[]) public bidsPlaced;

    mapping(bytes32 => bool) public listingHashes;
    mapping(uint256 => bool) public listedForAuction;
    mapping(uint256 => uint256) public auctionIdForTokenOrListing;
    mapping(uint256 => uint256) public tokenOrListingIdForAuction;

    // Access control
    mapping(address => bool) public authorizedContracts;
    address public immutable owner;

    // Additional state variables for ERC-1155
    mapping(uint256 => TokenListing) public tokenListings;
    mapping(address => mapping(uint256 => uint256)) public userTokenBalances;
    mapping(uint256 => mapping(address => uint256)) public escrowedTokens;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ContractAuthorized(address indexed contractAddr, bool authorized);

    event TokenListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address tokenContract,
        uint256 indexed tokenId,
        uint256 quantity,
        uint96 pricePerToken
    );

    event TokenListingUpdated(
        uint256 indexed listingId,
        uint256 newQuantity,
        bool active
    );

    // Additional events for batch operations
    event BatchTokenListingCreated(
        uint256[] listingIds,
        address indexed seller,
        address tokenContract,
        uint256[] tokenIds,
        uint256[] quantities,
        uint96[] pricesPerToken
    );

    event BatchTokenListingUpdated(
        uint256[] listingIds,
        uint256[] newQuantities,
        bool[] active
    );
    event ContractsSet(
        address indexed vertixNFTContract,
        address indexed governanceContract,
        address indexed escrowContract
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorized() {
        if(!authorizedContracts[msg.sender]) {
            revert MarketplaceStorage__NotAuthorized();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert MarketplaceStorage__NotOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) {
        owner = _owner;
        authorizedContracts[_owner] = true;
    }

    /*//////////////////////////////////////////////////////////////
                          ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function authorizeContract(address contractAddr, bool authorized) external onlyOwner {
        authorizedContracts[contractAddr] = authorized;
        emit ContractAuthorized(contractAddr, authorized);
    }

    function setContracts(
        address _vertixNFTContract,
        address _governanceContract,
        address _escrowContract
    ) external onlyOwner {
        vertixNFTContract = IVertixNFT(_vertixNFTContract);
        governanceContract = _governanceContract;
        escrowContract = _escrowContract;
        emit ContractsSet(
            _vertixNFTContract,
            _governanceContract,
            _escrowContract
        );
    }

    /*//////////////////////////////////////////////////////////////
                            NFT LISTINGS
    //////////////////////////////////////////////////////////////*/

    function createNFTListing(
        address seller,
        address nftContractAddr,
        uint256 tokenId,
        uint96 price
    ) external onlyAuthorized returns (uint256 listingId) {
        listingId = listingIdCounter++;

        nftListings[listingId] = NFTListing({
            seller: seller,
            nftContract: nftContractAddr,
            price: price,
            tokenId: tokenId,
            flags: 1 // active = true
        });

        bytes32 hash = keccak256(abi.encodePacked(nftContractAddr, tokenId));
        listingHashes[hash] = true;
    }

    function updateNFTListingFlags(uint256 listingId, uint8 flags) external onlyAuthorized {
        nftListings[listingId].flags = flags;
    }

    function getNFTListing(uint256 listingId) external view returns (
        address seller,
        address nftContractAddr,
        uint256 tokenId,
        uint96 price,
        bool active,
        bool auctionListed
    ) {
        NFTListing memory listing = nftListings[listingId];
        return (
            listing.seller,
            listing.nftContract,
            listing.tokenId,
            listing.price,
            (listing.flags & 1) == 1,
            (listing.flags & 2) == 2
        );
    }

    function removeNFTListingHash(address nftContractAddr, uint256 tokenId) external onlyAuthorized {
        bytes32 hash = keccak256(abi.encodePacked(nftContractAddr, tokenId));
        listingHashes[hash] = false;
    }

    /*//////////////////////////////////////////////////////////////
                          NON-NFT LISTINGS
    //////////////////////////////////////////////////////////////*/

    function createNonNFTListing(
        address seller,
        uint8 assetType,
        string calldata assetId,
        uint96 price,
        string calldata metadata,
        bytes32 verificationHash
    ) external onlyAuthorized returns (uint256 listingId) {
        listingId = listingIdCounter++;

        nonNFTListings[listingId] = NonNFTListing({
            seller: seller,
            price: price,
            assetType: assetType,
            flags: 1, // active = true
            assetId: assetId,
            metadata: metadata,
            verificationHash: verificationHash
        });

        bytes32 hash = keccak256(abi.encodePacked(seller, assetId));
        listingHashes[hash] = true;
    }

    function updateNonNFTListingFlags(uint256 listingId, uint8 flags) external onlyAuthorized {
        nonNFTListings[listingId].flags = flags;
    }

    function getNonNFTListing(uint256 listingId) external view returns (
        address seller,
        uint96 price,
        uint8 assetType,
        bool active,
        bool auctionListed,
        string memory assetId,
        string memory metadata,
        bytes32 verificationHash
    ) {
        NonNFTListing memory listing = nonNFTListings[listingId];
        return (
            listing.seller,
            listing.price,
            listing.assetType,
            (listing.flags & 1) == 1,
            (listing.flags & 2) == 2,
            listing.assetId,
            listing.metadata,
            listing.verificationHash
        );
    }

    function removeNonNFTListingHash(address seller, string calldata assetId) external onlyAuthorized {
        bytes32 hash = keccak256(abi.encodePacked(seller, assetId));
        listingHashes[hash] = false;
    }

    /*//////////////////////////////////////////////////////////////
                             AUCTIONS
    //////////////////////////////////////////////////////////////*/

    function createAuction(
        address seller,
        uint256 tokenIdOrListingId,
        uint96 startingPrice,
        uint24 duration,
        bool isNFT,
        address nftContractAddr,
        uint8 assetType,
        string calldata assetId
    ) external onlyAuthorized returns (uint256 auctionId) {
        auctionId = auctionIdCounter++;

        auctionListings[auctionId] = AuctionDetails({
            seller: seller,
            highestBidder: address(0),
            highestBid: 0,
            startingPrice: startingPrice,
            startTime: uint64(block.timestamp),
            duration: duration,
            flags: isNFT ? 3 : 1, // active=1, isNFT=2
            tokenIdOrListingId: tokenIdOrListingId,
            auctionId: auctionId,
            nftContract: nftContractAddr,
            assetType: VertixUtils.AssetType(assetType),
            assetId: assetId
        });

        listedForAuction[tokenIdOrListingId] = true;
        auctionIdForTokenOrListing[tokenIdOrListingId] = auctionId;
        tokenOrListingIdForAuction[auctionId] = tokenIdOrListingId;
    }

    function updateAuctionBid(
        uint256 auctionId,
        address bidder,
        uint96 bidAmount
    ) external onlyAuthorized nonReentrant {
        AuctionDetails storage auction = auctionListings[auctionId];
        auction.highestBidder = bidder;
        auction.highestBid = bidAmount;

        uint32 bidId = uint32(bidsPlaced[auctionId].length);
        bidsPlaced[auctionId].push(Bid({
            bidAmount: bidAmount,
            bidId: bidId,
            bidder: bidder
        }));
    }

    function endAuction(uint256 auctionId) external onlyAuthorized {
        AuctionDetails storage auction = auctionListings[auctionId];
        auction.flags &= ~uint8(1); // Set active to false

        uint256 tokenOrListingId = auction.tokenIdOrListingId;
        listedForAuction[tokenOrListingId] = false;
        delete auctionIdForTokenOrListing[tokenOrListingId];
        delete tokenOrListingIdForAuction[auctionId];
    }

    function getAuctionDetailsView(uint256 auctionId) external view returns (AuctionDetailsView memory) {
        AuctionDetails memory auction = auctionListings[auctionId];
        return AuctionDetailsView({
            active: (auction.flags & 1) == 1,
            isNFT: (auction.flags & 2) == 2,
            startTime: auction.startTime,
            duration: auction.duration,
            seller: auction.seller,
            highestBidder: auction.highestBidder,
            highestBid: auction.highestBid,
            tokenIdOrListingId: auction.tokenIdOrListingId,
            startingPrice: auction.startingPrice,
            nftContractAddr: auction.nftContract,
            assetType: uint8(auction.assetType),
            assetId: auction.assetId
        });
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function checkListingHash(bytes32 hash) external view returns (bool) {
        return listingHashes[hash];
    }

    function isTokenListedForAuction(uint256 tokenIdOrListingId) external view returns (bool) {
        return listedForAuction[tokenIdOrListingId];
    }

    function getBidsCount(uint256 auctionId) external view returns (uint256) {
        return bidsPlaced[auctionId].length;
    }
    function getBid(uint256 auctionId, uint256 bidIndex) external view returns (
        uint256 bidAmount,
        uint32 bidId,
        address bidder
    ) {
        Bid memory bid = bidsPlaced[auctionId][bidIndex];
        return (uint256(bid.bidAmount), bid.bidId, bid.bidder);
    }

    /*//////////////////////////////////////////////////////////////
                        AUCTION LISTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev List an NFT or non-NFT for auction
     * @param listingId ID of the listing
     * @param isNFT true if NFT and false if non-NFT
     * @param seller Address of the seller
     */
    function listForAuction(
        uint256 listingId,
        bool isNFT,
        address seller
    ) external onlyAuthorized {
        if (isNFT) {
            NFTListing storage listing = nftListings[listingId];
                    if ((listing.flags & 1) != 1) revert MarketplaceStorage__ListingNotActive();
        if (listing.seller != seller) revert MarketplaceStorage__NotSeller();
        if (listedForAuction[listingId]) revert MarketplaceStorage__AlreadyListedForAuction();

            listing.flags |= 2; // Set auction listed bit
        } else {
            NonNFTListing storage listing = nonNFTListings[listingId];
            if ((listing.flags & 1) != 1) revert MarketplaceStorage__ListingNotActive();
            if (listing.seller != seller) revert MarketplaceStorage__NotSeller();
            if ((listing.flags & 2) != 0) revert MarketplaceStorage__AlreadyListedForAuction();

            listing.flags |= 2; // Set auction listed bit
        }

        // Mark as listed for auction
        listedForAuction[listingId] = true;
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN PURCHASE EXECUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Execute cross-chain NFT purchase (storage updates only)
     * @param listingId ID of the listing
     * @param price Purchase price for validation
     * @return nftContract Address of the NFT contract
     * @return tokenId ID of the NFT
     * @return listingPrice Original listing price
     */
    function executeCrossChainNFTPurchase(
        uint256 listingId,
        uint96 price
    ) external onlyAuthorized returns (
        address nftContract,
        uint256 tokenId,
        uint96 listingPrice
    ) {
        NFTListing storage listing = nftListings[listingId];

        if ((listing.flags & 1) != 1) revert MarketplaceStorage__ListingNotActive();
        if (price < listing.price) revert MarketplaceStorage__InsufficientPrice();

        // Mark listing as sold
        listing.flags = 0; // Set inactive

        // Return values for caller
        nftContract = listing.nftContract;
        tokenId = listing.tokenId;
        listingPrice = listing.price;

        // Remove listing hash
        bytes32 hash = keccak256(abi.encodePacked(nftContract, tokenId));
        listingHashes[hash] = false;
    }

    /**
     * @dev Execute cross-chain non-NFT purchase (storage updates only)
     * @param listingId ID of the listing
     * @param price Purchase price for validation
     * @return seller Address of the seller
     * @return assetType Type of the asset
     * @return assetId ID of the asset
     * @return listingPrice Original listing price
     */
    function executeCrossChainNonNFTPurchase(
        uint256 listingId,
        uint96 price
    ) external onlyAuthorized returns (
        address seller,
        uint8 assetType,
        string memory assetId,
        uint96 listingPrice
    ) {
        NonNFTListing storage listing = nonNFTListings[listingId];

        if ((listing.flags & 1) != 1) revert MarketplaceStorage__ListingNotActive();
        if (price < listing.price) revert MarketplaceStorage__InsufficientPrice();

        // Mark listing as sold
        listing.flags = 0; // Set inactive

        // Return values for caller
        seller = listing.seller;
        assetType = listing.assetType;
        assetId = listing.assetId;
        listingPrice = listing.price;

        // Remove listing hash
        bytes32 hash = keccak256(abi.encodePacked(seller, assetId));
        listingHashes[hash] = false;
    }

    /*//////////////////////////////////////////////////////////////
                            TOKEN LISTINGS
    //////////////////////////////////////////////////////////////*/

    function createTokenListing(
        address seller,
        address tokenContract,
        uint256 tokenId,
        uint256 quantity,
        uint96 pricePerToken
    ) external onlyAuthorized returns (uint256 listingId) {
        listingId = listingIdCounter++;

        tokenListings[listingId] = TokenListing({
            seller: seller,
            tokenContract: tokenContract,
            tokenId: tokenId,
            quantity: quantity,
            pricePerToken: pricePerToken,
            flags: 1 // active = true
        });

        bytes32 hash = keccak256(abi.encodePacked(tokenContract, tokenId, seller));
        listingHashes[hash] = true;

        emit TokenListingCreated(listingId, seller, tokenContract, tokenId, quantity, pricePerToken);
    }

    function updateTokenListing(uint256 listingId, uint256 newQuantity) external onlyAuthorized {
        TokenListing storage listing = tokenListings[listingId];
        listing.quantity = newQuantity;

        if (newQuantity == 0) {
            listing.flags = 0; // Set inactive
        }

        emit TokenListingUpdated(listingId, newQuantity, newQuantity > 0);
    }

    function getTokenListing(uint256 listingId) external view returns (TokenListingView memory) {
        TokenListing memory listing = tokenListings[listingId];
        return TokenListingView({
            seller: listing.seller,
            tokenContract: listing.tokenContract,
            tokenId: listing.tokenId,
            quantity: listing.quantity,
            pricePerToken: listing.pricePerToken,
            active: (listing.flags & 1) == 1,
            auctionListed: (listing.flags & 2) == 2
        });
    }



    function removeTokenListingHash(address tokenContract, uint256 tokenId, address seller) external onlyAuthorized {
        bytes32 hash = keccak256(abi.encodePacked(tokenContract, tokenId, seller));
        listingHashes[hash] = false;
    }

    /**
     * @dev Create multiple token listings in a single transaction
     */
    function createBatchTokenListing(
        address seller,
        address tokenContract,
        uint256[] calldata tokenIds,
        uint256[] calldata quantities,
        uint96[] calldata pricesPerToken
    ) external onlyAuthorized returns (uint256[] memory listingIds) {
        uint256 batchSize = tokenIds.length;
        if (batchSize != quantities.length || batchSize != pricesPerToken.length) {
            revert MarketplaceStorage__ArrayLengthMismatch();
        }

        listingIds = new uint256[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            listingIds[i] = listingIdCounter++;

            tokenListings[listingIds[i]] = TokenListing({
                seller: seller,
                tokenContract: tokenContract,
                tokenId: tokenIds[i],
                quantity: quantities[i],
                pricePerToken: pricesPerToken[i],
                flags: 1 // active = true
            });
        }

        emit BatchTokenListingCreated(
            listingIds,
            seller,
            tokenContract,
            tokenIds,
            quantities,
            pricesPerToken
        );
    }

    /**
     * @dev Update multiple token listings in a single transaction
     */
    function updateBatchTokenListing(
        uint256[] calldata listingIds,
        uint256[] calldata newQuantities
    ) external onlyAuthorized {
        if (listingIds.length != newQuantities.length) {
            revert MarketplaceStorage__ArrayLengthMismatch();
        }
        
        bool[] memory activeFlags = new bool[](listingIds.length);

        for (uint256 i = 0; i < listingIds.length; i++) {
            tokenListings[listingIds[i]].quantity = newQuantities[i];
            activeFlags[i] = newQuantities[i] > 0;
            tokenListings[listingIds[i]].flags = activeFlags[i] ? 1 : 0;
        }

        emit BatchTokenListingUpdated(listingIds, newQuantities, activeFlags);
    }
}
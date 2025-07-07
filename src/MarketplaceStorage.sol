// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VertixUtils} from "./libraries/VertixUtils.sol";
import {IVertixNFT} from "./interfaces/IVertixNFT.sol";

/**
 * @title MarketplaceStorage
 * @dev Centralized storage contract for all marketplace data
 */
contract MarketplaceStorage {

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
    address public owner;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ContractAuthorized(address indexed contractAddr, bool authorized);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorized() {
        if(!authorizedContracts[msg.sender]) {
            revert("MStorage: Not authorized");
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert("MStorage: Not owner");
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
        uint256 bidAmount
    ) external onlyAuthorized {
        AuctionDetails storage auction = auctionListings[auctionId];
        auction.highestBidder = bidder;
        auction.highestBid = uint96(bidAmount);

        uint32 bidId = uint32(bidsPlaced[auctionId].length);
        bidsPlaced[auctionId].push(Bid({
            bidAmount: uint96(bidAmount),
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

    function getAuctionDetails(uint256 auctionId) external view returns (
        bool active,
        bool isNFT,
        uint256 startTime,
        uint24 duration,
        address seller,
        address highestBidder,
        uint256 highestBid,
        uint256 tokenIdOrListingId,
        uint256 startingPrice,
        address nftContractAddr,
        uint8 assetType,
        string memory assetId
    ) {
        AuctionDetails memory auction = auctionListings[auctionId];
        return (
            (auction.flags & 1) == 1,
            (auction.flags & 2) == 2,
            uint256(auction.startTime),
            auction.duration,
            auction.seller,
            auction.highestBidder,
            uint256(auction.highestBid),
            auction.tokenIdOrListingId,
            uint256(auction.startingPrice),
            address(auction.nftContract),
            uint8(auction.assetType),
            auction.assetId
        );
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
}
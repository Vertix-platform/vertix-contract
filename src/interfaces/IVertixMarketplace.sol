// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VertixUtils} from "../libraries/VertixUtils.sol";
import {IVertixNFT} from "./IVertixNFT.sol";


/**
 * @title Interface for VertixMarketplace contract
 * @dev Decentralized marketplace for NFT and non-NFT assets with royalties and platform fees
 */
interface IVertixMarketplace {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct Bid {
        uint256 auctionId;
        uint256 bidAmount;
        uint256 bidId;
        address bidder;
    }

    struct NFTListing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }

    struct NonNFTListing {
        address seller;
        bool active;
        string assetId;
        uint256 price;
        string metadata;
        bytes32 verificationHash;
        VertixUtils.AssetType assetType;
    }

    struct AuctionDetails {
        bool active;
        uint24 duration;
        uint256 startTime;
        address seller;
        address highestBidder;
        uint256 highestBid;
        uint256 tokenId;
        uint256 auctionId;
        uint256 startingPrice;
        IVertixNFT nftContract;
    }

    event NonNFTListed(
        uint256 indexed listingId,
        address indexed seller,
        VertixUtils.AssetType assetType,
        string assetId,
        uint256 price
    );
    event NFTBought(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 price,
        uint256 royaltyAmount,
        address royaltyRecipient,
        uint256 platformFee,
        address feeRecipient
    );
    event NonNFTBought(
        uint256 indexed listingId, address indexed buyer, uint256 price, uint256 platformFee, address feeRecipient
    );
    event NFTListed(
        uint256 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price
    );

    event NFTListingCancelled(uint256 indexed listingId, address indexed seller);
    event NonNFTListingCancelled(uint256 indexed listingId, address indexed seller);

    event NFTAuctionStarted(
        uint256 indexed auctionId,
        address indexed seller,
        uint256 startTime,
        uint24 duration,
        uint256 price,
        address nftContract,
        uint256 tokenId
    );

    event BidPlaced(
        uint256 indexed auctionId, uint256 indexed bidId, address indexed seller, uint256 bidAmount, uint256 tokenId
    );

    event AuctionEnded(
        uint256 indexed auctionId, address indexed seller, address indexed bidder, uint256 highestBid, uint256 tokenId
    );

    /**
     * @dev List an NFT for sale
     * @param nftContractAddr Address of NFT contract
     * @param tokenId ID of the NFT
     * @param price Sale price in wei
     */
    function listNFT(address nftContractAddr, uint256 tokenId, uint256 price) external;

    /**
     * @dev List a social media NFT for sale with off-chain price verification
     * @param tokenId ID of the social media NFT
     * @param price Sale price in wei (determined off-chain)
     * @param socialMediaId Social media identifier linked to the NFT
     * @param signature Verification server signature for price and social media ID
     */
    function listSocialMediaNFT(
        uint256 tokenId,
        uint256 price,
        string calldata socialMediaId,
        bytes calldata signature
    ) external;

    /**
     * @dev List a non-NFT asset for sale
     * @param assetType Type of asset (from VertixUtils.AssetType)
     * @param assetId Unique identifier for the asset
     * @param price Sale price in wei
     * @param metadata Additional metadata
     * @param verificationProof Verification data
     */
    function listNonNFTAsset(
        uint8 assetType,
        string calldata assetId,
        uint256 price,
        string calldata metadata,
        bytes calldata verificationProof
    ) external;

    /**
     * @dev Buy an NFT listing, paying royalties and platform fees
     * @param listingId ID of the listing to purchase
     */
    function buyNFT(uint256 listingId) external payable;

    /**
     * @dev Buy a non-NFT asset listing, paying platform fee, initiate escrow
     * @param listingId ID of the listing to purchase
     */
    function buyNonNFTAsset(uint256 listingId) external payable;

    /**
     * @dev Cancel an NFT listing
     * @param listingId The ID of the listing
     */
    function cancelNFTListing(uint256 listingId) external;

    /**
     * @dev Cancel a non-NFT listing
     * @param listingId The ID of the listing
     */
    function cancelNonNFTListing(uint256 listingId) external;

    /**
     * @notice starts an auction for a vertix NFT, which is only callable by the owner
     * @param _nftContract the contract address of the vertix NFT being auctioned
     * @param _tokenId the tokenId of the vertix NFT being auctioned
     * @param _duration the duration of the auction (in seconds)
     * @param _price minimum price being accepted for the auction
     */
    function startNFTAuction(address _nftContract, uint256 _tokenId, uint24 _duration, uint256 _price) external;

    /**
     * @notice Place a bid on an active NFT auction
     * @dev Checks auction validity, minimum bid requirements, and handles bid replacement
     * @param _auctionId The ID of the auction to bid on
     */
    function placeBidForAuction(uint256 _auctionId) external payable;

    /**
     * @notice End an NFT auction after its duration has expired
     * @dev Distributes funds and NFT based on auction outcome
     * @param _auctionId The ID of the auction to end
     */
    function endAuction(uint256 _auctionId) external;



    /*//////////////////////////////////////////////////////////////
                      VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get NFT listing details
     * @param listingId ID of the listing
     */
    function getNFTListing(uint256 listingId) external view returns (NFTListing memory);

    /**
     * @dev Get non-NFT listing details
     * @param listingId ID of the listing
     */
    function getNonNFTListing(uint256 listingId) external view returns (NonNFTListing memory);

    /**
     * @dev Get total number of listings
     */
    function getTotalListings() external view returns (uint256);

    /**
     * @dev Get purchase details
     * @param listingId ID of the listing
     * @return price
     * @return royaltyAmount
     * @return royaltyRecipient
     * @return platformFee
     * @return feeRecipient
     * @return sellerProceeds
     */

    function getPurchaseDetails(uint256 listingId)
        external
        view
        returns (
            uint256 price,
            uint256 royaltyAmount,
            address royaltyRecipient,
            uint256 platformFee,
            address feeRecipient,
            uint256 sellerProceeds
    );

    /**
     * @dev Returns whether a token is listed for auction
     * @param tokenId The ID of the NFT
     * @return bool True if the token is listed for auction, false otherwise
     */
    function isListedForAuction(uint256 tokenId) external view returns (bool);

    /**
     * @dev Returns the auction ID associated with a token
     * @param tokenId The ID of the NFT
     * @return uint256 The auction ID for the token, or 0 if not listed
     */
    function getAuctionIdForToken(uint256 tokenId) external view returns (uint256);

    /**
     * @dev Returns the token ID being auctioned
     * @param _auctionId The ID of the auction
     * @return uint256 The token ID of the NFT being auctioned
     */
    function getTokenIdForAuction(uint256 _auctionId) external view returns (uint256);

    /**
     * @dev Retrieves a specific bid for an auction
     * @param _auctionId The ID of the auction
     * @param _bidId The ID of the bid (index in the bids array)
     * @return Bid The bid details
     */
    function getSingleBidForAuction(uint256 _auctionId, uint256 _bidId) external view returns (Bid memory);

    /**
     * @dev Retrieves the total number of bids for an auction
     * @param _auctionId The ID of the auction
     * @return uint256 The number of bids
     */
    function getBidCountForAuction(uint256 _auctionId) external view returns (uint256);

    /**
     * @dev Returns the details of an auction
     * @param auctionId The ID of the auction
     * @return AuctionDetails The auction details struct
     */
    function getAuctionDetails(uint256 auctionId) external view returns (AuctionDetails memory);

    // @inherit-doc
    function onERC721Received(address,address,uint256,bytes calldata) external pure returns (bytes4);
}

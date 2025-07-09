// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IVertixGovernance} from "./interfaces/IVertixGovernance.sol";
import {IVertixEscrow} from "./interfaces/IVertixEscrow.sol";
import {MarketplaceStorage} from "./MarketplaceStorage.sol";
import {MarketplaceFees} from "./MarketplaceFees.sol";

/**
 * @title MarketplaceAuctions
 * @dev Handles all auction-related functionality with gas-optimized operations
 */
contract MarketplaceAuctions is ReentrancyGuardUpgradeable, PausableUpgradeable {

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error MA__InvalidDuration(uint24 duration);
    error MA__AlreadyListedForAuction();
    error MA__AuctionExpired();
    error MA__BidTooLow(uint256 bidAmount);
    error MA__AuctionInactive();
    error MA__InsufficientBalance();
    error MA__AuctionOngoing(uint256 timestamp);
    error MA__TransferFailed();
    error MA__NotSeller();
    error MA__NotListedForAuction();
    error MA__InvalidListing();
    error MA__InsufficientPayment();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    MarketplaceStorage public immutable STORAGE_CONTRACT;
    MarketplaceFees public immutable FEES_CONTRACT;
    IVertixGovernance public immutable GOVERNANCE_CONTRACT;
    IVertixEscrow public immutable ESCROW_CONTRACT;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event NFTAuctionStarted(
        uint256 indexed auctionId,
        address indexed seller,
        uint256 startTime,
        uint24 duration,
        uint256 price,
        address nftContract,
        uint256 tokenId
    );

    event NonNFTAuctionStarted(
        uint256 indexed auctionId,
        address indexed seller,
        uint256 startTime,
        uint24 duration,
        uint256 price,
        string assetId,
        uint8 assetType
    );

    event BidPlaced(
        uint256 indexed auctionId,
        uint256 indexed bidId,
        address indexed bidder,
        uint256 bidAmount,
        uint256 tokenId
    );

    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed bidder,
        uint256 highestBid,
        uint256 tokenId
    );

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _storageContract,
        address _governanceContract,
        address _escrowContract,
        address _feesContract
    ) {
        STORAGE_CONTRACT = MarketplaceStorage(_storageContract);
        GOVERNANCE_CONTRACT = IVertixGovernance(_governanceContract);
        ESCROW_CONTRACT = IVertixEscrow(_escrowContract);
        FEES_CONTRACT = MarketplaceFees(_feesContract);

        _disableInitializers();
    }

    function initialize() external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Common validation for auction creation
     * @param duration Auction duration in seconds
     * @param startingPrice Starting price for auction
     */
    function _validateAuctionRequirements(
        uint24 duration,
        uint96 startingPrice
    ) internal view {
        uint24 minDuration = STORAGE_CONTRACT.MIN_AUCTION_DURATION();
        uint24 maxDuration = STORAGE_CONTRACT.MAX_AUCTION_DURATION();
        if (duration < minDuration || duration > maxDuration) revert MA__InvalidDuration(duration);
        if (startingPrice == 0) revert MA__InsufficientPayment();
    }

    /**
     * @dev Common validation for auction listing access
     * @param seller Address of the seller
     * @param active Whether the listing is active
     * @param auctionListed Whether the item is listed for auction
     * @param alreadyInAuction Whether the item is already in an auction
     */
    function _validateAuctionAccess(
        address seller,
        bool active,
        bool auctionListed,
        bool alreadyInAuction
    ) internal view {
        if (!active) revert MA__InvalidListing();
        if (msg.sender != seller) revert MA__NotSeller();
        if (!auctionListed) revert MA__NotListedForAuction();
        if (alreadyInAuction) revert MA__AlreadyListedForAuction();
    }

    /**
     * @dev Common auction creation logic
     * @param seller Address of the seller
     * @param tokenIdOrListingId Token ID (for NFT) or listing ID (for non-NFT)
     * @param startingPrice Starting price for auction
     * @param duration Auction duration in seconds
     * @param isNft Whether this is an NFT auction
     * @param nftContractAddr NFT contract address (for NFT auctions)
     * @param assetType Asset type (for non-NFT auctions)
     * @param assetId Asset ID (for non-NFT auctions)
     */
    function _createAuction(
        address seller,
        uint256 tokenIdOrListingId,
        uint96 startingPrice,
        uint24 duration,
        bool isNft,
        address nftContractAddr,
        uint8 assetType,
        string memory assetId
    ) internal returns (uint256 auctionId) {
        auctionId = STORAGE_CONTRACT.createAuction(
            seller,
            tokenIdOrListingId,
            startingPrice,
            duration,
            isNft,
            nftContractAddr,
            assetType,
            assetId
        );

        if (isNft) {
            emit NFTAuctionStarted(auctionId, seller, block.timestamp, duration, startingPrice, nftContractAddr, tokenIdOrListingId);
        } else {
            emit NonNFTAuctionStarted(auctionId, seller, block.timestamp, duration, startingPrice, assetId, assetType);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           AUCTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Start NFT auction
     * @param listingId ID of the NFT listing
     * @param duration Auction duration in seconds
     * @param startingPrice Starting price for auction
     */
    function startNftAuction(
        uint256 listingId,
        uint24 duration,
        uint96 startingPrice
    ) external nonReentrant whenNotPaused {
        (
            address seller,
            address nftContractAddr,
            uint256 tokenId,
            ,
            bool active,
            bool auctionListed
        ) = STORAGE_CONTRACT.getNftListing(listingId);

        _validateAuctionAccess(seller, active, auctionListed, STORAGE_CONTRACT.isTokenListedForAuction(tokenId));

        _validateAuctionRequirements(duration, startingPrice);

        _createAuction(seller, tokenId, startingPrice, duration, true, nftContractAddr, 0, "");
    }

    /**
     * @dev Start non-NFT auction
     * @param listingId ID of the non-NFT listing
     * @param duration Auction duration in seconds
     * @param startingPrice Starting price for auction
     */
    function startNonNftAuction(
        uint256 listingId,
        uint24 duration,
        uint96 startingPrice
    ) external nonReentrant whenNotPaused {
        (
            address seller,
            ,
            uint8 assetType,
            bool active,
            bool auctionListed,
            string memory assetId,
            ,
        ) = STORAGE_CONTRACT.getNonNftListing(listingId);

        _validateAuctionAccess(seller, active, auctionListed, STORAGE_CONTRACT.isTokenListedForAuction(listingId));

        _validateAuctionRequirements(duration, startingPrice);

        _createAuction(seller, listingId, startingPrice, duration, false, address(0), assetType, assetId);
    }

    /**
     * @dev Place bid on auction
     * @param auctionId The auction to bid on
     */
    function placeBid(uint256 auctionId) external payable nonReentrant {
        MarketplaceStorage.AuctionDetailsView memory auction = STORAGE_CONTRACT.getAuctionDetailsView(auctionId);

        if (!auction.active) revert MA__AuctionInactive();

        uint256 endTime;
        unchecked {
            endTime = auction.startTime + auction.duration; // duration is bounded by MAX_AUCTION_DURATION
        }
        if (block.timestamp > endTime) revert MA__AuctionExpired();

        (uint256 platformFeeBps, ) = GOVERNANCE_CONTRACT.getFeeConfig();
        uint256 minBid;
        unchecked {
            minBid = (auction.startingPrice * platformFeeBps) / 10000;
        }

        if (msg.value < auction.startingPrice || msg.value <= auction.highestBid || msg.value < minBid) {
            revert MA__BidTooLow(msg.value);
        }

        // Refund previous highest bidder if exists
        uint256 currentHighestBid = auction.highestBid;
        address currentHighestBidder = auction.highestBidder;
        if (currentHighestBid > 0) {
            uint256 contractBalance = address(this).balance;
            unchecked {
                if (contractBalance - msg.value < currentHighestBid) {
                    revert MA__InsufficientBalance();
                }
            }
            (bool success, ) = payable(currentHighestBidder).call{value: currentHighestBid}("");
            if (!success) {
                revert MA__TransferFailed();
            }
        }

        // Update auction with new highest bid
        STORAGE_CONTRACT.updateAuctionBid(auctionId, msg.sender, msg.value);

        uint256 bidId = STORAGE_CONTRACT.getBidsCount(auctionId) - 1; // Just added, so -1 for current bid
        emit BidPlaced(auctionId, bidId, msg.sender, msg.value, auction.tokenIdOrListingId);
    }

    /**
     * @dev End auction and distribute funds/assets - gas optimized
     * @param auctionId The auction to end
     */
    function endAuction(uint256 auctionId) external nonReentrant whenNotPaused {
        MarketplaceStorage.AuctionDetailsView memory auction = STORAGE_CONTRACT.getAuctionDetailsView(auctionId);

        if (auction.seller != msg.sender) revert MA__NotSeller();
        if (!auction.active) revert MA__AuctionInactive();

        uint256 endTime;
        unchecked {
            endTime = auction.startTime + auction.duration;
        }
        if (block.timestamp < endTime) {
            revert MA__AuctionOngoing(block.timestamp);
        }

        // Mark auction as ended
        STORAGE_CONTRACT.endAuction(auctionId);

        // Distribute funds via MarketplaceFees
        address highestBidder = auction.highestBidder;
        uint256 highestBid = auction.highestBid;
        if (highestBidder != address(0)) {
            FEES_CONTRACT.processAuctionPayment{value: highestBid}(
                auction.highestBid,
                auction.seller,
                auction.nftContractAddr,
                auction.tokenIdOrListingId,
                auction.isNft,
                auctionId
            );
        }

        emit AuctionEnded(auctionId, auction.seller, auction.highestBidder, auction.highestBid, auction.tokenIdOrListingId);
    }


    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get auction details
     */
    function getAuctionInfo(uint256 auctionId) external view returns (
        bool active,
        bool isNft,
        uint256 startTime,
        uint24 duration,
        uint256 endTime,
        address seller,
        address highestBidder,
        uint256 highestBid,
        uint256 startingPrice
    ) {
        MarketplaceStorage.AuctionDetailsView memory auction = STORAGE_CONTRACT.getAuctionDetailsView(auctionId);

        unchecked {
            endTime = auction.startTime + auction.duration;
        }
    }

    /**
     * @dev Check if auction has expired
     */
    function isAuctionExpired(uint256 auctionId) external view returns (bool) {
        MarketplaceStorage.AuctionDetailsView memory auction = STORAGE_CONTRACT.getAuctionDetailsView(auctionId);

        unchecked {
            return block.timestamp > auction.startTime + auction.duration;
        }
    }

    /**
     * @dev Get time remaining in auction
     */
    function getTimeRemaining(uint256 auctionId) external view returns (uint256) {
        MarketplaceStorage.AuctionDetailsView memory auction = STORAGE_CONTRACT.getAuctionDetailsView(auctionId);

        uint256 endTime;
        unchecked {
            endTime = auction.startTime + auction.duration;
        }

        if (block.timestamp >= endTime) return 0;
        unchecked {
            return endTime - block.timestamp;
        }
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external {
        // Access control handled by storage contract owner
        if (msg.sender != STORAGE_CONTRACT.owner()) revert MA__NotSeller();
        _pause();
    }

    function unpause() external {
        if (msg.sender != STORAGE_CONTRACT.owner()) revert MA__NotSeller();
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    receive() external payable {
        // Allow contract to receive ETH for bid refunds
    }
}
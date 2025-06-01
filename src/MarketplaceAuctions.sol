// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {VertixUtils} from "./libraries/VertixUtils.sol";
import {IVertixNFT} from "./interfaces/IVertixNFT.sol";
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
    MarketplaceStorage public immutable storageContract;
    MarketplaceFees public immutable feesContract;
    IVertixGovernance public immutable governanceContract;
    IVertixEscrow public immutable escrowContract;

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
        storageContract = MarketplaceStorage(_storageContract);
        governanceContract = IVertixGovernance(_governanceContract);
        escrowContract = IVertixEscrow(_escrowContract);
        feesContract = MarketplaceFees(_feesContract);

        _disableInitializers();
    }

    function initialize() external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
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
    function startNFTAuction(
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
        ) = storageContract.getNFTListing(listingId);

        if (!active) revert MA__InvalidListing();
        if (msg.sender != seller) revert MA__NotSeller();
        if (!auctionListed) revert MA__NotListedForAuction();
        if (storageContract.isTokenListedForAuction(tokenId)) revert MA__AlreadyListedForAuction();

        uint24 minDuration = storageContract.MIN_AUCTION_DURATION();
        uint24 maxDuration = storageContract.MAX_AUCTION_DURATION();
        if (duration < minDuration || duration > maxDuration) revert MA__InvalidDuration(duration);

        if (startingPrice == 0) revert MA__InsufficientPayment();

        uint256 auctionId = storageContract.createAuction(
            seller,
            tokenId,
            startingPrice,
            duration,
            true, // isNFT
            nftContractAddr,
            0, // assetType (unused for NFT)
            "" // assetId (unused for NFT)
        );

        emit NFTAuctionStarted(auctionId, seller, block.timestamp, duration, startingPrice, nftContractAddr, tokenId);
    }

    /**
     * @dev Start non-NFT auction
     * @param listingId ID of the non-NFT listing
     * @param duration Auction duration in seconds
     * @param startingPrice Starting price for auction
     */
    function startNonNFTAuction(
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
        ) = storageContract.getNonNFTListing(listingId);

        if (!active) revert MA__InvalidListing();
        if (msg.sender != seller) revert MA__NotSeller();
        if (!auctionListed) revert MA__NotListedForAuction();
        if (storageContract.isTokenListedForAuction(listingId)) revert MA__AlreadyListedForAuction();

        uint24 minDuration = storageContract.MIN_AUCTION_DURATION();
        uint24 maxDuration = storageContract.MAX_AUCTION_DURATION();
        if (duration < minDuration || duration > maxDuration) revert MA__InvalidDuration(duration);

        if (startingPrice == 0) revert MA__InsufficientPayment();

        uint256 auctionId = storageContract.createAuction(
            seller,
            listingId,
            startingPrice,
            duration,
            false, // isNFT
            address(0), // nftContract (unused for non-NFT)
            assetType,
            assetId
        );

        emit NonNFTAuctionStarted(auctionId, seller, block.timestamp, duration, startingPrice, assetId, assetType);
    }

    /**
     * @dev Place bid on auction
     * @param auctionId The auction to bid on
     */
    function placeBid(uint256 auctionId) external payable nonReentrant {
        (
            bool active,
            ,
            uint256 startTime,
            uint24 duration,
            ,
            address currentHighestBidder,
            uint256 currentHighestBid,
            uint256 tokenIdOrListingId,
            uint256 startingPrice,
            ,
            ,
        ) = storageContract.getAuctionDetails(auctionId);

        if (!active) revert MA__AuctionInactive();

        uint256 endTime;
        unchecked {
            endTime = startTime + duration; // duration is bounded by MAX_AUCTION_DURATION
        }
        if (block.timestamp > endTime) revert MA__AuctionExpired();

        (uint256 platformFeeBps, ) = governanceContract.getFeeConfig();
        uint256 minBid;
        unchecked {
            minBid = (startingPrice * platformFeeBps) / 10000;
        }

        if (msg.value < startingPrice || msg.value <= currentHighestBid || msg.value < minBid) {
            revert MA__BidTooLow(msg.value);
        }

        // Refund previous highest bidder if exists
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
        storageContract.updateAuctionBid(auctionId, msg.sender, msg.value);

        uint256 bidId = storageContract.getBidsCount(auctionId) - 1; // Just added, so -1 for current bid
        emit BidPlaced(auctionId, bidId, msg.sender, msg.value, tokenIdOrListingId);
    }

    /**
     * @dev End auction and distribute funds/assets - gas optimized
     * @param auctionId The auction to end
     */
    function endAuction(uint256 auctionId) external nonReentrant whenNotPaused {
        (
            bool active,
            bool isNFT,
            uint256 startTime,
            uint24 duration,
            address seller,
            address highestBidder,
            uint256 highestBid,
            uint256 tokenIdOrListingId,
            ,
            address nftContractAddr,
            ,
        ) = storageContract.getAuctionDetails(auctionId);

        if (seller != msg.sender) revert MA__NotSeller();
        if (!active) revert MA__AuctionInactive();

        uint256 endTime;
        unchecked {
            endTime = startTime + duration;
        }
        if (block.timestamp < endTime) {
            revert MA__AuctionOngoing(block.timestamp);
        }

        // Mark auction as ended
        storageContract.endAuction(auctionId);

        // Distribute funds via MarketplaceFees
        if (highestBidder != address(0)) {
            feesContract.processAuctionPayment{value: highestBid}(
                highestBid,
                seller,
                nftContractAddr,
                tokenIdOrListingId,
                isNFT,
                auctionId
            );
        }

        emit AuctionEnded(auctionId, seller, highestBidder, highestBid, tokenIdOrListingId);
    }


    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get auction details
     */
    function getAuctionInfo(uint256 auctionId) external view returns (
        bool active,
        bool isNFT,
        uint256 startTime,
        uint24 duration,
        uint256 endTime,
        address seller,
        address highestBidder,
        uint256 highestBid,
        uint256 startingPrice
    ) {
        (
            active,
            isNFT,
            startTime,
            duration,
            seller,
            highestBidder,
            highestBid,
            ,
            startingPrice,
            ,
            ,
        ) = storageContract.getAuctionDetails(auctionId);

        unchecked {
            endTime = startTime + duration;
        }
    }

    /**
     * @dev Check if auction has expired
     */
    function isAuctionExpired(uint256 auctionId) external view returns (bool) {
        (, , uint256 startTime, uint24 duration, , , , , , , , ) = 
            storageContract.getAuctionDetails(auctionId);

        unchecked {
            return block.timestamp > startTime + duration;
        }
    }

    /**
     * @dev Get time remaining in auction
     */
    function getTimeRemaining(uint256 auctionId) external view returns (uint256) {
        (, , uint256 startTime, uint24 duration, , , , , , , , ) =
            storageContract.getAuctionDetails(auctionId);

        uint256 endTime;
        unchecked {
            endTime = startTime + duration;
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
        if (msg.sender != storageContract.owner()) revert MA__NotSeller();
        _pause();
    }

    function unpause() external {
        if (msg.sender != storageContract.owner()) revert MA__NotSeller();
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    receive() external payable {
        // Allow contract to receive ETH for bid refunds
    }
}
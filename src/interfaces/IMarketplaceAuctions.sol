// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IMarketplaceAuctions {
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

}
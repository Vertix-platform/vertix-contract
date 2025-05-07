// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VertixUtils} from "../libraries/VertixUtils.sol";

// Interface for the VertixMarketplace contract
interface IVertixMarketplace {
    // Structs for listings
    struct NFTListing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }

    struct NonNFTListing {
        address seller;
        VertixUtils.AssetType assetType;
        string assetId;
        uint256 price;
        string metadata;
        bytes32 verificationHash;
        bool active;
    }

    // List an NFT for sale
    function listNFT(address nftContract, uint256 tokenId, uint256 price) external;

    // List a non-NFT asset for sale
    function listNonNFTAsset(
        uint8 assetType,
        string calldata assetId,
        uint256 price,
        string calldata metadata,
        bytes calldata verificationProof
    ) external;

    // Buy an NFT
    function buyNFT(uint256 listingId) external payable;

    // Buy a non-NFT asset (initiates escrow)
    function buyNonNFTAsset(uint256 listingId) external payable;

    // Get NFT listing details
    function getNFTListing(uint256 listingId) external view returns (NFTListing memory);

    // Get non-NFT listing details
    function getNonNFTListing(uint256 listingId) external view returns (NonNFTListing memory);

    // Get total number of listings
    function getTotalListings() external view returns (uint256);

    // Events
    event NFTListed(
        uint256 indexed listingId,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );
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
    event NonNFTBought(uint256 indexed listingId, address indexed buyer, uint256 price, uint256 platformFee, address feeRecipient);
}
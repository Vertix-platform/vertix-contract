// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title ICrossChainMarketplace
 * @dev Interface for cross-chain marketplace functionality
 * @notice This interface defines functions for receiving listings from MarketplaceCore and handling cross-chain purchases
 */
interface ICrossChainMarketplace {
    
    // Structs
    struct CrossChainListing {
        uint16 sourceChainId;
        uint256 sourceListingId;
        address seller;
        address nftContract;
        uint256 tokenId;
        uint96 price;
        bool isActive;
        bool isNFT;
        string assetId;
        uint8 assetType;
    }

    struct CrossChainPurchase {
        uint16 sourceChainId;
        uint256 sourceListingId;
        address buyer;
        uint256 purchaseId;
        uint96 price;
        bool isCompleted;
    }

    // Events
    event CrossChainListingCreated(
        uint16 indexed sourceChainId,
        uint256 indexed sourceListingId,
        bytes32 indexed listingHash,
        address seller,
        uint96 price
    );

    event CrossChainListingCancelled(
        uint16 indexed sourceChainId,
        uint256 indexed sourceListingId,
        bytes32 indexed listingHash
    );

    event CrossChainPurchaseInitiated(
        uint16 indexed sourceChainId,
        uint256 indexed sourceListingId,
        uint256 indexed purchaseId,
        address buyer,
        uint96 price
    );

    event CrossChainPurchaseCompleted(
        uint16 indexed sourceChainId,
        uint256 indexed sourceListingId,
        uint256 indexed purchaseId,
        address buyer
    );

    event MarketplaceCoreUpdated(uint16 indexed chainId, address indexed marketplaceCoreAddress);

    // Errors
    error CCM__InvalidChain();
    error CCM__InvalidListing();
    error CCM__InsufficientPayment();
    error CCM__ListingNotActive();
    error CCM__PurchaseNotFound();
    error CCM__UnauthorizedSource();
    error CCM__InvalidPayload();
    error CCM__InvalidMarketplaceCore();
    error CCM__MarketplaceCoreNotSet();


    // Configuration functions
    function setMarketplaceCore(uint16 chainId, address marketplaceCoreAddress) external;
    
    function getMarketplaceCore(uint16 chainId) external view returns (address);

    // Core functions
    function purchaseCrossChain(
        uint16 sourceChainId,
        uint256 sourceListingId,
        bytes32 listingHash
    ) external payable;
    
    function cancelCrossChainListing(
        uint16 sourceChainId,
        uint256 sourceListingId,
        bytes32 listingHash
    ) external payable;

    // View functions
    function getCrossChainListing(bytes32 listingHash) external view returns (CrossChainListing memory);
    
    function getCrossChainPurchase(uint256 purchaseId) external view returns (CrossChainPurchase memory);
    
    function generateListingHash(
        uint16 sourceChainId,
        uint256 sourceListingId,
        address seller
    ) external pure returns (bytes32);
    
    function getSupportedChains() external pure returns (uint16[] memory);

    // Admin functions
    function addSupportedChain(uint16 chainId) external;
    
    function removeSupportedChain(uint16 chainId) external;


} 
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NonblockingLzApp} from "lib/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";

/**
 * @title CrossChainMarketplace
 * @dev Enables cross-chain marketplace functionality - receives listings from MarketplaceCore and handles cross-chain purchases
 * @notice This contract receives listing broadcasts from MarketplaceCore contracts and enables cross-chain purchases
 */
contract CrossChainMarketplace is ReentrancyGuard, Ownable, NonblockingLzApp {

    // Constants for cross-chain message types
    uint16 private constant MSG_TYPE_LISTING_CREATED = 1;
    uint16 private constant MSG_TYPE_LISTING_CANCELLED = 2;
    uint16 private constant MSG_TYPE_CROSS_CHAIN_PURCHASE = 3;
    uint16 private constant MSG_TYPE_PURCHASE_COMPLETED = 4;

    // Structs for cross-chain data
    struct CrossChainListing {
        uint16 sourceChainId;
        uint256 sourceListingId;
        address seller;
        address nftContract;
        uint256 tokenId;
        uint96 price;
        bool isActive;
        bool isNFT;
        string assetId; // For non-NFT assets
        uint8 assetType; // For non-NFT assets
    }

    struct CrossChainPurchase {
        uint16 sourceChainId;
        uint256 sourceListingId;
        address buyer;
        uint256 purchaseId;
        uint96 price;
        bool isCompleted;
    }

    // State variables
    mapping(uint16 => bool) public supportedChains;
    mapping(uint16 => address) public marketplaceCoreAddresses;
    mapping(bytes32 => CrossChainListing) public crossChainListings;
    mapping(uint256 => CrossChainPurchase) public crossChainPurchases;

    uint256 private purchaseIdCounter;
    uint256 private nonce;

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

    constructor(
        address _lzEndpoint
    ) NonblockingLzApp(_lzEndpoint) Ownable(msg.sender) {
        // Initialize supported chains (testnet)
        supportedChains[10109] = true; // Polygon Mumbai
        supportedChains[10160] = true; // Base Goerli
    }

    /*//////////////////////////////////////////////////////////////
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Set the MarketplaceCore contract address for a specific chain
     * @param chainId The LayerZero chain ID
     * @param marketplaceCoreAddress The address of the MarketplaceCore contract on that chain
     */
    function setMarketplaceCore(uint16 chainId, address marketplaceCoreAddress) external onlyOwner {
        if (marketplaceCoreAddress == address(0)) revert CCM__InvalidMarketplaceCore();

        marketplaceCoreAddresses[chainId] = marketplaceCoreAddress;
        emit MarketplaceCoreUpdated(chainId, marketplaceCoreAddress);
    }

    /**
     * @dev Get the MarketplaceCore address for a specific chain
     * @param chainId The LayerZero chain ID
     * @return The address of the MarketplaceCore contract
     */
    function getMarketplaceCore(uint16 chainId) external view returns (address) {
        return marketplaceCoreAddresses[chainId];
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN PURCHASE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Purchase an item listed on another chain
     * @param sourceChainId The chain where the item is listed
     * @param sourceListingId The listing ID on the source chain
     * @param listingHash The hash of the listing for verification
     */
    function purchaseCrossChain(
        uint16 sourceChainId,
        uint256 sourceListingId,
        bytes32 listingHash
    ) external payable nonReentrant {
        if (!supportedChains[sourceChainId]) revert CCM__InvalidChain();

        CrossChainListing memory listing = crossChainListings[listingHash];
        if (!listing.isActive) revert CCM__ListingNotActive();
        if (msg.value < listing.price) revert CCM__InsufficientPayment();

                // Create purchase record
        uint256 purchaseId = purchaseIdCounter++;
        crossChainPurchases[purchaseId] = CrossChainPurchase({
            sourceChainId: sourceChainId,
            sourceListingId: sourceListingId,
            buyer: msg.sender,
            purchaseId: purchaseId,
            price: listing.price,
            isCompleted: false
        });

        // Mark listing as inactive locally (EFFECTS before external calls)
        crossChainListings[listingHash].isActive = false;

        // Estimate cross-chain message fee
        (uint256 nativeFee,) = lzEndpoint.estimateFees(
            sourceChainId,
            address(this),
            abi.encode(MSG_TYPE_CROSS_CHAIN_PURCHASE, sourceListingId, msg.sender, purchaseId, listing.price),
            false,
            bytes("")
        );

        // For NFTs, we need to account for bridge fees as well
        uint256 totalRequiredFee = listing.price + nativeFee;

        // Note: Bridge fees are estimated and paid by the MarketplaceCore on the source chain
        // The user should send enough ETH to cover: NFT price + LayerZero message fee
        // Additional bridge fees will be deducted from the purchase price on the source chain

        if (msg.value < totalRequiredFee) revert CCM__InsufficientPayment();

        // Send purchase message to source chain MarketplaceCore (INTERACTIONS)
        // Include the total payment amount so the source chain can use it for bridge fees
        bytes memory payload = abi.encode(
            MSG_TYPE_CROSS_CHAIN_PURCHASE,
            sourceListingId,
            msg.sender,
            purchaseId,
            listing.price,
            listing.isNFT,
            msg.value - nativeFee, // Amount available for purchase + bridge fees
            nonce++
        );

        _sendToMarketplaceCore(sourceChainId, payload, nativeFee);

        emit CrossChainPurchaseInitiated(
            sourceChainId,
            sourceListingId,
            purchaseId,
            msg.sender,
            listing.price
        );
    }

    /**
     * @dev Cancel a cross-chain listing (only callable by the original seller)
     * @param sourceChainId The chain where the item is listed
     * @param sourceListingId The listing ID to cancel
     * @param listingHash The hash of the listing
     */
    function cancelCrossChainListing(
        uint16 sourceChainId,
        uint256 sourceListingId,
        bytes32 listingHash
    ) external payable nonReentrant {
        CrossChainListing memory listing = crossChainListings[listingHash];
        if (listing.seller != msg.sender) revert CCM__UnauthorizedSource();
        if (!listing.isActive) revert CCM__ListingNotActive();

        // Send cancellation message to source chain
        bytes memory payload = abi.encode(
            MSG_TYPE_LISTING_CANCELLED,
            sourceListingId,
            msg.sender,
            nonce++
        );

        _sendToMarketplaceCore(sourceChainId, payload, msg.value);

        // Mark listing as inactive locally
        crossChainListings[listingHash].isActive = false;

        emit CrossChainListingCancelled(sourceChainId, sourceListingId, listingHash);
    }

    /*//////////////////////////////////////////////////////////////
                        LAYERZERO MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 /*_nonce*/,
        bytes memory _payload
    ) internal override {
        // Verify the message is from an authorized MarketplaceCore contract
        address expectedMarketplaceCore = marketplaceCoreAddresses[_srcChainId];
        if (expectedMarketplaceCore == address(0)) revert CCM__UnauthorizedSource();

        // Decode the source address from LayerZero message
        address sourceSender;
        assembly {
            sourceSender := mload(add(_srcAddress, 20))
        }

        if (sourceSender != expectedMarketplaceCore) revert CCM__UnauthorizedSource();

        uint16 msgType = abi.decode(_payload, (uint16));

        if (msgType == MSG_TYPE_LISTING_CREATED) {
            _handleListingCreated(_srcChainId, _payload);
        } else if (msgType == MSG_TYPE_LISTING_CANCELLED) {
            _handleListingCancelled(_srcChainId, _payload);
        } else if (msgType == MSG_TYPE_PURCHASE_COMPLETED) {
            _handlePurchaseCompleted(_srcChainId, _payload);
        } else {
            revert CCM__InvalidPayload();
        }
    }

    function _handleListingCreated(uint16 _srcChainId, bytes memory _payload) internal {
        (
            , // msgType - not used after decoding
            uint256 sourceListingId,
            address seller,
            address nftContract,
            uint256 tokenId,
            uint96 price,
            bool isNFT,
            string memory assetId,
            uint8 assetType,
            // _nonce - not used after decoding
        ) = abi.decode(_payload, (uint16, uint256, address, address, uint256, uint96, bool, string, uint8, uint256));

        bytes32 listingHash = keccak256(abi.encodePacked(_srcChainId, sourceListingId, seller));

        crossChainListings[listingHash] = CrossChainListing({
            sourceChainId: _srcChainId,
            sourceListingId: sourceListingId,
            seller: seller,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            isActive: true,
            isNFT: isNFT,
            assetId: assetId,
            assetType: assetType
        });

        emit CrossChainListingCreated(_srcChainId, sourceListingId, listingHash, seller, price);
    }

    function _handleListingCancelled(uint16 _srcChainId, bytes memory _payload) internal {
        (
            , // msgType - not used after decoding
            uint256 sourceListingId,
            address seller,
            // _nonce - not used after decoding
        ) = abi.decode(_payload, (uint16, uint256, address, uint256));

        bytes32 listingHash = keccak256(abi.encodePacked(_srcChainId, sourceListingId, seller));
        crossChainListings[listingHash].isActive = false;

        emit CrossChainListingCancelled(_srcChainId, sourceListingId, listingHash);
    }

    function _handlePurchaseCompleted(uint16 _srcChainId, bytes memory _payload) internal {
        (
            , // msgType - not used after decoding
            uint256 sourceListingId,
            address buyer,
            uint256 purchaseId,
            , // price - not used after decoding
            , // isNFT - not used after decoding
            // _nonce - not used after decoding
        ) = abi.decode(_payload, (uint16, uint256, address, uint256, uint96, bool, uint256));

        // Mark purchase as completed
        crossChainPurchases[purchaseId].isCompleted = true;

        emit CrossChainPurchaseCompleted(_srcChainId, sourceListingId, purchaseId, buyer);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Send message to MarketplaceCore on a specific chain
     * @param chainId The destination chain ID
     * @param payload The message payload
     * @param fee The LayerZero fee for the message
     */
    function _sendToMarketplaceCore(uint16 chainId, bytes memory payload, uint256 fee) internal {
        address marketplaceCore = marketplaceCoreAddresses[chainId];
        if (marketplaceCore == address(0)) revert CCM__MarketplaceCoreNotSet();

        _lzSend(
            chainId,
            payload,
            payable(msg.sender),
            address(0),
            bytes(""),
            fee
        );
    }

    /*//////////////////////////////////////////////////////////////
                        UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getSupportedChains() external view returns (uint16[] memory) {
        uint16[] memory chains = new uint16[](2);
        uint256 count = 0;

        // Only return chains that are actually supported
        if (supportedChains[10109]) {
            chains[count++] = 10109; // Polygon Mumbai
        }
        if (supportedChains[10160]) {
            chains[count++] = 10160; // Base Goerli
        }

        // Resize array to actual count
        assembly {
            mstore(chains, count)
        }

        return chains;
    }

    function getCrossChainListing(bytes32 listingHash) external view returns (CrossChainListing memory) {
        return crossChainListings[listingHash];
    }

    function getCrossChainPurchase(uint256 purchaseId) external view returns (CrossChainPurchase memory) {
        return crossChainPurchases[purchaseId];
    }

    function generateListingHash(
        uint16 sourceChainId,
        uint256 sourceListingId,
        address seller
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(sourceChainId, sourceListingId, seller));
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addSupportedChain(uint16 chainId) external onlyOwner {
        supportedChains[chainId] = true;
    }

    function removeSupportedChain(uint16 chainId) external onlyOwner {
        supportedChains[chainId] = false;
    }

    receive() external payable {}
}
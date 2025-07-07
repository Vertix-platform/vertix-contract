// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {VertixUtils} from "../libraries/VertixUtils.sol";
import {IVertixNFT} from "./IVertixNFT.sol";


/**
 * @title Interface for MarketplaceCore contract
 * @dev Decentralized marketplace for NFT and non-NFT assets with royalties and platform fees
 */
interface IMarketplaceCore {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error MC__InvalidListing();
    error MC__NotOwner();
    error MC__InsufficientPayment();
    error MC__TransferFailed();
    error MC__DuplicateListing();
    error MC__NotSeller();
    error MC__InvalidAssetType();

    error MC__InvalidNFTContract();
    error MC__InvalidSocialMediaNFT();
    error MC__InvalidSignature();
    error Mc_AlreadyListedForAuction();

    error MC__InsufficientQuantity();
    error MC__NotApproved();
    error MC__InvalidTokenContract();
    error MC__InsufficientBalance();
    error MC_WithdrawFailed();
    error MC_InvalidIRecipient();
    error MC__InsufficientCrossChainFee();

    error MC__CrossChainMarketplaceNotSet();
    error MC__InvalidCrossChainMarketplace();
    
    error MarketplaceCore__InvalidEndpointCaller();
    error MarketplaceCore__InvalidSourceAddressLength();
    error MarketplaceCore__InvalidSourceAddress();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
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
        uint8 assetType,
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
        uint256 indexed listingId,
        address indexed buyer,
        uint256 price,
        uint256 sellerAmount,
        uint256 platformFee,
        address feeRecipient
    );
    event NFTListingCancelled(uint256 indexed listingId, address indexed seller, bool isNFT);
    event NonNFTListingCancelled(uint256 indexed listingId, address indexed seller, bool isNFT);
    event ListedForAuction(uint256 indexed listingId, bool isNFT, bool isListedForAuction);

    event TokensListed(
        uint256 indexed listingId,
        address indexed seller,
        address tokenContract,
        uint256 indexed tokenId,
        uint256 quantity,
        uint256 pricePerToken
    );

    event TokensBought(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 quantity,
        uint256 totalPrice,
        uint256 royaltyAmount,
        address royaltyRecipient
    );

    event BatchTokensListed(
        uint256[] indexed listingIds,
        address indexed seller,
        address tokenContract,
        uint256[] tokenIds,
        uint256[] quantities,
        uint96[] pricesPerToken
    );

    event BatchTokensBought(
        uint256[] indexed listingIds,
        address indexed buyer,
        uint256[] quantities,
        uint256[] totalPrices
    );

    // Cross-chain events
    event CrossChainListingBroadcast(uint256 indexed listingId, bool isNFT);
    event CrossChainListingReceived(uint16 indexed sourceChainId, bytes payload);

    event CrossChainBroadcastFailed(uint16 indexed chainId);

    event CrossChainNFTPurchaseExecuted(
        uint256 indexed listingId,
        address indexed buyer,
        uint16 indexed buyerChainId,
        uint256 purchaseId,
        address nftContract,
        uint256 tokenId,
        uint96 price
    );
    event CrossChainNonNFTPurchaseExecuted(
        uint256 indexed listingId,
        address indexed buyer,
        uint16 indexed buyerChainId,
        uint256 purchaseId,
        uint8 assetType,
        string assetId,
        uint96 price
    );
    event CrossChainMarketplaceUpdated(uint16 indexed chainId, address indexed marketplaceAddress);
    event CrossChainListingBroadcastSent(uint16 indexed chainId, uint256 indexed listingId, bool isNFT);
    event CrossChainPurchaseReceived(uint16 indexed srcChainId, bytes payload);


    /*//////////////////////////////////////////////////////////////
                        LISTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev List an NFT for sale with optional cross-chain broadcasting
     * @param nftContractAddr Address of NFT contract
     * @param tokenId ID of the NFT
     * @param price Sale price in wei
     * @param enableCrossChain Whether to broadcast to other chains
     */
    function listNFT(
        address nftContractAddr,
        uint256 tokenId,
        uint96 price,
        bool enableCrossChain
    ) external payable;



    /**
     * @dev List a non-NFT asset for sale with optional cross-chain broadcasting
     * @param assetType Type of asset (from VertixUtils.AssetType)
     * @param assetId Unique identifier for the asset
     * @param price Sale price in wei
     * @param metadata Additional metadata
     * @param verificationProof Verification data
     * @param enableCrossChain Whether to broadcast to other chains
     */
    function listNonNFTAsset(
        uint8 assetType,
        string calldata assetId,
        uint96 price,
        string calldata metadata,
        bytes calldata verificationProof,
        bool enableCrossChain
    ) external payable;



    /**
     * @dev List social media NFT with signature verification and optional cross-chain broadcasting
     * @param tokenId Token ID
     * @param price Listing price (verified off-chain)
     * @param socialMediaId Social media identifier
     * @param signature Server signature for verification
     * @param enableCrossChain Whether to broadcast to other chains
     */
    function listSocialMediaNFT(
        uint256 tokenId,
        uint96 price,
        string calldata socialMediaId,
        bytes calldata signature,
        bool enableCrossChain
    ) external payable;



    /*//////////////////////////////////////////////////////////////
                        UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Estimate cross-chain broadcasting fee
     */
    function estimateCrossChainFee() external view returns (uint256 nativeFee, uint256 zroFee);



    /**
     * @dev Set the CrossChainMarketplace contract address for a specific chain
     */
    function setCrossChainMarketplace(uint16 chainId, address marketplaceAddress) external;

    /**
     * @dev Get the CrossChainMarketplace address for a specific chain
     */
    function getCrossChainMarketplace(uint16 chainId) external view returns (address);
}

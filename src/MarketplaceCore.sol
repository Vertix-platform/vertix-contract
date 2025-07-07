// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ILayerZeroEndpoint} from "lib/solidity-examples/contracts/lzApp/interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "lib/solidity-examples/contracts/lzApp/interfaces/ILayerZeroReceiver.sol";

import {MarketplaceStorage} from "./MarketplaceStorage.sol";
import {MarketplaceFees} from "./MarketplaceFees.sol";
import {IVertixGovernance} from "./interfaces/IVertixGovernance.sol";
import {VertixUtils} from "./libraries/VertixUtils.sol";
import {IMarketplaceCore} from "./interfaces/IMarketplaceCore.sol";
import {ICrossChainMarketplace} from "./interfaces/ICrossChainMarketplace.sol";
import {ICrossChainBridge} from "./interfaces/ICrossChainBridge.sol";

/**
 * @title MarketplaceCore
 * @dev Handles listing and buying functionality for NFT and non-NFT assets with integrated cross-chain broadcasting
 * @notice This contract handles local listings and broadcasts to CrossChainMarketplace contracts on other chains
 */
contract MarketplaceCore is
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ILayerZeroReceiver,
    IERC721Receiver,
    IERC1155Receiver,
    IMarketplaceCore
{
    struct ListingInfo {
        address seller;
        address tokenContract;
        uint256 tokenId;
        uint256 quantity;
        uint96 pricePerToken;
        uint256 totalPrice;
    }

    struct SocialMediaNFTListingParams {
        uint256 tokenId;
        uint96 price;
        string socialMediaId;
        bytes signature;
        bool enableCrossChain;
    }

    /*//////////////////////////////////////////////////////////////
                            CROSS-CHAIN CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint16 private constant MSG_TYPE_LISTING_CREATED = 1;
    uint16 private constant MSG_TYPE_LISTING_CANCELLED = 2;
    uint16 private constant MSG_TYPE_CROSS_CHAIN_PURCHASE = 3;
    uint16 private constant MSG_TYPE_PURCHASE_COMPLETED = 4;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    MarketplaceStorage public immutable storageContract;
    MarketplaceFees public immutable feesContract;
    IVertixGovernance public immutable governanceContract;

    // LayerZero functionality (composition instead of inheritance)
    ILayerZeroEndpoint public immutable lzEndpoint;

    // Cross-chain functionality
    mapping(uint16 => bool) public supportedChains;
    mapping(uint16 => address) public crossChainMarketplaceAddresses;
    uint256 private nonce;

    // Gas limits for cross-chain messaging
    uint256 public constant GAS_LIMIT_LISTING_BROADCAST = 200000;
    uint256 public constant GAS_LIMIT_PURCHASE_NOTIFY = 150000;

    // Bridge integration
    ICrossChainBridge public crossChainBridge;

    // Events
    event CrossChainBridgeUpdated(address indexed bridgeAddress);

    // Errors
    error MC__BridgeNotSet();
    error MC__BridgeTransferFailed();

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _storageContract,
        address _feesContract,
        address _governanceContract,
        address _lzEndpoint
    ) {
        storageContract = MarketplaceStorage(_storageContract);
        feesContract = MarketplaceFees(_feesContract);
        governanceContract = IVertixGovernance(_governanceContract);
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        _disableInitializers();

        // Initialize supported chains (testnet)
        supportedChains[10109] = true; // Polygon Mumbai
        supportedChains[10160] = true; // Base Goerli
    }

    function initialize(address initialOwner) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(initialOwner);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev List an NFT for sale with optional cross-chain broadcasting
     * @param nftContractAddr Address of NFT contract
     * @param tokenId ID of the NFT
     * @param price Sale price in wei
     * @param enableCrossChain Whether to broadcast to other chains (default: false)
     */
    function listNFT(
        address nftContractAddr,
        uint256 tokenId,
        uint96 price,
        bool enableCrossChain
    ) external payable nonReentrant whenNotPaused {
        _listNFTInternal(nftContractAddr, tokenId, price, enableCrossChain);
    }



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
    ) external payable nonReentrant whenNotPaused {
        _listNonNFTAssetInternal(assetType, assetId, price, metadata, verificationProof, enableCrossChain);
    }

    

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
    ) external payable nonReentrant whenNotPaused {
        _listSocialMediaNFTInternal(SocialMediaNFTListingParams({
            tokenId: tokenId,
            price: price,
            socialMediaId: socialMediaId,
            signature: signature,
            enableCrossChain: enableCrossChain
        }));
    }



    /**
     * @dev List an NFT for auction
     * @param listingId ID of the NFT
     * @param isNFT true if NFT and false if non-NFT
     */
    function listForAuction(
        uint256 listingId,
        bool isNFT
    ) external nonReentrant whenNotPaused {
        // Delegate to storage contract for auction listing logic
        storageContract.listForAuction(listingId, isNFT, msg.sender);
        emit ListedForAuction(listingId, isNFT, true);
    }

    function listTokens(
        address tokenContract,
        uint256 tokenId,
        uint256 quantity,
        uint96 pricePerToken
    ) external nonReentrant whenNotPaused {
        if (!IVertixGovernance(governanceContract).isSupportedTokenContract(tokenContract))
            revert MC__InvalidTokenContract();
        if (pricePerToken == 0) revert MC__InsufficientPayment();

        // Check ownership and approval
        if (IERC1155(tokenContract).balanceOf(msg.sender, tokenId) < quantity)
            revert MC__InsufficientBalance();

        if (!IERC1155(tokenContract).isApprovedForAll(msg.sender, address(this)))
            revert MC__NotApproved();

        // Create listing
        uint256 listingId = storageContract.createTokenListing(
            msg.sender,
            tokenContract,
            tokenId,
            quantity,
            pricePerToken
        );

        // Transfer tokens to marketplace
        IERC1155(tokenContract).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            quantity,
            ""
        );

        emit TokensListed(listingId, msg.sender, tokenContract, tokenId, quantity, pricePerToken);
    }

    /**
     * @dev List multiple tokens in a single transaction
     * @param tokenContract The ERC-1155 token contract address
     * @param tokenIds Array of token IDs to list
     * @param quantities Array of quantities for each token
     * @param pricesPerToken Array of prices per token
     */
    function batchListTokens(
        address tokenContract,
        uint256[] calldata tokenIds,
        uint256[] calldata quantities,
        uint96[] calldata pricesPerToken
    ) external nonReentrant whenNotPaused {
        // Validate input arrays
        uint256 batchSize = tokenIds.length;
        if (batchSize == 0 ||
            batchSize != quantities.length ||
            batchSize != pricesPerToken.length
        ) revert MC__InvalidListing();

        // Validate token contract
        if (!IVertixGovernance(governanceContract).isSupportedTokenContract(tokenContract))
            revert MC__InvalidTokenContract();

        // Check ownership and approval for all tokens
        for (uint256 i = 0; i < batchSize; i++) {
            if (pricesPerToken[i] == 0) revert MC__InsufficientPayment();
            if (IERC1155(tokenContract).balanceOf(msg.sender, tokenIds[i]) < quantities[i])
                revert MC__InsufficientBalance();
        }

        if (!IERC1155(tokenContract).isApprovedForAll(msg.sender, address(this)))
            revert MC__NotApproved();

        // Create listings
        uint256[] memory listingIds = storageContract.createBatchTokenListing(
            msg.sender,
            tokenContract,
            tokenIds,
            quantities,
            pricesPerToken
        );

        // Transfer tokens
        for (uint256 i = 0; i < batchSize; i++) {
            IERC1155(tokenContract).safeTransferFrom(
                msg.sender,
                address(this),
                tokenIds[i],
                quantities[i],
                ""
            );
        }

        emit BatchTokensListed(
            listingIds,
            msg.sender,
            tokenContract,
            tokenIds,
            quantities,
            pricesPerToken
        );
    }

    /*//////////////////////////////////////////////////////////////
                          BUYING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
    * @dev Buy an NFT listing
    * @param listingId ID of the listing
    */
    function buyNFT(uint256 listingId) external payable nonReentrant whenNotPaused {
        // CHECKS: Validate listing exists and is active
        (
            address seller,
            address nftContractAddr,
            uint256 tokenId,
            uint96 price,
            bool active,
        ) = storageContract.getNFTListing(listingId);

        if (!active) revert MC__InvalidListing();
        if (msg.value < price) revert MC__InsufficientPayment();

        // EFFECTS: Update storage state before payment processing
        storageContract.updateNFTListingFlags(listingId, 0);
        storageContract.removeNFTListingHash(nftContractAddr, tokenId);

        // INTERACTIONS: Process payment through fees contract
        MarketplaceFees.PaymentConfig memory config = MarketplaceFees.PaymentConfig({
            totalPayment: msg.value,
            salePrice: price,
            nftContract: nftContractAddr,
            tokenId: tokenId,
            seller: seller,
            hasRoyalties: true,
            tokenContract: nftContractAddr
        });

        uint256 refundAmount = feesContract.processNFTSalePayment{value: msg.value}(config);

        // Handle refund if necessary
        if (refundAmount > 0) {
            feesContract.refundExcessPayment(msg.sender, refundAmount);
        }

        // Transfer NFT to buyer
        IERC721(nftContractAddr).safeTransferFrom(address(this), msg.sender, tokenId);

        // Get fees for event emission
        MarketplaceFees.FeeDistribution memory fees = feesContract.calculateNFTFees(price, nftContractAddr, tokenId);

        emit NFTBought(
            listingId,
            msg.sender,
            price,
            fees.royaltyAmount,
            fees.royaltyRecipient,
            fees.platformFee,
            fees.platformRecipient
        );
    }

    /**
     * @dev Buy non-NFT asset with escrow
     * @param listingId ID of the listing
     */
    function buyNonNFTAsset(uint256 listingId) external payable nonReentrant whenNotPaused {
        (
            address seller,
            uint96 price,
            ,
            bool active,
            ,
            string memory assetId,
            ,
        ) = storageContract.getNonNFTListing(listingId);

        if (!active) revert MC__InvalidListing();
        if (msg.value < price) revert MC__InsufficientPayment();

        // Update storage state before payment processing
        storageContract.updateNonNFTListingFlags(listingId, 0);
        storageContract.removeNonNFTListingHash(seller, assetId);

        // Process payment through fees contract
        uint256 refundAmount = feesContract.processNonNFTSalePayment{value: msg.value}(
            listingId,
            price,
            seller,
            msg.sender
        );

        // Handle refund if necessary
        if (refundAmount > 0) {
            feesContract.refundExcessPayment(msg.sender, refundAmount);
        }

        // Get fees for event emission
        MarketplaceFees.FeeDistribution memory fees = feesContract.calculateNonNFTFees(price);

        emit NonNFTBought(
            listingId,
            msg.sender,
            price,
            fees.sellerAmount,
            fees.platformFee,
            fees.platformRecipient
        );
    }

    function buyTokens(
        uint256 listingId,
        uint256 quantity
    ) external payable nonReentrant whenNotPaused {
        MarketplaceStorage.TokenListingView memory listing = storageContract.getTokenListing(listingId);

        if (!listing.active) revert MC__InvalidListing();
        if (quantity > listing.quantity) revert MC__InsufficientQuantity();

        uint256 totalPrice = uint256(listing.pricePerToken) * quantity;
        if (msg.value < totalPrice) revert MC__InsufficientPayment();

        // Update listing
        storageContract.updateTokenListing(
            listingId,
            listing.quantity - quantity
        );

        // Handle payment and fees
        MarketplaceFees.FeeDistribution memory fees =
            feesContract.calculateTokenFees(totalPrice, listing.tokenContract, listing.tokenId);

        // Process payment
        MarketplaceFees.PaymentConfig memory config = MarketplaceFees.PaymentConfig({
                totalPayment: msg.value,
                salePrice: totalPrice,
                tokenContract: listing.tokenContract,
                tokenId: listing.tokenId,
                seller: listing.seller,
                hasRoyalties: true,
                nftContract: listing.tokenContract
            });

        uint256 refundAmount = feesContract.processTokenSalePayment{value: msg.value}(config);

        if (refundAmount > 0) {
            feesContract.refundExcessPayment(msg.sender, refundAmount);
        }

        // Transfer tokens
        IERC1155(listing.tokenContract).safeTransferFrom(
            address(this),
            msg.sender,
            listing.tokenId,
            quantity,
            ""
        );

        emit TokensBought(
            listingId,
            msg.sender,
            quantity,
            totalPrice,
            fees.royaltyAmount,
            fees.royaltyRecipient
        );
    }

    /**
     * @dev Buy multiple tokens in a single transaction (Gas Optimized)
     * @param listingIds Array of listing IDs to buy from
     * @param quantities Array of quantities to buy for each listing
     */
    function batchBuyTokens(
        uint256[] calldata listingIds,
        uint256[] calldata quantities
    ) external payable nonReentrant whenNotPaused {
        if (listingIds.length == 0 || listingIds.length != quantities.length)
            revert MC__InvalidListing();

        uint256 totalPayment = 0;
        uint256 length = listingIds.length;

        ListingInfo[] memory listings = new ListingInfo[](length);


        // PHASE 1: Validate, calculate, and update all state
        for (uint256 i = 0; i < length;) {
            MarketplaceStorage.TokenListingView memory listing = storageContract.getTokenListing(listingIds[i]);

            if (!listing.active) revert MC__InvalidListing();
            if (quantities[i] > listing.quantity) revert MC__InsufficientQuantity();

            uint256 listingTotal = uint256(listing.pricePerToken) * quantities[i];
            totalPayment += listingTotal;

            listings[i] = ListingInfo({
                seller: listing.seller,
                tokenContract: listing.tokenContract,
                tokenId: listing.tokenId,
                quantity: quantities[i],
                pricePerToken: listing.pricePerToken,
                totalPrice: listingTotal
            });

            unchecked { ++i; }
        }

        if (msg.value < totalPayment) revert MC__InsufficientPayment();

        // PHASE 2: Update state
        for (uint256 i = 0; i < length;) {
            storageContract.updateTokenListing(listingIds[i], listings[i].quantity);
            unchecked { ++i; }
        }

        // PHASE 3: External interactions
        for (uint256 i = 0; i < length;) {
            IERC1155(listings[i].tokenContract).safeTransferFrom(
                address(this),
                msg.sender,
                listings[i].tokenId,
                listings[i].quantity,
                ""
            );

            MarketplaceFees.PaymentConfig memory config = MarketplaceFees.PaymentConfig({
                totalPayment: listings[i].totalPrice,
                salePrice: listings[i].totalPrice,
                tokenContract: listings[i].tokenContract,
                tokenId: listings[i].tokenId,
                seller: listings[i].seller,
                hasRoyalties: true,
                nftContract: listings[i].tokenContract
            });

            feesContract.processTokenSalePayment{value: listings[i].totalPrice}(config);

            unchecked { ++i; }
        }

        // Refund excess payment
        uint256 refundAmount = msg.value - totalPayment;
        if (refundAmount > 0) {
            feesContract.refundExcessPayment(msg.sender, refundAmount);
        }

        emit BatchTokensBought(listingIds, msg.sender, quantities, new uint256[](0));
    }

    /*//////////////////////////////////////////////////////////////
                           CANCEL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Cancel an NFT listing
     * @param listingId ID of the listing
     */
    function cancelNFTListing(uint256 listingId) external nonReentrant whenNotPaused {
        (
            address seller,
            address nftContractAddr,
            uint256 tokenId,
            ,
            bool active,
        ) = storageContract.getNFTListing(listingId);

        if (!active) revert MC__InvalidListing();
        if (msg.sender != seller) revert MC__NotSeller();

        storageContract.updateNFTListingFlags(listingId, 0); // Set inactive
        storageContract.removeNFTListingHash(nftContractAddr, tokenId);

        IERC721(nftContractAddr).safeTransferFrom(address(this), seller, tokenId);
        emit NFTListingCancelled(listingId, seller, true);
    }

    /**
     * @dev Cancel a non-NFT listing
     * @param listingId ID of the listing
     */
    function cancelNonNFTListing(uint256 listingId) external nonReentrant whenNotPaused {
        (
            address seller,
            ,
            ,
            bool active,
            ,
            string memory assetId,
            ,
        ) = storageContract.getNonNFTListing(listingId);

        if (!active) revert MC__InvalidListing();
        if (msg.sender != seller) revert MC__NotSeller();

        storageContract.updateNonNFTListingFlags(listingId, 0); // Set inactive
        storageContract.removeNonNFTListingHash(seller, assetId);

        emit NonNFTListingCancelled(listingId, seller, false);
    }

    /**
     * @dev LayerZero receiver function - called by LayerZero endpoint
     * @param _srcChainId Source chain ID
     * @param _srcAddress Source address
     * @param _nonce Message nonce
     * @param _payload Message payload
     */
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external override {
        if (msg.sender != address(lzEndpoint)) revert MarketplaceCore__InvalidEndpointCaller();

        // Verify the source address matches expected CrossChainMarketplace
        if (_srcAddress.length != 40) revert MarketplaceCore__InvalidSourceAddressLength();

        address srcAddress;
        assembly {
            srcAddress := shr(96, calldataload(add(_srcAddress.offset, 0)))
        }

        if (srcAddress != crossChainMarketplaceAddresses[_srcChainId]) revert MarketplaceCore__InvalidSourceAddress();

        // Call the internal handler
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Set the CrossChainMarketplace contract address for a specific chain
     * @param chainId The LayerZero chain ID
     * @param marketplaceAddress The address of the CrossChainMarketplace contract on that chain
     */
    function setCrossChainMarketplace(uint16 chainId, address marketplaceAddress) external onlyOwner {
        if (marketplaceAddress == address(0)) revert MC__InvalidCrossChainMarketplace();

        crossChainMarketplaceAddresses[chainId] = marketplaceAddress;
        emit CrossChainMarketplaceUpdated(chainId, marketplaceAddress);
    }

    /**
     * @dev Set the CrossChainBridge contract address
     * @param bridgeAddress The address of the CrossChainBridge contract
     */
    function setCrossChainBridge(address bridgeAddress) external onlyOwner {
        if (bridgeAddress == address(0)) revert MC__BridgeNotSet();

        crossChainBridge = ICrossChainBridge(bridgeAddress);
        emit CrossChainBridgeUpdated(bridgeAddress);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to handle cross-chain messages
     * @notice This contract primarily sends broadcasts, but can receive purchase notifications
     */
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes calldata /* _srcAddress */,
        uint64 /* _nonce */,
        bytes calldata _payload
    ) internal {
        // Decode the message type
        uint16 msgType = abi.decode(_payload, (uint16));

        if (msgType == MSG_TYPE_CROSS_CHAIN_PURCHASE) {
            _handleCrossChainPurchase(_srcChainId, _payload);
        } else if (msgType == MSG_TYPE_PURCHASE_COMPLETED) {
            emit CrossChainPurchaseReceived(_srcChainId, _payload);
        }
    }

    /**
     * @dev Internal LayerZero send function
     * @param _dstChainId Destination chain ID
     * @param _payload Message payload
     * @param _refundAddress Refund address
     * @param _zroPaymentAddress ZRO payment address
     * @param _adapterParams Adapter parameters
     * @param _nativeFee Native fee amount
     */
    function _lzSend(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams,
        uint256 _nativeFee
    ) internal {
        bytes memory remoteAddress = abi.encodePacked(
            crossChainMarketplaceAddresses[_dstChainId],
            address(this)
        );

        lzEndpoint.send{value: _nativeFee}(
            _dstChainId,
            remoteAddress,
            _payload,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    /**
     * @dev Handle cross-chain purchase requests
     * @notice This is called when someone purchases an item listed on this chain from another chain
     */
    function _handleCrossChainPurchase(uint16 _srcChainId, bytes calldata _payload) internal {
        (
            , // msgType - not used in this function
            uint256 sourceListingId,
            address buyer,
            uint256 purchaseId,
            uint96 price,
            bool isNFT,
            , // totalPaymentAmount - // Total amount available for purchase + bridge fees
            // _nonce - not used in this function
        ) = abi.decode(_payload, (uint16, uint256, address, uint256, uint96, bool, uint256, uint256));

        // Execute the purchase locally
        if (isNFT) {
            _executeNFTPurchaseForCrossChain(sourceListingId, buyer, _srcChainId, purchaseId, price);
        } else {
            _executeNonNFTPurchaseForCrossChain(sourceListingId, buyer, _srcChainId, purchaseId, price);
        }
    }

    /**
     * @dev Execute NFT purchase for cross-chain buyer
     */
    function _executeNFTPurchaseForCrossChain(
        uint256 listingId,
        address buyer,
        uint16 buyerChainId,
        uint256 purchaseId,
        uint96 price
    ) internal {
        // Delegate storage operations to storage contract
        (
            address nftContract,
            uint256 tokenId,
            /* uint96 listingPrice */
        ) = storageContract.executeCrossChainNFTPurchase(listingId, price);

        // Bridge the NFT to the buyer's chain if bridge is configured
        if (address(crossChainBridge) != address(0)) {
            // Transfer NFT to bridge contract for cross-chain delivery
            IERC721(nftContract).safeTransferFrom(address(this), address(crossChainBridge), tokenId);
            
            // Estimate bridge fee (buyer would need to pay this as part of purchase)
            (uint256 bridgeFee, ) = crossChainBridge.estimateBridgeFee(buyerChainId, buyer, false);
            
            // Bridge the NFT to the buyer on their chain
            try crossChainBridge.bridgeNFT{value: bridgeFee}(
                buyerChainId,
                nftContract,
                buyer,
                tokenId
            ) {
                // Successfully initiated bridge transfer
                emit CrossChainNFTPurchaseExecuted(
                    listingId,
                    buyer,
                    buyerChainId,
                    purchaseId,
                    nftContract,
                    tokenId,
                    price
                );
            } catch {
                // Bridge failed, emit error event but don't revert the purchase
                // The NFT will remain with the bridge contract for manual resolution
                revert MC__BridgeTransferFailed();
            }
        } else {
            // No bridge configured - emit event for manual bridging
            emit CrossChainNFTPurchaseExecuted(
                listingId,
                buyer,
                buyerChainId,
                purchaseId,
                nftContract,
                tokenId,
                price
            );
        }

        // Send purchase completion message back to buyer's chain
        bytes memory payload = abi.encode(
            MSG_TYPE_PURCHASE_COMPLETED,
            listingId,
            buyer,
            purchaseId,
            price,
            true, // isNFT
            nonce++
        );

        _sendToCrossChainMarketplace(buyerChainId, payload, 0);
    }

    /**
     * @dev Execute non-NFT asset purchase for cross-chain buyer
     */
    function _executeNonNFTPurchaseForCrossChain(
        uint256 listingId,
        address buyer,
        uint16 buyerChainId,
        uint256 purchaseId,
        uint96 price
    ) internal {
        // Delegate storage operations to storage contract
        (
            /* address seller */,
            uint8 assetType,
            string memory assetId,
            /* uint96 listingPrice */
        ) = storageContract.executeCrossChainNonNFTPurchase(listingId, price);

        emit CrossChainNonNFTPurchaseExecuted(
            listingId,
            buyer,
            buyerChainId,
            purchaseId,
            assetType,
            assetId,
            price
        );

        // Send purchase completion message back to buyer's chain
        bytes memory payload = abi.encode(
            MSG_TYPE_PURCHASE_COMPLETED,
            listingId,
            buyer,
            purchaseId,
            price,
            false, // isNFT
            nonce++
        );

        _sendToCrossChainMarketplace(buyerChainId, payload, 0);
    }

    /**
     * @dev Broadcast listing to all supported chains
     * @param listingId The listing ID
     * @param isNFT Whether this is an NFT listing
     * @param enableCrossChain Whether cross-chain broadcasting is enabled
     */
    function _broadcastListing(
        uint256 listingId,
        bool isNFT,
        bool enableCrossChain
    ) internal {
        if (!enableCrossChain) return;

        bytes memory payload;

        if (isNFT) {
            (
                address seller,
                address nftContract,
                uint256 tokenId,
                uint96 price,
                bool active,
            ) = storageContract.getNFTListing(listingId);

            if (!active) return;

            payload = abi.encode(
                MSG_TYPE_LISTING_CREATED,
                listingId,
                seller,
                nftContract,
                tokenId,
                price,
                true, // isNFT
                "", // assetId (empty for NFT)
                uint8(0), // assetType (0 for NFT)
                nonce++
            );
        } else {
            (
                address seller,
                uint96 price,
                uint8 assetType,
                bool active,
                ,
                string memory assetId,
                ,
            ) = storageContract.getNonNFTListing(listingId);

            if (!active) return;

            payload = abi.encode(
                MSG_TYPE_LISTING_CREATED,
                listingId,
                seller,
                address(0), // nftContract (empty for non-NFT)
                uint256(0), // tokenId (0 for non-NFT)
                price,
                false, // isNFT
                assetId,
                assetType,
                nonce++
            );
        }

        // Broadcast to all supported chains
        _broadcastToAllCrossChainMarketplaces(payload, listingId, isNFT);
    }

    /**
     * @dev Broadcast to all CrossChainMarketplace contracts on supported chains
     * @param payload The message payload
     * @param listingId The listing ID for events
     * @param isNFT Whether this is an NFT listing
     */
    function _broadcastToAllCrossChainMarketplaces(
        bytes memory payload,
        uint256 listingId,
        bool isNFT
    ) internal {
        uint16[] memory chainIds = new uint16[](2);
        chainIds[0] = 10109; // Polygon Mumbai
        chainIds[1] = 10160; // Base Goerli

        uint256 feesPerChain = msg.value / chainIds.length;

        uint256 length = chainIds.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                uint16 chainId = chainIds[i];
                if (supportedChains[chainId] && chainId != _getChainId()) {
                    address crossChainMarketplace = crossChainMarketplaceAddresses[chainId];

                    if (crossChainMarketplace == address(0)) {
                        emit CrossChainBroadcastFailed(chainId);
                        continue;
                    }

                    _sendToCrossChainMarketplace(chainId, payload, feesPerChain);
                    emit CrossChainListingBroadcastSent(chainId, listingId, isNFT);
                }
            }
        }
    }



    /**
     * @dev Internal function to send message to CrossChainMarketplace
     * @param chainId The destination chain ID
     * @param payload The message payload
     * @param fee The fee amount to send
     */
    function _sendToCrossChainMarketplace(uint16 chainId, bytes memory payload, uint256 fee) internal {
        address crossChainMarketplace = crossChainMarketplaceAddresses[chainId];
        if (crossChainMarketplace == address(0)) revert MC__CrossChainMarketplaceNotSet();

        _lzSend(
            chainId,
            payload,
            payable(msg.sender),
            address(0),
            bytes(""),
            fee
        );
    }

    /**
     * @dev Internal function to list an NFT for sale
     * @param nftContractAddr Address of NFT contract
     * @param tokenId ID of the NFT
     * @param price Sale price in wei
     * @param enableCrossChain Whether to broadcast to other chains
     */
    function _listNFTInternal(
        address nftContractAddr,
        uint256 tokenId,
        uint96 price,
        bool enableCrossChain
    ) internal {
        // Validate cross-chain fee if enabled
        if (enableCrossChain) {
            (uint256 requiredFee,) = estimateCrossChainFee();
            if (msg.value < requiredFee) revert MC__InsufficientCrossChainFee();
        }

        // Validate in single call
        if (!IVertixGovernance(governanceContract).isSupportedNFTContract(nftContractAddr)) revert MC__InvalidNFTContract();
        if (price == 0) revert MC__InsufficientPayment();

        // Check ownership and duplicates in single slot read
        bytes32 listingHash = keccak256(abi.encodePacked(nftContractAddr, tokenId));
        if (storageContract.checkListingHash(listingHash)) revert MC__DuplicateListing();
        if (IERC721(nftContractAddr).ownerOf(tokenId) != msg.sender) revert MC__NotOwner();

        // Single storage operation
        uint256 listingId = storageContract.createNFTListing(
            msg.sender,
            nftContractAddr,
            tokenId,
            price
        );

        // Transfer NFT (reverts on failure)
        IERC721(nftContractAddr).safeTransferFrom(msg.sender, address(this), tokenId);

        // Broadcast to other chains if enabled
        _broadcastListing(listingId, true, enableCrossChain);

        emit NFTListed(listingId, msg.sender, nftContractAddr, tokenId, price);

        if (enableCrossChain) {
            emit CrossChainListingBroadcast(listingId, true);
        }
    }

    /**
     * @dev Internal function to list a non-NFT asset for sale
     * @param assetType Type of asset (from VertixUtils.AssetType)
     * @param assetId Unique identifier for the asset
     * @param price Sale price in wei
     * @param metadata Additional metadata
     * @param verificationProof Verification data
     * @param enableCrossChain Whether to broadcast to other chains
     */
    function _listNonNFTAssetInternal(
        uint8 assetType,
        string calldata assetId,
        uint96 price,
        string calldata metadata,
        bytes calldata verificationProof,
        bool enableCrossChain
    ) internal {
        // Validate cross-chain fee if enabled
        if (enableCrossChain) {
            (uint256 requiredFee,) = estimateCrossChainFee();
            if (msg.value < requiredFee) revert MC__InsufficientCrossChainFee();
        }

        if (assetType > uint8(VertixUtils.AssetType.Other) || price == 0) {
            revert MC__InvalidAssetType();
        }

        // Check duplicates
        bytes32 listingHash = keccak256(abi.encodePacked(msg.sender, assetId));
        if (storageContract.checkListingHash(listingHash)) revert MC__DuplicateListing();

        uint256 listingId = storageContract.createNonNFTListing(
            msg.sender,
            assetType,
            assetId,
            price,
            metadata,
            VertixUtils.hashVerificationProof(verificationProof)
        );

        // Broadcast to other chains if enabled
        _broadcastListing(listingId, false, enableCrossChain);

        emit NonNFTListed(listingId, msg.sender, assetType, assetId, price);

        if (enableCrossChain) {
            emit CrossChainListingBroadcast(listingId, false);
        }
    }

/**
 * @dev Internal function to list social media NFT with signature verification
 * @param params Struct containing listing parameters:
 *   - tokenId: Token ID
 *   - price: Listing price (verified off-chain)
 *   - socialMediaId: Social media identifier
 *   - signature: Server signature for verification
 *   - enableCrossChain: Whether to broadcast to other chains
 */
function _listSocialMediaNFTInternal(SocialMediaNFTListingParams memory params) internal {
    // Validate cross-chain fee if enabled
    if (params.enableCrossChain) {
        (uint256 requiredFee,) = estimateCrossChainFee();
        if (msg.value < requiredFee) revert MC__InsufficientCrossChainFee();
    }

    // CHECKS: All validation first
    address nftContractAddr = address(storageContract.vertixNFTContract());

    if (params.price == 0) revert MC__InsufficientPayment();
    if (IERC721(nftContractAddr).ownerOf(params.tokenId) != msg.sender) revert MC__NotOwner();
    if (!storageContract.vertixNFTContract().getUsedSocialMediaIds(params.socialMediaId)) {
        revert MC__InvalidSocialMediaNFT();
    }

    // Verify signature
    address verificationServer = governanceContract.getVerificationServer();
    bytes32 messageHash = keccak256(
        abi.encodePacked(msg.sender, params.tokenId, params.price, params.socialMediaId)
    );
    bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
    if (ECDSA.recover(ethSignedHash, params.signature) != verificationServer) {
        revert MC__InvalidSignature();
    }

    // Check duplicate listing
    bytes32 listingHash = keccak256(abi.encodePacked(nftContractAddr, params.tokenId));
    if (storageContract.checkListingHash(listingHash)) revert MC__DuplicateListing();

    // EFFECTS: Update state before external interactions
    // Create listing first (this updates the storage state)
    uint256 listingId = storageContract.createNFTListing(
        msg.sender,
        nftContractAddr,
        params.tokenId,
        params.price
    );

    // INTERACTIONS: External calls happen last
    // Transfer NFT after state update to prevent reentrancy issues
    IERC721(nftContractAddr).safeTransferFrom(msg.sender, address(this), params.tokenId);

    // Broadcast to other chains if enabled
    _broadcastListing(listingId, true, params.enableCrossChain);

    emit NFTListed(listingId, msg.sender, nftContractAddr, params.tokenId, params.price);

    if (params.enableCrossChain) {
        emit CrossChainListingBroadcast(listingId, true);
    }
}

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external {
        if (msg.sender != storageContract.owner()) revert MC__NotOwner();
        _pause();
    }

    function unpause() external {
        if (msg.sender != storageContract.owner()) revert MC__NotOwner();
        _unpause();
    }



    /*//////////////////////////////////////////////////////////////
                           IERC721Receiver
    //////////////////////////////////////////////////////////////*/

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get the CrossChainMarketplace address for a specific chain
     * @param chainId The LayerZero chain ID
     * @return The address of the CrossChainMarketplace contract
     */
    function getCrossChainMarketplace(uint16 chainId) external view returns (address) {
        return crossChainMarketplaceAddresses[chainId];
    }

    function _getChainId() internal view returns (uint16) {
        return uint16(block.chainid);
    }
        /**
     * @dev Estimate cross-chain broadcasting fee
     */
    function estimateCrossChainFee() public view returns (uint256 nativeFee, uint256 zroFee) {
        uint16[] memory chainIds = new uint16[](2);
        chainIds[0] = 10109; // Polygon Mumbai
        chainIds[1] = 10160; // Base Goerli

        uint256 totalFee = 0;

        uint256 length = chainIds.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (supportedChains[chainIds[i]] && chainIds[i] != _getChainId()) {
                    bytes memory payload = abi.encode(
                        MSG_TYPE_LISTING_CREATED,
                        uint256(0), // dummy listing id
                        msg.sender,
                        address(0),
                        uint256(0),
                        uint96(0),
                        true,
                        "",
                        uint8(0),
                        nonce
                    );

                    (uint256 fee,) = lzEndpoint.estimateFees(
                        chainIds[i],
                        address(this),
                        payload,
                        false,
                        bytes("")
                    );

                    totalFee += fee;
                }
            }
        }

        return (totalFee, 0);
    }

    /*//////////////////////////////////////////////////////////////
                           IERC1155Receiver
    //////////////////////////////////////////////////////////////*/

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    // ERC165 support
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId;
    }

}
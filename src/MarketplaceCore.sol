// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {MarketplaceStorage} from "./MarketplaceStorage.sol";
import {MarketplaceFees} from "./MarketplaceFees.sol";
import {IVertixGovernance} from "./interfaces/IVertixGovernance.sol";
import {VertixUtils} from "./libraries/VertixUtils.sol";

/**
 * @title MarketplaceCore
 * @dev Handles listing and buying functionality for NFT and non-NFT assets
 */
contract MarketplaceCore is ReentrancyGuardUpgradeable, PausableUpgradeable {
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

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    MarketplaceStorage public immutable storageContract;
    MarketplaceFees public immutable feesContract;
    IVertixGovernance public immutable governanceContract;

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


    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _storageContract,
        address _feesContract,
        address _governanceContract
    ) {
        storageContract = MarketplaceStorage(_storageContract);
        feesContract = MarketplaceFees(_feesContract);
        governanceContract = IVertixGovernance(_governanceContract);
        _disableInitializers();
    }

    function initialize() external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    /*//////////////////////////////////////////////////////////////
                          LISTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev List an NFT for sale
     * @param nftContractAddr Address of NFT contract
     * @param tokenId ID of the NFT
     * @param price Sale price in wei
     */
    function listNFT(
        address nftContractAddr,
        uint256 tokenId,
        uint96 price
    ) external nonReentrant whenNotPaused {
        // Validate in single call
        if (!IVertixGovernance(governanceContract).isSupportedNFTContract(nftContractAddr)) revert MC__InvalidNFTContract();
        if (price == 0) revert MC__InsufficientPayment();

        // Check ownership and duplicates in single slot read
        bytes32 listingHash = keccak256(abi.encodePacked(nftContractAddr, tokenId));
        if (storageContract.checkListingHash(listingHash)) revert MC__DuplicateListing();
        if (IERC721(nftContractAddr).ownerOf(tokenId) != msg.sender) revert MC__NotOwner();

        // Transfer NFT (reverts on failure)
        IERC721(nftContractAddr).transferFrom(msg.sender, address(this), tokenId);

        // Single storage operation
        uint256 listingId = storageContract.createNFTListing(
            msg.sender,
            nftContractAddr,
            tokenId,
            price
        );

        emit NFTListed(listingId, msg.sender, nftContractAddr, tokenId, price);
    }

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
        uint96 price,
        string calldata metadata,
        bytes calldata verificationProof
    ) external nonReentrant whenNotPaused {
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

        emit NonNFTListed(listingId, msg.sender, assetType, assetId, price);
    }

    /**
     * @dev List social media NFT with signature verification and off-chain price verification
     * @param tokenId Token ID
     * @param price Listing price (verified off-chain)
     * @param socialMediaId Social media identifier
     * @param signature Server signature for verification
     */
    function listSocialMediaNFT(
        uint256 tokenId,
        uint96 price,
        string calldata socialMediaId,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        address nftContractAddr = address(storageContract.vertixNFTContract());
        if (price == 0) revert MC__InsufficientPayment();
        if (IERC721(address(nftContractAddr)).ownerOf(tokenId) != msg.sender) revert MC__NotOwner();
        if (!storageContract.vertixNFTContract().getUsedSocialMediaIds(socialMediaId)) revert MC__InvalidSocialMediaNFT();

        // Verify signature
        address verificationServer = governanceContract.getVerificationServer();
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, tokenId, price, socialMediaId));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedHash, signature) != verificationServer) revert MC__InvalidSignature();

        // Check duplicate listing
        bytes32 listingHash = keccak256(abi.encodePacked(address(nftContractAddr), tokenId));
        if (storageContract.checkListingHash(listingHash)) revert MC__DuplicateListing();

        // Transfer NFT and create listing
        IERC721(address(nftContractAddr)).transferFrom(msg.sender, address(this), tokenId);

        uint256 listingId = storageContract.createNFTListing(
            msg.sender,
            address(nftContractAddr),
            tokenId,
            price
        );

        emit NFTListed(listingId, msg.sender, address(nftContractAddr), tokenId, price);
    }

    /**
     * @dev List an NFT for auction
     * @param listingId ID of the NFT
     * @param isNFT true if NFT and false if non-NFT
     */
    function listForAuction(
        uint256 listingId,
        bool isNFT,
        uint256 startingPrice,
        uint24 duration
    ) external nonReentrant whenNotPaused {
        if (isNFT) {
            (
                address seller,
                address nftContractAddr,
                uint256 tokenId,
                ,
                bool active,
            ) = storageContract.getNFTListing(listingId);

            if (!active) revert MC__InvalidListing();
            if (msg.sender != seller) revert MC__NotSeller();
            if (storageContract.isTokenListedForAuction(listingId)) revert Mc_AlreadyListedForAuction();

            storageContract.updateNFTListingFlags(listingId, 3); // Set auction listed
            emit ListedForAuction(listingId, true, true);
        } else {
            (
                address seller,
                ,
                uint8 assetType,
                bool active,
                bool auctionListed,
                string memory assetId,
                ,
            ) = storageContract.getNonNFTListing(listingId);

            if (!active) revert MC__InvalidListing();
            if (msg.sender != seller) revert MC__NotSeller();
            if (auctionListed) revert Mc_AlreadyListedForAuction();

            storageContract.updateNonNFTListingFlags(listingId, 3); // Set auction listed
            emit ListedForAuction(listingId, false, true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          BUYING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Buy an NFT listing
     * @param listingId ID of the listing
     */
    function buyNFT(uint256 listingId) external payable nonReentrant whenNotPaused {
        (
            address seller,
            address nftContractAddr,
            uint256 tokenId,
            uint96 price,
            bool active,
        ) = storageContract.getNFTListing(listingId);

        if (!active) revert MC__InvalidListing();
        if (msg.value < price) revert MC__InsufficientPayment();

        // Mark inactive before transfers (CEI pattern)
        storageContract.updateNFTListingFlags(listingId, 0);
        storageContract.removeNFTListingHash(nftContractAddr, tokenId);

        IERC721(nftContractAddr).transferFrom(address(this), msg.sender, tokenId);


        MarketplaceFees.PaymentConfig memory config = MarketplaceFees.PaymentConfig({
            totalPayment: msg.value,
            salePrice: price,
            nftContract: nftContractAddr,
            tokenId: tokenId,
            seller: seller,
            hasRoyalties: true
        });

        uint256 refundAmount = feesContract.processNFTSalePayment{value: msg.value}(config);
        if (refundAmount > 0) {
            feesContract.refundExcessPayment(msg.sender, refundAmount);
        }
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

        // Mark inactive before transfers
        storageContract.updateNonNFTListingFlags(listingId, 0);
        storageContract.removeNonNFTListingHash(seller, assetId);

        // Process payment
        uint256 refundAmount = feesContract.processNonNFTSalePayment{value: msg.value}(
            listingId,
            price,
            seller,
            msg.sender
        );

        // Refund excess
        if (refundAmount > 0) {
            feesContract.refundExcessPayment(msg.sender, refundAmount);
        }

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

        IERC721(nftContractAddr).transferFrom(address(this), seller, tokenId);
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
}
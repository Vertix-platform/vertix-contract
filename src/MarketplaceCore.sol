// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

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
    MarketplaceStorage public immutable STORAGE_CONTRACT;
    MarketplaceFees public immutable FEES_CONTRACT;
    IVertixGovernance public immutable GOVERNANCE_CONTRACT;

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
    event NFTListingCancelled(uint256 indexed listingId, address indexed seller, bool isNft);
    event NonNFTListingCancelled(uint256 indexed listingId, address indexed seller, bool isNft);
    event ListedForAuction(uint256 indexed listingId, bool isNft, bool isListedForAuction);


    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _storageContract,
        address _feesContract,
        address _governanceContract
    ) {
        STORAGE_CONTRACT = MarketplaceStorage(_storageContract);
        FEES_CONTRACT = MarketplaceFees(_feesContract);
        GOVERNANCE_CONTRACT = IVertixGovernance(_governanceContract);
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
     * @dev Safely transfer ERC721 token with proper error handling
     */
    function _safeTransferNft(address nftContract, address from, address to, uint256 tokenId) internal {
        try IERC721(nftContract).transferFrom(from, to, tokenId) {
            // Verify transfer succeeded by checking ownership
            if (IERC721(nftContract).ownerOf(tokenId) != to) {
                revert MC__TransferFailed();
            }
        } catch {
            revert MC__TransferFailed();
        }
    }

    /**
     * @dev Common validation and checks for listing functions
     * @param nftContractAddr Address of NFT contract
     * @param tokenId ID of the NFT
     * @param price Sale price in wei
     */
    function _validateListingRequirements(
        address nftContractAddr,
        uint256 tokenId,
        uint96 price
    ) internal view {
        if (!GOVERNANCE_CONTRACT.isSupportedNftContract(nftContractAddr)) revert MC__InvalidNFTContract();
        if (price == 0) revert MC__InsufficientPayment();
        if (IERC721(nftContractAddr).ownerOf(tokenId) != msg.sender) revert MC__NotOwner();

        // Check duplicate listing
        bytes32 listingHash;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, nftContractAddr)
            mstore(add(ptr, 0x20), tokenId)
            listingHash := keccak256(ptr, 0x40)
        }
        if (STORAGE_CONTRACT.checkListingHash(listingHash)) revert MC__DuplicateListing();
    }

    /**
     * @dev Internal function to create NFT listing after validation
     * @param nftContractAddr Address of NFT contract
     * @param tokenId ID of the NFT
     * @param price Sale price in wei
     */
    function _createNftListing(
        address nftContractAddr,
        uint256 tokenId,
        uint96 price
    ) internal returns (uint256 listingId) {
        // Transfer NFT (reverts on failure)
        _safeTransferNft(nftContractAddr, msg.sender, address(this), tokenId);

        // Create listing
        listingId = STORAGE_CONTRACT.createNftListing(
            msg.sender,
            nftContractAddr,
            tokenId,
            price
        );

        emit NFTListed(listingId, msg.sender, nftContractAddr, tokenId, price);
    }

    /**
     * @dev Common validation for cancellation functions
     * @param seller Address of the seller
     * @param active Whether the listing is active
     */
    function _validateCancellation(address seller, bool active) internal view {
        if (!active) revert MC__InvalidListing();
        if (msg.sender != seller) revert MC__NotSeller();
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
    function listNft(
        address nftContractAddr,
        uint256 tokenId,
        uint96 price
    ) external nonReentrant whenNotPaused {
        _validateListingRequirements(nftContractAddr, tokenId, price);
        _createNftListing(nftContractAddr, tokenId, price);
    }

    /**
     * @dev List a non-NFT asset for sale
     * @param assetType Type of asset (from VertixUtils.AssetType)
     * @param assetId Unique identifier for the asset
     * @param price Sale price in wei
     * @param metadata Additional metadata
     * @param verificationProof Verification data
     */
    function listNonNftAsset(
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
        if (STORAGE_CONTRACT.checkListingHash(listingHash)) revert MC__DuplicateListing();

        uint256 listingId = STORAGE_CONTRACT.createNonNftListing(
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
    function listSocialMediaNft(
        uint256 tokenId,
        uint96 price,
        string calldata socialMediaId,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        address nftContractAddr = address(STORAGE_CONTRACT.vertixNftContract());
        
        // Additional validation specific to social media NFTs
        if (!STORAGE_CONTRACT.vertixNftContract().getUsedSocialMediaIds(socialMediaId)) {
            revert MC__InvalidSocialMediaNFT();
        }

        // Verify signature
        address verificationServer = GOVERNANCE_CONTRACT.getVerificationServer();
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, tokenId, price, socialMediaId));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        if (ECDSA.recover(ethSignedHash, signature) != verificationServer) revert MC__InvalidSignature();

        // Use common validation and listing creation
        _validateListingRequirements(nftContractAddr, tokenId, price);
        _createNftListing(nftContractAddr, tokenId, price);
    }

        /**
     * @dev List an NFT for auction
     * @param listingId ID of the NFT
     * @param isNft true if NFT and false if non-NFT
     */
    function listForAuction(
        uint256 listingId,
        bool isNft
    ) external nonReentrant whenNotPaused {
        if (isNft) {
            (
                address seller,
                ,
                ,
                ,
                bool active,
            ) = STORAGE_CONTRACT.getNftListing(listingId);

            if (!active) revert MC__InvalidListing();
            if (msg.sender != seller) revert MC__NotSeller();
            if (STORAGE_CONTRACT.isTokenListedForAuction(listingId)) revert Mc_AlreadyListedForAuction();

            STORAGE_CONTRACT.updateNftListingFlags(listingId, 3); // Set auction listed
            emit ListedForAuction(listingId, true, true);
        } else {
            (
                address seller,
                ,
                ,
                bool active,
                bool auctionListed,
                ,
                ,
            ) = STORAGE_CONTRACT.getNonNftListing(listingId);

            if (!active) revert MC__InvalidListing();
            if (msg.sender != seller) revert MC__NotSeller();
            if (auctionListed) revert Mc_AlreadyListedForAuction();

            STORAGE_CONTRACT.updateNonNftListingFlags(listingId, 3); // Set auction listed
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
    function buyNft(uint256 listingId) external payable nonReentrant whenNotPaused {
        (
            address seller,
            address nftContractAddr,
            uint256 tokenId,
            uint96 price,
            bool active,
        ) = STORAGE_CONTRACT.getNftListing(listingId);

        if (!active) revert MC__InvalidListing();
        if (msg.value < price) revert MC__InsufficientPayment();

        // Mark inactive before transfers (CEI pattern)
        STORAGE_CONTRACT.updateNftListingFlags(listingId, 0);
        STORAGE_CONTRACT.removeNftListingHash(nftContractAddr, tokenId);

        _safeTransferNft(nftContractAddr, address(this), msg.sender, tokenId);


        MarketplaceFees.PaymentConfig memory config = MarketplaceFees.PaymentConfig({
            totalPayment: msg.value,
            salePrice: price,
            nftContract: nftContractAddr,
            tokenId: tokenId,
            seller: seller,
            hasRoyalties: true
        });

        uint256 refundAmount = FEES_CONTRACT.processNftSalePayment{value: msg.value}(config);
        if (refundAmount > 0) {
            FEES_CONTRACT.refundExcessPayment(msg.sender, refundAmount);
        }
        MarketplaceFees.FeeDistribution memory fees = FEES_CONTRACT.calculateNftFees(price, nftContractAddr, tokenId);

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
    function buyNonNftAsset(uint256 listingId) external payable nonReentrant whenNotPaused {
        (
            address seller,
            uint96 price,
            ,
            bool active,
            ,
            string memory assetId,
            ,
        ) = STORAGE_CONTRACT.getNonNftListing(listingId);

        if (!active) revert MC__InvalidListing();
        if (msg.value < price) revert MC__InsufficientPayment();

        // Mark inactive before transfers
        STORAGE_CONTRACT.updateNonNftListingFlags(listingId, 0);
        STORAGE_CONTRACT.removeNonNftListingHash(seller, assetId);

        // Process payment
        uint256 refundAmount = FEES_CONTRACT.processNonNftSalePayment{value: msg.value}(
            listingId,
            price,
            seller,
            msg.sender
        );

        // Refund excess
        if (refundAmount > 0) {
            FEES_CONTRACT.refundExcessPayment(msg.sender, refundAmount);
        }

        MarketplaceFees.FeeDistribution memory fees = FEES_CONTRACT.calculateNonNftFees(price);

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
    function cancelNftListing(uint256 listingId) external nonReentrant whenNotPaused {
        (
            address seller,
            address nftContractAddr,
            uint256 tokenId,
            ,
            bool active,
        ) = STORAGE_CONTRACT.getNftListing(listingId);

        _validateCancellation(seller, active);

        STORAGE_CONTRACT.updateNftListingFlags(listingId, 0); // Set inactive
        STORAGE_CONTRACT.removeNftListingHash(nftContractAddr, tokenId);

        _safeTransferNft(nftContractAddr, address(this), seller, tokenId);
        emit NFTListingCancelled(listingId, seller, true);
    }

    /**
     * @dev Cancel a non-NFT listing
     * @param listingId ID of the listing
     */
    function cancelNonNftListing(uint256 listingId) external nonReentrant whenNotPaused {
        (
            address seller,
            ,
            ,
            bool active,
            ,
            string memory assetId,
            ,
        ) = STORAGE_CONTRACT.getNonNftListing(listingId);

        _validateCancellation(seller, active);

        STORAGE_CONTRACT.updateNonNftListingFlags(listingId, 0); // Set inactive
        STORAGE_CONTRACT.removeNonNftListingHash(seller, assetId);

        emit NonNFTListingCancelled(listingId, seller, false);
    }


    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external {
        if (msg.sender != STORAGE_CONTRACT.owner()) revert MC__NotOwner();
        _pause();
    }

    function unpause() external {
        if (msg.sender != STORAGE_CONTRACT.owner()) revert MC__NotOwner();
        _unpause();
    }

    fallback() payable external{}
    receive() payable external{}
}
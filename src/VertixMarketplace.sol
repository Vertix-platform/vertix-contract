// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IVertixNFT} from "./interfaces/IVertixNFT.sol";
import {IVertixGovernance} from "./interfaces/IVertixGovernance.sol";
import {VertixUtils} from "./libraries/VertixUtils.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title VertixMarketplace
 * @dev Decentralized marketplace for NFT and non-NFT assets with royalties and platform fees
 */
contract VertixMarketplace is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable
{
    using VertixUtils for *;

    // Errors
    error VertixMarketplace__InvalidListing();
    error VertixMarketplace__NotOwner();
    error VertixMarketplace__InvalidAssetType();
    error VertixMarketplace__InsufficientPayment();
    error VertixMarketplace__TransferFailed();
    error VertixMarketplace__InvalidNFTContract();
    error VertixMarketplace__DuplicateListing();
    error VertixMarketplace__NotSeller();

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

    // State variables
    IVertixNFT public nftContract;
    IVertixGovernance public governanceContract;
    address public escrowContract;
    uint256 private _listingIdCounter;
    mapping(uint256 => NFTListing) private _nftListings;
    mapping(uint256 => NonNFTListing) private _nonNFTListings;
    mapping(bytes32 => bool) private _listingHashes; // Prevents duplicate listings

    // Events
    event NFTListed(
        uint256 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price
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
    event NonNFTBought(
        uint256 indexed listingId, address indexed buyer, uint256 price, uint256 platformFee, address feeRecipient
    );
    event NFTListingCancelled(uint256 indexed listingId, address indexed seller);
    event NonNFTListingCancelled(uint256 indexed listingId, address indexed seller);

    // Modifiers
    modifier onlyValidNFTListing(uint256 listingId) {
        if (!_nftListings[listingId].active) revert VertixMarketplace__InvalidListing();
        _;
    }

    modifier onlyValidNonNFTListing(uint256 listingId) {
        if (!_nonNFTListings[listingId].active) revert VertixMarketplace__InvalidListing();
        _;
    }

    // Initialization
    function initialize(address _nftContract, address _governanceContract, address _escrowContract)
        public
        initializer
    {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __Pausable_init();
        nftContract = IVertixNFT(_nftContract);
        governanceContract = IVertixGovernance(_governanceContract);
        escrowContract = _escrowContract;
        _listingIdCounter = 1;
    }

    // Upgrade authorization
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Public functions
    /**
     * @dev List an NFT for sale
     * @param nftContractAddr Address of NFT contract
     * @param tokenId ID of the NFT
     * @param price Sale price in wei
     */
    function listNFT(address nftContractAddr, uint256 tokenId, uint256 price) external nonReentrant whenNotPaused {
        VertixUtils.validatePrice(price);
        if (nftContractAddr != address(nftContract)) revert VertixMarketplace__InvalidNFTContract();
        if (IERC721(nftContractAddr).ownerOf(tokenId) != msg.sender) revert VertixMarketplace__NotOwner();

        bytes32 listingHash = keccak256(abi.encodePacked(nftContractAddr, tokenId));
        if (_listingHashes[listingHash]) revert VertixMarketplace__DuplicateListing();

        IERC721(nftContractAddr).transferFrom(msg.sender, address(this), tokenId);

        uint256 listingId = _listingIdCounter++;
        _nftListings[listingId] =
            NFTListing({seller: msg.sender, nftContract: nftContractAddr, tokenId: tokenId, price: price, active: true});
        _listingHashes[listingHash] = true;

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
        uint256 price,
        string calldata metadata,
        bytes calldata verificationProof
    ) external nonReentrant whenNotPaused {
        VertixUtils.validatePrice(price);
        if (assetType > uint8(VertixUtils.AssetType.Other)) revert VertixMarketplace__InvalidAssetType();

        bytes32 listingHash = keccak256(abi.encodePacked(msg.sender, assetId));
        if (_listingHashes[listingHash]) revert VertixMarketplace__DuplicateListing();

        uint256 listingId = _listingIdCounter++;
        _nonNFTListings[listingId] = NonNFTListing({
            seller: msg.sender,
            assetType: VertixUtils.AssetType(assetType),
            assetId: assetId,
            price: price,
            metadata: metadata,
            verificationHash: VertixUtils.hashVerificationProof(verificationProof),
            active: true
        });
        _listingHashes[listingHash] = true;

        emit NonNFTListed(listingId, msg.sender, VertixUtils.AssetType(assetType), assetId, price);
    }

    /**
     * @dev Buy an NFT listing, paying royalties and platform fees
     * @param listingId ID of the listing to purchase
     */
    function buyNFT(uint256 listingId) external payable nonReentrant whenNotPaused onlyValidNFTListing(listingId) {
        NFTListing memory listing = _nftListings[listingId];
        if (msg.value < listing.price) revert VertixMarketplace__InsufficientPayment();

        // Get royalty info
        (address royaltyRecipient, uint256 royaltyAmount) =
            IERC2981(address(nftContract)).royaltyInfo(listing.tokenId, listing.price);

        // Get platform fee info
        (uint256 platformFeeBps, address feeRecipient) = governanceContract.getFeeConfig();
        uint256 platformFee = (listing.price * platformFeeBps) / 10000;

        // Validate total payment
        uint256 totalDeduction = royaltyAmount + platformFee;
        if (totalDeduction > listing.price) revert VertixMarketplace__InsufficientPayment();

        // Mark listing as inactive and remove from hashes
        _nftListings[listingId].active = false;
        delete _listingHashes[keccak256(abi.encodePacked(listing.nftContract, listing.tokenId))];

        // Transfer NFT to buyer
        IERC721(listing.nftContract).transferFrom(address(this), msg.sender, listing.tokenId);

        // Transfer royalties, platform fee, and seller proceeds
        if (royaltyAmount > 0) {
            (bool royaltySuccess,) = payable(royaltyRecipient).call{value: royaltyAmount}("");
            if (!royaltySuccess) revert VertixMarketplace__TransferFailed();
        }
        if (platformFee > 0) {
            (bool feeSuccess,) = payable(feeRecipient).call{value: platformFee}("");
            if (!feeSuccess) revert VertixMarketplace__TransferFailed();
        }
        (bool sellerSuccess,) = payable(listing.seller).call{value: listing.price - totalDeduction}("");
        if (!sellerSuccess) revert VertixMarketplace__TransferFailed();

        // Refund excess payment
        _refundExcessPayment(msg.value, listing.price);

        emit NFTBought(listingId, msg.sender, listing.price, royaltyAmount, royaltyRecipient, platformFee, feeRecipient);
    }

    /**
     * @dev Buy a non-NFT asset listing, paying platform fee
     * @param listingId ID of the listing to purchase
     */
    function buyNonNFTAsset(uint256 listingId)
        external
        payable
        nonReentrant
        whenNotPaused
        onlyValidNonNFTListing(listingId)
    {
        NonNFTListing memory listing = _nonNFTListings[listingId];
        if (msg.value < listing.price) revert VertixMarketplace__InsufficientPayment();

        // Get platform fee info
        (uint256 platformFeeBps, address feeRecipient) = governanceContract.getFeeConfig();
        uint256 platformFee = (listing.price * platformFeeBps) / 10000;

        // Validate total payment
        if (platformFee > listing.price) revert VertixMarketplace__InsufficientPayment();

        // Mark listing as inactive and remove from hashes
        _nonNFTListings[listingId].active = false;
        delete _listingHashes[keccak256(abi.encodePacked(listing.seller, listing.assetId))];

        // Transfer platform fee
        if (platformFee > 0) {
            (bool feeSuccess,) = payable(feeRecipient).call{value: platformFee}("");
            if (!feeSuccess) revert VertixMarketplace__TransferFailed();
        }

        // Transfer remaining funds to escrow
        uint256 escrowAmount = listing.price - platformFee;
        (bool success,) = escrowContract.call{value: escrowAmount}(
            abi.encodeWithSignature(
                "lockFunds(uint256,address,address,uint256)", listingId, listing.seller, msg.sender, escrowAmount
            )
        );
        if (!success) revert VertixMarketplace__TransferFailed();

        // Refund excess payment
        _refundExcessPayment(msg.value, listing.price);

        emit NonNFTBought(listingId, msg.sender, listing.price, platformFee, feeRecipient);
    }

    /**
     * @dev Cancel an NFT listing
     * @param listingId The ID of the listing
     */
    function cancelNFTListing(uint256 listingId) external nonReentrant onlyValidNFTListing(listingId) {
        NFTListing memory listing = _nftListings[listingId];
        if (msg.sender != listing.seller) revert VertixMarketplace__NotSeller();

        _nftListings[listingId].active = false;
        delete _listingHashes[keccak256(abi.encodePacked(listing.nftContract, listing.tokenId))];
        IERC721(listing.nftContract).transferFrom(address(this), listing.seller, listing.tokenId);

        emit NFTListingCancelled(listingId, listing.seller);
    }

    /**
     * @dev Cancel a non-NFT listing
     * @param listingId The ID of the listing
     */
    function cancelNonNFTListing(uint256 listingId) external nonReentrant onlyValidNonNFTListing(listingId) {
        NonNFTListing memory listing = _nonNFTListings[listingId];
        if (msg.sender != listing.seller) revert VertixMarketplace__NotSeller();

        _nonNFTListings[listingId].active = false;
        delete _listingHashes[keccak256(abi.encodePacked(listing.seller, listing.assetId))];

        emit NonNFTListingCancelled(listingId, listing.seller);
    }

    // Internal functions
    /**
     * @dev Refund excess payment to buyer
     * @param paidAmount Amount sent by buyer
     * @param requiredAmount Actual price of item
     */
    function _refundExcessPayment(uint256 paidAmount, uint256 requiredAmount) internal {
        if (paidAmount > requiredAmount) {
            (bool success,) = msg.sender.call{value: paidAmount - requiredAmount}("");
            if (!success) revert VertixMarketplace__TransferFailed();
        }
    }

    // View functions
    /**
     * @dev Get NFT listing details
     * @param listingId ID of the listing
     */
    function getNFTListing(uint256 listingId) external view returns (NFTListing memory) {
        return _nftListings[listingId];
    }

    /**
     * @dev Get non-NFT listing details
     * @param listingId ID of the listing
     */
    function getNonNFTListing(uint256 listingId) external view returns (NonNFTListing memory) {
        return _nonNFTListings[listingId];
    }

    /**
     * @dev Get total number of listings
     */
    function getTotalListings() external view returns (uint256) {
        return _listingIdCounter;
    }

    function getListingsByCollection(uint256 collectionId) external view returns (uint256[] memory) {
        uint256[] memory tokenIds = nftContract.getCollectionTokens(collectionId);
        uint256[] memory listingIds = new uint256[](tokenIds.length);
        uint256 count = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            bytes32 listingHash = keccak256(abi.encodePacked(address(nftContract), tokenIds[i]));
            if (_listingHashes[listingHash]) {
                for (uint256 j = 1; j < _listingIdCounter; j++) {
                    if (_nftListings[j].tokenId == tokenIds[i] && _nftListings[j].active) {
                        listingIds[count] = j;
                        count++;
                        break;
                    }
                }
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = listingIds[i];
        }
        return result;
    }

    function getListingsByPriceRange(uint256 minPrice, uint256 maxPrice) external view returns (uint256[] memory) {
        uint256[] memory listingIds = new uint256[](0);
        uint256 count = 0;

        for (uint256 i = 1; i < _listingIdCounter; i++) {
            if (_nftListings[i].active && _nftListings[i].price >= minPrice && _nftListings[i].price <= maxPrice) {
                // Manually resize the array
                uint256[] memory newListingIds = new uint256[](count + 1);
                for (uint256 j = 0; j < count; j++) {
                    newListingIds[j] = listingIds[j];
                }
                newListingIds[count] = i;
                listingIds = newListingIds;
                count++;
            }
        }

        return listingIds;
    }

    function getListingsByAssetType(VertixUtils.AssetType assetType) external view returns (uint256[] memory) {
        uint256[] memory listingIds = new uint256[](0);
        uint256 count = 0;

        for (uint256 i = 1; i < _listingIdCounter; i++) {
            if (_nonNFTListings[i].active && _nonNFTListings[i].assetType == assetType) {
                // Manually resize the array
                uint256[] memory newListingIds = new uint256[](count + 1);
                for (uint256 j = 0; j < count; j++) {
                    newListingIds[j] = listingIds[j];
                }
                newListingIds[count] = i;
                listingIds = newListingIds;
                count++;
            }
        }

        return listingIds;
    }

    function getPurchaseDetails(uint256 listingId)
        external
        view
        returns (
            uint256 price,
            uint256 royaltyAmount,
            address royaltyRecipient,
            uint256 platformFee,
            address feeRecipient,
            uint256 sellerProceeds
        )
    {
        NFTListing memory listing = _nftListings[listingId];
        if (!listing.active) revert VertixMarketplace__InvalidListing();

        (royaltyRecipient, royaltyAmount) = IERC2981(address(nftContract)).royaltyInfo(listing.tokenId, listing.price);
        (uint16 feeBps, address recipient) = governanceContract.getFeeConfig();
        platformFee = (listing.price * feeBps) / 10000;
        sellerProceeds = listing.price - royaltyAmount - platformFee;

        return (listing.price, royaltyAmount, royaltyRecipient, platformFee, recipient, sellerProceeds);
    }
}

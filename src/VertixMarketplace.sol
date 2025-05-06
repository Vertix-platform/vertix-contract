// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IVertixNFT} from "./interfaces/IVertixNFT.sol";
import {VertixUtils} from "./libraries/VertixUtils.sol";

/**
 * @title VertixMarketplace
 * @dev Decentralized marketplace for NFT and non-NFT assets
 */
contract VertixMarketplace is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
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

    // Type declarations
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
    address public escrowContract;
    uint256 private _listingIdCounter;
    mapping(uint256 => NFTListing) private _nftListings;
    mapping(uint256 => NonNFTListing) private _nonNFTListings;
    mapping(bytes32 => bool) private _listingHashes; // Prevents duplicate listings

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
    event NFTBought(uint256 indexed listingId, address indexed buyer, uint256 price);
    event NonNFTBought(uint256 indexed listingId, address indexed buyer, uint256 price);
    event ListingCancelled(uint256 indexed listingId, bool isNFT);

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
    function initialize(address _nftContract, address _escrowContract) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        nftContract = IVertixNFT(_nftContract);
        escrowContract = _escrowContract;
        _listingIdCounter = 1;
    }

    // Upgrade authorization
    function _authorizeUpgrade(address) internal override onlyOwner {}


    // Public functions
    /**
     * @dev List an NFT for sale
     * @param nftContractAddr Address of NFT contract
     * @param tokenId ID of the NFT
     * @param price Sale price in wei
     */
    function listNFT(
        address nftContractAddr,
        uint256 tokenId,
        uint256 price
    ) external nonReentrant {
        VertixUtils.validatePrice(price);
        if (nftContractAddr != address(nftContract)) revert VertixMarketplace__InvalidNFTContract();
        if (IERC721(nftContractAddr).ownerOf(tokenId) != msg.sender) revert VertixMarketplace__NotOwner();

        bytes32 listingHash = keccak256(abi.encodePacked(nftContractAddr, tokenId));
        if (_listingHashes[listingHash]) revert VertixMarketplace__DuplicateListing();

        IERC721(nftContractAddr).transferFrom(msg.sender, address(this), tokenId);

        uint256 listingId = _listingIdCounter++;
        _nftListings[listingId] = NFTListing({
            seller: msg.sender,
            nftContract: nftContractAddr,
            tokenId: tokenId,
            price: price,
            active: true
        });
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
    ) external nonReentrant {
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
     * @dev Buy an NFT listing
     * @param listingId ID of the listing to purchase
     */
    function buyNFT(uint256 listingId) external payable nonReentrant onlyValidNFTListing(listingId) {
        NFTListing memory listing = _nftListings[listingId];
        if (msg.value < listing.price) revert VertixMarketplace__InsufficientPayment();

        _nftListings[listingId].active = false;
        delete _listingHashes[keccak256(abi.encodePacked(listing.nftContract, listing.tokenId))];

        IERC721(listing.nftContract).transferFrom(address(this), msg.sender, listing.tokenId);

        (bool success, ) = listing.seller.call{value: listing.price}("");
        if (!success) revert VertixMarketplace__TransferFailed();

        _refundExcessPayment(msg.value, listing.price);
        emit NFTBought(listingId, msg.sender, listing.price);
    }

    /**
     * @dev Buy a non-NFT asset listing
     * @param listingId ID of the listing to purchase
     */
    function buyNonNFTAsset(uint256 listingId) external payable nonReentrant onlyValidNonNFTListing(listingId) {
        NonNFTListing memory listing = _nonNFTListings[listingId];
        if (msg.value < listing.price) revert VertixMarketplace__InsufficientPayment();

        _nonNFTListings[listingId].active = false;
        delete _listingHashes[keccak256(abi.encodePacked(listing.seller, listing.assetId))];

        (bool success, ) = escrowContract.call{value: listing.price}(
            abi.encodeWithSignature(
                "lockFunds(uint256,address,address,uint256)",
                listingId,
                listing.seller,
                msg.sender,
                listing.price
            )
        );
        if (!success) revert VertixMarketplace__TransferFailed();

        _refundExcessPayment(msg.value, listing.price);
        emit NonNFTBought(listingId, msg.sender, listing.price);
    }

    // Internal functions
    /**
     * @dev Refund excess payment to buyer
     * @param paidAmount Amount sent by buyer
     * @param requiredAmount Actual price of item
     */
    function _refundExcessPayment(uint256 paidAmount, uint256 requiredAmount) internal {
        if (paidAmount > requiredAmount) {
            (bool success, ) = msg.sender.call{value: paidAmount - requiredAmount}("");
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
}
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
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title VertixMarketplace
 * @dev Decentralized marketplace for NFT and non-NFT assets with royalties and platform fees
 */
contract VertixMarketplace is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    IERC721Receiver
{
    using VertixUtils for *;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error VertixMarketplace__InvalidListing();
    error VertixMarketplace__NotOwner();
    error VertixMarketplace__InvalidAssetType();
    error VertixMarketplace__InsufficientPayment();
    error VertixMarketplace__TransferFailed();
    error VertixMarketplace__InvalidNFTContract();
    error VertixMarketplace__DuplicateListing();
    error VertixMarketplace__NotSeller();

    error VertixMarketplace__IncorrectDuration(uint24 duration);
    error VertixMarketplace__AlreadyListedForAuction();
    error VertixMarketplace__AuctionExpired();
    error VertixMarketplace__AuctionBidTooLow(uint256 bidAmount);
    error VertixMarketplace__AuctionInactive();
    error VertixMarketplace__ContractInsufficientBalance();
    error VertixMarketplace__AuctionOngoing(uint256 timestamp);
    error VertixMarketplace__FeeTransferFailed();
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

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
    event NFTListed(
        uint256 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price
    );

    event NFTListingCancelled(uint256 indexed listingId, address indexed seller);
    event NonNFTListingCancelled(uint256 indexed listingId, address indexed seller);

    event NFTAuctionStarted(
        uint256 indexed auctionId,
        address indexed seller,
        uint256 startTime,
        uint24 duration,
        uint256 price,
        address nftContract,
        uint256 tokenId
    );

    event BidPlaced(
        uint256 indexed auctionId, uint256 indexed bidId, address indexed seller, uint256 bidAmount, uint256 tokenId
    );

    event AuctionEnded(
        uint256 indexed auctionId, address indexed seller, address indexed bidder, uint256 highestBid, uint256 tokenId
    );
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct Bid {
        uint256 auctionId;
        uint256 bidAmount;
        uint256 bidId;
        address bidder;
    }

    struct NFTListing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }

    struct NonNFTListing {
        address seller;
        bool active;
        string assetId;
        uint256 price;
        string metadata;
        bytes32 verificationHash;
        VertixUtils.AssetType assetType;
    }

    struct AuctionDetails {
        bool active;
        uint24 duration;
        uint256 startTime;
        address seller;
        address highestBidder;
        uint256 highestBid;
        uint256 tokenId;
        uint256 auctionId;
        uint256 startingPrice;
        IVertixNFT nftContract;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IVertixNFT public nftContract;
    IVertixGovernance public governanceContract;

    uint24 private constant MIN_AUCTION_DURATION = 1 hours;
    uint24 private constant MAX_AUCTION_DURATION = 7 days;

    address public escrowContract;
    uint256 private _auctionIdCounter;
    uint256 private _listingIdCounter;

    mapping(bytes32 => bool) private _listingHashes;
    mapping(uint256 => NFTListing) private _nftListings;
    mapping(uint256 => NonNFTListing) private _nonNFTListings;

    mapping(uint256 tokenId => bool listedForAuction) private _listedForAuction;
    mapping(uint256 tokenId => uint256 auctionId) private _auctionIdForToken;
    mapping(uint256 auctionId => uint256 tokenId) private _tokenIdForAuction;
    mapping(uint256 auctionId => AuctionDetails) private _auctionListings;

    mapping(uint256 auctionId => Bid[]) private _bidsPlaced;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyValidNFTListing(uint256 listingId) {
        if (!_nftListings[listingId].active) revert VertixMarketplace__InvalidListing();
        _;
    }

    modifier onlyValidNonNFTListing(uint256 listingId) {
        if (!_nonNFTListings[listingId].active) revert VertixMarketplace__InvalidListing();
        _;
    }

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
        _auctionIdCounter = 1;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

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
                "lockFunds(uint256, address, address)", listingId, listing.seller, msg.sender
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

    /**
     * @notice starts an auction for a vertix NFT, which is only callable by the owner
     * @param _nftContract the contract address of the vertix NFT being auctioned
     * @param _tokenId the tokenId of the vertix NFT being auctioned
     * @param _duration the duration of the auction (in seconds)
     * @param _price minimum price being accepted for the auction
     */
    function startNFTAuction(address _nftContract, uint256 _tokenId, uint24 _duration, uint256 _price) external {
        if (IVertixNFT(_nftContract) != nftContract) revert VertixMarketplace__InvalidNFTContract();
        if (IVertixNFT(_nftContract).ownerOf(_tokenId) != msg.sender) revert VertixMarketplace__NotOwner();
        if (_duration < MIN_AUCTION_DURATION || _duration > MAX_AUCTION_DURATION) {
            revert VertixMarketplace__IncorrectDuration(_duration);
        }

        VertixUtils.validatePrice(_price);

        if (_listedForAuction[_tokenId]) revert VertixMarketplace__AlreadyListedForAuction();

        uint256 _auctionId = _auctionIdCounter++;

        _listedForAuction[_tokenId] = true;
        _auctionIdForToken[_tokenId] = _auctionId;
        _tokenIdForAuction[_auctionId] = _tokenId;

        _auctionListings[_auctionId] = AuctionDetails({
            active: true,
            duration: _duration,
            startTime: block.timestamp,
            seller: msg.sender,
            highestBidder: address(0),
            highestBid: 0,
            nftContract: IVertixNFT(_nftContract),
            tokenId: _tokenId,
            auctionId: _auctionId,
            startingPrice: _price
        });

        IVertixNFT(_nftContract).transferFrom(msg.sender, address(this), _tokenId);
        emit NFTAuctionStarted(_auctionId, msg.sender, block.timestamp, _duration, _price, _nftContract, _tokenId);
    }

    /**
     * @notice Place a bid on an active NFT auction
     * @dev Checks auction validity, minimum bid requirements, and handles bid replacement
     * @param _auctionId The ID of the auction to bid on
     */
    function placeBidForAuction(uint256 _auctionId) external payable nonReentrant {
        AuctionDetails storage details = _auctionListings[_auctionId];

        if (!details.active) revert VertixMarketplace__AuctionInactive();
        if (block.timestamp > details.startTime + details.duration) revert VertixMarketplace__AuctionExpired();

        (uint256 platformFeeBps,) = governanceContract.getFeeConfig();

        uint256 platformFee = (details.startingPrice * platformFeeBps) / 10000;

        if (msg.value < details.startingPrice || msg.value <= details.highestBid || msg.value < platformFee) {
            revert VertixMarketplace__AuctionBidTooLow(msg.value);
        }

        if (details.highestBid > 0) {
            if (address(this).balance - msg.value < details.highestBid) {
                revert VertixMarketplace__ContractInsufficientBalance();
            }
            (bool success,) = payable(details.highestBidder).call{value: details.highestBid}("");
            if (!success) revert VertixMarketplace__TransferFailed();
        }

        uint256 bidId = _bidsPlaced[_auctionId].length;

        // store placed bid for auctionId
        Bid memory newBid = Bid({auctionId: _auctionId, bidAmount: msg.value, bidId: bidId, bidder: msg.sender});
        _bidsPlaced[_auctionId].push(newBid);

        // update highest bid and highest bidder
        details.highestBid = msg.value;
        details.highestBidder = msg.sender;

        emit BidPlaced(_auctionId, bidId, msg.sender, msg.value, details.tokenId);
    }

    /**
     * @notice End an NFT auction after its duration has expired
     * @dev Distributes funds and NFT based on auction outcome
     * @param _auctionId The ID of the auction to end
     */
    function endAuction(uint256 _auctionId) external nonReentrant {
        AuctionDetails storage details = _auctionListings[_auctionId];
        if (details.seller != msg.sender) revert VertixMarketplace__NotSeller();
        if (!details.active) revert VertixMarketplace__AuctionInactive();
        if (block.timestamp < details.startTime + details.duration) {
            revert VertixMarketplace__AuctionOngoing(block.timestamp);
        }

        address highestBidder = details.highestBidder;
        uint256 highestBid = details.highestBid;
        uint256 tokenID = details.tokenId;

        if (highestBid > 0) {
            (uint256 platformFeeBps, address feeRecipient) = governanceContract.getFeeConfig();

            uint256 platformFee = (highestBid * platformFeeBps) / 10000;

            if (platformFee > 0) {
                (bool feeSuccess,) = payable(feeRecipient).call{value: platformFee}("");
                if (!feeSuccess) revert VertixMarketplace__FeeTransferFailed();
            }

            //  transfer remainder of sales to seller and NFT to highest bidder
            (bool sellerSuccess,) = payable(details.seller).call{value: details.highestBid - platformFee}("");
            if (!sellerSuccess) revert VertixMarketplace__TransferFailed();

            details.nftContract.transferFrom(address(this), highestBidder, tokenID);
        } else {
            // if no bid we transfer back the nft to seller
            details.nftContract.transferFrom(address(this), details.seller, details.tokenId);
        }

        _listedForAuction[_auctionId] = false;
        details.active = false;
        emit AuctionEnded(_auctionId, details.seller, highestBidder, highestBid, tokenID);
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE & INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
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

    // Upgrade authorization
    function _authorizeUpgrade(address) internal override onlyOwner {}

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
        uint256 listingCounter = _listingIdCounter;

        uint256 tokenLength = tokenIds.length;
        for (uint256 i = 0; i < tokenLength; i++) {
            bytes32 listingHash = keccak256(abi.encodePacked(address(nftContract), tokenIds[i]));
            if (_listingHashes[listingHash]) {
                for (uint256 j = 1; j < listingCounter; j++) {
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

    /**
     * @dev Returns whether a token is listed for auction
     * @param tokenId The ID of the NFT
     * @return bool True if the token is listed for auction, false otherwise
     */
    function isListedForAuction(uint256 tokenId) external view returns (bool) {
        return _listedForAuction[tokenId];
    }

    /**
     * @dev Returns the auction ID associated with a token
     * @param tokenId The ID of the NFT
     * @return uint256 The auction ID for the token, or 0 if not listed
     */
    function getAuctionIdForToken(uint256 tokenId) external view returns (uint256) {
        return _auctionIdForToken[tokenId];
    }

    /**
     * @dev Returns the token ID being auctioned
     * @param _auctionId The ID of the auction
     * @return uint256 The token ID of the NFT being auctioned
     */
    function getTokenIdForAuction(uint256 _auctionId) external view returns (uint256) {
        return _tokenIdForAuction[_auctionId];
    }

    /**
     * @dev Retrieves a specific bid for an auction
     * @param _auctionId The ID of the auction
     * @param _bidId The ID of the bid (index in the bids array)
     * @return Bid The bid details
     */
    function getSingleBidForAuction(uint256 _auctionId, uint256 _bidId) external view returns (Bid memory) {
        return _bidsPlaced[_auctionId][_bidId];
    }

    /**
     * @dev Retrieves all bids for an auction
     * @param _auctionId The ID of the auction
     * @return Bid[] Array of all bids
     */
    function getAllBidsForAuction(uint256 _auctionId) external view returns (Bid[] memory) {
        return _bidsPlaced[_auctionId];
    }

    /**
     * @dev Retrieves the total number of bids for an auction
     * @param _auctionId The ID of the auction
     * @return uint256 The number of bids
     */
    function getBidCountForAuction(uint256 _auctionId) external view returns (uint256) {
        return _bidsPlaced[_auctionId].length;
    }

    /**
     * @dev Returns the details of an auction
     * @param auctionId The ID of the auction
     * @return AuctionDetails The auction details struct
     */
    function getAuctionDetails(uint256 auctionId) external view returns (AuctionDetails memory) {
        return _auctionListings[auctionId];
    }

    // @inherit-doc
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        pure
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }
}

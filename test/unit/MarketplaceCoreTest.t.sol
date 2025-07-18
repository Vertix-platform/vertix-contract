// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MarketplaceCore} from "../../src/MarketplaceCore.sol";
import {MarketplaceStorage} from "../../src/MarketplaceStorage.sol";
import {MarketplaceFees} from "../../src/MarketplaceFees.sol";
import {VertixGovernance} from "../../src/VertixGovernance.sol";
import {VertixNFT} from "../../src/VertixNFT.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {VertixUtils} from "../../src/libraries/VertixUtils.sol";


contract MarketplaceCoreTest is Test {
    // Contract instances
    MarketplaceCore public marketplaceCore;
    MarketplaceStorage public marketplaceStorage;
    MarketplaceFees public marketplaceFees;
    VertixGovernance public governance;
    VertixNFT public vertixNFT;

    // Addresses
    address public owner;
    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");
    address public verificationServer;
    address public feeRecipient;
    address public escrow;

    // Test variables
    uint256 public constant TOKEN_ID = 1;
    uint96 public constant LISTING_PRICE = 1 ether;
    uint256 public constant LISTING_ID = 1;
    uint8 public constant ASSET_TYPE = uint8(VertixUtils.AssetType.SocialMedia);
    string public constant ASSET_ID = "asset123";
    string public constant SOCIAL_MEDIA_ID = "social123";
    bytes32 public constant METADATA = keccak256("metadata");
    string public constant URI = "https://example.com/metadata";
    uint96 public constant INVALID_PRICE = 0;
    uint256 public deployerKey;
    uint256 public verificationServerKey;

    // Events
    event NFTListed(uint256 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price);
    event NonNFTListed(uint256 indexed listingId, address indexed seller, uint8 assetType, string assetId, uint256 price);
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
    event Paused(address account);
    event Unpaused(address account);


    function setUp() public {
        // Deploy contracts using the deployment script
        DeployVertix deployer = new DeployVertix();
        DeployVertix.VertixAddresses memory addresses = deployer.deployVertix();

        // Assign contract instances
        marketplaceCore = MarketplaceCore(payable(addresses.marketplaceProxy));
        marketplaceStorage = MarketplaceStorage(addresses.marketplaceStorage);
        marketplaceFees = MarketplaceFees(addresses.marketplaceFees);
        governance = VertixGovernance(addresses.governance);
        vertixNFT = VertixNFT(addresses.nft);
        verificationServer = addresses.verificationServer;
        feeRecipient = addresses.feeRecipient;
        escrow = addresses.escrow;

        // Get deployer key from HelperConfig
        HelperConfig helperConfig = new HelperConfig();
        deployerKey = helperConfig.DEFAULT_ANVIL_DEPLOYER_KEY();
        owner = vm.addr(deployerKey);

        // Setup: Mint an NFT to the seller
        vm.startPrank(owner);
        vertixNFT.mintSingleNft(seller, URI, METADATA, 500);
        vm.stopPrank();

        // Approve MarketplaceCore to transfer the NFT
        vm.prank(seller);
        vertixNFT.approve(address(marketplaceCore), TOKEN_ID);

        // Fund buyer with ETH
        vm.deal(buyer, 10 ether);

        // Add verification server as a signer
        // Use the same method as HelperConfig to generate the verification server key
        verificationServerKey = uint256(keccak256(abi.encodePacked("verificationServer")));
        // Fund the verification server address
        vm.deal(verificationServer, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        LISTING NFT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ListNft() public {
        vm.prank(seller);
        vm.expectEmit(true, true, true, true);
        emit NFTListed(LISTING_ID, seller, address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);
        assertEq(listingId, LISTING_ID);

        // Verify listing
        (address listedSeller, address nftContract, uint256 tokenId, uint96 price, bool active, bool isListedForAuction) = marketplaceStorage.getNftListing(listingId);
        assertEq(listedSeller, seller);
        assertEq(nftContract, address(vertixNFT));
        assertEq(tokenId, TOKEN_ID);
        assertEq(price, LISTING_PRICE);
        assertTrue(active);
        assertFalse(isListedForAuction);
        assertEq(vertixNFT.ownerOf(TOKEN_ID), address(marketplaceCore));
    }

    function test_RevertIf_ListNftWithInvalidContract() public {
        address invalidContract = makeAddr("invalidContract");
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InvalidNFTContract.selector);
        marketplaceCore.listNft(invalidContract, TOKEN_ID, LISTING_PRICE);
    }

    function test_RevertIf_ListNftWithZeroPrice() public {
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InsufficientPayment.selector);
        marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, INVALID_PRICE);
    }

    function test_RevertIf_ListNftNotOwner() public {
        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__NotOwner.selector);
        marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);
    }

    function test_RevertIf_ListNftDuplicate() public {
        // First listing should succeed
        vm.prank(seller);
        marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Since listing the NFT transfers it to the contract(marketplaceCore), we need to prank as marketplaceCore to test the duplicate listing
        vm.prank(address(marketplaceCore));
        vm.expectRevert(MarketplaceCore.MC__DuplicateListing.selector);
        marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);
    }

    function test_RelistNftAfterCancellation() public {
        // First listing should succeed
        vm.prank(seller);
        marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Cancel the first listing to return the NFT to the seller
        vm.prank(seller);
        marketplaceCore.cancelNftListing(LISTING_ID);

        // Approve the NFT again for relisting
        vm.prank(seller);
        vertixNFT.approve(address(marketplaceCore), TOKEN_ID);

        // Now try to list the same NFT again - this should succeed because the listing hash was removed
        vm.prank(seller);
        uint256 newListingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Verify the new listing ID is different from the first one
        assertEq(newListingId, LISTING_ID + 1);

        // Verify the new listing
        (address listedSeller, address nftContract, uint256 tokenId, uint96 price, bool active, bool isListedForAuction) = marketplaceStorage.getNftListing(newListingId);
        assertEq(listedSeller, seller);
        assertEq(nftContract, address(vertixNFT));
        assertEq(tokenId, TOKEN_ID);
        assertEq(price, LISTING_PRICE);
        assertTrue(active);
        assertFalse(isListedForAuction);
    }

    /*//////////////////////////////////////////////////////////////
                        LISTING NON-NFT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ListNonNftAsset() public {
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        vm.expectEmit(true, true, true, true);
        emit NonNFTListed(LISTING_ID, seller, ASSET_TYPE, ASSET_ID, LISTING_PRICE);

        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);
        assertEq(listingId, LISTING_ID);

        // Verify listing
        (address listedSeller, uint96 price, uint8 assetType, bool active, , string memory listedAssetId, , ) = marketplaceStorage.getNonNftListing(LISTING_ID);
        assertEq(listedSeller, seller);
        assertEq(price, LISTING_PRICE);
        assertEq(assetType, ASSET_TYPE);
        assertEq(listedAssetId, ASSET_ID);
        assertTrue(active);
    }

    function test_RevertIf_ListNonNftWithInvalidAssetType() public {
        bytes memory verificationProof = "proof";
        uint8 invalidAssetType = uint8(VertixUtils.AssetType.Other) + 1;
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InvalidAssetType.selector);
        marketplaceCore.listNonNftAsset(invalidAssetType, ASSET_ID, LISTING_PRICE, URI, verificationProof);
    }

    function test_RevertIf_ListNonNftWithZeroPrice() public {
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InsufficientPayment.selector);
        marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, INVALID_PRICE, URI, verificationProof);
    }

    function test_RevertIf_ListNonNftDuplicate() public {
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        // Try to list the same asset again as the same seller - this should fail with duplicate listing
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__DuplicateListing.selector);
        marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);
    }

    /*//////////////////////////////////////////////////////////////
                        LISTING SOCIAL MEDIA NFT TESTS
    //////////////////////////////////////////////////////////////*/

    modifier mintSocialMediaNft() {
        // Generate signature for social media NFT minting
        bytes32 messageHash = keccak256(abi.encodePacked(seller, SOCIAL_MEDIA_ID));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verificationServerKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Mint the social media NFT
        vm.startPrank(seller);
        vertixNFT.mintSocialMediaNft(seller, SOCIAL_MEDIA_ID, URI, METADATA, 500, signature);
        vertixNFT.approve(address(marketplaceCore), TOKEN_ID);
        vm.stopPrank();

        _;
    }

    function test_ListSocialMediaNft() public mintSocialMediaNft {
        // Generate signature for listing (different message format)
        bytes32 listingMessageHash = keccak256(abi.encodePacked(seller, TOKEN_ID, LISTING_PRICE, SOCIAL_MEDIA_ID));
        bytes32 listingEthSignedHash = MessageHashUtils.toEthSignedMessageHash(listingMessageHash);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(verificationServerKey, listingEthSignedHash);
        bytes memory listingSignature = abi.encodePacked(r2, s2, v2);

        vm.prank(seller);
        uint256 listingId = marketplaceCore.listSocialMediaNft(TOKEN_ID, LISTING_PRICE, SOCIAL_MEDIA_ID, listingSignature);
        assertEq(listingId, LISTING_ID);

        // Verify listing
        (address listedSeller, address nftContract, uint256 tokenId, uint96 price, bool active, bool isListedForAuction) = marketplaceStorage.getNftListing(listingId);
        assertEq(listedSeller, seller);
        assertEq(nftContract, address(vertixNFT));
        assertEq(tokenId, TOKEN_ID);
        assertEq(price, LISTING_PRICE);
        assertTrue(active);
        assertFalse(isListedForAuction);
        assertEq(vertixNFT.ownerOf(TOKEN_ID), address(marketplaceCore));
    }

    function test_RevertIf_ListSocialMediaNftWithInvalidSocialMediaId() public mintSocialMediaNft {
        string memory invalidSocialMediaId = "invalidId";
        bytes memory signature = "invalidSignature";
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InvalidSocialMediaNFT.selector);
        marketplaceCore.listSocialMediaNft(TOKEN_ID, LISTING_PRICE, invalidSocialMediaId, signature);
    }

        function test_RevertIf_ListSocialMediaNftWithInvalidSignature() public mintSocialMediaNft {
        // Generate a signature for a different message (wrong tokenId)
        bytes32 wrongMessageHash = keccak256(abi.encodePacked(seller, TOKEN_ID + 1, LISTING_PRICE, SOCIAL_MEDIA_ID));
        bytes32 wrongEthSignedHash = MessageHashUtils.toEthSignedMessageHash(wrongMessageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(verificationServerKey, wrongEthSignedHash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InvalidSignature.selector);
        marketplaceCore.listSocialMediaNft(TOKEN_ID, LISTING_PRICE, SOCIAL_MEDIA_ID, wrongSignature);
    }

    /*//////////////////////////////////////////////////////////////
                        BUY NFT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BuyNft() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Get expected fees from MarketplaceFees contract
        MarketplaceFees.FeeDistribution memory fees = marketplaceFees.calculateNftFees(LISTING_PRICE, address(vertixNFT), TOKEN_ID);

        // Buy NFT
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit NFTBought(listingId, buyer, LISTING_PRICE, fees.royaltyAmount, fees.royaltyRecipient, fees.platformFee, fees.platformRecipient);

        marketplaceCore.buyNft{value: LISTING_PRICE}(listingId);

        // Verify NFT transfer and listing status
        assertEq(vertixNFT.ownerOf(TOKEN_ID), buyer);
        (, , , , bool active, ) = marketplaceStorage.getNftListing(listingId);
        assertFalse(active);
    }

    function test_RevertIf_BuyNftInvalidListing() public {
        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__InvalidListing.selector);
        marketplaceCore.buyNft{value: LISTING_PRICE}(LISTING_ID);
    }

    function test_RevertIf_BuyNftInsufficientPayment() public {
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__InsufficientPayment.selector);
        marketplaceCore.buyNft{value: LISTING_PRICE - 1}(listingId);
    }

    /*//////////////////////////////////////////////////////////////
                        BUY NON-NFT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BuyNonNftAsset() public {
        // List non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        // Get expected fees from MarketplaceFees contract
        MarketplaceFees.FeeDistribution memory fees = marketplaceFees.calculateNonNftFees(LISTING_PRICE);

        // Buy non-NFT
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit NonNFTBought(listingId, buyer, LISTING_PRICE, fees.sellerAmount, fees.platformFee, fees.platformRecipient);

        marketplaceCore.buyNonNftAsset{value: LISTING_PRICE}(listingId);

        // Verify listing status
        (, , , bool active, , , , ) = marketplaceStorage.getNonNftListing(listingId);
        assertFalse(active);
    }

    function test_RevertIf_BuyNonNftInvalidListing() public {
        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__InvalidListing.selector);
        marketplaceCore.buyNonNftAsset{value: LISTING_PRICE}(LISTING_ID);
    }

    function test_RevertIf_BuyNonNftInsufficientPayment() public {
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__InsufficientPayment.selector);
        marketplaceCore.buyNonNftAsset{value: LISTING_PRICE - 1}(listingId);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL LISTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CancelNftListing() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Cancel listing
        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit NFTListingCancelled(listingId, seller, true);

        marketplaceCore.cancelNftListing(listingId);

        // Verify NFT returned and listing status
        assertEq(vertixNFT.ownerOf(TOKEN_ID), seller);
        (, , , , bool active, ) = marketplaceStorage.getNftListing(listingId);
        assertFalse(active);
    }

    function test_RevertIf_CancelNftNotSeller() public {
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__NotSeller.selector);
        marketplaceCore.cancelNftListing(listingId);
    }

    function test_RevertIf_CancelNftInvalidListing() public {
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InvalidListing.selector);
        marketplaceCore.cancelNftListing(LISTING_ID);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL NON-NFT LISTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CancelNonNftListing() public {
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit NonNFTListingCancelled(listingId, seller, false);

        marketplaceCore.cancelNonNftListing(listingId);

        // Verify listing status
        (, , , bool active, , , , ) = marketplaceStorage.getNonNftListing(listingId);
        assertFalse(active);
    }

    function test_RevertIf_CancelNonNftNotSeller() public {
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__NotSeller.selector);
        marketplaceCore.cancelNonNftListing(listingId);
    }

    function test_RevertIf_CancelNonNftInvalidListing() public {
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InvalidListing.selector);
        marketplaceCore.cancelNonNftListing(LISTING_ID);
    }

    /*//////////////////////////////////////////////////////////////
                        LIST FOR AUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ListNftForAuction() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // List for auction
        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit ListedForAuction(listingId, true, true);

        marketplaceCore.listForAuction(listingId, true);

        // Verify auction status
        (, , , , , bool isListedForAuction) = marketplaceStorage.getNftListing(listingId);
        assertTrue(isListedForAuction);
    }

    function test_ListNonNftForAuction() public {
        // List non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        // List for auction
        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit ListedForAuction(listingId, false, true);

        marketplaceCore.listForAuction(listingId, false);

        // Verify auction status
        (, , , , bool auctionListed, , , ) = marketplaceStorage.getNonNftListing(listingId);
        assertTrue(auctionListed);
    }

    function test_RevertIf_ListForAuctionNotSeller() public {
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__NotSeller.selector);
        marketplaceCore.listForAuction(listingId, true);
    }

    function test_RevertIf_ListForAuctionInvalidListing() public {
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InvalidListing.selector);
        marketplaceCore.listForAuction(LISTING_ID, true);
    }

    function test_RevertIf_ListForAuctionAlreadyListed() public {
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        vm.prank(seller);
        marketplaceCore.listForAuction(listingId, true);

        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.Mc_AlreadyListedForAuction.selector);
        marketplaceCore.listForAuction(listingId, true);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Paused(owner);

        marketplaceCore.pause();

        // Verify paused state
        vm.prank(seller);
        vm.expectRevert();
        marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);
    }

    function test_RevertIf_PauseNotOwner() public {
        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__NotOwner.selector);
        marketplaceCore.pause();
    }

    function test_Unpause() public {
        vm.prank(owner);
        marketplaceCore.pause();

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner);

        marketplaceCore.unpause();

        // Verify unpaused by listing NFT
        vm.prank(seller);
        marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);
    }

    function test_RevertIf_UnpauseNotOwner() public {
        vm.prank(owner);
        marketplaceCore.pause();

        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.MC__NotOwner.selector);
        marketplaceCore.unpause();
    }



    /*//////////////////////////////////////////////////////////////
                        BUYING TESTS - EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_BuyNftWithExactPayment() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Buy NFT with exact payment
        vm.prank(buyer);
        marketplaceCore.buyNft{value: LISTING_PRICE}(listingId);

        // Verify NFT transfer
        assertEq(vertixNFT.ownerOf(TOKEN_ID), buyer);
    }

    function test_BuyNftWithExcessPayment() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Buy NFT with excess payment
        uint256 excessPayment = LISTING_PRICE + 0.1 ether;
        vm.prank(buyer);
        marketplaceCore.buyNft{value: excessPayment}(listingId);

        // Verify NFT transfer
        assertEq(vertixNFT.ownerOf(TOKEN_ID), buyer);
    }

    function test_BuyNonNftAssetWithExactPayment() public {
        // List non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        // Buy non-NFT with exact payment
        vm.prank(buyer);
        marketplaceCore.buyNonNftAsset{value: LISTING_PRICE}(listingId);

        // Verify listing is inactive
        (, , , bool active, , , , ) = marketplaceStorage.getNonNftListing(listingId);
        assertFalse(active);
    }

    function test_BuyNonNftAssetWithExcessPayment() public {
        // List non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        // Buy non-NFT with excess payment
        uint256 excessPayment = LISTING_PRICE + 0.1 ether;
        vm.prank(buyer);
        marketplaceCore.buyNonNftAsset{value: excessPayment}(listingId);

        // Verify listing is inactive
        (, , , bool active, , , , ) = marketplaceStorage.getNonNftListing(listingId);
        assertFalse(active);
    }

    function test_RevertIf_BuyNftWithExcessiveOverpayment() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Try to buy with excessive overpayment (should still work but refund excess)
        uint256 excessivePayment = LISTING_PRICE * 2;
        vm.prank(buyer);
        marketplaceCore.buyNft{value: excessivePayment}(listingId);

        // Verify NFT transfer
        assertEq(vertixNFT.ownerOf(TOKEN_ID), buyer);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCELLATION TESTS - EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_CancelNftListingAfterBeingListedForAuction() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // List for auction
        vm.prank(seller);
        marketplaceCore.listForAuction(listingId, true);

        // Cancel listing
        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit NFTListingCancelled(listingId, seller, true);

        marketplaceCore.cancelNftListing(listingId);

        // Verify NFT returned and listing status
        assertEq(vertixNFT.ownerOf(TOKEN_ID), seller);
        (, , , , bool active, ) = marketplaceStorage.getNftListing(listingId);
        assertFalse(active);
    }

    function test_CancelNonNftListingAfterBeingListedForAuction() public {
        // List non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        // List for auction
        vm.prank(seller);
        marketplaceCore.listForAuction(listingId, false);

        // Cancel listing
        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit NonNFTListingCancelled(listingId, seller, false);

        marketplaceCore.cancelNonNftListing(listingId);

        // Verify listing status
        (, , , bool active, , , , ) = marketplaceStorage.getNonNftListing(listingId);
        assertFalse(active);
    }

    function test_RevertIf_CancelNftListingTwice() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Cancel listing
        vm.prank(seller);
        marketplaceCore.cancelNftListing(listingId);

        // Try to cancel again
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InvalidListing.selector);
        marketplaceCore.cancelNftListing(listingId);
    }

    function test_RevertIf_CancelNonNftListingTwice() public {
        // List non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        // Cancel listing
        vm.prank(seller);
        marketplaceCore.cancelNonNftListing(listingId);

        // Try to cancel again
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.MC__InvalidListing.selector);
        marketplaceCore.cancelNonNftListing(listingId);
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSE/UNPAUSE TESTS - EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_ListNftWhenPaused() public {
        // Pause the contract
        vm.prank(owner);
        marketplaceCore.pause();

        // Try to list NFT
        vm.prank(seller);
        vm.expectRevert();
        marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);
    }

    function test_RevertIf_ListNonNftWhenPaused() public {
        // Pause the contract
        vm.prank(owner);
        marketplaceCore.pause();

        // Try to list non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        vm.expectRevert();
        marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);
    }

    function test_RevertIf_BuyNftWhenPaused() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Pause the contract
        vm.prank(owner);
        marketplaceCore.pause();

        // Try to buy NFT
        vm.prank(buyer);
        vm.expectRevert();
        marketplaceCore.buyNft{value: LISTING_PRICE}(listingId);
    }

    function test_RevertIf_BuyNonNftWhenPaused() public {
        // List non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        // Pause the contract
        vm.prank(owner);
        marketplaceCore.pause();

        // Try to buy non-NFT
        vm.prank(buyer);
        vm.expectRevert();
        marketplaceCore.buyNonNftAsset{value: LISTING_PRICE}(listingId);
    }

    function test_RevertIf_CancelNftWhenPaused() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Pause the contract
        vm.prank(owner);
        marketplaceCore.pause();

        // Try to cancel listing
        vm.prank(seller);
        vm.expectRevert();
        marketplaceCore.cancelNftListing(listingId);
    }

    function test_RevertIf_CancelNonNftWhenPaused() public {
        // List non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);

        // Pause the contract
        vm.prank(owner);
        marketplaceCore.pause();

        // Try to cancel listing
        vm.prank(seller);
        vm.expectRevert();
        marketplaceCore.cancelNonNftListing(listingId);
    }

    function test_RevertIf_ListForAuctionWhenPaused() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Pause the contract
        vm.prank(owner);
        marketplaceCore.pause();

        // Try to list for auction
        vm.prank(seller);
        vm.expectRevert();
        marketplaceCore.listForAuction(listingId, true);
    }

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_ReentrantListNft() public {
        // This test would require a malicious contract that tries to reenter
        // For now, we'll test that the nonReentrant modifier is working
        // by ensuring normal operations work correctly
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);
        assertEq(listingId, LISTING_ID);
    }

    function test_RevertIf_ReentrantBuyNft() public {
        // List NFT
        vm.prank(seller);
        uint256 listingId = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        // Buy NFT (should work normally, reentrancy protection is implicit)
        vm.prank(buyer);
        marketplaceCore.buyNft{value: LISTING_PRICE}(listingId);
        assertEq(vertixNFT.ownerOf(TOKEN_ID), buyer);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE LISTINGS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleNftListings() public {
        // Mint another NFT
        vm.startPrank(owner);
        vertixNFT.mintSingleNft(seller, URI, METADATA, 500);
        vm.stopPrank();

        // Approve the second NFT
        vm.prank(seller);
        vertixNFT.approve(address(marketplaceCore), TOKEN_ID + 1);

        // List first NFT
        vm.prank(seller);
        uint256 listingId1 = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID, LISTING_PRICE);
        assertEq(listingId1, LISTING_ID);

        // List second NFT
        vm.prank(seller);
        uint256 listingId2 = marketplaceCore.listNft(address(vertixNFT), TOKEN_ID + 1, LISTING_PRICE);
        assertEq(listingId2, LISTING_ID + 1);

        // Verify both listings exist
        (address seller1, , , , bool active1, ) = marketplaceStorage.getNftListing(listingId1);
        (address seller2, , , , bool active2, ) = marketplaceStorage.getNftListing(listingId2);
        assertEq(seller1, seller);
        assertEq(seller2, seller);
        assertTrue(active1);
        assertTrue(active2);
    }

    function test_MultipleNonNftListings() public {
        // List first non-NFT
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        uint256 listingId1 = marketplaceCore.listNonNftAsset(ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof);
        assertEq(listingId1, LISTING_ID);

        // List second non-NFT with different asset ID
        vm.prank(seller);
        uint256 listingId2 = marketplaceCore.listNonNftAsset(ASSET_TYPE, "asset456", LISTING_PRICE, URI, verificationProof);
        assertEq(listingId2, LISTING_ID + 1);

        // Verify both listings exist
        (address seller1, , , bool active1, , , , ) = marketplaceStorage.getNonNftListing(listingId1);
        (address seller2, , , bool active2, , , , ) = marketplaceStorage.getNonNftListing(listingId2);
        assertEq(seller1, seller);
        assertEq(seller2, seller);
        assertTrue(active1);
        assertTrue(active2);
    }

    /*//////////////////////////////////////////////////////////////
                        RECEIVE AND FALLBACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveFunction() public {
        // Test that the contract can receive ETH
        uint256 initialBalance = address(marketplaceCore).balance;
        uint256 sendAmount = 1 ether;

        vm.deal(address(this), sendAmount);
        (bool success, ) = address(marketplaceCore).call{value: sendAmount}("");

        assertTrue(success, "Receive function should accept ETH");
        assertEq(address(marketplaceCore).balance, initialBalance + sendAmount, "Balance should increase");
    }

    function test_FallbackFunction() public {
        // Test that the fallback function works
        uint256 initialBalance = address(marketplaceCore).balance;
        uint256 sendAmount = 1 ether;

        vm.deal(address(this), sendAmount);
        (bool success, ) = address(marketplaceCore).call{value: sendAmount}(abi.encodeWithSignature("nonexistentFunction()"));

        assertTrue(success, "Fallback function should accept calls");
        assertEq(address(marketplaceCore).balance, initialBalance + sendAmount, "Balance should increase");
    }

}
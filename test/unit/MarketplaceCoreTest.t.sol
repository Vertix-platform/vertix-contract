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

}
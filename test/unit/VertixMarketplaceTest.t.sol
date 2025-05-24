// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {VertixMarketplace} from "../../src/VertixMarketplace.sol";
import {VertixNFT} from "../../src/VertixNFT.sol";
import {VertixGovernance} from "../../src/VertixGovernance.sol";
import {VertixEscrow} from "../../src/VertixEscrow.sol";
import {VertixUtils} from "../../src/libraries/VertixUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract VertixMarketplaceTest is Test {
    VertixMarketplace public marketplace;
    VertixNFT public nftContract;
    VertixGovernance public governance;
    VertixEscrow public escrow;

    address public owner = makeAddr("owner");
    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");
    address public feeRecipient = makeAddr("feeRecipient");
    address public verificationServer = makeAddr("verificationServer");

    uint256 public constant TOKEN_ID = 1;
    uint256 public constant PRICE = 1 ether;
    uint96 public constant ROYALTY_BPS = 500; // 5%
    string public constant TOKEN_URI = "https://example.com/token/1";
    bytes32 public constant METADATA_HASH = keccak256("metadata");

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

    function setUp() public {
        vm.startPrank(owner);

        VertixNFT nftImpl = new VertixNFT();
        VertixGovernance governanceImpl = new VertixGovernance();
        VertixEscrow escrowImpl = new VertixEscrow();
        VertixMarketplace marketplaceImpl = new VertixMarketplace();

        bytes memory nftInitData = abi.encodeWithSelector(VertixNFT.initialize.selector, verificationServer);
        ERC1967Proxy nftProxy = new ERC1967Proxy(address(nftImpl), nftInitData);
        nftContract = VertixNFT(address(nftProxy));

        bytes memory escrowInitData = abi.encodeWithSelector(VertixEscrow.initialize.selector);
        ERC1967Proxy escrowProxy = new ERC1967Proxy(address(escrowImpl), escrowInitData);
        escrow = VertixEscrow(payable(address(escrowProxy)));

        bytes memory governanceInitData = abi.encodeWithSelector(
            VertixGovernance.initialize.selector,
            address(0), // marketplace will be set later
            address(escrow),
            feeRecipient
        );
        ERC1967Proxy governanceProxy = new ERC1967Proxy(address(governanceImpl), governanceInitData);
        governance = VertixGovernance(address(governanceProxy));

        bytes memory marketplaceInitData = abi.encodeWithSelector(
            VertixMarketplace.initialize.selector, address(nftContract), address(governance), address(escrow)
        );
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(address(marketplaceImpl), marketplaceInitData);
        marketplace = VertixMarketplace(address(marketplaceProxy));

        // Set marketplace address in governance
        governance.setMarketplace(address(marketplace));

        vm.stopPrank();

        // Setup test data
        vm.deal(buyer, 10 ether);
        vm.deal(seller, 1 ether);

        // Mint NFT to seller
        vm.prank(seller);
        nftContract.mintSingleNFT(seller, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
    }

    /*//////////////////////////////////////////////////////////////
                           NFT LISTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ListNFT_Success() public {
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);

        vm.expectEmit(true, true, false, true);
        emit NFTListed(1, seller, address(nftContract), TOKEN_ID, PRICE);

        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        vm.stopPrank();

        // Verify listing
        VertixMarketplace.NFTListing memory listing = marketplace.getNFTListing(1);
        assertEq(listing.seller, seller);
        assertEq(listing.nftContract, address(nftContract));
        assertEq(listing.tokenId, TOKEN_ID);
        assertEq(listing.price, PRICE);
        assertTrue(listing.active);

        // Verify NFT transferred to marketplace
        assertEq(nftContract.ownerOf(TOKEN_ID), address(marketplace));
    }

    function test_ListNFT_RevertIf_InvalidPrice() public {
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);

        vm.expectRevert(VertixUtils.VertixUtils__InvalidPrice.selector);
        marketplace.listNFT(address(nftContract), TOKEN_ID, 0);
        vm.stopPrank();
    }

    function test_ListNFT_RevertIf_InvalidNFTContract() public {
        address fakeNFT = makeAddr("fakeNFT");

        vm.prank(seller);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__InvalidNFTContract.selector);
        marketplace.listNFT(fakeNFT, TOKEN_ID, PRICE);
    }

    function test_ListNFT_RevertIf_NotOwner() public {
        vm.prank(buyer);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__NotOwner.selector);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
    }

    function test_ListNFT_RevertIf_DuplicateListing() public {
        vm.startPrank(seller);

        // List first NFT (tokenId=1)
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);

        // Attempt to list same token again - should fail for duplicate
        vm.expectRevert(VertixMarketplace.VertixMarketplace__DuplicateListing.selector);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         NON-NFT LISTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ListNonNFTAsset_Success() public {
        string memory assetId = "twitter.com/user123";
        string memory metadata = "Social media profile";
        bytes memory verificationProof = "proof123";

        vm.expectEmit(true, true, false, true);
        emit NonNFTListed(1, seller, VertixUtils.AssetType.SocialMedia, assetId, PRICE);

        vm.prank(seller);
        marketplace.listNonNFTAsset(
            uint8(VertixUtils.AssetType.SocialMedia), assetId, PRICE, metadata, verificationProof
        );

        // Verify listing
        VertixMarketplace.NonNFTListing memory listing = marketplace.getNonNFTListing(1);
        assertEq(listing.seller, seller);
        assertEq(listing.assetId, assetId);
        assertEq(listing.price, PRICE);
        assertEq(listing.metadata, metadata);
        assertEq(uint8(listing.assetType), uint8(VertixUtils.AssetType.SocialMedia));
        assertTrue(listing.active);
    }

    function test_ListNonNFTAsset_RevertIf_InvalidPrice() public {
        vm.prank(seller);
        vm.expectRevert(VertixUtils.VertixUtils__InvalidPrice.selector);
        marketplace.listNonNFTAsset(uint8(VertixUtils.AssetType.SocialMedia), "assetId", 0, "metadata", "proof");
    }

    function test_ListNonNFTAsset_RevertIf_InvalidAssetType() public {
        vm.prank(seller);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__InvalidAssetType.selector);
        marketplace.listNonNFTAsset(
            10, // Invalid asset type
            "assetId",
            PRICE,
            "metadata",
            "proof"
        );
    }

    function test_ListNonNFTAsset_RevertIf_DuplicateListing() public {
        string memory assetId = "twitter.com/user123";

        vm.startPrank(seller);
        marketplace.listNonNFTAsset(uint8(VertixUtils.AssetType.SocialMedia), assetId, PRICE, "metadata", "proof");

        vm.expectRevert(VertixMarketplace.VertixMarketplace__DuplicateListing.selector);
        marketplace.listNonNFTAsset(uint8(VertixUtils.AssetType.SocialMedia), assetId, PRICE, "metadata2", "proof2");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           NFT BUYING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BuyNFT_Success() public {
        // List NFT
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        vm.stopPrank();

        // Calculate expected fees
        uint256 royaltyAmount = (PRICE * ROYALTY_BPS) / 10000; // 5%
        (uint16 platformFeeBps,) = governance.getFeeConfig();
        uint256 platformFee = (PRICE * platformFeeBps) / 10000; // 1%

        vm.expectEmit(true, true, false, true);
        emit NFTBought(1, buyer, PRICE, royaltyAmount, seller, platformFee, feeRecipient);

        vm.prank(buyer);
        marketplace.buyNFT{value: PRICE}(1);

        // Verify NFT transferred to buyer
        assertEq(nftContract.ownerOf(TOKEN_ID), buyer);

        // Verify listing is inactive
        VertixMarketplace.NFTListing memory listing = marketplace.getNFTListing(1);
        assertFalse(listing.active);
    }

    function test_BuyNFT_Success_WithExcessPayment() public {
        // List NFT
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        vm.stopPrank();

        uint256 excessPayment = PRICE + 0.5 ether;
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        marketplace.buyNFT{value: excessPayment}(1);

        // Verify excess was refunded
        uint256 buyerBalanceAfter = buyer.balance;
        assertEq(buyerBalanceBefore - buyerBalanceAfter, PRICE);

        // Verify NFT transferred
        assertEq(nftContract.ownerOf(TOKEN_ID), buyer);
    }

    function test_BuyNFT_RevertIf_InvalidListing() public {
        vm.prank(buyer);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__InvalidListing.selector);
        marketplace.buyNFT{value: PRICE}(999);
    }

    function test_BuyNFT_RevertIf_InsufficientPayment() public {
        // List NFT
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__InsufficientPayment.selector);
        marketplace.buyNFT{value: PRICE - 1}(1);
    }

    /*//////////////////////////////////////////////////////////////
                        NON-NFT BUYING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BuyNonNFTAsset_Success() public {
        // List non-NFT asset
        string memory assetId = "domain.com";
        vm.prank(seller);
        marketplace.listNonNFTAsset(
            uint8(VertixUtils.AssetType.Domain), assetId, PRICE, "Premium domain", "verification_proof"
        );

        (uint16 platformFeeBps,) = governance.getFeeConfig();
        uint256 platformFee = (PRICE * platformFeeBps) / 10000;

        vm.expectEmit(true, true, false, true);
        emit NonNFTBought(1, buyer, PRICE, platformFee, feeRecipient);

        vm.prank(buyer);
        marketplace.buyNonNFTAsset{value: PRICE}(1);

        // Verify listing is inactive
        VertixMarketplace.NonNFTListing memory listing = marketplace.getNonNFTListing(1);
        assertFalse(listing.active);
    }

    function test_BuyNonNFTAsset_RevertIf_InsufficientPayment() public {
        // List non-NFT asset
        vm.prank(seller);
        marketplace.listNonNFTAsset(uint8(VertixUtils.AssetType.Domain), "domain.com", PRICE, "metadata", "proof");

        vm.prank(buyer);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__InsufficientPayment.selector);
        marketplace.buyNonNFTAsset{value: PRICE - 1}(1);
    }

    /*//////////////////////////////////////////////////////////////
                         LISTING CANCELLATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CancelNFTListing_Success() public {
        // List NFT
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);

        vm.expectEmit(true, true, false, false);
        emit NFTListingCancelled(1, seller);

        marketplace.cancelNFTListing(1);
        vm.stopPrank();

        // Verify listing is inactive
        VertixMarketplace.NFTListing memory listing = marketplace.getNFTListing(1);
        assertFalse(listing.active);

        // Verify NFT returned to seller
        assertEq(nftContract.ownerOf(TOKEN_ID), seller);
    }

    function test_CancelNFTListing_RevertIf_NotSeller() public {
        // List NFT
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__NotSeller.selector);
        marketplace.cancelNFTListing(1);
    }

    function test_CancelNonNFTListing_Success() public {
        // List non-NFT asset
        vm.prank(seller);
        marketplace.listNonNFTAsset(uint8(VertixUtils.AssetType.Domain), "domain.com", PRICE, "metadata", "proof");

        vm.expectEmit(true, true, false, false);
        emit NonNFTListingCancelled(1, seller);

        vm.prank(seller);
        marketplace.cancelNonNFTListing(1);

        // Verify listing is inactive
        VertixMarketplace.NonNFTListing memory listing = marketplace.getNonNFTListing(1);
        assertFalse(listing.active);
    }

    function test_CancelNonNFTListing_RevertIf_NotSeller() public {
        // List non-NFT asset
        vm.prank(seller);
        marketplace.listNonNFTAsset(uint8(VertixUtils.AssetType.Domain), "domain.com", PRICE, "metadata", "proof");

        vm.prank(buyer);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__NotSeller.selector);
        marketplace.cancelNonNFTListing(1);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetTotalListings() public {
        assertEq(marketplace.getTotalListings(), 1); // Starts at 1

        // List NFT
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        vm.stopPrank();

        assertEq(marketplace.getTotalListings(), 2);

        // List non-NFT
        vm.prank(seller);
        marketplace.listNonNFTAsset(uint8(VertixUtils.AssetType.Domain), "domain.com", PRICE, "metadata", "proof");

        assertEq(marketplace.getTotalListings(), 3);
    }

    // function test_GetListingsByCollection() public {
    //     // Create collection and mint NFTs
    //     vm.startPrank(seller);
    //     uint256 collectionId = nftContract.createCollection("Test Collection", "TC", "image.jpg", 5);

    //     // Mint NFTs to collection
    //     uint256 tokenId2 = 2;
    //     uint256 tokenId3 = 3;
    //     nftContract.mintToCollection(seller, collectionId, "uri2", METADATA_HASH, ROYALTY_BPS);
    //     nftContract.mintToCollection(seller, collectionId, "uri3", METADATA_HASH, ROYALTY_BPS);

    //     // List NFTs
    //     nftContract.approve(address(marketplace), tokenId2);
    //     nftContract.approve(address(marketplace), tokenId3);
    //     marketplace.listNFT(address(nftContract), tokenId2, PRICE);
    //     marketplace.listNFT(address(nftContract), tokenId3, PRICE * 2);
    //     vm.stopPrank();

    //     uint256[] memory listings = marketplace.getListingsByCollection(collectionId);
    //     assertEq(listings.length, 2);
    // }

    // function test_GetListingsByPriceRange() public {
    //     // List multiple NFTs with different prices
    //     vm.startPrank(seller);

    //     // Mint additional NFTs
    //     uint256 tokenId2 = 2;
    //     uint256 tokenId3 = 3;
    //     nftContract.mintSingleNFT(seller, "uri2", METADATA_HASH, ROYALTY_BPS);
    //     nftContract.mintSingleNFT(seller, "uri3", METADATA_HASH, ROYALTY_BPS);

    //     // List with different prices
    //     nftContract.approve(address(marketplace), TOKEN_ID);
    //     nftContract.approve(address(marketplace), tokenId2);
    //     nftContract.approve(address(marketplace), tokenId3);

    //     marketplace.listNFT(address(nftContract), TOKEN_ID, 1 ether);
    //     marketplace.listNFT(address(nftContract), tokenId2, 2 ether);
    //     marketplace.listNFT(address(nftContract), tokenId3, 5 ether);
    //     vm.stopPrank();

    //     uint256[] memory listings = marketplace.getListingsByPriceRange(1 ether, 3 ether);
    //     assertEq(listings.length, 2);
    // }

    // function test_GetListingsByAssetType() public {
    //     // List different asset types
    //     vm.startPrank(seller);
    //     marketplace.listNonNFTAsset(uint8(VertixUtils.AssetType.Domain), "domain1.com", PRICE, "metadata1", "proof1");
    //     marketplace.listNonNFTAsset(uint8(VertixUtils.AssetType.Domain), "domain2.com", PRICE, "metadata2", "proof2");
    //     marketplace.listNonNFTAsset(
    //         uint8(VertixUtils.AssetType.SocialMedia), "twitter.com/user", PRICE, "metadata3", "proof3"
    //     );
    //     vm.stopPrank();

    //     uint256[] memory domainListings = marketplace.getListingsByAssetType(VertixUtils.AssetType.Domain);
    //     assertEq(domainListings.length, 2);

    //     uint256[] memory socialListings = marketplace.getListingsByAssetType(VertixUtils.AssetType.SocialMedia);
    //     assertEq(socialListings.length, 1);
    // }

    function test_GetPurchaseDetails() public {
        // List NFT
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        vm.stopPrank();

        (
            uint256 price,
            uint256 royaltyAmount,
            address royaltyRecipient,
            uint256 platformFee,
            address feeRecipient_,
            uint256 sellerProceeds
        ) = marketplace.getPurchaseDetails(1);

        assertEq(price, PRICE);
        assertEq(royaltyAmount, (PRICE * ROYALTY_BPS) / 10000);
        assertEq(royaltyRecipient, seller);
        assertEq(platformFee, (PRICE * 100) / 10000); // 1% default fee
        assertEq(feeRecipient_, feeRecipient);
        assertEq(sellerProceeds, PRICE - royaltyAmount - platformFee);
    }

    function test_IsListedForAuction_ReturnsFalse_WhenNotListed() public view {
        assertFalse(marketplace.isListedForAuction(TOKEN_ID));
    }

    function test_GetAuctionIdForToken_ReturnsZero_WhenNotListed() public view {
        assertEq(marketplace.getAuctionIdForToken(TOKEN_ID), 0);
    }

    function test_GetTokenIdForAuction_ReturnsZero_WhenInvalidAuction() public view {
        assertEq(marketplace.getTokenIdForAuction(999), 0);
    }

    function test_GetSingleBidForAuction_EmptyBids() public {
        // This will revert with array bounds error for non-existent auction
        vm.expectRevert();
        marketplace.getSingleBidForAuction(999, 0);
    }


    function test_GetBidCountForAuction_ReturnsZero() public view {
        assertEq(marketplace.getBidCountForAuction(999), 0);
    }

    function test_GetAuctionDetails_EmptyStruct() public view {
        VertixMarketplace.AuctionDetails memory details = marketplace.getAuctionDetails(999);
        assertFalse(details.active);
        assertEq(details.seller, address(0));
        assertEq(details.highestBidder, address(0));
        assertEq(details.highestBid, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause_Success() public {
        vm.prank(owner);
        marketplace.pause();

        // Try to list NFT while paused
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        vm.expectRevert();
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        vm.stopPrank();
    }

    function test_Unpause_Success() public {
        vm.startPrank(owner);
        marketplace.pause();
        marketplace.unpause();
        vm.stopPrank();

        // Should be able to list now
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        vm.stopPrank();

        VertixMarketplace.NFTListing memory listing = marketplace.getNFTListing(1);
        assertTrue(listing.active);
    }

    /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BuyInactiveListing_Reverts() public {
        // List and then cancel
        vm.startPrank(seller);
        nftContract.approve(address(marketplace), TOKEN_ID);
        marketplace.listNFT(address(nftContract), TOKEN_ID, PRICE);
        marketplace.cancelNFTListing(1);
        vm.stopPrank();

        // Try to buy cancelled listing
        vm.prank(buyer);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__InvalidListing.selector);
        marketplace.buyNFT{value: PRICE}(1);
    }

    function test_MultipleListingsAndPurchases() public {
        // Create multiple tokens and listings
        vm.startPrank(seller);
        uint256 tokenId2 = 2;
        uint256 tokenId3 = 3;
        nftContract.mintSingleNFT(seller, "uri2", METADATA_HASH, ROYALTY_BPS);
        nftContract.mintSingleNFT(seller, "uri3", METADATA_HASH, ROYALTY_BPS);

        // List all tokens
        nftContract.approve(address(marketplace), TOKEN_ID);
        nftContract.approve(address(marketplace), tokenId2);
        nftContract.approve(address(marketplace), tokenId3);

        marketplace.listNFT(address(nftContract), TOKEN_ID, 1 ether);
        marketplace.listNFT(address(nftContract), tokenId2, 2 ether);
        marketplace.listNFT(address(nftContract), tokenId3, 3 ether);
        vm.stopPrank();

        // Buy middle listing
        vm.prank(buyer);
        marketplace.buyNFT{value: 2 ether}(2);

        // Verify correct token was transferred
        assertEq(nftContract.ownerOf(tokenId2), buyer);
        assertEq(nftContract.ownerOf(TOKEN_ID), address(marketplace)); // Still listed
        assertEq(nftContract.ownerOf(tokenId3), address(marketplace)); // Still listed

        // Verify other listings still active
        assertTrue(marketplace.getNFTListing(1).active);
        assertFalse(marketplace.getNFTListing(2).active);
        assertTrue(marketplace.getNFTListing(3).active);
    }
}
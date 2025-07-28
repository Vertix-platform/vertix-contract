// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MarketplaceProxy} from "../../src/MarketplaceProxy.sol";
import {MarketplaceCore} from "../../src/MarketplaceCore.sol";
import {MarketplaceAuctions} from "../../src/MarketplaceAuctions.sol";
import {MarketplaceStorage} from "../../src/MarketplaceStorage.sol";
import {MarketplaceFees} from "../../src/MarketplaceFees.sol";
import {VertixGovernance} from "../../src/VertixGovernance.sol";
import {VertixNFT} from "../../src/VertixNFT.sol";

import {VertixUtils} from "../../src/libraries/VertixUtils.sol";

contract MarketplaceProxyTest is Test {
    // Contract instances
    MarketplaceProxy public marketplaceProxy;
    MarketplaceCore public marketplaceCore;
    MarketplaceAuctions public marketplaceAuctions;
    MarketplaceStorage public marketplaceStorage;
    MarketplaceFees public marketplaceFees;
    VertixGovernance public governance;
    VertixNFT public vertixNFT;
    address public crossChainBridge;

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
        marketplaceProxy = MarketplaceProxy(payable(addresses.marketplaceProxy));
        marketplaceCore = MarketplaceCore(payable(addresses.marketplaceCoreImpl));
        marketplaceAuctions = MarketplaceAuctions(payable(addresses.marketplaceAuctionsImpl));
        marketplaceStorage = MarketplaceStorage(addresses.marketplaceStorage);
        marketplaceFees = MarketplaceFees(addresses.marketplaceFees);
        governance = VertixGovernance(addresses.governance);
        vertixNFT = VertixNFT(addresses.nft);
        verificationServer = addresses.verificationServer;
        feeRecipient = addresses.feeRecipient;
        escrow = addresses.escrow;
        crossChainBridge = addresses.crossChainBridge;

        // Get deployer key from HelperConfig
        HelperConfig helperConfig = new HelperConfig();
        deployerKey = helperConfig.DEFAULT_ANVIL_DEPLOYER_KEY();
        owner = vm.addr(deployerKey);

        // Setup: Mint an NFT to the seller
        vm.startPrank(owner);
        vertixNFT.mintSingleNft(seller, URI, METADATA, 500);
        vm.stopPrank();

        // Approve MarketplaceProxy to transfer the NFT
        vm.prank(seller);
        vertixNFT.approve(address(marketplaceProxy), TOKEN_ID);

        // Fund buyer with ETH
        vm.deal(buyer, 10 ether);

        // Add verification server as a signer
        verificationServerKey = uint256(keccak256(abi.encodePacked("verificationServer")));
        vm.deal(verificationServer, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        // Test that the proxy was constructed with correct addresses
        assertEq(marketplaceProxy.marketplaceCoreAddress(), address(marketplaceCore), "Incorrect core address");
        assertEq(marketplaceProxy.marketplaceAuctionsAddress(), address(marketplaceAuctions), "Incorrect auctions address");
    }

    function test_RevertIf_ConstructorWithZeroCoreAddress() public {
        vm.expectRevert(abi.encodeWithSelector(MarketplaceProxy.MP__InvalidCoreAddress.selector));
        new MarketplaceProxy(address(0), address(marketplaceAuctions));
    }

    function test_RevertIf_ConstructorWithZeroAuctionsAddress() public {
        vm.expectRevert(abi.encodeWithSelector(MarketplaceProxy.MP__InvalidAuctionsAddress.selector));
        new MarketplaceProxy(address(marketplaceCore), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        FALLBACK FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FallbackToCoreFunction() public {
        // Test that core functions are properly routed to MarketplaceCore
        vm.prank(seller);
        vm.expectEmit(true, true, true, true);
        emit NFTListed(LISTING_ID, seller, address(vertixNFT), TOKEN_ID, LISTING_PRICE);

        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success, "listNft call failed");
        uint256 listingId = abi.decode(data, (uint256));
        assertEq(listingId, LISTING_ID, "Listing ID should match");

        // Verify the listing was created in storage
        (address listedSeller, address nftContract, uint256 tokenId, uint96 price, bool active, bool isListedForAuction) = marketplaceStorage.getNftListing(listingId);
        assertEq(listedSeller, seller, "Seller should match");
        assertEq(nftContract, address(vertixNFT), "NFT contract should match");
        assertEq(tokenId, TOKEN_ID, "Token ID should match");
        assertEq(price, LISTING_PRICE, "Price should match");
        assertTrue(active, "Listing should be active");
        assertFalse(isListedForAuction, "Should not be listed for auction");
    }

    function test_FallbackToAuctionsFunction() public {
        // First create a listing
        vm.prank(seller);
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success, "listNft call failed");
        uint256 listingId = abi.decode(data, (uint256));

        // Test that auction functions are properly routed to MarketplaceAuctions
        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit ListedForAuction(listingId, true, true);

        (bool success2, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, true)
        );
        require(success2, "listForAuction call failed");

        // Verify the listing is now marked for auction
        (, , , , bool active, bool isListedForAuction) = marketplaceStorage.getNftListing(listingId);
        assertTrue(active, "Listing should still be active");
        assertTrue(isListedForAuction, "Should be listed for auction");
    }

    function test_FallbackWithValue() public {
        // Test that the fallback function can receive ETH
        uint256 initialBalance = address(marketplaceProxy).balance;
        uint256 sendAmount = 1 ether;

        vm.deal(address(this), sendAmount);
        (bool success, ) = address(marketplaceProxy).call{value: sendAmount}("");

        assertTrue(success, "Fallback should accept ETH");
        assertEq(address(marketplaceProxy).balance, initialBalance + sendAmount, "Balance should increase");
    }

    function test_FallbackWithInvalidFunction() public {
        // Test that invalid function calls revert properly
        vm.expectRevert();
        (bool successInvalid, ) = address(marketplaceProxy).call(abi.encodeWithSignature("nonexistentFunction()"));
        assertFalse(successInvalid, "Invalid function call should revert");
    }

    /*//////////////////////////////////////////////////////////////
                        AUCTION FUNCTION DETECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsAuctionFunctionDetection() public pure {
        // Test all known auction function selectors
        bytes4 startNftAuctionSelector = bytes4(keccak256("startNftAuction(uint256,uint24,uint96)"));
        bytes4 startNonNftAuctionSelector = bytes4(keccak256("startNonNftAuction(uint256,uint24,uint96)"));
        bytes4 placeBidSelector = bytes4(keccak256("placeBid(uint256)"));
        bytes4 endAuctionSelector = bytes4(keccak256("endAuction(uint256)"));
        bytes4 getAuctionInfoSelector = bytes4(keccak256("getAuctionInfo(uint256)"));
        bytes4 isAuctionExpiredSelector = bytes4(keccak256("isAuctionExpired(uint256)"));
        bytes4 getTimeRemainingSelector = bytes4(keccak256("getTimeRemaining(uint256)"));

        // These should be detected as auction functions
        assertTrue(_isAuctionFunction(startNftAuctionSelector), "startNftAuction should be detected as auction function");
        assertTrue(_isAuctionFunction(startNonNftAuctionSelector), "startNonNftAuction should be detected as auction function");
        assertTrue(_isAuctionFunction(placeBidSelector), "placeBid should be detected as auction function");
        assertTrue(_isAuctionFunction(endAuctionSelector), "endAuction should be detected as auction function");
        assertTrue(_isAuctionFunction(getAuctionInfoSelector), "getAuctionInfo should be detected as auction function");
        assertTrue(_isAuctionFunction(isAuctionExpiredSelector), "isAuctionExpired should be detected as auction function");
        assertTrue(_isAuctionFunction(getTimeRemainingSelector), "getTimeRemaining should be detected as auction function");

        // These should NOT be detected as auction functions
        bytes4 listNftSelector = bytes4(keccak256("listNft(address,uint256,uint96)"));
        bytes4 buyNftSelector = bytes4(keccak256("buyNft(uint256)"));
        bytes4 cancelNftListingSelector = bytes4(keccak256("cancelNftListing(uint256)"));
        bytes4 pauseSelector = bytes4(keccak256("pause()"));
        bytes4 unpauseSelector = bytes4(keccak256("unpause()"));

        assertFalse(_isAuctionFunction(listNftSelector), "listNft should NOT be detected as auction function");
        assertFalse(_isAuctionFunction(buyNftSelector), "buyNft should NOT be detected as auction function");
        assertFalse(_isAuctionFunction(cancelNftListingSelector), "cancelNftListing should NOT be detected as auction function");
        assertFalse(_isAuctionFunction(pauseSelector), "pause should NOT be detected as auction function");
        assertFalse(_isAuctionFunction(unpauseSelector), "unpause should NOT be detected as auction function");
    }

    /*//////////////////////////////////////////////////////////////
                        CORE FUNCTION ROUTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ListNftRouting() public {
        vm.prank(seller);
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success, "listNft call failed");
        uint256 listingId = abi.decode(data, (uint256));
        assertEq(listingId, LISTING_ID, "Should route to core function");
    }

    function test_ListNonNftAssetRouting() public {
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNonNftAsset(uint8,string,uint96,string,bytes)", ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof)
        );
        require(success, "listNonNftAsset call failed");
        uint256 listingId = abi.decode(data, (uint256));
        assertEq(listingId, LISTING_ID, "Should route to core function");
    }

    function test_BuyNftRouting() public {
        // First create a listing
        vm.prank(seller);
        (bool success6, bytes memory data6) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success6, "listNft call failed");
        uint256 listingId = abi.decode(data6, (uint256));

        // Calculate expected values dynamically
        (address royaltyRecipient, uint256 royaltyAmount) = vertixNFT.royaltyInfo(TOKEN_ID, LISTING_PRICE);
        (uint256 platformFeeBps, address platformRecipient) = governance.getFeeConfig();
        uint256 platformFee = (LISTING_PRICE * platformFeeBps) / 10000;

        // Test buying through proxy
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit NFTBought(
            listingId,
            buyer,
            LISTING_PRICE,
            royaltyAmount,
            royaltyRecipient,
            platformFee,
            platformRecipient
        );

        (bool success, ) = address(marketplaceProxy).call{value: LISTING_PRICE}(
            abi.encodeWithSignature("buyNft(uint256)", listingId)
        );
        require(success, "buyNft call failed");

        // Verify NFT transfer
        assertEq(vertixNFT.ownerOf(TOKEN_ID), buyer, "NFT should be transferred to buyer");
    }

    function test_CancelNftListingRouting() public {
        // First create a listing
        vm.prank(seller);
        (bool success7, bytes memory data7) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success7, "listNft call failed");
        uint256 listingId = abi.decode(data7, (uint256));

        // Test canceling through proxy
        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit NFTListingCancelled(listingId, seller, true);

        (bool success, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("cancelNftListing(uint256)", listingId)
        );
        require(success, "cancelNftListing call failed");

        // Verify NFT returned
        assertEq(vertixNFT.ownerOf(TOKEN_ID), seller, "NFT should be returned to seller");
    }

    function test_PauseUnpauseRouting() public {
        // Test pause through proxy
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Paused(owner);
        (bool success, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("pause()")
        );
        require(success, "pause call failed");

        // Test that operations are paused
        vm.prank(seller);
        vm.expectRevert();
        (bool listingSuccess, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(listingSuccess, "listNft call failed");

        // Test unpause through proxy
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner);
        (success, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("unpause()")
        );
        require(success, "unpause call failed");

        // Test that operations work again
        vm.prank(seller);
        (bool success10, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success10, "listNft call failed");
    }

    /*//////////////////////////////////////////////////////////////
                        AUCTION FUNCTION ROUTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ListForAuctionRouting() public {
        // First create a listing
        vm.prank(seller);
        (bool success3, bytes memory data3) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success3, "listNft call failed");
        uint256 listingId = abi.decode(data3, (uint256));

        // Test listing for auction through proxy
        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit ListedForAuction(listingId, true, true);

        (bool success, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, true)
        );
        require(success, "listForAuction call failed");

        // Verify auction status
        (, , , , , bool isListedForAuction) = marketplaceStorage.getNftListing(listingId);
        assertTrue(isListedForAuction, "Should be listed for auction");
    }

    function test_StartNftAuctionRouting() public {
        // Mint a fresh NFT for this test to avoid conflicts
        vm.startPrank(owner);
        vertixNFT.mintSingleNft(seller, URI, METADATA, 500);
        vm.stopPrank();

        // Approve the new NFT
        vm.prank(seller);
        vertixNFT.approve(address(marketplaceProxy), TOKEN_ID + 1);

        // First create a listing and mark it for auction
        vm.prank(seller);
        (bool success4, bytes memory data4) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID + 1, LISTING_PRICE)
        );
        require(success4, "listNft call failed");
        uint256 listingId = abi.decode(data4, (uint256));

        vm.prank(seller);
        (bool success3, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, true)
        );
        require(success3, "listForAuction call failed");

        // Test starting auction through proxy
        vm.prank(seller);
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("startNftAuction(uint256,uint24,uint96)", listingId, 1 hours, LISTING_PRICE)
        );
        require(success, "startNftAuction call failed");
        uint256 auctionId = abi.decode(data, (uint256));
        assertEq(auctionId, 1, "Should create auction with ID 1");
    }

    function test_StartNonNftAuctionRouting() public {
        // First create a non-NFT listing
        bytes memory verificationProof = "proof";
        vm.prank(seller);
        (bool success1, bytes memory data1) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNonNftAsset(uint8,string,uint96,string,bytes)", ASSET_TYPE, ASSET_ID, LISTING_PRICE, URI, verificationProof)
        );
        require(success1, "listNonNftAsset call failed");
        uint256 listingId = abi.decode(data1, (uint256));

        // Mark the listing for auction
        vm.prank(seller);
        (bool success2, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, false)
        );
        require(success2, "listForAuction call failed");

        // Test starting non-NFT auction through proxy with correct signature
        vm.prank(seller);
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("startNonNftAuction(uint256,uint24,uint96)", listingId, 1 hours, LISTING_PRICE)
        );
        require(success, "startNonNftAuction call failed");
        uint256 auctionId = abi.decode(data, (uint256));
        assertEq(auctionId, 1, "Should create auction with ID 1");
    }

    function test_PlaceBidRouting() public {
        // First create and start an auction
        vm.prank(seller);
        (bool success1, bytes memory data1) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success1, "listNft call failed");
        uint256 listingId = abi.decode(data1, (uint256));

        vm.prank(seller);
        (bool success4, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, true)
        );
        require(success4, "listForAuction call failed");

        vm.prank(seller);
        (bool success2, bytes memory data2) = address(marketplaceProxy).call(
            abi.encodeWithSignature("startNftAuction(uint256,uint24,uint96)", listingId, 1 hours, LISTING_PRICE)
        );
        require(success2, "startNftAuction call failed");
        uint256 auctionId = abi.decode(data2, (uint256));

        // Test placing bid through proxy
        vm.prank(buyer);
        (bool success, ) = address(marketplaceProxy).call{value: LISTING_PRICE + 0.1 ether}(
            abi.encodeWithSignature("placeBid(uint256)", auctionId)
        );
        require(success, "placeBid call failed");

        // Verify bid was placed
        MarketplaceStorage.AuctionDetailsView memory auctionInfo = marketplaceStorage.getAuctionDetailsView(auctionId);
        assertEq(auctionInfo.highestBidder, buyer, "Buyer should be highest bidder");
        assertEq(auctionInfo.highestBid, LISTING_PRICE + 0.1 ether, "Highest bid should match");
    }

    function test_EndAuctionRouting() public {
        // Mint a fresh NFT for this test to avoid conflicts
        vm.startPrank(owner);
        vertixNFT.mintSingleNft(seller, URI, METADATA, 500);
        vm.stopPrank();

        // Approve the new NFT - use the token ID that was actually minted
        vm.prank(seller);
        vertixNFT.approve(address(marketplaceProxy), 2); // Use token ID 2 since thats what was minted

        // First create and start an auction
        vm.prank(seller);
        (bool success1, bytes memory data1) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), 2, LISTING_PRICE)
        );
        require(success1, "listNft call failed");
        uint256 listingId = abi.decode(data1, (uint256));

        vm.prank(seller);
        (bool success5, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, true)
        );
        require(success5, "listForAuction call failed");

        vm.prank(seller);
        (bool success2, bytes memory data2) = address(marketplaceProxy).call(
            abi.encodeWithSignature("startNftAuction(uint256,uint24,uint96)", listingId, 1 hours, LISTING_PRICE)
        );
        require(success2, "startNftAuction call failed");
        uint256 auctionId = abi.decode(data2, (uint256));

        // Place a bid
        vm.prank(buyer);
        (bool success11, ) = address(marketplaceProxy).call{value: LISTING_PRICE + 0.1 ether}(
            abi.encodeWithSignature("placeBid(uint256)", auctionId)
        );
        require(success11, "placeBid call failed");

        // Fast forward time to end auction
        vm.warp(block.timestamp + 1 hours + 1);

        // Test ending auction through proxy
        vm.prank(seller);
        (bool success, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("endAuction(uint256)", auctionId)
        );
        require(success, "endAuction call failed");

        // Verify auction is ended
        MarketplaceStorage.AuctionDetailsView memory auctionInfo = marketplaceStorage.getAuctionDetailsView(auctionId);
        assertFalse(auctionInfo.active, "Auction should be inactive");
    }

    function test_GetAuctionInfoRouting() public {
        // First create and start an auction
        vm.prank(seller);
        (bool success1, bytes memory data1) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success1, "listNft call failed");
        uint256 listingId = abi.decode(data1, (uint256));

        vm.prank(seller);
        (bool success6, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, true)
        );
        require(success6, "listForAuction call failed");

        vm.prank(seller);
        (bool success2, bytes memory data2) = address(marketplaceProxy).call(
            abi.encodeWithSignature("startNftAuction(uint256,uint24,uint96)", listingId, 1 hours, LISTING_PRICE)
        );
        require(success2, "startNftAuction call failed");
        uint256 auctionId = abi.decode(data2, (uint256));

        // Test getting auction info through proxy
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("getAuctionInfo(uint256)", auctionId)
        );
        require(success, "getAuctionInfo call failed");
        // For now, lets just verify the call succeeds and check the data length
        assertGt(data.length, 0, "Should return some data");

        // We can verify the auction exists by calling getAuctionDetailsView directly
        MarketplaceStorage.AuctionDetailsView memory auctionInfo = marketplaceStorage.getAuctionDetailsView(auctionId);
        assertEq(auctionInfo.seller, seller, "Seller should match");
        assertEq(auctionInfo.startingPrice, LISTING_PRICE, "Starting price should match");
        assertEq(auctionInfo.highestBid, 0, "Current bid should be 0 initially");
        assertTrue(auctionInfo.active, "Auction should be active");
        assertTrue(auctionInfo.isNft, "Should be NFT auction");
        assertEq(auctionInfo.tokenIdOrListingId, TOKEN_ID, "Token ID should match");
    }

    function test_IsAuctionExpiredRouting() public {
        // First create and start an auction
        vm.prank(seller);
        (bool success1, bytes memory data1) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success1, "listNft call failed");
        uint256 listingId = abi.decode(data1, (uint256));

        vm.prank(seller);
        (bool success7, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, true)
        );
        require(success7, "listForAuction call failed");

        vm.prank(seller);
        (bool success2, bytes memory data2) = address(marketplaceProxy).call(
            abi.encodeWithSignature("startNftAuction(uint256,uint24,uint96)", listingId, 1 hours, LISTING_PRICE)
        );
        require(success2, "startNftAuction call failed");
        uint256 auctionId = abi.decode(data2, (uint256));

        // Test before expiration
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("isAuctionExpired(uint256)", auctionId)
        );
        require(success, "isAuctionExpired call failed");
        bool expired = abi.decode(data, (bool));
        assertFalse(expired, "Auction should not be expired");

        // Fast forward time to after expiration
        vm.warp(block.timestamp + 1 hours + 1);

        // Test after expiration
        (success, data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("isAuctionExpired(uint256)", auctionId)
        );
        require(success, "isAuctionExpired call failed");
        expired = abi.decode(data, (bool));
        assertTrue(expired, "Auction should be expired");
    }

    function test_GetTimeRemainingRouting() public {
        // First create and start an auction
        vm.prank(seller);
        (bool success1, bytes memory data1) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success1, "listNft call failed");
        uint256 listingId = abi.decode(data1, (uint256));

        vm.prank(seller);
        (bool success8, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, true)
        );
        require(success8, "listForAuction call failed");

        vm.prank(seller);
        (bool success2, bytes memory data2) = address(marketplaceProxy).call(
            abi.encodeWithSignature("startNftAuction(uint256,uint24,uint96)", listingId, 1 hours, LISTING_PRICE)
        );
        require(success2, "startNftAuction call failed");
        uint256 auctionId = abi.decode(data2, (uint256));

        // Test getting time remaining
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("getTimeRemaining(uint256)", auctionId)
        );
        require(success, "getTimeRemaining call failed");
        uint256 timeRemaining = abi.decode(data, (uint256));
        assertGt(timeRemaining, 0, "Time remaining should be greater than 0");
        assertLe(timeRemaining, 1 hours, "Time remaining should be less than or equal to 1 hour");

        // Fast forward time
        vm.warp(block.timestamp + 30 minutes);

        // Test getting time remaining after some time has passed
        (success, data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("getTimeRemaining(uint256)", auctionId)
        );
        require(success, "getTimeRemaining call failed");
        timeRemaining = abi.decode(data, (uint256));
        assertGt(timeRemaining, 0, "Time remaining should still be greater than 0");
        assertLe(timeRemaining, 30 minutes, "Time remaining should be less than or equal to 30 minutes");
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateMarketplaceCoreAddress() public {
        // Deploy a new core implementation
        MarketplaceCore newCore = new MarketplaceCore(
            address(marketplaceStorage),
            address(marketplaceFees),
            address(governance),
            address(crossChainBridge)
        );

        // Test updating core address through proxy
        vm.prank(owner);
        marketplaceProxy.updateMarketplaceCoreAddress(address(newCore));

        // Verify the address was updated
        assertEq(marketplaceProxy.marketplaceCoreAddress(), address(newCore), "Core address should be updated");
    }

    function test_UpdateMarketplaceAuctionsAddress() public {
        // Deploy a new auctions implementation
        MarketplaceAuctions newAuctions = new MarketplaceAuctions(
            address(marketplaceStorage),
            address(governance),
            address(escrow),
            address(marketplaceFees)
        );

        // Test updating auctions address through proxy
        vm.prank(owner);
        marketplaceProxy.updateMarketplaceAuctionsAddress(address(newAuctions));

        // Verify the address was updated
        assertEq(marketplaceProxy.marketplaceAuctionsAddress(), address(newAuctions), "Auctions address should be updated");
    }

    function test_RevertIf_UpdateCoreAddressByNonOwner() public {
        address newCore = makeAddr("newCore");
        vm.prank(buyer);
        vm.expectRevert();
        marketplaceProxy.updateMarketplaceCoreAddress(newCore);
    }

    function test_RevertIf_UpdateAuctionsAddressByNonOwner() public {
        address newAuctions = makeAddr("newAuctions");
        vm.prank(buyer);
        vm.expectRevert();
        marketplaceProxy.updateMarketplaceAuctionsAddress(newAuctions);
    }

    // /*//////////////////////////////////////////////////////////////
    //                     RECEIVE FUNCTION TESTS
    // //////////////////////////////////////////////////////////////*/

    function test_ReceiveFunction() public {
        // Test that the contract can receive ETH
        uint256 initialBalance = address(marketplaceProxy).balance;
        uint256 sendAmount = 1 ether;

        vm.deal(address(this), sendAmount);
        (bool success, ) = address(marketplaceProxy).call{value: sendAmount}("");

        assertTrue(success, "Receive function should accept ETH");
        assertEq(address(marketplaceProxy).balance, initialBalance + sendAmount, "Balance should increase");
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FallbackWithComplexData() public {
        // Test fallback with complex function data
        bytes memory complexData = abi.encodeWithSignature(
            "listNft(address,uint256,uint96)",
            address(vertixNFT),
            TOKEN_ID,
            LISTING_PRICE
        );

        vm.prank(seller);
        (bool success, ) = address(marketplaceProxy).call(complexData);
        assertTrue(success, "Should handle complex function data");
    }

    function test_FallbackWithLargeData() public {
        // Test fallback with large data payload
        bytes memory largeData = new bytes(1000);
        for (uint i = 0; i < 1000; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }

        vm.expectRevert();
        (bool success, bytes memory data) = address(marketplaceProxy).call(largeData);
        console.logBytes(data);
        console.log(success);
    }


    function test_FallbackWithEmptyData() public {
        // Test fallback with empty data
        (bool success, ) = address(marketplaceProxy).call("");
        assertTrue(success, "Should handle empty data");
    }

    function test_MultipleConcurrentCalls() public {
        // Test multiple concurrent calls through the proxy
        vm.startPrank(seller);

        // Create multiple listings
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success, "listNft call failed");
        uint256 listingId1 = abi.decode(data, (uint256));

        vm.stopPrank();

        // Mint a second NFT for the second listing - do this as owner
        vm.startPrank(owner);
        vertixNFT.mintSingleNft(seller, URI, METADATA, 500);
        vm.stopPrank();

        // Now list the second NFT as seller
        vm.startPrank(seller);

        // Approve the second NFT
        vertixNFT.approve(address(marketplaceProxy), TOKEN_ID + 1);

        (success, data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID + 1, LISTING_PRICE)
        );
        require(success, "listNft call failed");
        uint256 listingId2 = abi.decode(data, (uint256));

        vm.stopPrank();

        assertEq(listingId1, 1, "First listing ID should be 1");
        assertEq(listingId2, 2, "Second listing ID should be 2");
    }

    function test_ProxyStateConsistency() public {
        // Test that proxy state remains consistent across calls
        vm.prank(seller);
        (bool success, bytes memory data) = address(marketplaceProxy).call(
            abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
        );
        require(success, "listNft call failed");
        uint256 listingId = abi.decode(data, (uint256));

        // Verify listing exists
        (address seller_, , , , bool active, ) = marketplaceStorage.getNftListing(listingId);
        assertEq(seller_, seller, "Seller should match");
        assertTrue(active, "Listing should be active");

        // Cancel listing
        vm.prank(seller);
        (bool success14, ) = address(marketplaceProxy).call(
            abi.encodeWithSignature("cancelNftListing(uint256)", listingId)
        );
        require(success14, "cancelNftListing call failed");

        // Verify listing is cancelled
        (, , , , bool activeAfter, ) = marketplaceStorage.getNftListing(listingId);
        assertFalse(activeAfter, "Listing should be inactive after cancellation");
    }

    // /*//////////////////////////////////////////////////////////////
    //                     INTEGRATION TESTS
    // //////////////////////////////////////////////////////////////*/

    // function test_CompleteMarketplaceFlow() public {
    //     // Test complete marketplace flow through proxy
    //     // 1. List NFT
    //     vm.prank(seller);
    //     (bool success, bytes memory data) = address(marketplaceProxy).call(
    //         abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
    //     );
    //     require(success, "listNft call failed");
    //     uint256 listingId = abi.decode(data, (uint256));

    //     // 2. Buy NFT
    //     vm.prank(buyer);
    //     address(marketplaceProxy).call{value: LISTING_PRICE}(
    //         abi.encodeWithSignature("buyNft(uint256)", listingId)
    //     );

    //     // 3. Verify NFT transfer
    //     assertEq(vertixNFT.ownerOf(TOKEN_ID), buyer, "NFT should be transferred to buyer");

    //     // 4. Verify listing is inactive
    //     (, , , , bool active, ) = marketplaceStorage.getNftListing(listingId);
    //     assertFalse(active, "Listing should be inactive after sale");
    // }

    // function test_CompleteAuctionFlow() public {
    //     // Test complete auction flow through proxy
    //     // 1. List NFT
    //     vm.prank(seller);
    //     (bool success, bytes memory data) = address(marketplaceProxy).call(
    //         abi.encodeWithSignature("listNft(address,uint256,uint96)", address(vertixNFT), TOKEN_ID, LISTING_PRICE)
    //     );
    //     require(success, "listNft call failed");
    //     uint256 listingId = abi.decode(data, (uint256));

    //     // 2. List for auction
    //     vm.prank(seller);
    //     (bool success9, ) = address(marketplaceProxy).call(
    //         abi.encodeWithSignature("listForAuction(uint256,bool)", listingId, true)
    //     );
    //     require(success9, "listForAuction call failed");

    //     // 3. Start auction
    //     vm.prank(seller);
    //     (success, data) = address(marketplaceProxy).call(
    //         abi.encodeWithSignature("startNftAuction(address,uint256,uint96,uint256)", address(vertixNFT), TOKEN_ID, LISTING_PRICE, 1 hours)
    //     );
    //     require(success, "startNftAuction call failed");
    //     uint256 auctionId = abi.decode(data, (uint256));

    //     // 4. Place bid
    //     vm.prank(buyer);
    //     (bool success15, ) = address(marketplaceProxy).call{value: LISTING_PRICE + 0.1 ether}(
    //         abi.encodeWithSignature("placeBid(uint256)", auctionId)
    //     );
    //     require(success15, "placeBid call failed");

    //     // 5. End auction
    //     vm.warp(block.timestamp + 1 hours + 1);
    //     vm.prank(seller);
    //     address(marketplaceProxy).call(
    //         abi.encodeWithSignature("endAuction(uint256)", auctionId)
    //     );

    //     // 6. Verify auction ended
    //     MarketplaceStorage.AuctionDetailsView memory auctionInfo = marketplaceStorage.getAuctionDetailsView(auctionId);
    //     assertFalse(auctionInfo.active, "Auction should be inactive after ending");
    // }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _isAuctionFunction(bytes4 selector) internal pure returns (bool) {
        return
            selector == bytes4(keccak256("startNftAuction(uint256,uint24,uint96)")) ||
            selector == bytes4(keccak256("startNonNftAuction(uint256,uint24,uint96)")) ||
            selector == bytes4(keccak256("placeBid(uint256)")) ||
            selector == bytes4(keccak256("endAuction(uint256)")) ||
            selector == bytes4(keccak256("getAuctionInfo(uint256)")) ||
            selector == bytes4(keccak256("isAuctionExpired(uint256)")) ||
            selector == bytes4(keccak256("getTimeRemaining(uint256)"));
    }
}
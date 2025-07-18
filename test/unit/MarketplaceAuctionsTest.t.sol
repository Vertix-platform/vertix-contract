// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MarketplaceAuctions} from "../../src/MarketplaceAuctions.sol";
import {MarketplaceStorage} from "../../src/MarketplaceStorage.sol";
import {MarketplaceFees} from "../../src/MarketplaceFees.sol";
import {VertixGovernance} from "../../src/VertixGovernance.sol";
import {VertixEscrow} from "../../src/VertixEscrow.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";

contract MarketplaceAuctionsTest is Test {
    // DeployVertix script instance
    DeployVertix public deployer;

    // Contract addresses from deployment
    DeployVertix.VertixAddresses public vertixAddresses;

    // Contract instances
    MarketplaceAuctions public auctions;
    MarketplaceStorage public storageContract;
    MarketplaceFees public feesContract;
    VertixGovernance public governance;
    VertixEscrow public escrow;

    // Test addresses
    address public owner;
    address public seller = makeAddr("seller");
    address public bidder1 = makeAddr("bidder1");
    address public bidder2 = makeAddr("bidder2");
    address public bidder3 = makeAddr("bidder3");
    address public unauthorized = makeAddr("unauthorized");

    // Test constants
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant LISTING_ID = 1;
    uint96 public constant STARTING_PRICE = 1 ether;
    uint96 public constant BID_AMOUNT_1 = 1.1 ether;
    uint96 public constant BID_AMOUNT_2 = 1.5 ether;
    uint96 public constant BID_AMOUNT_3 = 2 ether;
    uint24 public constant AUCTION_DURATION = 1 hours;
    uint8 public constant ASSET_TYPE = 1;
    string public constant ASSET_ID = "test-asset-123";
    string public constant METADATA = "test-metadata";
    bytes32 public constant VERIFICATION_HASH = keccak256("test-verification");

    // Test events
    event NFTAuctionStarted(
        uint256 indexed auctionId,
        address indexed seller,
        uint256 startTime,
        uint24 duration,
        uint256 price,
        address nftContract,
        uint256 tokenId
    );

    event NonNFTAuctionStarted(
        uint256 indexed auctionId,
        address indexed seller,
        uint256 startTime,
        uint24 duration,
        uint256 price,
        string assetId,
        uint8 assetType
    );

    event BidPlaced(
        uint256 indexed auctionId,
        uint256 indexed bidId,
        address indexed bidder,
        uint256 bidAmount,
        uint256 tokenId
    );

    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed bidder,
        uint256 highestBid,
        uint256 tokenId
    );

    function setUp() public {
        // Create deployer instance
        deployer = new DeployVertix();

        // Deploy all contracts using the DeployVertix script
        vertixAddresses = deployer.deployVertix();

        // Get contract instances
        auctions = MarketplaceAuctions(payable(vertixAddresses.marketplaceAuctionsImpl));
        storageContract = MarketplaceStorage(vertixAddresses.marketplaceStorage);
        feesContract = MarketplaceFees(vertixAddresses.marketplaceFees);
        governance = VertixGovernance(vertixAddresses.governance);
        escrow = VertixEscrow(vertixAddresses.escrow);

        // Get the owner from the governance contract
        owner = governance.owner();

        // Fund test accounts
        vm.deal(seller, 10 ether);
        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);
        vm.deal(bidder3, 10 ether);
        vm.deal(unauthorized, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Helper function to create an NFT listing and mark it for auction
     */
    function _createNftListingForAuction() internal returns (uint256 listingId) {
        // Create NFT listing
        vm.prank(owner);
        listingId = storageContract.createNftListing(
            seller,
            address(vertixAddresses.nft),
            TOKEN_ID,
            STARTING_PRICE
        );

        // Mark listing for auction
        vm.prank(owner);
        storageContract.updateNftListingFlags(listingId, 3); // active=1, auction=2
    }

    /**
     * @dev Helper function to create a non-NFT listing and mark it for auction
     */
    function _createNonNftListingForAuction() internal returns (uint256 listingId) {
        // Create non-NFT listing
        vm.prank(owner);
        listingId = storageContract.createNonNftListing(
            seller,
            ASSET_TYPE,
            ASSET_ID,
            STARTING_PRICE,
            METADATA,
            VERIFICATION_HASH
        );
        
        // Mark listing for auction
        vm.prank(owner);
        storageContract.updateNonNftListingFlags(listingId, 3); // active=1, auction=2
    }

    /**
     * @dev Helper function to advance time
     */
    function _advanceTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeploymentVerification() public view {
        // Verify that the auctions contract was deployed correctly
        assertTrue(vertixAddresses.marketplaceAuctionsImpl != address(0), "Auctions should be deployed");
        assertTrue(address(auctions) != address(0), "Auctions instance should be valid");
        
        // Verify contract addresses
        assertEq(address(auctions.STORAGE_CONTRACT()), address(storageContract), "Storage contract should be set");
        assertEq(address(auctions.FEES_CONTRACT()), address(feesContract), "Fees contract should be set");
        assertEq(address(auctions.GOVERNANCE_CONTRACT()), address(governance), "Governance contract should be set");
        assertEq(address(auctions.ESCROW_CONTRACT()), address(escrow), "Escrow contract should be set");
    }

    /*//////////////////////////////////////////////////////////////
                    NFT AUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartNftAuction() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        assertEq(auctionId, 1, "Auction ID should be 1");
        
        // Verify auction details
        (MarketplaceStorage.AuctionDetailsView memory auction, uint256 endTime) = auctions.getAuctionInfo(auctionId);
        assertTrue(auction.active, "Auction should be active");
        assertTrue(auction.isNft, "Should be NFT auction");
        assertEq(auction.seller, seller, "Seller should be correct");
        assertEq(auction.startingPrice, STARTING_PRICE, "Starting price should be correct");
        assertEq(auction.duration, AUCTION_DURATION, "Duration should be correct");
        assertEq(auction.tokenIdOrListingId, TOKEN_ID, "Token ID should be correct");
        assertEq(auction.nftContractAddr, address(vertixAddresses.nft), "NFT contract should be correct");
        assertEq(endTime, auction.startTime + AUCTION_DURATION, "End time should be correct");
    }

    function test_StartNftAuction_EmitsEvent() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit NFTAuctionStarted(1, seller, block.timestamp, AUCTION_DURATION, STARTING_PRICE, address(vertixAddresses.nft), TOKEN_ID);
        
        auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
    }

    function test_RevertIf_StartNftAuction_NotSeller() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(unauthorized);
        vm.expectRevert(MarketplaceAuctions.MA__NotSeller.selector);
        auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
    }

    function test_RevertIf_StartNftAuction_InvalidDuration() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceAuctions.MA__InvalidDuration.selector, 30 minutes));
        auctions.startNftAuction(listingId, 30 minutes, STARTING_PRICE);
    }

    function test_RevertIf_StartNftAuction_ZeroPrice() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        vm.expectRevert(MarketplaceAuctions.MA__InsufficientPayment.selector);
        auctions.startNftAuction(listingId, AUCTION_DURATION, 0);
    }

    function test_RevertIf_StartNftAuction_NotListedForAuction() public {
        // Create listing but don't mark for auction
        vm.prank(owner);
        uint256 listingId = storageContract.createNftListing(
            seller, 
            address(vertixAddresses.nft), 
            TOKEN_ID, 
            STARTING_PRICE
        );
        
        vm.prank(seller);
        vm.expectRevert(MarketplaceAuctions.MA__NotListedForAuction.selector);
        auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
    }

    function test_RevertIf_StartNftAuction_AlreadyListedForAuction() public {
        uint256 listingId = _createNftListingForAuction();
        
        // Start first auction
        vm.prank(seller);
        auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // Try to start second auction for same listing
        vm.prank(seller);
        vm.expectRevert(MarketplaceAuctions.MA__AlreadyListedForAuction.selector);
        auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                    NON-NFT AUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_StartNonNftAuction() public {
        uint256 listingId = _createNonNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNonNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        assertEq(auctionId, 1, "Auction ID should be 1");
        
        // Verify auction details
        (MarketplaceStorage.AuctionDetailsView memory auction, uint256 endTime) = auctions.getAuctionInfo(auctionId);
        assertTrue(auction.active, "Auction should be active");
        assertFalse(auction.isNft, "Should not be NFT auction");
        assertEq(auction.seller, seller, "Seller should be correct");
        assertEq(auction.startingPrice, STARTING_PRICE, "Starting price should be correct");
        assertEq(auction.duration, AUCTION_DURATION, "Duration should be correct");
        assertEq(auction.tokenIdOrListingId, listingId, "Listing ID should be correct");
        assertEq(auction.assetType, ASSET_TYPE, "Asset type should be correct");
        assertEq(auction.assetId, ASSET_ID, "Asset ID should be correct");
        assertEq(endTime, auction.startTime + AUCTION_DURATION, "End time should be correct");
    }

    function test_StartNonNftAuction_EmitsEvent() public {
        uint256 listingId = _createNonNftListingForAuction();
        
        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit NonNFTAuctionStarted(1, seller, block.timestamp, AUCTION_DURATION, STARTING_PRICE, ASSET_ID, ASSET_TYPE);
        
        auctions.startNonNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
    }

    function test_RevertIf_StartNonNftAuction_NotSeller() public {
        uint256 listingId = _createNonNftListingForAuction();
        
        vm.prank(unauthorized);
        vm.expectRevert(MarketplaceAuctions.MA__NotSeller.selector);
        auctions.startNonNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
    }

    /*//////////////////////////////////////////////////////////////
                    BIDDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PlaceBid() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        vm.prank(bidder1);
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);
        
        // Verify bid was placed
        (MarketplaceStorage.AuctionDetailsView memory auction,) = auctions.getAuctionInfo(auctionId);
        assertEq(auction.highestBidder, bidder1, "Highest bidder should be correct");
        assertEq(auction.highestBid, BID_AMOUNT_1, "Highest bid should be correct");
        assertEq(storageContract.getBidsCount(auctionId), 1, "Bid count should be 1");
    }

    function test_PlaceBid_EmitsEvent() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        vm.prank(bidder1);
        vm.expectEmit(true, true, true, true);
        emit BidPlaced(auctionId, 0, bidder1, BID_AMOUNT_1, TOKEN_ID);
        
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);
    }

    function test_PlaceBid_RefundsPreviousBidder() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // First bid
        vm.prank(bidder1);
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);
        
        uint256 bidder1BalanceBefore = bidder1.balance;
        
        // Second bid (should refund first bidder)
        vm.prank(bidder2);
        auctions.placeBid{value: BID_AMOUNT_2}(auctionId);
        
        uint256 bidder1BalanceAfter = bidder1.balance;
        assertEq(bidder1BalanceAfter, bidder1BalanceBefore + BID_AMOUNT_1, "First bidder should be refunded");
        
        // Verify new highest bid
        (MarketplaceStorage.AuctionDetailsView memory auction,) = auctions.getAuctionInfo(auctionId);
        assertEq(auction.highestBidder, bidder2, "Highest bidder should be updated");
        assertEq(auction.highestBid, BID_AMOUNT_2, "Highest bid should be updated");
    }

    function test_RevertIf_PlaceBid_AuctionInactive() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // End auction
        _advanceTime(AUCTION_DURATION + 1);
        vm.prank(seller);
        auctions.endAuction(auctionId);
        
        // Try to place bid on ended auction
        vm.prank(bidder1);
        vm.expectRevert(MarketplaceAuctions.MA__AuctionInactive.selector);
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);
    }

    function test_RevertIf_PlaceBid_AuctionExpired() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // Advance time past auction end
        _advanceTime(AUCTION_DURATION + 1);
        
        vm.prank(bidder1);
        vm.expectRevert(MarketplaceAuctions.MA__AuctionExpired.selector);
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);
    }

    function test_RevertIf_PlaceBid_BidTooLow() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // Try to bid below starting price
        vm.prank(bidder1);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceAuctions.MA__BidTooLow.selector, STARTING_PRICE - 0.1 ether));
        auctions.placeBid{value: STARTING_PRICE - 0.1 ether}(auctionId);
    }

    function test_RevertIf_PlaceBid_BidNotHigherThanCurrent() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // First bid
        vm.prank(bidder1);
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);
        
        // Try to bid same amount
        vm.prank(bidder2);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceAuctions.MA__BidTooLow.selector, BID_AMOUNT_1));
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);
    }

    /*//////////////////////////////////////////////////////////////
                    AUCTION ENDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EndAuction() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // Place bid
        vm.prank(bidder1);
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);
        
        // Advance time to end auction
        _advanceTime(AUCTION_DURATION + 1);
        
        vm.prank(seller);
        auctions.endAuction(auctionId);
        
        // Verify auction ended
        (MarketplaceStorage.AuctionDetailsView memory auction,) = auctions.getAuctionInfo(auctionId);
        assertFalse(auction.active, "Auction should not be active");
        assertFalse(storageContract.isTokenListedForAuction(TOKEN_ID), "Should not be listed for auction");
    }

    function test_EndAuction_EmitsEvent() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // Place bid
        vm.prank(bidder1);
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);
        
        // Advance time to end auction
        _advanceTime(AUCTION_DURATION + 1);
        
        vm.prank(seller);
        vm.expectEmit(true, true, true, true);
        emit AuctionEnded(auctionId, seller, bidder1, BID_AMOUNT_1, TOKEN_ID);
        
        auctions.endAuction(auctionId);
    }

    function test_RevertIf_EndAuction_NotSeller() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        _advanceTime(AUCTION_DURATION + 1);
        
        vm.prank(unauthorized);
        vm.expectRevert(MarketplaceAuctions.MA__NotSeller.selector);
        auctions.endAuction(auctionId);
    }

    function test_RevertIf_EndAuction_AuctionInactive() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // End auction
        _advanceTime(AUCTION_DURATION + 1);
        vm.prank(seller);
        auctions.endAuction(auctionId);
        
        // Try to end again
        vm.prank(seller);
        vm.expectRevert(MarketplaceAuctions.MA__AuctionInactive.selector);
        auctions.endAuction(auctionId);
    }

    function test_RevertIf_EndAuction_AuctionOngoing() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // Try to end auction before it expires
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(MarketplaceAuctions.MA__AuctionOngoing.selector, block.timestamp));
        auctions.endAuction(auctionId);
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetAuctionInfo() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        (MarketplaceStorage.AuctionDetailsView memory auction, uint256 endTime) = auctions.getAuctionInfo(auctionId);
        
        assertTrue(auction.active, "Auction should be active");
        assertEq(auction.seller, seller, "Seller should be correct");
        assertEq(auction.startingPrice, STARTING_PRICE, "Starting price should be correct");
        assertEq(auction.duration, AUCTION_DURATION, "Duration should be correct");
        assertEq(endTime, auction.startTime + AUCTION_DURATION, "End time should be correct");
    }

    function test_IsAuctionExpired() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        // Check before expiration
        assertFalse(auctions.isAuctionExpired(auctionId), "Auction should not be expired");
        
        // Advance time past expiration
        _advanceTime(AUCTION_DURATION + 1);
        assertTrue(auctions.isAuctionExpired(auctionId), "Auction should be expired");
    }

    function test_GetTimeRemaining() public {
        uint256 listingId = _createNftListingForAuction();
        
        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
        
        uint256 timeRemaining = auctions.getTimeRemaining(auctionId);
        assertGt(timeRemaining, 0, "Time remaining should be greater than 0");
        assertLe(timeRemaining, AUCTION_DURATION, "Time remaining should be less than or equal to duration");
        
        // Advance time
        _advanceTime(AUCTION_DURATION / 2);
        uint256 newTimeRemaining = auctions.getTimeRemaining(auctionId);
        assertLt(newTimeRemaining, timeRemaining, "Time remaining should decrease");
        
        // Advance past expiration
        _advanceTime(AUCTION_DURATION);
        assertEq(auctions.getTimeRemaining(auctionId), 0, "Time remaining should be 0 after expiration");
    }

    /*//////////////////////////////////////////////////////////////
                    PAUSE FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PauseAndUnpause() public {
        // Pause
        vm.prank(owner);
        auctions.pause();
        assertTrue(auctions.paused(), "Contract should be paused");
        
        // Unpause
        vm.prank(owner);
        auctions.unpause();
        assertFalse(auctions.paused(), "Contract should not be paused");
    }

    function test_RevertIf_Pause_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert(MarketplaceAuctions.MA__NotSeller.selector);
        auctions.pause();
    }

    function test_RevertIf_Unpause_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert(MarketplaceAuctions.MA__NotSeller.selector);
        auctions.unpause();
    }

    function test_RevertIf_StartAuction_WhenPaused() public {
        uint256 listingId = _createNftListingForAuction();

        // Pause contract
        vm.prank(owner);
        auctions.pause();

        vm.prank(seller);
        vm.expectRevert();
        auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);
    }

    function test_RevertIf_EndAuction_WhenPaused() public {
        uint256 listingId = _createNftListingForAuction();

        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);

        // Pause contract
        vm.prank(owner);
        auctions.pause();

        _advanceTime(AUCTION_DURATION + 1);
        vm.prank(seller);
        vm.expectRevert();
        auctions.endAuction(auctionId);
    }

    /*//////////////////////////////////////////////////////////////
                    EDGE CASES AND INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleBids() public {
        uint256 listingId = _createNftListingForAuction();

        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);

        // Place multiple bids
        vm.prank(bidder1);
        auctions.placeBid{value: BID_AMOUNT_1}(auctionId);

        vm.prank(bidder2);
        auctions.placeBid{value: BID_AMOUNT_2}(auctionId);

        vm.prank(bidder3);
        auctions.placeBid{value: BID_AMOUNT_3}(auctionId);

        // Verify final state
        (MarketplaceStorage.AuctionDetailsView memory auction,) = auctions.getAuctionInfo(auctionId);
        assertEq(auction.highestBidder, bidder3, "Highest bidder should be correct");
        assertEq(auction.highestBid, BID_AMOUNT_3, "Highest bid should be correct");
        assertEq(storageContract.getBidsCount(auctionId), 3, "Bid count should be 3");

        // Verify bidder balances (previous bidders should be refunded)
        assertGt(bidder1.balance, 0, "Bidder1 should have been refunded");
        assertGt(bidder2.balance, 0, "Bidder2 should have been refunded");
    }

    function test_AuctionWithNoBids() public {
        uint256 listingId = _createNftListingForAuction();

        vm.prank(seller);
        uint256 auctionId = auctions.startNftAuction(listingId, AUCTION_DURATION, STARTING_PRICE);

        // Advance time to end auction
        _advanceTime(AUCTION_DURATION + 1);

        vm.prank(seller);
        auctions.endAuction(auctionId);

        // Verify auction ended with no winner
        (MarketplaceStorage.AuctionDetailsView memory auction,) = auctions.getAuctionInfo(auctionId);
        assertFalse(auction.active, "Auction should not be active");
        assertEq(auction.highestBidder, address(0), "Should be no highest bidder");
        assertEq(auction.highestBid, 0, "Should be no highest bid");
    }

    function test_ReceiveFunction() public {
        // Test that contract can receive ETH
        uint256 contractBalanceBefore = address(auctions).balance;

        payable(address(auctions)).transfer(1 ether);

        assertEq(address(auctions).balance, contractBalanceBefore + 1 ether, "Contract should receive ETH");
    }
} 
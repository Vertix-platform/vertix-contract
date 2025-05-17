// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2, console} from "forge-std/Test.sol";
import {VertixMarketplace} from "../../src/VertixMarketplace.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {MockVertixNFT} from "../../test/mocks/MockVertixNFT.sol";
import {MockVertixGovernance} from "../../test/mocks/MockVertixGovernance.sol";

// Helper contract to simulate failed Ether transfers
contract EtherRejecter {
    receive() external payable {
        revert("Ether transfer rejected");
    }
}

contract VertixMarketplaceAuctionTest is Test {
    VertixMarketplace marketplace;
    MockVertixNFT nftContract;
    MockVertixGovernance governanceContract;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address escrowContract = makeAddr("escrow");
    address feeRecipient = makeAddr("feeRecipient");

    address INVALID_NFT = makeAddr("invalidNft");

    uint24 constant MIN_AUCTION_DURATION = 1 hours;
    uint24 constant MAX_AUCTION_DURATION = 7 days;
    uint256 constant VALID_PRICE = 1 ether;
    uint256 constant TOKEN_ID = 1;

    event NFTAuctionStarted(
        uint256 indexed auctionId,
        address indexed seller,
        uint256 startTime,
        uint24 duration,
        uint256 price,
        address nftContract,
        uint256 tokenId
    );

    // Helper fucntion for starting auctions
    function startAuction(address seller, uint256 tokenId, uint24 duration, uint256 price) internal {
        vm.prank(seller);
        marketplace.startNFTAuction(address(nftContract), tokenId, duration, price);
    }

    function setUp() public {
        // Deploy mock contracts
        nftContract = new MockVertixNFT();

        // Deploy and initialize marketplace
        marketplace = new VertixMarketplace();

        governanceContract = new MockVertixGovernance(feeRecipient, address(marketplace), escrowContract);

        marketplace.initialize(address(nftContract), address(governanceContract), escrowContract);

        // Mint an NFT to user1
        vm.prank(user1);
        nftContract.mint(user1, TOKEN_ID);

        // Approve marketplace to transfer NFT
        vm.prank(user1);
        nftContract.approve(address(marketplace), TOKEN_ID);
    }

    // Test successful auction start
    function testStartNFTAuctionSuccess() public {
        uint24 duration = 1 days;
        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit NFTAuctionStarted(1, user1, block.timestamp, duration, VALID_PRICE, address(nftContract), TOKEN_ID);

        // Verify ownership before starting auction
        assertEq(nftContract.ownerOf(TOKEN_ID), user1, "user1 should own the NFT");

        // Verify auction state before auction
        assertFalse(marketplace.isListedForAuction(TOKEN_ID));

        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, duration, VALID_PRICE);

        VertixMarketplace.AuctionDetails memory details = marketplace.getAuctionDetails(1);
        assertTrue(details.active);
        assertEq(details.duration, duration);
        assertEq(details.seller, user1);
        assertEq(details.highestBidder, address(0));
        assertEq(address(details.nftContract), address(nftContract));
        assertEq(details.tokenId, TOKEN_ID);
        assertEq(details.auctionId, 1);
        assertEq(details.startingPrice, VALID_PRICE);

        // Verify token is transferred to marketplace
        assertEq(nftContract.ownerOf(TOKEN_ID), address(marketplace));

        // Verify auction state using getters
        assertTrue(marketplace.isListedForAuction(TOKEN_ID));
        assertEq(marketplace.getAuctionIdForToken(TOKEN_ID), 1);
        vm.stopPrank();
    }

    // Test revert if NFT contract is invalid
    function testStartNFTAuctionInvalidNFTContract() public {
        vm.prank(user1);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__InvalidNFTContract.selector);
        marketplace.startNFTAuction(INVALID_NFT, TOKEN_ID, 1 days, VALID_PRICE);
    }

    // Test revert if caller is not the owner
    function testStartNFTAuctionNotOwner() public {
        vm.prank(user2);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__NotOwner.selector);
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, 1 days, VALID_PRICE);
    }

    // Test revert if duration is too short
    function testStartNFTAuctionDurationTooShort() public {
        uint24 invalidDuration = MIN_AUCTION_DURATION - 1;
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(VertixMarketplace.VertixMarketplace__IncorrectDuration.selector, invalidDuration)
        );
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, invalidDuration, VALID_PRICE);
    }

    // Test revert if duration is too long
    function testStartNFTAuctionDurationTooLong() public {
        uint24 invalidDuration = MAX_AUCTION_DURATION + 1;
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(VertixMarketplace.VertixMarketplace__IncorrectDuration.selector, invalidDuration)
        );
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, invalidDuration, VALID_PRICE);
    }

    // Test revert if NFT is already listed for auction
    function testStartNFTAuctionAlreadyListed() public {
        // Start first auction
        vm.prank(user1);
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, 1 days, VALID_PRICE);

        // call with marketplace contract since its the new owner
        vm.prank(address(marketplace));
        vm.expectRevert(abi.encodeWithSelector(VertixMarketplace.VertixMarketplace__AlreadyListedForAuction.selector));
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, 1 days, VALID_PRICE);
    }

    function testStartNFTAuctionInvalidPrice() public {
        vm.prank(user1);
        vm.expectRevert(); // Assuming validatePrice reverts (specific error depends on VertixUtils)
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, 1 days, 0);
    }

    function testPlaceBidSuccess() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Provide Ether to user2
        vm.deal(user2, 2 ether);

        // Place bid
        vm.prank(user2);
        marketplace.placeBidForAuction{value: 1.5 ether}(1);

        // Verify auction state
        VertixMarketplace.AuctionDetails memory details = marketplace.getAuctionDetails(1);
        assertEq(details.highestBid, 1.5 ether, "Highest bid should be 1.5 ether");
        assertEq(details.highestBidder, user2, "Highest bidder should be user2");

        // Verify bid storage
        VertixMarketplace.Bid memory bid = marketplace.getSingleBidForAuction(1, 0);
        assertEq(bid.auctionId, 1, "Bid auction ID should be 1");
        assertEq(bid.bidAmount, 1.5 ether, "Bid amount should be 1.5 ether");
        assertEq(bid.bidder, user2, "Bidder should be user2");

        // Verify contract balance
        assertEq(address(marketplace).balance, 1.5 ether, "Contract should hold 1.5 ether");
    }

    // Test multiple users placing bids
    function testPlaceMultipleBids() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Provide Ether to users
        vm.deal(user2, 3 ether);
        vm.deal(user3, 3 ether);

        // User2 places first bid
        vm.prank(user2);
        marketplace.placeBidForAuction{value: 1.5 ether}(1);

        // Verify user2's balance
        assertEq(user2.balance, 1.5 ether, "User2 should have 1.5 ether remaining");

        // User3 places higher bid
        uint256 user3InitialBalance = user3.balance;
        vm.prank(user3);
        marketplace.placeBidForAuction{value: 2 ether}(1);

        // Verify auction state
        VertixMarketplace.AuctionDetails memory details = marketplace.getAuctionDetails(1);
        assertEq(details.highestBid, 2 ether, "Highest bid should be 2 ether");
        assertEq(details.highestBidder, user3, "Highest bidder should be user3");

        // Verify user2 was refunded
        assertEq(user2.balance, 3 ether, "User2 should be refunded 1.5 ether");

        // Verify user3's balance
        assertEq(user3.balance, user3InitialBalance - 2 ether, "User3 should have sent 2 ether");

        // Verify bid storage
        VertixMarketplace.Bid memory bid1 = marketplace.getSingleBidForAuction(1, 0);
        assertEq(bid1.auctionId, 1, "First bid auction ID should be 1");
        assertEq(bid1.bidId, 0, "First bid ID should be 0");
        assertEq(bid1.bidAmount, 1.5 ether, "First bid amount should be 1.5 ether");
        assertEq(bid1.bidder, user2, "First bidder should be user2");

        VertixMarketplace.Bid memory bid2 = marketplace.getSingleBidForAuction(1, 1);
        assertEq(bid2.auctionId, 1, "Second bid auction ID should be 1");
        assertEq(bid2.bidId, 1, "Second bid ID should be 1");
        assertEq(bid2.bidAmount, 2 ether, "Second bid amount should be 2 ether");
        assertEq(bid2.bidder, user3, "Second bidder should be user3");

        // Verify bid count
        assertEq(marketplace.getBidCountForAuction(1), 2, "Bid count should be 2");

        // Verify contract balance
        assertEq(address(marketplace).balance, 2 ether, "Contract should hold 2 ether");
    }

    // Test revert when bid is too low
    function testPlaceBidTooLow() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Provide Ether to users
        vm.deal(user2, 2 ether);
        vm.deal(user2, 2 ether);
        vm.deal(user3, 2 ether);

        // Try to place bid below starting price
        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(VertixMarketplace.VertixMarketplace__AuctionBidTooLow.selector, 0.5 ether)
        );
        marketplace.placeBidForAuction{value: 0.5 ether}(1);

        // Place valid bid
        vm.prank(user2);
        marketplace.placeBidForAuction{value: 1.5 ether}(1);

        // Try to place bid equal to current highest bid
        vm.prank(user3);
        vm.expectRevert(
            abi.encodeWithSelector(VertixMarketplace.VertixMarketplace__AuctionBidTooLow.selector, 1.5 ether)
        );
        marketplace.placeBidForAuction{value: 1.5 ether}(1);
    }

    // Test revert when auction is inactive
    function testPlaceBidAuctionInactive() public {
        // No auction started
        vm.deal(user2, 1.5 ether);
        vm.prank(user2);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__AuctionInactive.selector);
        marketplace.placeBidForAuction{value: 1.5 ether}(1);
    }

    // Test revert when auction is expired
    function testPlaceBidAuctionExpired() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Warp time to after auction duration
        vm.warp(block.timestamp + 1 days + 1);

        // Try to place bid
        vm.deal(user2, 1.5 ether);
        vm.prank(user2);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__AuctionExpired.selector);
        marketplace.placeBidForAuction{value: 1.5 ether}(1);
    }

    // Test revert when contract has insufficient balance to refund
    function testPlaceBidInsufficientContractBalance() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Place first bid
        vm.deal(user2, 1.5 ether);
        vm.prank(user2);
        marketplace.placeBidForAuction{value: 1.5 ether}(1);

        // Drain contract balance to simulate insufficient funds
        vm.deal(address(marketplace), 0);
        console.log("marketplace balance before: ", address(marketplace).balance);

        // Try to place second bid
        vm.deal(user3, 2 ether);
        vm.prank(user3);
        console.log("marketplace balance after: ", address(marketplace).balance);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__ContractInsufficientBalance.selector);
        marketplace.placeBidForAuction{value: 2 ether}(1);
    }

    // Test refund logic for outbid user
    function testOutbidUserRefund() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Provide Ether to users
        vm.deal(user2, 3 ether);
        vm.deal(user3, 3 ether);

        // User2 places first bid
        vm.prank(user2);
        marketplace.placeBidForAuction{value: 1.5 ether}(1);

        // Record user2's balance
        uint256 user2BalanceBefore = user2.balance;

        // User3 places higher bid
        vm.prank(user3);
        marketplace.placeBidForAuction{value: 2 ether}(1);

        // Verify user2 was refunded
        assertEq(user2.balance, user2BalanceBefore + 1.5 ether, "User2 should be refunded 1.5 ether");

        // Verify contract balance
        assertEq(address(marketplace).balance, 2 ether, "Contract should hold 2 ether");
    }

    // New test for invalid bid index
    function testGetBidsForAuctionInvalidIndex() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Place a bid
        vm.deal(user2, 1.5 ether);
        vm.prank(user2);
        marketplace.placeBidForAuction{value: 1.5 ether}(1);

        // Try to access an invalid index
        vm.expectRevert();
        marketplace.getSingleBidForAuction(1, 1);
    }

    // Test successful auction end with bids
    function testEndAuctionWithBidsSuccess() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);
        console.log("duration of auction is: ", marketplace.getAuctionDetails(1).duration);

        // Place bids
        vm.deal(user2, 2 ether);
        vm.deal(user3, 3 ether);
        vm.prank(user2);
        marketplace.placeBidForAuction{value: 1.5 ether}(1);
        vm.prank(user3);
        marketplace.placeBidForAuction{value: 2 ether}(1);

        // Verify contract balance after bids
        assertEq(address(marketplace).balance, 2 ether, "Contract should hold 2 ether after bids");

        // Warp to after auction duration
        vm.warp(block.timestamp + 1 days + 1);

        // Get fee config
        (uint16 feeBps, address feeRecipient_) = governanceContract.getFeeConfig();

        uint256 platformFee = (2 ether * uint256(feeBps)) / 10_000;

        uint256 sellerProceeds = 2 ether - platformFee;

        // Record balances before
        uint256 feeRecipientBalanceBefore = feeRecipient_.balance;
        uint256 sellerBalanceBefore = user1.balance;

        // End auction
        vm.prank(user1);
        marketplace.endAuction(1);

        // Verify NFT ownership
        assertEq(nftContract.ownerOf(TOKEN_ID), user3, "NFT should be owned by user3");

        // Verify balances
        assertEq(
            feeRecipient_.balance, feeRecipientBalanceBefore + platformFee, "Fee recipient should receive platform fee"
        );
        assertEq(user1.balance, sellerBalanceBefore + sellerProceeds, "Seller should receive proceeds");

        // Verify auction state
        VertixMarketplace.AuctionDetails memory details = marketplace.getAuctionDetails(1);
        assertFalse(details.active, "Auction should be inactive");
        assertFalse(marketplace.isListedForAuction(TOKEN_ID), "Token should not be listed for auction");
        assertEq(marketplace.getTokenIdForAuction(1), TOKEN_ID, "Token ID for auction should remain");

        // Verify contract balance
        assertEq(address(marketplace).balance, 0, "Contract should have no balance");
    }

    // Test successful auction end with no bids
    function testEndAuctionNoBidsSuccess() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Warp to after auction duration
        vm.warp(block.timestamp + 1 days + 1);

        // End auction
        vm.prank(user1);
        marketplace.endAuction(1);

        // Verify NFT ownership
        assertEq(nftContract.ownerOf(TOKEN_ID), user1, "NFT should be returned to seller");

        // Verify auction state
        VertixMarketplace.AuctionDetails memory details = marketplace.getAuctionDetails(1);
        assertFalse(details.active, "Auction should be inactive");
        assertFalse(marketplace.isListedForAuction(TOKEN_ID), "Token should not be listed for auction");

        // Verify contract balance
        assertEq(address(marketplace).balance, 0, "Contract should have no balance");
    }

    // Test revert if caller is not seller
    function testEndAuctionNotSeller() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Warp to after auction duration
        vm.warp(block.timestamp + 1 days + 1);

        // Try to end auction as non-seller
        vm.prank(user2);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__NotSeller.selector);
        marketplace.endAuction(1);
    }

    // Test revert if auction is inactive
    function testEndAuctionInactive() public {
        // Start and end auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(user1);
        marketplace.endAuction(1);

        // Try to end again
        vm.prank(user1);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__AuctionInactive.selector);
        marketplace.endAuction(1);
    }

    // Test revert if auction is still ongoing
    function testEndAuctionOngoing() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Try to end before duration
        vm.prank(user1);
        uint256 timestamp = block.timestamp;
        vm.expectRevert(abi.encodeWithSelector(VertixMarketplace.VertixMarketplace__AuctionOngoing.selector, timestamp));
        marketplace.endAuction(1);
    }

    // Test revert if fee transfer fails
    function testEndAuctionFeeTransferFailed() public {
        // Start auction
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // Place bid
        vm.deal(user2, 2 ether);
        vm.prank(user2);
        marketplace.placeBidForAuction{value: 2 ether}(1);

        // Set fee recipient to a contract that rejects Ether
        address rejectingContract = address(new EtherRejecter());
        vm.prank(address(governanceContract));
        governanceContract.setFeeRecipient(rejectingContract);

        // Warp to after auction duration
        vm.warp(block.timestamp + 1 days + 1);

        // Try to end auction
        vm.prank(user1);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__FeeTransferFailed.selector);
        marketplace.endAuction(1);
    }

    // Test revert if seller transfer fails
    function testEndAuctionSellerTransferFailed() public {
        // Start first auction (optional, to ensure consistent state)
        startAuction(user1, TOKEN_ID, 1 days, VALID_PRICE);

        // End first auction with no bids to return NFT to user1
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(user1);
        marketplace.endAuction(1);

        // Verify NFT is back with user1
        assertEq(nftContract.ownerOf(TOKEN_ID), user1, "NFT should be owned by user1");

        // Deploy EtherRejecter contract
        address rejectingContract = address(new EtherRejecter());

        // Approve and transfer NFT to EtherRejecter
        vm.prank(user1);
        nftContract.approve(rejectingContract, TOKEN_ID);
        vm.prank(user1);
        nftContract.transferFrom(user1, rejectingContract, TOKEN_ID);

        // Verify EtherRejecter owns the NFT
        assertEq(nftContract.ownerOf(TOKEN_ID), rejectingContract, "NFT should be owned by EtherRejecter");

        // Approve marketplace to transfer NFT from EtherRejecter
        vm.prank(rejectingContract);
        (bool success,) = address(nftContract).call(
            abi.encodeWithSignature("approve(address,uint256)", address(marketplace), TOKEN_ID)
        );
        require(success, "Approval failed");

        // Start new auction with EtherRejecter as seller
        vm.prank(rejectingContract);
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, 1 days, VALID_PRICE);

        // Place bid for the new auction (ID 2)
        vm.deal(user2, 2 ether);
        vm.prank(user2);
        marketplace.placeBidForAuction{value: 2 ether}(2);

        // Warp to after auction duration
        vm.warp(block.timestamp + 1 days + 1);

        // Try to end auction, expect revert due to seller transfer failure
        vm.prank(rejectingContract);
        vm.expectRevert(VertixMarketplace.VertixMarketplace__TransferFailed.selector);
        marketplace.endAuction(2);
    }
}

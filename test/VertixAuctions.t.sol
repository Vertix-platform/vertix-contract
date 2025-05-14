// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {VertixMarketplace} from "../src/VertixMarketplace.sol";
import {IVertixNFT} from "../src/interfaces/IVertixNFT.sol";
import {ERC721} from"@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Mock VertixNFT contract for testing
contract MockVertixNFT is ERC721 {
    constructor() ERC721("VertixNFT", "VNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}


contract VertixMarketplaceAuctionTest is Test {
    VertixMarketplace marketplace;
    MockVertixNFT nftContract;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address escrowContract = makeAddr("escrow");
    address governanceContract = makeAddr("governanceContract");

    address INVALID_NFT = makeAddr("invalidNft");

    uint24 constant MIN_AUCTION_DURATION = 1 hours;
    uint24 constant MAX_AUCTION_DURATION = 7 days;
    uint256 constant VALID_PRICE = 1 ether;
    uint256 constant TOKEN_ID = 1;

    event NFTAuctionStarted(
        uint256 indexed auctionId,
        address indexed seller,
        uint24 duration,
        uint256 price,
        address nftContract,
        uint256 tokenId
    );

    function setUp() public {
        // Deploy mock contracts
        nftContract = new MockVertixNFT();

        // Deploy and initialize marketplace
        marketplace = new VertixMarketplace();
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
        emit NFTAuctionStarted(1, user1, duration, VALID_PRICE, address(nftContract), TOKEN_ID);

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
        vm.expectRevert(abi.encodeWithSelector(VertixMarketplace.VertixMarketplace__IncorrectDuration.selector, invalidDuration));
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, invalidDuration, VALID_PRICE);
    }

    // Test revert if duration is too long
    function testStartNFTAuctionDurationTooLong() public {
        uint24 invalidDuration = MAX_AUCTION_DURATION + 1;
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VertixMarketplace.VertixMarketplace__IncorrectDuration.selector, invalidDuration));
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, invalidDuration, VALID_PRICE);
    }

    // Test revert if NFT is already listed for auction
    function testStartNFTAuctionAlreadyListed() public {
        // Start first auction
        vm.prank(user1);
        marketplace.startNFTAuction(address(nftContract), TOKEN_ID, 1 days, VALID_PRICE);

        // Try to start another auction for the same token
        address newOwner = nftContract.ownerOf(TOKEN_ID);

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
}

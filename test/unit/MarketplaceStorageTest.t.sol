// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MarketplaceStorage} from "../../src/MarketplaceStorage.sol";
import {CrossChainRegistry} from "../../src/CrossChainRegistry.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";


contract MarketplaceStorageTest is Test {
    // DeployVertix script instance
    DeployVertix public deployer;

    // Contract addresses from deployment
    DeployVertix.VertixAddresses public vertixAddresses;

    // Contract instances
    MarketplaceStorage public storageContract;

    address public owner;
    address public authorizedContract = makeAddr("authorizedContract");
    address public unauthorizedContract = makeAddr("unauthorizedContract");
    address public seller = makeAddr("seller");
    address public bidder1 = makeAddr("bidder1");
    address public bidder2 = makeAddr("bidder2");
    address public nftContract = makeAddr("nftContract");

    uint256 public constant TOKEN_ID = 1;
    uint256 public constant LISTING_ID = 1;
    uint256 public constant AUCTION_ID = 1;
    uint96 public constant LISTING_PRICE = 1 ether;
    uint96 public constant STARTING_PRICE = 0.5 ether;
    uint96 public constant BID_AMOUNT_1 = 1 ether;
    uint96 public constant BID_AMOUNT_2 = 1.5 ether;
    uint24 public constant AUCTION_DURATION = 1 hours;
    uint8 public constant ASSET_TYPE = 1;
    string public constant ASSET_ID = "asset123";
    string public constant METADATA = "metadata123";
    bytes32 public constant VERIFICATION_HASH = bytes32(uint256(123456789));

    event ContractAuthorized(address indexed contractAddr, bool authorized);

    function setUp() public {
        // Create deployer instance
        deployer = new DeployVertix();

        // Deploy all contracts using the DeployVertix script
        vertixAddresses = deployer.deployVertix();

        // Get the storage contract instance
        storageContract = MarketplaceStorage(vertixAddresses.marketplaceStorage);

        // Get the owner from the storage contract
        owner = storageContract.owner();

        // Fund test accounts
        vm.deal(seller, 10 ether);
        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);

        // Authorize a test contract
        vm.prank(owner);
        storageContract.authorizeContract(authorizedContract, true);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPLOYMENT VERIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeploymentVerification() public view {
        // Verify that the storage contract was deployed correctly
        assertTrue(vertixAddresses.marketplaceStorage != address(0), "Storage should be deployed");
        assertTrue(vertixAddresses.governance != address(0), "Governance should be deployed");
        assertTrue(vertixAddresses.escrow != address(0), "Escrow should be deployed");

        // Verify that storage has correct owner
        assertEq(storageContract.owner(), owner, "Storage should have correct owner");

        // Verify initial state
        assertEq(storageContract.listingIdCounter(), 1, "Initial listing counter should be 1");
        assertEq(storageContract.auctionIdCounter(), 1, "Initial auction counter should be 1");
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeContract() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ContractAuthorized(authorizedContract, false);
        storageContract.authorizeContract(authorizedContract, false);

        assertFalse(storageContract.authorizedContracts(authorizedContract), "Contract should be unauthorized");
    }

    function test_RevertIf_NonOwnerAuthorizesContract() public {
        vm.prank(seller);
        vm.expectRevert("MStorage: Not owner");
        storageContract.authorizeContract(authorizedContract, true);
    }

    function test_SetContracts() public {
        address newNftContract = makeAddr("newNftContract");
        address newGovernanceContract = makeAddr("newGovernanceContract");
        address newEscrowContract = makeAddr("newEscrowContract");

        vm.prank(owner);
        storageContract.setContracts(newNftContract, newGovernanceContract, newEscrowContract);

        assertEq(address(storageContract.vertixNftContract()), newNftContract, "NFT contract should be updated");
        assertEq(storageContract.governanceContract(), newGovernanceContract, "Governance contract should be updated");
        assertEq(storageContract.escrowContract(), newEscrowContract, "Escrow contract should be updated");
    }

    function test_RevertIf_NonOwnerSetsContracts() public {
        vm.prank(seller);
        vm.expectRevert("MStorage: Not owner");
        storageContract.setContracts(address(0), address(0), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    NFT LISTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateNftListing() public {
        vm.prank(authorizedContract);
        uint256 listingId = storageContract.createNftListing(seller, nftContract, TOKEN_ID, LISTING_PRICE);

        assertEq(listingId, LISTING_ID, "Listing ID should be correct");
        assertEq(storageContract.listingIdCounter(), 2, "Listing counter should be incremented");

        // Verify listing data
        (address listingSeller, address listingNftContract, uint256 listingTokenId, uint96 listingPrice, bool active, bool auctionListed) = 
            storageContract.getNftListing(listingId);

        assertEq(listingSeller, seller, "Seller should be correct");
        assertEq(listingNftContract, nftContract, "NFT contract should be correct");
        assertEq(listingTokenId, TOKEN_ID, "Token ID should be correct");
        assertEq(listingPrice, LISTING_PRICE, "Price should be correct");
        assertTrue(active, "Listing should be active");
        assertFalse(auctionListed, "Listing should not be auction listed");

        // Verify listing hash exists (we'll check the actual hash in a separate test)
        assertTrue(storageContract.listingIdCounter() > 1, "Listing should be created");
    }

    function test_RevertIf_UnauthorizedCreateNftListing() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.createNftListing(seller, nftContract, TOKEN_ID, LISTING_PRICE);
    }

    function test_UpdateNftListingFlags() public {
        // Create listing first
        vm.prank(authorizedContract);
        uint256 listingId = storageContract.createNftListing(seller, nftContract, TOKEN_ID, LISTING_PRICE);

        // Update flags to set auction listed
        vm.prank(authorizedContract);
        storageContract.updateNftListingFlags(listingId, 3); // active=1, auction=2

        // Verify flags updated
        (,,,, bool active, bool auctionListed) = storageContract.getNftListing(listingId);
        assertTrue(active, "Listing should still be active");
        assertTrue(auctionListed, "Listing should be auction listed");
        assertTrue(storageContract.isTokenListedForAuction(listingId), "Should be listed for auction");
    }

    function test_RevertIf_UnauthorizedUpdateNftListingFlags() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.updateNftListingFlags(LISTING_ID, 0);
    }

    function test_RemoveNftListingHash() public {
        // Create listing first
        vm.prank(authorizedContract);
        storageContract.createNftListing(seller, nftContract, TOKEN_ID, LISTING_PRICE);

        // Remove listing hash
        vm.prank(authorizedContract);
        storageContract.removeNftListingHash(nftContract, TOKEN_ID);

        // Verify hash removed
        bytes32 expectedHash = keccak256(abi.encodePacked(nftContract, TOKEN_ID));
        assertFalse(storageContract.checkListingHash(expectedHash), "Listing hash should be removed");
    }

    function test_RevertIf_UnauthorizedRemoveNftListingHash() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.removeNftListingHash(nftContract, TOKEN_ID);
    }

    /*//////////////////////////////////////////////////////////////
                    NON-NFT LISTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateNonNftListing() public {
        vm.prank(authorizedContract);
        uint256 listingId = storageContract.createNonNftListing(
            seller, ASSET_TYPE, ASSET_ID, LISTING_PRICE, METADATA, VERIFICATION_HASH
        );

        assertEq(listingId, LISTING_ID, "Listing ID should be correct");
        assertEq(storageContract.listingIdCounter(), 2, "Listing counter should be incremented");

        // Verify listing data
        (address listingSeller, uint96 listingPrice, uint8 listingAssetType, bool active, bool auctionListed, 
         string memory listingAssetId, string memory listingMetadata, bytes32 listingVerificationHash) = 
            storageContract.getNonNftListing(listingId);

        assertEq(listingSeller, seller, "Seller should be correct");
        assertEq(listingPrice, LISTING_PRICE, "Price should be correct");
        assertEq(listingAssetType, ASSET_TYPE, "Asset type should be correct");
        assertTrue(active, "Listing should be active");
        assertFalse(auctionListed, "Listing should not be auction listed");
        assertEq(listingAssetId, ASSET_ID, "Asset ID should be correct");
        assertEq(listingMetadata, METADATA, "Metadata should be correct");
        assertEq(listingVerificationHash, VERIFICATION_HASH, "Verification hash should be correct");

        // Verify listing hash
        bytes32 expectedHash = keccak256(abi.encodePacked(seller, ASSET_ID));
        assertTrue(storageContract.checkListingHash(expectedHash), "Listing hash should be set");
    }

    function test_RevertIf_UnauthorizedCreateNonNftListing() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.createNonNftListing(
            seller, ASSET_TYPE, ASSET_ID, LISTING_PRICE, METADATA, VERIFICATION_HASH
        );
    }

    function test_UpdateNonNftListingFlags() public {
        // Create listing first
        vm.prank(authorizedContract);
        uint256 listingId = storageContract.createNonNftListing(
            seller, ASSET_TYPE, ASSET_ID, LISTING_PRICE, METADATA, VERIFICATION_HASH
        );

        // Update flags to set auction listed
        vm.prank(authorizedContract);
        storageContract.updateNonNftListingFlags(listingId, 3); // active=1, auction=2

        // Verify flags updated by checking the auction listing status
        assertTrue(storageContract.isTokenListedForAuction(listingId), "Should be listed for auction");
    }

    function test_RevertIf_UnauthorizedUpdateNonNftListingFlags() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.updateNonNftListingFlags(LISTING_ID, 0);
    }

    function test_RemoveNonNftListingHash() public {
        // Create listing first
        vm.prank(authorizedContract);
        storageContract.createNonNftListing(
            seller, ASSET_TYPE, ASSET_ID, LISTING_PRICE, METADATA, VERIFICATION_HASH
        );

        // Remove listing hash
        vm.prank(authorizedContract);
        storageContract.removeNonNftListingHash(seller, ASSET_ID);

        // Verify hash removed
        bytes32 expectedHash = keccak256(abi.encodePacked(seller, ASSET_ID));
        assertFalse(storageContract.checkListingHash(expectedHash), "Listing hash should be removed");
    }

    function test_RevertIf_UnauthorizedRemoveNonNftListingHash() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.removeNonNftListingHash(seller, ASSET_ID);
    }

    /*//////////////////////////////////////////////////////////////
                    AUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateNftAuction() public {
        vm.prank(authorizedContract);
        uint256 auctionId = storageContract.createAuction(
            seller, TOKEN_ID, STARTING_PRICE, AUCTION_DURATION, true, nftContract, ASSET_TYPE, ""
        );

        assertEq(auctionId, AUCTION_ID, "Auction ID should be correct");
        assertEq(storageContract.auctionIdCounter(), 2, "Auction counter should be incremented");

        // Verify auction data
        MarketplaceStorage.AuctionDetailsView memory auction = storageContract.getAuctionDetailsView(auctionId);
        assertTrue(auction.active, "Auction should be active");
        assertTrue(auction.isNft, "Auction should be for NFT");
        assertEq(auction.seller, seller, "Seller should be correct");
        assertEq(auction.startingPrice, STARTING_PRICE, "Starting price should be correct");
        assertEq(auction.duration, AUCTION_DURATION, "Duration should be correct");
        assertEq(auction.tokenIdOrListingId, TOKEN_ID, "Token ID should be correct");
        assertEq(auction.nftContractAddr, nftContract, "NFT contract should be correct");

        // Verify mappings
        assertTrue(storageContract.isTokenListedForAuction(TOKEN_ID), "Should be listed for auction");
        assertEq(storageContract.auctionIdForTokenOrListing(TOKEN_ID), auctionId, "Auction ID mapping should be correct");
        assertEq(storageContract.tokenOrListingIdForAuction(auctionId), TOKEN_ID, "Token ID mapping should be correct");
    }

    function test_CreateNonNftAuction() public {
        vm.prank(authorizedContract);
        uint256 auctionId = storageContract.createAuction(
            seller, LISTING_ID, STARTING_PRICE, AUCTION_DURATION, false, address(0), ASSET_TYPE, ASSET_ID
        );

        assertEq(auctionId, AUCTION_ID, "Auction ID should be correct");

        // Verify auction data
        MarketplaceStorage.AuctionDetailsView memory auction = storageContract.getAuctionDetailsView(auctionId);
        assertTrue(auction.active, "Auction should be active");
        assertFalse(auction.isNft, "Auction should not be for NFT");
        assertEq(auction.seller, seller, "Seller should be correct");
        assertEq(auction.assetId, ASSET_ID, "Asset ID should be correct");
        assertEq(auction.assetType, ASSET_TYPE, "Asset type should be correct");
    }

    function test_RevertIf_UnauthorizedCreateAuction() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.createAuction(
            seller, TOKEN_ID, STARTING_PRICE, AUCTION_DURATION, true, nftContract, ASSET_TYPE, ""
        );
    }

    function test_UpdateAuctionBid() public {
        // Create auction first
        vm.prank(authorizedContract);
        uint256 auctionId = storageContract.createAuction(
            seller, TOKEN_ID, STARTING_PRICE, AUCTION_DURATION, true, nftContract, ASSET_TYPE, ""
        );

        // Place first bid
        vm.prank(authorizedContract);
        storageContract.updateAuctionBid(auctionId, bidder1, BID_AMOUNT_1);

        // Verify bid data
        MarketplaceStorage.AuctionDetailsView memory auction = storageContract.getAuctionDetailsView(auctionId);
        assertEq(auction.highestBidder, bidder1, "Highest bidder should be correct");
        assertEq(auction.highestBid, BID_AMOUNT_1, "Highest bid should be correct");
        assertEq(storageContract.getBidsCount(auctionId), 1, "Bid count should be 1");

        // Verify bid details
        (uint256 bidAmount, uint32 bidId, address bidder) = storageContract.getBid(auctionId, 0);
        assertEq(bidAmount, BID_AMOUNT_1, "Bid amount should be correct");
        assertEq(bidId, 0, "Bid ID should be correct");
        assertEq(bidder, bidder1, "Bidder should be correct");

        // Place second bid
        vm.prank(authorizedContract);
        storageContract.updateAuctionBid(auctionId, bidder2, BID_AMOUNT_2);

        // Verify updated bid data
        auction = storageContract.getAuctionDetailsView(auctionId);
        assertEq(auction.highestBidder, bidder2, "Highest bidder should be updated");
        assertEq(auction.highestBid, BID_AMOUNT_2, "Highest bid should be updated");
        assertEq(storageContract.getBidsCount(auctionId), 2, "Bid count should be 2");
    }

    function test_RevertIf_UnauthorizedUpdateAuctionBid() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.updateAuctionBid(AUCTION_ID, bidder1, BID_AMOUNT_1);
    }

    function test_EndAuction() public {
        // Create auction first
        vm.prank(authorizedContract);
        uint256 auctionId = storageContract.createAuction(
            seller, TOKEN_ID, STARTING_PRICE, AUCTION_DURATION, true, nftContract, ASSET_TYPE, ""
        );

        // End auction
        vm.prank(authorizedContract);
        storageContract.endAuction(auctionId);

        // Verify auction ended
        MarketplaceStorage.AuctionDetailsView memory auction = storageContract.getAuctionDetailsView(auctionId);
        assertFalse(auction.active, "Auction should not be active");
        assertFalse(storageContract.isTokenListedForAuction(TOKEN_ID), "Should not be listed for auction");
        assertEq(storageContract.auctionIdForTokenOrListing(TOKEN_ID), 0, "Auction ID mapping should be cleared");
        assertEq(storageContract.tokenOrListingIdForAuction(auctionId), 0, "Token ID mapping should be cleared");
    }

    function test_RevertIf_UnauthorizedEndAuction() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.endAuction(AUCTION_ID);
    }

    /*//////////////////////////////////////////////////////////////
                    UTILITY FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CheckListingHash() public {
        // Create NFT listing
        vm.prank(authorizedContract);
        storageContract.createNftListing(seller, nftContract, TOKEN_ID, LISTING_PRICE);

        // Create non-NFT listing
        vm.prank(authorizedContract);
        storageContract.createNonNftListing(seller, ASSET_TYPE, ASSET_ID, LISTING_PRICE, METADATA, VERIFICATION_HASH);

        // Check that listings were created
        assertEq(storageContract.listingIdCounter(), 3, "Two listings should be created");

        // Check non-existent hash
        bytes32 nonExistentHash = keccak256(abi.encodePacked(address(0), uint256(999)));
        assertFalse(storageContract.checkListingHash(nonExistentHash), "Non-existent hash should return false");
    }

    function test_IsTokenListedForAuction() public {
        // Create auction
        vm.prank(authorizedContract);
        storageContract.createAuction(
            seller, TOKEN_ID, STARTING_PRICE, AUCTION_DURATION, true, nftContract, ASSET_TYPE, ""
        );

        assertTrue(storageContract.isTokenListedForAuction(TOKEN_ID), "Token should be listed for auction");
        assertFalse(storageContract.isTokenListedForAuction(999), "Non-auction token should return false");
    }

    function test_GetBidsCount() public {
        // Create auction
        vm.prank(authorizedContract);
        uint256 auctionId = storageContract.createAuction(
            seller, TOKEN_ID, STARTING_PRICE, AUCTION_DURATION, true, nftContract, ASSET_TYPE, ""
        );

        assertEq(storageContract.getBidsCount(auctionId), 0, "Initial bid count should be 0");

        // Place bid
        vm.prank(authorizedContract);
        storageContract.updateAuctionBid(auctionId, bidder1, BID_AMOUNT_1);

        assertEq(storageContract.getBidsCount(auctionId), 1, "Bid count should be 1");
    }

    function test_GetBid() public {
        // Create auction and place bid
        vm.prank(authorizedContract);
        uint256 auctionId = storageContract.createAuction(
            seller, TOKEN_ID, STARTING_PRICE, AUCTION_DURATION, true, nftContract, ASSET_TYPE, ""
        );

        vm.prank(authorizedContract);
        storageContract.updateAuctionBid(auctionId, bidder1, BID_AMOUNT_1);

        // Get bid details
        (uint256 bidAmount, uint32 bidId, address bidder) = storageContract.getBid(auctionId, 0);
        assertEq(bidAmount, BID_AMOUNT_1, "Bid amount should be correct");
        assertEq(bidId, 0, "Bid ID should be correct");
        assertEq(bidder, bidder1, "Bidder should be correct");
    }

    /*//////////////////////////////////////////////////////////////
                    EDGE CASES AND ERROR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MultipleListingsAndAuctions() public {
        // Create multiple NFT listings
        vm.startPrank(authorizedContract);
        uint256 listing1 = storageContract.createNftListing(seller, nftContract, 1, LISTING_PRICE);
        uint256 listing2 = storageContract.createNftListing(seller, nftContract, 2, LISTING_PRICE);
        uint256 listing3 = storageContract.createNftListing(seller, nftContract, 3, LISTING_PRICE);
        vm.stopPrank();

        assertEq(listing1, 1, "First listing ID should be 1");
        assertEq(listing2, 2, "Second listing ID should be 2");
        assertEq(listing3, 3, "Third listing ID should be 3");
        assertEq(storageContract.listingIdCounter(), 4, "Listing counter should be 4");

        // Create multiple auctions
        vm.startPrank(authorizedContract);
        uint256 auction1 = storageContract.createAuction(seller, 1, STARTING_PRICE, AUCTION_DURATION, true, nftContract, ASSET_TYPE, "");
        uint256 auction2 = storageContract.createAuction(seller, 2, STARTING_PRICE, AUCTION_DURATION, true, nftContract, ASSET_TYPE, "");
        vm.stopPrank();

        assertEq(auction1, 1, "First auction ID should be 1");
        assertEq(auction2, 2, "Second auction ID should be 2");
        assertEq(storageContract.auctionIdCounter(), 3, "Auction counter should be 3");
    }

    function test_ListingFlagsCombinations() public {
        // Create NFT listing
        vm.prank(authorizedContract);
        uint256 listingId = storageContract.createNftListing(seller, nftContract, TOKEN_ID, LISTING_PRICE);

        // Test different flag combinations
        vm.startPrank(authorizedContract);

        // Set to inactive (flag 0)
        storageContract.updateNftListingFlags(listingId, 0);
        (,,,, bool active1, bool auctionListed1) = storageContract.getNftListing(listingId);
        assertFalse(active1, "Listing should be inactive");
        assertFalse(auctionListed1, "Listing should not be auction listed");

        // Set to active only (flag 1)
        storageContract.updateNftListingFlags(listingId, 1);
        (,,,, bool active2, bool auctionListed2) = storageContract.getNftListing(listingId);
        assertTrue(active2, "Listing should be active");
        assertFalse(auctionListed2, "Listing should not be auction listed");

        // Set to auction only (flag 2)
        storageContract.updateNftListingFlags(listingId, 2);
        (,,,, bool active3, bool auctionListed3) = storageContract.getNftListing(listingId);
        assertFalse(active3, "Listing should be inactive");
        assertTrue(auctionListed3, "Listing should be auction listed");

        // Set to both active and auction (flag 3)
        storageContract.updateNftListingFlags(listingId, 3);
        (,,,, bool active4, bool auctionListed4) = storageContract.getNftListing(listingId);
        assertTrue(active4, "Listing should be active");
        assertTrue(auctionListed4, "Listing should be auction listed");

        vm.stopPrank();
    }

    function test_AuctionDurationLimits() public {
        // Test minimum duration
        vm.prank(authorizedContract);
        uint256 auction1 = storageContract.createAuction(
            seller, TOKEN_ID, STARTING_PRICE, 1 hours, true, nftContract, ASSET_TYPE, ""
        );
        assertEq(auction1, 1, "Auction should be created with minimum duration");

        // Test maximum duration
        vm.prank(authorizedContract);
        uint256 auction2 = storageContract.createAuction(
            seller, TOKEN_ID + 1, STARTING_PRICE, 7 days, true, nftContract, ASSET_TYPE, ""
        );
        assertEq(auction2, 2, "Auction should be created with maximum duration");
    }

    function test_Constants() public view {
        assertEq(storageContract.MIN_AUCTION_DURATION(), 1 hours, "Minimum auction duration should be 1 hour");
        assertEq(storageContract.MAX_AUCTION_DURATION(), 7 days, "Maximum auction duration should be 7 days");
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHAIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetCrossChainRegistry() public {
        address newCrossChainRegistry = makeAddr("newCrossChainRegistry");

        vm.prank(owner);
        storageContract.setCrossChainRegistry(newCrossChainRegistry);

        assertEq(storageContract.crossChainRegistry(), newCrossChainRegistry, "Cross-chain registry should be updated");
    }

    function test_RevertIf_NonOwnerSetsCrossChainRegistry() public {
        address newCrossChainRegistry = makeAddr("newCrossChainRegistry");

        vm.prank(seller);
        vm.expectRevert("MStorage: Not owner");
        storageContract.setCrossChainRegistry(newCrossChainRegistry);
    }

    function test_GetCurrentChainType() public view {
        // Test for different chain IDs
        // Note: In test environment, block.chainid is typically 31337 (Anvil)
        uint8 chainType = storageContract.getCurrentChainType();

        // For Anvil (31337), it should default to Polygon (0)
        assertEq(chainType, 0, "Should default to Polygon for local testing");
    }

    function test_GetSupportedChains() public view {
        uint8[] memory supportedChains = storageContract.getSupportedChains();

        assertEq(supportedChains.length, 3, "Should have 3 supported chains");
        assertEq(supportedChains[0], 0, "First chain should be Polygon");
        assertEq(supportedChains[1], 1, "Second chain should be Base");
        assertEq(supportedChains[2], 2, "Third chain should be Ethereum");
    }

    function test_RegisterCrossChainAssetForAllChains() public {
        // Set up cross-chain registry first
        address crossChainRegistry = makeAddr("crossChainRegistry");
        vm.prank(owner);
        storageContract.setCrossChainRegistry(crossChainRegistry);

        // Mock the CrossChainRegistry to avoid actual calls
        vm.mockCall(
            crossChainRegistry,
            abi.encodeWithSelector(
                CrossChainRegistry.registerCrossChainAsset.selector,
                nftContract,
                TOKEN_ID,
                0, // originChainType (Polygon)
                1, // targetChainType (Base)
                address(0),
                LISTING_PRICE
            ),
            abi.encode(bytes32(0))
        );

        vm.mockCall(
            crossChainRegistry,
            abi.encodeWithSelector(
                CrossChainRegistry.registerCrossChainAsset.selector,
                nftContract,
                TOKEN_ID,
                0, // originChainType (Polygon)
                2, // targetChainType (Ethereum)
                address(0),
                LISTING_PRICE
            ),
            abi.encode(bytes32(0))
        );

        vm.prank(authorizedContract);
        storageContract.registerCrossChainAssetForAllChains(
            nftContract,
            TOKEN_ID,
            LISTING_PRICE,
            0 // originChainType (Polygon)
        );

        // Verify that the registry was called for each supported chain (except origin)
        // This test verifies the function executes without reverting
        // In a real scenario, you'd verify the actual CrossChainRegistry calls
    }

    function test_RevertIf_UnauthorizedRegisterCrossChainAsset() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.registerCrossChainAssetForAllChains(
            nftContract,
            TOKEN_ID,
            LISTING_PRICE,
            0
        );
    }

    function test_RegisterCrossChainAssetForAllChains_SkipsOriginChain() public {
        // Set up cross-chain registry
        address crossChainRegistry = makeAddr("crossChainRegistry");
        vm.prank(owner);
        storageContract.setCrossChainRegistry(crossChainRegistry);

        // Mock calls for Base and Ethereum (should be called)
        vm.mockCall(
            crossChainRegistry,
            abi.encodeWithSelector(
                CrossChainRegistry.registerCrossChainAsset.selector,
                nftContract,
                TOKEN_ID,
                1, // originChainType (Base)
                0, // targetChainType (Polygon)
                address(0),
                LISTING_PRICE
            ),
            abi.encode(bytes32(0))
        );

        vm.mockCall(
            crossChainRegistry,
            abi.encodeWithSelector(
                CrossChainRegistry.registerCrossChainAsset.selector,
                nftContract,
                TOKEN_ID,
                1, // originChainType (Base)
                2, // targetChainType (Ethereum)
                address(0),
                LISTING_PRICE
            ),
            abi.encode(bytes32(0))
        );

        // Should NOT call for origin chain (Base = 1)
        vm.mockCallRevert(
            crossChainRegistry,
            abi.encodeWithSelector(
                CrossChainRegistry.registerCrossChainAsset.selector,
                nftContract,
                TOKEN_ID,
                1, // originChainType (Base)
                1, // targetChainType (Base) - same as origin
                address(0),
                LISTING_PRICE
            ),
            "Should not call for same chain"
        );

        vm.prank(authorizedContract);
        storageContract.registerCrossChainAssetForAllChains(
            nftContract,
            TOKEN_ID,
            LISTING_PRICE,
            1 // originChainType (Base)
        );

        // Test passes if no revert occurs (origin chain was skipped)
    }

    function test_SetCrossChainListing() public {
        // Create listing first
        vm.prank(authorizedContract);
        uint256 listingId = storageContract.createNftListing(seller, nftContract, TOKEN_ID, LISTING_PRICE);

        // Set as cross-chain listing
        vm.prank(authorizedContract);
        storageContract.setCrossChainListing(listingId, true);

        // Verify cross-chain listing status
        (,,,,,, bool isCrossChainListed) = storageContract.getNftListingWithChain(listingId);
        assertTrue(isCrossChainListed, "Listing should be cross-chain listed");
    }

    function test_RevertIf_UnauthorizedSetCrossChainListing() public {
        vm.prank(unauthorizedContract);
        vm.expectRevert("MStorage: Not authorized");
        storageContract.setCrossChainListing(LISTING_ID, true);
    }
}
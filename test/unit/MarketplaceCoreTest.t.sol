// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MarketplaceCore} from "../../src/MarketplaceCore.sol";
import {MarketplaceAuctions} from "../../src/MarketplaceAuctions.sol";
import {VertixNFT} from "../../src/VertixNFT.sol";
import {MarketplaceStorage} from "../../src/MarketplaceStorage.sol";
import {VertixGovernance} from "../../src/VertixGovernance.sol";
import {VertixEscrow} from "../../src/VertixEscrow.sol";

contract MarketplaceCoreTest is Test {
    // The main entry point for Marketplace logic
    MarketplaceCore public marketplace; // This will be the MarketplaceProxy address, cast to MarketplaceCore

    MarketplaceAuctions public marketplaceAuctions; // MarketplaceProxy cast to MarketplaceAuctions
    VertixNFT public vertixNFT;
    MarketplaceStorage public marketplaceStorage;
    VertixGovernance public vertixGovernance;
    VertixEscrow public vertixEscrow;

    address public owner; // Will be set from deployerKey
    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");
    address public user = makeAddr("user");

    // All deployed contract addresses
    DeployVertix.VertixAddresses internal vertixAddresses;

    uint256 public constant TOKEN_ID = 1;
    uint96 public constant PRICE = 1 ether;
    uint96 public constant ROYALTY_BPS = 500; // 5%
    string public constant TOKEN_URI = "https://example.com/token/1";
    bytes32 public constant METADATA_HASH = keccak256("metadata");

    event NFTListed(
        uint256 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price
    );

        event NonNFTListed(
        uint256 indexed listingId,
        address indexed seller,
        uint8 assetType,
        string assetId,
        uint96 price
    );

    event NFTBought(
        uint256 indexed listingId,
        address indexed buyer,
        uint96 price,
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
        HelperConfig helperConfig = new HelperConfig();
        (address verificationServer, address feeRecipient, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        owner = vm.addr(deployerKey);

        vm.startPrank(owner);
        DeployVertix deployer = new DeployVertix();
        vertixAddresses = deployer.deployVertix();
        vm.stopPrank();

        // Assign the proxy address, cast to MarketplaceCore for interacting with core functions
        marketplace = MarketplaceCore(payable(vertixAddresses.marketplaceProxy));
        // Also assign the proxy address, cast to MarketplaceAuctions for interacting with auction functions
        marketplaceAuctions = MarketplaceAuctions(payable(vertixAddresses.marketplaceProxy));

        // Assign other contract instances for full test environment
        vertixNFT = VertixNFT(vertixAddresses.nft);
        marketplaceStorage = MarketplaceStorage(vertixAddresses.marketplaceStorage);
        vertixGovernance = VertixGovernance(vertixAddresses.governance);
        vertixEscrow = VertixEscrow(vertixAddresses.escrow);

        // Fund test accounts
        vm.deal(buyer, 10 ether);
        vm.deal(seller, 1 ether);
        vm.deal(user, 1 ether);

        vm.prank(seller); // Owner of NFT contract
        vertixNFT.mintSingleNFT(seller, TOKEN_URI, METADATA_HASH, ROYALTY_BPS);
    }

    /*//////////////////////////////////////////////////////////////
                           NFT LISTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ListNFT_Success() public {
        vm.startPrank(seller);
        vertixNFT.approve(address(marketplace), TOKEN_ID);

        vm.expectEmit(true, true, false, true);
        emit NFTListed(1, seller, address(vertixNFT), TOKEN_ID, PRICE);

        marketplace.listNFT(address(vertixNFT), TOKEN_ID, PRICE);
        vm.stopPrank();

        // Verify listing
        (
            address listingSeller,
            address nftContractAddr,
            uint256 tokenId,
            uint96 price,
            bool active,
        ) = marketplaceStorage.getNFTListing(1);
        assertEq(listingSeller, seller);
        assertEq(nftContractAddr, address(vertixNFT));
        assertEq(tokenId, TOKEN_ID);
        assertEq(price, PRICE);
        assertEq(active, true); // Active listing , 0); // No flags set

        // Verify NFT transferred to marketplace
        assertEq(vertixNFT.ownerOf(TOKEN_ID), address(marketplace));
    }

}
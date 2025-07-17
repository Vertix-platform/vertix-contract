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
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";


contract MarketplaceFeesTest is Test {
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
        // Test variables
    uint256 public constant SALE_PRICE = 1 ether;
    uint16 public constant PLATFORM_FEE_BPS = 100; // 1%
    uint256 public constant ROYALTY_BPS = 500; // 5%
    uint256 public constant HIGHEST_BID = 1.5 ether;
    uint256 public constant STARTING_PRICE = 0.5 ether;

    // Events
    // Events
    event FeesDistributed(
        uint256 indexed salePrice,
        uint256 platformFee,
        uint256 royaltyAmount,
        address platformRecipient,
        address royaltyRecipient,
        address seller
    );
    event EscrowDeposit(
        uint256 indexed listingId,
        uint256 amount,
        address seller,
        address buyer
    );


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

        // Mock VertixNFT to support IERC2981 royalties
        vm.mockCall(
            address(vertixNFT),
            abi.encodeWithSelector(IERC2981.royaltyInfo.selector, TOKEN_ID, SALE_PRICE),
            abi.encode(owner, (SALE_PRICE * ROYALTY_BPS) / 10000)
        );

        // Add verification server as a signer
        // Use the same method as HelperConfig to generate the verification server key
        verificationServerKey = uint256(keccak256(abi.encodePacked("verificationServer")));
        // Fund the verification server address
        vm.deal(verificationServer, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        FEE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CalculateNftFees() public  view{
        MarketplaceFees.FeeDistribution memory fees = marketplaceFees.calculateNftFees(SALE_PRICE, address(vertixNFT), TOKEN_ID);

        uint256 expectedPlatformFee = (SALE_PRICE * PLATFORM_FEE_BPS) / 10000;
        uint256 expectedRoyaltyAmount = (SALE_PRICE * ROYALTY_BPS) / 10000;
        uint256 expectedSellerAmount = SALE_PRICE - expectedPlatformFee - expectedRoyaltyAmount;

        assertEq(fees.platformFee, expectedPlatformFee, "Incorrect platform fee");
        assertEq(fees.royaltyAmount, expectedRoyaltyAmount, "Incorrect royalty amount");
        assertEq(fees.sellerAmount, expectedSellerAmount, "Incorrect seller amount");
        assertEq(fees.platformRecipient, feeRecipient, "Incorrect platform recipient");
        assertEq(fees.royaltyRecipient, owner, "Incorrect royalty recipient");
    }

    function test_RevertIf_NftFeesExceedSalePrice() public {
        // Mock high royalty to exceed sale price
        vm.mockCall(
            address(vertixNFT),
            abi.encodeWithSelector(IERC2981.royaltyInfo.selector, TOKEN_ID, SALE_PRICE),
            abi.encode(owner, SALE_PRICE)
        );

        vm.expectRevert(MarketplaceFees.MarketplaceFees__InvalidFeeConfig.selector);
        marketplaceFees.calculateNftFees(SALE_PRICE, address(vertixNFT), TOKEN_ID);
    }

    function test_CalculateNonNftFees() public view {
        MarketplaceFees.FeeDistribution memory fees = marketplaceFees.calculateNonNftFees(SALE_PRICE);

        uint256 expectedPlatformFee = (SALE_PRICE * PLATFORM_FEE_BPS) / 10000;
        uint256 expectedSellerAmount = SALE_PRICE - expectedPlatformFee;

        assertEq(fees.platformFee, expectedPlatformFee, "Incorrect platform fee");
        assertEq(fees.royaltyAmount, 0, "Royalty amount should be 0");
        assertEq(fees.sellerAmount, expectedSellerAmount, "Incorrect seller amount");
        assertEq(fees.platformRecipient, feeRecipient, "Incorrect platform recipient");
        assertEq(fees.royaltyRecipient, address(0), "Royalty recipient should be 0");
    }

    function test_RevertIf_NonNftFeesExceedSalePrice() public {
         uint16 maliciousFeeBps = 10001;
        // Mock the getFeeConfig call to return a feeBps that causes the revert
        vm.mockCall(
            address(governance),
            abi.encodeWithSelector(governance.getFeeConfig.selector),
            abi.encode(maliciousFeeBps, feeRecipient)
        );

        // Expect the transaction to revert with MarketplaceFees__InvalidFeeConfig
        vm.expectRevert(MarketplaceFees.MarketplaceFees__InvalidFeeConfig.selector);

        // Call the function that calculates non-NFT fees
        marketplaceFees.calculateNonNftFees(SALE_PRICE);
    }

    function test_CalculateMinimumBid() public view {
        uint256 minimumBid = marketplaceFees.calculateMinimumBid(STARTING_PRICE, 0);
        uint256 expectedPlatformFee = (STARTING_PRICE * PLATFORM_FEE_BPS) / 10000;
        uint256 expectedMinimumBid = STARTING_PRICE > expectedPlatformFee ? STARTING_PRICE : expectedPlatformFee;

        assertEq(minimumBid, expectedMinimumBid, "Incorrect minimum bid");

        // Test with existing highest bid
        minimumBid = marketplaceFees.calculateMinimumBid(STARTING_PRICE, HIGHEST_BID);
        assertEq(minimumBid, HIGHEST_BID + 1, "Incorrect minimum bid with highest bid");
    }

    /*//////////////////////////////////////////////////////////////
                        PAYMENT PROCESSING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ProcessNftSalePayment() public {
        uint256 totalPayment = 1.2 ether;

        uint256 expectedPlatformFee = (SALE_PRICE * PLATFORM_FEE_BPS) / 10000; // 0.01 ETH
        uint256 expectedRoyaltyAmount = (SALE_PRICE * ROYALTY_BPS) / 10000;   // 0.05 ETH
        uint256 expectedSellerAmount = SALE_PRICE - expectedPlatformFee - expectedRoyaltyAmount; // 1 - 0.01 - 0.05 = 0.94 ETH
        uint256 expectedRefund = totalPayment - SALE_PRICE; // 1.2 - 1 = 0.2 ETH

        uint256 initialBuyerBalance = buyer.balance;
        uint256 initialSellerBalance = seller.balance;
        uint256 initialFeeRecipientBalance = feeRecipient.balance;
        uint256 initialRoyaltyRecipientBalance = owner.balance; // Corrected: owner is the royalty recipient in this setup

        MarketplaceFees.PaymentConfig memory config = MarketplaceFees.PaymentConfig({
            totalPayment: totalPayment,
            salePrice: SALE_PRICE,
            nftContract: address(vertixNFT),
            tokenId: TOKEN_ID,
            seller: seller,
            hasRoyalties: true
        });

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit FeesDistributed(SALE_PRICE, expectedPlatformFee, expectedRoyaltyAmount, feeRecipient, owner, seller);

        uint256 refundAmount = marketplaceFees.processNftSalePayment{value: totalPayment}(config);

        assertEq(refundAmount, expectedRefund, "Refund amount mismatch");

        // Buyer's balance should be initial - totalPayment as the refund is returned by the function, not sent back directly.
        assertEq(buyer.balance, initialBuyerBalance - totalPayment, "Buyer balance mismatch");
        // Seller's balance: initial + expectedSellerAmount
        assertEq(seller.balance, initialSellerBalance + expectedSellerAmount, "Seller balance mismatch");
        // Fee recipient's balance: initial + expectedPlatformFee
        assertEq(feeRecipient.balance, initialFeeRecipientBalance + expectedPlatformFee, "Fee recipient balance mismatch");
        // Corrected: Royalty recipient's balance (owner)
        assertEq(owner.balance, initialRoyaltyRecipientBalance + expectedRoyaltyAmount, "Royalty recipient balance mismatch");
        // MarketplaceFees contract should hold the refund amount temporarily
        assertEq(address(marketplaceFees).balance, expectedRefund, "MarketplaceFees contract should hold the refund amount");
    }

    function test_ProcessNftSalePaymentWithExcessPayment() public {
        uint256 totalPayment = 1.5 ether;
        uint256 excessPayment = totalPayment - SALE_PRICE; // 0.5 ETH

        uint256 expectedPlatformFee = (SALE_PRICE * PLATFORM_FEE_BPS) / 10000; // 0.01 ETH
        uint256 expectedRoyaltyAmount = (SALE_PRICE * ROYALTY_BPS) / 10000;   // 0.05 ETH
        uint256 expectedSellerAmount = SALE_PRICE - expectedPlatformFee - expectedRoyaltyAmount; // 0.94 ETH

        uint256 initialBuyerBalance = buyer.balance;
        uint256 initialSellerBalance = seller.balance;
        uint256 initialFeeRecipientBalance = feeRecipient.balance;
        uint256 initialRoyaltyRecipientBalance = owner.balance;

        MarketplaceFees.PaymentConfig memory config = MarketplaceFees.PaymentConfig({
            totalPayment: totalPayment,
            salePrice: SALE_PRICE,
            nftContract: address(vertixNFT),
            tokenId: TOKEN_ID,
            seller: seller,
            hasRoyalties: true
        });

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit FeesDistributed(SALE_PRICE, expectedPlatformFee, expectedRoyaltyAmount, feeRecipient, owner, seller);

        uint256 refundAmount = marketplaceFees.processNftSalePayment{value: totalPayment}(config);

        assertEq(refundAmount, excessPayment, "Incorrect refund amount");
        assertEq(feeRecipient.balance, initialFeeRecipientBalance + expectedPlatformFee, "Incorrect platform fee transfer");
        assertEq(owner.balance, initialRoyaltyRecipientBalance + expectedRoyaltyAmount, "Incorrect royalty transfer");
        assertEq(seller.balance, initialSellerBalance + expectedSellerAmount, "Incorrect seller amount transfer");
        assertEq(buyer.balance, initialBuyerBalance - totalPayment, "Incorrect buyer balance after refund (before explicit refund call)");
        assertEq(address(marketplaceFees).balance, excessPayment, "MarketplaceFees contract should hold the excess payment");
    }

    function test_RevertIf_ProcessNftSalePaymentInsufficientPayment() public {
        MarketplaceFees.PaymentConfig memory config = MarketplaceFees.PaymentConfig({
            totalPayment: SALE_PRICE,
            salePrice: SALE_PRICE,
            nftContract: address(vertixNFT),
            tokenId: TOKEN_ID,
            seller: seller,
            hasRoyalties: true
        });

        vm.prank(buyer);
        vm.expectRevert(MarketplaceFees.MarketplaceFees__InsufficientPayment.selector);
        marketplaceFees.processNftSalePayment{value: SALE_PRICE - 1}(config);
    }

    function test_ProcessNonNftSalePayment() public {
        uint256 platformFee = (SALE_PRICE * PLATFORM_FEE_BPS) / 10000;
        uint256 escrowAmount = SALE_PRICE - platformFee;

        uint256 initialBuyerBalance = buyer.balance;
        uint256 initialFeeRecipientBalance = feeRecipient.balance;
        uint256 initialEscrowBalance = address(escrow).balance;
        uint256 initialSellerBalance = seller.balance; // Capture initial seller balance

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit FeesDistributed(SALE_PRICE, platformFee, 0, feeRecipient, address(0), seller);
        vm.expectEmit(true, true, true, true);
        emit EscrowDeposit(LISTING_ID, escrowAmount, seller, buyer);

        uint256 refundAmount = marketplaceFees.processNonNftSalePayment{value: SALE_PRICE}(LISTING_ID, SALE_PRICE, seller, buyer);

        assertEq(refundAmount, 0, "Incorrect refund amount");
        assertEq(feeRecipient.balance, initialFeeRecipientBalance + platformFee, "Incorrect platform fee transfer");
        assertEq(seller.balance, initialSellerBalance, "Seller balance should not change (escrow)"); // Seller's balance should remain the same as funds go to escrow
        assertEq(address(escrow).balance, initialEscrowBalance + escrowAmount, "Incorrect escrow deposit");
        assertEq(buyer.balance, initialBuyerBalance - SALE_PRICE, "Incorrect buyer balance after non-NFT sale");
    }

    function test_RevertIf_ProcessNonNftSalePaymentInsufficientPayment() public {
        vm.prank(buyer);
        vm.expectRevert(MarketplaceFees.MarketplaceFees__InsufficientPayment.selector);
        marketplaceFees.processNonNftSalePayment{value: SALE_PRICE - 1}(LISTING_ID, SALE_PRICE, seller, buyer);
    }

    function test_ProcessAuctionPayment_Nft() public {
        uint256 platformFee = (HIGHEST_BID * PLATFORM_FEE_BPS) / 10000;
        // Calculate royalty based on HIGHEST_BID for this specific test
        uint256 expectedRoyaltyAmount = (HIGHEST_BID * ROYALTY_BPS) / 10000;
        uint256 sellerAmount = HIGHEST_BID - platformFee - expectedRoyaltyAmount;

        uint256 initialBuyerBalance = buyer.balance;
        uint256 initialSellerBalance = seller.balance;
        uint256 initialFeeRecipientBalance = feeRecipient.balance;
        uint256 initialOwnerBalance = owner.balance; // Owner is royalty recipient

        // Mock IERC2981(vertixNFT).royaltyInfo() specifically for HIGHEST_BID in this test
        vm.mockCall(
            address(vertixNFT),
            abi.encodeWithSelector(IERC2981.royaltyInfo.selector, TOKEN_ID, HIGHEST_BID),
            abi.encode(owner, expectedRoyaltyAmount)
        );

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit FeesDistributed(HIGHEST_BID, platformFee, expectedRoyaltyAmount, feeRecipient, owner, seller);

        marketplaceFees.processAuctionPayment{value: HIGHEST_BID}(HIGHEST_BID, seller, address(vertixNFT), TOKEN_ID, true, LISTING_ID);

        assertEq(feeRecipient.balance, initialFeeRecipientBalance + platformFee, "Incorrect platform fee transfer");
        assertEq(owner.balance, initialOwnerBalance + expectedRoyaltyAmount, "Incorrect royalty transfer");
        assertEq(seller.balance, initialSellerBalance + sellerAmount, "Incorrect seller amount transfer");
        assertEq(buyer.balance, initialBuyerBalance - HIGHEST_BID, "Incorrect buyer balance after auction payment");
    }

    function test_ProcessAuctionPayment_NonNft() public {
        uint256 platformFee = (HIGHEST_BID * PLATFORM_FEE_BPS) / 10000;
        uint256 escrowAmount = HIGHEST_BID - platformFee;

        uint256 initialBuyerBalance = buyer.balance;
        uint256 initialSellerBalance = seller.balance;
        uint256 initialFeeRecipientBalance = feeRecipient.balance;
        uint256 initialEscrowBalance = address(escrow).balance;

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit FeesDistributed(HIGHEST_BID, platformFee, 0, feeRecipient, address(0), seller);
        vm.expectEmit(true, true, true, true);
        emit EscrowDeposit(LISTING_ID, escrowAmount, seller, buyer);

        marketplaceFees.processAuctionPayment{value: HIGHEST_BID}(HIGHEST_BID, seller, address(0), 0, false, LISTING_ID);

        assertEq(feeRecipient.balance, initialFeeRecipientBalance + platformFee, "Incorrect platform fee transfer");
        assertEq(seller.balance, initialSellerBalance, "Seller balance should not change (escrow)");
        assertEq(address(escrow).balance, initialEscrowBalance + escrowAmount, "Incorrect escrow deposit");
        assertEq(buyer.balance, initialBuyerBalance - HIGHEST_BID, "Incorrect buyer balance after non-NFT auction payment");
    }

    function test_RefundExcessPayment() public {
        uint256 excessAmount = 0.5 ether;
        uint256 initialBuyerBalance = buyer.balance;

        // To properly test this, we need to simulate the MarketplaceFees contract holding funds.
        // We'll use vm.deal to give the MarketplaceFees contract some ETH.
        vm.deal(address(marketplaceFees), excessAmount);

        // The refundExcessPayment function is designed to be called by an external entity (e.g., MarketplaceCore)
        // not by the MarketplaceFees contract itself. Prank with the owner (deployer) of the system.
        vm.startPrank(owner);
        marketplaceFees.refundExcessPayment(buyer, excessAmount);
        vm.stopPrank();

        assertEq(buyer.balance, initialBuyerBalance + excessAmount, "Incorrect buyer balance after refund");
        assertEq(address(marketplaceFees).balance, 0, "MarketplaceFees contract balance should be 0 after refund");
    }

    function test_RevertIf_SafeTransferEthFails() public {
        // Mock a failing ETH transfer
        address failingRecipient = address(new FailingRecipient());
        vm.prank(owner);
        governance.setFeeRecipient(failingRecipient);

        MarketplaceFees.PaymentConfig memory config = MarketplaceFees.PaymentConfig({
            totalPayment: SALE_PRICE,
            salePrice: SALE_PRICE,
            nftContract: address(vertixNFT),
            tokenId: TOKEN_ID,
            seller: seller,
            hasRoyalties: true
        });

        vm.prank(buyer);
        vm.expectRevert(MarketplaceFees.MarketplaceFees__TransferFailed.selector);
        marketplaceFees.processNftSalePayment{value: SALE_PRICE}(config);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetPlatformFeeConfig() public view {
        (uint256 feeBps, address recipient) = marketplaceFees.getPlatformFeeConfig();
        assertEq(feeBps, PLATFORM_FEE_BPS, "Incorrect platform fee BPS");
        assertEq(recipient, feeRecipient, "Incorrect fee recipient");
    }

    function test_PreviewNftFees() public view {
        (uint256 totalFees, uint256 platformFee, uint256 royaltyAmount, uint256 sellerReceives) =
            marketplaceFees.previewNftFees(SALE_PRICE, address(vertixNFT), TOKEN_ID);

        uint256 expectedPlatformFee = (SALE_PRICE * PLATFORM_FEE_BPS) / 10000;
        uint256 expectedRoyaltyAmount = (SALE_PRICE * ROYALTY_BPS) / 10000;
        uint256 expectedTotalFees = expectedPlatformFee + expectedRoyaltyAmount;
        uint256 expectedSellerReceives = SALE_PRICE - expectedTotalFees;

        assertEq(totalFees, expectedTotalFees, "Incorrect total fees");
        assertEq(platformFee, expectedPlatformFee, "Incorrect platform fee");
        assertEq(royaltyAmount, expectedRoyaltyAmount, "Incorrect royalty amount");
        assertEq(sellerReceives, expectedSellerReceives, "Incorrect seller receives");
    }

    function test_PreviewNonNftFees() public view {
        (uint256 totalFees, uint256 platformFee, uint256 sellerReceives) =
            marketplaceFees.previewNonNftFees(SALE_PRICE);

        uint256 expectedPlatformFee = (SALE_PRICE * PLATFORM_FEE_BPS) / 10000;
        uint256 expectedTotalFees = expectedPlatformFee;
        uint256 expectedSellerReceives = SALE_PRICE - expectedTotalFees;

        assertEq(totalFees, expectedTotalFees, "Incorrect total fees");
        assertEq(platformFee, expectedPlatformFee, "Incorrect platform fee");
        assertEq(sellerReceives, expectedSellerReceives, "Incorrect seller receives");
    }
}

// Mock contract to simulate a failing ETH transfer
contract FailingRecipient {
    receive() external payable {
        revert("Transfer failed");
    }
}

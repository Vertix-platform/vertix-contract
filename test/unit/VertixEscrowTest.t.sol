// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VertixEscrow} from "../../src/VertixEscrow.sol";
import {VertixEscrowV2Mock} from "../mocks/MockVertixEscrow.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";

contract VertixEscrowTest is Test {
    // DeployVertix script instance
    DeployVertix public deployer;

    // Contract addresses from deployment
    DeployVertix.VertixAddresses public vertixAddresses;

    // Contract instances
    VertixEscrow public escrow;
    VertixEscrow public escrowImplementation;

    address public owner;
    address public seller = makeAddr("seller");
    address public buyer = makeAddr("buyer");
    address public user = makeAddr("user");

    uint256 public constant LISTING_ID = 1;
    uint256 public constant AMOUNT = 1 ether;
    uint32 public constant NEW_ESCROW_DURATION = 14 days;

    event FundsLocked(
        uint256 indexed listingId, address indexed seller, address indexed buyer, uint96 amount, uint32 deadline
    );
    event FundsReleased(uint256 indexed listingId, address indexed recipient, uint256 amount);
    event DisputeRaised(uint256 indexed listingId);
    event DisputeResolved(uint256 indexed listingId, address indexed winner);

    function setUp() public {
        // Create deployer instance
        deployer = new DeployVertix();

        // Deploy all contracts using the DeployVertix script
        vertixAddresses = deployer.deployVertix();

        // Get the escrow contract instance
        escrow = VertixEscrow(vertixAddresses.escrow);

        // Get the owner from the governance contract (which owns the escrow)
        owner = address(vertixAddresses.governance);

        // Fund test accounts
        vm.deal(buyer, 10 ether);
        vm.deal(seller, 1 ether);
        vm.deal(user, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Helper function to get the escrow implementation address for upgrade testing
     */
    function getEscrowImplementation() internal returns (address) {
        // For upgrade testing, we need to deploy a new implementation
        // since the DeployVertix script doesn't expose the implementation address
        return address(new VertixEscrow());
    }

    /*//////////////////////////////////////////////////////////////
                    DEPLOYMENT VERIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeploymentVerification() public view {
        // Verify all contracts were deployed
        assertTrue(vertixAddresses.escrow != address(0), "Escrow not deployed");
        assertTrue(vertixAddresses.governance != address(0), "Governance not deployed");
        assertTrue(vertixAddresses.nft != address(0), "NFT not deployed");
        assertTrue(vertixAddresses.marketplaceProxy != address(0), "Marketplace proxy not deployed");
        assertTrue(vertixAddresses.marketplaceStorage != address(0), "Marketplace storage not deployed");
        assertTrue(vertixAddresses.crossChainRegistry != address(0), "Cross-chain registry not deployed");
        assertTrue(vertixAddresses.crossChainBridge != address(0), "Cross-chain bridge not deployed");

        // Verify escrow is properly initialized
        assertEq(escrow.owner(), owner, "Escrow owner should be governance");
        assertEq(escrow.escrowDuration(), 7 days, "Escrow duration should be 7 days");
        assertFalse(escrow.paused(), "Escrow should not be paused");
    }

    /*//////////////////////////////////////////////////////////////
                    INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialization() public view {
        assertEq(escrow.owner(), owner);
        assertEq(escrow.escrowDuration(), 7 days);
        assertEq(escrow.paused(), false);
    }

    function test_CannotReinitialize() public {
        vm.prank(owner);
        vm.expectRevert();
        escrow.initialize();
    }

    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        escrow.transferOwnership(newOwner);
        assertEq(escrow.owner(), newOwner);
        vm.prank(newOwner);
        escrow.pause();
        assertTrue(escrow.paused());
    }

    function test_RenounceOwnership() public {
        vm.prank(owner);
        escrow.renounceOwnership();
        assertEq(escrow.owner(), address(0));
        vm.prank(owner);
        vm.expectRevert();
        escrow.pause();
    }

    /*//////////////////////////////////////////////////////////////
                    LOCK FUNDS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LockFunds() public {
        vm.prank(buyer);

        vm.expectEmit(true, true, true, true);
        emit FundsLocked(LISTING_ID, seller, buyer, uint96(AMOUNT), uint32(block.timestamp + 7 days));

        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        VertixEscrow.Escrow memory escrowData = escrow.getEscrow(LISTING_ID);
        assertEq(escrowData.seller, seller);
        assertEq(escrowData.buyer, buyer);
        assertEq(escrowData.amount, AMOUNT);
        assertEq(escrowData.deadline, block.timestamp + 7 days);
        assertEq(escrowData.completed, false);
        assertEq(escrowData.disputed, false);
        assertEq(address(escrow).balance, AMOUNT);
    }

    function test_RevertIf_LockFundsWithZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert(VertixEscrow.VertixEscrow__IncorrectAmountSent.selector);
        escrow.lockFunds{value: 0}(LISTING_ID, seller, buyer);
    }

    function test_RevertIf_LockFundsWithExcessiveAmount() public {
        uint256 excessiveAmount = uint256(type(uint96).max) + 1;
        vm.deal(buyer, excessiveAmount);

        vm.prank(buyer);
        vm.expectRevert(VertixEscrow.VertixEscrow__IncorrectAmountSent.selector);
        escrow.lockFunds{value: excessiveAmount}(LISTING_ID, seller, buyer);
    }

    function test_RevertIf_LockFundsForExistingEscrow() public {
        // Lock funds first time
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Try to lock funds again for the same listing
        vm.prank(buyer);
        vm.expectRevert(VertixEscrow.VertixEscrow__EscrowAlreadyExists.selector);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);
    }

    function test_RevertIf_LockFundsWithZeroAddresses() public {
        vm.prank(buyer);
        vm.expectRevert(VertixEscrow.VertixEscrow__ZeroAddress.selector);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, address(0), buyer);

        vm.prank(buyer);
        vm.expectRevert(VertixEscrow.VertixEscrow__ZeroAddress.selector);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, address(0));
    }

    function test_RevertIf_LockFundsWhenPaused() public {
        vm.prank(owner);
        escrow.pause();

        vm.prank(buyer);
        vm.expectRevert();
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);
    }

    function test_LockFundsWithMaxAmount() public {
        uint96 maxAmount = type(uint96).max;
        vm.deal(buyer, maxAmount);
        vm.prank(buyer);
        escrow.lockFunds{value: maxAmount}(LISTING_ID, seller, buyer);
        VertixEscrow.Escrow memory escrowData = escrow.getEscrow(LISTING_ID);
        assertEq(escrowData.amount, maxAmount);
        assertEq(address(escrow).balance, maxAmount);
    }

    function test_LockFundsReducesBuyerBalance() public {
        uint256 initialBalance = buyer.balance;
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);
        assertEq(buyer.balance, initialBalance - AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                    CONFIRM TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/
    function test_ConfirmTransfer() public {
        vm.prank(buyer);
        uint256 initialBuyerBalance = buyer.balance;
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);
        uint256 initialSellerBalance = seller.balance; // 1

        // Confirm transfer
        vm.prank(buyer);

        vm.expectEmit(true, true, false, true);
        emit FundsReleased(LISTING_ID, seller, AMOUNT);

        escrow.confirmTransfer(LISTING_ID);

        // Verify funds were released
        assertEq(seller.balance, initialSellerBalance + AMOUNT, "Seller should receive funds");
        assertEq(initialBuyerBalance - AMOUNT, buyer.balance, "Funds were not released");

        // Verify escrow was deleted
        VertixEscrow.Escrow memory escrowData = escrow.getEscrow(LISTING_ID);
        assertEq(escrowData.seller, address(0));
        assertEq(escrowData.amount, 0);
    }

    function test_RevertIf_NonBuyerConfirmsTransfer() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Attempt to confirm as seller
        vm.prank(seller);
        vm.expectRevert(VertixEscrow.VertixEscrow__OnlyBuyerCanConfirm.selector);
        escrow.confirmTransfer(LISTING_ID);
    }

    function test_RevertIf_NonParticipantConfirmsTransfer() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Attempt to confirm as non-participant
        vm.prank(user);
        vm.expectRevert(VertixEscrow.VertixEscrow__NotEscrowParticipant.selector);
        escrow.confirmTransfer(LISTING_ID);
    }

    function test_RevertIf_ConfirmCompletedTransfer() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Complete the transfer
        vm.prank(buyer);
        escrow.confirmTransfer(LISTING_ID);

        // Try to confirm again
        vm.prank(buyer);
        vm.expectRevert(); // Should fail - escrow doesn't exist anymore
        escrow.confirmTransfer(LISTING_ID);
    }

    function test_RevertIf_ConfirmTransferInDispute() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Raise dispute
        vm.prank(buyer);
        escrow.raiseDispute(LISTING_ID);

        // Try to confirm
        vm.prank(buyer);
        vm.expectRevert(VertixEscrow.VertixEscrow__EscrowInDispute.selector);
        escrow.confirmTransfer(LISTING_ID);
    }

    function test_RevertIf_ConfirmTransferWhenPaused() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Pause the contract
        vm.prank(owner);
        escrow.pause();

        // Try to confirm
        vm.prank(buyer);
        vm.expectRevert();
        escrow.confirmTransfer(LISTING_ID);
    }

    /*//////////////////////////////////////////////////////////////
                    DISPUTE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RaiseDispute() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Raise dispute as buyer
        vm.prank(buyer);

        vm.expectEmit(true, false, false, false);
        emit DisputeRaised(LISTING_ID);

        escrow.raiseDispute(LISTING_ID);

        // Verify dispute state
        VertixEscrow.Escrow memory escrowData = escrow.getEscrow(LISTING_ID);
        assertTrue(escrowData.disputed);
    }

    function test_RaiseDisputeAsSeller() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Raise dispute as seller
        vm.prank(seller);
        vm.expectEmit(true, false, false, false);
        emit DisputeRaised(LISTING_ID);
        escrow.raiseDispute(LISTING_ID);

        VertixEscrow.Escrow memory escrowData = escrow.getEscrow(LISTING_ID);
        assertTrue(escrowData.disputed);
    }

    function test_RevertIf_NonParticipantRaisesDispute() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Attempt to raise dispute as non-participant
        vm.prank(user);
        vm.expectRevert(VertixEscrow.VertixEscrow__NotEscrowParticipant.selector);
        escrow.raiseDispute(LISTING_ID);
    }

    function test_RevertIf_RaiseDisputeOnCompletedEscrow() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Complete the transfer
        vm.prank(buyer);
        escrow.confirmTransfer(LISTING_ID);

        // Try to raise dispute
        vm.prank(buyer);
        /**
         * Can't use VertixEscrow.VertixEscrow__EscrowAlreadyCompleted.selector because after confirming transfer
         * the escrow is deleted, so escrow.completed can reach
         */
        vm.expectRevert();
        escrow.raiseDispute(LISTING_ID);
    }

    function test_RevertIf_RaiseDisputeAgain() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Raise dispute
        vm.prank(buyer);
        escrow.raiseDispute(LISTING_ID);

        // Try to raise again
        vm.prank(buyer);
        vm.expectRevert(VertixEscrow.VertixEscrow__DisputeAlreadyRaised.selector);
        escrow.raiseDispute(LISTING_ID);
    }

    function test_ResolveDisputeForBuyer() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        vm.prank(buyer);
        escrow.raiseDispute(LISTING_ID);

        uint256 initialBuyerBalance = buyer.balance;

        // Resolve dispute in buyer's favor
        vm.prank(owner);

        vm.expectEmit(true, true, false, true);
        emit FundsReleased(LISTING_ID, buyer, AMOUNT);

        vm.expectEmit(true, true, false, false);
        emit DisputeResolved(LISTING_ID, buyer);

        escrow.resolveDispute(LISTING_ID, buyer);

        // Verify funds were sent
        assertEq(buyer.balance, initialBuyerBalance + AMOUNT);

        // Verify escrow was deleted
        VertixEscrow.Escrow memory escrowData = escrow.getEscrow(LISTING_ID);
        assertEq(escrowData.seller, address(0));
    }

    function test_ResolveDisputeForSeller() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        vm.prank(seller);
        escrow.raiseDispute(LISTING_ID);

        uint256 initialSellerBalance = seller.balance;

        // Resolve dispute in seller's favor
        vm.prank(owner);
        escrow.resolveDispute(LISTING_ID, seller);

        // Verify funds were sent
        assertEq(seller.balance, initialSellerBalance + AMOUNT);
        // Verify escrow was deleted
        VertixEscrow.Escrow memory escrowData = escrow.getEscrow(LISTING_ID);
        assertEq(escrowData.seller, address(0));
    }

    function test_RevertIf_NonOwnerResolvesDispute() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        vm.prank(buyer);
        escrow.raiseDispute(LISTING_ID);

        // Try to resolve as non-owner
        vm.prank(user);
        vm.expectRevert();
        escrow.resolveDispute(LISTING_ID, buyer);
    }

    function test_RevertIf_ResolveNonExistentDispute() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Try to resolve without dispute
        vm.prank(owner);
        vm.expectRevert(VertixEscrow.VertixEscrow__NoActiveDispute.selector);
        escrow.resolveDispute(LISTING_ID, buyer);
    }

    function test_RevertIf_ResolveWithInvalidWinner() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        vm.prank(buyer);
        escrow.raiseDispute(LISTING_ID);

        // Try to resolve with invalid winner
        vm.prank(owner);
        vm.expectRevert(VertixEscrow.VertixEscrow__InvalidWinner.selector);
        escrow.resolveDispute(LISTING_ID, user);
    }

    function test_RevertIf_RaiseDisputeWhenPaused() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);
        vm.prank(owner);
        escrow.pause();
        vm.prank(buyer);
        vm.expectRevert();
        escrow.raiseDispute(LISTING_ID);
    }

    function test_RevertIf_ResolveDisputeWhenPaused() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);
        vm.prank(buyer);
        escrow.raiseDispute(LISTING_ID);
        vm.prank(owner);
        escrow.pause();
        vm.prank(owner);
        vm.expectRevert();
        escrow.resolveDispute(LISTING_ID, buyer);
    }

    function test_RevertIf_RaiseDisputeNonExistentEscrow() public {
        vm.prank(buyer);
        vm.expectRevert(VertixEscrow.VertixEscrow__NotEscrowParticipant.selector);
        escrow.raiseDispute(LISTING_ID);
    }

    /*//////////////////////////////////////////////////////////////
                    REFUND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Refund() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        uint256 initialBuyerBalance = buyer.balance;

        // Advance time past deadline
        vm.warp(block.timestamp + 8 days);

        // Refund
        vm.expectEmit(true, true, false, true);
        emit FundsReleased(LISTING_ID, buyer, AMOUNT);

        vm.prank(buyer);
        escrow.refund(LISTING_ID);

        // Verify funds were returned
        assertEq(buyer.balance, initialBuyerBalance + AMOUNT);

        // Verify escrow was deleted
        VertixEscrow.Escrow memory escrowData = escrow.getEscrow(LISTING_ID);
        assertEq(escrowData.seller, address(0));
    }

    function test_RevertIf_RefundBeforeDeadline() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Try to refund before deadline
        vm.expectRevert(VertixEscrow.VertixEscrow__DeadlineNotPassed.selector);
        escrow.refund(LISTING_ID);
    }

    function test_RevertIf_RefundCompletedEscrow() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Complete the escrow
        vm.prank(buyer);
        escrow.confirmTransfer(LISTING_ID);

        // Advance time past deadline
        vm.warp(block.timestamp + 8 days);

        // Try to refund
        vm.expectRevert(); // Should fail - escrow doesn't exist anymore
        escrow.refund(LISTING_ID);
    }

    function test_RevertIf_RefundDisputedEscrow() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);

        // Raise dispute
        vm.prank(buyer);
        escrow.raiseDispute(LISTING_ID);

        // Advance time past deadline
        vm.warp(block.timestamp + 8 days);

        // Try to refund
        vm.expectRevert(VertixEscrow.VertixEscrow__EscrowInDispute.selector);
        escrow.refund(LISTING_ID);
    }

    function test_RevertIf_RefundWhenPaused() public {
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);
        vm.prank(owner);
        escrow.pause();
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert();
        escrow.refund(LISTING_ID);
    }

    function test_RevertIf_RefundNonExistentEscrow() public {
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert(VertixEscrow.VertixEscrow__ZeroAddress.selector);
        escrow.refund(LISTING_ID);
    }

    /*//////////////////////////////////////////////////////////////
                    ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetEscrowDuration() public {
        vm.prank(owner);
        escrow.setEscrowDuration(NEW_ESCROW_DURATION);

        assertEq(escrow.escrowDuration(), NEW_ESCROW_DURATION);
    }

    function test_RevertIf_NonOwnerSetsEscrowDuration() public {
        vm.prank(user);
        vm.expectRevert();
        escrow.setEscrowDuration(NEW_ESCROW_DURATION);
    }

    function test_RevertIf_SetZeroEscrowDuration() public {
        vm.prank(owner);
        vm.expectRevert(VertixEscrow.VertixEscrow__InvalidDuration.selector);
        escrow.setEscrowDuration(0);
    }

    function test_SetMaxEscrowDuration() public {
        uint32 maxDuration = type(uint32).max;
        vm.prank(owner);
        escrow.setEscrowDuration(maxDuration);
        assertEq(escrow.escrowDuration(), maxDuration);
    }

    function test_PauseAndUnpause() public {
        // Pause
        vm.prank(owner);
        escrow.pause();
        assertTrue(escrow.paused());

        // Unpause
        vm.prank(owner);
        escrow.unpause();
        assertFalse(escrow.paused());
    }

    function test_EscrowDurationAffectsNewEscrows() public {
        vm.prank(owner);
        escrow.setEscrowDuration(NEW_ESCROW_DURATION);
        vm.prank(buyer);
        escrow.lockFunds{value: AMOUNT}(LISTING_ID, seller, buyer);
        VertixEscrow.Escrow memory escrowData = escrow.getEscrow(LISTING_ID);
        assertEq(escrowData.deadline, block.timestamp + NEW_ESCROW_DURATION);
    }

    function test_RevertIf_NonOwnerPausesOrUnpauses() public {
        vm.prank(user);
        vm.expectRevert();
        escrow.pause();

        vm.prank(owner);
        escrow.pause();

        vm.prank(user);
        vm.expectRevert();
        escrow.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                    UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade() public {
        // First deploy our mock upgraded implementation
        vm.startPrank(owner);
        VertixEscrowV2Mock newImplementation = new VertixEscrowV2Mock();

        // Get current escrow duration for comparison later
        uint32 originalDuration = escrow.escrowDuration();

        // Upgrade the proxy to point to the new implementation
        escrow.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();

        // Cast our proxy to the V2 interface to access new functions
        VertixEscrowV2Mock upgradedEscrow = VertixEscrowV2Mock(address(escrow));

        // Verify the upgrade was successful by:
        // Checking state was preserved
        assertEq(upgradedEscrow.escrowDuration(), originalDuration);
        assertEq(upgradedEscrow.owner(), owner);

        // Testing the new functionality from V2
        vm.prank(owner);
        upgradedEscrow.setNewFeature(100);
        assertEq(upgradedEscrow.getNewFeature(), 100);

        // Ensure original functionality still works
        vm.prank(owner);
        upgradedEscrow.setEscrowDuration(14 days);
        assertEq(upgradedEscrow.escrowDuration(), 14 days);
    }

    function test_RevertIf_NonOwnerUpgrades() public {
        // Deploy new implementation using helper function
        address newImplementation = getEscrowImplementation();

        // Try to upgrade as non-owner
        vm.prank(user);
        vm.expectRevert();
        escrow.upgradeToAndCall(newImplementation, "");
    }
}

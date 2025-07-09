// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VertixGovernance} from "../../src/VertixGovernance.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock implementation for V2 of the contract with additional functionality
contract VertixGovernanceV2Mock is VertixGovernance {
    bool public newFeatureEnabled;

    function enableNewFeature() external onlyOwner {
        newFeatureEnabled = true;
    }
}

contract VertixGovernanceTest is Test {
    VertixGovernance public governanceImplementation;
    VertixGovernance public governance;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public marketplace = makeAddr("marketplace");
    address public escrow = makeAddr("escrow");
    address public feeRecipient = makeAddr("feeRecipient");
    address public newFeeRecipient = makeAddr("newFeeRecipient");
    address public newMarketplace = makeAddr("newMarketplace");
    address public newEscrow = makeAddr("newEscrow");
    address public verificationServer = makeAddr("verificationServer");
    address public newServer = makeAddr("newServer");

    uint16 public constant DEFAULT_FEE_BPS = 100; // 1%
    uint16 public constant NEW_FEE_BPS = 200; // 2%
    uint16 public constant MAX_FEE_BPS = 1000; // 10%
    uint16 public constant INVALID_FEE_BPS = 1100; // 11%

    event PlatformFeeUpdated(uint16 oldFee, uint16 newFee);
    event FeeRecipientUpdated(address newRecipient);
    event MarketplaceUpdated(address newMarketplace);
    event EscrowUpdated(address newEscrow);
    event VerificationServerUpdated(address newServer);

    function setUp() public {
        vm.startPrank(owner);
        governanceImplementation = new VertixGovernance();

        // Deploy proxy and initialize
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(governanceImplementation),
            abi.encodeWithSelector(VertixGovernance.initialize.selector, marketplace, escrow, feeRecipient, verificationServer)
        );
        governance = VertixGovernance(address(proxy));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialization() public view {
        assertEq(governance.owner(), owner);

        (uint16 feeBps, address recipient) = governance.getFeeConfig();
        assertEq(feeBps, DEFAULT_FEE_BPS);
        assertEq(recipient, feeRecipient);

        (address marketplaceAddr, address escrowAddr) = governance.getContractAddresses();
        assertEq(marketplaceAddr, marketplace);
        assertEq(escrowAddr, escrow);

        address verificationServerAddr = governance.getVerificationServer();
        assertEq(verificationServerAddr, verificationServer);
    }

    function test_CannotReinitialize() public {
        vm.prank(owner);
        vm.expectRevert();
        governance.initialize(marketplace, escrow, feeRecipient, verificationServer);
    }

    function test_RevertIf_InitializeWithZeroAddresses() public {
        vm.startPrank(owner);

        // Test with zero escrow
        VertixGovernance newImplementation = new VertixGovernance();
        vm.expectRevert(VertixGovernance.VertixGovernance__ZeroAddress.selector);
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(newImplementation),
            abi.encodeWithSelector(VertixGovernance.initialize.selector, marketplace, address(0), feeRecipient, verificationServer)
        );

        // Test with zero verification server
        newImplementation = new VertixGovernance();
        vm.expectRevert(VertixGovernance.VertixGovernance__ZeroAddress.selector);
        proxy = new ERC1967Proxy(
            address(newImplementation),
            abi.encodeWithSelector(VertixGovernance.initialize.selector, marketplace, escrow, feeRecipient, address(0))
        );

        // Test with zero fee recipient
        newImplementation = new VertixGovernance();
        vm.expectRevert(VertixGovernance.VertixGovernance__ZeroAddress.selector);
        proxy = new ERC1967Proxy(
            address(newImplementation),
            abi.encodeWithSelector(VertixGovernance.initialize.selector, marketplace, escrow, address(0), verificationServer)
        );

        // Marketplace can be zero initially
        newImplementation = new VertixGovernance();
        proxy = new ERC1967Proxy(
            address(newImplementation),
            abi.encodeWithSelector(VertixGovernance.initialize.selector, address(0), escrow, feeRecipient, verificationServer)
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    PLATFORM FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetPlatformFee() public {
        vm.prank(owner);

        vm.expectEmit(false, false, false, true);
        emit PlatformFeeUpdated(DEFAULT_FEE_BPS, NEW_FEE_BPS);

        governance.setPlatformFee(NEW_FEE_BPS);

        (uint16 feeBps,) = governance.getFeeConfig();
        assertEq(feeBps, NEW_FEE_BPS);
    }

    function test_RevertIf_NonOwnerSetsPlatformFee() public {
        vm.prank(user);
        vm.expectRevert();
        governance.setPlatformFee(NEW_FEE_BPS);
    }

    function test_RevertIf_SetInvalidPlatformFee() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__InvalidFee.selector);
        governance.setPlatformFee(INVALID_FEE_BPS);
    }

    function test_RevertIf_SetSamePlatformFee() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__SameValue.selector);
        governance.setPlatformFee(DEFAULT_FEE_BPS);
    }

    /*//////////////////////////////////////////////////////////////
                    FEE RECIPIENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetFeeRecipient() public {
        vm.prank(owner);

        vm.expectEmit(false, false, false, true);
        emit FeeRecipientUpdated(newFeeRecipient);

        governance.setFeeRecipient(newFeeRecipient);

        (, address recipient) = governance.getFeeConfig();
        assertEq(recipient, newFeeRecipient);
    }

    function test_RevertIf_NonOwnerSetsFeeRecipient() public {
        vm.prank(user);
        vm.expectRevert();
        governance.setFeeRecipient(newFeeRecipient);
    }

    function test_RevertIf_SetZeroAddressFeeRecipient() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__ZeroAddress.selector);
        governance.setFeeRecipient(address(0));
    }

    function test_RevertIf_SetSameFeeRecipient() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__SameValue.selector);
        governance.setFeeRecipient(feeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                    MARKETPLACE ADDRESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetMarketplace() public {
        vm.prank(owner);

        vm.expectEmit(false, false, false, true);
        emit MarketplaceUpdated(newMarketplace);

        governance.setMarketplace(newMarketplace);

        (address marketplaceAddr,) = governance.getContractAddresses();
        assertEq(marketplaceAddr, newMarketplace);
    }

    function test_RevertIf_NonOwnerSetsMarketplace() public {
        vm.prank(user);
        vm.expectRevert();
        governance.setMarketplace(newMarketplace);
    }

    function test_RevertIf_SetZeroAddressMarketplace() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__ZeroAddress.selector);
        governance.setMarketplace(address(0));
    }

    function test_RevertIf_SetSameMarketplace() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__SameValue.selector);
        governance.setMarketplace(marketplace);
    }

    /*//////////////////////////////////////////////////////////////
                    ESCROW ADDRESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetEscrow() public {
        vm.prank(owner);

        vm.expectEmit(false, false, false, true);
        emit EscrowUpdated(newEscrow);

        governance.setEscrow(newEscrow);

        (, address escrowAddr) = governance.getContractAddresses();
        assertEq(escrowAddr, newEscrow);
    }

    function test_RevertIf_NonOwnerSetsEscrow() public {
        vm.prank(user);
        vm.expectRevert();
        governance.setEscrow(newEscrow);
    }

    function test_RevertIf_SetZeroAddressEscrow() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__ZeroAddress.selector);
        governance.setEscrow(address(0));
    }

    function test_RevertIf_SetSameEscrow() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__SameValue.selector);
        governance.setEscrow(escrow);
    }

    /*//////////////////////////////////////////////////////////////
                    VERIFICATION SERVER TESTS
    //////////////////////////////////////////////////////////////*/
    function test_SetVerificationServer() public {
        vm.prank(owner);

        vm.expectEmit(false, false, true, false);
        emit VerificationServerUpdated(newServer);

        governance.setVerificationServer(newServer);
        address server = governance.getVerificationServer();
        assertEq(server, newServer);
    }
    function test_RevertIf_NonOwnerSetsVerificationServer() public {
        vm.prank(user);
        vm.expectRevert();
        governance.setVerificationServer(verificationServer);
    }
    function test_RevertIf_SetZeroAddressVerificationServer() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__ZeroAddress.selector);
        governance.setVerificationServer(address(0));
    }
    function test_RevertIf_SetSameVerificationServer() public {
        vm.prank(owner);
        vm.expectRevert(VertixGovernance.VertixGovernance__SameValue.selector);
        governance.setVerificationServer(verificationServer);
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetFeeConfig() public view {
        (uint16 feeBps, address recipient) = governance.getFeeConfig();
        assertEq(feeBps, DEFAULT_FEE_BPS);
        assertEq(recipient, feeRecipient);
    }

    function test_GetContractAddresses() public view {
        (address marketplaceAddr, address escrowAddr) = governance.getContractAddresses();
        assertEq(marketplaceAddr, marketplace);
        assertEq(escrowAddr, escrow);
    }

    function test_GetVerificationServer() public view {
        address server = governance.getVerificationServer();
        assertEq(server, verificationServer);
    }

    /*//////////////////////////////////////////////////////////////
                    CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constants() public view {
        assertEq(governance.MAX_FEE_BPS(), MAX_FEE_BPS);
        assertEq(governance.DEFAULT_FEE_BPS(), DEFAULT_FEE_BPS);
    }

    /*//////////////////////////////////////////////////////////////
                    UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade() public {
        vm.startPrank(owner);
        VertixGovernanceV2Mock newImplementation = new VertixGovernanceV2Mock();

        // Get current fee config for comparison after upgrade
        (uint16 oldFeeBps, address oldFeeRecipient) = governance.getFeeConfig();
        (address oldMarketplace, address oldEscrow) = governance.getContractAddresses();
        address oldVerificationServer = governance.getVerificationServer();

        // Upgrade the proxy to point to the new implementation
        governance.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();

        // Cast our proxy to the V2 interface to access new functions
        VertixGovernanceV2Mock upgradedGovernance = VertixGovernanceV2Mock(address(governance));

        // Verify the upgrade was successful by:
        // Checking state was preserved
        (uint16 newFeeBps, address newFeeRecipientAddr) = upgradedGovernance.getFeeConfig();
        (address newMarketplaceAddr, address newEscrowAddr) = upgradedGovernance.getContractAddresses();
        address verificationServerAddr = upgradedGovernance.getVerificationServer();

        assertEq(newFeeBps, oldFeeBps);
        assertEq(newFeeRecipientAddr, oldFeeRecipient);
        assertEq(newMarketplaceAddr, oldMarketplace);
        assertEq(newEscrowAddr, oldEscrow);
        assertEq(verificationServerAddr, oldVerificationServer);
        assertEq(upgradedGovernance.owner(), owner);

        // Testing the new functionality from V2
        vm.prank(owner);
        upgradedGovernance.enableNewFeature();
        assertTrue(upgradedGovernance.newFeatureEnabled());

        // Ensure original functionality still works
        vm.prank(owner);
        upgradedGovernance.setPlatformFee(NEW_FEE_BPS);
        (uint16 updatedFeeBps,) = upgradedGovernance.getFeeConfig();
        assertEq(updatedFeeBps, NEW_FEE_BPS);
    }

    function test_RevertIf_NonOwnerUpgrades() public {
        // Deploy new implementation
        VertixGovernanceV2Mock newImplementation = new VertixGovernanceV2Mock();

        // Try to upgrade as non-owner
        vm.prank(user);
        vm.expectRevert();
        governance.upgradeToAndCall(address(newImplementation), "");
    }
}

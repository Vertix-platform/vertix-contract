// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VertixNFT} from "../src/VertixNFT.sol";
import {VertixGovernance} from "../src/VertixGovernance.sol";
import {VertixEscrow} from "../src/VertixEscrow.sol";
import {MarketplaceStorage} from "../src/MarketplaceStorage.sol"; // Import MarketplaceStorage
import {MarketplaceCore} from "../src/MarketplaceCore.sol";
import {MarketplaceAuctions} from "../src/MarketplaceAuctions.sol";
import {MarketplaceFees} from "../src/MarketplaceFees.sol";
import {MarketplaceProxy} from "../src/MarketplaceProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployVertix is Script {
    // Defines a structure to hold all deployed contract addresses for easy return and tracking.
    struct VertixAddresses {
        address nft;
        address governance;
        address escrow;
        address marketplaceProxy;
        address marketplaceCoreImpl;     // Store implementation address
        address marketplaceAuctionsImpl; // Store implementation address
        address marketplaceFees;
        address marketplaceStorage;      // Added MarketplaceStorage address
        address verificationServer;
        address feeRecipient;
    }

    /// @notice Deploys all Vertix contracts and links them appropriately.
    /// @param vertixAddresses A struct containing all deployed contract addresses.
    /// @return vertixAddresses The populated struct with all deployed contract addresses.
    function deployVertix() public returns (VertixAddresses memory vertixAddresses) {
        // Retrieve network-specific configurations.
        HelperConfig helperConfig = new HelperConfig();
        (address verificationServer, address feeRecipient, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        // Start broadcasting transactions from the deployer's key.
        vm.startBroadcast(deployerKey);

        // --- Step 1: Deploy MarketplaceStorage ---
        // MarketplaceStorage is a fundamental dependency and is not upgradeable itself in this setup.
        // It's deployed directly.
        address marketplaceStorage = address(new MarketplaceStorage(msg.sender)); // Pass deployer as initial owner
        vertixAddresses.marketplaceStorage = marketplaceStorage;
        console.log("MarketplaceStorage deployed at:", marketplaceStorage);

        // --- Step 2: Deploy VertixNFT (Implementation and Proxy) ---
        address vertixNftImpl = address(new VertixNFT());
        vertixAddresses.nft = deployProxy(
            vertixNftImpl,
            abi.encodeWithSelector(VertixNFT.initialize.selector, verificationServer),
            "VertixNFT"
        );

        // --- Step 3: Deploy Escrow (Implementation and Proxy) ---
        address escrowImpl = address(new VertixEscrow());
        vertixAddresses.escrow = deployProxy(
            escrowImpl,
            abi.encodeWithSelector(VertixEscrow.initialize.selector),
            "VertixEscrow"
        );

        // --- Step 4: Deploy VertixGovernance (Implementation and Proxy) ---
        // We temporarily pass address(0) for the marketplace and update it later.
        address governanceImpl = address(new VertixGovernance());
        vertixAddresses.governance = deployProxy(
            governanceImpl,
            abi.encodeWithSelector(
                VertixGovernance.initialize.selector,
                address(0), // Placeholder for marketplace proxy (will be set later)
                vertixAddresses.escrow,
                feeRecipient,
                verificationServer
            ),
            "VertixGovernance"
        );

        // --- Step 5: Deploy MarketplaceFees (Implementation) ---
        // MarketplaceFees takes governance and escrow in its constructor (immutable).
        // It's not proxied in this setup, as its logic is considered stable.
        address marketplaceFeesImpl = address(new MarketplaceFees(vertixAddresses.governance, vertixAddresses.escrow));
        vertixAddresses.marketplaceFees = marketplaceFeesImpl;
        console.log("MarketplaceFees deployed at:", vertixAddresses.marketplaceFees);


        // --- Step 6: Deploy MarketplaceCore *Implementation* ---
        // Its immutable dependencies (storage, fees, governance) are now known (their final addresses).
        address marketplaceCoreImpl = address(
            new MarketplaceCore(
                vertixAddresses.marketplaceStorage,
                vertixAddresses.marketplaceFees,
                vertixAddresses.governance
            )
        );
        vertixAddresses.marketplaceCoreImpl = marketplaceCoreImpl;
        console.log("MarketplaceCore implementation deployed at:", marketplaceCoreImpl);

        // --- Step 7: Deploy MarketplaceAuctions *Implementation* ---
        // Its immutable dependencies (storage, governance, escrow, fees) are now known.
        address marketplaceAuctionsImpl = address(
            new MarketplaceAuctions(
                vertixAddresses.marketplaceStorage,
                vertixAddresses.governance,
                vertixAddresses.escrow,
                vertixAddresses.marketplaceFees
            )
        );
        vertixAddresses.marketplaceAuctionsImpl = marketplaceAuctionsImpl;
        console.log("MarketplaceAuctions implementation deployed at:", marketplaceAuctionsImpl);

        // --- Step 8: Deploy the main MarketplaceProxy ---
        // This proxy points to the *implementations* of Core and Auctions.
        vertixAddresses.marketplaceProxy = address(new MarketplaceProxy(marketplaceCoreImpl, marketplaceAuctionsImpl));
        console.log("Main MarketplaceProxy deployed at:", vertixAddresses.marketplaceProxy);

        // --- Step 9: Call `initialize` on MarketplaceCore and MarketplaceAuctions *through the MarketplaceProxy*. ---
        // This is crucial for OpenZeppelin upgradeable contracts to set up their internal state
        // (like Pausable and ReentrancyGuard) within the proxy's storage context.
        // We cast the proxy address to the interface of the implementation.
        // The `payable()` cast is necessary because MarketplaceCore/Auctions have payable functions (e.g., fallback/receive implicitly from ReentrancyGuardUpgradeable).
        MarketplaceCore(payable(vertixAddresses.marketplaceProxy)).initialize();
        console.log("MarketplaceCore initialized via proxy.");
        MarketplaceAuctions(payable(vertixAddresses.marketplaceProxy)).initialize();
        console.log("MarketplaceAuctions initialized via proxy.");

        // --- Step 10: Set essential contracts in MarketplaceStorage ---
        // Authorize the deployed marketplace proxy and the core/auctions implementations if needed
        // The `setContracts` in MarketplaceStorage needs to be called by its owner.
        // In this script, `msg.sender` (the deployer) is the owner of MarketplaceStorage.
        MarketplaceStorage(marketplaceStorage).setContracts(
            vertixAddresses.nft,             // VertixNFT proxy
            vertixAddresses.governance,      // VertixGovernance proxy
            vertixAddresses.escrow           // Escrow proxy
        );
        console.log("MarketplaceStorage essential contracts set.");

        // Authorize MarketplaceCore and MarketplaceAuctions implementations in MarketplaceStorage
        // This allows them to call `onlyAuthorized` functions in storage.
        MarketplaceStorage(marketplaceStorage).authorizeContract(vertixAddresses.marketplaceCoreImpl, true);
        MarketplaceStorage(marketplaceStorage).authorizeContract(vertixAddresses.marketplaceAuctionsImpl, true);
        console.log("MarketplaceCore and MarketplaceAuctions implementations authorized in Storage.");


        // --- Step 11: Update VertixGovernance with the main marketplace proxy address. ---
        // This is done via the Governance proxy.
        VertixGovernance(vertixAddresses.governance).setMarketplace(vertixAddresses.marketplaceProxy);
        console.log("VertixGovernance marketplace set to:", vertixAddresses.marketplaceProxy);

        // --- Step 12: Transfer Escrow ownership to governance. ---
        // This is done via the Escrow proxy.
        VertixEscrow(vertixAddresses.escrow).transferOwnership(vertixAddresses.governance);
        console.log("Escrow ownership transferred to:", vertixAddresses.governance);

        // Stop broadcasting transactions.
        vm.stopBroadcast();

        // Return all deployed addresses.
        vertixAddresses.verificationServer = verificationServer;
        vertixAddresses.feeRecipient = feeRecipient;
        return vertixAddresses;
    }

    /// @notice Helper function to deploy an ERC1967Proxy for an implementation contract.
    /// @param impl The address of the implementation contract.
    /// @param initData The encoded call to the `initialize` function (or constructor) of the implementation.
    /// @param name A descriptive name for logging.
    /// @return proxy The address of the deployed proxy.
    function deployProxy(address impl, bytes memory initData, string memory name) internal returns (address proxy) {
        console.log(string.concat(name, " implementation deployed at:"), impl);
        proxy = address(new ERC1967Proxy(impl, initData));
        console.log(string.concat(name, " proxy deployed at:"), proxy);
        return proxy;
    }

    /// @notice Entry point for the Forge script.
    function run() external returns (VertixAddresses memory) {
        return deployVertix();
    }
}
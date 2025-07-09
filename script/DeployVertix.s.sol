// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VertixNFT} from "../src/VertixNFT.sol";
import {VertixGovernance} from "../src/VertixGovernance.sol";
import {VertixEscrow} from "../src/VertixEscrow.sol"; // Using VertixEscrow as per your trace
import {MarketplaceStorage} from "../src/MarketplaceStorage.sol"; // Import MarketplaceStorage
import {MarketplaceCore} from "../src/MarketplaceCore.sol";
import {MarketplaceAuctions} from "../src/MarketplaceAuctions.sol";
import {MarketplaceFees} from "../src/MarketplaceFees.sol";
import {MarketplaceProxy} from "../src/MarketplaceProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployVertix is Script {
    struct VertixAddresses {
        address nft;
        address governance;
        address escrow;
        address marketplaceProxy;
        address marketplaceCoreImpl;     // Stores implementation address
        address marketplaceAuctionsImpl; // Stores implementation address
        address marketplaceFees;
        address marketplaceStorage;
        address verificationServer;
        address feeRecipient;
    }

    /// @notice Deploys all Vertix contracts and links them appropriately.
    /// @param vertixAddresses A struct containing all deployed contract addresses.
    /// @return vertixAddresses The populated struct with all deployed contract addresses.
    function deployVertix() public returns (VertixAddresses memory vertixAddresses) {
        HelperConfig helperConfig = new HelperConfig();
        (address verificationServer, address feeRecipient, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        // Deploy MarketplaceStorage
        address marketplaceStorage = address(new MarketplaceStorage(msg.sender)); // Pass deployer as initial owner
        vertixAddresses.marketplaceStorage = marketplaceStorage;
        console.log("MarketplaceStorage deployed at:", marketplaceStorage);

        // Deploy VertixNFT (Implementation and Proxy)
        address vertixNftImpl = address(new VertixNFT());
        vertixAddresses.nft = deployProxy(
            vertixNftImpl,
            abi.encodeWithSelector(VertixNFT.initialize.selector, verificationServer),
            "VertixNFT"
        );

        // Deploy Escrow (Implementation and Proxy)
        address escrowImpl = address(new VertixEscrow());
        vertixAddresses.escrow = deployProxy(
            escrowImpl,
            abi.encodeWithSelector(VertixEscrow.initialize.selector),
            "VertixEscrow"
        );

        // Deploy VertixGovernance (Implementation and Proxy)
        // We temporarily pass address(0) for the marketplace and update it later.
        address governanceImpl = address(new VertixGovernance());
        vertixAddresses.governance = deployProxy(
            governanceImpl,
            abi.encodeWithSelector(
                VertixGovernance.initialize.selector,
                address(0),
                vertixAddresses.escrow,
                feeRecipient,
                verificationServer
            ),
            "VertixGovernance"
        );

        // Deploy MarketplaceFees (Implementation)
        // MarketplaceFees takes governance and escrow in its constructor (immutable).
        // It's not proxied in this setup, as its logic is considered stable.
        address marketplaceFeesImpl = address(new MarketplaceFees(vertixAddresses.governance, vertixAddresses.escrow));
        vertixAddresses.marketplaceFees = marketplaceFeesImpl;
        console.log("MarketplaceFees deployed at:", vertixAddresses.marketplaceFees);


        // Deploy MarketplaceCore *Implementation*
        // Its immutable dependencies (storage, fees, governance) are now known.
        address marketplaceCoreImpl = address(
            new MarketplaceCore(
                vertixAddresses.marketplaceStorage,
                vertixAddresses.marketplaceFees,
                vertixAddresses.governance
            )
        );
        vertixAddresses.marketplaceCoreImpl = marketplaceCoreImpl;
        console.log("MarketplaceCore implementation deployed at:", marketplaceCoreImpl);

        // Deploy MarketplaceAuctions *Implementation*
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

        // Deploy the main MarketplaceProxy
        // This proxy points to the *implementations* of Core and Auctions.
        vertixAddresses.marketplaceProxy = address(new MarketplaceProxy(marketplaceCoreImpl, marketplaceAuctionsImpl));
        console.log("Main MarketplaceProxy deployed at:", vertixAddresses.marketplaceProxy);

        // Call `initialize` on MarketplaceCore *through the MarketplaceProxy*.
        // Only initialize the primary contract (MarketplaceCore) via the proxy.
        // This sets the `_initialized` flag in the proxy's storage.
        MarketplaceCore(payable(vertixAddresses.marketplaceProxy)).initialize();
        console.log("MarketplaceCore initialized via proxy.");

        // Set essential contracts in MarketplaceStorage
        // Authorize the deployed marketplace proxy and the core/auctions implementations if needed
        // The `setContracts` in MarketplaceStorage needs to be called by its owner.
        // In this script, `msg.sender` (the deployer) is the owner of MarketplaceStorage.
        MarketplaceStorage(marketplaceStorage).setContracts(
            vertixAddresses.nft,             // VertixNFT proxy
            vertixAddresses.governance,      // VertixGovernance proxy
            vertixAddresses.escrow           // VertixEscrow proxy
        );
        console.log("MarketplaceStorage essential contracts set.");

        // Authorize MarketplaceCore and MarketplaceAuctions implementations in MarketplaceStorage
        // This allows them to call `onlyAuthorized` functions in storage.
        MarketplaceStorage(marketplaceStorage).authorizeContract(vertixAddresses.marketplaceCoreImpl, true);
        MarketplaceStorage(marketplaceStorage).authorizeContract(vertixAddresses.marketplaceAuctionsImpl, true);
        console.log("MarketplaceCore and MarketplaceAuctions implementations authorized in Storage.");


        // Update VertixGovernance with the main marketplace proxy address.
        // This is done via the Governance proxy.
        VertixGovernance(vertixAddresses.governance).setMarketplace(vertixAddresses.marketplaceProxy);
        console.log("VertixGovernance marketplace set to:", vertixAddresses.marketplaceProxy);

        // add VertixNFT contract as supported NFT contract
        VertixGovernance(vertixAddresses.governance).addSupportedNftContract(vertixAddresses.nft);

        // Transfer Escrow ownership to governance.
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

    function run() external returns (VertixAddresses memory) {
        return deployVertix();
    }
}
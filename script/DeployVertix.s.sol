// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VertixNFT} from "../src/VertixNFT.sol";
import {VertixGovernance} from "../src/VertixGovernance.sol";
import {VertixEscrow} from "../src/VertixEscrow.sol";
import {MarketplaceStorage} from "../src/MarketplaceStorage.sol";
import {MarketplaceCore} from "../src/MarketplaceCore.sol";
import {MarketplaceAuctions} from "../src/MarketplaceAuctions.sol";
import {MarketplaceFees} from "../src/MarketplaceFees.sol";
import {MarketplaceProxy} from "../src/MarketplaceProxy.sol";
import {CrossChainRegistry} from "../src/CrossChainRegistry.sol";
import {CrossChainBridge} from "../src/CrossChainBridge.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployVertix is Script {
    struct VertixAddresses {
        address nft;
        address governance;
        address escrow;
        address marketplaceProxy;
        address marketplaceCoreImpl;
        address marketplaceAuctionsImpl;
        address marketplaceFees;
        address marketplaceStorage;
        address crossChainRegistry;
        address crossChainBridge;
        address verificationServer;
        address feeRecipient;
    }

    function deployVertix() public returns (VertixAddresses memory vertixAddresses) {
        HelperConfig helperConfig = new HelperConfig();
        (address verificationServer, address feeRecipient, address layerZeroEndpoint, uint8 chainType, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        // Deploy contracts in stages to reduce stack depth
        vertixAddresses = _deployInitialContracts(deployerKey, verificationServer, feeRecipient);
        _deployMarketplaceComponents(vertixAddresses);
        _deployCrossChainComponents(vertixAddresses, layerZeroEndpoint, chainType);
        _setupContracts(vertixAddresses, chainType);

        vm.stopBroadcast();

        // Set additional addresses
        vertixAddresses.verificationServer = verificationServer;
        vertixAddresses.feeRecipient = feeRecipient;
        return vertixAddresses;
    }

    function _deployInitialContracts(
        uint256 deployerKey,
        address verificationServer,
        address feeRecipient
    ) internal returns (VertixAddresses memory) {
        VertixAddresses memory addresses;

        // Deploy MarketplaceStorage
        addresses.marketplaceStorage = address(new MarketplaceStorage(vm.addr(deployerKey)));
        console.log("MarketplaceStorage deployed at:", addresses.marketplaceStorage);

        // Deploy CrossChainRegistry
        addresses.crossChainRegistry = address(new CrossChainRegistry(vm.addr(deployerKey), addresses.marketplaceStorage));
        console.log("CrossChainRegistry deployed at:", addresses.crossChainRegistry);

        // Deploy VertixNFT
        address vertixNftImpl = address(new VertixNFT());
        addresses.nft = deployProxy(
            vertixNftImpl,
            abi.encodeWithSelector(VertixNFT.initialize.selector, verificationServer),
            "VertixNFT"
        );

        // Deploy Escrow
        address escrowImpl = address(new VertixEscrow());
        addresses.escrow = deployProxy(
            escrowImpl,
            abi.encodeWithSelector(VertixEscrow.initialize.selector),
            "VertixEscrow"
        );

        // Deploy Governance
        address governanceImpl = address(new VertixGovernance());
        addresses.governance = deployProxy(
            governanceImpl,
            abi.encodeWithSelector(
                VertixGovernance.initialize.selector,
                address(0), // Temporary, will set later
                addresses.escrow,
                feeRecipient,
                verificationServer
            ),
            "VertixGovernance"
        );

        return addresses;
    }

    function _deployMarketplaceComponents(VertixAddresses memory addresses) internal {
        // Deploy MarketplaceFees
        addresses.marketplaceFees = address(new MarketplaceFees(addresses.governance, addresses.escrow));
        console.log("MarketplaceFees deployed at:", addresses.marketplaceFees);

        // Deploy MarketplaceCore Implementation
        addresses.marketplaceCoreImpl = address(
            new MarketplaceCore(
                addresses.marketplaceStorage,
                addresses.marketplaceFees,
                addresses.governance
            )
        );
        console.log("MarketplaceCore implementation deployed at:", addresses.marketplaceCoreImpl);

        // Deploy MarketplaceAuctions Implementation
        addresses.marketplaceAuctionsImpl = address(
            new MarketplaceAuctions(
                addresses.marketplaceStorage,
                addresses.governance,
                addresses.escrow,
                addresses.marketplaceFees
            )
        );
        console.log("MarketplaceAuctions implementation deployed at:", addresses.marketplaceAuctionsImpl);

        // Deploy MarketplaceProxy
        addresses.marketplaceProxy = address(new MarketplaceProxy(
            addresses.marketplaceCoreImpl,
            addresses.marketplaceAuctionsImpl
        ));
        console.log("Main MarketplaceProxy deployed at:", addresses.marketplaceProxy);
    }

    function _deployCrossChainComponents(
        VertixAddresses memory addresses,
        address layerZeroEndpoint,
        uint8 chainType
    ) internal {
        // Deploy CrossChainBridge
        address crossChainBridgeImpl = address(new CrossChainBridge(
            addresses.crossChainRegistry,
            addresses.governance
        ));
        addresses.crossChainBridge = deployProxy(
            crossChainBridgeImpl,
            abi.encodeWithSelector(
                CrossChainBridge.initialize.selector,
                layerZeroEndpoint,
                chainType,
                0.01 ether
            ),
            "CrossChainBridge"
        );
    }

    function _setupContracts(VertixAddresses memory addresses, uint8 chainType) internal {
        // Initialize MarketplaceCore via proxy
        MarketplaceCore(payable(addresses.marketplaceProxy)).initialize();
        console.log("MarketplaceCore initialized via proxy.");

        // Setup MarketplaceStorage
        MarketplaceStorage(addresses.marketplaceStorage).setContracts(
            addresses.nft,
            addresses.governance,
            addresses.escrow
        );
        MarketplaceStorage(addresses.marketplaceStorage).authorizeContract(addresses.marketplaceCoreImpl, true);
        MarketplaceStorage(addresses.marketplaceStorage).authorizeContract(addresses.marketplaceAuctionsImpl, true);
        console.log("MarketplaceStorage setup complete.");

        // Setup CrossChainRegistry
        CrossChainRegistry(addresses.crossChainRegistry).authorizeContract(addresses.crossChainBridge, true);
        CrossChainRegistry(addresses.crossChainRegistry).setChainConfig(
            chainType,
            addresses.crossChainBridge,
            addresses.governance,
            12, // confirmationBlocks
            50, // feeBps (0.5%)
            true // isActive
        );
        console.log("CrossChainRegistry setup complete.");

        // Final Governance setup
        VertixGovernance(addresses.governance).setMarketplace(addresses.marketplaceProxy);
        VertixGovernance(addresses.governance).addSupportedNftContract(addresses.nft);
        VertixEscrow(addresses.escrow).transferOwnership(addresses.governance);
        console.log("Governance setup complete.");
    }

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
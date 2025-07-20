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
        _deployCrossChainComponents(vertixAddresses, layerZeroEndpoint, chainType);
        _deployMarketplaceComponents(vertixAddresses);
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

        // Deploy VertixNFT (after governance is deployed)
        address vertixNftImpl = address(new VertixNFT());
        addresses.nft = deployProxy(
            vertixNftImpl,
            abi.encodeWithSelector(VertixNFT.initialize.selector, addresses.governance),
            "VertixNFT"
        );

        return addresses;
    }

    function _deployMarketplaceComponents(VertixAddresses memory addresses) internal {
        // Deploy MarketplaceFees
        addresses.marketplaceFees = address(new MarketplaceFees(addresses.governance, addresses.escrow));

        // Deploy MarketplaceCore Implementation
        addresses.marketplaceCoreImpl = address(
            new MarketplaceCore(
                addresses.marketplaceStorage,
                addresses.marketplaceFees,
                addresses.governance,
                addresses.crossChainBridge
            )
        );

        // Deploy MarketplaceAuctions Implementation
        addresses.marketplaceAuctionsImpl = address(
            new MarketplaceAuctions(
                addresses.marketplaceStorage,
                addresses.governance,
                addresses.escrow,
                addresses.marketplaceFees
            )
        );

        // Deploy MarketplaceProxy
        addresses.marketplaceProxy = address(new MarketplaceProxy(
            addresses.marketplaceCoreImpl,
            addresses.marketplaceAuctionsImpl
        ));
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

        // Setup MarketplaceStorage
        MarketplaceStorage(addresses.marketplaceStorage).setContracts(
            addresses.nft,
            addresses.governance,
            addresses.escrow
        );
        MarketplaceStorage(addresses.marketplaceStorage).setCrossChainRegistry(addresses.crossChainRegistry);
        MarketplaceStorage(addresses.marketplaceStorage).authorizeContract(addresses.marketplaceProxy, true);
        MarketplaceStorage(addresses.marketplaceStorage).authorizeContract(addresses.marketplaceCoreImpl, true);
        MarketplaceStorage(addresses.marketplaceStorage).authorizeContract(addresses.marketplaceAuctionsImpl, true);

        // Setup CrossChainRegistry
        CrossChainRegistry(addresses.crossChainRegistry).authorizeContract(addresses.crossChainBridge, true);
        CrossChainRegistry(addresses.crossChainRegistry).authorizeContract(addresses.marketplaceProxy, true);
        CrossChainRegistry(addresses.crossChainRegistry).authorizeContract(addresses.marketplaceCoreImpl, true);
        CrossChainRegistry(addresses.crossChainRegistry).setChainConfig(
            chainType,
            addresses.crossChainBridge,
            addresses.governance,
            12, // confirmationBlocks
            50, // feeBps (0.5%)
            true // isActive
        );

        // Setup CrossChainBridge trusted remotes for cross-chain communication
        // Note: These need to be set after deployment on both chains
        // For Polygon (chainType 1) -> Base (chainType 2)
        if (chainType == 1) {
            // Set trusted remote for Base chain (LayerZero ID 184)
            CrossChainBridge(addresses.crossChainBridge).setTrustedRemote(184, abi.encodePacked(addresses.crossChainBridge));
        } else if (chainType == 2) {
            // Set trusted remote for Polygon chain (LayerZero ID 109)
            CrossChainBridge(addresses.crossChainBridge).setTrustedRemote(109, abi.encodePacked(addresses.crossChainBridge));
        }

        // Final Governance setup
        VertixGovernance(addresses.governance).setMarketplace(addresses.marketplaceProxy);
        VertixGovernance(addresses.governance).addSupportedNftContract(addresses.nft);
        VertixEscrow(addresses.escrow).transferOwnership(addresses.governance);
    }

    function deployProxy(address impl, bytes memory initData, string memory name) internal returns (address proxy) {
        console.log(string.concat(name, " implementation deployed at:"), impl);
        proxy = address(new ERC1967Proxy(impl, initData));
        console.log(string.concat(name, " proxy deployed at:"), proxy);
        return proxy;
    }

    /**
     * @dev Get the current chain name for logging
     */
    function _getChainName() internal view returns (string memory) {
        if (block.chainid == 137) return "Polygon Mainnet";
        if (block.chainid == 80001) return "Polygon Mumbai";
        if (block.chainid == 8453) return "Base Mainnet";
        if (block.chainid == 84532) return "Base Sepolia";
        if (block.chainid == 1) return "Ethereum Mainnet";
        if (block.chainid == 11155111) return "Sepolia";
        return "Local Network";
    }

    /**
     * @dev Deploy and setup contracts for a specific chain with detailed logging
     * @param chainName Name of the chain for logging
     */
    function deployForChain(string memory chainName) internal returns (VertixAddresses memory) {
        console.log("Deploying Vertix contracts for:", chainName);
        VertixAddresses memory addresses = deployVertix();

        console.log("=== Deployment Summary for", chainName, "===");
        console.log("NFT Contract:", addresses.nft);
        console.log("Governance:", addresses.governance);
        console.log("Escrow:", addresses.escrow);
        console.log("Marketplace Proxy:", addresses.marketplaceProxy);
        console.log("Marketplace Core:", addresses.marketplaceCoreImpl);
        console.log("Marketplace Auctions:", addresses.marketplaceAuctionsImpl);
        console.log("Marketplace Fees:", addresses.marketplaceFees);
        console.log("Marketplace Storage:", addresses.marketplaceStorage);
        console.log("CrossChain Registry:", addresses.crossChainRegistry);
        console.log("CrossChain Bridge:", addresses.crossChainBridge);
        console.log("Verification Server:", addresses.verificationServer);
        console.log("Fee Recipient:", addresses.feeRecipient);
        console.log("==========================================");

        return addresses;
    }

    /**
     * @dev Set up cross-chain trusted remotes after both chains are deployed
     * @param polygonBridgeAddress Bridge contract address on Polygon
     * @param baseBridgeAddress Bridge contract address on Base
     * @param deployerKey Private key for deployment
     */
    function setupCrossChainTrustedRemotes(
        address polygonBridgeAddress,
        address baseBridgeAddress,
        uint256 deployerKey
    ) external {
        vm.startBroadcast(deployerKey);

        // Set trusted remote on Polygon bridge for Base
        CrossChainBridge(polygonBridgeAddress).setTrustedRemote(184, abi.encodePacked(baseBridgeAddress));
        console.log("Polygon bridge: Set trusted remote for Base chain");

        // Set trusted remote on Base bridge for Polygon
        CrossChainBridge(baseBridgeAddress).setTrustedRemote(109, abi.encodePacked(polygonBridgeAddress));
        console.log("Base bridge: Set trusted remote for Polygon chain");

        vm.stopBroadcast();
        console.log("Cross-chain trusted remotes setup complete!");
    }

    function run() external returns (VertixAddresses memory) {
        // Get chain name based on current network
        string memory chainName = _getChainName();
        return deployForChain(chainName);
    }
}
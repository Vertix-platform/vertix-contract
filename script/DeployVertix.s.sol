// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

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
import {CrossChainMarketplace} from "../src/CrossChainMarketplace.sol";
import {CrossChainBridge} from "../src/CrossChainBridge.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployVertix is Script {
    struct ProxyAddresses {
        address nft;
        address governance;
        address escrow;
        address marketplace;
    }

    struct ImplementationAddresses {
        address marketplaceCore;
        address marketplaceAuctions;
        address marketplaceFees;
        address marketplaceStorage;
    }

    struct CrossChainAddresses {
        address marketplace;
        address bridge;
    }

    struct VertixAddresses {
        ProxyAddresses proxies;
        ImplementationAddresses implementations;
        CrossChainAddresses crossChain;
        address verificationServer;
        address feeRecipient;
    }

    function deployVertix() public returns (VertixAddresses memory) {
        HelperConfig helperConfig = new HelperConfig();
        (address verificationServer, address feeRecipient, address lzEndpoint, uint256 deployerKey) = 
            helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        VertixAddresses memory vertixAddresses;

        // Deploy MarketplaceStorage (not proxied)
        vertixAddresses.implementations.marketplaceStorage = address(
            new MarketplaceStorage(msg.sender)
        );
        console.log("MarketplaceStorage deployed at:", vertixAddresses.implementations.marketplaceStorage);

        // Deploy VertixNFT (Proxy)
        address vertixNftImpl = address(new VertixNFT());
        vertixAddresses.proxies.nft = deployProxy(
            vertixNftImpl,
            abi.encodeWithSelector(VertixNFT.initialize.selector, verificationServer),
            "VertixNFT"
        );

        // Deploy Escrow (Proxy)
        address escrowImpl = address(new VertixEscrow());
        vertixAddresses.proxies.escrow = deployProxy(
            escrowImpl,
            abi.encodeWithSelector(VertixEscrow.initialize.selector),
            "VertixEscrow"
        );

        // Deploy Governance (Proxy)
        address governanceImpl = address(new VertixGovernance());
        vertixAddresses.proxies.governance = deployProxy(
            governanceImpl,
            abi.encodeWithSelector(
                VertixGovernance.initialize.selector,
                address(0), // Will set marketplace later
                vertixAddresses.proxies.escrow,
                feeRecipient,
                verificationServer
            ),
            "VertixGovernance"
        );

        // Deploy MarketplaceFees (Implementation)
        vertixAddresses.implementations.marketplaceFees = address(
            new MarketplaceFees(
                vertixAddresses.proxies.governance,
                vertixAddresses.proxies.escrow
            )
        );
        console.log("MarketplaceFees deployed at:", vertixAddresses.implementations.marketplaceFees);

        // Deploy CrossChain Components
        vertixAddresses.crossChain.bridge = address(new CrossChainBridge(lzEndpoint));
        vertixAddresses.crossChain.marketplace = address(new CrossChainMarketplace(lzEndpoint));
        console.log("CrossChainBridge deployed at:", vertixAddresses.crossChain.bridge);
        console.log("CrossChainMarketplace deployed at:", vertixAddresses.crossChain.marketplace);

        // Deploy Marketplace Implementations
        vertixAddresses.implementations.marketplaceCore = address(
            new MarketplaceCore(
                vertixAddresses.implementations.marketplaceStorage,
                vertixAddresses.implementations.marketplaceFees,
                vertixAddresses.proxies.governance,
                lzEndpoint
            )
        );
        vertixAddresses.implementations.marketplaceAuctions = address(
            new MarketplaceAuctions(
                vertixAddresses.implementations.marketplaceStorage,
                vertixAddresses.proxies.governance,
                vertixAddresses.proxies.escrow,
                vertixAddresses.implementations.marketplaceFees
            )
        );

        // Deploy Marketplace Proxy
        vertixAddresses.proxies.marketplace = address(
            new MarketplaceProxy(
                vertixAddresses.implementations.marketplaceCore,
                vertixAddresses.implementations.marketplaceAuctions
            )
        );
        console.log("MarketplaceProxy deployed at:", vertixAddresses.proxies.marketplace);

        // Initialize MarketplaceCore through proxy
        MarketplaceCore(payable(vertixAddresses.proxies.marketplace)).initialize(msg.sender);

        // Configure MarketplaceStorage
        MarketplaceStorage(vertixAddresses.implementations.marketplaceStorage).setContracts(
            vertixAddresses.proxies.nft,
            vertixAddresses.proxies.governance,
            vertixAddresses.proxies.escrow
        );
        MarketplaceStorage(vertixAddresses.implementations.marketplaceStorage).authorizeContract(
            vertixAddresses.implementations.marketplaceCore, 
            true
        );
        MarketplaceStorage(vertixAddresses.implementations.marketplaceStorage).authorizeContract(
            vertixAddresses.implementations.marketplaceAuctions, 
            true
        );

        // Configure Cross-Chain
        _configureCrossChainIntegration(vertixAddresses);

        // Finalize Governance Setup
        VertixGovernance(vertixAddresses.proxies.governance).setMarketplace(
            vertixAddresses.proxies.marketplace
        );
        VertixGovernance(vertixAddresses.proxies.governance).addSupportedNFTContract(
            vertixAddresses.proxies.nft
        );
        VertixEscrow(vertixAddresses.proxies.escrow).transferOwnership(
            vertixAddresses.proxies.governance
        );

        vm.stopBroadcast();

        // Set remaining addresses
        vertixAddresses.verificationServer = verificationServer;
        vertixAddresses.feeRecipient = feeRecipient;

        return vertixAddresses;
    }

    function _configureCrossChainIntegration(
        VertixAddresses memory vertixAddresses
    ) internal {
        uint16 currentChainId = _getLayerZeroChainId(block.chainid);
        uint16[] memory supportedChains = new uint16[](2);
        supportedChains[0] = 10109; // Polygon Mumbai
        supportedChains[1] = 10160; // Base Goerli

        MarketplaceCore marketplaceCore = MarketplaceCore(payable(vertixAddresses.proxies.marketplace));
        CrossChainMarketplace crossChainMarketplace = CrossChainMarketplace(
            payable(vertixAddresses.crossChain.marketplace)
        );

        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i] != currentChainId) {
                marketplaceCore.setCrossChainMarketplace(
                    supportedChains[i],
                    vertixAddresses.crossChain.marketplace
                );
                crossChainMarketplace.setMarketplaceCore(
                    supportedChains[i],
                    vertixAddresses.implementations.marketplaceCore
                );
            }
        }
    }

    function _getLayerZeroChainId(uint256 chainId) internal pure returns (uint16) {
        if (chainId == 80001) return 10109; // Polygon Mumbai
        if (chainId == 84531) return 10160; // Base Goerli
        if (chainId == 1) return 101;       // Ethereum Mainnet
        if (chainId == 137) return 109;     // Polygon Mainnet
        if (chainId == 8453) return 184;    // Base Mainnet
        return 10109; // Default testnet
    }

    function deployProxy(
        address impl,
        bytes memory initData,
        string memory name
    ) internal returns (address proxy) {
        console.log(string.concat(name, " implementation deployed at:"), impl);
        proxy = address(new ERC1967Proxy(impl, initData));
        console.log(string.concat(name, " proxy deployed at:"), proxy);
        return proxy;
    }

    function run() external returns (VertixAddresses memory) {
        return deployVertix();
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract HelperConfig is Script {
    // Error
    error HelperConfig__PrivateKeyNotSet();

    struct NetworkConfig {
        address verificationServer;
        address feeRecipient;
        address lzEndpoint;
        uint256 deployerKey;
    }

    uint256 public immutable DEFAULT_ANVIL_DEPLOYER_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 1) {
            // Ethereum Mainnet
            activeNetworkConfig = getEthMainnetConfig();
        } else if (block.chainid == 137) {
            // Polygon Mainnet
            activeNetworkConfig = getPolygonMainnetConfig();
        } else if (block.chainid == 80001) {
            // Polygon Mumbai Testnet
            activeNetworkConfig = getPolygonMumbaiConfig();
        } else if (block.chainid == 8453) {
            // Base Mainnet
            activeNetworkConfig = getBaseMainnetConfig();
        } else if (block.chainid == 84532) {
            // Base Sepolia Testnet
            activeNetworkConfig = getBaseSepoliaConfig();
        } else if (block.chainid == 11155111) {
            // Sepolia Testnet
            activeNetworkConfig = getSepoliaConfig();
        } else {
            // Default to Anvil
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getEthMainnetConfig() public view returns (NetworkConfig memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        if (deployerKey == 0) {
            revert HelperConfig__PrivateKeyNotSet();
        }
        return NetworkConfig({
            verificationServer: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            feeRecipient: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            lzEndpoint: 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675, // LayerZero Ethereum mainnet endpoint
            deployerKey: deployerKey
        });
    }

    function getPolygonMainnetConfig() public view returns (NetworkConfig memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        if (deployerKey == 0) {
            revert HelperConfig__PrivateKeyNotSet();
        }

        return NetworkConfig({
            verificationServer: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            feeRecipient: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            lzEndpoint: 0x3c2269811836af69497E5F486A85D7316753cf62, // LayerZero Polygon mainnet endpoint
            deployerKey: deployerKey
        });
    }

    function getPolygonMumbaiConfig() public view returns (NetworkConfig memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        if (deployerKey == 0) {
            revert HelperConfig__PrivateKeyNotSet();
        }
        return NetworkConfig({
            verificationServer: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            feeRecipient: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            lzEndpoint: 0xf69186dfBa60DdB133E91E9A4B5673624293d8F8, // LayerZero Mumbai testnet endpoint
            deployerKey: deployerKey
        });
    }

    function getBaseMainnetConfig() public view returns (NetworkConfig memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        if (deployerKey == 0) {
            revert HelperConfig__PrivateKeyNotSet();
        }

        return NetworkConfig({
            verificationServer: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            feeRecipient: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            lzEndpoint: 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7, // LayerZero Base mainnet endpoint
            deployerKey: deployerKey
        });
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        if (deployerKey == 0) {
            revert HelperConfig__PrivateKeyNotSet();
        }

        return NetworkConfig({
            verificationServer: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            feeRecipient: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f, // LayerZero Base Sepolia testnet endpoint
            deployerKey: deployerKey
        });
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        if (deployerKey == 0) {
            revert HelperConfig__PrivateKeyNotSet();
        }

        return NetworkConfig({
            verificationServer: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            feeRecipient: 0xe9f1406E039d5c3FBF442C2542Df84E52A51d3C4,
            lzEndpoint: 0xae92d5aD7583AD66E49A0c67BAd18F6ba52dDDc1, // LayerZero Sepolia testnet endpoint
            deployerKey: deployerKey
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // This is for local Anvil testing
        if (activeNetworkConfig.verificationServer != address(0)) {
            return activeNetworkConfig;
        }

        uint256 deployerKey = DEFAULT_ANVIL_DEPLOYER_KEY;
        vm.startBroadcast(deployerKey);
        address verificationServer = makeAddr("verificationServer");
        address feeRecipient = makeAddr("feeRecipient");
        address lzEndpoint = makeAddr("lzEndpoint"); // Mock LayerZero endpoint for local testing
        vm.stopBroadcast();

        return NetworkConfig({
            verificationServer: verificationServer,
            feeRecipient: feeRecipient,
            lzEndpoint: lzEndpoint,
            deployerKey: deployerKey
        });
    }
}

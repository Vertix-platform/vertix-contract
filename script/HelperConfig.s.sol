// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract HelperConfig is Script {
    // Error
    error HelperConfig__PrivateKeyNotSet();

    struct NetworkConfig {
        address verificationServer;
        address feeRecipient;
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
        vm.stopBroadcast();

        return NetworkConfig({
            verificationServer: verificationServer,
            feeRecipient: feeRecipient,
            deployerKey: deployerKey
        });
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VertixNFT} from "../src/VertixNFT.sol";
import {VertixGovernance} from "../src/VertixGovernance.sol";
import {VertixEscrow} from "../src/VertixEscrow.sol";
import {VertixMarketplace} from "../src/VertixMarketplace.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployVertix is Script {
    struct VertixAddresses {
        address nft;
        address governance;
        address escrow;
        address marketplace;
    }

    VertixAddresses addresses;

    function run() external returns (VertixAddresses memory) {
        HelperConfig helperConfig = new HelperConfig();
        (address verificationServer, address feeRecipient, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        // Deploy VertixNFT
        addresses.nft = deployProxy(
            address(new VertixNFT()),
            abi.encodeWithSelector(VertixNFT.initialize.selector, verificationServer),
            "VertixNFT"
        );

        // Deploy VertixEscrow
        addresses.escrow = deployProxy(
            address(new VertixEscrow()), abi.encodeWithSelector(VertixEscrow.initialize.selector), "VertixEscrow"
        );

        // Deploy VertixGovernance
        addresses.governance = deployProxy(
            address(new VertixGovernance()),
            abi.encodeWithSelector(
                VertixGovernance.initialize.selector,
                address(0), // Placeholder for marketplace
                addresses.escrow,
                feeRecipient
            ),
            "VertixGovernance"
        );

        // Deploy VertixMarketplace
        addresses.marketplace = deployProxy(
            address(new VertixMarketplace()),
            abi.encodeWithSelector(
                VertixMarketplace.initialize.selector, addresses.nft, addresses.governance, addresses.escrow
            ),
            "VertixMarketplace"
        );

        // Update VertixGovernance
        VertixGovernance(addresses.governance).setMarketplace(addresses.marketplace);
        console.log("VertixGovernance marketplace set to:", addresses.marketplace);

        // Transfer VertixEscrow ownership
        VertixEscrow(addresses.escrow).transferOwnership(addresses.governance);
        console.log("VertixEscrow ownership transferred to:", addresses.governance);

        vm.stopBroadcast();

        return addresses;
    }

    function deployProxy(address impl, bytes memory initData, string memory name) internal returns (address proxy) {
        console.log(string.concat(name, " implementation deployed at:"), impl);
        proxy = address(new ERC1967Proxy(impl, initData));
        console.log(string.concat(name, " proxy deployed at:"), proxy);
    }
}

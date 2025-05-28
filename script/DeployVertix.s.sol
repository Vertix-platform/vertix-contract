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
        address verificationServer;
        address feeRecipient;
    }

    function deployVertix() public returns (VertixAddresses memory) {
        HelperConfig helperConfig = new HelperConfig();
        (address verificationServer, address feeRecipient, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        // Deploy VertixNFT
        address nft = deployProxy(
            address(new VertixNFT()),
            abi.encodeWithSelector(VertixNFT.initialize.selector, verificationServer),
            "VertixNFT"
        );

        // Deploy VertixEscrow
        address escrow = deployProxy(
            address(new VertixEscrow()),
            abi.encodeWithSelector(VertixEscrow.initialize.selector),
            "VertixEscrow"
        );

        // Deploy VertixGovernance
        address governance = deployProxy(
            address(new VertixGovernance()),
            abi.encodeWithSelector(
                VertixGovernance.initialize.selector,
                address(0), // Placeholder for marketplace (updated later)
                escrow,
                feeRecipient,
                verificationServer
            ),
            "VertixGovernance"
        );

        // Deploy VertixMarketplace
        address marketplace = deployProxy(
            address(new VertixMarketplace()),
            abi.encodeWithSelector(
                VertixMarketplace.initialize.selector, nft, governance, escrow
            ),
            "VertixMarketplace"
        );

        // Update VertixGovernance with marketplace address
        VertixGovernance(governance).setMarketplace(marketplace);
        console.log("VertixGovernance marketplace set to:", marketplace);

        // Transfer VertixEscrow ownership to governance
        VertixEscrow(escrow).transferOwnership(governance);
        console.log("VertixEscrow ownership transferred to:", governance);

        vm.stopBroadcast();

        return VertixAddresses({
            nft: nft,
            governance: governance,
            escrow: escrow,
            marketplace: marketplace,
            verificationServer: verificationServer,
            feeRecipient: feeRecipient
        });
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
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ERC1155Collection is Initializable, ERC1155Upgradeable, OwnableUpgradeable {
    // Event to emit tokenURI for off-chain storage
    event TokenURIMinted(uint256 indexed tokenId, string tokenURI);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory uri) external initializer {
        __ERC1155_init(uri);
        __Ownable_init(msg.sender);
    }

    function safeMint(address to, uint256 tokenId, uint256 amount, string memory tokenURI) external onlyOwner {
        _mint(to, tokenId, amount, "");
        // Emit tokenURI for off-chain storage
        emit TokenURIMinted(tokenId, tokenURI);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VertixEscrow} from "../../src/VertixEscrow.sol";

contract VertixEscrowV2Mock is VertixEscrow {
    uint256 private _newFeature;

    function setNewFeature(uint256 value) external onlyOwner {
        _newFeature = value;
    }

    function getNewFeature() external view returns (uint256) {
        return _newFeature;
    }
}

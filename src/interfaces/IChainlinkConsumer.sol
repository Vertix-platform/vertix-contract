// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IChainlinkConsumer {
    function requestAssetValue(string calldata assetType, string calldata assetId) external returns (bytes32);
    function getValue(bytes32 requestId) external view returns (uint256);
}
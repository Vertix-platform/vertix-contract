// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVertixAssetVerifier {
    function verifyAsset(address user, string calldata assetType, string calldata assetId) external view returns (bool);
    function submitVerification(string calldata assetType, string calldata assetId, bytes calldata proof) external;
}
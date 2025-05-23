// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VertixUtils
 * @dev Library for common utilities in Vertix contracts
 */
library VertixUtils {
    // Errors
    error VertixUtils__InvalidPrice();
    error VertixUtils__EmptyProof();

    // Type declarations
    enum AssetType {
        SocialMedia,
        Domain,
        App,
        Website,
        Youtube,
        Other
    }

    // Constants
    uint256 private constant MIN_PRICE = 1 wei;

    /**
     * @dev Validate price is non-zero
     * @param price The price to validate
     */
    function validatePrice(uint256 price) internal pure {
        if (price < MIN_PRICE) revert VertixUtils__InvalidPrice();
    }

    /**
     * @dev Hash verification proof for off-chain validation
     * @param proof The verification proof bytes
     * @return The keccak256 hash of the proof
     */
    function hashVerificationProof(bytes calldata proof) internal pure returns (bytes32) {
        if (proof.length == 0) revert VertixUtils__EmptyProof();
        return keccak256(proof);
    }

    /**
     * @dev Get string representation of AssetType (useful for frontends)
     * @param assetType The AssetType enum value
     * @return String representation
     */
    function assetTypeToString(AssetType assetType) internal pure returns (string memory) {
        if (assetType == AssetType.SocialMedia) return "SocialMedia";
        if (assetType == AssetType.Domain) return "Domain";
        if (assetType == AssetType.App) return "App";
        if (assetType == AssetType.Website) return "Website";
        if (assetType == AssetType.Youtube) return "Youtube";
        return "Other";
    }
}

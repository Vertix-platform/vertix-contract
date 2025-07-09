// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VertixUtils
 * @dev Library for common utilities in Vertix contracts including multi-chain support
 */
library VertixUtils {
    // Errors
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

    // Multi-chain support
    enum ChainType {
        Polygon,     // 0 - Primary chain
        Base,        // 1 - Secondary chain
        Ethereum     // 2 - Future support
    }

    // Cross-chain message types
    enum MessageType {
        AssetTransfer,       // 0 - Asset ownership transfer
        PriceSync,          // 1 - Price synchronization
        VerificationSync,   // 2 - Verification status sync
        EscrowUpdate        // 3 - Escrow status update
    }

    // Cross-chain asset representation
    struct CrossChainAsset {
        uint8 chainType;        // ChainType enum
        address contractAddress;
        uint256 tokenId;
        uint64 lastSyncBlock;   // Last block when synced
        bool isActive;
    }

    // Cross-chain message structure
    struct CrossChainMessage {
        uint8 messageType;      // MessageType enum
        uint8 sourceChain;      // Source ChainType
        uint8 targetChain;      // Target ChainType
        uint64 timestamp;
        bytes32 messageHash;
        bytes payload;
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
     * @dev Create asset ID for cross-chain tracking
     * @param chainType Source chain type
     * @param contractAddr Contract address
     * @param tokenId Token ID
     * @return bytes32 unique asset identifier
     */
    function createCrossChainAssetId(
        ChainType chainType,
        address contractAddr,
        uint256 tokenId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(chainType, contractAddr, tokenId));
    }
}

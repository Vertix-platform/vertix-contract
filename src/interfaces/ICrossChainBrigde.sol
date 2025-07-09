// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ICrossChainBridge
 * @dev Interface for the CrossChainBridge contract
 */

interface ICrossChainBridge {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error CCB__InvalidChainType();
    error CCB__InvalidDestinationChain();
    error CCB__UnauthorizedTransfer();
    error CCB__InsufficientFee();
    error CCB__InvalidPayload();
    error CCB__NoStoredMessage();
    error CCB__OnlyEndpoint();
    error CCB__MessageAlreadyProcessed();
    error CCB__TransferFailed();
    error CCB__InvalidListing();
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/

    enum MessageType {
        ASSET_TRANSFER,
        ASSET_UNLOCK,
        PRICE_SYNC,
        GOVERNANCE_UPDATE,
        NON_NFT_TRANSFER,
        NON_NFT_UNLOCK
    }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct BridgeRequest {
        address owner;
        address nftContract;        // For NFTs: contract address, For non-NFTs: marketplace address
        uint256 tokenId;           // For NFTs: token ID, For non-NFTs: listing ID
        uint8 targetChainType;
        address targetContract;
        uint96 fee;
        uint64 timestamp;
        uint8 status;              // 0=pending, 1=completed, 2=failed
        bool isNft;                // True for NFT, false for non-NFT
        uint8 assetType;           // Asset type for non-NFT assets (from VertixUtils.AssetType)
        string assetId;            // Asset ID for non-NFT assets
    }

    struct PayloadData {
        MessageType messageType;
        bytes32 requestId;
        address owner;
        address contractAddr;
        uint256 tokenId;
        address targetContract;
        uint256 timestamp;
        bool isNft;
        uint8 assetType;
        string assetId;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title ICrossChainBridge
 * @dev Interface for cross-chain bridge operations using LayerZero
 */
interface ICrossChainBridge {
    // Structs
    struct NonNFTAsset {
        uint8 assetType;      // Type of asset (1: game item, 2: service, 3: license, etc.)
        string assetId;       // Unique identifier for the asset
        bytes metadata;       // Additional metadata about the asset
        address owner;        // Current owner of the asset
        bool transferable;    // Whether the asset can be transferred
        uint256 expiryTime;  // 0 for perpetual, timestamp for time-limited assets
    }

    // Events
    event TokenBridgeInitiated(
        uint16 indexed dstChainId,
        address indexed token,
        address indexed from,
        address to,
        uint256 amount,
        uint256 nonce
    );

    event TokenBridgeCompleted(
        uint16 indexed srcChainId,
        bytes32 indexed srcAddress,
        address indexed to,
        uint256 amount,
        uint256 nonce
    );

    event NFTBridgeInitiated(
        uint16 indexed dstChainId,
        address indexed nftContract,
        address indexed from,
        address to,
        uint256 tokenId,
        uint256 nonce
    );

    event NFTBridgeCompleted(
        uint16 indexed srcChainId,
        bytes32 indexed srcAddress,
        address indexed to,
        uint256 tokenId,
        uint256 nonce
    );

    event NonNFTAssetBridgeInitiated(
        uint16 indexed dstChainId,
        string indexed assetId,
        address indexed from,
        address to,
        uint8 assetType,
        uint256 nonce
    );

    event NonNFTAssetBridgeCompleted(
        uint16 indexed srcChainId,
        string indexed assetId,
        address indexed to,
        uint8 assetType,
        uint256 nonce
    );

    event NonNFTAssetRegistered(
        string indexed assetId,
        address indexed owner,
        uint8 assetType
    );

    event NonNFTAssetUpdated(
        string indexed assetId,
        address indexed owner
    );

    event NonNFTAssetTransferred(
        string indexed assetId,
        address indexed from,
        address indexed to
    );

    event TokenSupported(
        address indexed token,
        bool supported
    );

    event ChainSupported(
        uint16 indexed chainId,
        bool supported
    );

    event AssetTypeSupported(
        uint8 indexed assetType,
        bool supported
    );

    event EmergencyWithdraw(
        address indexed token,
        uint256 amount,
        address indexed recipient
    );



    // Errors
    error Bridge__InvalidDestination();
    error Bridge__InvalidToken();
    error Bridge__InsufficientValue();
    error Bridge__TransferFailed();
    error Bridge__InvalidPayload();
    error Bridge__UnauthorizedSource();
    error Bridge__AssetNotTransferable();
    error Bridge__AssetExpired();
    error Bridge__InvalidAssetType();
    error Bridge__AssetNotFound();
    error Bridge__NotOwner();
    error Bridge__InsufficientBalance();
    error Bridge__AssetAlreadyExists();
    error Bridge__InvalidAmount();

    // Core functions
    function bridgeToken(
        uint16 dstChainId,
        address token,
        address to,
        uint256 amount,
        bool useNative
    ) external payable;

    function bridgeNFT(
        uint16 dstChainId,
        address nftContract,
        address to,
        uint256 tokenId
    ) external payable;

    function bridgeNonNFTAsset(
        uint16 dstChainId,
        string calldata assetId,
        address to,
        bytes calldata metadata
    ) external payable;

    // View functions
    function estimateBridgeFee(
        uint16 dstChainId,
        address to,
        bool useNative
    ) external view returns (uint256 nativeFee, uint256 zroFee);

    // function getSupportedChains() external view returns (uint16[] memory);
    // function isSupportedToken(address token) external view returns (bool);
    // function getNonce() external view returns (uint256);
    // function getNonNFTAsset(string calldata assetId) external view returns (NonNFTAsset memory);
    // function isValidAssetType(uint8 assetType) external view returns (bool);
}
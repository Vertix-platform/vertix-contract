// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {NonblockingLzApp} from "lib/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";
import {VertixUtils} from "./libraries/VertixUtils.sol";
import {ICrossChainBridge} from "./interfaces/ICrossChainBridge.sol";

/**
 * @title CrossChainBridge
 * @dev Implementation of cross-chain bridge using LayerZero
 */
contract CrossChainBridge is ICrossChainBridge, NonblockingLzApp, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    // Constants for packet types
    uint16 private constant PACKET_TYPE_TOKEN = 1;
    uint16 private constant PACKET_TYPE_NFT = 2;
    uint16 private constant PACKET_TYPE_NON_NFT = 3;


    // State variables
    mapping(address => bool) public supportedTokens;
    mapping(uint16 => bool) public supportedChainIds;
    mapping(string => NonNFTAsset) private nonNFTAssets;
    mapping(uint8 => bool) private validAssetTypes;
    uint256 private nonce;

    // Gas-optimized arrays for supported chains and asset types
    uint16[] private supportedChainsList;
    uint8[] private validAssetTypesList;

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) Ownable(msg.sender) {
        // Initialize supported chains (TESTNET)
        supportedChainIds[10109] = true; // Polygon Mumbai testnet
        supportedChainIds[10160] = true; // Base Goerli testnet
        supportedChainsList = [10109, 10160];

        // Initialize valid asset types
        uint8[6] memory assetTypes = [
            uint8(VertixUtils.AssetType.SocialMedia),
            uint8(VertixUtils.AssetType.Domain),
            uint8(VertixUtils.AssetType.App),
            uint8(VertixUtils.AssetType.Website),
            uint8(VertixUtils.AssetType.Youtube),
            uint8(VertixUtils.AssetType.Other)
        ];

        // Gas optimization: Use unchecked loop and single storage assignment
        unchecked {
            for (uint256 i = 0; i < assetTypes.length; ++i) {
                validAssetTypes[assetTypes[i]] = true;
            }
        }
        validAssetTypesList = assetTypes;
    }

    // Admin functions
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert Bridge__InvalidToken();
        supportedTokens[token] = true;
        emit TokenSupported(token, true);
    }

    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        emit TokenSupported(token, false);
    }

    function addSupportedChain(uint16 chainId) external onlyOwner {
        if (chainId == 0) revert Bridge__InvalidDestination();
        if (!supportedChainIds[chainId]) {
            supportedChainIds[chainId] = true;
            supportedChainsList.push(chainId);
        }
        emit ChainSupported(chainId, true);
    }

    function removeSupportedChain(uint16 chainId) external onlyOwner {
        if (supportedChainIds[chainId]) {
            supportedChainIds[chainId] = false;
            _removeFromChainsList(chainId);
        }
        emit ChainSupported(chainId, false);
    }

    function addAssetType(uint8 assetType) external onlyOwner {
        if (!validAssetTypes[assetType]) {
            validAssetTypes[assetType] = true;
            validAssetTypesList.push(assetType);
        }
        emit AssetTypeSupported(assetType, true);
    }

    function removeAssetType(uint8 assetType) external onlyOwner {
        if (validAssetTypes[assetType]) {
            validAssetTypes[assetType] = false;
            _removeFromAssetTypesList(assetType);
        }
        emit AssetTypeSupported(assetType, false);
    }

    // Core bridge functions
    function bridgeToken(
        uint16 dstChainId,
        address token,
        address to,
        uint256 amount,
        bool useNative
    ) external payable override nonReentrant {
        if (!supportedChainIds[dstChainId]) revert Bridge__InvalidDestination();
        if (!useNative && !supportedTokens[token]) revert Bridge__InvalidToken();
        if (amount == 0) revert Bridge__InvalidAmount();

        // Get the bridge fee
        (uint256 nativeFee,) = estimateBridgeFee(dstChainId, to, useNative);
        if (msg.value < nativeFee) revert Bridge__InsufficientValue();

        // Increment nonce once and use it consistently
        uint256 currentNonce = nonce++;

        // Handle token transfer based on type
        if (useNative) {
            // For native tokens, ensure msg.value covers both amount and fee
            if (msg.value < amount + nativeFee) revert Bridge__InsufficientValue();
            // The native token amount is already included in msg.value
            // LayerZero will handle the fee, and the remaining amount represents the bridged value
        } else {
            // For ERC20 tokens, transfer to this contract first
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Prepare the payload
        bytes memory payload = abi.encode(
            PACKET_TYPE_TOKEN,
            useNative ? address(0) : token, // Use address(0) for native tokens
            msg.sender,
            to,
            amount,
            currentNonce
        );

        // Send cross-chain message
        _lzSend(
            dstChainId,
            payload,
            payable(msg.sender),
            address(0),
            bytes(""),
            msg.value
        );

        emit TokenBridgeInitiated(
            dstChainId, 
            useNative ? address(0) : token, 
            msg.sender, 
            to, 
            amount, 
            currentNonce
        );
    }

    function bridgeNFT(
        uint16 dstChainId,
        address nftContract,
        address to,
        uint256 tokenId
    ) external payable override nonReentrant {
        if (!supportedChainIds[dstChainId]) revert Bridge__InvalidDestination();
        if (!supportedTokens[nftContract]) revert Bridge__InvalidToken();

        // Get the bridge fee
        (uint256 nativeFee,) = estimateBridgeFee(dstChainId, to, false);
        if (msg.value < nativeFee) revert Bridge__InsufficientValue();
        
        // Increment nonce once and use it consistently
        uint256 currentNonce = nonce++;

        // Prepare the payload
        bytes memory payload = abi.encode(
            PACKET_TYPE_NFT,
            nftContract,
            msg.sender,
            to,
            tokenId,
            currentNonce
        );

        // Transfer NFT to this contract
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        // Send cross-chain message
        _lzSend(
            dstChainId,
            payload,
            payable(msg.sender),
            address(0),
            bytes(""),
            msg.value
        );

        emit NFTBridgeInitiated(dstChainId, nftContract, msg.sender, to, tokenId, currentNonce);
    }

    function bridgeNonNFTAsset(
        uint16 dstChainId,
        string calldata assetId,
        address to,
        bytes calldata metadata
    ) external payable override nonReentrant {
        if (!supportedChainIds[dstChainId]) revert Bridge__InvalidDestination();

        NonNFTAsset memory asset = nonNFTAssets[assetId];
        if (asset.owner == address(0)) revert Bridge__AssetNotFound();
        if (!asset.transferable) revert Bridge__AssetNotTransferable();
        if (asset.expiryTime != 0 && asset.expiryTime < block.timestamp) revert Bridge__AssetExpired();
        if (asset.owner != msg.sender) revert Bridge__NotOwner();

        // Get the bridge fee
        (uint256 nativeFee,) = estimateBridgeFee(dstChainId, to, false);
        if (msg.value < nativeFee) revert Bridge__InsufficientValue();

        // Increment nonce once and use it consistently
        uint256 currentNonce = nonce++;

        // Prepare the payload
        bytes memory payload = abi.encode(
            PACKET_TYPE_NON_NFT,
            assetId,
            msg.sender,
            to,
            asset.assetType,
            metadata,
            currentNonce
        );

        // Update state
        asset.owner = address(this);
        nonNFTAssets[assetId] = asset;

        // Send cross-chain message
        _lzSend(
            dstChainId,
            payload,
            payable(msg.sender),
            address(0),
            bytes(""),
            msg.value
        );

        emit NonNFTAssetBridgeInitiated(
            dstChainId,
            assetId,
            msg.sender,
            to,
            asset.assetType,
            currentNonce
        );
    }

    // LayerZero receive function
    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 /* nonce */,
        bytes memory payload
    ) internal override nonReentrant {
        if (!supportedChainIds[srcChainId]) revert Bridge__UnauthorizedSource();

        // Decode the packet type
        (uint16 packetType) = abi.decode(payload, (uint16));

        if (packetType == PACKET_TYPE_TOKEN) {
            _handleTokenReceive(srcChainId, srcAddress, payload);
        } else if (packetType == PACKET_TYPE_NFT) {
            _handleNFTReceive(srcChainId, srcAddress, payload);
        } else if (packetType == PACKET_TYPE_NON_NFT) {
            _handleNonNFTReceive(srcChainId, srcAddress, payload);
        } else {
            revert Bridge__InvalidPayload();
        }
    }

    // Internal handlers
    function _handleTokenReceive(
        uint16 srcChainId,
        bytes memory /* srcAddress */,
        bytes memory payload
    ) private {
        (
            , // packetType - not used after decoding
            address token,
            address from,
            address to,
            uint256 amount,
            uint256 _nonce
        ) = abi.decode(payload, (uint16, address, address, address, uint256, uint256));

        if (token == address(0)) {
            // Handle native token transfer
            if (address(this).balance < amount) revert Bridge__InsufficientBalance();

            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) revert Bridge__TransferFailed();
        } else {
            // Handle ERC20 token transfer
            if (!supportedTokens[token]) revert Bridge__InvalidToken();
            if (IERC20(token).balanceOf(address(this)) < amount) revert Bridge__InsufficientBalance();

            IERC20(token).safeTransfer(to, amount);
        }

        emit TokenBridgeCompleted(
            srcChainId,
            bytes32(bytes20(from)),
            to,
            amount,
            _nonce
        );
    }

    function _handleNFTReceive(
        uint16 srcChainId,
        bytes memory /* srcAddress */,
        bytes memory payload
    ) private {
        (
            , // packetType - not used after decoding
            address nftContract,
            address from,
            address to,
            uint256 tokenId,
            uint256 _nonce
        ) = abi.decode(payload, (uint16, address, address, address, uint256, uint256));

        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);

        emit NFTBridgeCompleted(
            srcChainId,
            bytes32(bytes20(from)),
            to,
            tokenId,
            _nonce
        );
    }

    function _handleNonNFTReceive(
        uint16 srcChainId,
        bytes memory /* srcAddress */,
        bytes memory payload
    ) private {
        (
            ,
            string memory assetId,
            ,
            address to,
            uint8 assetType,
            bytes memory metadata,
            uint256 _nonce
        ) = abi.decode(payload, (uint16, string, address, address, uint8, bytes, uint256));
        if (!validAssetTypes[assetType]) revert Bridge__InvalidAssetType();

        // Create or update the asset on this chain
        NonNFTAsset storage asset = nonNFTAssets[assetId];
        asset.assetType = assetType;
        asset.owner = to;
        asset.metadata = metadata;
        asset.transferable = true;
        // Keep existing expiry time if any

        emit NonNFTAssetBridgeCompleted(
            srcChainId,
            assetId,
            to,
            assetType,
            _nonce
        );
    }

    // View functions
    function estimateBridgeFee(
        uint16 dstChainId,
        address to,
        bool /* useNative */
    ) public view override returns (uint256 nativeFee, uint256 zroFee) {
        bytes memory payload = abi.encode(PACKET_TYPE_TOKEN, address(0), msg.sender, to, 0, 0);
        return lzEndpoint.estimateFees(dstChainId, address(this), payload, false, bytes(""));
    }

    // function getSupportedChains() external view returns (uint16[] memory) {
    //     return supportedChainsList;
    // }

    // function isSupportedToken(address token) external view returns (bool) {
    //     return supportedTokens[token];
    // }

    // function isSupportedChain(uint16 chainId) external view returns (bool) {
    //     return supportedChainIds[chainId];
    // }

    // function getNonce() external view returns (uint256) {
    //     return nonce;
    // }

    // function getNonNFTAsset(string calldata assetId) external view returns (NonNFTAsset memory) {
    //     return nonNFTAssets[assetId];
    // }

    // function isValidAssetType(uint8 assetType) external view returns (bool) {
    //     return validAssetTypes[assetType];
    // }

    // function getValidAssetTypes() external view returns (uint8[] memory) {
    //     return validAssetTypesList;
    // }

    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* tokenId */,
        bytes calldata /* data */
    ) external nonReentrant override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // Receive function for native tokens
    receive() external payable {}

    // Asset management functions
    function registerNonNFTAsset(
        string calldata assetId,
        uint8 assetType,
        bytes calldata metadata,
        bool transferable,
        uint256 expiryTime
    ) external {
        if (!validAssetTypes[assetType]) revert Bridge__InvalidAssetType();
        if (nonNFTAssets[assetId].owner != address(0)) revert Bridge__AssetAlreadyExists();

        nonNFTAssets[assetId] = NonNFTAsset({
            assetType: assetType,
            assetId: assetId,
            metadata: metadata,
            owner: msg.sender,
            transferable: transferable,
            expiryTime: expiryTime
        });

        emit NonNFTAssetRegistered(assetId, msg.sender, assetType);
    }

    function updateNonNFTAsset(
        string calldata assetId,
        bytes calldata metadata,
        bool transferable,
        uint256 expiryTime
    ) external {
        NonNFTAsset storage asset = nonNFTAssets[assetId];
        if (asset.owner != msg.sender) revert Bridge__NotOwner();

        asset.metadata = metadata;
        asset.transferable = transferable;
        asset.expiryTime = expiryTime;

        emit NonNFTAssetUpdated(assetId, msg.sender);
    }

    function transferNonNFTAsset(
        string calldata assetId,
        address to
    ) external {
        NonNFTAsset storage asset = nonNFTAssets[assetId];
        if (asset.owner != msg.sender) revert Bridge__NotOwner();
        if (!asset.transferable) revert Bridge__AssetNotTransferable();
        if (asset.expiryTime != 0 && asset.expiryTime < block.timestamp) revert Bridge__AssetExpired();

        asset.owner = to;
        emit NonNFTAssetTransferred(assetId, msg.sender, to);
    }

    // Emergency functions
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            // Withdraw native tokens
            if (address(this).balance < amount) revert Bridge__InsufficientBalance();
            (bool success, ) = payable(owner()).call{value: amount}("");
            if (!success) revert Bridge__TransferFailed();
        } else {
            // Withdraw ERC20 tokens
            if (IERC20(token).balanceOf(address(this)) < amount) revert Bridge__InsufficientBalance();
            IERC20(token).safeTransfer(owner(), amount);
        }

        emit EmergencyWithdraw(token, amount, owner());
    }



    // Internal helper functions
    function _removeFromChainsList(uint16 chainId) internal {
        uint256 length = supportedChainsList.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (supportedChainsList[i] == chainId) {
                    supportedChainsList[i] = supportedChainsList[length - 1];
                    supportedChainsList.pop();
                    break;
                }
            }
        }
    }

    function _removeFromAssetTypesList(uint8 assetType) internal {
        uint256 length = validAssetTypesList.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (validAssetTypesList[i] == assetType) {
                    validAssetTypesList[i] = validAssetTypesList[length - 1];
                    validAssetTypesList.pop();
                    break;
                }
            }
        }
    }
}
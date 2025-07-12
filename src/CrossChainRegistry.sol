// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VertixUtils} from "./libraries/VertixUtils.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {MarketplaceStorage} from "./MarketplaceStorage.sol";

contract CrossChainRegistry {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error CCR__NotAuthorized();
    error CCR__NotOwner();
    error CCR__AssetNotExists();
    error CCR__AssetAlreadyExists();
    error CCR__InvalidChainType();
    error CCR__UnsupportedChain();
    error CCR__UnauthorizedTransfer();
    error CCR__InvalidListing();

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct CrossChainAsset {
        address originContract;
        address targetContract;
        uint96 lastSyncPrice;
        uint64 lastSyncBlock;
        uint32 syncCount;
        uint16 flags; // bit 0=active, bit 1=verified, bit 2=locked
        uint8 originChain;
        uint8 targetChain;
        uint256 tokenId;
    }

    struct BridgeRequest {
        address owner;
        address nftContract;
        address targetContract;
        uint256 tokenId;
        uint96 fee;
        uint64 timestamp;
        uint8 targetChainType;
        uint8 status;
        uint8 assetType;
        bool isNft;
        string assetId;
    }

    struct PendingMessage {
        bytes32 messageHash;
        uint64 timestamp;
        uint32 retryCount;
        uint8 messageType;
        uint8 sourceChain;
        uint8 targetChain;
        bool processed;
    }

    struct ChainConfig {
        address bridgeContract;
        address governanceContract;
        uint64 lastBlockSynced;
        uint32 confirmationBlocks;
        uint16 feeBps;
        bool isActive;
    }

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public owner;
    address public marketplaceStorage; // Added for non-NFT listing checks
    mapping(address => bool) public authorizedContracts;

    mapping(bytes32 => CrossChainAsset) public crossChainAssets;
    mapping(uint8 => ChainConfig) public chainConfigs;
    mapping(bytes32 => PendingMessage) public pendingMessages;
    mapping(uint8 => bytes32[]) public chainMessageQueues;
    mapping(address => mapping(uint256 => bytes32)) public assetToChainId;
    mapping(uint8 => uint256) public chainAssetCounts;

    // Moved from CrossChainBridge
    mapping(bytes32 => BridgeRequest) public bridgeRequests;
    mapping(address => bytes32[]) public userBridgeRequests;
    uint256 public totalBridgeRequests;

    uint256 public totalCrossChainAssets;
    uint64 public lastGlobalSync;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event CrossChainAssetRegistered(
        bytes32 indexed assetId,
        uint8 indexed originChain,
        uint8 indexed targetChain,
        address originContract,
        uint256 tokenId
    );
    event CrossChainMessageQueued(
        bytes32 indexed messageHash,
        uint8 indexed sourceChain,
        uint8 indexed targetChain,
        uint8 messageType
    );
    event CrossChainSyncCompleted(
        bytes32 indexed assetId,
        uint8 indexed chainType,
        uint96 syncedPrice,
        uint64 blockNumber
    );
    event ChainConfigUpdated(
        uint8 indexed chainType,
        address bridgeContract,
        bool isActive
    );
    event BridgeRequestCreated(
        bytes32 indexed requestId,
        address indexed owner,
        uint16 indexed targetChainId,
        uint256 tokenId,
        uint96 fee
    );
    event AssetUnlocked(
        bytes32 indexed requestId,
        address indexed owner,
        address nftContract,
        uint256 tokenId
    );
    event NonNftAssetUnlocked(
        bytes32 indexed requestId,
        address indexed owner,
        uint8 assetType,
        string assetId
    );

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender]) revert CCR__NotAuthorized();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert CCR__NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _owner, address _marketplaceStorage) {
        owner = _owner;
        marketplaceStorage = _marketplaceStorage;
        authorizedContracts[_owner] = true;
        lastGlobalSync = uint64(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                           ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/
    function authorizeContract(address contractAddr, bool authorized) external onlyOwner {
        authorizedContracts[contractAddr] = authorized;
    }

    /*//////////////////////////////////////////////////////////////
                      CHAIN CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    function setChainConfig(
        uint8 chainType,
        address bridgeContract,
        address governanceContract,
        uint32 confirmationBlocks,
        uint16 feeBps,
        bool isActive
    ) external onlyOwner {
        chainConfigs[chainType] = ChainConfig({
            bridgeContract: bridgeContract,
            governanceContract: governanceContract,
            lastBlockSynced: uint64(block.number),
            confirmationBlocks: confirmationBlocks,
            feeBps: feeBps,
            isActive: isActive
        });
        emit ChainConfigUpdated(chainType, bridgeContract, isActive);
    }

    /*//////////////////////////////////////////////////////////////
                     CROSS-CHAIN ASSET MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    function registerCrossChainAsset(
        address originContract,
        uint256 tokenId,
        uint8 originChain,
        uint8 targetChain,
        address targetContract,
        uint96 initialPrice
    ) external onlyAuthorized returns (bytes32 assetId) {
        assetId = VertixUtils.createCrossChainAssetId(VertixUtils.ChainType(originChain), originContract, tokenId);
        if (crossChainAssets[assetId].originContract != address(0)) revert CCR__AssetAlreadyExists();

        crossChainAssets[assetId] = CrossChainAsset({
            originContract: originContract,
            targetContract: targetContract,
            lastSyncPrice: initialPrice,
            lastSyncBlock: uint64(block.number),
            syncCount: 0,
            flags: 1, // Active
            originChain: originChain,
            targetChain: targetChain,
            tokenId: tokenId
        });

        assetToChainId[originContract][tokenId] = assetId;
        chainAssetCounts[originChain]++;
        totalCrossChainAssets++;

        emit CrossChainAssetRegistered(assetId, originChain, targetChain, originContract, tokenId);
    }

    function updateAssetSync(
        bytes32 assetId,
        uint96 newPrice,
        uint8 targetChain
    ) external onlyAuthorized {
        CrossChainAsset storage asset = crossChainAssets[assetId];
        if (asset.originContract == address(0)) revert CCR__AssetNotExists();

        asset.lastSyncPrice = newPrice;
        asset.lastSyncBlock = uint64(block.number);
        asset.syncCount++;
        emit CrossChainSyncCompleted(assetId, targetChain, newPrice, uint64(block.number));
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN MESSAGE QUEUE
    //////////////////////////////////////////////////////////////*/
    function queueCrossChainMessage(
        uint8 messageType,
        uint8 sourceChain,
        uint8 targetChain,
        bytes calldata payload
    ) external onlyAuthorized returns (bytes32 messageHash) {
        VertixUtils.CrossChainMessage memory message = VertixUtils.CrossChainMessage({
            messageType: messageType,
            sourceChain: sourceChain,
            targetChain: targetChain,
            timestamp: uint64(block.timestamp),
            messageHash: bytes32(0),
            payload: payload
        });

        messageHash = keccak256(abi.encodePacked(message.messageType, message.sourceChain, message.targetChain, message.timestamp, message.payload));
        message.messageHash = messageHash;

        pendingMessages[messageHash] = PendingMessage({
            messageHash: messageHash,
            timestamp: uint64(block.timestamp),
            retryCount: 0,
            messageType: messageType,
            sourceChain: sourceChain,
            targetChain: targetChain,
            processed: false
        });

        chainMessageQueues[targetChain].push(messageHash);
        emit CrossChainMessageQueued(messageHash, sourceChain, targetChain, messageType);
    }

    function markMessageProcessed(bytes32 messageHash) external onlyAuthorized {
        pendingMessages[messageHash].processed = true;
    }

    /*//////////////////////////////////////////////////////////////
                    BRIDGE REQUEST MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    function registerBridgeRequest(
        address sender,
        address contractAddr,
        uint256 tokenId,
        uint8 targetChainType,
        address targetContract,
        uint96 fee,
        bool isNft,
        uint8 assetType,
        string memory assetId
    ) external onlyAuthorized returns (bytes32 requestId) {
        requestId = isNft
            ? keccak256(abi.encodePacked(sender, contractAddr, tokenId, targetChainType, block.timestamp))
            : keccak256(abi.encodePacked(sender, contractAddr, assetId, targetChainType, block.timestamp));

        bridgeRequests[requestId] = BridgeRequest({
            owner: sender,
            nftContract: contractAddr,
            targetContract: targetContract,
            tokenId: tokenId,
            fee: fee,
            timestamp: uint64(block.timestamp),
            targetChainType: targetChainType,
            status: 0,
            isNft: isNft,
            assetType: assetType,
            assetId: assetId
        });

        userBridgeRequests[sender].push(requestId);
        totalBridgeRequests++;

        bytes32 crossChainAssetId = isNft
            ? VertixUtils.createCrossChainAssetId(VertixUtils.ChainType(chainConfigs[targetChainType].lastBlockSynced), contractAddr, tokenId)
            : keccak256(abi.encodePacked(chainConfigs[targetChainType].lastBlockSynced, contractAddr, assetId));

        CrossChainAsset storage asset = crossChainAssets[crossChainAssetId];
        if (asset.originContract == address(0)) {
            asset.originContract = contractAddr;
            asset.targetContract = targetContract;
            asset.originChain = uint8(chainConfigs[targetChainType].lastBlockSynced);
            asset.targetChain = targetChainType;
            asset.tokenId = tokenId;
            asset.flags = 5; // Active (bit 0) + Locked (bit 2)
            chainAssetCounts[asset.originChain]++;
            totalCrossChainAssets++;
        } else {
            asset.flags |= 4; // Set locked flag
        }

        emit BridgeRequestCreated(requestId, sender, chainConfigs[targetChainType].feeBps, tokenId, fee);
    }

    function lockAsset(
        address sender,
        address contractAddr,
        uint256 tokenId,
        bool isNft,
        string memory assetId,
        uint8 originChain
    ) external onlyAuthorized {
        bytes32 crossChainAssetId = isNft
            ? VertixUtils.createCrossChainAssetId(VertixUtils.ChainType(originChain), contractAddr, tokenId)
            : keccak256(abi.encodePacked(originChain, contractAddr, assetId));

        CrossChainAsset storage asset = crossChainAssets[crossChainAssetId];
        if (asset.originContract == address(0)) revert CCR__AssetNotExists();
        if (isNft && IERC721(contractAddr).ownerOf(tokenId) != sender) revert CCR__UnauthorizedTransfer();
        if (!isNft) {
            // Assume MarketplaceStorage has a similar interface
            (address seller, , , bool active, , string memory storedAssetId, ,) = MarketplaceStorage(marketplaceStorage).getNonNftListing(tokenId);
            if (seller != sender) revert CCR__UnauthorizedTransfer();
            if (!active || keccak256(bytes(storedAssetId)) != keccak256(bytes(assetId))) revert CCR__InvalidListing();
            MarketplaceStorage(marketplaceStorage).updateNonNftListingFlags(tokenId, 0);
        }

        asset.flags |= 4; // Set locked flag
        if (isNft) {
            IERC721(contractAddr).transferFrom(sender, address(this), tokenId);
        }
    }

    function unlockAsset(
        bytes32 requestId,
        address assetOwner,
        address contractAddr,
        uint256 tokenId,
        bool isNft,
        uint8 assetType,
        string memory assetId,
        uint8 sourceChain
    ) external onlyAuthorized {
        bytes32 crossChainAssetId = isNft
            ? VertixUtils.createCrossChainAssetId(VertixUtils.ChainType(sourceChain), contractAddr, tokenId)
            : keccak256(abi.encodePacked(sourceChain, contractAddr, assetId));

        CrossChainAsset storage asset = crossChainAssets[crossChainAssetId];
        if (asset.originContract == address(0)) revert CCR__AssetNotExists();
        if ((asset.flags & 4) == 0) return; // Not locked

        asset.flags &= ~uint16(4); // Clear locked flag
        if (isNft) {
            IERC721(contractAddr).transferFrom(address(this), assetOwner, tokenId);
            emit AssetUnlocked(requestId, assetOwner, contractAddr, tokenId);
        } else {
            MarketplaceStorage(marketplaceStorage).updateNonNftListingFlags(tokenId, 1);
            emit NonNftAssetUnlocked(requestId, assetOwner, assetType, assetId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getCrossChainAsset(bytes32 assetId) external view returns (
        address originContract,
        address targetContract,
        uint256 tokenId,
        uint96 lastSyncPrice,
        uint64 lastSyncBlock,
        uint8 originChain,
        uint8 targetChain,
        bool isActive,
        bool isVerified,
        bool isLocked
    ) {
        CrossChainAsset memory asset = crossChainAssets[assetId];
        return (
            asset.originContract,
            asset.targetContract,
            asset.tokenId,
            asset.lastSyncPrice,
            asset.lastSyncBlock,
            asset.originChain,
            asset.targetChain,
            (asset.flags & 1) == 1,
            (asset.flags & 2) == 2,
            (asset.flags & 4) == 4
        );
    }

    function getChainMessageQueue(uint8 chainType) external view returns (bytes32[] memory) {
        return chainMessageQueues[chainType];
    }

    function getPendingMessageCount(uint8 chainType) external view returns (uint256) {
        bytes32[] memory messages = chainMessageQueues[chainType];
        uint256 pending = 0;
        for (uint256 i = 0; i < messages.length; i++) {
            if (!pendingMessages[messages[i]].processed) pending++;
        }
        return pending;
    }

    function getAssetIdByContract(address contractAddr, uint256 tokenId) external view returns (bytes32) {
        return assetToChainId[contractAddr][tokenId];
    }

    function getChainConfig(uint8 chainType) external view returns (ChainConfig memory) {
        return chainConfigs[chainType];
    }

    function getBridgeRequest(bytes32 requestId) external view returns (BridgeRequest memory) {
        return bridgeRequests[requestId];
    }

    function getUserBridgeRequests(address user) external view returns (bytes32[] memory) {
        return userBridgeRequests[user];
    }
}
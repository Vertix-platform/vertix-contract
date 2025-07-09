// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VertixUtils} from "./libraries/VertixUtils.sol";

/**
 * @title CrossChainRegistry
 * @dev Centralized storage for cross-chain asset tracking and synchronization
 * Follows the same pattern as MarketplaceStorage for consistency
 */
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

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    // Gas-optimized cross-chain asset tracking
    struct CrossChainAsset {
        address originContract;     // Original contract address
        address targetContract;     // Target chain contract address  
        uint96 lastSyncPrice;      // Last synced price (supports up to ~79B ETH)
        uint64 lastSyncBlock;      // Last sync block number
        uint32 syncCount;          // Number of syncs performed
        uint16 flags;              // Packed flags: bit 0=active, bit 1=verified, bit 2=locked
        uint8 originChain;         // Origin ChainType
        uint8 targetChain;         // Target ChainType
        uint256 tokenId;           // Token ID
    }

    // Cross-chain message queue (gas-optimized)
    struct PendingMessage {
        bytes32 messageHash;
        uint64 timestamp;
        uint32 retryCount;
        uint8 messageType;         // MessageType enum
        uint8 sourceChain;         // Source chain
        uint8 targetChain;         // Target chain
        bool processed;
    }

    // Chain configuration
    struct ChainConfig {
        address bridgeContract;    // Bridge contract on this chain
        address governanceContract; // Governance contract on this chain
        uint64 lastBlockSynced;    // Last block number synced
        uint32 confirmationBlocks; // Required confirmations
        uint16 feeBps;            // Cross-chain fee in basis points
        bool isActive;            // Chain is active for cross-chain operations
    }

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    address public owner;
    mapping(address => bool) public authorizedContracts;
    
    // Cross-chain asset tracking
    mapping(bytes32 => CrossChainAsset) public crossChainAssets;
    mapping(uint8 => ChainConfig) public chainConfigs; // ChainType => Config
    
    // Message queue for cross-chain communication
    mapping(bytes32 => PendingMessage) public pendingMessages;
    mapping(uint8 => bytes32[]) public chainMessageQueues; // ChainType => message hashes
    
    // Asset mappings for efficient lookups
    mapping(address => mapping(uint256 => bytes32)) public assetToChainId; // contract => tokenId => chainAssetId
    mapping(uint8 => uint256) public chainAssetCounts; // ChainType => count
    
    // Sync tracking
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

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender]) {
            revert CCR__NotAuthorized();
        }
        _;
    }
    
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert CCR__NotOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address _owner) {
        owner = _owner;
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
        assetId = VertixUtils.createCrossChainAssetId(
            VertixUtils.ChainType(originChain),
            originContract,
            tokenId
        );
        
        if (crossChainAssets[assetId].originContract != address(0)) {
            revert CCR__AssetAlreadyExists();
        }
        
        crossChainAssets[assetId] = CrossChainAsset({
            originContract: originContract,
            targetContract: targetContract,
            lastSyncPrice: initialPrice,
            lastSyncBlock: uint64(block.number),
            syncCount: 0,
            flags: 1, // Set active flag
            originChain: originChain,
            targetChain: targetChain,
            tokenId: tokenId
        });
        
        assetToChainId[originContract][tokenId] = assetId;
        chainAssetCounts[originChain]++;
        totalCrossChainAssets++;
        
        emit CrossChainAssetRegistered(
            assetId,
            originChain,
            targetChain,
            originContract,
            tokenId
        );
    }
    
    function updateAssetSync(
        bytes32 assetId,
        uint96 newPrice,
        uint8 targetChain
    ) external onlyAuthorized {
        CrossChainAsset storage asset = crossChainAssets[assetId];
        if (asset.originContract == address(0)) {
            revert CCR__AssetNotExists();
        }
        
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
            messageHash: bytes32(0), // Will be set after hashing
            payload: payload
        });

        messageHash = keccak256(abi.encodePacked(
            message.messageType,
            message.sourceChain,
            message.targetChain,
            message.timestamp,
            message.payload
        ));
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
        bool isVerified
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
            (asset.flags & 1) == 1,  // isActive
            (asset.flags & 2) == 2   // isVerified
        );
    }
    
    function getChainMessageQueue(uint8 chainType) external view returns (bytes32[] memory) {
        return chainMessageQueues[chainType];
    }
    
    function getPendingMessageCount(uint8 chainType) external view returns (uint256) {
        bytes32[] memory messages = chainMessageQueues[chainType];
        uint256 pending = 0;
        for (uint256 i = 0; i < messages.length; i++) {
            if (!pendingMessages[messages[i]].processed) {
                pending++;
            }
        }
        return pending;
    }
    
    function getAssetIdByContract(address contractAddr, uint256 tokenId) external view returns (bytes32) {
        return assetToChainId[contractAddr][tokenId];
    }
    
    function getChainConfig(uint8 chainType) external view returns (ChainConfig memory) {
        return chainConfigs[chainType];
    }
} 
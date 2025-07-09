// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {VertixUtils} from "./libraries/VertixUtils.sol";
import {CrossChainRegistry} from "./CrossChainRegistry.sol";
import {MarketplaceStorage} from "./MarketplaceStorage.sol";
import {IVertixGovernance} from "./interfaces/IVertixGovernance.sol";
import {ICrossChainBridge} from "./interfaces/ICrossChainBrigde.sol";

// LayerZero official imports
import {ILayerZeroEndpoint} from "@layerzero-contracts/lzApp/interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "@layerzero-contracts/lzApp/interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroUserApplicationConfig} from "@layerzero-contracts/lzApp/interfaces/ILayerZeroUserApplicationConfig.sol";

/**
 * @title CrossChainBridge
 * @dev Handles cross-chain asset transfers using LayerZero protocol
 */
contract CrossChainBridge is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ILayerZeroReceiver,
    ILayerZeroUserApplicationConfig,
    ICrossChainBridge
{

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    ILayerZeroEndpoint public layerZeroEndpoint;
    CrossChainRegistry public immutable REGISTRY_CONTRACT;
    MarketplaceStorage public immutable MARKETPLACE_STORAGE;
    IVertixGovernance public immutable GOVERNANCE_CONTRACT;

    // Bridge configuration
    uint8 public currentChainType;
    uint256 public minimumBridgeFee;

    // LayerZero configuration
    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(uint16 => mapping(uint16 => uint)) public minDstGasLookup;
    mapping(uint16 => uint) public payloadSizeLimitLookup;

    // Chain configuration
    mapping(uint8 => uint16) public chainTypeToLayerZeroId;
    mapping(uint16 => uint8) public layerZeroIdToChainType;
    mapping(uint8 => bool) public supportedChains;

    // Cross-chain asset tracking
    mapping(bytes32 => BridgeRequest) public bridgeRequests;
    mapping(bytes32 => bool) public processedMessages;
    mapping(address => bytes32[]) public userBridgeRequests;
    mapping(bytes32 => bool) public lockedAssets;

    // Failed message storage
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;

    // Request tracking
    uint256 public totalBridgeRequests;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event BridgeRequestCreated(
        bytes32 indexed requestId,
        address indexed owner,
        uint16 indexed targetChainId,
        uint256 tokenId,
        uint96 fee
    );

    event AssetBridged(
        bytes32 indexed requestId,
        address indexed owner,
        uint8 indexed targetChain,
        address nftContract,
        uint256 tokenId
    );

    event AssetUnlocked(
        bytes32 indexed requestId,
        address indexed owner,
        address nftContract,
        uint256 tokenId
    );

    event NonNftAssetBridged(
        bytes32 indexed requestId,
        address indexed owner,
        uint8 indexed targetChain,
        uint8 assetType,
        string assetId
    );

    event NonNftAssetUnlocked(
        bytes32 indexed requestId,
        address indexed owner,
        uint8 assetType,
        string assetId
    );

    struct BridgeParams {
        bool isNft;                // True for NFT, false for non-NFT
        address contractAddr;      // For NFTs: NFT contract, For non-NFTs: marketplace contract
        uint256 tokenId;          // For NFTs: token ID, For non-NFTs: listing ID
        uint8 assetType;          // For non-NFTs: asset type (ignored for NFTs)
        string assetId;           // For non-NFTs: asset identifier (ignored for NFTs)
        uint8 targetChainType;
        address targetContract;
        bytes adapterParams;
    }

    event TrustedRemoteSet(uint16 indexed chainId, bytes trustedRemote);
    event MessageFailed(uint16 indexed srcChainId, bytes srcAddress, uint64 nonce, bytes payload);
    event RetryMessageSuccess(uint16 indexed srcChainId, bytes srcAddress, uint64 nonce, bytes32 payloadHash);
    event ChainSupported(uint8 indexed chainType, uint16 layerZeroId, bool supported);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier supportedChain(uint8 chainType) {
        if (!supportedChains[chainType]) {
            revert CCB__InvalidChainType();
        }
        _;
    }

    modifier onlyEndpoint() {
        if (msg.sender != address(layerZeroEndpoint)) {
            revert CCB__OnlyEndpoint();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _registryContract,
        address _marketplaceStorage,
        address _governanceContract
    ) {
        REGISTRY_CONTRACT = CrossChainRegistry(_registryContract);
        MARKETPLACE_STORAGE = MarketplaceStorage(_marketplaceStorage);
        GOVERNANCE_CONTRACT = IVertixGovernance(_governanceContract);
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address _layerZeroEndpoint,
        uint8 _currentChainType,
        uint256 _minimumBridgeFee
    ) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        layerZeroEndpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
        currentChainType = _currentChainType;
        minimumBridgeFee = _minimumBridgeFee;

        // Set up chain mappings (standard LayerZero chain IDs)
        if (_currentChainType == uint8(VertixUtils.ChainType.Polygon)) {
            chainTypeToLayerZeroId[uint8(VertixUtils.ChainType.Polygon)] = 109; // Polygon
            chainTypeToLayerZeroId[uint8(VertixUtils.ChainType.Base)] = 184; // Base
        } else if (_currentChainType == uint8(VertixUtils.ChainType.Base)) {
            chainTypeToLayerZeroId[uint8(VertixUtils.ChainType.Base)] = 184; // Base
            chainTypeToLayerZeroId[uint8(VertixUtils.ChainType.Polygon)] = 109; // Polygon
        }

        // Set reverse mappings
        layerZeroIdToChainType[109] = uint8(VertixUtils.ChainType.Polygon);
        layerZeroIdToChainType[184] = uint8(VertixUtils.ChainType.Base);

        // Enable supported chains
        supportedChains[uint8(VertixUtils.ChainType.Polygon)] = true;
        supportedChains[uint8(VertixUtils.ChainType.Base)] = true;
    }

    // UUPS upgradeability
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(owner()).transfer(balance);
        }
    }

    function emergencyWithdraw(address token, uint256 tokenId) external onlyOwner {
        _safeTransferNft(token, address(this), owner(), tokenId);
    }

    function setTrustedRemote(uint16 _srcChainId, bytes calldata _path) external onlyOwner {
        trustedRemoteLookup[_srcChainId] = _path;
        emit TrustedRemoteSet(_srcChainId, _path);
    }

    function setMinDstGas(uint16 _dstChainId, uint16 _packetType, uint _minGas) external onlyOwner {
        minDstGasLookup[_dstChainId][_packetType] = _minGas;
    }

    function setPayloadSizeLimit(uint16 _dstChainId, uint _size) external onlyOwner {
        payloadSizeLimitLookup[_dstChainId] = _size;
    }

    /*//////////////////////////////////////////////////////////////
                     BRIDGE CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    function setMinimumBridgeFee(uint256 _minimumBridgeFee) external onlyOwner {
        minimumBridgeFee = _minimumBridgeFee;
    }

    function setSupportedChain(uint8 chainType, uint16 layerZeroId, bool supported) external onlyOwner {
        supportedChains[chainType] = supported;
        chainTypeToLayerZeroId[chainType] = layerZeroId;
        layerZeroIdToChainType[layerZeroId] = chainType;
        emit ChainSupported(chainType, layerZeroId, supported);
    }

    /*//////////////////////////////////////////////////////////////
                      LAYERZERO APP CONFIG
    //////////////////////////////////////////////////////////////*/

    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint _configType,
        bytes calldata _config
    ) external override onlyOwner {
        layerZeroEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) external override onlyOwner {
        layerZeroEndpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) external override onlyOwner {
        layerZeroEndpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
        layerZeroEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }


    /*//////////////////////////////////////////////////////////////
                        BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function bridgeAsset(BridgeParams calldata params) external payable nonReentrant whenNotPaused {
        // Get LayerZero chain ID
        uint16 targetLayerZeroChainId = chainTypeToLayerZeroId[params.targetChainType];
        if (targetLayerZeroChainId == 0) {
            revert CCB__InvalidDestinationChain();
        }

        bytes32 requestId;
        bytes32 assetId;
        MessageType messageType;

        if (params.isNft) {
            // NFT Asset Bridging
            if (IERC721(params.contractAddr).ownerOf(params.tokenId) != msg.sender) {
                revert CCB__UnauthorizedTransfer();
            }

            // Generate IDs for NFT
            requestId = keccak256(abi.encodePacked(
                msg.sender,
                params.contractAddr,
                params.tokenId,
                params.targetChainType,
                block.timestamp
            ));

            assetId = VertixUtils.createCrossChainAssetId(
                VertixUtils.ChainType(currentChainType),
                params.contractAddr,
                params.tokenId
            );

            messageType = MessageType.ASSET_TRANSFER;

        } else {
            // Non-NFT Asset Bridging
            // Verify ownership through marketplace storage
            (address seller, , , bool active, , string memory storedAssetId, ,) = 
                MARKETPLACE_STORAGE.getNonNftListing(params.tokenId);

            if (seller != msg.sender) {
                revert CCB__UnauthorizedTransfer();
            }
            if (!active) {
                revert CCB__InvalidListing();
            }
            if (keccak256(bytes(storedAssetId)) != keccak256(bytes(params.assetId))) {
                revert CCB__InvalidListing();
            }

            // Generate IDs for non-NFT
            requestId = keccak256(abi.encodePacked(
                msg.sender,
                params.contractAddr,
                params.assetId,
                params.targetChainType,
                block.timestamp
            ));

            assetId = keccak256(abi.encodePacked(
                currentChainType,
                params.contractAddr,
                params.assetId
            ));

            messageType = MessageType.NON_NFT_TRANSFER;
        }

        // Create LayerZero message with unified payload
        bytes memory payload = abi.encode(
            messageType,
            requestId,
            msg.sender,
            params.contractAddr,
            params.tokenId,
            params.targetContract,
            block.timestamp,
            params.isNft,
            params.assetType,
            params.assetId
        );

        // Calculate fees
        (uint256 nativeFee,) = layerZeroEndpoint.estimateFees(
            targetLayerZeroChainId,
            address(this),
            payload,
            false,
            params.adapterParams
        );

        uint256 totalFee = nativeFee + minimumBridgeFee;
        if (msg.value < totalFee) {
            revert CCB__InsufficientFee();
        }

        // Lock the asset based on type
        if (params.isNft) {
            _safeTransferNft(params.contractAddr, msg.sender, address(this), params.tokenId);
        } else {
            // For non-NFT assets, we mark them as inactive in marketplace to prevent double-spending
            MARKETPLACE_STORAGE.updateNonNftListingFlags(params.tokenId, 0);
        }
        lockedAssets[assetId] = true;

        // Create unified bridge request
        bridgeRequests[requestId] = BridgeRequest({
            owner: msg.sender,
            nftContract: params.contractAddr,
            tokenId: params.tokenId,
            targetChainType: params.targetChainType,
            targetContract: params.targetContract,
            fee: uint96(totalFee),
            timestamp: uint64(block.timestamp),
            status: 0, // pending
            isNft: params.isNft,
            assetType: params.assetType,
            assetId: params.assetId
        });

        // Register in cross-chain registry
        REGISTRY_CONTRACT.registerCrossChainAsset(
            params.contractAddr,
            params.tokenId,
            currentChainType,
            params.targetChainType,
            params.targetContract,
            uint96(totalFee)
        );

        // Track user requests
        userBridgeRequests[msg.sender].push(requestId);
        totalBridgeRequests++;

        // Send LayerZero message
        layerZeroEndpoint.send{value: msg.value}(
            targetLayerZeroChainId,
            trustedRemoteLookup[targetLayerZeroChainId],
            payload,
            payable(msg.sender),
            address(0),
            params.adapterParams
        );

        emit BridgeRequestCreated(
            requestId,
            msg.sender,
            targetLayerZeroChainId,
            params.tokenId,
            uint96(totalFee)
        );
    }

    /*//////////////////////////////////////////////////////////////
                     LAYERZERO RECEIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external override onlyEndpoint {
        bytes32 hashedPayload = keccak256(_payload);

        // Check if message already processed
        if (processedMessages[hashedPayload]) {
            revert CCB__MessageAlreadyProcessed();
        }

        // Try to process the message
        try this.nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload) {
            // Mark as processed
            processedMessages[hashedPayload] = true;
        } catch {
            // Store failed message
            failedMessages[_srcChainId][_srcAddress][_nonce] = hashedPayload;
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload);
        }
    }

    function nonblockingLzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public {
        // Only internal transaction
        require(msg.sender == address(this), "CCB: caller must be bridge");
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    /*//////////////////////////////////////////////////////////////
                        RETRY FAILED MESSAGES
    //////////////////////////////////////////////////////////////*/

    function retryMessage(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external payable {
        bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
        if (payloadHash == bytes32(0)) {
            revert CCB__NoStoredMessage();
        }

        if (keccak256(_payload) != payloadHash) {
            revert CCB__InvalidPayload();
        }

        delete failedMessages[_srcChainId][_srcAddress][_nonce];

        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);

        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _nonblockingLzReceive(
    uint16 _srcChainId,
    bytes memory /* _srcAddress */,
    uint64 /* _nonce */,
    bytes memory _payload
) internal {
    uint8 srcChainType = layerZeroIdToChainType[_srcChainId];

    PayloadData memory data = abi.decode(_payload, (PayloadData));

    if (data.messageType == MessageType.ASSET_TRANSFER) {
        _handleAssetTransfer(
            data.requestId,
            data.owner,
            data.contractAddr,
            data.tokenId,
            data.targetContract,
            srcChainType
        );
    } else if (data.messageType == MessageType.NON_NFT_TRANSFER) {
        _handleNonNftTransfer(
            data.requestId,
            data.owner,
            data.contractAddr,
            data.tokenId,
            data.assetType,
            data.assetId,
            data.targetContract,
            srcChainType
        );
    }
}

    /**
     * @dev Safely transfer ERC721 token with proper error handling
     */
    function _safeTransferNft(address nftContract, address from, address to, uint256 tokenId) internal {
        try IERC721(nftContract).transferFrom(from, to, tokenId) {
            // Verify transfer succeeded by checking ownership
            if (IERC721(nftContract).ownerOf(tokenId) != to) {
                revert CCB__TransferFailed();
            }
        } catch {
            revert CCB__TransferFailed();
        }
    }

    function _handleAssetTransfer(
        bytes32 requestId,
        address owner,
        address nftContract,
        uint256 tokenId,
        address /* targetContract */,
        uint8 srcChainType
    ) internal {
        // Create asset ID
        bytes32 assetId = VertixUtils.createCrossChainAssetId(
            VertixUtils.ChainType(srcChainType),
            nftContract,
            tokenId
        );

        // Check if asset is locked (should be unlocked on destination)
        if (lockedAssets[assetId]) {
            // Unlock the asset
            delete lockedAssets[assetId];
            _safeTransferNft(nftContract, address(this), owner, tokenId);

            emit AssetUnlocked(requestId, owner, nftContract, tokenId);
        } else {
            // This is a new asset arrival - mint or transfer
            // Implementation depends on your NFT contract design
            emit AssetBridged(requestId, owner, currentChainType, nftContract, tokenId);
        }
    }

    function _handleNonNftTransfer(
        bytes32 requestId,
        address owner,
        address marketplaceContract,
        uint256 listingId,
        uint8 assetType,
        string memory assetIdStr,
        address /* targetContract */,
        uint8 srcChainType
    ) internal {
        // Create asset ID for non-NFT
        bytes32 assetId = keccak256(abi.encodePacked(
            srcChainType,
            marketplaceContract,
            assetIdStr
        ));

        // Check if asset is locked (should be unlocked/reactivated on destination)
        if (lockedAssets[assetId]) {
            // Unlock the asset by reactivating the listing
            delete lockedAssets[assetId];
            MARKETPLACE_STORAGE.updateNonNftListingFlags(listingId, 1); // Reactivate

            emit NonNftAssetUnlocked(requestId, owner, assetType, assetIdStr);
        } else {
            // This is a new non-NFT asset arrival - create new listing
            // Implementation would depend on how you want to handle cross-chain non-NFT creation
            emit NonNftAssetBridged(requestId, owner, currentChainType, assetType, assetIdStr);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // function getBridgeRequest(bytes32 requestId) external view returns (BridgeRequest memory) {
    //     return bridgeRequests[requestId];
    // }

    // function getUserBridgeRequests(address user) external view returns (bytes32[] memory) {
    //     return userBridgeRequests[user];
    // }

    // function isAssetLocked(bytes32 assetId) external view returns (bool) {
    //     return lockedAssets[assetId];
    // }

    // function isTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool) {
    //     bytes memory trustedSource = trustedRemoteLookup[_srcChainId];
    //     return keccak256(trustedSource) == keccak256(_srcAddress);
    // }
    function estimateBridgeFee(BridgeParams calldata params)
        external
        view
        returns (uint256 nativeFee, uint256 totalFee)
    {
        uint16 targetLayerZeroChainId = chainTypeToLayerZeroId[params.targetChainType];
        if (targetLayerZeroChainId == 0) {
            revert CCB__InvalidDestinationChain();
        }

        bytes32 requestId;
        MessageType messageType;

        if (params.isNft) {
            requestId = keccak256(abi.encodePacked(
                msg.sender,
                params.contractAddr,
                params.tokenId,
                params.targetChainType,
                block.timestamp
            ));
            messageType = MessageType.ASSET_TRANSFER;
        } else {
            requestId = keccak256(abi.encodePacked(
                msg.sender,
                params.contractAddr,
                params.assetId,
                params.targetChainType,
                block.timestamp
            ));
            messageType = MessageType.NON_NFT_TRANSFER;
        }

        bytes memory payload = abi.encode(
            messageType,
            requestId,
            msg.sender,
            params.contractAddr,
            params.tokenId,
            params.targetContract,
            block.timestamp,
            params.isNft,
            params.assetType,
            params.assetId
        );

        (nativeFee,) = layerZeroEndpoint.estimateFees(
            targetLayerZeroChainId,
            address(this),
            payload,
            false,
            params.adapterParams
        );

        totalFee = nativeFee + minimumBridgeFee;
    }
}
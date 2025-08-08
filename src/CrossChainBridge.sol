// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {VertixUtils} from "./libraries/VertixUtils.sol";
import {CrossChainRegistry} from "./CrossChainRegistry.sol";
import {IVertixGovernance} from "./interfaces/IVertixGovernance.sol";
import {ILayerZeroEndpoint} from "@layerzero-contracts/lzApp/interfaces/ILayerZeroEndpoint.sol";
import {ILayerZeroReceiver} from "@layerzero-contracts/lzApp/interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroUserApplicationConfig} from "@layerzero-contracts/lzApp/interfaces/ILayerZeroUserApplicationConfig.sol";

contract CrossChainBridge is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ILayerZeroReceiver,
    ILayerZeroUserApplicationConfig,
    IERC721Receiver
{
    error CCB__InvalidChainType();
    error CCB__OnlyEndpoint();
    error CCB__InvalidDestinationChain();
    error CCB__InsufficientFee();
    error CCB__MessageAlreadyProcessed();
    error CCB__NoStoredMessage();
    error CCB__InvalidPayload();

    CrossChainRegistry public immutable REGISTRY_CONTRACT;
    IVertixGovernance public immutable GOVERNANCE_CONTRACT;

    struct BridgeParams {
        address contractAddr;
        address targetContract;
        uint256 tokenId;
        uint8 targetChainType;
        uint8 assetType;
        bool isNft;
        string assetId;
        bytes adapterParams;
    }

    enum MessageType { ASSET_TRANSFER, NON_NFT_TRANSFER }

    struct PayloadData {
        MessageType messageType;
        bytes32 requestId;
        address owner;
        address contractAddr;
        address targetContract;
        uint256 tokenId;
        uint64 timestamp;
        uint8 assetType;
        bool isNft;
        string assetId;
    }

    ILayerZeroEndpoint public layerZeroEndpoint;
    uint8 public currentChainType;
    uint256 public minimumBridgeFee;

    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(uint16 => mapping(uint16 => uint)) public minDstGasLookup;
    mapping(uint16 => uint) public payloadSizeLimitLookup;
    mapping(uint8 => uint16) public chainTypeToLayerZeroId;
    mapping(uint16 => uint8) public layerZeroIdToChainType;
    mapping(uint8 => bool) public supportedChains;
    mapping(bytes32 => bool) public processedMessages;
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;

    event AssetBridged(bytes32 indexed requestId, address indexed owner, uint8 indexed targetChain, address nftContract, uint256 tokenId);
    event NonNftAssetBridged(bytes32 indexed requestId, address indexed owner, uint8 indexed targetChain, uint8 assetType, string assetId);
    event TrustedRemoteSet(uint16 indexed chainId, bytes trustedRemote);
    event MessageFailed(uint16 indexed srcChainId, bytes srcAddress, uint64 nonce, bytes payload);
    event RetryMessageSuccess(uint16 indexed srcChainId, bytes srcAddress, uint64 nonce, bytes32 payloadHash);
    event ChainSupported(uint8 indexed chainType, uint16 layerZeroId, bool supported);

    modifier supportedChain(uint8 chainType) {
        if (!supportedChains[chainType]) revert CCB__InvalidChainType();
        _;
    }

    modifier onlyEndpoint() {
        if (msg.sender != address(layerZeroEndpoint)) revert CCB__OnlyEndpoint();
        _;
    }

    constructor(address _reg, address _gov) {
        REGISTRY_CONTRACT = CrossChainRegistry(_reg);
        GOVERNANCE_CONTRACT = IVertixGovernance(_gov);
        _disableInitializers();
    }

    function initialize(address _lzEndpoint, uint8 _chainType, uint256 _minFee) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        layerZeroEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        currentChainType = _chainType;
        minimumBridgeFee = _minFee;

        if (_chainType == uint8(VertixUtils.ChainType.Polygon)) {
            chainTypeToLayerZeroId[uint8(VertixUtils.ChainType.Polygon)] = 109;
            chainTypeToLayerZeroId[uint8(VertixUtils.ChainType.Base)] = 184;
        } else {
            chainTypeToLayerZeroId[uint8(VertixUtils.ChainType.Base)] = 184;
            chainTypeToLayerZeroId[uint8(VertixUtils.ChainType.Polygon)] = 109;
        }

        layerZeroIdToChainType[109] = uint8(VertixUtils.ChainType.Polygon);
        layerZeroIdToChainType[184] = uint8(VertixUtils.ChainType.Base);
        supportedChains[uint8(VertixUtils.ChainType.Polygon)] = true;
        supportedChains[uint8(VertixUtils.ChainType.Base)] = true;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function withdrawFees() external onlyOwner {
        uint256 bal = address(this).balance;
        if (bal > 0) payable(owner()).transfer(bal);
    }

    function emergencyWithdraw(address token, uint256 tokenId) external onlyOwner {
        IERC721(token).transferFrom(address(this), owner(), tokenId);
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
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

    function setMinimumBridgeFee(uint256 _fee) external onlyOwner {
        minimumBridgeFee = _fee;
    }

    function setSupportedChain(uint8 chainType, uint16 layerZeroId, bool supported) external onlyOwner {
        supportedChains[chainType] = supported;
        chainTypeToLayerZeroId[chainType] = layerZeroId;
        layerZeroIdToChainType[layerZeroId] = chainType;
        emit ChainSupported(chainType, layerZeroId, supported);
    }

    function setConfig(uint16 _version, uint16 _chainId, uint _configType, bytes calldata _config) external override onlyOwner {
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

    function _generateRequestId(address sender, BridgeParams calldata p) private view returns (bytes32) {
        return p.isNft
            ? keccak256(abi.encodePacked(sender, p.contractAddr, p.tokenId, p.targetChainType, block.timestamp))
            : keccak256(abi.encodePacked(sender, p.contractAddr, p.assetId, p.targetChainType, block.timestamp));
    }

    function _encodePayload(bytes32 reqId, address sender, BridgeParams calldata p) private view returns (bytes memory) {
        return abi.encode(
            p.isNft ? MessageType.ASSET_TRANSFER : MessageType.NON_NFT_TRANSFER,
            reqId,
            sender,
            p.contractAddr,
            p.tokenId,
            p.targetContract,
            block.timestamp,
            p.isNft,
            p.assetType,
            p.assetId
        );
    }

    function _estimateFees(uint16 targetLzId, bytes memory payload, bytes calldata adapterParams) private view returns (uint256 totalFee) {
        (uint256 nativeFee,) = layerZeroEndpoint.estimateFees(targetLzId, address(this), payload, false, adapterParams);
        totalFee = nativeFee + minimumBridgeFee;
    }

    function bridgeAsset(BridgeParams calldata p) external payable nonReentrant whenNotPaused supportedChain(p.targetChainType) {
        uint16 targetLzId = chainTypeToLayerZeroId[p.targetChainType];
        if (targetLzId == 0) revert CCB__InvalidDestinationChain();

        bytes32 reqId = _generateRequestId(msg.sender, p);
        bytes memory payload = _encodePayload(reqId, msg.sender, p);
        uint256 totalFee = _estimateFees(targetLzId, payload, p.adapterParams);

        if (msg.value < totalFee) revert CCB__InsufficientFee();

        REGISTRY_CONTRACT.lockAsset(msg.sender, p.contractAddr, p.tokenId, p.isNft, p.assetId, currentChainType);
        REGISTRY_CONTRACT.registerBridgeRequest(
            msg.sender,
            p.contractAddr,
            p.tokenId,
            p.targetChainType,
            p.targetContract,
            uint96(totalFee),
            p.isNft,
            p.assetType,
            p.assetId
        );

        layerZeroEndpoint.send{value: msg.value}(targetLzId, trustedRemoteLookup[targetLzId], payload, payable(msg.sender), address(0), p.adapterParams);
    }

    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) external override onlyEndpoint {
        bytes32 hash = keccak256(_payload);
        if (processedMessages[hash]) revert CCB__MessageAlreadyProcessed();

        try this.nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload) {
            processedMessages[hash] = true;
            REGISTRY_CONTRACT.markMessageProcessed(hash);
        } catch {
            failedMessages[_srcChainId][_srcAddress][_nonce] = hash;
            emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload);
        }
    }

    function nonblockingLzReceive(uint16 _srcChainId, bytes calldata, uint64, bytes calldata _payload) public {
        require(msg.sender == address(this), "CCB: invalid caller");

        uint8 srcChainType = layerZeroIdToChainType[_srcChainId];
        PayloadData memory data = abi.decode(_payload, (PayloadData));

        if (data.messageType == MessageType.ASSET_TRANSFER) {
            REGISTRY_CONTRACT.unlockAsset(data.requestId, data.owner, data.contractAddr, data.tokenId, true, 0, "", srcChainType);
            emit AssetBridged(data.requestId, data.owner, currentChainType, data.contractAddr, data.tokenId);
        } else {
            REGISTRY_CONTRACT.unlockAsset(data.requestId, data.owner, data.contractAddr, data.tokenId, false, data.assetType, data.assetId, srcChainType);
            emit NonNftAssetBridged(data.requestId, data.owner, currentChainType, data.assetType, data.assetId);
        }
    }

    function retryMessage(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) external payable {
        bytes32 hash = failedMessages[_srcChainId][_srcAddress][_nonce];
        if (hash == bytes32(0)) revert CCB__NoStoredMessage();
        if (keccak256(_payload) != hash) revert CCB__InvalidPayload();

        delete failedMessages[_srcChainId][_srcAddress][_nonce];
        this.nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, hash);
    }

    function estimateBridgeFee(BridgeParams calldata p) external view returns (uint256 nativeFee, uint256 totalFee) {
        uint16 targetLzId = chainTypeToLayerZeroId[p.targetChainType];
        if (targetLzId == 0) revert CCB__InvalidDestinationChain();

        bytes32 reqId = _generateRequestId(msg.sender, p);
        bytes memory payload = _encodePayload(reqId, msg.sender, p);
        (nativeFee,) = layerZeroEndpoint.estimateFees(targetLzId, address(this), payload, false, p.adapterParams);
        totalFee = nativeFee + minimumBridgeFee;
    }
}
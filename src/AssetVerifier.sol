// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainlinkClient} from "@chainlink/contracts/src/v0.8/operatorforwarder/ChainlinkClient.sol";
import {Chainlink} from "@chainlink/contracts/src/v0.8/operatorforwarder/Chainlink.sol";

interface IChainlinkConsumer {
    function requestAssetVerification(
        bytes32 requestId,
        address user,
        string calldata assetType,
        string calldata assetId,
        bytes calldata proof
    ) external;
}

// Errors
error AssetVerifier__OnlyChainlinkConsumer();
error AssetVerifier__RequestNotPending();
error AssetVerifier__OnlyOwner();
error AssetVerifier__InvalidAssetType();
error AssetVerifier__InvalidAssetId();
error AssetVerifier__InvalidProof();
error AssetVerifier__AssetAlreadyVerified();

contract AssetVerifier is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    address public owner;
    address public chainlinkConsumer; // ChainlinkConsumer contract for verification
    mapping(string => mapping(string => address)) public verifiedAssets; // assetType => assetId => owner
    mapping(bytes32 => VerificationRequest) public pendingVerifications; // requestId => verification details

    struct VerificationRequest {
        address user;
        string assetType; // e.g., "social_media", "domain", "app", "website"
        string assetId; // e.g., "123" (social media), "example.com" (domain), "com.app.id" (app)
        bool isPending;
    }

    event AssetVerificationRequested(bytes32 indexed requestId, address indexed user, string assetType, string assetId);
    event AssetVerified(address indexed user, string assetType, string assetId);
    event VerificationFailed(address indexed user, string assetType, string assetId);

    constructor(address _chainlinkConsumer, address _link) {
        owner = msg.sender;
        chainlinkConsumer = _chainlinkConsumer;
        _setChainlinkToken(_link);
    }

    function submitVerification(string calldata assetType, string calldata assetId, bytes calldata proof) external {
        // Validate inputs
        if (bytes(assetType).length == 0) revert AssetVerifier__InvalidAssetType();
        if (bytes(assetId).length == 0) revert AssetVerifier__InvalidAssetId();
        if (proof.length == 0) revert AssetVerifier__InvalidProof();
        if (verifiedAssets[assetType][assetId] != address(0)) revert AssetVerifier__AssetAlreadyVerified();

        bytes32 requestId = bytes32(keccak256(abi.encodePacked(msg.sender, block.timestamp, assetType, assetId)));

        pendingVerifications[requestId] = VerificationRequest({
            user: msg.sender,
            assetType: assetType,
            assetId: assetId,
            isPending: true
        });

        IChainlinkConsumer(chainlinkConsumer).requestAssetVerification(requestId, msg.sender, assetType, assetId, proof);

        emit AssetVerificationRequested(requestId, msg.sender, assetType, assetId);
    }

    function fulfillVerification(bytes32 requestId, bool isVerified) external {
        if (msg.sender != chainlinkConsumer) revert AssetVerifier__OnlyChainlinkConsumer();
        VerificationRequest storage request = pendingVerifications[requestId];
        if (!request.isPending) revert AssetVerifier__RequestNotPending();

        if (isVerified) {
            verifiedAssets[request.assetType][request.assetId] = request.user;
            emit AssetVerified(request.user, request.assetType, request.assetId);
        } else {
            emit VerificationFailed(request.user, request.assetType, request.assetId);
        }

        request.isPending = false;
        delete pendingVerifications[requestId];
    }

    function verifyAsset(address user, string calldata assetType, string calldata assetId) external view returns (bool) {
        return verifiedAssets[assetType][assetId] == user;
    }

    function setChainlinkConsumer(address _chainlinkConsumer) external {
        if (msg.sender != owner) revert AssetVerifier__OnlyOwner();
        chainlinkConsumer = _chainlinkConsumer;
    }
}
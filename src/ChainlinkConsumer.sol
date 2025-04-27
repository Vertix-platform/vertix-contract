// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ChainlinkClient} from "@chainlink/contracts/src/v0.8/operatorforwarder/ChainlinkClient.sol";
import {Chainlink} from "@chainlink/contracts/src/v0.8/operatorforwarder/Chainlink.sol";

contract ChainlinkConsumer is ChainlinkClient {
    error ChainlinkConsumer__OnlyOwner();

    using Chainlink for Chainlink.Request;

    address private oracle;
    bytes32 private jobId;
    uint256 private fee;
    bool public isMock;
    mapping(bytes32 => uint256) public values; // Request ID => Value
    mapping(bytes32 => bool) public verifications; // Request ID => Verification result

    event ValueRequested(bytes32 indexed requestId, string assetType, string assetId);
    event ValueFulfilled(bytes32 indexed requestId, uint256 value);
    event VerificationRequested(bytes32 indexed requestId, address indexed user, string assetType, string assetId);
    event VerificationFulfilled(bytes32 indexed requestId, bool isVerified);

    constructor(address _oracle, bytes32 _jobId, uint256 _fee, address _link, bool _isMock) {
        if (!_isMock) {
            _setChainlinkToken(_link);
        }
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;
        isMock = _isMock;
    }

    function requestSocialMediaValue(string calldata /** platform **/, string calldata accountId) external returns (bytes32) {
        // Legacy function for backward compatibility
        return requestAssetValue("social_media", accountId);
    }

    function requestAssetValue(string memory assetType, string calldata assetId) public returns (bytes32) {
        bytes32 requestId;

        if (isMock) {
            requestId = bytes32(keccak256(abi.encodePacked(msg.sender, block.timestamp, assetType, assetId)));
            (bool success, ) = oracle.call(
                abi.encodeWithSignature(
                    "requestData(address,bytes,bytes32)",
                    address(this),
                    abi.encode(assetType, assetId),
                    requestId
                )
            );
            require(success, "Mock request failed");
        } else {
            Chainlink.Request memory request = _buildChainlinkRequest(jobId, address(this), this.fulfill.selector);
            string memory url = string(abi.encodePacked(
                "https://api.vertix.io/value?assetType=", assetType, "&assetId=", assetId
            )); // link is just a placeholder for now
            request._add("get", url);
            request._add("path", "value");
            requestId = _sendChainlinkRequestTo(oracle, request, fee);
        }

        emit ValueRequested(requestId, assetType, assetId);
        return requestId;
    }

    function requestAssetVerification(
        bytes32 requestId,
        address user,
        string calldata assetType,
        string calldata assetId,
        bytes calldata proof
    ) external {
        if (isMock) {
            (bool success, ) = oracle.call(
                abi.encodeWithSignature(
                    "requestData(address,bytes,bytes32)",
                    address(this),
                    abi.encode(user, assetType, assetId, proof),
                    requestId
                )
            );
            require(success, "Mock request failed");
        } else {
            Chainlink.Request memory request = _buildChainlinkRequest(jobId, address(this), this.fulfillVerification.selector);
            string memory url = string(abi.encodePacked(
                "https://api.vertix.io/verify?assetType=", assetType, "&assetId=", assetId
            ));
            request._add("get", url);
            request._add("path", "isVerified");
            request._addBytes("proof", proof);
            _sendChainlinkRequestTo(oracle, request, fee);
        }

        emit VerificationRequested(requestId, user, assetType, assetId);
    }

    function fulfill(bytes32 requestId, uint256 value) public recordChainlinkFulfillment(requestId) {
        values[requestId] = value;
        emit ValueFulfilled(requestId, value);
    }

    function fulfillVerification(bytes32 requestId, bool isVerified) public recordChainlinkFulfillment(requestId) {
        verifications[requestId] = isVerified;
        emit VerificationFulfilled(requestId, isVerified);
    }

        // Allow updating mock mode (for transitioning to real oracle)
    function setMockMode(bool _isMock, address _link) external {
        if (msg.sender != address(this)) revert ChainlinkConsumer__OnlyOwner();
        isMock = _isMock;
        if (!_isMock) {
            _setChainlinkToken(_link);
        }
    }

    function getValue(bytes32 requestId) external view returns (uint256) {
        return values[requestId];
    }

    function getVerification(bytes32 requestId) external view returns (bool) {
        return verifications[requestId];
    }
}
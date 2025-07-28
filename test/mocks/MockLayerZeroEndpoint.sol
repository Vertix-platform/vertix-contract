// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MockLayerZeroEndpoint {
    mapping(uint16 => uint256) public mockFees;

    // Mock fee estimation
    function estimateFees(
        uint16 _dstChainId,
        address /*_userApplication*/,
        bytes calldata /*_payload*/,
        bool /*_payInLZToken*/,
        bytes calldata /*_adapterParams*/
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        nativeFee = mockFees[_dstChainId];
        zroFee = 0;
    }

    // Mock send function
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable {
        // Mock successful send
    }

    // Mock setConfig
    function setConfig(uint16 _version, uint16 _chainId, uint256 _configType, bytes calldata _config) external {
        // Mock setConfig
    }

    // Mock setSendVersion
    function setSendVersion(uint16 _version) external {
        // Mock setSendVersion
    }

    // Mock setReceiveVersion
    function setReceiveVersion(uint16 _version) external {
        // Mock setReceiveVersion
    }

    // Mock forceResumeReceive
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external {
        // Mock forceResumeReceive
    }

    // Helper functions for testing
    function setMockFee(uint16 _chainId, uint256 _fee) external {
        mockFees[_chainId] = _fee;
    }
}
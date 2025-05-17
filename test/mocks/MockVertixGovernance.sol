// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MockVertixGovernance {
    struct FeeConfig {
        uint16 feeBps;
        address feeRecipient;
    }

    FeeConfig private _feeConfig;
    uint16 public constant DEFAULT_FEE_BPS = 100; // 1% default fee

    constructor(address _feeRecipient, address _marketplace, address _escrow) {
        if (_marketplace == address(0) || _escrow == address(0) || _feeRecipient == address(0)) {
            revert("ZeroAddress");
        }
        _feeConfig = FeeConfig(DEFAULT_FEE_BPS, _feeRecipient);
    }

    function getFeeConfig() external view returns (uint16 feeBps, address recipient) {
        return (_feeConfig.feeBps, _feeConfig.feeRecipient);
    }

    // Mock other functions if needed
    function setPlatformFee(uint16 newFee) external {
        _feeConfig.feeBps = newFee;
    }

    function setFeeRecipient(address newRecipient) external {
        _feeConfig.feeRecipient = newRecipient;
    }
}

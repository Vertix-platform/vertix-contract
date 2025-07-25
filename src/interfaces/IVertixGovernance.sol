// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IVertixGovernance
 * @dev Interface for the VertixGovernance contract
 */
interface IVertixGovernance {
    // Structs
    struct FeeConfig {
        uint16 feeBps; // Platform fee in basis points (1% = 100)
        address feeRecipient; // Address receiving fees
    }

    struct ContractAddresses {
        address marketplace;
        address escrow;
    }

    // Events
    event PlatformFeeUpdated(uint16 oldFee, uint16 newFee);
    event FeeRecipientUpdated(address newRecipient);
    event MarketplaceUpdated(address newMarketplace);
    event EscrowUpdated(address newEscrow);

    // External functions
    function initialize(address _marketplace, address _escrow, address _feeRecipient, address _verificationServer) external;

    function setPlatformFee(uint16 newFee) external;

    function setFeeRecipient(address newRecipient) external;

    function setMarketplace(address newMarketplace) external;

    function setEscrow(address newEscrow) external;

    function setVerificationServer(address newServer) external;

    function addSupportedNftContract(address nftContract) external;

    function removeSupportedNftContract(address nftContract) external;

    // View functions
    function getFeeConfig() external view returns (uint16 feeBps, address recipient);

    function getContractAddresses() external view returns (address marketplace, address escrow);

    function getVerificationServer() external view returns (address);

    function isSupportedNftContract(address nftContract) external view returns (bool);
}

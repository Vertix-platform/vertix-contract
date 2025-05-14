// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Imports
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title VertixGovernance
 * @dev Manages platform parameters with gas-optimized operations
 */
contract VertixGovernance is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Type declarations
    struct FeeConfig {
        uint16 feeBps; // Platform fee in basis points (1% = 100)
        address feeRecipient; // Address receiving fees
    }

    struct ContractAddresses {
        address marketplace;
        address escrow;
    }

    // Constants
    uint16 public constant MAX_FEE_BPS = 1000; // 10% maximum fee
    uint16 public constant DEFAULT_FEE_BPS = 100; // 1% default fee

    // Errors
    error InvalidFee();
    error ZeroAddress();
    error SameValue();

    // State variables
    FeeConfig private _feeConfig;
    ContractAddresses public contracts;

    // Events
    event PlatformFeeUpdated(uint16 newFee);
    event FeeRecipientUpdated(address newRecipient);
    event MarketplaceUpdated(address newMarketplace);
    event EscrowUpdated(address newEscrow);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initialization
    function initialize(address _marketplace, address _escrow, address _feeRecipient) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        if (_escrow == address(0) || _feeRecipient == address(0)) {
            revert ZeroAddress();
        }

        contracts = ContractAddresses(_marketplace, _escrow);
        _feeConfig = FeeConfig(DEFAULT_FEE_BPS, _feeRecipient);
    }

    // Upgrade authorization
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // External functions

    // Public functions
    /**
     * @dev Update platform fee (max 10%)
     * @param newFee New fee in basis points (100 = 1%)
     */
    function setPlatformFee(uint16 newFee) external onlyOwner {
        if (newFee > MAX_FEE_BPS) revert InvalidFee();
        if (newFee == _feeConfig.feeBps) revert SameValue();

        _feeConfig.feeBps = newFee;
        emit PlatformFeeUpdated(newFee);
    }

    /**
     * @dev Update fee recipient
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        if (newRecipient == _feeConfig.feeRecipient) revert SameValue();

        _feeConfig.feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    /**
     * @dev Update marketplace contract address
     * @param newMarketplace New marketplace address
     */
    function setMarketplace(address newMarketplace) external onlyOwner {
        if (newMarketplace == address(0)) revert ZeroAddress();
        if (newMarketplace == contracts.marketplace) revert SameValue();

        contracts.marketplace = newMarketplace;
        emit MarketplaceUpdated(newMarketplace);
    }

    /**
     * @dev Update escrow contract address
     * @param newEscrow New escrow address
     */
    function setEscrow(address newEscrow) external onlyOwner {
        if (newEscrow == address(0)) revert ZeroAddress();
        if (newEscrow == contracts.escrow) revert SameValue();

        contracts.escrow = newEscrow;
        emit EscrowUpdated(newEscrow);
    }

    // View functions
    /**
     * @dev Get current fee configuration
     * @return feeBps Current fee in basis points
     * @return recipient Current fee recipient
     */
    function getFeeConfig() external view returns (uint16 feeBps, address recipient) {
        return (_feeConfig.feeBps, _feeConfig.feeRecipient);
    }

    /**
     * @dev Get current contract addresses
     * @return marketplace Marketplace contract address
     * @return escrow Escrow contract address
     */
    function getContractAddresses() external view returns (address marketplace, address escrow) {
        return (contracts.marketplace, contracts.escrow);
    }
}

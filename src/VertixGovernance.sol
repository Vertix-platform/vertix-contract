// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title VertixGovernance
 * @dev governance contract for managing platform parameters
 */
contract VertixGovernance is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Type declarations
    struct ContractAddresses {
        address marketplace;
        address escrow;
    }

    // Errors
    error VertixGovernance__PlatformFeeTooHigh();
    error VertixGovernance__ZeroAddress();
    error VertixGovernance__SameValue();

    // Constants
    uint16 public constant MAX_PLATFORM_FEE = 1000; // 10% in basis points
    uint16 public constant DEFAULT_PLATFORM_FEE = 100; // 1%

    // State variables
    ContractAddresses public contracts;
    uint16 public platformFee; // Fee in basis points (1% = 100)

    // Events
    event PlatformFeeUpdated(uint16 newFee);
    event MarketplaceContractUpdated(address newMarketplace);
    event EscrowContractUpdated(address newEscrow);
    event ContractsUpdated(address indexed marketplace, address indexed escrow);

    // Constructor
    function initialize(address _marketplaceContract, address _escrowContract) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        if (_marketplaceContract == address(0)) revert VertixGovernance__ZeroAddress();
        if (_escrowContract == address(0)) revert VertixGovernance__ZeroAddress();

        contracts = ContractAddresses(_marketplaceContract, _escrowContract);
        platformFee = DEFAULT_PLATFORM_FEE;
    }

    // UUPS upgradeability
    function _authorizeUpgrade(address) internal override onlyOwner {}


    // Public functions
    /**
     * @dev Update platform fee (max 10%)
     * @param newFee Fee in basis points (100 = 1%)
     */
    function setPlatformFee(uint16 newFee) external onlyOwner {
        if (newFee > MAX_PLATFORM_FEE) revert VertixGovernance__PlatformFeeTooHigh();
        if (newFee == platformFee) revert VertixGovernance__SameValue();

        platformFee = newFee;
        emit PlatformFeeUpdated(newFee);
    }

    /**
     * @dev Update marketplace contract address
     * @param newMarketplace New marketplace contract address
     */
    function setMarketplaceContract(address newMarketplace) external onlyOwner {
        if (newMarketplace == address(0)) revert VertixGovernance__ZeroAddress();
        if (newMarketplace == contracts.marketplace) revert VertixGovernance__SameValue();

        contracts.marketplace = newMarketplace;
        emit MarketplaceContractUpdated(newMarketplace);
    }

    /**
     * @dev Update escrow contract address
     * @param newEscrow New escrow contract address
     */
    function setEscrowContract(address newEscrow) external onlyOwner {
        if (newEscrow == address(0)) revert VertixGovernance__ZeroAddress();
        if (newEscrow == contracts.escrow) revert VertixGovernance__SameValue();

        contracts.escrow = newEscrow;
        emit EscrowContractUpdated(newEscrow);
    }

    /**
     * @dev Batch update both contracts
     * @param newMarketplace New marketplace contract address
     * @param newEscrow New escrow contract address
     */
    function setContracts(address newMarketplace, address newEscrow) external onlyOwner {
        if (newMarketplace == address(0) || newEscrow == address(0)) revert VertixGovernance__ZeroAddress();
        if (newMarketplace == contracts.marketplace && newEscrow == contracts.escrow) revert VertixGovernance__SameValue();

        contracts = ContractAddresses(newMarketplace, newEscrow);
        emit ContractsUpdated(newMarketplace, newEscrow);
    }

    // View functions
    /**
     * @dev Get current contract addresses
     * @return Tuple of (marketplace, escrow) addresses
     */
    function getContracts() external view returns (address, address) {
        return (contracts.marketplace, contracts.escrow);
    }
}
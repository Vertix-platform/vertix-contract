// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Imports
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title VertixGovernance
 * @dev Manages platform parameters with gas-optimized operations
 */
contract VertixGovernance is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Errors
    error VertixGovernance__InvalidFee();
    error VertixGovernance__ZeroAddress();
    error VertixGovernance__SameValue();
    error VertixGovernance__InvalidNFTContract();

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

    // State variables
    FeeConfig private _feeConfig;
    ContractAddresses public contracts;
    address public verificationServer;
    mapping(address => bool) public supportedNftContracts;


    // Events
    event PlatformFeeUpdated(uint16 oldFee, uint16 newFee);
    event FeeRecipientUpdated(address newRecipient);
    event MarketplaceUpdated(address newMarketplace);
    event EscrowUpdated(address newEscrow);
    event VerificationServerUpdated(address newServer);
    event SupportedNFTContractAdded(address indexed nftContract);
    event SupportedNFTContractRemoved(address indexed nftContract);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Initialization
    function initialize(address _marketplace, address _escrow, address _feeRecipient,address _verificationServer) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        if (_escrow == address(0) || _feeRecipient == address(0) || _verificationServer == address(0)) {
            revert VertixGovernance__ZeroAddress();
        }

        contracts = ContractAddresses(_marketplace, _escrow);
        _feeConfig = FeeConfig(DEFAULT_FEE_BPS, _feeRecipient);
        verificationServer = _verificationServer;
    }

    // Upgrade authorization
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // External functions
    /**
     * @dev Update platform fee (max 10%)
     * @param newFee New fee in basis points (100 = 1%)
     */
    function setPlatformFee(uint16 newFee) external onlyOwner {
        if (newFee > MAX_FEE_BPS) revert VertixGovernance__InvalidFee();
        if (newFee == _feeConfig.feeBps) revert VertixGovernance__SameValue();
        uint16 oldFee = _feeConfig.feeBps;

        _feeConfig.feeBps = newFee;
        emit PlatformFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Update fee recipient
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert VertixGovernance__ZeroAddress();
        if (newRecipient == _feeConfig.feeRecipient) revert VertixGovernance__SameValue();

        _feeConfig.feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    /**
     * @dev Update marketplace contract address
     * @param newMarketplace New marketplace address
     */
    function setMarketplace(address newMarketplace) external onlyOwner {
        if (newMarketplace == address(0)) revert VertixGovernance__ZeroAddress();
        if (newMarketplace == contracts.marketplace) revert VertixGovernance__SameValue();

        contracts.marketplace = newMarketplace;
        emit MarketplaceUpdated(newMarketplace);
    }

    /**
     * @dev Update escrow contract address
     * @param newEscrow New escrow address
     */
    function setEscrow(address newEscrow) external onlyOwner {
        if (newEscrow == address(0)) revert VertixGovernance__ZeroAddress();
        if (newEscrow == contracts.escrow) revert VertixGovernance__SameValue();

        contracts.escrow = newEscrow;
        emit EscrowUpdated(newEscrow);
    }

    /**
     * @dev Set verification server
     * @param newServer New server address
     */

    function setVerificationServer(address newServer) external onlyOwner {
        if (newServer == address(0)) revert VertixGovernance__ZeroAddress();
        if (newServer == verificationServer) revert VertixGovernance__SameValue();
        verificationServer = newServer;
        emit VerificationServerUpdated(newServer);
    }

    /**
     * @dev Add supported NFT contract (external contracts)
     * @param nftContract Address of the NFT contract
     */

    function addSupportedNftContract(address nftContract) external onlyOwner {
        if (nftContract == address(0)) revert VertixGovernance__ZeroAddress();
        supportedNftContracts[nftContract] = true;
        emit SupportedNFTContractAdded(nftContract);
    }

    /**
     * @dev Remove supported NFT contract
     * @param nftContract Address of the NFT contract
     */
    function removeSupportedNftContract(address nftContract) external onlyOwner {
        if (!supportedNftContracts[nftContract]) revert VertixGovernance__InvalidNFTContract();
        supportedNftContracts[nftContract] = false;
        emit SupportedNFTContractRemoved(nftContract);
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

    /**
     * @dev Get current server address
     * @return Server address
     */
    function getVerificationServer() external view returns (address) {
        return verificationServer;
    }

    /**
     * @dev Check if an NFT contract is supported
     * @param nftContract Address of the NFT contract
     * @return True if supported, false otherwise
     */
    function isSupportedNftContract(address nftContract) external view returns (bool) {
        return supportedNftContracts[nftContract];
    }

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Imports
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract VertixEscrow is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // Errors
    error VertixEscrow__InvalidPrice();
    error VertixEscrow__EscrowNotActive();
    error VertixEscrow__Unauthorized();
    error VertixEscrow__TransferFailed();
    error VertixEscrow__FundsNotDeposited();
    error VertixEscrow__AlreadyDeposited();
    error VertixEscrow__EscrowExpired();
    error VertixEscrow__DisputeNotResolved();

    // Type Declarations
    struct Escrow {
        address seller;
        address buyer;
        uint256 price;
        bytes32 assetHash; // Hash of asset details (e.g., social media account, website)
        uint256 depositAmount; // Amount deposited by buyer
        uint256 deadline; // Escrow expiration timestamp
        bool isActive;
        bool isCompleted;
        bool isDisputed;
    }
    // State Variables
    uint256 private _escrowId;
    IERC20 public paymentToken; // Stablecoin or native token for payments
    uint256 public platformFee; // Fee percentage (e.g., 2.5% = 250)
    address public feeRecipient; // Address to receive platform fees
    uint256 public disputeResolutionPeriod; // Time to resolve disputes (e.g., 7 days)

    mapping(uint256 => Escrow) public escrows; // Escrow ID => Escrow details
    mapping(uint256 => address) public disputeResolver; // Escrow ID => Resolver (admin or arbitrator)

    // Events
    event EscrowCreated(uint256 indexed escrowId, address indexed seller, address indexed buyer, uint256 price, bytes32 assetHash);
    event EscrowDeposited(uint256 indexed escrowId, address indexed buyer, uint256 amount);
    event EscrowCompleted(uint256 indexed escrowId, address indexed seller, address indexed buyer);
    event EscrowDisputed(uint256 indexed escrowId, address indexed seller, address indexed buyer);
    event EscrowResolved(uint256 indexed escrowId, address indexed resolver, bool sellerWins);
    event EscrowCancelled(uint256 indexed escrowId, address indexed seller, address indexed buyer);

    // Modifiers
    modifier onlyEscrowParticipant(uint256 escrowId) {
        if (escrows[escrowId].seller != msg.sender && escrows[escrowId].buyer != msg.sender) revert VertixEscrow__Unauthorized();
        _;
    }

    modifier onlyDisputeResolver(uint256 escrowId) {
        if (disputeResolver[escrowId] != msg.sender) revert VertixEscrow__Unauthorized();
        _;
    }

    // Functions
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _paymentToken,
        uint256 _platformFee,
        address _feeRecipient,
        uint256 _disputeResolutionPeriod
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        paymentToken = IERC20(_paymentToken);
        platformFee = _platformFee;
        feeRecipient = _feeRecipient;
        disputeResolutionPeriod = _disputeResolutionPeriod; // e.g., 7 days in seconds
        _escrowId = 0;
    }

    // External Functions
    function createEscrow(
        address buyer,
        uint256 price,
        bytes32 assetHash,
        uint256 duration
    ) external nonReentrant returns (uint256) {
        if (price == 0) revert VertixEscrow__InvalidPrice();
        if (buyer == address(0)) revert VertixEscrow__Unauthorized();

        uint256 escrowId = _escrowId++;
        uint256 deadline = block.timestamp + duration; // e.g., 30 days

        escrows[escrowId] = Escrow({
            seller: msg.sender,
            buyer: buyer,
            price: price,
            assetHash: assetHash,
            depositAmount: 0,
            deadline: deadline,
            isActive: true,
            isCompleted: false,
            isDisputed: false
        });

        emit EscrowCreated(escrowId, msg.sender, buyer, price, assetHash);
        return escrowId;
    }

    function depositFunds(uint256 escrowId) external nonReentrant {
        Escrow memory escrow = escrows[escrowId];
        if (!escrow.isActive) revert VertixEscrow__EscrowNotActive();
        if (msg.sender != escrow.buyer) revert VertixEscrow__Unauthorized();
        if (escrow.depositAmount > 0) revert VertixEscrow__AlreadyDeposited();
        if (block.timestamp > escrow.deadline) revert VertixEscrow__EscrowExpired();

        // Transfer funds to contract
        if (!paymentToken.transferFrom(msg.sender, address(this), escrow.price)) revert VertixEscrow__TransferFailed();
        escrow.depositAmount = escrow.price;

        emit EscrowDeposited(escrowId, msg.sender, escrow.price);
    }

    function completeEscrow(uint256 escrowId) external nonReentrant onlyEscrowParticipant(escrowId) {
        Escrow memory escrow = escrows[escrowId];
        if (!escrow.isActive) revert VertixEscrow__EscrowNotActive();
        if (escrow.isDisputed) revert VertixEscrow__DisputeNotResolved();
        if (escrow.depositAmount != escrow.price) revert VertixEscrow__FundsNotDeposited();
        if (block.timestamp > escrow.deadline) revert VertixEscrow__EscrowExpired();

        uint256 fee = (escrow.price * platformFee) / 10000;
        uint256 sellerProceeds = escrow.price - fee;

        // Transfer fee to feeRecipient and proceeds to seller
        if (!paymentToken.transfer(feeRecipient, fee)) revert VertixEscrow__TransferFailed();
        if (!paymentToken.transfer(escrow.seller, sellerProceeds)) revert VertixEscrow__TransferFailed();

        escrow.isActive = false;
        escrow.isCompleted = true;

        emit EscrowCompleted(escrowId, escrow.seller, escrow.buyer);
    }

    function disputeEscrow(uint256 escrowId) external nonReentrant onlyEscrowParticipant(escrowId) {
        Escrow memory escrow = escrows[escrowId];
        if (!escrow.isActive) revert VertixEscrow__EscrowNotActive();
        if (escrow.depositAmount != escrow.price) revert VertixEscrow__FundsNotDeposited();
        if (block.timestamp > escrow.deadline) revert VertixEscrow__EscrowExpired();

        escrow.isDisputed = true;
        disputeResolver[escrowId] = owner(); // Admin as default resolver

        emit EscrowDisputed(escrowId, escrow.seller, escrow.buyer);
    }

    function resolveDispute(uint256 escrowId, bool sellerWins) external nonReentrant onlyDisputeResolver(escrowId) {
        Escrow memory escrow = escrows[escrowId];
        if (!escrow.isActive || !escrow.isDisputed) revert VertixEscrow__EscrowNotActive();

        address recipient = sellerWins ? escrow.seller : escrow.buyer;
        uint256 fee = sellerWins ? (escrow.price * platformFee) / 10000 : 0;
        uint256 proceeds = escrow.price - fee;

        // Transfer funds
        if (fee > 0) {
            if (!paymentToken.transfer(feeRecipient, fee)) revert VertixEscrow__TransferFailed();
        }
        if (!paymentToken.transfer(recipient, proceeds)) revert VertixEscrow__TransferFailed();

        escrow.isActive = false;
        escrow.isCompleted = true;

        emit EscrowResolved(escrowId, msg.sender, sellerWins);
    }

    function cancelEscrow(uint256 escrowId) external nonReentrant onlyEscrowParticipant(escrowId) {
        Escrow memory escrow = escrows[escrowId];
        if (!escrow.isActive) revert VertixEscrow__EscrowNotActive();
        if (escrow.isDisputed) revert VertixEscrow__DisputeNotResolved();
        if (escrow.depositAmount > 0 && block.timestamp <= escrow.deadline) {
            revert VertixEscrow__Unauthorized(); // Cannot cancel if funds deposited and not expired
        }

        if (escrow.depositAmount > 0) {
            // Refund buyer if funds were deposited
            if (!paymentToken.transfer(escrow.buyer, escrow.depositAmount)) revert VertixEscrow__TransferFailed();
        }

        escrow.isActive = false;
        emit EscrowCancelled(escrowId, escrow.seller, escrow.buyer);
    }

    // Internal Functions
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // View & Pure Functions
    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }

    // Admin Functions
    function setDisputeResolver(uint256 escrowId, address resolver) external onlyOwner {
        disputeResolver[escrowId] = resolver;
    }

    function setDisputeResolutionPeriod(uint256 period) external onlyOwner {
        disputeResolutionPeriod = period;
    }
}
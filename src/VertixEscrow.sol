// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title VertixEscrow
 * @dev escrow contract for non-NFT asset sales
 */
contract VertixEscrow is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable
{
    // Errors
    error VertixEscrow__IncorrectAmountSent();
    error VertixEscrow__EscrowAlreadyExists();
    error VertixEscrow__NotEscrowParticipant();
    error VertixEscrow__OnlyBuyerCanConfirm();
    error VertixEscrow__EscrowAlreadyCompleted();
    error VertixEscrow__EscrowInDispute();
    error VertixEscrow__DisputeAlreadyRaised();
    error VertixEscrow__NoActiveDispute();
    error VertixEscrow__InvalidWinner();
    error VertixEscrow__DeadlineNotPassed();
    error VertixEscrow__ZeroAddress();
    error VertixEscrow__InvalidDuration();

    struct Escrow {
        address seller;
        address buyer;
        uint96 amount;
        uint32 deadline;
        bool completed;
        bool disputed;
    }

    // State variables
    mapping(uint256 => Escrow) public escrows;
    uint32 public escrowDuration;

    // Events
    event FundsLocked(uint256 indexed listingId, address indexed seller, address indexed buyer, uint96 amount, uint32 deadline);
    event FundsReleased(uint256 indexed listingId, address indexed recipient, uint256 amount);
    event DisputeRaised(uint256 indexed listingId);
    event DisputeResolved(uint256 indexed listingId, address indexed winner);

    // Modifiers
    modifier onlyEscrowParticipant(uint256 listingId) {
        Escrow storage e = escrows[listingId];
        if (msg.sender != e.seller && msg.sender != e.buyer) {
            revert VertixEscrow__NotEscrowParticipant();
        }
        _;
    }

    // Constructor
    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __Pausable_init();
        escrowDuration = 7 days;
    }

    // UUPS upgradeability
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Public functions
    /**
     * @dev Lock funds in escrow
     * @param listingId The ID of the listing
     * @param seller The address of the seller
     * @param buyer The address of the buyer
     */
    function lockFunds(uint256 listingId, address seller, address buyer) external payable nonReentrant whenNotPaused {
        if (msg.value == 0 || msg.value > type(uint96).max) revert VertixEscrow__IncorrectAmountSent();
        if (escrows[listingId].seller != address(0)) revert VertixEscrow__EscrowAlreadyExists();
        if (seller == address(0) || buyer == address(0)) revert VertixEscrow__ZeroAddress();

        escrows[listingId] = Escrow({
            seller: seller,
            buyer: buyer,
            amount: uint96(msg.value),
            deadline: uint32(block.timestamp + escrowDuration),
            completed: false,
            disputed: false
        });

        emit FundsLocked(listingId, seller, buyer, uint96(msg.value), escrows[listingId].deadline);
    }

    /**
     * @dev Buyer confirms asset transfer
     * @param listingId The ID of the listing
     */
    function confirmTransfer(uint256 listingId) external nonReentrant whenNotPaused onlyEscrowParticipant(listingId) {
        Escrow storage escrow = escrows[listingId];

        if (msg.sender != escrow.buyer) revert VertixEscrow__OnlyBuyerCanConfirm();
        if (escrow.completed) revert VertixEscrow__EscrowAlreadyCompleted();
        if (escrow.disputed) revert VertixEscrow__EscrowInDispute();

        escrow.completed = true;
        uint256 amount = escrow.amount;
        address seller = escrow.seller;

        emit FundsReleased(listingId, seller, amount);
        delete escrows[listingId];

        (bool success,) = seller.call{value: amount}("");
        require(success, "Transfer failed");

    }

    /**
     * @dev Raise a dispute
     * @param listingId The ID of the listing
     */
    function raiseDispute(uint256 listingId) external whenNotPaused onlyEscrowParticipant(listingId) {
        Escrow storage escrow = escrows[listingId];
        if (escrow.completed) revert VertixEscrow__EscrowAlreadyCompleted();
        if (escrow.disputed) revert VertixEscrow__DisputeAlreadyRaised();

        escrow.disputed = true;
        emit DisputeRaised(listingId);
    }

    /**
     * @dev Admin resolves dispute
     * @param listingId The ID of the listing
     * @param winner The address of the dispute winner
     */
    function resolveDispute(uint256 listingId, address winner) external onlyOwner nonReentrant whenNotPaused {
        Escrow storage escrow = escrows[listingId];
        if (escrow.seller == address(0) || escrow.buyer == address(0)) revert VertixEscrow__ZeroAddress();
        if (!escrow.disputed) revert VertixEscrow__NoActiveDispute();
        if (escrow.completed) revert VertixEscrow__EscrowAlreadyCompleted();
        if (winner != escrow.seller && winner != escrow.buyer) revert VertixEscrow__InvalidWinner();

        escrow.completed = true;
        uint256 amount = escrow.amount;
        emit FundsReleased(listingId, winner, amount);
        emit DisputeResolved(listingId, winner);

        delete escrows[listingId];

        (bool success,) = winner.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Refund if deadline passes
     * @param listingId The ID of the listing
     */
    function refund(uint256 listingId) external nonReentrant whenNotPaused {
        Escrow storage escrow = escrows[listingId];
        if(escrow.seller == address(0) || escrow.buyer == address(0)) revert VertixEscrow__ZeroAddress();
        if (block.timestamp <= escrow.deadline) revert VertixEscrow__DeadlineNotPassed();
        if (escrow.completed) revert VertixEscrow__EscrowAlreadyCompleted();
        if (escrow.disputed) revert VertixEscrow__EscrowInDispute();

        escrow.completed = true;
        uint256 amount = escrow.amount;
        address buyer = escrow.buyer;
        emit FundsReleased(listingId, buyer, amount);

        delete escrows[listingId];

        (bool success,) = buyer.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function refund(uint256 listingId) external nonReentrant whenNotPaused {
        Escrow storage escrow = escrows[listingId];
        if (block.timestamp <= escrow.deadline) revert VertixEscrow__DeadlineNotPassed();
        if (escrow.completed) revert VertixEscrow__EscrowAlreadyCompleted();
        if (escrow.disputed) revert VertixEscrow__EscrowInDispute();

        escrow.completed = true;
        uint256 amount = escrow.amount;
        emit FundsReleased(listingId, escrow.buyer, amount);

        delete escrows[listingId];

        (bool success,) = escrow.buyer.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function setEscrowDuration(uint32 newDuration) external onlyOwner {
        if(newDuration == 0) revert VertixEscrow__InvalidDuration();
        escrowDuration = newDuration;
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Get escrow details
     * @param listingId The ID of the listing
     */
    function getEscrow(uint256 listingId) external view returns (Escrow memory) {
        return escrows[listingId];
    }
}
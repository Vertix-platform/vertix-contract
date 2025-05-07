// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title VertixEscrow
 * @dev escrow contract for non-NFT asset sales
 */
contract VertixEscrow is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
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
    event FundsLocked(uint256 indexed listingId, address indexed seller, address indexed buyer, uint256 amount);
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
        escrowDuration = 7 days;
    }

    // UUPS upgradeability
    function _authorizeUpgrade(address) internal override onlyOwner {}


    // Public functions
    /**
     * @dev Lock funds in escrow
     * @param listingId The ID of the listing
     * @param seller The address of the seller
     * @param buyer The address of the buyer
     */
    function lockFunds(
        uint256 listingId,
        address seller,
        address buyer
    ) external payable nonReentrant {
        if (msg.value == 0 || msg.value > type(uint96).max) revert VertixEscrow__IncorrectAmountSent();
        if (escrows[listingId].seller != address(0)) revert VertixEscrow__EscrowAlreadyExists();

        escrows[listingId] = Escrow({
            seller: seller,
            buyer: buyer,
            amount: uint96(msg.value),
            deadline: uint32(block.timestamp + escrowDuration),
            completed: false,
            disputed: false
        });

        emit FundsLocked(listingId, seller, buyer, msg.value);
    }

    /**
     * @dev Buyer confirms asset transfer
     * @param listingId The ID of the listing
     */
    function confirmTransfer(uint256 listingId) external nonReentrant onlyEscrowParticipant(listingId) {
        Escrow memory escrow = escrows[listingId];

        if (msg.sender != escrow.buyer) revert VertixEscrow__OnlyBuyerCanConfirm();
        if (escrow.completed) revert VertixEscrow__EscrowAlreadyCompleted();
        if (escrow.disputed) revert VertixEscrow__EscrowInDispute();

        escrow.completed = true;
        uint256 amount = escrow.amount;
        delete escrows[listingId];

        (bool success, ) = escrow.seller.call{value: amount}("");
        require(success, "Transfer failed");

        emit FundsReleased(listingId, escrow.seller, amount);
    }

    /**
     * @dev Raise a dispute
     * @param listingId The ID of the listing
     */
    function raiseDispute(uint256 listingId) external onlyEscrowParticipant(listingId) {
        Escrow memory escrow = escrows[listingId];
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
    function resolveDispute(uint256 listingId, address winner) external onlyOwner nonReentrant {
        Escrow memory escrow = escrows[listingId];
        if (!escrow.disputed) revert VertixEscrow__NoActiveDispute();
        if (escrow.completed) revert VertixEscrow__EscrowAlreadyCompleted();
        if (winner != escrow.seller && winner != escrow.buyer) revert VertixEscrow__InvalidWinner();

        escrow.completed = true;
        uint256 amount = escrow.amount;
        delete escrows[listingId];

        (bool success, ) = winner.call{value: amount}("");
        require(success, "Transfer failed");

        emit FundsReleased(listingId, winner, amount);
        emit DisputeResolved(listingId, winner);
    }

    /**
     * @dev Refund if deadline passes
     * @param listingId The ID of the listing
     */
    function refund(uint256 listingId) external nonReentrant {
        Escrow memory escrow = escrows[listingId];
        if (block.timestamp <= escrow.deadline) revert VertixEscrow__DeadlineNotPassed();
        if (escrow.completed) revert VertixEscrow__EscrowAlreadyCompleted();
        if (escrow.disputed) revert VertixEscrow__EscrowInDispute();

        escrow.completed = true;
        uint256 amount = escrow.amount;
        delete escrows[listingId];

        (bool success, ) = escrow.buyer.call{value: amount}("");
        require(success, "Transfer failed");

        emit FundsReleased(listingId, escrow.buyer, amount);
    }

    // View functions
    /**
     * @dev Get escrow details
     * @param listingId The ID of the listing
     */
    function getEscrow(uint256 listingId) external view returns (Escrow memory) {
        return escrows[listingId];
    }
}
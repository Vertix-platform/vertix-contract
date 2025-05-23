// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IVertixEscrow
 * @dev Interface for the VertixEscrow contract
 */
interface IVertixEscrow {
    // Structs
    struct Escrow {
        address seller;
        address buyer;
        uint96 amount;
        uint32 deadline;
        bool completed;
        bool disputed;
    }

    // Events
    event FundsLocked(
        uint256 indexed listingId, address indexed seller, address indexed buyer, uint96 amount, uint32 deadline
    );
    event FundsReleased(uint256 indexed listingId, address indexed recipient, uint256 amount);
    event DisputeRaised(uint256 indexed listingId);
    event DisputeResolved(uint256 indexed listingId, address indexed winner);

    // External functions
    function lockFunds(uint256 listingId, address seller, address buyer) external payable;

    function confirmTransfer(uint256 listingId) external;

    function raiseDispute(uint256 listingId) external;

    function resolveDispute(uint256 listingId, address winner) external;

    function refund(uint256 listingId) external;

    // View functions
    function getEscrowDetails(uint256 listingId) external view returns (Escrow memory);
}

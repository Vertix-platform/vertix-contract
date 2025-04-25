// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVertixEscrow {
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

    // Events
    event EscrowCreated(uint256 indexed escrowId, address indexed seller, address indexed buyer, uint256 price, bytes32 assetHash);
    event EscrowDeposited(uint256 indexed escrowId, address indexed buyer, uint256 amount);
    event EscrowCompleted(uint256 indexed escrowId, address indexed seller, address indexed buyer);
    event EscrowDisputed(uint256 indexed escrowId, address indexed seller, address indexed buyer);
    event EscrowResolved(uint256 indexed escrowId, address indexed resolver, bool sellerWins);
    event EscrowCancelled(uint256 indexed escrowId, address indexed seller, address indexed buyer);

    function createEscrow(address buyer, uint256 price, bytes32 assetHash, uint256 duration) external returns (uint256);
    function depositFunds(uint256 escrowId) external;
    function completeEscrow(uint256 escrowId) external;
    function disputeEscrow(uint256 escrowId) external;
    function resolveDispute(uint256 escrowId, bool sellerWins) external;
    function cancelEscrow(uint256 escrowId) external;
    function getEscrow(uint256 escrowId) external view returns (
        address seller,
        address buyer,
        uint256 price,
        bytes32 assetHash,
        uint256 depositAmount,
        uint256 deadline,
        bool isActive,
        bool isCompleted,
        bool isDisputed
    );
}
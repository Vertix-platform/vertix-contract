# Vertix Smart Contracts

## Overview

Vertix is a decentralized marketplace where people can trade digital assets. This includes creator-branded NFTs, in-game items, digital accounts, websites, domains, apps, etc. It uses a combination of Polygon and Base technology to ensure secure, clear, and trustworthy transactions. The smart contracts allow for various NFT functions, such as borrowing, staking, and selling. They also provide secure ways to handle manual transfers and ensure that assets are authentic.

## Features

- **NFT Trading**: Mint, trade, borrow, stake, and sell creator-branded NFTs and in-game items.

- **Escrow System**: Secure escrow-like smart contracts for safe manual transfers of digital assets.

- **Verification**: Ensures authenticity of digital assets, including accounts, domains, apps, etc.

- **Hybrid Architecture**: Leverages Polygon for low-cost, high-speed transactions and Base for scalability.

- **Decentralized Marketplace**: Trustless trading for gamers, creators, and digital entrepreneurs.

## Prerequisites

- **Foundry**: Ensure you have ([Foundry](https://github.com/foundry-rs/foundry)) installed.

- **Node.js**: Required for dependency management.

- **Polygon & Base Nodes**: Access to Polygon and Base RPC endpoints for deployment and testing.

## Contributing

Contributions are made to our repos via Issues and Pull Requests (PRs). First search existing Issues and PRs before creating your own.

### Fork and Pull Workflow

In general, we follow the ["fork-and-pull" Git workflow](https://github.com/susam/gitpr)

1. Fork the repository to your own Github account
2. Clone the project to your machine
3. Create a branch locally with a succinct but descriptive name
4. Commit changes to the branch following the [standard convention commit spec](https://www.conventionalcommits.org/en/v1.0.0/#:~:text=fix%3A%20a%20commit%20of%20the,CHANGE%3A%20%2C%20or%20appends%20a%20!)
5. Following any formatting and testing guidelines specific to this repo
6. Push changes to your fork
7. Open a PR in our repository

## Installation

- Install dependencies:

```node
make install
```

## Usage

Compile Contracts

```node
forge build
```

## Run Tests

```node
forge test
```

## Deploy Contracts

Deploy to Polygon or Base:

```node
make deployNftMarketplacePolygon
```

or

```node
make deployNftMarketplaceBase
```

## Interact with Contracts

Use Foundry's cast to interact with deployed contracts. Ensure you have anvil running:

```node
cast call <contract-address> "<function-signature>" --rpc-url $POLYGON_RPC_URL
```

## Contract Structure

- **MarketplaceStorage.sol**:

- **VertixEscrow.sol**: Manages secure escrow for manual asset transfers.

## Testing

Run test per function:

```node
forge test --mt <function name>
```

Run test per contract:

```node
forge test --mc <contract name>
```

## License

This project is licensed under the MIT License. See the LICENSE (./LICENSE) file for details.

## Cross-Chain Marketplace

The Vertix Marketplace now supports automatic cross-chain broadcasting of listings, enabling users to list items on one chain and have them automatically visible on all supported chains.

### Key Features

- **Unified Listing**: List NFTs and non-NFT assets with optional cross-chain broadcasting in a single transaction
- **Automatic Broadcasting**: Listings are automatically broadcasted to all supported chains when enabled
- **Backward Compatibility**: Existing function signatures still work without cross-chain functionality
- **Cost Optimization**: Cross-chain broadcasting is optional and only charges when used

### Supported Chains

Currently supported chains for cross-chain functionality:
- **Mainnet**: Ethereum, Polygon, Base
- **Testnet**: Polygon Mumbai, Base Sepolia, Ethereum Sepolia

### Usage Examples

#### 1. Basic NFT Listing (Local Chain Only)

```solidity
// List NFT on current chain only (backward compatible)
marketplace.listNFT(nftContract, tokenId, price);
```

#### 2. Cross-Chain NFT Listing

```solidity
// Get estimated cross-chain fee
(uint256 crossChainFee,) = marketplace.estimateCrossChainFee();

// List NFT with cross-chain broadcasting
marketplace.listNFT{value: crossChainFee}(
    nftContract, 
    tokenId, 
    price, 
    true  // enableCrossChain
);
```

#### 3. Cross-Chain Non-NFT Asset Listing

```solidity
// Get estimated cross-chain fee
(uint256 crossChainFee,) = marketplace.estimateCrossChainFee();

// List non-NFT asset with cross-chain broadcasting
marketplace.listNonNFTAsset{value: crossChainFee}(
    assetType,
    assetId,
    price,
    metadata,
    verificationProof,
    true  // enableCrossChain
);
```

#### 4. Cross-Chain Social Media NFT Listing

```solidity
// Get estimated cross-chain fee
(uint256 crossChainFee,) = marketplace.estimateCrossChainFee();

// List social media NFT with cross-chain broadcasting
marketplace.listSocialMediaNFT{value: crossChainFee}(
    tokenId,
    price,
    socialMediaId,
    signature,
    true  // enableCrossChain
);
```

### Architecture Changes

The marketplace architecture has been consolidated to eliminate the need for separate cross-chain contracts:

**Before:**
1. User lists item on `MarketplaceCore`
2. User calls `CrossChainMarketplace.broadcastListing()` separately
3. Two separate transactions required

**After:**
1. User lists item on `MarketplaceCore` with `enableCrossChain = true`
2. Cross-chain broadcasting happens automatically in the same transaction
3. Single transaction with automatic broadcasting

### Benefits

1. **Simplified UX**: Users no longer need to make separate calls for cross-chain broadcasting
2. **Gas Optimization**: Single transaction instead of multiple transactions
3. **Automatic Synchronization**: Listings are immediately available on all chains
4. **Error Reduction**: Eliminates the possibility of forgetting to broadcast
5. **Backward Compatibility**: Existing integrations continue to work unchanged

### Technical Implementation

The `MarketplaceCore` contract now inherits from `NonblockingLzApp` and includes:

- LayerZero integration for cross-chain messaging
- Automatic fee estimation for cross-chain operations
- Configurable supported chains
- Internal broadcasting logic integrated into listing functions

### Gas Costs

Cross-chain broadcasting incurs additional gas costs for LayerZero messaging:
- **Local listing only**: Standard gas cost (unchanged)
- **Cross-chain listing**: Standard gas cost + LayerZero fees for each target chain
- **Fee estimation**: Use `estimateCrossChainFee()` to get current costs

### Migration Guide

For existing applications:
1. **No changes required** for basic functionality
2. **Optional upgrade** to use cross-chain features by adding the `enableCrossChain` parameter
3. **Fee handling** required when enabling cross-chain broadcasting

### Error Handling

New error types for cross-chain functionality:
- `MC__InsufficientCrossChainFee()`: When provided fee is insufficient for cross-chain operations
- `CrossChainBroadcastFailed(chainId)`: When broadcasting to a specific chain fails (non-blocking)

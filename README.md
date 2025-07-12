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

- Clone the repository:
```
git clone git@github.com:Vertix-platform/contract.git
cd contracts
```

- Install dependencies:
```
make install
```

## Usage
Compile Contracts

```
forge build --sizes
```

## Run Tests
```
forge test
```

## Deploy Contracts
Deploy to Polygon or Base:

```
 make deploy ARGS="--network polygon-testnet"
```
or

```
make deploy ARGS="--network base-testnet"
```

or

Run you can run `anvil` for local testing

```
make deploy ARGS="--network anvil"
```

## Interact with Contracts
Use Foundry’s cast to interact with deployed contracts. Ensure you have anvil running:

```
cast call <contract-address> "<function-signature>" --rpc-url $POLYGON_RPC_URL
```

## Contract Structure

### Core Marketplace Contracts
- **MarketplaceCore.sol**: Core marketplace functionality for listing, buying, and managing NFT and non-NFT assets
- **MarketplaceStorage.sol**: Storage contract for marketplace listings and data management
- **MarketplaceFees.sol**: Fee calculation and distribution system for marketplace transactions
- **MarketplaceAuctions.sol**: Auction functionality for marketplace assets
- **MarketplaceProxy.sol**: Proxy contract for marketplace implementation upgrades

### NFT & Asset Management
- **VertixNFT.sol**: ERC721 NFT contract with social media integration and verification
- **VertixEscrow.sol**: Secure escrow system for manual asset transfers and dispute resolution
- **VertixGovernance.sol**: Governance contract for platform management and configuration

### Cross-Chain Infrastructure
- **CrossChainBridge.sol**: Bridge contract for cross-chain asset transfers using LayerZero
- **CrossChainRegistry.sol**: Registry for managing cross-chain configurations and validations

### Supporting Contracts
- **VertixUtils.sol**: Utility library for common functions and data structures
- **Interfaces/**: Contract interfaces for external integrations
  - **ICrossChainBridge.sol**: Cross-chain bridge interface
  - **IVertixNFT.sol**: NFT contract interface
  - **IVertixEscrow.sol**: Escrow contract interface
  - **IVertixGovernance.sol**: Governance contract interface


## Testing
Run test per function:

```
forge test --mt <function name>
```

Run test per contract:
```
forge test --mc <contract name>
```

## License
This project is licensed under the MIT License. See the LICENSE (./LICENSE) file for details.

## Contact
For inquiries, reach out via Email or [X](https://x.com/vertix_market).

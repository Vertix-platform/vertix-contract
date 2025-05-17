-include .env

.PHONY: all test clean deploy help install snapshot format anvil

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]"
	@echo "    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "Available networks:"
	@echo "  polygon, polygon-testnet, base, base-testnet, sepolia, eth, anvil"

all: clean remove install update build

clean:; forge clean

remove:; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install:; forge install https://github.com/OpenZeppelin/openzeppelin-contracts.git@v5.0.2 --no-commit && \
	forge install https://github.com/smartcontractkit/chainlink.git@v0.8.1 --no-commit && \
	forge install https://github.com/Cyfrin/foundry-devops.git@0.0.11 --no-commit && \
	forge install https://github.com/transmissions11/solmate.git@v6 --no-commit && \
	forge install https://github.com/foundry-rs/forge-std.git@v1 --no-commit && \
	forge install https://github.com/gnosis/safe-contracts.git@v1.3.0 --no-commit

update:; forge update

build:; forge build

test:; forge test

snapshot:; forge snapshot

format:; forge fmt

anvil:; anvil --block-time 1

NETWORK_ARGS := --rpc-url $(ANVIL_RPC_URL) --private-key $(ANVIL_PRIVATE_KEY) --broadcast -- --vvvv

ifeq ($(findstring --network polygon,$(ARGS)),--network polygon)
	NETWORK_ARGS := --rpc-url $(POLYGON_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier-url $(POLYGONSCAN_API_URL) --verifier polygonscan
endif
ifeq ($(findstring --network polygon-testnet,$(ARGS)),--network polygon-testnet)
	NETWORK_ARGS := --rpc-url $(POLYGON_MUMBAI_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast -- --vvvv
endif
ifeq ($(findstring --network base,$(ARGS)),--network base)
	NETWORK_ARGS := --rpc-url $(BASE_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier-url $(BASESCAN_API_URL) --verifier basescan
endif
ifeq ($(findstring --network base-testnet,$(ARGS)),--network base-testnet)
	NETWORK_ARGS := --rpc-url $(BASE_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast -- --vvvv
endif
ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier-url $(ETHERSCAN_API_URL) --verifier etherscan
endif
ifeq ($(findstring --network eth,$(ARGS)),--network eth)
	NETWORK_ARGS := --rpc-url $(ETHEREUM_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast -- --vvvv
endif
ifeq ($(findstring --network anvil,$(ARGS)),--network anvil)
	NETWORK_ARGS := --rpc-url $(ANVIL_RPC_URL) --private-key $(ANVIL_PRIVATE_KEY) --broadcast -- --vvvv
endif

deploy:
	@forge script script/DeployVertix.s.sol:DeployVertix $(NETWORK_ARGS)

## Sample command
## make deploy ARGS="--network polygon"
## make deploy ARGS="--network polygon-testnet"
## make deploy ARGS="--network base"
## make deploy ARGS="--network base-testnet"
## make deploy ARGS="--network sepolia"
## make deploy ARGS="--network eth"
## make deploy ARGS="--network anvil"
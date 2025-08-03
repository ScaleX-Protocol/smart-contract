-include .env

# Default values
# DEFAULT_NETWORK := arbitrumSepolia
DEFAULT_NETWORK := default_network
FORK_NETWORK := mainnet

# Custom flag can be set via make flag=<flag> e.g. make flag="-vvvv --force"
flag ?=

# Custom network can be set via make network=<network_name>
network ?= $(DEFAULT_NETWORK)

.PHONY: account chain compile deploy deploy-verify flatten fork format generate lint test verify upgrade upgrade-verify full-integration simple-integration simple-demo swap deploy-chain-balance-manager add-tokens-chain-balance-manager add-single-token-chain-balance-manager remove-single-token-chain-balance-manager list-tokens-chain-balance-manager test-chain-balance-manager fill-orderbook-tokens market-orderbook-tokens

# Helper function to run forge script
define forge_script
	forge script script/Deploy.s.sol:Deploy --rpc-url $(network) --broadcast $(flag)
endef

# Helper function to run upgrade script
define forge_upgrade_script
 forge script script/UpgradeBeaconProxies.s.sol:UpgradeBeaconProxies --rpc-url $(network) --broadcast $(flag)
endef

# Helper function to run mock deployment script
define forge_deploy_mocks
	forge script script/DeployMocks.s.sol:DeployMocks --rpc-url $(network) --broadcast $(flag)
endef

define forge_fill_mock_orderbook
	forge script script/FillMockOrderBook.s.sol:FillMockOrderBook --rpc-url $(network) --broadcast $(flag)
endef

define forge_place_market_mock_orderbook
	forge script script/PlaceMarketMockOrderBook.s.sol:PlaceMarketMockOrderBook --rpc-url $(network) --broadcast $(flag)
endef

define forge_fill_orderbook_with_tokens
	forge script script/FillMockOrderBook.s.sol:FillMockOrderBook --sig "runWithTokens(string,string)" "$(token0)" "$(token1)" --rpc-url $(network) --broadcast $(flag)
endef

define forge_market_orderbook_with_tokens
	forge script script/PlaceMarketMockOrderBook.s.sol:PlaceMarketMockOrderBook --sig "runWithTokens(string,string)" "$(token0)" "$(token1)" --rpc-url $(network) --broadcast $(flag)
endef

define forge_swap
	forge script script/Swap.s.sol:Swap --rpc-url $(network) --broadcast $(flag)
endef

define forge_mint_tokens
	forge script script/MintTokens.s.sol:MintTokens --rpc-url $(network) --broadcast $(flag)
endef

define forge_simple_market_order_demo
	forge script script/SimpleMarketOrderDemo.s.sol:SimpleMarketOrderDemo --rpc-url $(network) --broadcast $(flag)
endef

define forge_deploy_chain_balance_manager
	forge script script/DeployChainBalanceManager.s.sol:DeployChainBalanceManager --rpc-url $(network) --broadcast $(flag)
endef

define forge_add_tokens_chain_balance_manager
	forge script script/AddTokensToChainBalanceManager.s.sol:AddTokensToChainBalanceManager --rpc-url $(network) --broadcast $(flag)
endef

define forge_test_chain_balance_manager_unlock_claim
	forge script script/TestChainBalanceManagerUnlockClaim.s.sol:TestChainBalanceManagerUnlockClaim --rpc-url $(network) --broadcast $(flag)
endef

define forge_test_chain_balance_manager_simple
	forge script script/TestChainBalanceManagerSimple.s.sol:TestChainBalanceManagerSimple --rpc-url $(network) --broadcast $(flag)
endef

define forge_test_chain_balance_manager_basic
	forge script script/TestChainBalanceManagerBasic.s.sol:TestChainBalanceManagerBasic --rpc-url $(network) --broadcast $(flag)
endef

# Define a target to deploy using the specified network
deploy:
	$(call forge_script,)
	$(MAKE) generate-abi

# Define a target to verify deployment using the specified network
deploy-verify:
	$(call forge_script,--verify)
	$(MAKE) generate-abi

# Define a target to upgrade contracts using the specified network
upgrade:
	 $(call forge_upgrade_script,)
	 $(MAKE) generate-abi

# Define a target to upgrade and verify contracts using the specified network
upgrade-verify:
	 $(call forge_upgrade_script,--verify)
	 $(MAKE) generate-abi

# Define a target to deploy mock contracts
deploy-mocks:
	$(call forge_deploy_mocks,)

# Define a target to deploy and verify mock contracts
deploy-mocks-verify:
	$(call forge_deploy_mocks,--verify)

# Define a target to fill mock order book
fill-orderbook:
	$(call forge_fill_mock_orderbook,)

# Define a target to place market mock order book
market-orderbook:
	$(call forge_place_market_mock_orderbook,)

# Define a target to fill orderbook with specific tokens
fill-orderbook-tokens:
	$(call forge_fill_orderbook_with_tokens,)

# Define a target to place market orders with specific tokens
market-orderbook-tokens:
	$(call forge_market_orderbook_with_tokens,)

# Define a target to execute swaps
swap:
	$(call forge_swap,)

# Define a target to mint tokens
mint-tokens:
	$(call forge_mint_tokens,)

# Define a target to run simple market order demo
simple-demo:
	$(call forge_simple_market_order_demo,)

# Define a target to deploy ChainBalanceManager
deploy-chain-balance-manager:
	$(call forge_deploy_chain_balance_manager,)

# Define a target to add tokens to ChainBalanceManager
add-tokens-chain-balance-manager:
	$(call forge_add_tokens_chain_balance_manager,)

# Define a target to add single token to ChainBalanceManager
add-single-token-chain-balance-manager:
	forge script script/AddTokensToChainBalanceManager.s.sol:AddTokensToChainBalanceManager --sig "addSingleToken(address)" $(token) --rpc-url $(network) --broadcast $(flag)

# Define a target to remove single token from ChainBalanceManager
remove-single-token-chain-balance-manager:
	forge script script/AddTokensToChainBalanceManager.s.sol:AddTokensToChainBalanceManager --sig "removeSingleToken(address)" $(token) --rpc-url $(network) --broadcast $(flag)

# Define a target to list whitelisted tokens in ChainBalanceManager
list-tokens-chain-balance-manager:
	forge script script/AddTokensToChainBalanceManager.s.sol:AddTokensToChainBalanceManager --sig "listWhitelistedTokens()" --rpc-url $(network)

# Test ChainBalanceManager
test-chain-balance-manager:
	forge test --match-contract ChainBalanceManagerTest -v

# Test ChainBalanceManager unlock/claim functionality with deployment
test-chain-balance-manager-unlock-claim:
	$(call forge_test_chain_balance_manager_unlock_claim,)

# Test ChainBalanceManager simple test (deploys own mock tokens)
test-chain-balance-manager-simple:
	$(call forge_test_chain_balance_manager_simple,)

# Test ChainBalanceManager basic functionality
test-chain-balance-manager-basic:
	$(call forge_test_chain_balance_manager_basic,)

# Define a target to run simple integration (deploy, deploy-mocks, simple demo)
simple-integration:
	@echo "=========================================="
	@echo "Starting Simple Integration Demo..."
	@echo "=========================================="
	@echo "Step 1: Deploying core contracts..."
	$(MAKE) deploy
	@echo "\n✓ Core contracts deployed"
	@sleep 2
	@echo "\nStep 2: Deploying mock tokens..."
	$(MAKE) deploy-mocks
	@echo "\n✓ Mock tokens deployed"
	@sleep 2
	@echo "\nStep 3: Running simple market order demo..."
	$(MAKE) simple-demo
	@echo "\n✓ Simple market order demo completed"
	@echo "\n=========================================="
	@echo "Simple Integration Demo Complete!"
	@echo "=========================================="

# Define a target to run full integration (deploy everything and test)
full-integration:
	@echo "=========================================="
	@echo "Starting Full Integration Test Sequence..."
	@echo "=========================================="
	@echo "Step 1: Deploying core contracts..."
	$(MAKE) deploy
	@echo "\n✓ Core contracts deployed"
	@sleep 2
	@echo "\nStep 2: Deploying mock tokens..."
	$(MAKE) deploy-mocks
	@echo "\n✓ Mock tokens deployed"
	@sleep 2
	@echo "\nStep 3: Filling orderbook with limit orders..."
	$(MAKE) fill-orderbook
	@echo "\n✓ Orderbook filled with limit orders"
	@sleep 2
	@echo "\nStep 4: Placing market orders..."
	$(MAKE) market-orderbook
	@echo "\n✓ Market orders placed and executed"
	@sleep 2
	@echo "\nStep 5: Executing swaps..."
	$(MAKE) swap
	@echo "\n✓ Swaps executed"
	@sleep 2
	@echo "\n=========================================="
	@echo "Full Integration Test Complete!"
	@echo "=========================================="

# Define a target to verify contracts using the specified network
verify:
	forge script script/VerifyAll.s.sol --ffi --rpc-url $(network)

compile-watch-core:
	forge build src/core --watch src/core

test-core:
	forge test src/core --watch src/core

# Define a target to compile the contracts
compile:
	forge compile

# Define a target to run tests
test:
	forge test

# Define a target to lint the code
lint:
	forge fmt

# Define a target to generate ABI files
generate-abi:
	node script/generateTsAbis.js

# Define a target to build the project
build:
	forge clean && forge build --build-info --build-info-path out/build-info/


# Define a target to display help information
help:
	@echo "Makefile targets:"
	@echo "  deploy          - Deploy contracts using the specified network"
	@echo "  deploy-verify   - Deploy and verify contracts using the specified network"
	@echo "  deploy-mocks    - Deploy mock contracts"
	@echo "  deploy-mocks-verify - Deploy and verify mock contracts"
	@echo "  fill-orderbook  - Fill mock order book"
	@echo "  market-orderbook - Place market orders in mock order book"
	@echo "  fill-orderbook-tokens - Fill orderbook with specific tokens (usage: make fill-orderbook-tokens token0=MOCK_TOKEN_WETH token1=MOCK_TOKEN_USDC)"
	@echo "  market-orderbook-tokens - Place market orders with specific tokens (usage: make market-orderbook-tokens token0=MOCK_TOKEN_WETH token1=MOCK_TOKEN_USDC)"
	@echo "  swap            - Execute token swaps"
	@echo "  mint-tokens     - Mint tokens to specified recipient"
	@echo "  simple-demo     - Run simple market order demonstration"
	@echo "  simple-integration - Run simple integration (deploy, deploy-mocks, simple-demo)"
	@echo "  full-integration - Run full deployment and testing sequence"
	@echo "  upgrade         - Upgrade contracts using the specified network"
	@echo "  upgrade-verify  - Upgrade and verify contracts using the specified network"
	@echo "  verify          - Verify contracts using the specified network"
	@echo "  deploy-chain-balance-manager - Deploy ChainBalanceManager contract"
	@echo "  add-tokens-chain-balance-manager - Add tokens to ChainBalanceManager whitelist"
	@echo "  add-single-token-chain-balance-manager - Add single token (usage: make add-single-token-chain-balance-manager token=0x...)"
	@echo "  remove-single-token-chain-balance-manager - Remove single token (usage: make remove-single-token-chain-balance-manager token=0x...)"
	@echo "  list-tokens-chain-balance-manager - List all whitelisted tokens"
	@echo "  test-chain-balance-manager - Run ChainBalanceManager tests"
	@echo "  test-chain-balance-manager-unlock-claim - Test unlock/claim functionality with deployed contracts"
	@echo "  compile         - Compile the contracts"
	@echo "  test            - Run tests"
	@echo "  lint            - Lint the code"
	@echo "  generate-abi    - Generate ABI files"
	@echo "  build           - Build the project with build info"
	@echo "  help            - Display this help information"
-include .env

# Default values
# DEFAULT_NETWORK := arbitrumSepolia
DEFAULT_NETWORK := default_network
FORK_NETWORK := mainnet

# Custom flag can be set via make flag=<flag> e.g. make flag="-vvvv --force"
flag ?=

# Custom network can be set via make network=<network_name>
network ?= $(DEFAULT_NETWORK)

# =============================================================
#                   ESPRESSO HYPERLANE INTEGRATION
# =============================================================

# Espresso testnet RPC URLs (proven working)
RARI_RPC := https://rari.caff.testnet.espresso.network
APPCHAIN_RPC := https://appchain.caff.testnet.espresso.network
ARBITRUM_RPC := https://sepolia-rollup.arbitrum.io/rpc

# Helper function to get RPC URL by network name
define get_rpc_url
$(if $(filter rari_testnet,$(1)),$(RARI_RPC),\
$(if $(filter appchain_testnet,$(1)),$(APPCHAIN_RPC),\
$(if $(filter arbitrum_sepolia,$(1)),$(ARBITRUM_RPC),\
$(1))))
endef

.PHONY: account chain compile deploy deploy-verify flatten fork format generate lint test verify upgrade upgrade-verify full-integration simple-integration simple-demo swap deploy-chain-balance-manager add-tokens-chain-balance-manager add-single-token-chain-balance-manager remove-single-token-chain-balance-manager list-tokens-chain-balance-manager test-chain-balance-manager fill-orderbook-tokens market-orderbook-tokens deploy-upgradeable-gtx upgrade-gtx-contract test-espresso-integration check-env

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

define forge_fill_mock_orderbook_configurable
	forge script script/FillMockOrderBook.s.sol:FillMockOrderBook --sig "runConfigurable(uint128,uint128,uint128,uint128,uint128,uint8,uint128,uint128,uint256,uint256)" $(buy_start_price) $(buy_end_price) $(sell_start_price) $(sell_end_price) $(price_step) $(num_orders) $(buy_quantity) $(sell_quantity) $(eth_amount) $(usdc_amount) --rpc-url $(network) --broadcast $(flag)
endef

define forge_place_market_mock_orderbook_configurable
	forge script script/PlaceMarketMockOrderBook.s.sol:PlaceMarketMockOrderBook --sig "runConfigurable(uint8,uint8,uint256,uint256)" $(num_buy_orders) $(num_sell_orders) $(eth_amount) $(usdc_amount) --rpc-url $(network) --broadcast $(flag)
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

define forge_deploy_faucet
	forge script script/faucet/DeployFaucet.s.sol:DeployFaucet --rpc-url $(network) --broadcast $(flag)
endef

define forge_setup_faucet
	forge script script/faucet/SetupFaucet.s.sol:SetupFaucet --rpc-url $(network) --broadcast $(flag)
endef

define forge_add_faucet_tokens
	forge script script/faucet/AddToken.s.sol:AddToken --rpc-url $(network) --broadcast $(flag)
endef

define forge_deposit_faucet_tokens
	forge script script/faucet/DepositToken.s.sol:DepositToken --rpc-url $(network) --broadcast $(flag)
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

# =============================================================
#              NEW ESPRESSO HYPERLANE FUNCTIONS
# =============================================================

# Environment check
check-env:
	@if [ -z "$(PRIVATE_KEY)" ]; then \
		echo "Error: PRIVATE_KEY not set in .env"; \
		exit 1; \
	fi

# Deploy upgradeable GTX contracts
define forge_deploy_upgradeable_gtx
	NETWORK=$(1) forge script script/DeployUpgradeableGTX.s.sol:DeployUpgradeableGTX --rpc-url $(call get_rpc_url,$(1)) --broadcast $(flag)
endef

# Upgrade GTX contracts
define forge_upgrade_gtx
	PROXY_ADDRESS=$(1) CONTRACT_TYPE=$(2) forge script script/UpgradeGTXContract.s.sol:UpgradeGTXContract --rpc-url $(call get_rpc_url,$(3)) --broadcast $(flag)
endef

# Test Espresso integration
define forge_test_espresso
	TEST_TYPE=$(1) $(2) forge script script/TestEspressoIntegration.s.sol:TestEspressoIntegration --rpc-url $(call get_rpc_url,$(3)) $(4)
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

# Define a target to fill orderbook with configurable parameters
fill-orderbook-configurable:
	$(call forge_fill_mock_orderbook_configurable,)

# Define a target to place market orders with configurable parameters
market-orderbook-configurable:
	$(call forge_place_market_mock_orderbook_configurable,)

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

# Send tokens with balance logging
send-token:
	$(call forge_send_token,)

# Define a target to deploy faucet
deploy-faucet:
	$(call forge_deploy_faucet,)

# Define a target to deploy and verify faucet
deploy-faucet-verify:
	$(call forge_deploy_faucet,--verify)

# Define a target to setup faucet
setup-faucet:
	$(call forge_setup_faucet,)

# Define a target to add tokens to faucet
add-faucet-tokens:
	$(call forge_add_faucet_tokens,)

# Define a target to deposit tokens to faucet
deposit-faucet-tokens:
	$(call forge_deposit_faucet_tokens,)

# Define a target to check token balances
check-balances:
	$(call forge_check_balances,)

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
	@echo "Step 2: Deploying mock tokens..."
	$(MAKE) deploy-mocks
	@echo "\n✓ Mock tokens deployed"
	@sleep 2
	@echo "\nStep 3: Deploying and setting up faucet..."
	forge clean
	$(MAKE) deploy-faucet
	$(MAKE) setup-faucet
	$(MAKE) add-faucet-tokens
	$(MAKE) deposit-faucet-tokens
	@echo "\n✓ Faucet deployed and configured"
	@sleep 2
	@echo "Step 4: Filling orderbook with limit orders..."
	$(MAKE) fill-orderbook
	@echo "\n✓ Orderbook filled with limit orders"
	@sleep 2
	@echo "Step 5: Placing market orders..."
	$(MAKE) market-orderbook
	@echo "\n✓ Market orders placed and executed"
	@sleep 2
	@echo "Step 6: Executing swaps..."
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

# =============================================================
#         NEW UPGRADEABLE & ESPRESSO INTEGRATION TARGETS
# =============================================================

# Deploy upgradeable GTX contracts to Rari (host chain)
deploy-upgradeable-rari: check-env
	@echo "⚡ Deploying Upgradeable GTX to Rari..."
	$(call forge_deploy_upgradeable_gtx,rari_testnet)

# Deploy upgradeable GTX contracts to Appchain (source chain)
deploy-upgradeable-appchain: check-env
	@echo "⚡ Deploying Upgradeable GTX to Appchain..."
	$(call forge_deploy_upgradeable_gtx,appchain_testnet)

# Deploy upgradeable GTX contracts to Arbitrum (source chain)
deploy-upgradeable-arbitrum: check-env
	@echo "⚡ Deploying Upgradeable GTX to Arbitrum..."
	$(call forge_deploy_upgradeable_gtx,arbitrum_sepolia)

# Deploy upgradeable GTX to all chains
deploy-upgradeable-all: check-env
	@echo "🚀 Deploying to all chains with upgradeability..."
	@$(MAKE) deploy-upgradeable-rari
	@echo ""
	@$(MAKE) deploy-upgradeable-appchain
	@echo ""
	@$(MAKE) deploy-upgradeable-arbitrum
	@echo ""
	@echo "🎉 All upgradeable contracts deployed!"
	@echo "📋 Update proxy addresses in .env for instant upgrades"

# Upgrade BalanceManager (Rari host chain)
upgrade-balance-manager: check-env
	@if [ -z "$(PROXY_ADDRESS)" ]; then \
		echo "Usage: make upgrade-balance-manager PROXY_ADDRESS=0x123..."; \
		exit 1; \
	fi
	@echo "⚡ Upgrading BalanceManager in seconds..."
	$(call forge_upgrade_gtx,$(PROXY_ADDRESS),BalanceManager,rari_testnet)

# Upgrade ChainBalanceManager (source chains)
upgrade-chain-balance-manager: check-env
	@if [ -z "$(PROXY_ADDRESS)" ] || [ -z "$(NETWORK)" ]; then \
		echo "Usage: make upgrade-chain-balance-manager PROXY_ADDRESS=0x123... NETWORK=appchain_testnet"; \
		exit 1; \
	fi
	@echo "⚡ Upgrading ChainBalanceManager in seconds..."
	$(call forge_upgrade_gtx,$(PROXY_ADDRESS),ChainBalanceManager,$(NETWORK))

# Test cross-chain deposit (Appchain → Rari) - Working version
deposit-appchain-to-rari: check-env
	@echo "🔄 Depositing from Appchain to Rari..."
	forge script script/TestAppchainToRariDeposit.s.sol:TestAppchainToRariDeposit --rpc-url https://appchain.caff.testnet.espresso.network --broadcast

# Test cross-chain deposit (Appchain → Rari) - Original version
test-deposit: check-env
	@if [ -z "$(APPCHAIN_CHAIN_BM_PROXY)" ]; then \
		echo "Error: Set APPCHAIN_CHAIN_BM_PROXY in .env"; \
		exit 1; \
	fi
	@echo "🔄 Testing cross-chain deposit..."
	$(call forge_test_espresso,deposit,APPCHAIN_CHAIN_BM_PROXY=$(APPCHAIN_CHAIN_BM_PROXY),appchain_testnet,)

# Test cross-chain withdrawal (Rari → Appchain)
test-withdraw: check-env
	@if [ -z "$(RARI_BALANCE_MANAGER_PROXY)" ]; then \
		echo "Error: Set RARI_BALANCE_MANAGER_PROXY in .env"; \
		exit 1; \
	fi
	@echo "🔄 Testing cross-chain withdrawal..."
	$(call forge_test_espresso,withdraw,RARI_BALANCE_MANAGER_PROXY=$(RARI_BALANCE_MANAGER_PROXY),rari_testnet,)

# Test complete cross-chain flow
test-cross-chain: check-env
	@echo "🔄 Testing complete cross-chain flow..."
	$(call forge_test_espresso,complete,APPCHAIN_CHAIN_BM_PROXY=$(APPCHAIN_CHAIN_BM_PROXY) RARI_BALANCE_MANAGER_PROXY=$(RARI_BALANCE_MANAGER_PROXY),appchain_testnet,)

# Check balances across all chains
test-balances: check-env
	@echo "📊 Checking balances across all chains..."
	@echo "=== Rari Synthetic Balances ==="
	@$(call forge_test_espresso,balance_rari,,rari_testnet,)
	@echo ""
	@echo "=== Appchain Unlocked Balances ==="
	@$(call forge_test_espresso,balance_appchain,,appchain_testnet,)


# Define a target to display help information
help:
	@echo "=== GTX CLOB DEX - Upgradeable Contracts with Espresso Hyperlane ==="
	@echo ""
	@echo "🚀 Quick Start Commands:"
	@echo "  deploy-upgradeable-all          - Deploy upgradeable contracts to all chains"
	@echo "  test-cross-chain                - Test complete cross-chain flow"
	@echo ""
	@echo "⚡ Instant Upgrades (Perfect for Accelerator!):"
	@echo "  upgrade-balance-manager PROXY_ADDRESS=0x123..."
	@echo "  upgrade-chain-balance-manager PROXY_ADDRESS=0x123... NETWORK=appchain_testnet"
	@echo ""
	@echo "🔗 Espresso Cross-Chain Testing:"
	@echo "  test-deposit                    - Test Appchain → Rari deposit"
	@echo "  test-withdraw                   - Test Rari → Appchain withdrawal"
	@echo "  test-balances                   - Check balances across all chains"
	@echo ""
	@echo "🏗️  Upgradeable Deployment:"
	@echo "  deploy-upgradeable-rari         - Deploy upgradeable BalanceManager"
	@echo "  deploy-upgradeable-appchain     - Deploy upgradeable ChainBalanceManager"
	@echo "  deploy-upgradeable-arbitrum     - Deploy upgradeable ChainBalanceManager"
	@echo ""
	@echo "📋 Legacy CLOB Commands:"
	@echo "  deploy                          - Deploy contracts using the specified network"
	@echo "  deploy-verify                   - Deploy and verify contracts"
	@echo "  deploy-mocks                    - Deploy mock contracts"
	@echo "  fill-orderbook                  - Fill mock order book"
	@echo "  market-orderbook                - Place market orders in mock order book"
	@echo "  swap                            - Execute token swaps"
	@echo "  simple-demo                     - Run simple market order demonstration"
	@echo "  simple-integration              - Run simple integration sequence"
	@echo "  full-integration                - Run full deployment and testing"
	@echo ""
	@echo "🔧 Development Commands:"
	@echo "  compile                         - Compile the contracts"
	@echo "  test                            - Run tests"
	@echo "  lint                            - Lint the code"
	@echo "  generate-abi                    - Generate ABI files"
	@echo "  build                           - Build project with build info"
	@echo ""
	@echo "📋 Required Environment Variables (.env):"
	@echo "  PRIVATE_KEY=0x123..."
	@echo "  RARI_BALANCE_MANAGER_PROXY=0x123...      # After deployment"
	@echo "  APPCHAIN_CHAIN_BM_PROXY=0x123...         # After deployment"
	@echo ""
	@echo "🎯 Perfect for Accelerator Development!"
	@echo "   Upgrade contracts in seconds, iterate at lightning speed!"

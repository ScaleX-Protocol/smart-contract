# Shell Scripts Directory

This directory contains all project-specific shell scripts organized by functionality.

## 📁 Directory Structure

```
shellscripts/
├── README.md                           # This file
├── lib/                                # Library scripts
│   └── quote-currency-config.sh       # Quote currency configuration
├── lending/                            # Lending-related scripts
│   ├── AchieveAPYGoals.sh
│   ├── AchieveRemainingTargets.sh
│   ├── ExecuteAPYTargets.sh
│   ├── ExecuteAPYTargetsV2.sh
│   ├── borrow-idrx.sh
│   ├── diagnose-borrow.sh
│   ├── run-borrow-only.sh
│   ├── run-deposit-and-borrow.sh
│   ├── run-supply-and-borrow.sh
│   ├── run-weth-borrow-debug.sh
│   └── supply-and-borrow-idrx.sh
└── [49 root-level scripts]
```

## 🚀 Script Categories

### Deployment Scripts
- `deploy.sh` - Main deployment script
- `deploy-faucet.sh` - Deploy faucet contract
- `deploy-sidechain.sh` - Deploy to sidechain
- `upgrade_router.sh` - Upgrade router contract
- `manual-upgrade.sh` - Manual upgrade process
- `validate-deployment.sh` - Validate deployment

### AI Agent Scripts
- `install-simple-policy.sh` - Install agent policy
- `encode-policy.sh` - Encode policy parameters
- `test-agent-install.sh` - Test agent installation
- `test-agent-order.sh` - Test agent order placement
- `test-agent-trade-simple.sh` - Simple agent trade test
- `agent-executor-trade.sh` - Agent executor trading
- `create-multiple-agents.sh` - Create multiple agents
- `complete-agent-setup.sh` - Complete agent setup
- `setup-agent-executors.sh` - Setup agent executors
- `fix-agent-setup-manual.sh` - Fix agent setup manually
- `check-agent-wallets.sh` - Check agent wallet balances
- `fund-agent-wallets.sh` - Fund agent wallets
- `authorize-only.sh` - Authorization only

### Lending Scripts (in `lending/`)
- `AchieveAPYGoals.sh` - Achieve APY targets
- `AchieveRemainingTargets.sh` - Achieve remaining APY targets
- `ExecuteAPYTargets.sh` - Execute APY targets
- `ExecuteAPYTargetsV2.sh` - Execute APY targets v2
- `borrow-idrx.sh` - Borrow IDRX
- `diagnose-borrow.sh` - Diagnose borrowing issues
- `run-borrow-only.sh` - Run borrow-only scenario
- `run-deposit-and-borrow.sh` - Deposit and borrow
- `run-supply-and-borrow.sh` - Supply and borrow
- `run-weth-borrow-debug.sh` - Debug WETH borrowing
- `supply-and-borrow-idrx.sh` - Supply and borrow IDRX

### Lending Management Scripts
- `create-weth-lending-activity.sh` - Create WETH lending activity
- `supply-weth-collateral.sh` - Supply WETH as collateral
- `update-borrowing.sh` - Update borrowing positions
- `update-lending-params.sh` - Update lending parameters
- `test-simple-borrow.sh` - Simple borrow test
- `debug-collateral.sh` - Debug collateral issues
- `debug-health-factor.sh` - Debug health factor
- `analyze-collateral-options.sh` - Analyze collateral options

### Oracle & Pricing Scripts
- `update-rwa-prices.sh` - Update RWA oracle prices
- `update-all-oracle-prices.sh` - Update all oracle prices
- `update-orderbook-prices.sh` - Update orderbook prices
- `check-oracle-prices.sh` - Check oracle prices
- `check-oracle-config.sh` - Check oracle configuration
- `analyze-oracle-logs.sh` - Analyze oracle event logs
- `get-oracle-events.sh` - Get oracle events
- `decode-all-price-events.sh` - Decode price events
- `query-historical-price-events.sh` - Query historical prices
- `find-price-overwrite.sh` - Find price overwrite events

### Wallet & Token Management
- `generate_wallets.sh` - Generate new wallets
- `list-wallets.sh` - List all wallets
- `show-wallet-info.sh` - Show wallet information
- `wallet-summary.sh` - Wallet balance summary
- `send-tokens.sh` - Send tokens between wallets
- `fund-and-deposit.sh` - Fund wallets and deposit

### Data Population & Validation
- `populate-data.sh` - Populate test data
- `validate-data-population.sh` - Validate populated data
- `reset-orderbooks.sh` - Reset orderbooks
- `check-idrx-pool-stats.sh` - Check IDRX pool statistics

### Configuration & Utilities
- `update-env.sh` - Update environment variables
- `QUICK_COMMANDS_2PCT_APY.sh` - Quick commands for 2% APY setup
- `lib/quote-currency-config.sh` - Quote currency configuration library

## 📝 Usage Guidelines

### Running Scripts
Most scripts require being run from the project root:
```bash
# From project root
./shellscripts/deploy.sh

# Or with bash
bash shellscripts/deploy.sh
```

### Environment Requirements
Many scripts require:
- `.env` file with proper configuration
- Forge/Foundry installed
- Correct network RPC URLs
- Funded deployer wallet

### Script Execution Order
For fresh deployment:
1. `deploy.sh` - Deploy all contracts
2. `populate-data.sh` - Populate initial data
3. `validate-deployment.sh` - Validate everything works

For agent setup:
1. `install-simple-policy.sh` - Install policy
2. `create-multiple-agents.sh` - Create agents
3. `fund-agent-wallets.sh` - Fund agents
4. `test-agent-order.sh` - Test trading

## 🔧 Common Tasks

### Update Oracle Prices
```bash
./shellscripts/update-all-oracle-prices.sh
```

### Create Agent and Test Trading
```bash
./shellscripts/install-simple-policy.sh
./shellscripts/test-agent-order.sh
```

### Check System Status
```bash
./shellscripts/check-oracle-prices.sh
./shellscripts/check-idrx-pool-stats.sh
./shellscripts/wallet-summary.sh
```

### Lending Operations
```bash
./shellscripts/lending/supply-and-borrow-idrx.sh
./shellscripts/lending/diagnose-borrow.sh
```

## ⚠️ Important Notes

- **Always review scripts before running** - Many interact with blockchain
- **Check network settings** - Ensure you're on the correct network
- **Backup data** - Some scripts reset state
- **Test on testnet first** - Before running on mainnet
- **Monitor gas prices** - Some operations can be expensive

## 📚 Related Documentation

- Agent System: `/docs/agent-system/`
- Deployment Guide: `/docs/deployment/`
- Lending Protocol: `/docs/lending/`
- Oracle System: `/docs/oracle/`

---

**Last Updated:** February 13, 2026
**Total Scripts:** 60+ (49 root + 11 lending)

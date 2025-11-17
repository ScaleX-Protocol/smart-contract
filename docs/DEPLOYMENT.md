# SCALEX Two-Chain Trading System - Quick Deployment Guide

Deploy the complete SCALEX two-chain trading system with cross-chain token deposits and CLOB trading.

## Architecture

- **Core Chain (31337)**: Trading infrastructure, pools, synthetic tokens
- **Side Chain (31337)**: Token deposits and cross-chain messaging

## Deposit Types

1. **Cross-Chain Deposits**: Side chain → Core chain via Hyperlane messaging
2. **Local Deposits**: Direct deposits on core chain using `depositLocal()` function

## Prerequisites

### 1. Hyperlane Infrastructure
```bash
# Deploy Hyperlane to both chains
cd $PROJECT_DIR/hyperlane-scalex-core-devnet
hyperlane core deploy --chain scalex-core-devnet --registry $PROJECT_DIR/hyperlane-scalex-core-devnet --key $PRIVATE_KEY --yes
hyperlane core deploy --chain scalex-side-devnet --registry $PROJECT_DIR/hyperlane-scalex-core-devnet --key $PRIVATE_KEY --yes

# Start relayer
hyperlane relayer --chains scalex-core-devnet,scalex-side-devnet --registry $PROJECT_DIR/hyperlane-scalex-core-devnet --key $PRIVATE_KEY --yes 2>&1 | tee relayer.log
```

### 2. Set Environment Variables
```bash
# Extract mailbox addresses
export CORE_MAILBOX=$(grep 'mailbox:' $PROJECT_DIR/hyperlane-scalex-core-devnet/chains/scalex-core-devnet/addresses.yaml | awk '{print $2}' | tr -d '"')
export SIDE_MAILBOX=$(grep 'mailbox:' $PROJECT_DIR/hyperlane-scalex-core-devnet/chains/scalex-side-devnet/addresses.yaml | awk '{print $2}' | tr -d '"')

# Verify extraction worked
echo "CORE_MAILBOX: $CORE_MAILBOX"
echo "SIDE_MAILBOX: $SIDE_MAILBOX"
```

## Deployment Steps

### Step 0: Clean Previous Data
```bash
rm -f deployments/*.json
rm -rf broadcast/ cache/ out/
```

### Step 1: Deploy Core Chain Trading
```bash
CORE_MAILBOX=$CORE_MAILBOX SIDE_MAILBOX=$SIDE_MAILBOX make deploy-core-chain-trading network=scalex_core_devnet
```

### Step 2: Deploy Side Chain Tokens
```bash
make deploy-side-chain-tokens network=scalex_side_devnet
```

### Step 3: Deploy Core Chain Tokens
```bash
make deploy-core-chain-tokens network=scalex_core_devnet
```

### Step 4: Create Trading Pools
```bash
make create-trading-pools network=scalex_core_devnet
```

### Step 5: Deploy Side Chain Balance Manager
```bash
SIDE_MAILBOX=$SIDE_MAILBOX CORE_MAILBOX=$CORE_MAILBOX make deploy-side-chain-bm network=scalex_side_devnet
```

### Step 6: Configure Cross-Chain
```bash
# Chain IDs are now auto-detected from network parameter - no manual specification needed!
make register-side-chain network=scalex_core_devnet
make configure-balance-manager network=scalex_core_devnet
make update-core-chain-mappings network=scalex_core_devnet
```

### Step 7: Update Side Chain Mappings
```bash
make update-side-chain-mappings network=scalex_side_devnet
```

**NOTE**: Step 6 above now automatically configures both cross-chain AND local token mappings:
- **Cross-chain mappings**: Side chain tokens → Core chain synthetic tokens  
- **Local mappings**: Core chain regular tokens → Core chain synthetic tokens (for `depositLocal()`)

This ensures both deposit pathways work correctly for trading.

## Validation & Testing

### 1. Validate Core Deployment
```bash
make validate-deployment
```
Should show: ` ALL VALIDATIONS PASSED!`

### 2. Validate Cross-Chain System
```bash
make validate-cross-chain-deposit
```
Should show: ` CROSS-CHAIN SYSTEM VALIDATION PASSED!`

This validates:
- Chain connectivity (both core and side chains)
- Contract deployment verification 
- Token whitelisting and mapping correctness
- User token balances and cross-chain activity
- Hyperlane integration status

### 3. Test Cross-Chain Deposits
```bash
# Test USDC cross-chain deposit
make test-cross-chain-deposit network=scalex_side_devnet side_chain=31337 core_chain=31337 token=USDC amount=1000000000

# Test WETH cross-chain deposit  
make test-cross-chain-deposit network=scalex_side_devnet side_chain=31337 core_chain=31337 token=WETH amount=1000000000000000000
```

### 4. Test Local Deposits
```bash
# Test USDC local deposit on core chain
make test-local-deposit network=scalex_core_devnet token=USDC amount=1000000000

# Test WETH local deposit on core chain
make test-local-deposit network=scalex_core_devnet token=WETH amount=1000000000000000000
```

### 5. Test Data Population (Optional)
```bash
# Populate system with traders, liquidity, and trading activity
make validate-data-population
```
Should show: ` DATA POPULATION VALIDATION PASSED!`

## Quick Validation Workflow

After completing all deployment steps, run this validation sequence:

```bash
# 1. Validate core deployment
make validate-deployment

# 2. Validate cross-chain system  
make validate-cross-chain-deposit

# 3. Test both deposit methods
make test-cross-chain-deposit network=scalex_side_devnet side_chain=31337 core_chain=31337 token=USDC amount=1000000000
make test-local-deposit network=scalex_core_devnet token=USDC amount=1000000000

# 4. Optional: Populate with trading data
make validate-data-population
```

All commands should show success messages. Check the respective `.log` files for detailed results.

## Expected Files

After successful deployment:
```bash
deployments/
├── 31337.json    # Core chain contracts
└── 31337.json    # Side chain contracts

# Validation log files (created during testing)
deployment.log              # Core deployment validation results
cross-chain-deposit.log     # Cross-chain system validation results  
population.log             # Data population validation results (optional)
```

## Available Validation Scripts

The deployment includes comprehensive validation scripts:

| Script | Command | Purpose |
|--------|---------|---------|
| **Core Deployment** | `make validate-deployment` | Validates all contracts, pools, and basic functionality |
| **Cross-Chain System** | `make validate-cross-chain-deposit` | Validates cross-chain deposits, token mappings, and Hyperlane integration |
| **Data Population** | `make validate-data-population` | Validates trading system with populated data (traders, liquidity, activity) |

## Core Deployment Structure

### Core Chain (31337.json)
- `PROXY_BALANCEMANAGER` - Main trading contract
- `PROXY_TOKENREGISTRY` - Token registry (handles local + cross-chain mappings)
- `PROXY_SYNTHETICTOKENFACTORY` - Creates synthetic tokens
- `PROXY_POOLMANAGER` - Manages trading pools
- `gsUSDC`, `gsWETH`, `gsWBTC` - Synthetic tokens for trading
- `USDC`, `WETH`, `WBTC` - Regular tokens for local deposits

### Side Chain (31337.json)  
- `ChainBalanceManager` - Handles deposits
- `USDC`, `WETH`, `WBTC` - Native tokens

## Quick Troubleshooting

**Command fails with "file not found"**: Use chain IDs (31337, 31337) not chain names
**Validation fails**: Run deployment steps in order, don't skip steps
**Cross-chain deposits fail**: Ensure Hyperlane relayer is running
**Local deposits fail**: Ensure Step 6 (update-core-chain-mappings) was completed
**Trading fails after deposits**: TokenRegistry misconfiguration - validation will catch this
**"TokenRegistry local mapping misconfigured"**: Re-run Step 6 to fix token mappings

## Success Criteria

### Core Deployment Success
`make validate-deployment` passes (including TokenRegistry local mappings)
Both deployment files exist (31337.json, 31337.json)  
Required trading pools exist (gsWETH/gsUSDC, gsWBTC/gsUSDC)
All contracts have non-zero addresses

### Cross-Chain System Success  
`make validate-cross-chain-deposit` passes
Token whitelisting and mappings are correct
Hyperlane relayer is active and processing messages
Cross-chain deposit tests succeed

### Trading System Readiness
Local deposit tests succeed (can trade after deposits)
Users can deposit both via cross-chain and local methods
Synthetic tokens are properly minted for trading
Optional: `make validate-data-population` passes for full trading demo  

---

**Total deployment time**: ~5-10 minutes  
**Result**: Fully functional two-chain trading system ready for use.
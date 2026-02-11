# Range Liquidity Manager - Quick Start

## 🚀 Quick Deployment

```bash
# 1. Set up environment
cp .env.example .env
# Edit .env with your values:
#   PRIVATE_KEY, RPC_URL, POOL_MANAGER, BALANCE_MANAGER, SCALEX_ROUTER

# 2. Deploy everything in one command
forge script script/deployments/DeployAndConfigureRangeLiquidity.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    -vvvv

# 3. Save the output addresses to .env
# (Copy from script output)
```

## 📋 Common Commands

### Create Position
```bash
# Set parameters in .env
BASE_TOKEN=0x...
QUOTE_TOKEN=0x...
LOWER_PRICE=7000000000000
UPPER_PRICE=8000000000000
TICK_COUNT=20
DEPOSIT_AMOUNT=100000000000
REBALANCE_THRESHOLD=500

# Create position
forge script script/range-liquidity/CreateTestPosition.s.sol \
    --rpc-url $RPC_URL --broadcast
```

### View Position
```bash
# Set POSITION_ID in .env
POSITION_ID=1

# View details
forge script script/range-liquidity/ViewPosition.s.sol \
    --rpc-url $RPC_URL
```

### Rebalance Position
```bash
# Manual rebalance (as owner)
forge script script/range-liquidity/RebalancePosition.s.sol \
    --rpc-url $RPC_URL --broadcast
```

### Set Bot
```bash
# Set BOT_ADDRESS in .env
BOT_ADDRESS=0x...

# Authorize bot
forge script script/range-liquidity/SetAuthorizedBot.s.sol \
    --rpc-url $RPC_URL --broadcast
```

### Close Position
```bash
# Close and withdraw all funds
forge script script/range-liquidity/ClosePosition.s.sol \
    --rpc-url $RPC_URL --broadcast
```

## 🔧 Using Cast (CLI)

### View Position
```bash
cast call $RANGE_LIQUIDITY_MANAGER \
    "getPosition(uint256)" $POSITION_ID \
    --rpc-url $RPC_URL
```

### Check Rebalance Status
```bash
cast call $RANGE_LIQUIDITY_MANAGER \
    "canRebalance(uint256)(bool,uint256)" $POSITION_ID \
    --rpc-url $RPC_URL
```

### Get User Positions
```bash
cast call $RANGE_LIQUIDITY_MANAGER \
    "getUserPositions(address)(uint256[])" $USER_ADDRESS \
    --rpc-url $RPC_URL
```

### Rebalance (via Cast)
```bash
cast send $RANGE_LIQUIDITY_MANAGER \
    "rebalancePosition(uint256)" $POSITION_ID \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

## 📊 Position Strategies

### UNIFORM (50/50)
Equal distribution of buy and sell orders
```solidity
strategy: IRangeLiquidityManager.Strategy.UNIFORM
```

### BID_HEAVY (70/30)
More buy orders - good for accumulation
```solidity
strategy: IRangeLiquidityManager.Strategy.BID_HEAVY
```

### ASK_HEAVY (30/70)
More sell orders - good for distribution
```solidity
strategy: IRangeLiquidityManager.Strategy.ASK_HEAVY
```

## 🎯 Example Parameters

### Conservative (Tight Range)
```bash
LOWER_PRICE=74000_00000000  # 74k
UPPER_PRICE=76000_00000000  # 76k
TICK_COUNT=10
REBALANCE_THRESHOLD=200      # 2%
```

### Moderate (Medium Range)
```bash
LOWER_PRICE=70000_00000000  # 70k
UPPER_PRICE=80000_00000000  # 80k
TICK_COUNT=20
REBALANCE_THRESHOLD=500      # 5%
```

### Aggressive (Wide Range)
```bash
LOWER_PRICE=60000_00000000  # 60k
UPPER_PRICE=90000_00000000  # 90k
TICK_COUNT=50
REBALANCE_THRESHOLD=1000     # 10%
```

## ⚠️ Important Notes

1. **One Position Per Pool**: Each address can only have 1 active position per pool
2. **Post-Only Orders**: All orders are passive (Post-Only)
3. **Gas Costs**: Scale with tick count (10 ticks ≈ 500k gas, 50 ticks ≈ 2M gas)
4. **Approvals**: Must approve tokens to BalanceManager before creating position
5. **Price Format**: Use 8 decimals for prices (70000_00000000 = 70,000)

## 🤖 Keeper Bot (Simple)

```bash
#!/bin/bash
# monitor.sh

while true; do
    echo "Checking position $POSITION_ID..."

    CAN_REBALANCE=$(cast call $RANGE_LIQUIDITY_MANAGER \
        "canRebalance(uint256)(bool,uint256)" $POSITION_ID \
        --rpc-url $RPC_URL | head -1)

    if [[ $CAN_REBALANCE == "true" ]]; then
        echo "Rebalancing..."
        cast send $RANGE_LIQUIDITY_MANAGER \
            "rebalancePosition(uint256)" $POSITION_ID \
            --rpc-url $RPC_URL \
            --private-key $BOT_PRIVATE_KEY
    fi

    sleep 300  # Check every 5 minutes
done
```

## 📚 Full Documentation

- **User Guide**: `RANGE_LIQUIDITY_README.md`
- **Deployment**: `DEPLOYMENT_GUIDE.md`
- **Contracts**: `src/core/RangeLiquidityManager.sol`

## ❓ Troubleshooting

| Error | Solution |
|-------|----------|
| `PositionAlreadyExists` | Close existing position first |
| `InvalidPriceRange` | Check current price is within range |
| `NotAuthorizedToRebalance` | Set bot via `setAuthorizedBot()` |
| `RebalanceThresholdNotMet` | Wait for more price drift |
| `InsufficientBalance` | Ensure you have enough tokens |

## 🔗 Useful Links

- Foundry Docs: https://book.getfoundry.sh/
- Contract Source: `src/core/RangeLiquidityManager.sol`
- Scripts: `script/range-liquidity/`

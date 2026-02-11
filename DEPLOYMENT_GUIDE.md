# Range Liquidity Manager - Deployment Guide

## Prerequisites

1. **Environment Setup**
   - Foundry installed (`forge`, `cast`, `anvil`)
   - Private key with sufficient gas funds
   - RPC endpoint for target network

2. **Existing Contracts**
   - PoolManager deployed
   - BalanceManager deployed
   - ScaleXRouter deployed

3. **Environment Variables**

Create a `.env` file:

```bash
# Network
RPC_URL=https://your-rpc-endpoint
CHAIN_ID=5000

# Deployer
PRIVATE_KEY=your_private_key_here

# Existing Contract Addresses
POOL_MANAGER=0x...
BALANCE_MANAGER=0x...
SCALEX_ROUTER=0x...

# Optional: For testing
BASE_TOKEN=0x...  # e.g., WBTC
QUOTE_TOKEN=0x... # e.g., USDC
```

## Deployment Steps

### Step 1: Deploy RangeLiquidityManager

```bash
# Load environment variables
source .env

# Deploy the contract
forge script script/deployments/DeployRangeLiquidityManager.s.sol:DeployRangeLiquidityManager \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    -vvvv
```

**Expected Output:**
```
=== DEPLOYING RANGE LIQUIDITY MANAGER ===
Deployer address: 0x...

Configuration:
  PoolManager: 0x...
  BalanceManager: 0x...
  Router: 0x...

Step 1: Deploying RangeLiquidityManager implementation...
[OK] Implementation deployed at: 0x...

Step 2: Deploying UpgradeableBeacon...
[OK] Beacon deployed at: 0x...

Step 3: Deploying BeaconProxy...
[OK] Proxy deployed at: 0x...

=== DEPLOYMENT COMPLETE ===

Deployed Addresses:
  Implementation: 0x...
  Beacon: 0x...
  Proxy (RangeLiquidityManager): 0x...
```

**Save the proxy address:**
```bash
echo "RANGE_LIQUIDITY_MANAGER=0x..." >> .env
echo "RANGE_LIQUIDITY_BEACON=0x..." >> .env
```

### Step 2: Configure Permissions

```bash
# Configure RangeLiquidityManager in BalanceManager
forge script script/configuration/ConfigureRangeLiquidityManager.s.sol:ConfigureRangeLiquidityManager \
    --rpc-url $RPC_URL \
    --broadcast \
    -vvvv
```

**Expected Output:**
```
=== CONFIGURING RANGE LIQUIDITY MANAGER ===
Deployer: 0x...
RangeLiquidityManager: 0x...
BalanceManager: 0x...

Step 1: Authorizing RangeLiquidityManager in BalanceManager...
[OK] RangeLiquidityManager authorized

=== CONFIGURATION COMPLETE ===
```

### Step 3: Verify Deployment

```bash
# Check if RangeLiquidityManager is authorized
cast call $BALANCE_MANAGER \
    "isAuthorizedOperator(address)(bool)" \
    $RANGE_LIQUIDITY_MANAGER \
    --rpc-url $RPC_URL
```

**Expected:** `true`

## Testing Deployment

### Create a Test Position

Set up test parameters in `.env`:

```bash
# Test Position Parameters
BASE_TOKEN=0x...           # WBTC address
QUOTE_TOKEN=0x...          # USDC address
LOWER_PRICE=7000000000000  # 70,000 (8 decimals)
UPPER_PRICE=8000000000000  # 80,000 (8 decimals)
TICK_COUNT=20
DEPOSIT_AMOUNT=100000000000 # 100,000 USDC (6 decimals)
REBALANCE_THRESHOLD=500     # 5%
```

Run the test script:

```bash
forge script script/range-liquidity/CreateTestPosition.s.sol:CreateTestPosition \
    --rpc-url $RPC_URL \
    --broadcast \
    -vvvv
```

**Expected Output:**
```
=== CREATING TEST RANGE LIQUIDITY POSITION ===
User: 0x...
RangeLiquidityManager: 0x...

Position Parameters:
  Base Token: 0x...
  Quote Token: 0x...
  Price Range: 7000000000000 - 8000000000000
  Tick Count: 20
  Deposit Amount: 100000000000
  Strategy: UNIFORM
  Auto-Rebalance: true
  Rebalance Threshold: 500 bps

Step 1: Approving tokens...
[OK] Tokens approved

Step 2: Creating position...
[OK] Position created!
Position ID: 1

Step 3: Fetching position details...
Position Details:
  Owner: 0x...
  Strategy: 0
  Lower Price: 7000000000000
  Upper Price: 8000000000000
  Center Price: 7500000000000
  Tick Count: 20
  Buy Orders: 10
  Sell Orders: 10
  Active: true
  Created At: 1234567890

Position Value:
  Total Value (Quote): 100000000000
  Base Amount: 0
  Quote Amount: 100000000000
  Locked in Orders: 100000000000
  Free Balance: 0

Rebalance Status:
  Can Rebalance: false
  Current Drift: 0 bps

=== POSITION CREATION COMPLETE ===

Position ID: 1
```

Save the position ID:
```bash
echo "POSITION_ID=1" >> .env
```

## Managing Positions

### View Position Details

```bash
forge script script/range-liquidity/ViewPosition.s.sol:ViewPosition \
    --rpc-url $RPC_URL \
    -vvvv
```

### Rebalance Position

```bash
# Manual rebalance (as owner)
forge script script/range-liquidity/RebalancePosition.s.sol:RebalancePosition \
    --rpc-url $RPC_URL \
    --broadcast \
    -vvvv
```

### Close Position

```bash
forge script script/range-liquidity/ClosePosition.s.sol:ClosePosition \
    --rpc-url $RPC_URL \
    --broadcast \
    -vvvv
```

## Keeper Bot Setup

For automated rebalancing, set up a keeper bot:

### 1. Authorize Bot Address

```bash
# Set bot address in .env
echo "BOT_ADDRESS=0x..." >> .env

# Authorize bot for position
cast send $RANGE_LIQUIDITY_MANAGER \
    "setAuthorizedBot(uint256,address)" \
    $POSITION_ID \
    $BOT_ADDRESS \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

### 2. Bot Monitoring Script

Create a simple monitoring script:

```bash
#!/bin/bash
# monitor_positions.sh

while true; do
    echo "Checking position $POSITION_ID..."

    # Check if can rebalance
    CAN_REBALANCE=$(cast call $RANGE_LIQUIDITY_MANAGER \
        "canRebalance(uint256)(bool,uint256)" \
        $POSITION_ID \
        --rpc-url $RPC_URL)

    if [[ $CAN_REBALANCE == *"true"* ]]; then
        echo "Rebalancing position $POSITION_ID..."

        # Execute rebalance
        forge script script/range-liquidity/RebalancePosition.s.sol:RebalancePosition \
            --rpc-url $RPC_URL \
            --broadcast \
            --private-key $BOT_PRIVATE_KEY
    else
        echo "No rebalance needed"
    fi

    # Wait 5 minutes
    sleep 300
done
```

Make executable and run:
```bash
chmod +x monitor_positions.sh
./monitor_positions.sh
```

## Verification Checklist

- [ ] RangeLiquidityManager deployed successfully
- [ ] Beacon and proxy addresses saved
- [ ] RangeLiquidityManager authorized in BalanceManager
- [ ] Test position created successfully
- [ ] Position shows correct parameters
- [ ] Orders placed in orderbook (check via OrderBook contract)
- [ ] Can view position details
- [ ] Can rebalance position (after price drift)
- [ ] Can close position and receive funds
- [ ] Bot authorization works (if using keeper)

## Troubleshooting

### Issue: "PositionAlreadyExists"

**Cause:** User already has a position for this pool.

**Solution:** Close existing position first or use a different address.

```bash
# Check user positions
cast call $RANGE_LIQUIDITY_MANAGER \
    "getUserPositions(address)(uint256[])" \
    $USER_ADDRESS \
    --rpc-url $RPC_URL
```

### Issue: "InvalidPriceRange"

**Cause:** Lower price >= upper price, or current price outside range.

**Solution:** Check current market price and adjust range.

```bash
# Get current price from Oracle
cast call $ORACLE \
    "getPrice(address)(uint256)" \
    $BASE_TOKEN \
    --rpc-url $RPC_URL
```

### Issue: "NotAuthorizedToRebalance"

**Cause:** Caller is not owner or authorized bot.

**Solution:** Check bot authorization.

```bash
# Get position details
cast call $RANGE_LIQUIDITY_MANAGER \
    "getPosition(uint256)" \
    $POSITION_ID \
    --rpc-url $RPC_URL
```

### Issue: "RebalanceThresholdNotMet"

**Cause:** Price hasn't drifted enough.

**Solution:** Wait for more price movement or manually rebalance as owner.

```bash
# Check drift
cast call $RANGE_LIQUIDITY_MANAGER \
    "canRebalance(uint256)(bool,uint256)" \
    $POSITION_ID \
    --rpc-url $RPC_URL
```

### Issue: Insufficient balance

**Cause:** User doesn't have enough tokens.

**Solution:** Mint or acquire tokens first.

```bash
# Check token balance
cast call $QUOTE_TOKEN \
    "balanceOf(address)(uint256)" \
    $USER_ADDRESS \
    --rpc-url $RPC_URL
```

## Gas Estimates

Based on tick count:

| Tick Count | Create Gas | Rebalance Gas | Close Gas |
|------------|------------|---------------|-----------|
| 10         | ~500k      | ~1M           | ~300k     |
| 20         | ~900k      | ~1.8M         | ~500k     |
| 50         | ~2M        | ~4M           | ~1M       |
| 100        | ~4M        | ~8M           | ~2M       |

**Recommendation:** Start with 10-20 ticks for optimal gas efficiency.

## Production Deployment

### Mainnet Deployment

1. **Test on testnet first**
   - Deploy to Sepolia/Goerli
   - Create test positions
   - Verify all functionality

2. **Security audit**
   - Get contracts audited
   - Fix any issues found

3. **Deploy to mainnet**
   ```bash
   # Use mainnet RPC and private key
   RPC_URL=https://mainnet.rpc PRIVATE_KEY=$MAINNET_KEY \
   forge script script/deployments/DeployRangeLiquidityManager.s.sol \
       --rpc-url $RPC_URL \
       --broadcast \
       --verify
   ```

4. **Monitor closely**
   - Watch for unusual activity
   - Monitor gas prices
   - Set up alerts for rebalancing

## Support

For issues or questions:
- GitHub Issues: [Create an issue](https://github.com/your-repo/issues)
- Documentation: See `RANGE_LIQUIDITY_README.md`
- Contract Source: `src/core/RangeLiquidityManager.sol`

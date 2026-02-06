# Complete Lending APY Update Solution

## Overview

This solution provides a complete script that updates interest rate parameters **AND** creates lending activity (deposits + borrows) to generate non-zero APY values, similar to how `update-orderbook-prices.sh` creates trading activity.

## What It Does

The script performs **4 phases** automatically:

1. **Phase 1**: Update interest rate parameters for all selected tokens
2. **Phase 2**: Supply tokens to lending pools (deposits)
3. **Phase 3**: Borrow tokens against collateral (creates utilization)
4. **Phase 4**: Verify APY values are non-zero

**Result**: Supply APY becomes > 0% because borrowing activity creates utilization!

## Quick Start

```bash
# Run with defaults (30% utilization)
bash shellscripts/update-lending-params.sh

# Create 50% utilization (higher supply APY)
BORROW_RATIO=50 bash shellscripts/update-lending-params.sh

# Update only IDRX and WETH
TOKENS="IDRX,WETH" bash shellscripts/update-lending-params.sh
```

## How It Works

### Phase 1: Update Interest Rate Parameters
```
Calls LendingManager.setInterestRateParams() for each token
- Sets base rate, optimal utilization, slopes
- Emits InterestRateParamsSet events
- Indexer processes and updates database
```

### Phase 2: Supply Tokens
```
Calls LendingManager.supply() for each token
- Deposits tokens from user balance
- Creates supply positions
- Makes tokens available for borrowing
```

### Phase 3: Borrow Tokens
```
Calls LendingManager.borrow() for each token
- Borrows percentage of supplied amount (default 30%)
- Creates utilization = borrowed / supplied
- Generates interest that suppliers earn
```

### Phase 4: Calculate APY
```
Borrow APY = f(baseRate, utilization, slopes)
Supply APY = Borrow APY × Utilization

Example with 30% utilization:
- IDRX Borrow APY: ~5.75%
- IDRX Supply APY: ~1.73% (5.75% × 30%)
```

## Environment Variables

### Required
- `PRIVATE_KEY` - Account with tokens and permissions

### Optional Configuration

#### Network Settings
```bash
SCALEX_CORE_RPC="http://127.0.0.1:8545"  # RPC URL
CORE_CHAIN_ID="84532"                     # Chain ID (auto-detected)
```

#### Token Selection
```bash
TOKENS="ALL"                    # ALL or comma-separated list
TOKENS="IDRX,WETH,WBTC"        # Only these tokens
```

#### Lending Activity
```bash
BORROW_RATIO=30                 # % of supply to borrow (creates utilization)
IDRX_SUPPLY_AMOUNT=10000        # Amount to supply (in token units)
WETH_SUPPLY_AMOUNT=10           # Amount to supply (in token units)
```

#### Interest Rate Parameters (basis points: 1% = 100)
```bash
IDRX_BASE_RATE=200              # 2.00%
IDRX_OPTIMAL_UTIL=8000          # 80.00%
IDRX_RATE_SLOPE1=1000           # 10.00%
IDRX_RATE_SLOPE2=5000           # 50.00%
```

## Usage Examples

### Example 1: Basic Usage
```bash
# Update all tokens with 30% utilization
bash shellscripts/update-lending-params.sh
```

**Result**:
- All tokens get interest rates configured
- 30% of supply is borrowed
- Supply APY becomes non-zero

### Example 2: Higher Utilization (Higher APY)
```bash
# Create 50% utilization for higher supply APY
BORROW_RATIO=50 bash shellscripts/update-lending-params.sh
```

**Result**:
- 50% of supply is borrowed
- Supply APY = Borrow APY × 50% (higher earnings)

### Example 3: Specific Tokens Only
```bash
# Update only IDRX and WETH
TOKENS="IDRX,WETH" bash shellscripts/update-lending-params.sh
```

### Example 4: Custom Supply Amounts
```bash
# Supply larger amounts
IDRX_SUPPLY_AMOUNT=100000 \
WETH_SUPPLY_AMOUNT=50 \
BORROW_RATIO=40 \
bash shellscripts/update-lending-params.sh
```

### Example 5: Custom Interest Rates
```bash
# Increase IDRX base rate to 3%
IDRX_BASE_RATE=300 \
IDRX_RATE_SLOPE1=1200 \
bash shellscripts/update-lending-params.sh
```

### Example 6: Complete Customization
```bash
# Everything custom
TOKENS="IDRX" \
IDRX_BASE_RATE=250 \
IDRX_OPTIMAL_UTIL=8000 \
IDRX_RATE_SLOPE1=1200 \
IDRX_RATE_SLOPE2=5000 \
IDRX_SUPPLY_AMOUNT=50000 \
BORROW_RATIO=45 \
bash shellscripts/update-lending-params.sh
```

## Default Configuration

### Stablecoins (IDRX)
```
Interest Rates:
  Base Rate: 2%
  Optimal: 80%
  Slope1: 10%
  Slope2: 50%

Lending Activity:
  Supply: 10,000 IDRX
  Borrow: 30% of supply = 3,000 IDRX
  Utilization: 30%

Expected APY (at 30% utilization):
  Borrow APY: ~5.75%
  Supply APY: ~1.73%
```

### Crypto Assets (WETH)
```
Interest Rates:
  Base Rate: 3%
  Optimal: 80%
  Slope1: 12%
  Slope2: 60%

Lending Activity:
  Supply: 10 WETH
  Borrow: 30% = 3 WETH
  Utilization: 30%

Expected APY (at 30% utilization):
  Borrow APY: ~7.5%
  Supply APY: ~2.25%
```

### Crypto Assets (WBTC)
```
Interest Rates:
  Base Rate: 2.5%
  Optimal: 80%
  Slope1: 11%
  Slope2: 55%

Lending Activity:
  Supply: 1 WBTC
  Borrow: 30% = 0.3 WBTC
  Utilization: 30%

Expected APY (at 30% utilization):
  Borrow APY: ~6.625%
  Supply APY: ~1.99%
```

## Verification

### 1. Check Script Output
```bash
# Look for success messages in the terminal output:
[OK] IDRX interest rates set
[OK] IDRX supplied: 10000
[OK] IDRX borrowed: 3000
[OK] Supply APY is non-zero!
```

### 2. Check Dashboard API
```bash
# Verify non-zero APY in the response
curl -s http://localhost:42070/api/lending/dashboard/0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a | \
  jq '.supplies[] | {asset, realTimeRates}'

# Expected output:
{
  "asset": "IDRX",
  "realTimeRates": {
    "supplyAPY": "1.73%",     # Non-zero!
    "borrowAPY": "5.75%",
    "utilizationRate": "30.0%"
  }
}
```

### 3. Check Database
```bash
# Verify interest rate parameters
docker exec postgres-database psql -U postgres -d ponder_base_sepolia -c \
  "SELECT token, base_rate, optimal_utilization FROM interest_rate_parameters WHERE token LIKE '%80fd%';"

# Verify lending positions
docker exec postgres-database psql -U postgres -d ponder_base_sepolia -c \
  "SELECT * FROM lending_positions WHERE user_address = '0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a' LIMIT 5;"
```

## Understanding APY Calculation

### Borrow APY Formula
```
If utilization ≤ optimal:
  Borrow APY = baseRate + (utilization / optimal) × rateSlope1

If utilization > optimal:
  Borrow APY = baseRate + rateSlope1 + ((utilization - optimal) / (1 - optimal)) × rateSlope2
```

### Supply APY Formula
```
Supply APY = Borrow APY × Utilization × (1 - Reserve Factor)
```

### Example Calculation (IDRX at 30% utilization)
```
Given:
- Base Rate: 2% (200 bps)
- Optimal: 80% (8000 bps)
- Slope1: 10% (1000 bps)
- Utilization: 30%

Calculation:
- Borrow APY = 2% + (30% / 80%) × 10%
             = 2% + 0.375 × 10%
             = 2% + 3.75%
             = 5.75%

- Supply APY = 5.75% × 30%
             = 1.725%
```

## Comparison with Orderbook Price Script

| Feature | update-orderbook-prices.sh | update-lending-params.sh |
|---------|---------------------------|--------------------------|
| **Purpose** | Create trading activity | Create lending activity |
| **Phase 1** | Place limit orders (BUY) | Update interest rates |
| **Phase 2** | Place limit orders (SELL) | Supply tokens (deposits) |
| **Phase 3** | Execute market orders | Borrow tokens |
| **Phase 4** | Verify prices | Verify APY > 0% |
| **Result** | Non-zero prices on orderbook | Non-zero supply APY |
| **Pattern** | Same multi-phase approach | Same multi-phase approach |

## Troubleshooting

### Issue: Supply APY still 0%

**Possible Causes**:
1. Borrowing failed (insufficient collateral)
2. BORROW_RATIO set to 0
3. Supply amount too small

**Solution**:
```bash
# Check script output for errors
cat /tmp/update_lending_params_output.log | grep -i error

# Increase borrow ratio
BORROW_RATIO=50 bash shellscripts/update-lending-params.sh

# Check borrowing power
cast call $LENDING_MANAGER "getUserBorrowingPower(address)(uint256)" $USER_ADDRESS
```

### Issue: Insufficient balance for supply

**Error**: `[SKIP] IDRX - insufficient balance`

**Solution**:
```bash
# Deposit tokens to BalanceManager first
# Check current balance
cast call $BALANCE_MANAGER "getBalance(address,address)(uint256)" $USER_ADDRESS $TOKEN_ADDRESS

# Deposit more tokens
cast send $BALANCE_MANAGER "deposit(address,uint256)" $TOKEN_ADDRESS $AMOUNT --private-key $PRIVATE_KEY
```

### Issue: Script permission denied

**Solution**:
```bash
chmod +x shellscripts/update-lending-params.sh
```

### Issue: Forge compilation error

**Solution**:
```bash
# Recompile contracts
forge build --force

# Try again
bash shellscripts/update-lending-params.sh
```

## Advanced Usage

### Adjust Utilization Dynamically

Create different utilization levels for different tokens:

```bash
# High utilization for stablecoins (safer)
IDRX_SUPPLY_AMOUNT=100000
IDRX_BORROW_AMOUNT=70000  # 70% utilization

# Lower utilization for volatile assets
WETH_SUPPLY_AMOUNT=10
WETH_BORROW_AMOUNT=2      # 20% utilization

# Run the script
IDRX_SUPPLY_AMOUNT=100000 IDRX_BORROW_AMOUNT=70000 \
WETH_SUPPLY_AMOUNT=10 WETH_BORROW_AMOUNT=2 \
bash shellscripts/update-lending-params.sh
```

### Test Interest Rate Models

Experiment with different rate curves:

```bash
# Aggressive rates (high APY)
IDRX_BASE_RATE=500       # 5%
IDRX_RATE_SLOPE1=2000    # 20%
BORROW_RATIO=40

# Conservative rates (low APY)
IDRX_BASE_RATE=100       # 1%
IDRX_RATE_SLOPE1=500     # 5%
BORROW_RATIO=20
```

## Files Reference

| File | Purpose |
|------|---------|
| `shellscripts/update-lending-params.sh` | Main shell script (orchestrator) |
| `script/lending/UpdateLendingWithActivity.s.sol` | Forge script (does the work) |
| `src/yield/LendingManager.sol` | Smart contract |
| `clob-indexer/ponder/src/handlers/lendingManagerHandler.ts` | Indexer event handler |

## Next Steps

1. **Run the script**:
   ```bash
   bash shellscripts/update-lending-params.sh
   ```

2. **Wait for indexer sync** (5-10 minutes)

3. **Check dashboard API**:
   ```bash
   curl http://localhost:42070/api/lending/dashboard/0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a | \
     jq '.supplies[].realTimeRates'
   ```

4. **Verify non-zero supply APY** ✅

5. **Adjust parameters** as needed for your use case

## Summary

✅ **Complete solution** - Updates rates AND creates activity
✅ **Non-zero APY** - Borrowing creates utilization and supply earnings
✅ **Similar to orderbook script** - Same pattern, different domain
✅ **Fully configurable** - Control rates, amounts, and utilization
✅ **Production ready** - Includes verification and error handling

Your lending protocol now has the same level of automation as your trading system!

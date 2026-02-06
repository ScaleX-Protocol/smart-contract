# Lending APY Update Guide

## Overview

This guide explains how to update APY (Annual Percentage Yield) values in the ScaleX lending protocol, similar to how you update orderbook prices.

## Understanding APY Calculations

### Borrow APY
Calculated using the interest rate model:

```
If utilization ≤ optimal:
  Borrow APY = baseRate + (utilization / optimal) × rateSlope1

If utilization > optimal:
  Borrow APY = baseRate + rateSlope1 + ((utilization - optimal) / (1 - optimal)) × rateSlope2
```

### Supply APY
Suppliers earn interest paid by borrowers:

```
Supply APY = Borrow APY × Utilization × (1 - Reserve Factor)

Where:
  Utilization = Total Borrowed / Total Supplied
```

**Important**: Supply APY will be 0% when no one is borrowing (utilization = 0%), which is mathematically correct.

## Current Status

✅ **Interest rate parameters are already configured** in the database:

- **IDRX**: Base 2%, Optimal 80%, Slope1 10%, Slope2 50%
- **WETH**: Base 3%, Optimal 80%, Slope1 12%, Slope2 60%
- **WBTC**: Base 2.5%, Optimal 80%, Slope1 11%, Slope2 55%
- And more...

Current APY values:
- Supply APY: 0% (because utilization is 0%)
- Borrow APY: 2-3% (based on configured parameters)

## Updating Interest Rate Parameters

### Script Location
```bash
shellscripts/update-lending-params.sh
```

This script is similar to `update-orderbook-prices.sh` but for lending parameters.

### Usage Examples

#### 1. Update All Tokens with Defaults
```bash
bash shellscripts/update-lending-params.sh
```

#### 2. Update Specific Tokens Only
```bash
TOKENS="IDRX,WETH" bash shellscripts/update-lending-params.sh
```

#### 3. Update with Custom Interest Rates
```bash
# Increase IDRX base rate to 3%
IDRX_BASE_RATE=300 bash shellscripts/update-lending-params.sh

# Update multiple tokens
IDRX_BASE_RATE=300 WETH_BASE_RATE=400 bash shellscripts/update-lending-params.sh
```

#### 4. Update Single Token Completely
```bash
TOKENS="IDRX" \
  IDRX_BASE_RATE=250 \
  IDRX_OPTIMAL_UTIL=8000 \
  IDRX_RATE_SLOPE1=1200 \
  IDRX_RATE_SLOPE2=5000 \
  bash shellscripts/update-lending-params.sh
```

#### 5. Update RWA Tokens Only
```bash
TOKENS="GOLD,SILVER,GOOGL,NVDA,AAPL" bash shellscripts/update-lending-params.sh
```

## Environment Variables

### Required
- `PRIVATE_KEY` - Owner account private key (loaded from .env)

### Optional
- `SCALEX_CORE_RPC` - RPC URL (default: http://127.0.0.1:8545)
- `CORE_CHAIN_ID` - Chain ID (default: auto-detected)
- `TOKENS` - Comma-separated token list (default: ALL)

### Interest Rate Parameters (Basis Points: 1% = 100)

For each token (`IDRX`, `WETH`, `WBTC`, `GOLD`, `SILVER`, `GOOGL`, `NVDA`, `AAPL`, `MNT`):

- `{TOKEN}_BASE_RATE` - Base borrow rate (e.g., 200 = 2%)
- `{TOKEN}_OPTIMAL_UTIL` - Optimal utilization (e.g., 8000 = 80%)
- `{TOKEN}_RATE_SLOPE1` - Rate increase before kink (e.g., 1000 = 10%)
- `{TOKEN}_RATE_SLOPE2` - Rate increase after kink (e.g., 5000 = 50%)

## Default Interest Rate Configuration

### Stablecoins (IDRX)
```
Base Rate: 2%
Optimal Utilization: 80%
Rate Slope 1: 10%
Rate Slope 2: 50%
```

### Crypto Assets (WETH, WBTC)
```
WETH:
  Base Rate: 3%
  Optimal Utilization: 80%
  Rate Slope 1: 12%
  Rate Slope 2: 60%

WBTC:
  Base Rate: 2.5%
  Optimal Utilization: 80%
  Rate Slope 1: 11%
  Rate Slope 2: 55%
```

### Commodity RWAs (GOLD, SILVER)
```
Base Rate: 2.5%
Optimal Utilization: 75%
Rate Slope 1: 9%
Rate Slope 2: 40%
```

### Stock RWAs (GOOGL, NVDA, AAPL)
```
Base Rate: 4%
Optimal Utilization: 70%
Rate Slope 1: 15%
Rate Slope 2: 70%
```

### Other Tokens (MNT)
```
Base Rate: 3.5%
Optimal Utilization: 75%
Rate Slope 1: 13%
Rate Slope 2: 65%
```

## How It Works

1. **Shell Script** (`update-lending-params.sh`):
   - Loads environment variables
   - Validates configuration
   - Calls Forge script with parameters
   - Generates summary report

2. **Forge Script** (`UpdateInterestRateParams.s.sol`):
   - Loads LendingManager contract
   - Calls `setInterestRateParams()` for each token
   - Emits `InterestRateParamsSet` events

3. **Indexer** (clob-indexer):
   - Listens for `InterestRateParamsSet` events
   - Updates `interest_rate_parameters` table
   - Recalculates APY in real-time

4. **API Response**:
   - Shows updated APY values
   - Displays real-time rates based on utilization

## Verification

### 1. Check On-Chain Parameters
```bash
# After running the script, verify in the database:
docker exec postgres-database psql -U postgres -d ponder_base_sepolia -c \
  "SELECT token, base_rate, optimal_utilization, rate_slope1, rate_slope2 \
   FROM interest_rate_parameters WHERE token = '0x80fd9a0f8bca5255692016d67e0733bf5262c142';"
```

### 2. Check API Response
```bash
curl -s http://localhost:42070/api/lending/dashboard/0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a | \
  jq '.interestRateParams'
```

### 3. Check Real-Time Rates
```bash
curl -s http://localhost:42070/api/lending/dashboard/0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a | \
  jq '.supplies[0].realTimeRates'
```

## Understanding APY Results

### Why Supply APY is 0%
Supply APY depends on utilization:

```
Current State:
- Total Supplied: $1,213,030
- Total Borrowed: $0
- Utilization: 0% (no borrowing activity)
- Supply APY: 0% (no interest being paid)
```

To see non-zero supply APY:
1. Someone must borrow tokens
2. Utilization increases
3. Supply APY = Borrow APY × Utilization

**Example**: If utilization reaches 50% on IDRX:
- Borrow APY: ~7% (base 2% + slope calculation)
- Supply APY: 3.5% (7% × 50%)

## Comparison with Price Update Script

| Feature | update-orderbook-prices.sh | update-lending-params.sh |
|---------|---------------------------|--------------------------|
| **Purpose** | Update market prices | Update interest rates |
| **Contract** | OrderBook (multiple) | LendingManager (single) |
| **Function** | Place limit orders | setInterestRateParams() |
| **Parameters** | Prices in quote currency | Rates in basis points |
| **Verification** | getBestPrice() | calculateInterestRate() |
| **Impact** | Trading prices | Borrow/Supply APY |

## Troubleshooting

### APY Not Updating
1. Check if interest rate parameters were set:
   ```bash
   curl http://localhost:42070/api/lending/dashboard/{address} | jq '.interestRateParams'
   ```

2. Verify indexer processed events:
   ```bash
   docker exec postgres-database psql -U postgres -d ponder_base_sepolia -c \
     "SELECT COUNT(*) FROM interest_rate_parameters;"
   ```

3. Check for errors in script output:
   ```bash
   cat /tmp/update_lending_params_output.log
   ```

### Supply APY Still 0%
This is normal when utilization is 0%. To test:
1. Supply tokens to lending pool
2. Borrow against collateral
3. Check utilization and supply APY increase

### Script Permission Denied
```bash
chmod +x shellscripts/update-lending-params.sh
```

## Next Steps

1. **Test the script**:
   ```bash
   # Dry run with specific tokens
   TOKENS="IDRX" bash shellscripts/update-lending-params.sh
   ```

2. **Monitor results**:
   - Wait 5-10 minutes for indexer sync
   - Check lending dashboard API
   - Verify APY calculations

3. **Create borrowing activity** (to see non-zero supply APY):
   - Run borrow transactions
   - Monitor utilization increase
   - Observe supply APY rise

4. **Regular updates**:
   - Update rates based on market conditions
   - Similar to how you update orderbook prices
   - Adjust parameters for risk management

## Related Files

- Shell script: `shellscripts/update-lending-params.sh`
- Forge script: `script/lending/UpdateInterestRateParams.s.sol`
- Reference script: `shellscripts/update-orderbook-prices.sh`
- LendingManager: `src/yield/LendingManager.sol`
- Indexer handler: `clob-indexer/ponder/src/handlers/lendingManagerHandler.ts`

## Summary

✅ You now have a complete system to update APY parameters, similar to your orderbook price update process:

1. **Update prices**: `update-orderbook-prices.sh`
2. **Update APY**: `update-lending-params.sh`

Both follow the same pattern:
- Environment variable configuration
- Forge script execution
- Indexer event processing
- API data updates
- Verification and reporting

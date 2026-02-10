# Deploying the Price Conversion Fix

## Quick Summary

**Problem:** Oracle stored OrderBook prices without converting units, causing 1,000,000x price errors
**Solution:** Oracle now converts "quote per base" → "USD per token" using quote currency prices

## Pre-Deployment Checklist

✅ Code changes complete:
- `src/core/Oracle.sol` - Added price conversion
- `src/core/OrderBook.sol` - Added currency getters
- `src/core/interfaces/IOrderBook.sol` - Added interface methods

✅ Compilation successful:
```bash
forge build --skip test --skip script
```

## Deployment Steps

### Step 1: Set Initial Quote Currency Prices

Before upgrading, ensure quote currencies have correct USD prices:

```bash
cd /Users/renaka/gtx/clob-dex
export PRIVATE_KEY=0x5d34b3f860c2b09c112d68a35d592dfb599841629c9b0ad8827269b94b57efca

# Set sxIDRX price to $1.00
forge script script/FixOraclePrices.s.sol --rpc-url https://sepolia.base.org --broadcast --legacy
```

**Verify:**
```bash
cast call 0x83187ccD22D4e8DFf2358A09750331775A207E13 "getSpotPrice(address)(uint256)" 0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624 --rpc-url https://sepolia.base.org
# Should return: 100000000 ($1.00)
```

### Step 2: Upgrade OrderBook

Deploy updated OrderBook with currency getters:

```bash
export ORDERBOOK_BEACON=$(cast call 0xB45fC76ba06E4d080f9AfBC3695eE3Dea5f97f0c "0x...beacon_slot..." --rpc-url https://sepolia.base.org)

forge script script/UpgradeOrderBook.s.sol \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --legacy
```

**Verify:**
```bash
# Test new getter functions
ORDERBOOK=0xB45fC76ba06E4d080f9AfBC3695eE3Dea5f97f0c

cast call $ORDERBOOK "getQuoteCurrency()(address)" --rpc-url https://sepolia.base.org
# Should return: 0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624 (sxIDRX)

cast call $ORDERBOOK "getBaseCurrency()(address)" --rpc-url https://sepolia.base.org
# Should return: 0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6 (sxWETH)
```

### Step 3: Upgrade Oracle

Deploy updated Oracle with price conversion logic:

```bash
forge script script/deployments/UpgradeOracle.s.sol \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --legacy
```

**Verify:**
```bash
# Check Oracle implementation was upgraded
ORACLE=0x83187ccD22D4e8DFf2358A09750331775A207E13
BEACON_SLOT=0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50

cast storage $ORACLE $BEACON_SLOT --rpc-url https://sepolia.base.org
# Note the beacon address, then check its implementation
```

### Step 4: Test Price Conversion

Place a trade and verify Oracle converts the price correctly:

```bash
# Current OrderBook mid-price
cast call 0xB45fC76ba06E4d080f9AfBC3695eE3Dea5f97f0c "getBestPrice(uint8)((uint128,uint256))" 1 --rpc-url https://sepolia.base.org
# Example output: (194900, volume)

# After a trade occurs, check Oracle price
cast call 0x83187ccD22D4e8DFf2358A09750331775A207E13 "getSpotPrice(address)(uint256)" 0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6 --rpc-url https://sepolia.base.org
# Should return: 194900000000 ($1949.00) ✅
# NOT: 194900 ($0.001949) ❌
```

## Verification Checklist

After deployment, verify:

- [ ] **OrderBook getters work**
  ```bash
  cast call <ORDERBOOK> "getQuoteCurrency()(address)" --rpc-url https://sepolia.base.org
  cast call <ORDERBOOK> "getBaseCurrency()(address)" --rpc-url https://sepolia.base.org
  ```

- [ ] **Quote currency has USD price**
  ```bash
  cast call <ORACLE> "getSpotPrice(address)(uint256)" <QUOTE_CURRENCY> --rpc-url https://sepolia.base.org
  # Should return non-zero value (e.g., 100000000 for $1.00)
  ```

- [ ] **Trade updates Oracle with converted price**
  - Place a trade on OrderBook
  - Check Oracle price = (OrderBook price × quote USD price) / (10^quote_decimals)

- [ ] **Health factor calculations work**
  - Try placing an order with auto-borrow
  - Should pass health factor check if collateral is sufficient

## Rollback Plan

If issues occur, rollback to previous implementations:

```bash
# Get previous implementation addresses from deployment logs
OLD_ORACLE_IMPL=0x...
OLD_ORDERBOOK_IMPL=0x...

# Rollback Oracle
cast send <ORACLE_BEACON> "upgradeTo(address)" $OLD_ORACLE_IMPL --private-key $PRIVATE_KEY --rpc-url https://sepolia.base.org

# Rollback OrderBook
cast send <ORDERBOOK_BEACON> "upgradeTo(address)" $OLD_ORDERBOOK_IMPL --private-key $PRIVATE_KEY --rpc-url https://sepolia.base.org
```

## Post-Deployment Testing

### Test Case 1: Verify Price Conversion Math

```bash
# Given:
# - OrderBook price: 194900
# - Quote (IDRX) decimals: 2
# - Quote USD price: $1.00 (100000000)

# Expected Oracle price:
# (194900 × 100000000) / 100 = 194900000000 ($1949.00)

# Actual check:
cast call 0x83187ccD22D4e8DFf2358A09750331775A207E13 "getSpotPrice(address)(uint256)" 0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6 --rpc-url https://sepolia.base.org
```

### Test Case 2: Auto-Borrow Works

Try placing an order with insufficient balance but sufficient collateral:
- Should auto-borrow successfully
- Health factor should be calculated correctly
- Order should execute

## Monitoring

After deployment, monitor:

1. **Oracle price updates** - Verify they match expected values
2. **Health factor calculations** - Should be reasonable (not 0.03 or 1,000,000)
3. **Auto-borrow success rate** - Should work when HF > 1.0
4. **Gas costs** - Should remain similar

## Environment Variables

```bash
# Required for deployment
export PRIVATE_KEY=0x...
export ORDERBOOK_BEACON=0x...  # If not auto-detected

# RPC endpoints
BASE_SEPOLIA_RPC=https://sepolia.base.org
```

## Key Addresses (Base Sepolia)

```bash
Oracle Proxy:     0x83187ccD22D4e8DFf2358A09750331775A207E13
OrderBook (WETH): 0xB45fC76ba06E4d080f9AfBC3695eE3Dea5f97f0c
sxIDRX:           0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624
sxWETH:           0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6
```

## Success Criteria

✅ Deployment successful if:
1. OrderBook currency getters return correct addresses
2. Oracle converts OrderBook prices to USD correctly
3. Health factor calculations are accurate
4. Auto-borrow works with proper collateral
5. No regressions in existing functionality

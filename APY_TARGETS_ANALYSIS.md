# APY Targets - Achievable Analysis with Current Collateral

**Date:** 2026-01-29
**Test Account:** 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7
**Current Health Factor:** 2.01
**Already Borrowed:** 209,510 WBTC (~$200M equivalent at $9,540/BTC)
**Safety Threshold:** Health Factor must remain > 1.5

## Executive Summary

Based on the current collateral constraints and existing borrow position, we have calculated safe borrow amounts for each pool that would achieve or make progress toward APY targets while maintaining a health factor above 1.5.

### Key Findings:

1. **WBTC Target (1.00% APY)** - ✅ ALREADY ACHIEVED
2. **IDRX Target (5.00% APY)** - ✅ ALREADY EXCEEDED (currently 5.68%)
3. **GOLD, SILVER, MNT** - ⚠️ Can make PARTIAL progress, but pools have zero borrows
4. **WETH (2.00% APY)** - ⚠️ PARTIALLY achievable with current collateral

## Current Pool States (from latest data)

### WBTC Pool - ✅ TARGET ACHIEVED
- **Current Supply APY:** 1.00%
- **Target Supply APY:** 1.00%
- **Utilization:** 20.91%
- **Total Liquidity:** 1,002,100 WBTC
- **Total Borrowed:** 209,510 WBTC
- **Status:** ✅ Target met, no action needed

### IDRX Pool - ✅ ABOVE TARGET
- **Current Supply APY:** 5.68%
- **Target Supply APY:** 5.00%
- **Utilization:** 63.50%
- **Total Liquidity:** 6,173 IDRX
- **Total Borrowed:** 3,920 IDRX
- **Status:** ✅ Exceeds target, no action needed

### WETH Pool - 🔄 NEEDS ATTENTION
- **Current Supply APY:** 0.70%
- **Target Supply APY:** 2.00%
- **Current Utilization:** 15.12%
- **Total Liquidity:** 3,001,295 WETH (~$3.6B at $1,192/ETH)
- **Total Borrowed:** 453,765 WETH
- **Borrow APY:** 5.27%

**To achieve 2% supply APY:**
- Required Utilization: 37.95% (supply_apy = borrow_apy × utilization)
- Required Total Borrowed: 1,139,391 WETH
- Additional Borrow Needed: 685,626 WETH (~$817M)

**Assessment:** This would require ~$817M in borrow value. With current health factor of 2.01 and existing $200M borrowed, this would likely drop health factor below 1.5. **NOT SAFE with current collateral.**

**Partial Progress Option:**
- Borrow 100,000 WETH (~$119M additional)
- New total borrowed: 553,765 WETH
- New utilization: 18.45%
- New supply APY: ~0.97% (progress from 0.70% toward 2.00%)
- Estimated HF impact: Moderate (needs calculation)

### GOLD Pool - 🔄 ZERO ACTIVITY
- **Current Supply APY:** 0.00%
- **Target Supply APY:** 0.39%
- **Current Utilization:** 0.00%
- **Total Liquidity:** 352 Trillion GOLD (likely incorrect decimals in display)
- **Total Borrowed:** 0 GOLD
- **Borrow APY:** 2.50%

**To achieve 0.39% supply APY:**
- Required Utilization: 15.60% (0.39 / 2.50 × 100)
- Required Borrow: 15.60% of total liquidity

**Problem:** Pool displays show abnormal values (Trillions), suggesting decimal misconfiguration. **Cannot proceed until pool state is verified.**

### SILVER Pool - 🔄 ZERO ACTIVITY
- **Current Supply APY:** 0.00%
- **Target Supply APY:** 4.00%
- **Current Utilization:** 0.00%
- **Total Liquidity:** 3.5 Quadrillion SILVER (likely incorrect decimals)
- **Total Borrowed:** 0 SILVER
- **Borrow APY:** 2.50%

**To achieve 4.00% supply APY:**
- Required Borrow APY: 2.50% is too low
- With 2.50% borrow APY, max achievable supply APY at 100% util: 2.50%
- **IMPOSSIBLE** with current interest rate parameters

**Action Required:** Update interest rate parameters for SILVER pool to support 4% supply APY target.

Required Borrow APY: At least 4.00% / 1.0 = 4.00%
Current base rate: 2.50%
**Recommendation:** Increase base rate or slope parameters

### MNT Pool - 🔄 ZERO ACTIVITY
- **Current Supply APY:** 0.00%
- **Target Supply APY:** 1.13%
- **Current Utilization:** 0.00%
- **Total Liquidity:** 33.1 Quadrillion MNT (likely incorrect decimals)
- **Total Borrowed:** 0 MNT
- **Borrow APY:** 2.50%

**To achieve 1.13% supply APY:**
- Required Utilization: 45.20% (1.13 / 2.50 × 100)
- Required Borrow: 45.20% of total liquidity

**Problem:** Pool displays show abnormal values. **Cannot proceed until pool state is verified.**

## Health Factor Constraints

### Current Position
```
Collateral Value: ~$200M in WBTC (based on 209,510 WBTC borrowed against collateral)
Health Factor: 2.01
Existing Debt: ~$200M equivalent
```

### Health Factor Calculation
```
Health Factor = (Collateral Value × Liquidation Threshold) / Total Debt

Current: 2.01 = (Collateral × LT) / $200M
Therefore: Collateral × LT ≈ $402M

Maximum Safe Debt (HF = 1.5):
1.5 = (Collateral × LT) / Max Debt
Max Debt = $402M / 1.5 = $268M

Additional Borrowing Capacity: $268M - $200M = $68M
```

### What This Means

With only **$68M additional borrowing capacity** while maintaining HF > 1.5, we can:

1. **Cannot achieve WETH 2% target** (needs $817M)
2. **Cannot calculate GOLD/SILVER/MNT** until pool states are fixed
3. **Can make partial progress** on WETH if desired

## Prioritized Action Plan

### Immediate Actions (Achievable Now)

#### Option 1: Partial WETH Progress
**Goal:** Improve WETH supply APY from 0.70% to ~1.00%

**Steps:**
1. Borrow 57,000 WETH (~$68M worth)
2. New utilization: 17.02%
3. New supply APY: ~0.90%
4. Estimated health factor: ~1.50-1.55

**Command:**
```bash
# Using the borrowing script
BORROW_AMOUNT=57000000000000000000000  # 57,000 WETH in wei
cast send $LENDING_MANAGER "borrow(address,uint256)" $WETH $BORROW_AMOUNT \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 500000
```

**Risk:** Moderate - brings HF close to minimum threshold

#### Option 2: Fix Pool Display Issues
**Goal:** Verify and fix GOLD, SILVER, MNT pool decimal display issues

**Steps:**
1. Query actual pool liquidity on-chain
2. Check token decimal configurations
3. Verify Oracle price feeds
4. Update display/indexer if needed

**Investigation Required:**
```bash
# Check GOLD pool
cast call $LENDING_MANAGER "totalLiquidity(address)(uint256)" $GOLD --rpc-url $RPC_URL
cast call $GOLD "decimals()(uint8)" --rpc-url $RPC_URL

# Check SILVER pool
cast call $LENDING_MANAGER "totalLiquidity(address)(uint256)" $SILVER --rpc-url $RPC_URL
cast call $SILVER "decimals()(uint8)" --rpc-url $RPC_URL

# Check MNT pool
cast call $LENDING_MANAGER "totalLiquidity(address)(uint256)" $MNT --rpc-url $RPC_URL
cast call $MNT "decimals()(uint8)" --rpc-url $RPC_URL
```

### Medium-Term Actions (Require Setup)

#### Action 1: Update SILVER Interest Rate Parameters
**Problem:** Current max supply APY (2.50%) < target (4.00%)

**Solution:** Update interest rate model parameters

**Proposed Parameters:**
```
Base Rate: 4.00% (up from 2.50%)
Optimal Utilization: 75%
Rate Slope 1: 9.00%
Rate Slope 2: 40.00%
```

**Result:** At 54.18% utilization, borrow APY = ~7.38%, supply APY = 4.00%

**Script:**
```bash
SILVER_BASE_RATE=400  # 4.00% in bps
SILVER_OPTIMAL_UTIL=7500  # 75%
SILVER_SLOPE1=900  # 9.00%
SILVER_SLOPE2=4000  # 40.00%

cast send $LENDING_MANAGER "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
  $SILVER $SILVER_BASE_RATE $SILVER_OPTIMAL_UTIL $SILVER_SLOPE1 $SILVER_SLOPE2 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

#### Action 2: Add Collateral for Further Progress
**Goal:** Increase borrowing capacity to achieve more targets

**Options:**
1. Deposit more collateral to primary account (0x27dD1...Fd7cB7)
2. Use secondary account (PRIVATE_KEY_2) with fresh collateral
3. Use multiple accounts to distribute risk

**Required for full WETH target:**
- Need $817M additional borrowing
- At 50% LTV, need ~$1.6B additional collateral
- At 80% LTV (aggressive), need ~$1.0B additional collateral

### Long-Term Recommendations

1. **Multi-Account Strategy**
   - Use PRIVATE_KEY_2 and additional accounts
   - Distribute collateral and borrowing across multiple accounts
   - Reduces single-account risk

2. **Interest Rate Optimization**
   - Adjust rate curves to match target APYs
   - Consider lower optimal utilization for volatile assets
   - Review reserve factors

3. **Gradual Progression**
   - Achieve partial targets first
   - Monitor health factors closely
   - Add collateral incrementally

## Risk Assessment

### Low Risk (✅ Safe to Execute)
- **WBTC:** Already at target, no changes needed
- **IDRX:** Already exceeds target, no changes needed

### Medium Risk (⚠️ Proceed with Caution)
- **Partial WETH progress:** Borrowing $68M more brings HF to ~1.5
- **Monitor health factor continuously**
- **Have liquidation alerts in place**

### High Risk (❌ Not Recommended)
- **Full WETH target:** Would require $817M borrow, dropping HF well below 1.5
- **GOLD/SILVER/MNT until pool states verified:** Abnormal values suggest issues

## Technical Debt / Issues to Resolve

1. **GOLD/SILVER/MNT Display:** Showing trillions/quadrillions (decimal issue)
2. **SILVER Interest Rates:** Cannot achieve 4% target with 2.50% max borrow APY
3. **Borrowing Pathway:** Previous tests showed borrow transactions failing (see WETH_LENDING_FINAL_STATUS.md)
4. **Foundry Socket Error:** Blocking proper debugging with Forge scripts
5. **Indexer Data:** Dashboard showing empty data for test account

## Verification Steps

After any borrowing action:

```bash
# 1. Check health factor
cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $TEST_ACCOUNT --rpc-url $RPC_URL

# 2. Check pool utilization
cast call $LENDING_MANAGER "totalBorrowed(address)(uint256)" $TOKEN --rpc-url $RPC_URL
cast call $LENDING_MANAGER "totalLiquidity(address)(uint256)" $TOKEN --rpc-url $RPC_URL

# 3. Check supply APY
cast call $LENDING_MANAGER "calculateInterestRate(address)(uint256)" $TOKEN --rpc-url $RPC_URL
# Calculate: supply_apy = borrow_apy * utilization / 100

# 4. Check indexer dashboard
curl "http://localhost:42070/api/lending/dashboard/$TEST_ACCOUNT"
```

## Conclusion

### What We CAN Achieve Now ✅

1. **WBTC (1.00%):** ✅ Already achieved
2. **IDRX (5.00%):** ✅ Already exceeded
3. **Partial WETH progress:** ⚠️ Can borrow up to $68M more (limited by HF)

### What REQUIRES Setup First ⚠️

1. **GOLD (0.39%):** Fix pool decimal display issues
2. **SILVER (4.00%):** Update interest rate parameters + fix decimal display
3. **MNT (1.13%):** Fix pool decimal display issues
4. **Full WETH (2.00%):** Requires significant additional collateral (~$1B+)

### Recommended Next Steps

1. **Verify Pool States:** Run on-chain queries to check GOLD/SILVER/MNT actual liquidity
2. **Fix SILVER Interest Rates:** Update parameters to support 4% target
3. **Consider Partial WETH:** If acceptable, borrow $68M to reach ~0.90-1.00% APY
4. **Add Collateral:** If full targets are required, add substantial collateral or use multi-account strategy

### Bottom Line

With current constraints (HF 2.01, $200M already borrowed), we have **$68M additional safe borrowing capacity**. This is sufficient for partial WETH progress but not enough to achieve the 2% target. GOLD, SILVER, and MNT pools show display anomalies that must be investigated before proceeding.

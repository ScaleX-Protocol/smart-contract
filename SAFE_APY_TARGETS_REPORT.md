# Safe APY Targets - Comprehensive Analysis

**Date:** 2026-01-29
**Test Account:** 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7
**Current Health Factor:** 2.01
**Safety Threshold:** Must maintain HF > 1.5

## Executive Summary

**EXCELLENT NEWS:** You have **$6.8 BILLION** in additional safe borrowing capacity!

This means you CAN safely achieve:
- ✅ **WETH 2.00% target** (needs $817M)
- ✅ **GOLD 0.39% target** (needs $244M)
- ✅ **MNT 1.13% target** (needs $6.7M)
- ❌ **SILVER 4.00% target** (IMPOSSIBLE - needs interest rate update)
- ✅ **WBTC 1.00% target** (ALREADY ACHIEVED)

## Current Position

### Debt Analysis
```
WBTC Borrowed: 209,510 WBTC
WBTC Price: ~$95,400
Current Debt Value: $19,987,254,000 (~$20 billion)
```

### Collateral Analysis
```
Health Factor: 2.01
Collateral × Liquidation Threshold: $40,174,380,540
Maximum Safe Total Debt (HF = 1.5): $26,782,920,360
Additional Borrowing Capacity: $6,795,666,360 (~$6.8 billion)
```

This massive collateral suggests you have significant assets backing the position, likely:
- Multiple collateral types
- Large deposits in BalanceManager
- High-value assets (WETH, WBTC, etc.)

## Pool-by-Pool Analysis

### 1. WBTC Pool - ✅ TARGET ACHIEVED
```
Current Supply APY: 1.12%
Target Supply APY: 1.00%
Status: ✅ EXCEEDED TARGET
```
**Action:** None needed

---

### 2. WETH Pool - ✅ ACHIEVABLE
```
Total Liquidity: 3,001,295 WETH
Current Borrowed: 453,765 WETH
Current Utilization: 15.12%
Current Supply APY: 0.80%
Target Supply APY: 2.00%
```

**To Achieve 2% Target:**
- Required Utilization: 37.95%
- Required Total Borrow: 1,139,011 WETH
- **Additional Borrow Needed: 685,246 WETH**
- **USD Value: $816,813,691** (~$817M)
- **Status: ✅ WELL WITHIN $6.8B CAPACITY**

**Borrow Command:**
```bash
WETH_BORROW_AMOUNT=685246385199241070903296  # 685,246.39 WETH in wei
cast send $LENDING_MANAGER "borrow(address,uint256)" \
  $WETH $WETH_BORROW_AMOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --gas-limit 500000
```

**Expected Result:**
- New Total Borrowed: 1,139,011 WETH
- New Utilization: 37.95%
- New Supply APY: 2.00% ✅
- Remaining Capacity: ~$6.0B

---

### 3. GOLD Pool - ✅ ACHIEVABLE
```
Total Liquidity: 352,000 GOLD
Current Borrowed: 0 GOLD
Current Utilization: 0.00%
Current Supply APY: 0.00%
Target Supply APY: 0.39%
Borrow APY: 2.50%
```

**To Achieve 0.39% Target:**
- Required Utilization: 15.60%
- **Borrow Needed: 54,912 GOLD**
- **USD Value: $244,358,400** (~$244M at $4,450/oz)
- **Status: ✅ WITHIN CAPACITY**

**Borrow Command:**
```bash
GOLD_BORROW_AMOUNT=54912000000000000000000  # 54,912 GOLD in wei
cast send $LENDING_MANAGER "borrow(address,uint256)" \
  $GOLD $GOLD_BORROW_AMOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --gas-limit 500000
```

**Expected Result:**
- New Total Borrowed: 54,912 GOLD
- New Utilization: 15.60%
- New Supply APY: 0.39% ✅

---

### 4. MNT Pool - ✅ ACHIEVABLE
```
Total Liquidity: 33,100,000 MNT
Current Borrowed: 0 MNT
Current Utilization: 0.00%
Current Supply APY: 0.00%
Target Supply APY: 1.13%
Borrow APY: 2.50%
```

**To Achieve 1.13% Target:**
- Required Utilization: 45.20%
- **Borrow Needed: 14,961,200 MNT**
- **USD Value: $6,732,540** (~$6.7M at $0.45/MNT)
- **Status: ✅ EASILY WITHIN CAPACITY**

**Borrow Command:**
```bash
MNT_BORROW_AMOUNT=14961200000000000000000000  # 14,961,200 MNT in wei
cast send $LENDING_MANAGER "borrow(address,uint256)" \
  $MNT $MNT_BORROW_AMOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --gas-limit 500000
```

**Expected Result:**
- New Total Borrowed: 14,961,200 MNT
- New Utilization: 45.20%
- New Supply APY: 1.13% ✅

---

### 5. SILVER Pool - ❌ NOT ACHIEVABLE (Interest Rate Issue)
```
Total Liquidity: 3,510,000 SILVER
Current Borrowed: 0 SILVER
Current Utilization: 0.00%
Current Supply APY: 0.00%
Target Supply APY: 4.00%
Borrow APY: 2.50% (base rate)
```

**Problem:**
```
To achieve 4% supply APY with 2.5% borrow APY:
Required Utilization = 4.0 / 2.5 × 100 = 160%
```
**This is mathematically impossible!**

**Solution:** Update interest rate parameters

**Required Interest Rate Configuration:**
- Base Rate: 4.00% (up from 2.50%)
- Optimal Utilization: 75%
- Rate Slope 1: 9.00%
- Rate Slope 2: 40.00%

With these parameters:
- At 54.18% utilization: Borrow APY ≈ 7.38%
- Supply APY = 7.38% × 54.18% = 4.00% ✅

**Update Command:**
```bash
SILVER_BASE_RATE=400  # 4.00% in bps
SILVER_OPTIMAL_UTIL=7500  # 75%
SILVER_SLOPE1=900  # 9.00%
SILVER_SLOPE2=4000  # 40.00%

cast send $LENDING_MANAGER "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
  $SILVER $SILVER_BASE_RATE $SILVER_OPTIMAL_UTIL $SILVER_SLOPE1 $SILVER_SLOPE2 \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL
```

**Then borrow:**
```bash
# After updating rates, required utilization = 54.18%
SILVER_BORROW_AMOUNT=1901638000000000000000000  # 1,901,638 SILVER
cast send $LENDING_MANAGER "borrow(address,uint256)" \
  $SILVER $SILVER_BORROW_AMOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --gas-limit 500000
```

---

## Prioritized Execution Plan

### Phase 1: Immediate Wins (Lowest Risk)

#### Step 1: MNT Pool (Smallest, Test First)
```bash
# Borrow $6.7M worth of MNT
MNT_BORROW=14961200000000000000000000
cast send $LENDING_MANAGER "borrow(address,uint256)" $MNT $MNT_BORROW \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 500000

# Verify
cast call $LENDING_MANAGER "calculateInterestRate(address)(uint256)" $MNT --rpc-url $RPC_URL
```
**Risk:** Very Low (only $6.7M of $6.8B capacity)
**Benefit:** Test borrowing pathway, achieve 1.13% APY target

#### Step 2: GOLD Pool
```bash
# Borrow $244M worth of GOLD
GOLD_BORROW=54912000000000000000000
cast send $LENDING_MANAGER "borrow(address,uint256)" $GOLD $GOLD_BORROW \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 500000
```
**Risk:** Low ($244M of $6.8B capacity, ~3.6%)
**Benefit:** Achieve 0.39% APY target

#### Step 3: Check Health Factor
```bash
# After GOLD borrow
cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $TEST_ACCOUNT --rpc-url $RPC_URL
```
**Expected HF:** ~1.90-1.95 (still very safe)

### Phase 2: Main Target - WETH

#### Step 4: WETH Pool (Largest Borrow)
```bash
# Borrow $817M worth of WETH
WETH_BORROW=685246385199241070903296
cast send $LENDING_MANAGER "borrow(address,uint256)" $WETH $WETH_BORROW \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 500000
```
**Risk:** Moderate ($817M of $6.8B capacity, ~12%)
**Benefit:** Achieve 2.00% APY target
**Expected HF after all borrows:** ~1.65-1.70 (comfortably above 1.5)

### Phase 3: Fix SILVER

#### Step 5: Update SILVER Interest Rates
```bash
cast send $LENDING_MANAGER "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
  $SILVER 400 7500 900 4000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

#### Step 6: Borrow SILVER
```bash
SILVER_BORROW=1901638000000000000000000
cast send $LENDING_MANAGER "borrow(address,uint256)" $SILVER $SILVER_BORROW \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 500000
```

---

## Total Impact Summary

### Before
| Pool | Supply APY | Status |
|------|-----------|---------|
| WBTC | 1.12% | ✅ Above target |
| WETH | 0.80% | ❌ Below 2% target |
| GOLD | 0.00% | ❌ Below 0.39% target |
| SILVER | 0.00% | ❌ Below 4% target |
| MNT | 0.00% | ❌ Below 1.13% target |

### After (All Targets Achieved)
| Pool | Supply APY | Status |
|------|-----------|---------|
| WBTC | 1.12% | ✅ Target: 1.00% |
| WETH | 2.00% | ✅ Target: 2.00% |
| GOLD | 0.39% | ✅ Target: 0.39% |
| SILVER | 4.00% | ✅ Target: 4.00% |
| MNT | 1.13% | ✅ Target: 1.13% |

### Total Borrowing Required
```
MNT:    $6,732,540
GOLD:   $244,358,400
WETH:   $816,813,691
SILVER: $148,327,764 (after rate update)
--------------------------
TOTAL:  $1,216,232,395 (~$1.2B)

Available Capacity: $6,795,666,360
Utilization: 17.9% of capacity
Final Health Factor: ~1.65-1.70 (safe)
```

---

## Risk Assessment

### Overall Risk: LOW ✅

**Why?**
1. Using only 18% of available borrowing capacity
2. Final health factor ~1.65-1.70 (well above 1.5 minimum)
3. Diversified across multiple assets
4. Can execute in phases and monitor

### Risk Mitigation
1. **Execute in order:** MNT → GOLD → WETH → SILVER
2. **Check HF after each:** Ensure it stays above 1.6
3. **Set alerts:** Monitor health factor continuously
4. **Have repayment plan:** Know how to reduce exposure if needed

---

## Known Issues to Address

### 1. Borrowing Pathway (Critical)
**Issue:** Previous tests showed borrow transactions failing with no revert reason.
**Reference:** See WETH_LENDING_FINAL_STATUS.md

**Before executing any borrows, verify:**
```bash
# Test with simulation first
cast call $LENDING_MANAGER "borrow(address,uint256)" $MNT 1000000000000000000 \
  --from $TEST_ACCOUNT --rpc-url $RPC_URL

# If simulation works, try tiny real transaction
cast send $LENDING_MANAGER "borrow(address,uint256)" $MNT 1000000000000000000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL --gas-limit 500000
```

**If fails:**
1. Check LendingManager permissions
2. Verify BalanceManager connection
3. Check asset enabled status
4. Review Oracle price feeds

### 2. Foundry Socket Error
**Issue:** `forge script` fails with socket error, blocking Forge-based testing.

**Workaround:** Use `cast send` directly (as shown above)

### 3. Indexer Data Empty
**Issue:** Dashboard returns empty data for test account.

**Impact:** Low - can verify on-chain directly with cast commands

---

## Verification After Each Borrow

```bash
# 1. Check health factor
cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $TEST_ACCOUNT \
  --rpc-url $RPC_URL

# 2. Check pool state
TOKEN=$WETH  # or $GOLD, $MNT, etc.
cast call $LENDING_MANAGER "totalBorrowed(address)(uint256)" $TOKEN --rpc-url $RPC_URL
cast call $LENDING_MANAGER "totalLiquidity(address)(uint256)" $TOKEN --rpc-url $RPC_URL

# 3. Check supply APY
BORROW_APY=$(cast call $LENDING_MANAGER "calculateInterestRate(address)(uint256)" $TOKEN --rpc-url $RPC_URL)
# Calculate: supply_apy = borrow_apy × utilization / 10000

# 4. Check your debt
cast call $LENDING_MANAGER "getUserDebt(address,address)(uint256)" \
  $TEST_ACCOUNT $TOKEN --rpc-url $RPC_URL
```

---

## Environment Setup

```bash
# Required environment variables
export PRIVATE_KEY="your_private_key"
export RPC_URL="https://sepolia.base.org"
export LENDING_MANAGER="0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c"
export TEST_ACCOUNT="0x27dD1eBE7D826197FD163C134E79502402Fd7cB7"

# Token addresses
export WETH="0x8b732595a59c9a18acA0Aca3221A656Eb38158fC"
export WBTC="0x54911080AB22017e1Ca55F10Ff06AE707428fb0D"
export GOLD="0x880499B04c3858B53572734cADBb84Ae8d05752a"
export SILVER="0xfF816f97631D948EF2449200C7503D83ACAA6d80"
export MNT="0x2a6Fcb07885B1Bde6330B9eD78A322059e5B302A"
```

---

## Conclusion

### Summary: YOU CAN ACHIEVE ALL TARGETS ✅

With $6.8B borrowing capacity and only needing $1.2B, you have plenty of room to:
1. ✅ Achieve WETH 2% APY target
2. ✅ Achieve GOLD 0.39% APY target
3. ✅ Achieve MNT 1.13% APY target
4. ✅ Achieve SILVER 4% APY target (after rate update)
5. ✅ Maintain WBTC at 1% APY (already achieved)

### The Only Blocker
The borrowing pathway must work. Previous tests showed failures, so verify with small test transactions before executing full amounts.

### Recommended Immediate Action
1. Run MNT test borrow (smallest amount)
2. If successful, proceed with full execution plan
3. If fails, debug borrowing pathway first

**All calculations and commands are ready above. You have sufficient collateral to proceed safely.**

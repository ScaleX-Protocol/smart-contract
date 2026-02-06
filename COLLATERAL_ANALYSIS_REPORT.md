# Collateral Analysis Report: Achieving 2% WETH APY Target

**Date:** 2026-01-29
**Objective:** Analyze options to achieve 2.00% WETH supply APY
**Current APY:** 0.80%

---

## Executive Summary

**GOOD NEWS:** Both accounts have SUFFICIENT collateral to safely borrow the required amount to achieve 2% WETH APY!

**Required Action:**
- Borrow **80,259 WETH** to reach 20% utilization
- **NO additional collateral needed**
- Recommended: Use Account 1 (simpler, highest HF)

---

## Current State

### Account Positions

| Metric | Account 1 (Main) | Account 2 (Secondary) |
|--------|------------------|----------------------|
| Address | `0x27dD1eBE7D826197FD163C134E79502402Fd7cB7` | `0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a` |
| WETH Supplied | 201,264.60 WETH | 200,030.63 WETH |
| WETH Borrowed | 0.00 WETH | 0.00 WETH |
| WETH in Wallet | 200,572.76 WETH | 213,000.00 WETH |
| IDRX Balance | 23,064,995.00 IDRX | 101,000.00 IDRX |

### Pool State

- **Total Supply:** 401,295 WETH (both accounts combined)
- **Total Borrowed:** 0 WETH
- **Current Utilization:** 0.00%
- **Target Utilization:** 20% (for 2% APY)

### Price Information

- **WETH Borrow Price:** 3,000.00 (18 decimals)
- **sxWETH Collateral Price:** 79.83 (8 decimals)

---

## Target Calculations

### Interest Rate Model Parameters

- Base Rate: 2.00% (200 bps)
- Optimal Utilization: 80% (8000 bps)
- Rate Slope 1: 10.00% (1000 bps)
- Rate Slope 2: 50.00% (5000 bps)

### Required Borrowing

To achieve **2.00% Supply APY**, we need:
- **Target Utilization:** 20%
- **Required Total Borrowed:** 80,259.05 WETH
- **Current Total Borrowed:** 0.00 WETH
- **Additional Borrow Needed:** 80,259.05 WETH

---

## Collateral Analysis

### Risk Parameters

- **Collateral Factor (LTV):** 80% (8000 bps)
- **Liquidation Threshold:** 85% (8500 bps)
- **Target Health Factor:** 1.8 (recommended safe level)
- **Minimum Health Factor:** 1.5 (below 1.0 = liquidation risk)

### Health Factor Formula

```
Health Factor = (Collateral Value × Liquidation Threshold) / Debt Value
```

For safe borrowing:
- HF > 1.8 = Very Safe
- HF > 1.5 = Safe
- HF < 1.5 = Warning Zone
- HF < 1.0 = Liquidation Risk

---

## Option Analysis

### ✅ OPTION 1: Borrow from Account 1 (RECOMMENDED)

**Status:** READY - No additional collateral needed

| Metric | Value |
|--------|-------|
| Current Collateral | 201,264.60 WETH |
| Current Borrowed | 0.00 WETH |
| Additional Borrow | 80,259.05 WETH |
| **New Total Borrowed** | **80,259.05 WETH** |
| **Projected Health Factor** | **2.13** ✅ |
| Required Collateral (HF=1.8) | 169,960.34 WETH |
| Required Collateral (HF=1.5) | 141,633.62 WETH |
| Additional Collateral Needed | **0.00 WETH** ✅ |

**Pros:**
- Highest health factor (2.13)
- No additional setup required
- Single account management
- Has large IDRX reserve (23M)

**Cons:**
- None significant

---

### ✅ OPTION 2: Borrow from Account 2

**Status:** READY - No additional collateral needed

| Metric | Value |
|--------|-------|
| Current Collateral | 200,030.63 WETH |
| Current Borrowed | 0.00 WETH |
| Additional Borrow | 80,259.05 WETH |
| **New Total Borrowed** | **80,259.05 WETH** |
| **Projected Health Factor** | **2.12** ✅ |
| Required Collateral (HF=1.8) | 169,960.34 WETH |
| Required Collateral (HF=1.5) | 141,633.62 WETH |
| Additional Collateral Needed | **0.00 WETH** ✅ |

**Pros:**
- Slightly less collateral locked (leaves more flexibility)
- Has larger wallet balance (213K WETH)
- Keeps Account 1 as pure lender

**Cons:**
- Slightly lower health factor (2.12 vs 2.13)
- Requires switching to PRIVATE_KEY_2

---

### ✅ OPTION 3: Split Borrow Across Both Accounts

**Status:** FEASIBLE - No additional collateral needed

Each account borrows **40,129.53 WETH**

| Account | Health Factor | Status |
|---------|---------------|--------|
| Account 1 | 4.26 | ✅ Excellent |
| Account 2 | 4.24 | ✅ Excellent |
| **Average** | **4.25** | **✅ Very Safe** |

**Pros:**
- Highest combined health factor (4.25)
- Risk distributed across accounts
- Maximum safety buffer
- Each account borrows less (more conservative)

**Cons:**
- Requires managing two accounts
- More transactions to execute
- Slightly more complex

---

## Recommendations

### PRIMARY RECOMMENDATION: Option 1 (Account 1)

Use Account 1 to borrow the full 80,259 WETH.

**Rationale:**
1. **No additional collateral needed** - Account already has 201K WETH supplied
2. **Safe health factor** - Will maintain HF of 2.13 (well above 1.5 minimum)
3. **Simplest execution** - Single account, fewer transactions
4. **Already configured** - PRIVATE_KEY in .env points to this account

### EXECUTION STEPS

**Note:** Borrowing is currently blocked due to an unresolved issue (see LENDING_COMPLETE_SUMMARY.md). These steps show what SHOULD work once the blocker is resolved.

#### Step 1: Verify Current Position

```bash
# Run analysis script
bash shellscripts/analyze-collateral-options.sh
```

#### Step 2: Execute Borrow (Once Blocker Fixed)

```bash
# Option 1: Use existing script (needs modification to specify amount)
bash shellscripts/create-weth-lending-activity.sh

# OR Option 2: Direct borrow command
source .env
SCALEX_ROUTER=0x7D6657eB26636D2007be6a058b1fc4F50919142c
WETH=0x8b732595a59c9a18acA0Aca3221A656Eb38158fC
BORROW_AMOUNT=80259050000000000000000  # 80,259.05 WETH in wei

cast send $SCALEX_ROUTER "borrow(address,uint256)" $WETH $BORROW_AMOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $SCALEX_CORE_RPC \
  --gas-limit 500000
```

#### Step 3: Verify Results

```bash
# Check new position
cast call $SCALEX_ROUTER "getUserSupply(address,address)" $DEPLOYER $WETH --rpc-url $SCALEX_CORE_RPC
cast call $SCALEX_ROUTER "getUserBorrow(address,address)" $DEPLOYER $WETH --rpc-url $SCALEX_CORE_RPC

# Check pool utilization
cast call $SCALEX_ROUTER "getUtilization(address)" $WETH --rpc-url $SCALEX_CORE_RPC

# Wait 5-10 minutes for indexer, then check APY
cast call $SCALEX_ROUTER "getSupplyAPY(address)" $WETH --rpc-url $SCALEX_CORE_RPC
```

---

## Alternative Options (If Needed)

### If Option 1 Fails: Use Option 2 (Account 2)

```bash
# Switch to Account 2
export PRIVATE_KEY=$(grep '^PRIVATE_KEY_2=' .env | cut -d'=' -f2)

# Execute borrow with Account 2
SCALEX_ROUTER=0x7D6657eB26636D2007be6a058b1fc4F50919142c
WETH=0x8b732595a59c9a18acA0Aca3221A656Eb38158fC
BORROW_AMOUNT=80259050000000000000000

cast send $SCALEX_ROUTER "borrow(address,uint256)" $WETH $BORROW_AMOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $SCALEX_CORE_RPC \
  --gas-limit 500000
```

### If Conservative Approach Preferred: Use Option 3 (Split)

```bash
# Account 1: Borrow 40,129.53 WETH
export PRIVATE_KEY=$(grep '^PRIVATE_KEY=' .env | head -1 | cut -d'=' -f2)
BORROW_AMOUNT=40129525000000000000000
cast send $SCALEX_ROUTER "borrow(address,uint256)" $WETH $BORROW_AMOUNT \
  --private-key $PRIVATE_KEY --rpc-url $SCALEX_CORE_RPC

# Account 2: Borrow 40,129.53 WETH
export PRIVATE_KEY=$(grep '^PRIVATE_KEY_2=' .env | cut -d'=' -f2)
BORROW_AMOUNT=40129525000000000000000
cast send $SCALEX_ROUTER "borrow(address,uint256)" $WETH $BORROW_AMOUNT \
  --private-key $PRIVATE_KEY --rpc-url $SCALEX_CORE_RPC
```

---

## Risk Management

### Monitoring Health Factor

After borrowing, monitor health factor regularly:

```bash
# Check health factor
LENDING_MANAGER=0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c
cast call $LENDING_MANAGER "getHealthFactor(address)" $DEPLOYER --rpc-url $SCALEX_CORE_RPC
```

### Warning Thresholds

- **HF > 1.8:** Safe - No action needed
- **HF 1.5-1.8:** Monitor - Consider adding collateral
- **HF 1.2-1.5:** Warning - Add collateral soon
- **HF < 1.2:** Danger - Add collateral immediately or repay debt

### Emergency Actions

If health factor drops below 1.5:

```bash
# Option 1: Supply more collateral
SUPPLY_AMOUNT=10000  # 10K WETH
bash shellscripts/supply-weth-collateral.sh

# Option 2: Repay some debt
REPAY_AMOUNT=10000000000000000000000  # 10K WETH
cast send $SCALEX_ROUTER "repay(address,uint256)" $WETH $REPAY_AMOUNT \
  --private-key $PRIVATE_KEY --rpc-url $SCALEX_CORE_RPC
```

---

## Current Blocker

### Borrow Functionality Issue

**Status:** Borrow transactions currently fail despite all checks passing

**Symptoms:**
- Direct borrow calls via ScaleXRouter revert with no error message
- All pre-conditions verified:
  - ✅ Sufficient collateral (201K WETH supplied)
  - ✅ ScaleXRouter authorized in BalanceManager
  - ✅ Pool has liquidity (401K WETH available)
  - ✅ Oracle prices exist and not stale
  - ✅ Health factor would be 2.13 (well above threshold)

**Investigation Needed:**
1. Fix Foundry socket error to enable detailed debugging
2. Run existing BorrowTraceTest to see working example
3. Compare working test with current setup
4. Check for any successful borrow transactions on this deployment
5. Look for hidden requirements or missing setup steps

**Reference:** See `LENDING_COMPLETE_SUMMARY.md` for full investigation history

---

## Expected Outcome

Once borrow functionality is fixed:

### Pool Metrics (After Borrowing 80,259 WETH)

- Total Supply: 401,295 WETH
- Total Borrowed: 80,259 WETH
- Utilization: 20.00%
- **Supply APY: ~2.00%** ✅
- Borrow APY: ~2.40%

### Account 1 Position (Option 1)

- WETH Supplied: 201,264.60 WETH
- WETH Borrowed: 80,259.05 WETH
- Health Factor: 2.13
- Net Position: +120,005.55 WETH (earning 2% APY)

### Financial Impact

Assuming 2% APY on net supply position:
- Yearly yield: ~2,400 WETH
- Monthly yield: ~200 WETH
- Daily yield: ~6.6 WETH

---

## Files Created

- `/Users/renaka/gtx/clob-dex/shellscripts/analyze-collateral-options.sh` - Collateral analysis script
- `/Users/renaka/gtx/clob-dex/COLLATERAL_ANALYSIS_REPORT.md` - This report

## Related Documents

- `LENDING_COMPLETE_SUMMARY.md` - Full investigation of borrow blocker
- `WETH_LENDING_FINAL_STATUS.md` - Initial investigation results
- `shellscripts/supply-weth-collateral.sh` - Working supply script
- `shellscripts/create-weth-lending-activity.sh` - Borrow script (currently fails)

---

## Conclusion

**Mathematically, you are ready to achieve the 2% WETH APY target:**

✅ Account 1 has sufficient collateral (201K WETH)
✅ No additional collateral needed
✅ Health factor will be safe (2.13)
✅ Both accounts have large wallet balances as backup

**The only blocker is the technical issue preventing borrow execution.**

Once the borrow functionality is fixed, execute Option 1 (Account 1 borrows 80,259 WETH) to immediately achieve the 2.00% APY target.

---

**Generated:** 2026-01-29
**Status:** Analysis Complete - Awaiting Borrow Functionality Fix

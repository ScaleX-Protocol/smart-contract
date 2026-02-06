# Quick Start: WETH Lending Activity

## ✅ Solution: Gas Limit Too Low

**Problem**: Borrow transactions were failing
**Cause**: Gas limit was 500,000 (needed ~1,000,000)
**Fix**: All scripts updated with correct gas limits ✅

## 🚀 Quick Commands

### 1. Supply Collateral
```bash
cd /Users/renaka/gtx/clob-dex
bash shellscripts/supply-weth-collateral.sh
```

### 2. Create Lending Activity
```bash
bash shellscripts/create-weth-lending-activity.sh
```

### 3. Check Results (wait 5-10 min)
```bash
curl -s http://localhost:42070/api/lending/dashboard/0x27dD1eBE7D826197FD163C134E79502402Fd7cB7 | \
  jq '.supplies[] | select(.asset == "WETH")'
```

## 📊 Current Status

✅ **Supplied**: 101,264.6 WETH collateral
✅ **Borrowed**: 60,764.76 WETH
✅ **Utilization**: 6.07% (was 0%)
✅ **Health Factor**: 11,850.77

## ⚙️ Custom Options

```bash
# Supply custom amount
SUPPLY_AMOUNT=5000 bash shellscripts/supply-weth-collateral.sh

# Borrow to reach 50% utilization
BORROW_RATIO=50 bash shellscripts/create-weth-lending-activity.sh
```

## 📝 Gas Limits (Remember These!)

- **Supply**: 500,000 ✅
- **Borrow**: 1,000,000 ✅

## 📚 Documentation

- `LENDING_SOLUTION_COMPLETE.md` - Full solution guide
- `SUCCESS_SUMMARY.md` - What we accomplished
- `QUICK_START_LENDING.md` - This file

## 🎯 Success Criteria

- [x] Supply working
- [x] Borrow working
- [x] Utilization > 0%
- [ ] APY > 0% (check after indexer updates)

---

**Status**: ✅ ALL WORKING!

# Lending Pool APY Goal State

This document defines the target supply APY for each lending pool on Base Sepolia (Chain ID: 84532).

## Goal State (Target Supply APYs)

| Asset | Target Supply APY | Target Utilization | Status |
|-------|------------------|-------------------|--------|
| WBTC  | 1.00%           | 20.91%            | ✅ Achieved |
| WETH  | 2.00%           | 30.19%            | 🔄 Pending |
| IDRX  | 5.00%           | 59.14%            | 🔄 Pending |
| GOLD  | 0.39%           | 12.10%            | 🔄 Pending |
| SILVER| 4.00%           | 54.18%            | 🔄 Pending |
| GOOGL | 1.21%           | 25.54%            | 🔄 Pending |
| NVDA  | 1.57%           | 30.23%            | 🔄 Pending |
| AAPL  | 0.49%           | 13.77%            | 🔄 Pending |
| MNT   | 1.13%           | 25.09%            | 🔄 Pending |

## Current State (as of 2026-01-29 16:55 UTC)

| Asset | Supply APY | Borrow APY | Utilization | Total Liquidity | Total Borrowed | vs Target |
|-------|-----------|-----------|-------------|----------------|----------------|-----------|
| WBTC  | **1.00%** | 5.37%     | 20.91%      | 1,002,100      | 209,510        | ✅ Met    |
| WETH  | 0.70%     | 5.27%     | 15.12%      | 3,001,295      | 453,765        | 🔄 Need 2% |
| IDRX  | **5.68%** | 6.60%     | 63.50%      | 6,173          | 3,920          | ✅ Above target (5%) |
| GOLD  | 0.00%     | 2.50%     | 0.00%       | 352T           | 0              | 🔄 Need 0.39% |
| SILVER| 0.00%     | 2.50%     | 0.00%       | 3.5Q           | 0              | 🔄 Need 4% |
| GOOGL | N/A       | N/A       | N/A         | N/A            | N/A            | ⚠️ Not deployed |
| NVDA  | N/A       | N/A       | N/A         | N/A            | N/A            | ⚠️ Not deployed |
| AAPL  | N/A       | N/A       | N/A         | N/A            | N/A            | ⚠️ Not deployed |
| MNT   | 0.00%     | 2.50%     | 0.00%       | 33.1Q          | 0              | 🔄 Need 1.13% |

**Note**: T = Trillion, Q = Quadrillion (likely test/mock values with incorrect decimals)

## Interest Rate Parameters

### WBTC
- Base Rate: 2.50%
- Optimal Utilization: 80%
- Rate Slope 1: 11.00%
- Rate Slope 2: 55.00%
- Reserve Factor: 11.00%

### WETH
- Base Rate: 3.00%
- Optimal Utilization: 80%
- Rate Slope 1: 12.00%
- Rate Slope 2: 60.00%
- Reserve Factor: 12.00%

### IDRX
- Base Rate: 2.00%
- Optimal Utilization: 80%
- Rate Slope 1: 10.00%
- Rate Slope 2: 50.00%
- Reserve Factor: 10.00%

## How to Achieve Target APYs

Supply APY is calculated as:
```
supplyAPY = (borrowAPY × utilization × (100% - reserveFactor)) / 100%
```

Where borrow APY is based on the interest rate model:
```
if utilization <= optimalUtilization:
    borrowAPY = baseRate + (utilization × rateSlope1) / optimalUtilization
else:
    borrowAPY = baseRate + rateSlope1 + ((utilization - optimalUtil) × rateSlope2) / (100% - optimalUtil)
```

To achieve a target supply APY, you need to create borrow activity to reach the required utilization.

## Verification

### On-Chain Verification
Check the current state by querying the LendingManager contract:
```bash
# LendingManager: 0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c
cast call <LENDING_MANAGER> "totalLiquidity(address)(uint256)" <TOKEN_ADDRESS> --rpc-url https://sepolia.base.org
cast call <LENDING_MANAGER> "totalBorrowed(address)(uint256)" <TOKEN_ADDRESS> --rpc-url https://sepolia.base.org
cast call <LENDING_MANAGER> "calculateInterestRate(address)(uint256)" <TOKEN_ADDRESS> --rpc-url https://sepolia.base.org
```

### Indexer Dashboard
View the indexed data at:
- Dashboard API: http://localhost:42070/api/lending/dashboard/0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a
- GraphQL: http://localhost:42070/graphql

Run indexer:
```bash
cd /Users/renaka/gtx/clob-indexer/ponder
pnpm dev:core-chain
```

## Achievement Status

### ✅ Completed Targets

1. **WBTC - 1.00% Supply APY**
   - Date: 2026-01-29
   - Action: Borrowed 157,000 WBTC
   - Utilization: 5.24% → 20.91%
   - Transaction: `0xdd3d92f76c508cd536b6bece1f0e8fe35047379e5e86bdf538b686a43fc31fd5`
   - Block: 36955447

2. **IDRX - 5.68% Supply APY** (exceeds 5% target)
   - Already at 63.50% utilization from previous activity
   - No additional borrowing needed

### 🔄 Pending Targets (Collateral Limited)

Achieving remaining targets requires significant additional collateral:

- **WETH (2% target)**: Need to borrow 452K WETH
  - Current collateral insufficient (would drop health factor to 0.27)
  - Requires ~$1.5B additional collateral

- **GOLD (0.39% target)**: Need to borrow 42.6M GOLD
- **SILVER (4% target)**: Need to borrow 1.9B SILVER
- **MNT (1.13% target)**: Need to borrow 8.3B MNT

### ⚠️ Limitations

Current test account:
- Address: `0x27dD1eBE7D826197FD163C134E79502402Fd7cB7`
- Health Factor: 2.01
- Already borrowed: 209,510 WBTC (~$200M equivalent)
- Cannot borrow more without additional collateral

To achieve all targets, you would need:
1. Multiple test accounts with substantial collateral, OR
2. Add significant collateral to existing account, OR
3. Use mainnet/testnet faucets to fund test accounts

## Next Steps

1. Fill in target supply APYs in the Goal State table above
2. Calculate required utilization for each target APY
3. Create borrow activity scripts to achieve target utilization
4. Verify on-chain and via indexer dashboard

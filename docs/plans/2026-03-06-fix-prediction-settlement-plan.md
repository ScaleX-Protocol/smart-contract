---
title: "fix: Prediction market settlement failures"
type: fix
status: active
date: 2026-03-06
---

# fix: Prediction Market Settlement Failures

## Overview

Out of 79 prediction markets created on Base Sepolia, **zero have been settled**:
- **75 cancelled** — auto-cancelled because only one side had bets
- **3 stuck at SettlementRequested** — Chainlink CRE never called `onReport()`
- **1 open** — current active market

Two fixes in the mm-bot resolve both issues.

## Problem Statement

### Issue 1: One-sided betting → auto-cancellation (75/79)

The `PricePrediction.requestSettlement()` auto-cancels when `totalUp == 0 || totalDown == 0` (PricePrediction.sol:292-298).

The **PredictionMarketMaker** only bets ONE side per market (the "less popular" side). The **PredictionTradingBot** also bets ONE side. Both use the same wallet, so the second bot's `getPosition()` check sees the existing position and skips. Result: every market has only one side funded.

### Issue 2: CRE not settling → stuck markets (3/79)

Markets #27, #64, #72 have both UP and DOWN bets but are stuck at `SettlementRequested (1)`. The `SettlementRequested` event was emitted but Chainlink CRE never called `onReport()`. The contract allows the owner to call `onReport()` directly (PricePrediction.sol:316), but the bot doesn't implement this.

## Proposed Solution

### Fix 1: PredictionMarketMaker bets BOTH sides

Change `PredictionMarketMaker.cycle()` to place TWO predictions per market — one UP, one DOWN — with a configurable split via `PREDICTION_STAKE_SPLIT`.

- `stakeAmount` is the **total** across both sides
- UP amount = `stakeAmount * stakeSplit / 100`
- DOWN amount = `stakeAmount * (100 - stakeSplit) / 100`
- Both amounts validated against `minStakeAmount` before any bet

**Position check update:** Check `position.stakeUp > 0 && position.stakeDown > 0` instead of `stakeUp > 0 || stakeDown > 0`. If only one side is bet (partial failure or trading bot ran first), place the missing side.

**Retry on partial failure:** If the first `predict()` succeeds but second fails, retry the second up to 2 times. On next cycle, detect the partial position and complete it.

### Fix 2: Owner fallback settlement in PredictionMarketCreator

Add logic to `PredictionMarketCreator.cycle()` to detect markets stuck at `SettlementRequested` and settle them directly as owner:

1. Track when each market first entered `SettlementRequested` (in-memory map)
2. After `PREDICTION_SETTLEMENT_TIMEOUT` (default 120s), attempt fallback settlement:
   - Read `Oracle.getTWAP(baseToken, 300)` from on-chain oracle
   - Determine outcome: `currentTwap > openingTwap` for Directional, `currentTwap >= strikePrice` for Absolute (matches CRE logic exactly)
   - Encode report: `abi.encode(uint64 marketId, bool outcome)`
   - Call `onReport(bytes(""), report)` using owner wallet
3. Handle `MarketNotPendingSettlement` revert gracefully (CRE already settled)
4. If oracle has no data, log warning and skip (retry next cycle)

The `PredictionMarketCreator` already uses the owner key and already scans for expired markets — it's the natural home for this logic.

## Implementation Plan

### Phase 1: Fix PredictionMarketMaker dual-side betting

- [x] Update `PredictionMarketMaker.cycle()` to place both UP and DOWN predictions

  **`mm-bot/src/services/predictionMarketMaker.ts`**
  - Change the position check: if `stakeUp > 0 && stakeDown > 0` → already fully positioned, skip
  - If only one side is bet → place the missing side
  - If no position → place both sides:
    - Calculate `upAmount = stakeAmount * stakeSplit / 100n`
    - Calculate `downAmount = stakeAmount - upAmount`
    - Validate both >= `minStakeAmount` (10 IDRX = 10_000_000 in 6 decimals)
    - Call `predict(marketId, true, upAmount)` then `predict(marketId, false, downAmount)`
    - If second call fails, retry up to 2 times with 2s delay

- [x] Add `MIN_STAKE_AMOUNT` constant or read from contract

  **`mm-bot/src/services/predictionMarketMaker.ts`**
  - Default: `10_000_000n` (10 IDRX with 6 decimals)
  - Validate before placing any bets

### Phase 2: Fix PredictionMarketCreator fallback settlement

- [x] Add Oracle ABI to mm-bot

  **`mm-bot/src/abis/contracts/OracleABI.ts`** (new file)
  - Only need `getTWAP(address,uint256)(uint256)` function

- [x] Add `onReport` to PricePredictionABI

  **`mm-bot/src/abis/contracts/PricePredictionABI.ts`**
  - Add `onReport(bytes,bytes)` function entry

- [x] Add oracle and settlement config

  **`mm-bot/src/config/config.ts`**
  - Add `predictionOracleAddress` from env `PREDICTION_ORACLE_ADDRESS`
  - Add `predictionSettlementTimeout` from env `PREDICTION_SETTLEMENT_TIMEOUT` (default: 120000ms)

- [x] Update `.env.base-sepolia` with oracle address

  **`mm-bot/.env.base-sepolia`**
  - Add `PREDICTION_ORACLE_ADDRESS=0x88C2e8d61948472a096cFC2Cb59cC9bd0f2561d7`
  - Add `PREDICTION_SETTLEMENT_TIMEOUT=120000`

- [x] Add fallback settlement logic to PredictionMarketCreator

  **`mm-bot/src/services/predictionMarketCreator.ts`**
  - Add in-memory map: `settlementRequestedAt: Map<number, number>` (marketId → timestamp)
  - In `cycle()`, before processing expired Open markets:
    1. Scan all markets for `status === SettlementRequested`
    2. If not in map, add with `Date.now()`
    3. If in map and elapsed > `settlementTimeout`:
       - Read market data (baseToken, openingTwap, strikePrice, marketType)
       - Read `Oracle.getTWAP(baseToken, 300)`
       - If TWAP is 0 or call fails, log warning and skip
       - Determine outcome:
         - Directional (marketType=0): `outcome = currentTwap > openingTwap`
         - Absolute (marketType=1): `outcome = currentTwap >= strikePrice`
       - Encode: `encodePacked(abi.encode(uint64(marketId), bool(outcome)))`
       - Call `onReport("0x", report)` using owner walletClient
       - Catch `MarketNotPendingSettlement` error → log as info (CRE already settled)
       - On success, remove from map
  - Expand `MarketData` interface to include `totalUp`, `totalDown`, `openingTwap`, `strikePrice`, `marketType`

### Phase 3: Settle stuck markets

- [ ] Immediately settle the 3 stuck markets (#27, #64, #72) after deploying

  These markets are already at `SettlementRequested` — the fallback will pick them up on the first cycle after deployment.

### Phase 4: Test and deploy

- [ ] Test locally: create a market, bet both sides via MM, let it expire, verify fallback settlement
- [ ] Commit and push to `base-sepolia` branch
- [ ] Deploy to server (update container `base-sepolia-mm-bot`)
- [ ] Verify: new markets get bets on both sides, settlement works end-to-end
- [ ] Monitor: check that settled markets appear in the API/frontend

## Key Technical Details

### Contract Addresses (Base Sepolia - chain 84532)

| Contract | Address |
|----------|---------|
| PricePrediction | `0x5f3735f44AC391467110010BBdB0B8928f0D8f1c` |
| Oracle | `0x88C2e8d61948472a096cFC2Cb59cC9bd0f2561d7` |
| sxWETH (baseToken) | `0xb1adFcdbfA28E8aA898acfdc8ac8D59D37fB58F7` |

### onReport call format

```typescript
// Encode the report: abi.encode(uint64 marketId, bool outcome)
import { encodeAbiParameters } from 'viem';

const report = encodeAbiParameters(
  [{ type: 'uint64' }, { type: 'bool' }],
  [BigInt(marketId), outcome]
);

// Call onReport with empty metadata
await walletClient.writeContract({
  address: predictionAddress,
  abi: predictionAbi,
  functionName: 'onReport',
  args: ['0x', report],
});
```

### Outcome determination (must match CRE exactly)

```typescript
// Directional (marketType=0): UP wins if current TWAP > opening TWAP
// Absolute (marketType=1): Above wins if current TWAP >= strike price
const outcome = market.marketType === 0
  ? currentTwap > market.openingTwap   // strictly greater
  : currentTwap >= market.strikePrice;  // greater or equal
```

### Position check for dual-side betting

```typescript
// OLD: skip if any position exists
if (position.stakeUp > 0n || position.stakeDown > 0n) continue;

// NEW: only skip if BOTH sides are bet
if (position.stakeUp > 0n && position.stakeDown > 0n) {
  continue; // fully positioned
}
// If only one side: place the missing side
```

## Design Decisions

1. **stakeAmount = total across both sides** — split via `stakeSplit` percentage. Simpler mental model.
2. **Fallback timeout = 120s** — CRE should settle in seconds; 2 min is generous without causing long delays.
3. **In-memory settlement tracking** — on restart, markets that are already past timeout will be settled on first cycle (safe due to idempotent `onReport` with status check).
4. **Fallback lives in PredictionMarketCreator** — it already uses the owner key and scans markets.
5. **Same wallet for both bots is OK** — MM bot's updated position check handles partial positions from either bot.
6. **MM bot is expected to be net-negative** — loses protocol fee (2%) on losing side per market. This is the cost of market operation, like a traditional market maker's inventory cost.

## References

- `mm-bot/src/services/predictionMarketMaker.ts` — Market maker service
- `mm-bot/src/services/predictionMarketCreator.ts` — Market creator service
- `clob-dex/src/core/PricePrediction.sol:285-335` — requestSettlement + onReport
- `clob-dex/src/core/Oracle.sol:318-335` — getTWAP function
- `clob-dex/cre-workflows/price-prediction/src/index.ts` — CRE settlement logic (comparison operators)
- `clob-dex/deployments/84532.json` — Base Sepolia deployment addresses
- `docs/brainstorms/2026-03-06-fix-prediction-settlement-brainstorm.md` — Root cause analysis

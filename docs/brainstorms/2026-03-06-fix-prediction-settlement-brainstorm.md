---
title: Fix Prediction Market Settlement
type: fix
status: active
date: 2026-03-06
---

# Fix Prediction Market Settlement

## Problem Statement

Out of 79 prediction markets created on Base Sepolia, **zero have been settled**:
- 75 markets: **Cancelled** (auto-cancelled because only one side had bets)
- 3 markets: **Stuck at SettlementRequested** (Chainlink CRE never called `onReport()`)
- 1 market: **Open** (current)

## Root Cause Analysis

### Issue 1: One-sided betting causes auto-cancellation (75/79 markets)

The smart contract auto-cancels markets when `requestSettlement()` is called if either `totalUp == 0` or `totalDown == 0` (PricePrediction.sol:292-298).

**Why only one side gets bets:**
- The **PredictionTradingBot** picks ONE direction based on Binance price trend
- The **PredictionMarketMaker** also picks ONE direction (the "less popular" side)
- Both bots use the **same wallet** (`config.account`), so both check `getPosition(marketId, address)` and skip if already positioned
- Result: First bot to run places a bet on one side, second bot sees existing position and skips

Even when they happen to pick opposite sides, they're using the same account, so the second bot's `getPosition` check sees the first bot's position and skips.

**Additionally:** The PredictionMarketMaker only bets ONE side per market by design — it picks the less-staked side but never bets BOTH sides.

### Issue 2: Chainlink CRE not settling (3 stuck markets)

Markets #27, #64, #72 have both UP and DOWN bets but are stuck at `SettlementRequested` (status=1). This means:
- `requestSettlement()` was called successfully
- The `SettlementRequested` event was emitted
- But Chainlink CRE never called `onReport()` to finalize

**Likely causes:**
- CRE workflow not deployed/active on Base Sepolia
- CRE workflow misconfigured (wrong contract address, wrong event signature)
- CRE DON not monitoring the correct chain

The contract allows the **owner** to call `onReport()` directly as a fallback (PricePrediction.sol:316), but the bot doesn't implement this.

## Chosen Approach: Fix Both Issues

### Fix 1: Market Maker bets BOTH sides

Change PredictionMarketMaker to always place TWO predictions per market:
- Bet UP with a portion of the stake
- Bet DOWN with the remaining portion
- Use `stakeSplit` to control the ratio (e.g., 60/40)

This guarantees every market has both sides covered, preventing auto-cancellation.

### Fix 2: Owner settlement fallback in PredictionMarketCreator

Add logic to PredictionMarketCreator to detect markets stuck at `SettlementRequested` for too long (e.g., 5+ minutes) and settle them directly using the owner key by calling `onReport()` with the oracle TWAP data.

The owner already has permission to call `onReport()` (PricePrediction.sol:316). The bot can:
1. Read the current TWAP from the oracle contract
2. Compare with the market's opening TWAP / strike price
3. Determine the outcome (UP or DOWN)
4. Encode and call `onReport()` directly

## Key Decisions

- **Market maker bets both sides** — not just the less-popular side
- **Owner fallback settlement** — when CRE doesn't settle within a timeout
- **Oracle-based outcome** — read TWAP from on-chain oracle for correctness
- **Keep Chainlink CRE** as primary settlement path, fallback is just a safety net

## Open Questions

None — both fixes are well-scoped and straightforward.

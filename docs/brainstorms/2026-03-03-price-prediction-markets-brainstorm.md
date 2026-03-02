# Price Prediction Markets with Yield

**Date:** 2026-03-03
**Status:** Brainstorm
**Author:** Brainstorm session

---

## What We're Building

A `PricePrediction.sol` contract that lets users stake sxTokens (already earning lending yield) on short-term price outcomes derived from the existing `Oracle.sol` TWAP. Markets are settled trustlessly via **Chainlink CRE**, which reads the on-chain oracle and submits a signed result. Funds remain in the unified BalanceManager pool during the prediction, so **yield accrues to all participants** regardless of outcome — only the principal is at risk.

### Two Market Types

1. **Directional (UP/DOWN)** — Will ETH/USDC be higher or lower in 5 minutes vs. the current TWAP?
2. **Absolute (Above/Below Strike)** — Will ETH/USDC be above $3,500 in 5 minutes?

---

## Why This Approach

- **Reuses existing infrastructure**: `BalanceManager.lock/unlock`, `Oracle.getTWAP`, authorized operator pattern
- **Yield is a free differentiator**: `unlock()` auto-claims yield before settlement, so even losing participants keep their accrued yield
- **No external oracle dependency**: Chainlink CRE reads our own `Oracle.sol`, price data comes from actual orderbook trades
- **Simple UX**: Binary outcomes, fast markets, claim-based settlement

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Market types | Both UP/DOWN and Above/Below strike | Covers simple and targeted predictions |
| Market creation | Admin/owner only | Prevents spam; ensures adequate liquidity per market |
| Settlement oracle | Chainlink CRE + Oracle.getTWAP | Trustless, uses on-chain orderbook data |
| Protocol fee | ~2% of prize pool on settlement | Covers CRE costs, protocol revenue |
| Locked funds & liquidation | Included in liquidation (default behavior) | No special handling needed; existing seizeCollateral works |
| Yield during prediction | All participants receive yield; only principal is at risk | unlock() auto-claims yield before distributing prize pool |
| Market duration | Configurable by admin (default: 5 minutes) | Flexibility for different trading pair volatilities |

---

## Architecture

```
BalanceManager (unified pool)
  /        |        \
OrderBook  PricePrediction  LendingManager
(trading)  (predictions)    (yield source)

PricePrediction.sol
  ├── createMarket(poolId, marketType, strikePrice, duration)  ← admin only
  ├── predict(marketId, side, amount)                          ← any user
  ├── requestSettlement(marketId)                              ← anyone, after endTime
  ├── settleMarket(marketId, outcome, signature)               ← Chainlink CRE
  └── claim(marketId)                                          ← winner

Chainlink CRE Workflow
  EVM Log Trigger: SettlementRequested
    → Read Oracle.getTWAP(token, 300)    (5-min TWAP at settlement time)
    → Compute outcome (UP/DOWN or above/below strike)
    → Sign and submit to settleMarket()
```

---

## User Flow

```
1. User has 1000 sxUSDC (earning ~5% APY from lending)
2. Admin has created: "ETH/USDC UP/DOWN — 5 min" market
3. User calls predict(marketId, UP, 100)
   → BalanceManager.lock(user, sxUSDC, 100)  [funds still earn yield]
4. Market ends → anyone calls requestSettlement()
   → emits SettlementRequested event
5. Chainlink CRE detects event, reads Oracle TWAP, submits signed result
6. Winner calls claim(marketId)
   → BalanceManager.unlock(user, sxUSDC, stake)  [auto-claims yield]
   → Winner receives proportional share of loser stakes minus 2% fee
7. Loser calls claim(marketId)
   → BalanceManager.unlock(user, sxUSDC, 0 principal)  [auto-claims yield]
   → Loser keeps accumulated yield, loses principal
```

---

## Prize Pool Mechanics

**Winning side** receives: `total_losing_stake * (1 - fee%)` distributed proportionally by stake size
**Losing side** receives: `0` principal (but keeps yield claimed on unlock)
**Protocol**: `total_losing_stake * fee%` (e.g., 2%)

Example with 500 USDC on UP, 400 USDC on DOWN, UP wins, 2% fee:
- Loser pool to distribute: `400 * 0.98 = 392 USDC`
- Each UP bettor gets back: their stake + (stake/500) * 392

---

## Integration Points

| Contract | What PricePrediction Needs |
|----------|---------------------------|
| `BalanceManager` | Authorized operator (to call lock/unlock) |
| `Oracle.sol` | Read-only access to `getTWAP(token, window)` |
| `Chainlink CRE` | Trusted settlement caller (signature verification) |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| TWAP manipulation on short windows | Require minimum market liquidity (orderbook volume threshold) before admin can create market |
| No liquidity on one side | Allow cancellation/refund if one side has 0 participants at endTime |
| Chainlink CRE fails to settle | Allow fallback: any user can trigger re-request after grace period |
| Locked funds counted as collateral | Default behavior — users should manage their health factor |

---

## Resolved Questions

- **Market creation**: Admin only ✓
- **Fee**: ~2% of prize pool ✓
- **Market types**: Both UP/DOWN and Above/Below ✓
- **Liquidation policy**: Locked funds included in liquidation (existing behavior) ✓
- **Minimum stake**: Yes, configurable floor (default 10 USDC) to prevent dust positions ✓
- **Collateral currency**: sxUSDC only at launch — stable value simplifies prize pool accounting ✓

---

## Open Questions

1. **Max TVL cap per market?** How much total stake per market to limit liquidity fragmentation? (Suggested: admin-configurable per market, e.g. 100k USDC default)
2. **CRE signature scheme**: Which specific Chainlink CRE report format should we use for on-chain signature verification?

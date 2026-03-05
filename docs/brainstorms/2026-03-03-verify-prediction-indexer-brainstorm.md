# Verify Prediction Indexer Without Full Historical Sync

**Date:** 2026-03-03
**Status:** Brainstorm
**Author:** Brainstorm session

---

## Problem

The ponder indexer uses a **shared** `SCALEX_CORE_DEVNET_START_BLOCK=37778599` for all contracts on the core chain. PricePrediction was deployed at block `38364125` — roughly **585k blocks later**. This means the indexer must scan all 585k blocks before it reaches any prediction events to process.

We need to verify that the prediction indexer handlers (`handleMarketCreated`, `handlePredicted`, `handleMarketSettled`, `handleClaimed`, etc.) work correctly without waiting hours for a full historical sync.

**Constraint:** Production `.env.core-chain` must keep the shared `SCALEX_CORE_DEVNET_START_BLOCK` for all contracts — no per-contract start block overrides in production.

---

## What's Already In Place

- 19 markets created on-chain (block ~38364125–38500000), all settled/cancelled, with predictions placed and claimed
- `pricePredictionHandler.ts` with 6 handler functions fully implemented
- `predictionMarkets`, `predictionPositions`, `predictionEvents` tables in schema
- `PRICE_PREDICTION_CONTRACT_ADDRESS=0xB5D611e673d16d4d734635641076Ce8DeBDa5291` in `.env.core-chain`
- Existing `POOL_START_BLOCK` pattern in `core-chain-ponder.config.ts` shows per-contract overrides are already done for PoolManager (for a different reason — capturing earlier events)

---

## Approaches

### Approach A: Temporary Verification Env File ⚡ (Quick one-time check)

Create `.env.verify-prediction` (gitignored or deleted after use) with:
- `SCALEX_CORE_DEVNET_START_BLOCK=38364125` (PricePrediction deployment block)
- `SCALEX_CORE_DEVNET_END_BLOCK=38500000` (cap after all test markets)
- A separate DB (e.g., `ponder_verify_prediction`) to avoid corrupting production data

Run `ponder dev` with this env file against the real Base Sepolia RPC. The indexer only scans ~136k blocks, finds all 19 markets, and you can verify the DB tables are populated correctly.

**Pros:**
- Uses real on-chain events — no mocking
- Bounded scan (~136k blocks instead of 720k+), finishes much faster
- Production `.env.core-chain` untouched
- No new code required

**Cons:**
- Manual step, not automated
- One-time — doesn't provide ongoing test coverage
- Requires a clean separate database

---

### Approach B: Unit Tests for Handler Logic 🧪 (Permanent solution)

Add Vitest to the indexer project. Write unit tests that:
- Import each handler function directly (`pricePredictionHandler.handleMarketCreated`, etc.)
- Create a mock ponder context (`{ db: { insert, update, findFirst }, event, network }`)
- Feed synthetic event objects matching the contract ABI
- Assert the correct DB operations are called

Example:
```typescript
// src/handlers/__tests__/pricePredictionHandler.test.ts
it("handleMarketCreated inserts market with correct fields", async () => {
  const ctx = mockContext({ chainId: 84532 });
  const event = mockEvent({
    args: { marketId: 1n, baseToken: "0xBa609...", marketType: 0, duration: 300n, ... }
  });
  await handleMarketCreated({ context: ctx, event });
  expect(ctx.db.insert).toHaveBeenCalledWith(expect.objectContaining({
    id: "84532-1", status: 0, marketType: 0
  }));
});
```

**Pros:**
- No indexer sync required — runs in milliseconds
- Permanent coverage, runs in CI
- Tests handler logic in isolation
- Catches regressions immediately

**Cons:**
- Mocks may drift from real ponder context interface
- Initial setup effort (Vitest + mock utilities)
- Doesn't test the ponder event wiring (only handler logic)

---

### Approach C: Reuse POOL_START_BLOCK Pattern with TEST_START_BLOCK 🔧 (Configurable override)

Add a `PREDICTION_VERIFY_START_BLOCK` env var to `core-chain-ponder.config.ts`:

```typescript
PricePrediction: {
  startBlock: Number(process.env.PREDICTION_VERIFY_START_BLOCK)
    || Number(process.env.SCALEX_CORE_DEVNET_START_BLOCK) || 0,
}
```

Set `PREDICTION_VERIFY_START_BLOCK=38364125` in `.env.core-chain` only during verification testing. Remove or leave empty in production.

**Pros:**
- Uses the existing pattern (analogous to `POOL_START_BLOCK`)
- Explicitly documented as a verification tool, not a production override

**Cons:**
- Adds another env var to track
- Risk of accidentally leaving it set in production

---

## Recommendation

**Immediate verification (today):** Use **Approach A** — create a temp env file with a bounded block range and a separate DB. Run once, confirm all 6 handler types fired correctly, check DB rows. This takes 15–30 minutes to sync ~136k blocks instead of the full 720k+.

**Long-term:** Add **Approach B** (unit tests) as part of the prediction feature's definition of done. The existing `withEventValidator` wrapper and handler structure make them straightforward to test in isolation.

**Avoid Approach C** unless there's a recurring need — it adds another env var that could accidentally be left set in production.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Immediate verification method | Temp env file with bounded block range (A) | Fastest path, no code changes, tests real on-chain data |
| Long-term coverage | Unit tests (B) | Permanent, fast, no sync required |
| Production config | Unchanged shared `SCALEX_CORE_DEVNET_START_BLOCK` | User requirement: all contracts same start block |
| Separate DB for verification | Yes | Avoid corrupting production indexed data |

---

## Open Questions

*None — approach is clear.*

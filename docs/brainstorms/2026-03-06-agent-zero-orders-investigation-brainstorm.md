# Investigation: Why Agents Never Place Orders

**Date:** 2026-03-06
**Status:** Investigation Complete
**Projects:** scalex-8004 (agents), clob-indexer (backend)

## What We Found

All 8 registered agents on `https://base-sepolia-api.scalex.money/api/agents` show `totalOrders: 0` despite containers running for 22+ hours and executing hundreds of ticks.

## Root Causes

### 1. Orders Bypass AgentRouter (Critical)

**The Problem:** Agent order placement in `scalex-8004/src/core/contracts.ts` calls `Router.placeLimitOrder()` and `Router.placeMarketOrder()` directly (lines 472-484, 509-520), NOT `AgentRouter`.

**Why It Matters:** The indexer (Ponder) only attributes orders to agents when they come through `AgentRouter` events:
- `AgentSwapExecuted` / `AgentLimitOrderPlaced` (for user-delegated orders)
- `AgentSelfTradeExecuted` / `AgentSelfLimitOrderPlaced` (for self-funded orders)

Since agents use `Router` directly, their orders appear as regular user orders with `agentTokenId = 0`. The `/api/agents` endpoint queries `orders WHERE agent_token_id = X`, finding nothing.

**The Fix:** Agent order tools (`place_limit_order`, `place_market_order`) should call `AgentRouter.selfLimitOrder()` / `AgentRouter.selfTrade()` instead of `Router`, passing the agent's `SCALEX_AGENT_TOKEN_ID`.

### 2. `trades_today` Counter is Misleading (Medium)

**The Problem:** In `scheduler.ts:394-396`, `trades_today` increments by 1 for any tick where the LLM called ANY tools — including read-only tools like `get_balance`, `get_prices`, `get_order_book`.

**Impact:** Agent-1 (Moderate) hits "Daily trade limit reached (100/100)" after 100 ticks with tool calls, even if zero actual orders were placed. Agent-3 (Conservative) hits 20/20. This **self-throttles agents prematurely**.

**The Fix:** Only increment `trades_today` when write tools are called (e.g., `place_limit_order`, `place_market_order`, `self_predict`). Classify tools as read vs write and only count write actions.

### 3. Error Ticks and Context Gathering Failures (Low-Medium)

**The Problem:** Agent-5 (Grid Trading) shows many `error` ticks interspersed with successes. One logged error: "Failed to gather portfolio: HTTP request failed." Error details are stored in SQLite (`scalex.db`) but not printed to stdout.

**Possible Causes:**
- LLM API failures (agents use MiniMax `MiniMax-M2.1` via `api.minimax.io`)
- Ponder indexer GraphQL timeouts
- RPC node rate limiting

**The Fix:** Add error message logging to stdout for debugging. Consider adding retry logic for transient failures.

## Server Observations

**Container Status (2026-03-06):**

| Container | Strategy | Status | Notes |
|-----------|----------|--------|-------|
| scalex-agent-0 | DCA | Up 22h | Ran 1 tick (success, 11 tools), next in ~23h |
| scalex-agent-1 | Moderate | Up 22h | Blocked: "Daily trade limit reached (100/100)" |
| scalex-agent-2 | Unknown | Up 22h | Not checked |
| scalex-agent-3 | Conservative | Up 22h | Blocked: "Daily trade limit reached (20/20)" |
| scalex-agent-4 | Unknown | Up 22h | Not checked |
| scalex-agent-5 | Grid Trading | Up 22h | Active, many ticks, mix of success/error |
| scalex-agent-6 | Unknown | Up 22h | Not checked |
| scalex-agent-7 | Unknown | Up 22h | Not checked |

**Other Relevant Containers:**
- `base-sepolia-prediction-trading`, `base-sepolia-prediction-mm` — prediction bots (separate from agents)
- `base-sepolia-mm-*`, `base-sepolia-tb-*` — MM bots and trading bots (separate project)
- `base-sepolia-clob-indexer` — Ponder indexer (healthy)
- `base-sepolia-api` — REST API (healthy)

## Architecture Flow

```
Current (broken):
  Agent → Router.placeLimitOrder() → OrderPlaced(agentTokenId=0) → Indexer → orders table (no agent attribution)

Required (correct):
  Agent → AgentRouter.selfLimitOrder(agentTokenId) → AgentSelfLimitOrderPlaced + OrderPlaced(agentTokenId=X) → Indexer → orders + agent_orders tables
```

## Additional Issues

### SCALEX_PREDICTION Not Set
`SCALEX_PREDICTION` is not in `.env`, defaulting to zero address (`0x000...`). Any prediction-related tool calls would fail. Not blocking for order book trading but blocks prediction agents.

### Agent Token ID
`SCALEX_AGENT_TOKEN_ID=0` — must match the actual on-chain NFT token ID for each agent. If agents 0-7 have different NFT IDs, this needs per-agent configuration.

## Key Decisions

- **Priority:** Fix AgentRouter routing first (Issue 1) — this is the only way orders appear in the API
- **Scope:** Changes needed in `scalex-8004/src/core/contracts.ts` and `scalex-8004/src/mcp/tools.ts`
- **No indexer changes needed** — the indexer already handles `AgentRouter` events correctly

## Resolved Questions

1. **Does `AgentRouter` support self-funded trading?** YES. `executeSelfMarketOrder()` (line 517) and `executeSelfLimitOrder()` (line 541) exist in `AgentRouter.sol`. Also `cancelSelfOrder()` (line 566). These emit `AgentSelfTradeExecuted`, `AgentSelfLimitOrderPlaced`, `AgentSelfOrderCancelled` events that the indexer already handles.

2. **Are agent NFT token IDs sequential (0-7)?** NO. The API shows token IDs 1428-1439. `AGENT_ID` env var (0-7) is just a container identifier for loading metadata, NOT the on-chain NFT token ID. Each container needs `SCALEX_AGENT_TOKEN_ID` set to its actual NFT token ID.

3. **Should we fix the `trades_today` counter?** YES — user confirmed. Only write operations should count.

### Additional Critical Finding: Missing Environment Variables on Server

The server containers are **missing key environment variables**:
- `SCALEX_AGENT_ROUTER` — NOT SET (defaults to zero address `0x000...`)
- `SCALEX_AGENT_TOKEN_ID` — NOT SET (defaults to `0`)
- `SCALEX_PREDICTION` — NOT SET (defaults to zero address)

Even after fixing the code, these must be configured per-container:

| Container | AGENT_ID | Required SCALEX_AGENT_TOKEN_ID |
|-----------|----------|-------------------------------|
| scalex-agent-0 | 0 | needs mapping to NFT token ID (1428?) |
| scalex-agent-1 | 1 | needs mapping to NFT token ID (1429?) |
| ... | ... | ... |
| scalex-agent-7 | 7 | needs mapping to NFT token ID (1439?) |

Server also uses different contract addresses than local `.env`:
- Server Router: `0xc02dCE91749Db64f349ef3029E6d9b565454688B`
- Local Router: `0xc882b5af2B1AFB37CDe4D1f696fb112979cf98EE`

## Open Questions

1. **What is the mapping between AGENT_ID (0-7) and on-chain NFT token IDs (1428-1439)?** Need to verify each agent's actual token ID.
2. **What is the deployed `AgentRouter` contract address on Base Sepolia?** Must be set as `SCALEX_AGENT_ROUTER` on all containers.
3. **What about the MiniMax LLM errors?** Should we switch to a more reliable LLM provider or add retry logic?

## Issue 4: Agents Use Ponder GraphQL Instead of REST API

Currently, `scalex-8004/src/core/indexer.ts` queries the Ponder GraphQL indexer directly at `INDEXER_URL` (`base-sepolia-indexer.scalex.money`). Agents should instead use the REST API at `base-sepolia-api.scalex.money` (from `clob-indexer/api`).

**Why:** The REST API provides enriched, pre-processed data with proper formatting (Binance-compatible shapes), pagination, and aggregation. Direct Ponder queries bypass all this.

### REST API Coverage for Agent Needs

| Agent Function | Current (Ponder GraphQL) | Required (REST API) | Endpoint Exists? |
|---|---|---|---|
| Get pools | `getIndexedPools()` | `GET /api/markets` | YES |
| Get trades | `getRecentTrades()` | `GET /api/trades?symbol=X` | YES |
| Get orders | `getUserOrders()` | `GET /api/allOrders?address=X` | YES |
| Get candles | `getCandles()` | `GET /api/kline?symbol=X&interval=Y` | YES |
| Get order book | `getIndexedOrderBook()` | `GET /api/depth?symbol=X` | YES |
| Get balances | `getIndexedBalances()` | `GET /api/account?address=X` | YES |
| Get lending positions | `getLendingPositions()` | `GET /api/lending/dashboard/:user` | YES |
| Get user stats | `getUserStats()` | `GET /api/users/:address/analytics` | YES |
| Get prediction markets | N/A (via contract calls) | `GET /api/predictions/markets?status=0` | YES |
| Get prediction positions | N/A (via contract calls) | `GET /api/predictions/positions/:address` | YES |
| Get claimable predictions | N/A | `GET /api/predictions/pending/:address` | YES |
| Cross-chain transfers | `getCrossChainTransfers()` | `GET /api/activity/:address?type=transfer` | PARTIAL |
| Raw GraphQL | `queryGraphQL()` | No equivalent needed | N/A |

**All critical endpoints exist.** The migration is straightforward — rewrite `indexer.ts` to call REST endpoints instead of GraphQL.

### Additional API Enhancements Needed

1. **Pool lookup by base/quote address** — Agents use base/quote token addresses for orders, but REST API uses `symbol` (e.g., `sxWETHsxIDRX`). Need a way to map addresses to symbols, or add `GET /api/pools?baseCurrency=0x...&quoteCurrency=0x...` endpoint.

## Summary of Required Changes

### Code Changes (scalex-8004)
1. **Add AgentRouter trading ABI** — Add `executeSelfMarketOrder`, `executeSelfLimitOrder`, `cancelSelfOrder` to `abis.ts`
2. **Add self-trading functions** — Add `selfMarketOrder()`, `selfLimitOrder()`, `selfCancelOrder()` to `contracts.ts` using `AgentRouter`
3. **Wire tools to AgentRouter** — Change `place_limit_order`, `place_market_order`, `cancel_order` in `tools.ts` to use the new self-trading functions
4. **Fix `trades_today` counter** — Only count write tool calls (order placement, prediction, cancel) in `scheduler.ts`
5. **Migrate indexer.ts to REST API** — Replace all Ponder GraphQL calls with REST API calls to `base-sepolia-api.scalex.money`
6. **Use `INDEXER_REST_URL` env var** — Add new env var (or repurpose `INDEXER_URL`) to point to the REST API

### API Changes (clob-indexer/api)
1. **Add pool lookup by address** — `GET /api/pools?baseCurrency=0x...&quoteCurrency=0x...` or add address fields to `/api/markets` response

### Infrastructure Changes (server)
1. **Set `SCALEX_AGENT_ROUTER`** on all 8 containers
2. **Set `SCALEX_AGENT_TOKEN_ID`** per container (mapping AGENT_ID to NFT token ID)
3. **Set `SCALEX_PREDICTION`** if prediction agents should work
4. **Update `INDEXER_URL`** to point to REST API (`base-sepolia-api.scalex.money`)
5. **Restart all containers** after env changes

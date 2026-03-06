---
title: "fix: Agent order routing through AgentRouter and REST API migration"
type: fix
status: completed
date: 2026-03-06
---

# Fix Agent Order Routing Through AgentRouter and REST API Migration

## Overview

All 8 deployed agents show `totalOrders: 0` on the API despite running 22+ hours and executing hundreds of ticks. Three root causes identified:

1. **Orders bypass AgentRouter** — agents call `Router.placeLimitOrder/placeMarketOrder` directly, so orders have no `agentTokenId` attribution in the indexer
2. **`trades_today` counter overcounts** — counts any tick with tool calls (including reads) as a trade, causing premature self-throttling
3. **Agents use Ponder GraphQL instead of REST API** — should use `base-sepolia-api.scalex.money`

Brainstorm: `docs/brainstorms/2026-03-06-agent-zero-orders-investigation-brainstorm.md`

## Proposed Solution

Route agent orders through `AgentRouter.executeSelfLimitOrder/executeSelfMarketOrder/cancelSelfOrder` (already deployed on-chain), fix the trade counter, and migrate indexer.ts from GraphQL to REST API calls.

## Technical Approach

### Phase 1: AgentRouter Order Routing (scalex-8004)

The existing `selfPredict`/`selfClaimPrediction` pattern in `contracts.ts:771-812` already demonstrates the correct approach. We replicate it for trading.

#### 1.1 Add AgentRouter Trading ABI

**File:** `scalex-8004/src/core/abis.ts` (after line 594)

Add `AgentRouterTradingABI` with three functions matching the Solidity signatures from `AgentRouter.sol:517-580`:

```typescript
export const AgentRouterTradingABI = [
  {
    type: 'function',
    name: 'executeSelfMarketOrder',
    inputs: [
      { name: 'strategyAgentId', type: 'uint256' },
      { name: 'pool', type: 'tuple', components: [
        { name: 'baseCurrency', type: 'address' },
        { name: 'quoteCurrency', type: 'address' },
        { name: 'orderBook', type: 'address' },
      ]},
      { name: 'side', type: 'uint8' },
      { name: 'quantity', type: 'uint128' },
      { name: 'minOutAmount', type: 'uint128' },
    ],
    outputs: [
      { name: 'orderId', type: 'uint48' },
      { name: 'filled', type: 'uint128' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'executeSelfLimitOrder',
    inputs: [
      { name: 'strategyAgentId', type: 'uint256' },
      { name: 'pool', type: 'tuple', components: [
        { name: 'baseCurrency', type: 'address' },
        { name: 'quoteCurrency', type: 'address' },
        { name: 'orderBook', type: 'address' },
      ]},
      { name: 'price', type: 'uint128' },
      { name: 'quantity', type: 'uint128' },
      { name: 'side', type: 'uint8' },
      { name: 'timeInForce', type: 'uint8' },
    ],
    outputs: [
      { name: 'orderId', type: 'uint48' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'cancelSelfOrder',
    inputs: [
      { name: 'strategyAgentId', type: 'uint256' },
      { name: 'pool', type: 'tuple', components: [
        { name: 'baseCurrency', type: 'address' },
        { name: 'quoteCurrency', type: 'address' },
        { name: 'orderBook', type: 'address' },
      ]},
      { name: 'orderId', type: 'uint48' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
] as const;
```

**Pool struct compatibility:** Verified — `AgentRouter.sol:519` takes `IPoolManager.Pool calldata pool` which is `{ baseCurrency, quoteCurrency, orderBook }`, matching the existing `getPoolStruct()` return type in `contracts.ts:113-121`.

#### 1.2 Update Order Placement Functions

**File:** `scalex-8004/src/core/contracts.ts`

**Import** `AgentRouterTradingABI` from abis.ts (line 26).

**Add** `SCALEX_AGENT_TOKEN_ID` env var reader:
```typescript
const STRATEGY_AGENT_TOKEN_ID = parseInt(process.env.SCALEX_AGENT_TOKEN_ID || '0', 10);
```

**Add startup validation** — new `requireAgentRouter()` function:
```typescript
function requireAgentRouter() {
  if (AGENT_ROUTER_ADDRESS === '0x0000000000000000000000000000000000000000') {
    throw new Error('SCALEX_AGENT_ROUTER not set — cannot place agent orders');
  }
  if (STRATEGY_AGENT_TOKEN_ID === 0) {
    throw new Error('SCALEX_AGENT_TOKEN_ID not set — cannot place agent orders');
  }
  return { walletClient: requireWallet().walletClient, agentTokenId: STRATEGY_AGENT_TOKEN_ID };
}
```

**Modify** `placeLimitOrder` (lines 460-496):
- Call `requireAgentRouter()` instead of `requireWallet()`
- Target `AGENT_ROUTER_ADDRESS` with `AgentRouterTradingABI`
- Call `executeSelfLimitOrder(strategyAgentId, pool, price, quantity, side, timeInForce)`
- Remove `depositAmount` parameter (AgentRouter doesn't support inline deposits — agents must deposit first via separate `deposit` tool)

**Modify** `placeMarketOrder` (lines 498-530):
- Same pattern — call `executeSelfMarketOrder(strategyAgentId, pool, side, quantity, minOutAmount)`
- Remove `depositAmount` parameter

**Modify** `cancelOrder` (lines 532-545):
- Call `cancelSelfOrder(strategyAgentId, pool, orderId)`

#### 1.3 Update Tool Definitions

**File:** `scalex-8004/src/mcp/tools.ts`

**Remove** `deposit_amount` from `place_limit_order` tool schema (line 174-176) — no longer applicable. Update description to clarify agents must deposit funds first.

**Remove** `deposit_amount` from `place_market_order` tool schema — same reason.

**Do NOT add** `strategy_agent_id` to tool schemas — inject server-side from env var. The LLM shouldn't need to know or provide the token ID. This is safer and simpler.

**Update** `approve_token` tool handler (line 500) — approve `AGENT_ROUTER_ADDRESS` instead of `ROUTER_ADDRESS`:
```typescript
case 'approve_token':
  return contracts.approveToken(args.token as Address, contracts.AGENT_ROUTER_ADDRESS, args.amount as string);
```

**Update** tool dispatch (lines 502-506) — remove `deposit_amount` args from `placeLimitOrder` and `placeMarketOrder` calls.

#### 1.4 Update System Prompt

**File:** `scalex-8004/src/scheduler/agent.ts` — `buildSystemPrompt()` function

Add note: "Your orders are placed through AgentRouter. You must have sufficient balance in the BalanceManager before placing orders. Use `deposit` to add funds if needed. The `approve_token` tool approves the AgentRouter contract."

Remove any mention of `deposit_amount` parameter from order tool instructions.

### Phase 2: Fix `trades_today` Counter (scalex-8004)

#### 2.1 Define Write Tools Set

**File:** `scalex-8004/src/scheduler/agent.ts` (top of file)

```typescript
const WRITE_TOOLS = new Set([
  'place_limit_order',
  'place_market_order',
  'cancel_order',
  'swap',
  'deposit',
  'withdraw',
  'borrow',
  'repay',
  'self_predict',
  'self_claim_prediction',
]);
```

Note: `approve_token` excluded — approvals are not trades.

#### 2.2 Split actionsTaken

**File:** `scalex-8004/src/scheduler/agent.ts` (line 218 area)

Add a separate array:
```typescript
const writeActionsTaken: string[] = [];
```

In the tool execution loop (line 266), add:
```typescript
actionsTaken.push(`${toolName}(${toolCall.function.arguments})`);
if (WRITE_TOOLS.has(toolName)) {
  writeActionsTaken.push(toolName);
}
```

Return `writeActionsTaken` in the result object alongside `actionsTaken`.

#### 2.3 Update Counter Logic

**File:** `scalex-8004/src/scheduler/scheduler.ts` (lines 394-397)

Change condition from:
```typescript
if (result.status === 'success' && result.actionsTaken.length > 0) {
```
To:
```typescript
if (result.status === 'success' && result.writeActionsTaken.length > 0) {
```

This ensures `trades_today` only increments when actual write operations occur.

### Phase 3: REST API Migration (scalex-8004)

#### 3.1 Rewrite indexer.ts

**File:** `scalex-8004/src/core/indexer.ts`

Replace all GraphQL calls with REST API calls. Use a new env var `API_URL` (defaulting to `INDEXER_URL` for backward compat):

```typescript
const API_URL = process.env.API_URL || process.env.INDEXER_URL || 'http://localhost:3001';
```

**Function mapping:**

| Current Function | REST Endpoint | Key Differences |
|---|---|---|
| `getIndexedPools()` | `GET ${API_URL}/api/markets` | Returns enriched data with prices, volume |
| `getRecentTrades(poolId, limit)` | `GET ${API_URL}/api/trades?symbol=${symbol}&limit=${limit}` | Uses `symbol` not `poolId`; returns Binance-format |
| `getUserOrders(addr, status, limit)` | `GET ${API_URL}/api/allOrders?address=${addr}&limit=${limit}` | Binance-compatible order format |
| `getCandles(poolId, interval, limit)` | `GET ${API_URL}/api/kline?symbol=${symbol}&interval=${interval}&limit=${limit}` | Returns Binance kline arrays |
| `getIndexedOrderBook(poolId, limit)` | `GET ${API_URL}/api/depth?symbol=${symbol}&limit=${limit}` | Returns `{ bids, asks }` |
| `getIndexedBalances(addr)` | `GET ${API_URL}/api/account?address=${addr}` | Returns `{ balances: [{asset, free, locked}] }` |
| `getLendingPositions(addr)` | `GET ${API_URL}/api/lending/dashboard/${addr}` | Returns full dashboard with supplies, borrows |
| `getUserStats(addr)` | `GET ${API_URL}/api/users/${addr}/analytics` | Returns PnL, win rate, fill rate |
| `getCrossChainTransfers(addr, limit)` | `GET ${API_URL}/api/activity/${addr}?type=transfer&limit=${limit}` | Part of activity feed |
| `queryGraphQL(query, vars)` | **Remove** | No REST equivalent; tool should be removed |

#### 3.2 Handle poolId-to-symbol Mapping

The REST API uses `symbol` (e.g., `sxWETHsxIDRX`) while agents currently pass `poolId` (order book hex address). Two options:

**Option A (Recommended):** Build a local symbol lookup cache. On first call to `getIndexedPools()` (which returns both `poolId` and `symbol`), cache the mapping. Use it to convert poolId to symbol for subsequent calls.

```typescript
let poolSymbolMap: Map<string, string> | null = null;

async function getSymbolForPool(poolId: string): Promise<string> {
  if (!poolSymbolMap) {
    const pools = await getIndexedPools();
    poolSymbolMap = new Map(pools.map(p => [p.poolId.toLowerCase(), p.symbol]));
  }
  return poolSymbolMap.get(poolId.toLowerCase()) || poolId;
}
```

**Option B:** Add a `GET /api/pools?baseCurrency=0x...&quoteCurrency=0x...` endpoint to the REST API in clob-indexer. More work but cleaner long-term.

#### 3.3 Remove `query_indexer` Tool

**File:** `scalex-8004/src/mcp/tools.ts`

Remove the `query_indexer` tool definition and handler. It exposes raw GraphQL which won't work against the REST API. If needed, replace with a `query_api` tool that makes GET requests to the REST API, but this is likely unnecessary given the specific tools available.

#### 3.4 Update Prediction Market Data Source

**File:** `scalex-8004/src/scheduler/scheduler.ts` — `gatherContext()` function

The prediction context gathering currently calls contracts directly. Update to use REST API:
- `GET /api/predictions/markets?status=0` for active markets
- `GET /api/predictions/positions/${owner}` for agent positions
- `GET /api/predictions/pending/${owner}` for claimable markets

### Phase 4: API Enhancement (clob-indexer/api)

#### 4.1 Add Pool Lookup by Address (Optional)

**File:** `clob-indexer/api/src/routes/market.routes.ts`

If Option B from 3.2 is chosen, add endpoint:
```
GET /api/pools?baseCurrency=0x...&quoteCurrency=0x...
```

This queries the `pools` table by base/quote currency addresses and returns pool details including `symbol`. Not strictly required if the agent-side cache approach (Option A) is used.

### Phase 5: Infrastructure Configuration (Server)

#### 5.1 Environment Variables

Set on all 8 agent containers:

```bash
SCALEX_AGENT_ROUTER=<deployed AgentRouter address on Base Sepolia>
SCALEX_AGENT_TOKEN_ID=<NFT token ID for this specific agent>
API_URL=https://base-sepolia-api.scalex.money
```

**AgentRouter address:** Two addresses found in docs:
- `0x91136624222e2faAfBfdE8E06C412649aB2b90D0` (from `AGENT_CONFIGURATION.md`)
- `0x36f229515bf0e4c74165b214c56bE8c0b49a1574` (from `AGENT_FLOWS_AND_FUNCTIONS.md`)

Must verify which is the currently deployed proxy.

**Token ID mapping:** Based on API response, agents have token IDs 1428-1439. Need to verify mapping:

| Container | AGENT_ID | Expected Token ID |
|-----------|----------|-------------------|
| scalex-agent-0 | 0 | 1428 (verify) |
| scalex-agent-1 | 1 | 1429 (verify) |
| scalex-agent-2 | 2 | 1430 (verify) |
| scalex-agent-3 | 3 | 1431 (verify) |
| scalex-agent-4 | 4 | 1432 (verify) |
| scalex-agent-5 | 5 | 1433 (verify) |
| scalex-agent-6 | 6 | 1434 (verify) |
| scalex-agent-7 | 7 | 1439 (verify) |

#### 5.2 Pre-migration Steps

Before deploying the code:
1. Verify agent wallet addresses own their respective NFT token IDs on-chain
2. Ensure agent wallets have approved AgentRouter for token spending
3. Check that agents have sufficient BalanceManager balances (since inline `depositAmount` is removed)
4. Cancel any existing open orders placed via Router (AgentRouter cannot cancel Router-placed orders)

#### 5.3 Deployment

1. Build updated scalex-8004 image
2. Stop all 8 agent containers
3. Update docker-compose/env with new env vars
4. Restart all containers
5. Monitor logs for first successful tick with order placement

## System-Wide Impact

### Interaction Graph

```
Agent tick → Scheduler.executeTick()
  → gatherContext() → indexer.ts → REST API (was: Ponder GraphQL)
  → executeStrategyTick() → LLM → handleToolCall()
    → place_limit_order → contracts.placeLimitOrder()
      → AgentRouter.executeSelfLimitOrder() (was: Router.placeLimitOrder())
        → OrderBook.placeOrder(strategyAgentId, executor)
          → OrderPlaced event (with agentTokenId)
          → AgentSelfLimitOrderPlaced event
        → Ponder Indexer picks up both events
          → orders table (agentTokenId set)
          → agent_orders table (new row)
        → REST API /api/agents/:id/orders returns the order
```

### Error Propagation

- `SCALEX_AGENT_ROUTER` not set → `requireAgentRouter()` throws → tick result: error → scheduler logs and retries next tick
- NFT ownership check fails → `AgentRouter` reverts "Not strategy agent owner" → tool returns error → LLM sees error, may retry or skip
- REST API down → `indexer.ts` fetch throws → `gatherContext()` fails → tick result: error → scheduler retries

### State Lifecycle Risks

- **Pre-migration orders:** Open orders placed via Router cannot be cancelled via AgentRouter. Must cancel before deploying or keep a fallback `cancelOrder` that tries Router if AgentRouter fails.
- **Counter reset:** After deploying the `trades_today` fix, counters will effectively reset (only write tools count now). Agents previously throttled will start executing again.

## Acceptance Criteria

### Functional Requirements

- [ ] Agent orders appear in `GET /api/agents/:agentTokenId/orders` with correct `agentTokenId`
- [ ] Agent orders appear in `GET /api/agents/:agentTokenId/stats` with correct volume
- [ ] `trades_today` only increments when write tools execute (not read tools)
- [ ] Agents no longer hit "Daily trade limit reached" from read-only ticks
- [ ] All indexer.ts functions fetch from REST API instead of Ponder GraphQL
- [ ] `approve_token` approves AgentRouter instead of Router
- [ ] Startup fails gracefully if `SCALEX_AGENT_ROUTER` or `SCALEX_AGENT_TOKEN_ID` not set

### Non-Functional Requirements

- [ ] No breaking changes to agent MCP/A2A/chat interfaces
- [ ] Error messages are clear when AgentRouter config is missing
- [ ] REST API responses are properly error-handled (non-200 status)

## Dependencies & Prerequisites

- Deployed AgentRouter contract address on Base Sepolia (needs verification)
- NFT token ID mapping for agents 0-7 (needs on-chain verification)
- Agent wallets must own their respective NFT tokens
- Agent wallets need token approvals for AgentRouter

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Wrong AgentRouter address | Medium | High | Verify on-chain before deployment |
| NFT ownership mismatch | Medium | High | Check ownerOf() for each token ID |
| REST API format mismatch | Low | Medium | Test each endpoint mapping locally first |
| Pre-migration orders stuck | Low | Low | Cancel open orders before deploying |

## References & Research

### Internal References

- AgentRouter contract: `clob-dex/src/ai-agents/AgentRouter.sol:517-580`
- Current order placement: `scalex-8004/src/core/contracts.ts:460-545`
- Tool dispatch: `scalex-8004/src/mcp/tools.ts:498-550`
- Scheduler counter: `scalex-8004/src/scheduler/scheduler.ts:394-397`
- Self-predict pattern: `scalex-8004/src/core/contracts.ts:771-812`
- Agent auth patterns: `memory/agent-auth-patterns.md`
- Agent system docs: `clob-dex/docs/agent-system/`

### External References

- REST API endpoints: `clob-indexer/api/src/routes/` (market, agents, predictions, lending, wallet, activity)
- Ponder indexer handlers: `clob-indexer/ponder/src/handlers/agentRouterHandler.ts`

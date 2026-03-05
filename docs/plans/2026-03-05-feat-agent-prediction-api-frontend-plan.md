---
title: "feat: Agent Prediction API + Frontend Integration"
type: feat
status: active
date: 2026-03-05
---

# feat: Agent Prediction API + Frontend Integration

## Overview

Surface agent prediction data (already indexed by Ponder) through the API layer and frontend. The data pipeline is complete — `agent_prediction_events` table and `agent_stats.totalPredictions/totalPredictionVolume/totalPredictionClaims` columns are already populated by the indexer. We need to expose and display them.

Three workstreams:
1. **API**: Add prediction stats to agent endpoints + new `/predictions` endpoint per agent
2. **Agent UI**: Show prediction stats on agent cards and detail page
3. **Prediction Market UI**: Enrich prediction events with agent identity badges

## Proposed Solution

### API Changes (clob-indexer/api)

Follow existing patterns: Elysia routes with `t.Object()` validation, static service methods with `runQuery<T>()`, parameterized SQL, standard `{ success, data, pagination }` response format.

### Frontend Changes (frontend/apps/web)

Follow existing patterns: React Query hooks with `fetchAPI<T>()`, TanStack Router, responsive grid layouts with stat cards, `useIsMobile()` for responsive breakpoints.

## Acceptance Criteria

### API

- [ ] `GET /api/agents` returns `totalPredictions`, `totalPredictionVolume`, `totalPredictionClaims` per agent
- [ ] `GET /api/agents/:agentTokenId` returns prediction stats in `aggregateStats`
- [ ] `GET /api/agents/:agentTokenId/predictions` returns paginated prediction events with market context
- [ ] Predictions endpoint supports `?action=PREDICT|CLAIM` filter, `?limit=` and `?offset=` pagination
- [ ] Predictions endpoint joins against `prediction_markets` for market context (strikePrice, status, outcome)
- [ ] Predictions endpoint sorted by `timestamp DESC` (most recent first)
- [ ] `GET /api/predictions/events/:marketId` enriched with `agentTokenId` when prediction was agent-made

### Frontend — Agent UI

- [ ] `AgentCard.tsx` shows prediction count in stats row
- [ ] `AgentDetail.tsx` shows prediction stats (Predictions, Prediction Volume, Claims) in stats grid
- [ ] `AgentDetail.tsx` has Predictions tab with `AgentPredictionsTable` component
- [ ] `AgentPredictionsTable` shows: Action, Market, Direction, Amount, Time with pagination
- [ ] `useAgentPredictions(agentTokenId)` hook fetches from new endpoint
- [ ] Zero state: "No prediction activity yet" centered message

### Frontend — Prediction Market UI

- [ ] Prediction event list in market detail shows agent badge when event was agent-initiated
- [ ] Badge shows agent tokenId/name linking to agent detail page
- [ ] Badge distinguishes delegated vs self-funded (tooltip or label)

## Changes

### Part 1: API — Add Prediction Stats to Agent Endpoints

#### 1.1 Modify `agents.service.ts` — getAgents()

**File:** `/Users/renaka/gtx/clob-indexer/api/src/services/agents.service.ts`

In the stats aggregation query (around line 78-86), add prediction columns to the SELECT:

```sql
SELECT
    agent_token_id::text,
    MAX(last_activity_timestamp)::integer as last_activity_at,
    COALESCE(SUM(total_trading_volume), 0)::text as total_trading_volume,
    COALESCE(SUM(total_predictions), 0)::int as total_predictions,
    COALESCE(SUM(total_prediction_volume), 0)::text as total_prediction_volume,
    COALESCE(SUM(total_prediction_claims), 0)::int as total_prediction_claims
FROM agent_stats
WHERE chain_id = $1 AND agent_token_id = ANY($2::numeric[])
GROUP BY agent_token_id
```

In the data merge step (around line 97-120), add prediction fields to each agent object:

```typescript
totalPredictions: activityMap.get(agent.tokenId)?.total_predictions || 0,
totalPredictionVolume: activityMap.get(agent.tokenId)?.total_prediction_volume || '0',
totalPredictionClaims: activityMap.get(agent.tokenId)?.total_prediction_claims || 0,
```

#### 1.2 Modify `agents.service.ts` — getAgent()

**File:** `/Users/renaka/gtx/clob-indexer/api/src/services/agents.service.ts`

In the detail stats aggregation query (around line 160-175), add prediction columns:

```sql
COALESCE(SUM(total_predictions), 0)::int as total_predictions,
COALESCE(SUM(total_prediction_volume), 0)::text as total_prediction_volume,
COALESCE(SUM(total_prediction_claims), 0)::int as total_prediction_claims
```

In the `aggregateStats` response object, add:

```typescript
totalPredictions: stats?.total_predictions || 0,
totalPredictionVolume: stats?.total_prediction_volume || '0',
totalPredictionClaims: stats?.total_prediction_claims || 0,
```

### Part 2: API — New Predictions Endpoint

#### 2.1 Add route to `agents.routes.ts`

**File:** `/Users/renaka/gtx/clob-indexer/api/src/routes/agents.routes.ts`

Add new route:

```typescript
.get('/agents/:agentTokenId/predictions', AgentsService.getAgentPredictions, {
    params: t.Object({
        agentTokenId: t.String(),
    }),
    query: t.Object({
        chainId: t.Optional(t.String()),
        action: t.Optional(t.String()),  // "PREDICT" or "CLAIM"
        limit: t.Optional(t.String()),
        offset: t.Optional(t.String()),
    }),
    detail: {
        summary: 'Get agent prediction events',
        description: 'Get paginated prediction events for a specific agent with optional action filter',
        tags: ['Agents'],
    },
})
```

#### 2.2 Add `getAgentPredictions()` to `agents.service.ts`

**File:** `/Users/renaka/gtx/clob-indexer/api/src/services/agents.service.ts`

New static method following the existing pattern from `getAgentLending`:

```typescript
static async getAgentPredictions(ctx: Context) {
    try {
        const { params, query } = ctx as any;
        const chainId = parseInt(query.chainId as string) || 84532;
        const agentTokenId = params.agentTokenId;
        const action = query.action as string | undefined;
        const limit = Math.min(Math.max(parseInt(query.limit as string ?? '50') || 50, 1), 100);
        const offset = Math.max(parseInt(query.offset as string ?? '0') || 0, 0);

        // Validate action filter
        if (action && !['PREDICT', 'CLAIM'].includes(action)) {
            ctx.set.status = 400;
            return { success: false, error: 'Invalid action. Must be: PREDICT or CLAIM' };
        }

        // Build query with optional action filter
        const params_: unknown[] = [chainId, agentTokenId];
        let actionFilter = '';
        if (action) {
            params_.push(action);
            actionFilter = `AND ape.action = $3`;
        }

        // Count query
        const countResult = await runQuery<{ count: number }>(`
            SELECT COUNT(*)::int as count
            FROM agent_prediction_events ape
            WHERE ape.chain_id = $1 AND ape.agent_token_id = $2 ${actionFilter}
        `, params_);

        // Main query with market context JOIN
        const predictions = await runQuery<any>(`
            SELECT
                ape.id,
                ape.chain_id,
                ape.owner,
                ape.agent_token_id::text as agent_token_id,
                ape.executor,
                ape.action,
                ape.market_id::text as market_id,
                ape.predict_up,
                ape.amount::text as amount,
                ape.timestamp,
                ape.transaction_id,
                ape.block_number::text as block_number,
                pm.base_token,
                pm.strike_price::text as strike_price,
                pm.status as market_status,
                pm.outcome as market_outcome,
                pm.end_time as market_end_time
            FROM agent_prediction_events ape
            LEFT JOIN prediction_markets pm
                ON ape.market_id = pm.market_id AND ape.chain_id = pm.chain_id
            WHERE ape.chain_id = $1 AND ape.agent_token_id = $2 ${actionFilter}
            ORDER BY ape.timestamp DESC
            LIMIT $${params_.length + 1} OFFSET $${params_.length + 2}
        `, [...params_, limit, offset]);

        return {
            success: true,
            data: predictions,
            count: countResult[0]?.count || 0,
            pagination: { limit, offset },
        };
    } catch (error) {
        console.error('Error fetching agent predictions:', error);
        ctx.set.status = 500;
        return { success: false, error: `Failed to fetch agent predictions: ${error}` };
    }
}
```

### Part 3: API — Enrich Prediction Events with Agent Identity

#### 3.1 Modify Ponder prediction events endpoint

**File:** `/Users/renaka/gtx/clob-indexer/ponder/src/api/index.ts`

In the `GET /api/predictions/events/:marketId` handler, LEFT JOIN against `agent_prediction_events` on `transaction_id` to add optional `agentTokenId` and `executor` fields:

```sql
SELECT
    pe.*,
    ape.agent_token_id::text as agent_token_id,
    ape.executor as agent_executor
FROM prediction_events pe
LEFT JOIN agent_prediction_events ape
    ON pe.transaction_id = ape.transaction_id
    AND pe.chain_id = ape.chain_id
WHERE pe.market_id = $1 AND pe.chain_id = $2
ORDER BY pe.timestamp DESC
```

This adds nullable `agentTokenId` and `agentExecutor` fields to each prediction event. When non-null, the frontend shows the agent badge.

### Part 4: Frontend — Types

#### 4.1 Update `agents.types.ts`

**File:** `/Users/renaka/gtx/frontend/apps/web/src/features/agents/types/agents.types.ts`

Add to `AgentMarketplaceItem`:
```typescript
totalPredictions: number;
totalPredictionVolume: string;
totalPredictionClaims: number;
```

Add to `AgentStatsData` (or `AgentDetailResponse.aggregateStats`):
```typescript
totalPredictions: number;
totalPredictionVolume: string;
totalPredictionClaims: number;
```

Add new type:
```typescript
export interface AgentPredictionEvent {
    id: string;
    chainId: number;
    owner: string;
    agentTokenId: string;
    executor: string;
    action: 'PREDICT' | 'CLAIM';
    marketId: string;
    predictUp: boolean | null;
    amount: string;
    timestamp: number;
    transactionId: string;
    blockNumber: string;
    // Market context (from JOIN)
    baseToken?: string;
    strikePrice?: string;
    marketStatus?: number;
    marketOutcome?: number;
    marketEndTime?: number;
}

export interface AgentPredictionsResponse {
    success: boolean;
    data: AgentPredictionEvent[];
    count: number;
    pagination: { limit: number; offset: number };
}
```

#### 4.2 Update `prediction.types.ts`

**File:** `/Users/renaka/gtx/frontend/apps/web/src/features/predictions/types/prediction.types.ts`

Add to prediction event type (or create enriched variant):
```typescript
agentTokenId?: string;  // Non-null when prediction was made by an agent
agentExecutor?: string; // The agent executor address
```

### Part 5: Frontend — Hooks

#### 5.1 Create `useAgentPredictions.ts`

**File:** `/Users/renaka/gtx/frontend/apps/web/src/features/agents/hooks/useAgentPredictions.ts`

```typescript
import { useQuery } from '@tanstack/react-query';
import { fetchAPI } from '@/hooks/fetchAPI';
import type { AgentPredictionsResponse } from '../types/agents.types';

export function useAgentPredictions(
    agentTokenId: string | undefined,
    options?: { action?: 'PREDICT' | 'CLAIM'; limit?: number; offset?: number }
) {
    const params = new URLSearchParams();
    if (options?.action) params.set('action', options.action);
    if (options?.limit) params.set('limit', String(options.limit));
    if (options?.offset) params.set('offset', String(options.offset));
    const queryString = params.toString();

    return useQuery<AgentPredictionsResponse, Error>({
        queryKey: ['agent-predictions', agentTokenId, options],
        queryFn: () => fetchAPI<AgentPredictionsResponse>(
            `/agents/${agentTokenId}/predictions${queryString ? `?${queryString}` : ''}`
        ),
        enabled: !!agentTokenId,
        staleTime: 30_000,
    });
}
```

### Part 6: Frontend — Agent Card Updates

#### 6.1 Update `AgentCard.tsx`

**File:** `/Users/renaka/gtx/frontend/apps/web/src/features/agents/components/AgentCard.tsx`

Add a prediction stat to the existing stats row (3-column grid). Change grid to 4 columns or add a second row:

```tsx
{/* Existing stats row - add prediction count */}
<div className="grid grid-cols-4 gap-2 mt-3">
    {/* existing: Users, Volume, Orders */}
    <div className="flex items-center gap-1 text-[#606060] text-xs">
        <Target size={12} />
        <span>{agent.totalPredictions || 0}</span>
    </div>
</div>
```

### Part 7: Frontend — Agent Detail Updates

#### 7.1 Update `AgentDetail.tsx`

**File:** `/Users/renaka/gtx/frontend/apps/web/src/features/agents/components/AgentDetail.tsx`

Add prediction stats to the stats grid (currently 4 stats: Users, Volume, Orders, Cancelled). Expand to include 3 prediction stats:

```tsx
{/* Add to stats grid */}
<div className="bg-[#111111] border border-[#1F1F1F] rounded-lg p-4">
    <div className="flex items-center gap-1.5 text-[#606060] text-xs mb-2">
        <Target size={12} />
        <span>Predictions</span>
    </div>
    <p className="text-[#E0E0E0] font-semibold text-lg">
        {stats?.totalPredictions || 0}
    </p>
    <p className="text-[#606060] text-xs mt-0.5">
        {stats?.totalPredictionClaims || 0} claimed
    </p>
</div>
<div className="bg-[#111111] border border-[#1F1F1F] rounded-lg p-4">
    <div className="flex items-center gap-1.5 text-[#606060] text-xs mb-2">
        <TrendingUp size={12} />
        <span>Pred. Volume</span>
    </div>
    <p className="text-[#E0E0E0] font-semibold text-lg">
        {formatTokenAmount(stats?.totalPredictionVolume || '0')} IDRX
    </p>
</div>
```

Add Predictions tab/section after existing content, rendering `AgentPredictionsTable`:

```tsx
<AgentPredictionsTable agentTokenId={agentTokenId} />
```

#### 7.2 Create `AgentPredictionsTable.tsx`

**File:** `/Users/renaka/gtx/frontend/apps/web/src/features/agents/components/AgentPredictionsTable.tsx`

Table component showing agent prediction history:

- **Columns**: Action (PREDICT/CLAIM badge), Market (strikePrice + asset), Direction (UP/DOWN with color), Amount, Time (relative)
- **Features**: Action filter tabs (All / Predict / Claim), pagination
- **Empty state**: "No prediction activity yet" centered message
- **Pattern**: Follow `AgentOrdersTable` structure with React Query pagination

### Part 8: Frontend — Prediction Market Agent Badges

#### 8.1 Update prediction event list component

**File:** In the prediction market detail component (wherever prediction events are rendered)

When a prediction event has `agentTokenId` (non-null from the enriched API response), render an agent badge:

```tsx
{event.agentTokenId && (
    <Link to={`/agents/${event.agentTokenId}`}>
        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-[#1A1A2E] border border-[#2A2A4E] text-xs text-[#8B8BFF]">
            <Bot size={10} />
            Agent #{event.agentTokenId}
        </span>
    </Link>
)}
```

## System-Wide Impact

- **API surface parity**: Agent endpoints gain 3 new response fields + 1 new endpoint. No breaking changes.
- **Prediction API enrichment**: LEFT JOIN adds nullable fields — existing consumers unaffected.
- **State lifecycle**: Read-only. No write operations, no mutation risks.
- **Error propagation**: Standard try/catch → 500 response pattern. No new error modes.

## References

### Internal References
- Agent routes: `/Users/renaka/gtx/clob-indexer/api/src/routes/agents.routes.ts`
- Agent service: `/Users/renaka/gtx/clob-indexer/api/src/services/agents.service.ts`
- Ponder schema: `/Users/renaka/gtx/clob-indexer/ponder/ponder.schema.ts:1319-1570`
- AgentCard: `/Users/renaka/gtx/frontend/apps/web/src/features/agents/components/AgentCard.tsx`
- AgentDetail: `/Users/renaka/gtx/frontend/apps/web/src/features/agents/components/AgentDetail.tsx`
- Prediction component: `/Users/renaka/gtx/frontend/apps/web/src/features/predictions/components/predictions.tsx`
- Brainstorm: `docs/brainstorms/2026-03-05-agent-prediction-api-frontend-brainstorm.md`

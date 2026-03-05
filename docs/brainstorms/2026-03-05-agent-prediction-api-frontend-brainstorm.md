# Agent Prediction API + Frontend Integration

**Date:** 2026-03-05
**Status:** Ready for planning

## What We're Building

Surface agent prediction data (already indexed by ponder) through the API layer and frontend. Three workstreams:

1. **API**: Add prediction stats to agent endpoints + new `/predictions` endpoint per agent
2. **Agent UI**: Show prediction stats on agent cards and detail page
3. **Prediction Market UI**: Enrich prediction events with agent identity badges

## Why This Approach

The data pipeline is complete — `agentPredictionEvents` table and `agentStats.totalPredictions/totalPredictionVolume/totalPredictionClaims` columns are already populated by the indexer. We just need to expose and display them.

## Key Decisions

1. **Full integration scope** — API + agent detail + prediction market enrichment
2. **Agent badge on predictions** — Show agent badge/tag next to agent-made predictions in market detail view (e.g. "Predicted UP by Agent #1428 (SmartMoneyTracker)")
3. **Follow existing patterns** — Elysia routes/services for API, React Query hooks + TanStack Router for frontend

## Architecture

### API Changes (clob-indexer/api)

**Modify `agents.service.ts`:**
- Include `totalPredictions`, `totalPredictionVolume`, `totalPredictionClaims` in agent stats queries (they already exist in `agent_stats` table)

**Add new endpoint:**
- `GET /api/agents/:agentTokenId/predictions` — Query `agent_prediction_events` table filtered by agentTokenId, join with `prediction_markets` for market context
- Response: `{ predictions: AgentPredictionEvent[], count: number }`
- Support pagination (limit/offset) and action filter (PREDICT/CLAIM)

**Modify Ponder prediction API (`ponder/src/api/index.ts`):**
- Enrich `GET /api/predictions/events/:marketId` responses with agent identity when `agentTokenId` is present in event data
- Or: add `agentTokenId` field to prediction events response if the prediction was agent-initiated

### Frontend Changes (frontend/apps/web)

**Agent feature (`features/agents/`):**
- Update `AgentCard.tsx` — show prediction count + volume in stats row
- Update `AgentDetail.tsx` — add Predictions tab/section
- Add `AgentPredictionsTable.tsx` — table of prediction events (market, direction, amount, outcome)
- Add `useAgentPredictions(agentTokenId)` hook

**Prediction feature (`features/predictions/`):**
- Update prediction event list in market detail to show agent badge when prediction was made by an agent
- Badge shows agent name/ID linking to agent detail page

## Data Sources

| Data | Table | Already Indexed? |
|------|-------|-----------------|
| Agent prediction count | `agent_stats.totalPredictions` | Yes |
| Agent prediction volume | `agent_stats.totalPredictionVolume` | Yes |
| Agent claim count | `agent_stats.totalPredictionClaims` | Yes |
| Prediction event history | `agent_prediction_events` | Yes |
| Market context for events | `prediction_markets` | Yes |

## Open Questions

None — all data is already indexed, patterns are established.

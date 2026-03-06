---
title: "feat: Enrich overview page with lending and prediction platform data"
type: feat
status: completed
date: 2026-03-06
brainstorm: docs/brainstorms/2026-03-06-overview-lending-prediction-enrichment-brainstorm.md
---

# feat: Enrich overview page with lending and prediction platform data

## Overview

Add platform-wide lending and prediction data to the frontend overview page, integrated into existing sections. Currently the overview only shows trading data (volume, liquidity, markets, leaderboards). After this change, visitors see the full breadth of platform activity across trading, lending, and predictions in a single scroll.

## Problem Statement / Motivation

The overview page gives an incomplete picture of the platform. Lending and prediction features exist but are invisible unless users navigate to those pages. This makes the platform appear smaller than it is and reduces discovery of lending/prediction features.

## Proposed Solution

Integrate lending and prediction data into existing overview sections rather than adding tabs or separate pages:

1. **Expand PlatformStats** with lending + prediction metric cards (single scrollable row)
2. **Add Active Prediction Markets** section near TrendingMarkets
3. **Add Top Lending Pools** section near TopOpportunities
4. **Add Recently Settled Predictions** section showing outcomes
5. **Create new backend endpoint** `GET /api/lending/stats` for platform-wide lending aggregates

## Technical Approach

### Architecture

**Data flow:**
```
pool_lending_stats table (Ponder DB)
  └─> GET /api/lending/stats (Elysia API, port 3000)
        └─> useLendingStats() hook (fetchAPI)
              └─> PlatformStats + TopLendingPools components

prediction_markets table (Ponder DB)
  ├─> GET /api/predictions/stats (Ponder API, port 42069) — EXISTS
  │     └─> usePredictionStats() hook (fetchIndexerAPI)
  │           └─> PlatformStats component
  └─> GET /api/predictions/markets (Ponder API) — EXISTS
        └─> usePredictionMarkets() hook (fetchIndexerAPI) — EXISTS
              └─> ActivePredictions + RecentlySettled components
```

### Implementation Phases

#### Phase 1: Backend — Lending Stats Endpoint

**File:** `/Users/renaka/gtx/clob-indexer/api/src/routes/lending.routes.ts`

Add `GET /api/lending/stats?chainId=` endpoint that aggregates `pool_lending_stats` table data. Place it in the Elysia API server (consistent with existing `/api/lending/dashboard/:user` route).

**Response contract:**
```typescript
interface LendingStatsResponse {
  totalSupply: string;      // sum of all pool totalSupply (bigint as string)
  totalBorrow: string;      // sum of all pool totalBorrow (bigint as string)
  bestSupplyAPY: number;    // max supplyRate / 100 across pools
  activeLenders: number;    // sum of activeLenders
  activeBorrowers: number;  // sum of activeBorrowers
  pools: Array<{
    token: string;          // token address
    symbol: string;         // resolved symbol (e.g., "ETH", "USDC")
    totalSupply: string;
    totalBorrow: string;
    supplyRate: number;     // APY as percentage (supplyRate / 100)
    borrowRate: number;     // APY as percentage (borrowRate / 100)
    utilizationRate: number; // percentage (utilizationRate / 10000)
  }>;
}
```

**SQL query pattern** (following existing `runQuery` helper):
```sql
SELECT token, total_supply, total_borrow, supply_rate, borrow_rate,
       utilization_rate, active_lenders, active_borrowers
FROM pool_lending_stats
WHERE chain_id = $1
ORDER BY supply_rate DESC
```

**Token symbol resolution:** Join with `currencies` table (same pattern as existing lending dashboard route, line ~200 of `lending.routes.ts`).

- [x] Add `GET /api/lending/stats` route to `lending.routes.ts`
- [x] Query `pool_lending_stats` table with `chainId` filter
- [x] Aggregate totals (totalSupply, totalBorrow, bestSupplyAPY)
- [x] Resolve token symbols via `currencies` table
- [x] Return pools sorted by supplyRate descending

#### Phase 2: Frontend Hooks

**New file:** `/Users/renaka/gtx/frontend/apps/web/src/features/lending/hooks/useLendingStats.ts`

```typescript
// Uses fetchAPI (Elysia API at port 3000, consistent with useLendingDashboard)
export function useLendingStats({ chainId }: { chainId?: number } = {}) {
  return useQuery<LendingStatsResponse>({
    queryKey: ['lendingStats', chainId],
    queryFn: () => fetchAPI<LendingStatsResponse>(
      `/lending/stats${chainId ? `?chainId=${chainId}` : ''}`
    ),
    staleTime: 15_000,
    refetchInterval: 30_000,
  });
}
```

**New file:** `/Users/renaka/gtx/frontend/apps/web/src/features/predictions/hooks/usePredictionStats.ts`

```typescript
// Uses fetchIndexerAPI (Ponder API, consistent with usePredictionMarkets)
export function usePredictionStats({ chainId }: { chainId?: number } = {}) {
  return useQuery<PredictionStatsResponse>({
    queryKey: ['predictionStats', chainId],
    queryFn: () => fetchIndexerAPI<PredictionStatsResponse>(
      `/api/predictions/stats${chainId ? `?chainId=${chainId}` : ''}`
    ),
    staleTime: 15_000,
    refetchInterval: 30_000,
  });
}
```

**Types to add** in `lending.types.ts`:
```typescript
export interface LendingStatsResponse {
  totalSupply: string;
  totalBorrow: string;
  bestSupplyAPY: number;
  activeLenders: number;
  activeBorrowers: number;
  pools: LendingPoolStat[];
}

export interface LendingPoolStat {
  token: string;
  symbol: string;
  totalSupply: string;
  totalBorrow: string;
  supplyRate: number;
  borrowRate: number;
  utilizationRate: number;
}
```

**Types to add** in `prediction.types.ts`:
```typescript
export interface PredictionStatsResponse {
  totalMarkets: number;
  activeMarkets: number;
  settledMarkets: number;
  cancelledMarkets: number;
  totalVolumeUp: string;
  totalVolumeDown: string;
  uniqueParticipants: number;
}
```

- [x] Create `useLendingStats.ts` hook
- [x] Create `usePredictionStats.ts` hook
- [x] Add `LendingStatsResponse` and `LendingPoolStat` types to `lending.types.ts`
- [x] Add `PredictionStatsResponse` type to `prediction.types.ts`

#### Phase 3: Expand PlatformStats Component

**File:** `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/marketplace/PlatformStats.tsx`

**Changes:**
1. Accept new props: `lendingStats`, `predictionStats`, `lendingLoading`, `predictionLoading`
2. Add 4 new stat cards: Total Supplied, Total Borrowed, Best Supply APY, Active Predictions
3. Change grid layout from `grid grid-cols-2 lg:grid-cols-4` to a single scrollable row: `flex gap-4 overflow-x-auto` with `min-w-[200px]` per card
4. Each card's loading state is independent (trading cards load from `isLoading`, lending cards from `lendingLoading`, prediction cards from `predictionLoading`)

**New stat cards:**
| Label | Value Source | Icon | Format |
|-------|-------------|------|--------|
| Total Supplied | `lendingStats.totalSupply` | `Vault` | `formatNumber()` with $ |
| Total Borrowed | `lendingStats.totalBorrow` | `ArrowDownRight` | `formatNumber()` with $ |
| Best Supply APY | `lendingStats.bestSupplyAPY` | `Percent` | `X.XX%` |
| Active Predictions | `predictionStats.activeMarkets` | `Target` | integer |

- [x] Update `PlatformStatsProps` interface with lending/prediction data
- [x] Add 4 new stat cards with appropriate icons from `lucide-react`
- [x] Change layout to `flex gap-4 overflow-x-auto` with `min-w-[200px]` per card
- [x] Add scrollbar hiding CSS (`scrollbar-hide` or `-webkit-scrollbar: none`)
- [x] Independent loading states per data source

#### Phase 4: Active Prediction Markets Section

**New file:** `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/marketplace/ActivePredictions.tsx`

Follows `TrendingMarkets.tsx` section header pattern. Shows open prediction markets with:
- Token pair and market type (Directional/Absolute)
- Pool split bar (UP vs DOWN stake ratio) — reuse `computePoolPcts` from `predictions/utils/tokens.ts`
- Relative countdown timer ("2h 15m left") — reuse `CountdownTimer` component from predictions
- Total stake amount in collateral token (e.g., "1,250 USDC")
- Click navigates to `/predictions`
- "View All" link to `/predictions`
- Client-side filter: only show markets where `endTime > Math.floor(Date.now() / 1000)` to exclude markets that have ended but aren't settled yet
- Show up to 6 markets, sorted by total stake descending
- Empty state: "No active prediction markets" with CTA to view all

**Data source:** Reuse existing `usePredictionMarkets({ status: MarketStatus.Open, limit: 10 })` — note status must be numeric `0`, not string "Open"

- [x] Create `ActivePredictions.tsx` with section header pattern
- [x] Create `PredictionCard` sub-component with pool bar, countdown, stakes
- [x] Client-side filter for `endTime > now`
- [x] Grid layout: `grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4` (matches TrendingMarkets)
- [x] Loading skeleton matching card layout
- [x] Empty state component

#### Phase 5: Top Lending Pools Section

**New file:** `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/marketplace/TopLendingPools.tsx`

Follows `TopOpportunities.tsx` `OpportunityCard` pattern. Single card showing top lending pools ranked by supply APY.

**Card structure:**
- Title: "Top Lending Pools" with `Landmark` icon
- Subtitle: "Highest earning opportunities"
- List of top 5 pools, each showing:
  - Token icon (`TokenIcon` component) + symbol
  - Supply APY (green text)
  - Borrow APY
  - Utilization bar
- "View All" link to `/lending`

**Data source:** `useLendingStats()` — pools are already sorted by supplyRate descending from the API

- [x] Create `TopLendingPools.tsx` following OpportunityCard pattern
- [x] Show top 5 pools from `lendingStats.pools`
- [x] Display supply APY, borrow APY, utilization for each pool
- [x] Use `TokenIcon` for asset display
- [x] "View All" link to `/lending`
- [x] Loading skeleton and empty state

#### Phase 6: Recently Settled Predictions Section

**New file:** `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/marketplace/RecentlySettled.tsx`

Compact section showing last 5 settled prediction markets with outcomes.

**Card structure:**
- Token pair + market type
- Outcome indicator: "UP Won" (green) or "DOWN Won" (red)
- Settlement time (relative: "2h ago")
- Total payout amount
- Click navigates to `/predictions`

**Data source:** `usePredictionMarkets({ status: MarketStatus.Settled, limit: 5 })`

- [x] Create `RecentlySettled.tsx` component
- [x] Show outcome badge (UP Won / DOWN Won) with color coding
- [x] Relative settlement time display
- [x] Grid layout: `grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4`
- [x] Loading skeleton and empty state

#### Phase 7: Wire Up OverviewNew.tsx

**File:** `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/OverviewNew.tsx`

Add data fetching hooks and new sections to the main overview component.

```typescript
// New imports
import { useLendingStats } from "@/features/lending/hooks/useLendingStats";
import { usePredictionStats } from "@/features/predictions/hooks/usePredictionStats";
import { usePredictionMarkets } from "@/features/predictions/hooks/usePredictionMarkets";
import { MarketStatus } from "@/features/predictions/types/prediction.types";
import ActivePredictions from "./marketplace/ActivePredictions";
import TopLendingPools from "./marketplace/TopLendingPools";
import RecentlySettled from "./marketplace/RecentlySettled";
```

**Updated section order:**
1. Header
2. PlatformStats (expanded with lending + prediction props)
3. TrendingMarkets
4. **ActivePredictions** ← NEW
5. TopOpportunities
6. **TopLendingPools** ← NEW
7. **RecentlySettled** ← NEW
8. TopAgentsSpotlight
9. Leaderboards
10. MarketsTable
11. Footer

- [x] Add `useLendingStats()` and `usePredictionStats()` hooks to OverviewNew
- [x] Add `usePredictionMarkets` calls for active and settled markets
- [x] Pass lending/prediction data to expanded `PlatformStats`
- [x] Add ActivePredictions, TopLendingPools, RecentlySettled sections
- [x] Update header subtitle: "Explore markets, lending pools, predictions, and start trading."

#### Phase 8: Mobile Support

**File:** `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/OverviewMobile.tsx`

Add condensed versions of new sections to mobile layout:
- PlatformStats: expand from 2 to 4 cards in `grid-cols-2` (add Total Supplied, Active Predictions)
- Active Predictions: horizontal scroll card list (like existing TrendingMarkets mobile)
- Top Lending Pools: compact list (3 pools)
- Recently Settled: skip on mobile (keep it lean)

- [x] Add lending/prediction hooks to OverviewMobile
- [x] Expand mobile stat cards
- [x] Add mobile prediction markets horizontal scroll
- [x] Add compact lending pools list

## Acceptance Criteria

### Functional Requirements

- [ ] Overview page shows 8 stat cards: 24h Volume, Total Liquidity, Active Markets, 24h Trades, Total Supplied, Total Borrowed, Best Supply APY, Active Predictions
- [ ] PlatformStats is horizontally scrollable on narrow viewports, all cards visible on desktop
- [ ] Active Prediction Markets section shows open markets with countdown timers, stakes, and pool bars
- [ ] Markets with `endTime` in the past are filtered out client-side
- [ ] Countdown timers show relative time ("2h 15m left")
- [ ] Top Lending Pools section shows pools sorted by supply APY with rates
- [ ] Recently Settled section shows last 5 settled markets with outcomes
- [ ] All new sections have "View All" links to their respective pages
- [ ] Clicking prediction cards navigates to `/predictions`
- [ ] Clicking lending pool items navigates to `/lending`
- [ ] Mobile overview shows condensed versions of new sections
- [ ] All sections have proper loading skeletons and empty states
- [ ] `GET /api/lending/stats?chainId=` returns platform-wide aggregates

### Non-Functional Requirements

- [ ] All new hooks use `staleTime: 15_000, refetchInterval: 30_000` for consistency
- [ ] Each data source loads independently (lending failure doesn't block prediction display)
- [ ] No user address required for any overview data
- [ ] Token symbols display consistently across trading/lending/prediction sections

## Dependencies & Risks

- **Backend dependency:** Phase 1 (lending stats endpoint) must complete before Phase 5 (TopLendingPools) can show real data. Other phases can proceed in parallel with mock data.
- **Risk: Empty data on testnet.** Base Sepolia may have few lending pools or prediction markets. Plan for empty states to look good.
- **Risk: `pool_lending_stats` table may have stale data.** The Ponder indexer must be syncing lending events for stats to be accurate. Verify indexer is running.

## References & Research

### Internal References
- Current overview: `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/OverviewNew.tsx`
- PlatformStats component: `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/marketplace/PlatformStats.tsx`
- TrendingMarkets pattern: `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/marketplace/TrendingMarkets.tsx`
- TopOpportunities pattern: `/Users/renaka/gtx/frontend/apps/web/src/features/overview/components/marketplace/TopOpportunities.tsx`
- Lending dashboard route: `/Users/renaka/gtx/clob-indexer/api/src/routes/lending.routes.ts`
- Prediction stats endpoint: `/Users/renaka/gtx/clob-indexer/ponder/src/api/index.ts:4778`
- Prediction markets hook: `/Users/renaka/gtx/frontend/apps/web/src/features/predictions/hooks/usePredictionMarkets.ts`
- CountdownTimer: `/Users/renaka/gtx/frontend/apps/web/src/features/predictions/components/CountdownTimer.tsx`
- Token utils: `/Users/renaka/gtx/frontend/apps/web/src/features/predictions/utils/tokens.ts`
- Pool lending stats schema: `/Users/renaka/gtx/clob-indexer/ponder/ponder.schema.ts:1058`
- Lending types: `/Users/renaka/gtx/frontend/apps/web/src/features/lending/types/lending.types.ts`
- Prediction types: `/Users/renaka/gtx/frontend/apps/web/src/features/predictions/types/prediction.types.ts`
- fetchAPI client: `/Users/renaka/gtx/frontend/apps/web/src/hooks/fetchAPI.ts`
- fetchIndexerAPI client: `/Users/renaka/gtx/frontend/apps/web/src/hooks/fetchIndexerAPI.ts`

### Key Design Decisions
- Lending stats endpoint in Elysia API (not Ponder) — consistent with existing lending route
- Frontend uses `fetchAPI` for lending stats, `fetchIndexerAPI` for prediction stats — matches existing patterns
- Prediction status filter uses numeric values (0=Open, 2=Settled), not strings
- Supply/borrow rates are APY (supplyRate / 100), utilization is percentage (utilizationRate / 10000)
- Stake amounts displayed in collateral token units (USDC), not USD

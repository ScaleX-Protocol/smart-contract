# Overview Page: Lending & Prediction Data Enrichment

**Date:** 2026-03-06
**Status:** Draft

## What We're Building

Enhance the frontend overview page to display platform-wide lending and prediction data, integrated naturally into the existing layout. Currently the overview only shows trading data (volume, liquidity, markets, leaderboards). We want visitors to see the full breadth of platform activity across all three product areas: trading, lending, and predictions.

## Why This Approach

**Integrated layout** — Rather than tabs or separate sections, we weave lending and prediction data into existing overview sections. This keeps the page feeling unified and avoids hiding data behind clicks. Users see the full platform picture in a single scroll.

## Key Decisions

### Lending Data — Comprehensive
- **PlatformStats expansion:** Add Total Supplied, Total Borrowed, and average/best APY stat cards alongside existing trading stats (24h Volume, Total Liquidity, Active Markets, 24h Trades)
- **Top Lending Pools card:** Add alongside TopOpportunities section, showing highest-APY or most-liquid lending pools with their rates
- **Interest rate info:** Display per-asset rate information in the pools card

### Prediction Data — Comprehensive
- **PlatformStats expansion:** Add Active Prediction Markets count and Total Staked volume
- **Active/Upcoming Markets section:** Show active prediction markets near TrendingMarkets, with stakes and countdown timers
- **Recently Settled section:** Show recent outcomes to demonstrate platform activity
- **No agent prediction stats** — Keep prediction section focused on market data only

### Backend Changes
- **New `/api/lending/stats` endpoint:** Platform-wide aggregate lending stats (total supplied, total borrowed, pool stats, rates) without requiring a user address
- Keep existing `/lending/dashboard/:user` endpoint for future personal data use

### Data Sources
| Data | Source | Endpoint |
|------|--------|----------|
| Lending platform stats | New endpoint | `GET /api/lending/stats` |
| Lending pool rates | New endpoint | `GET /api/lending/stats` (includes per-pool data) |
| Prediction markets (active) | Existing | `GET /api/predictions/markets?status=Open` |
| Prediction markets (settled) | Existing | `GET /api/predictions/markets?status=Settled&limit=5` |
| Trading stats | Existing | `GET /ticker/24hr/all`, `GET /markets` |

### Frontend Patterns
- Use existing `@tanstack/react-query` patterns with `useQuery`
- New hook: `useLendingStats()` calling `fetchAPI` (main API server)
- Reuse existing `usePredictionMarkets()` hook from predictions feature
- Follow component patterns in `OverviewNew.tsx` and marketplace components

## Layout Flow (Updated)

1. **Header** — title "Overview"
2. **PlatformStats** — expanded to ~6-8 cards: 24h Volume, Total Liquidity, Active Markets, 24h Trades, **Total Supplied, Total Borrowed, Best Supply APY, Active Predictions**
3. **TrendingMarkets** — existing trading markets
4. **Active Prediction Markets** — new section near TrendingMarkets showing open/upcoming markets with stakes and timers
5. **TopOpportunities** — existing (Top Gainers, Highest Volume, Most Liquid)
6. **Top Lending Pools** — new card alongside TopOpportunities showing best-APY pools with rates
7. **Recently Settled Predictions** — recent outcomes with results
8. **TopAgentsSpotlight** — existing
9. **Leaderboards** — existing
10. **MarketsTable** — existing
11. **Footer** — existing

## Resolved Questions

1. **PlatformStats layout:** Single scrollable row — horizontally scroll on smaller screens, keeps clean single-row look
2. **Prediction countdown format:** Relative time ("2h 15m left") — conveys urgency immediately
3. **Lending stats endpoint scope:** Chain-specific with `?chainId=` param — consistent with other endpoints, supports multi-chain future

## Out of Scope

- User-specific portfolio/positions on overview (future enhancement)
- Agent prediction activity stats on overview
- Prediction market creation from overview
- Lending actions from overview (supply/borrow CTAs)

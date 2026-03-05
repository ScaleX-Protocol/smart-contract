# Agent Prediction Integration Brainstorm

**Date:** 2026-03-05
**Status:** Ready for planning

## What We're Building

Add prediction market support to the ERC-8004 agent system, allowing agents to predict on behalf of users (delegated) and on their own behalf (self-funded). This follows the exact same patterns used for trading and lending integration.

### Scope

1. **PolicyFactory** - Add prediction permission fields to Policy struct
2. **AgentRouter** - Add delegated + self-funded prediction functions (predict, claim)
3. **AgentRouter Events** - New agent prediction events with `strategyAgentId` + `executor`
4. **Reputation** - Record predictions to reputation registry
5. **Indexer** - New event types, handlers, and DB schema for agent prediction events
6. **PricePrediction** - Add `predictFor(address user, ...)` function so AgentRouter can predict on behalf of users

## Why This Approach

**AgentRouter emits its own events** (not modifying PricePrediction's Predicted event):
- Matches existing trading/lending pattern exactly
- PricePrediction contract stays clean and generic
- Agent-specific indexing is separate from base prediction indexing
- Easier to maintain and extend

**Agent can claim on behalf of users**:
- Complete agent lifecycle: predict -> wait -> claim
- Matches how agents handle full trading/lending flows
- Users don't need to manually claim if they delegated to an agent

## Key Decisions

1. **Policy fields**: `allowPredict`, `allowClaimPrediction`, `maxPredictionStake` (per-prediction cap)
2. **Event pattern**: AgentRouter emits `AgentPredictionPlaced`, `AgentPredictionClaimed`, `AgentSelfPredictionPlaced`, `AgentSelfPredictionClaimed`
3. **Reputation tags**: `("trade", "predict")` for predictions, `("trade", "claim_prediction")` for claims
4. **PricePrediction change needed**: Add `predictFor(address user, uint64 marketId, bool predictUp, uint256 amount)` and `claimFor(address user, uint64 marketId)` - AgentRouter calls these instead of `predict()` directly (since `predict()` uses `msg.sender` as the user)
5. **No circuit breaker for predictions**: Predictions are fixed-outcome binary bets, not continuous positions. Circuit breaker drawdown logic doesn't apply.
6. **Template updates**: Add prediction permissions to Conservative/Moderate/Aggressive templates

## Functions to Add

### AgentRouter - Delegated (user's funds)

```solidity
function executePredict(
    address user, uint256 strategyAgentId,
    uint64 marketId, bool predictUp, uint256 amount
) external

function executeClaimPrediction(
    address user, uint256 strategyAgentId, uint64 marketId
) external
```

### AgentRouter - Self-funded (agent's funds)

```solidity
function selfPredict(
    uint256 strategyAgentId,
    uint64 marketId, bool predictUp, uint256 amount
) external

function selfClaimPrediction(
    uint256 strategyAgentId, uint64 marketId
) external
```

### PricePrediction - Router support

```solidity
function predictFor(address user, uint64 marketId, bool predictUp, uint256 amount) external
function claimFor(address user, uint64 marketId) external
```

## Events to Add

```solidity
// Delegated
event AgentPredictionPlaced(address indexed user, uint256 indexed strategyAgentId, address indexed executor, uint64 marketId, bool predictUp, uint256 amount, uint256 timestamp);
event AgentPredictionClaimed(address indexed user, uint256 indexed strategyAgentId, address indexed executor, uint64 marketId, uint256 payout, uint256 timestamp);

// Self-funded
event AgentSelfPredictionPlaced(uint256 indexed strategyAgentId, address indexed agentWallet, uint64 marketId, bool predictUp, uint256 amount);
event AgentSelfPredictionClaimed(uint256 indexed strategyAgentId, address indexed agentWallet, uint64 marketId, uint256 payout);
```

## Indexer Changes

- Add 4 new PonderEvents constants
- Add 4 new handler functions in `agentRouterHandler.ts`
- Add DB schema for agent prediction events (or extend existing agent_events table)
- Wire up in `index.core-chain.ts`

## Open Questions

None - all decisions resolved.

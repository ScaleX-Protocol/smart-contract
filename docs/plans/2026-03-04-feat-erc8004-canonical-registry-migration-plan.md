---
title: "feat: Migrate ERC-8004 to Canonical Registries for 8004scan Indexing"
type: feat
status: active
date: 2026-03-04
deepened: 2026-03-04
brainstorm: docs/brainstorms/2026-03-04-erc8004-canonical-migration-brainstorm.md
---

# feat: Migrate ERC-8004 to Canonical Registries for 8004scan Indexing

## Enhancement Summary

**Deepened on:** 2026-03-04
**Sections enhanced:** All 5 phases + new sections
**Research agents used:** Security Sentinel, Architecture Strategist, Code Simplicity Reviewer, Deployment Verification Agent, Performance Oracle, Pattern Recognition Specialist, Data Integrity Guardian, Best Practices Researcher

### Key Improvements

1. **Fix function names**: `setAuthorizedRouter(address, true)` not `authorizeRouter()`, `addAuthorizedOperator()` not `authorize()` (Architecture Strategist, Pattern Recognition)
2. **Wrap reputation calls in try/catch**: `giveFeedback()` must not revert the entire trade if it fails (Security, Performance, Simplicity - unanimous P0)
3. **Add old AgentRouter deauthorization step**: Old router must be removed from BalanceManager and all 8 OrderBooks (Data Integrity Guardian)
4. **Validation interface fix is dead code**: `_getPortfolioValue()` returns 0 so circuit breaker never triggers - skip validation fix (Code Simplicity Reviewer)
5. **Add `registrations` array to metadata**: Two-step process required for 8004scan verification loop (Best Practices Researcher)
6. **int128 overflow guard**: PnL cast `int128(int256(...))` can silently truncate (Security Sentinel)
7. **Consider splitting into 2 PRs**: PR1 = migration only (minimum for 8004scan), PR2 = reputation recording fix (Code Simplicity Reviewer)

### New Considerations Discovered

- **credential.txt in repo root** contains hardcoded credentials - must be gitignored immediately (Security Sentinel - CRITICAL)
- **PnL calculation is semantically wrong**: `amountOut - amountIn` compares raw amounts of different tokens with different decimals (Performance Oracle)
- **Indexer needs agent whitelist filter**: Canonical registry has 10+ agents from other projects; indexer should filter to only our agents (Performance Oracle)
- **OrderBook stores `agentTokenId`**: Hidden dependency - new canonical token IDs will be different from old ones (Architecture Strategist)
- **`.well-known/agent-registration.json`** should be hosted on `agent.scalex.money` for domain verification (Best Practices Researcher)

---

## Overview

Fresh deployment of the agent system pointing to **canonical ERC-8004 registries** (vanity `0x8004...` addresses) on Base Sepolia so that all agents appear on [testnet.8004scan.io](https://testnet.8004scan.io/). This includes fixing the broken Reputation interface, fresh deployment of AgentRouter and PolicyFactory, registering agents on canonical registry, updating the indexer and frontend, and making agent metadata ERC-8004 compliant.

## Problem Statement

Our 7 agents are registered on custom registry instances (`0xC2A6...`) that 8004scan does not index. The canonical registries at `0x8004A...`, `0x8004B...`, `0x8004C...` are what 8004scan watches. Additionally, the `IERC8004Reputation` interface in AgentRouter is broken:
- `IERC8004Reputation.submitFeedback()` does not exist on the canonical `ReputationRegistryUpgradeable` (uses `giveFeedback()`)

> **Note:** The `IERC8004Validation` interface is also broken (`requestValidation()` vs `validationRequest()`), but `_getPortfolioValue()` always returns 0, making the circuit breaker dead code. Validation fix is deferred.

## Proposed Solution

**Fresh deployment** of AgentRouter and PolicyFactory pointing to canonical registries from the start (no upgrade of existing contracts). Fix the broken reputation interface, register agents on canonical registry, and update all downstream systems.

### Recommended PR Split (from Code Simplicity Reviewer)

| PR | Scope | Goal |
|----|-------|------|
| **PR1: Migration** | Phases 1-5 below (but reputation calls wrapped in try/catch with existing broken interface temporarily) | Agents appear on 8004scan |
| **PR2: Reputation Fix** | Fix `IERC8004Reputation`, update `_recordTradeToReputation()`, deploy upgraded implementation | Reputation data flows to 8004scan |

This split isolates the migration risk from the reputation interface change. PR1 can be deployed and verified on 8004scan before touching reputation logic. If you prefer a single PR, the phases below work as-is.

## Technical Approach

### Architecture

```
Fresh Deployment:
AgentRouter (NEW) --> Canonical Identity  (0x8004A818BFB912233c491871b3d84c89A494BD9e)
                  --> Canonical Reputation (0x8004B663056A597Dffe9eCcC1965A193B7388713)
                  --> Canonical Validation (0x8004Cb1BF31DAf7788923b405b754f57acEB4272)
PolicyFactory (NEW) --> Canonical Identity (0x8004A818BFB912233c491871b3d84c89A494BD9e)
```

Old contracts at `0xE9c1...` (AgentRouter) and `0x8ea2...` (PolicyFactory) are abandoned and **deauthorized** from BalanceManager and all OrderBooks.

### Implementation Phases

#### Phase 1: Fix Contract Interfaces

**Goal:** Fix the broken reputation interface so contracts work against canonical registries.

##### 1.1 Fix `IERC8004Reputation` Interface

**File:** `src/ai-agents/interfaces/IERC8004Reputation.sol`

Replace the entire interface. Remove:
- `enum FeedbackType` (TRADE_EXECUTION, BORROW, REPAY, etc.)
- `struct Feedback` (custom struct)
- `submitFeedback(uint256, FeedbackType, bytes)`
- `getScore(uint256)`, `getMetrics(uint256)`, `getFeedbackHistory(uint256, uint256, uint256)`

Add canonical interface (minimal - only what AgentRouter calls):
```solidity
interface IERC8004Reputation {
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;
}
```

> **Research Insight (Code Simplicity):** Only `giveFeedback()` is needed. Remove `getSummary()` and `getIdentityRegistry()` - AgentRouter never calls them.

##### 1.2 Skip `IERC8004Validation` Interface Fix

> **Research Insight (Code Simplicity):** `_getPortfolioValue()` at `AgentRouter.sol:725-727` returns 0 (TODO comment). The circuit breaker at line ~713 checks `portfolioValue < threshold` which is `0 < threshold` = always true, so `requestValidation()` is never reached. This is dead code. Defer validation fix to a future PR when `_getPortfolioValue()` is implemented.

##### 1.3 Update AgentRouter Reputation Recording

**File:** `src/ai-agents/AgentRouter.sol` (lines 740-769)

Replace `_recordTradeToReputation()`:
```solidity
function _recordTradeToReputation(
    uint256 strategyAgentId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut
) internal {
    // Bounds check: prevent int128 overflow on narrowing cast
    int256 pnlRaw = int256(amountOut) - int256(amountIn);
    int128 pnl = int128(pnlRaw);
    require(int256(pnl) == pnlRaw, "PnL overflow");

    // MUST NOT revert the trade if reputation recording fails
    try IERC8004Reputation(getStorage().reputationRegistry).giveFeedback(
        strategyAgentId,
        pnl,
        18, // valueDecimals
        "trade",   // tag1
        "swap",    // tag2
        "",        // endpoint
        "",        // feedbackURI
        bytes32(0) // feedbackHash
    ) {} catch {
        // Silently continue - reputation is non-critical
        // Consider emitting an event for debugging:
        // emit ReputationRecordingFailed(strategyAgentId);
    }
}
```

> **Research Insights:**
> - **Security Sentinel + Performance Oracle + Code Simplicity (unanimous P0):** Wrap in `try/catch`. If `giveFeedback()` reverts (e.g., self-feedback guard), it must NOT fail the entire trade.
> - **Security Sentinel:** `int128(int256(...))` is an unchecked narrowing cast. Add bounds check.
> - **Performance Oracle:** `giveFeedback()` costs ~65,000-90,000 gas per trade. Acceptable but adds ~15% to swap gas costs.
> - **Performance Oracle:** PnL calculation `amountOut - amountIn` is semantically wrong when tokens have different decimals (e.g., USDC 6 decimals vs WETH 18 decimals). This produces garbage data. Consider normalizing to a common base or using `tag1="revenues"` with USD-denominated values. **Defer to PR2.**
> - **Best Practices Researcher:** Consider using spec-native tags like `tag1="revenues"` instead of `tag1="trade"` for better 8004scan aggregation.

Similarly update `_recordBorrowToReputation()` (tag2="borrow") and `_recordRepayToReputation()` (tag2="repay") with the same try/catch pattern.

##### 1.4 Update MockERC8004Reputation

**File:** `src/ai-agents/mocks/MockERC8004Reputation.sol`

Update mock to implement the new `giveFeedback()` interface for test compatibility.

##### 1.5 Update Tests

**File:** `test/ai-agents/AgentRouter.t.sol`

Update all test calls to match new reputation signatures. Update mock deployments accordingly.

**Deliverable:** All contracts compile, all tests pass.

---

#### Phase 2: Fresh Deployment

**Goal:** Deploy new AgentRouter and PolicyFactory pointing to canonical registries.

##### 2.1 Create Deployment Script

**File:** `script/deployments/DeployCanonicalAgentRouter.s.sol` (new)

Based on existing `DeployPhase5.s.sol` pattern:

```solidity
// Use canonical registries (already deployed, not ours to deploy)
address canonicalIdentity   = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
address canonicalReputation = 0x8004B663056A597Dffe9eCcC1965A193B7388713;
address canonicalValidation = 0x8004Cb1BF31DAf7788923b405b754f57acEB4272;

// 1. Deploy PolicyFactory (Beacon proxy)
PolicyFactory policyImpl = new PolicyFactory();
UpgradeableBeacon policyBeacon = new UpgradeableBeacon(address(policyImpl), deployer);
BeaconProxy policyProxy = new BeaconProxy(
    address(policyBeacon),
    abi.encodeCall(PolicyFactory.initialize, (deployer, canonicalIdentity))
);

// 2. Deploy AgentRouter (Beacon proxy)
AgentRouter routerImpl = new AgentRouter();
UpgradeableBeacon routerBeacon = new UpgradeableBeacon(address(routerImpl), deployer);
BeaconProxy routerProxy = new BeaconProxy(
    address(routerBeacon),
    abi.encodeCall(AgentRouter.initialize, (
        deployer,
        canonicalIdentity,
        canonicalReputation,
        canonicalValidation,
        address(policyProxy),
        poolManager,
        balanceManager,
        lendingManager
    ))
);

// 3. Authorize new AgentRouter in PolicyFactory
PolicyFactory(address(policyProxy)).setAuthorizedRouter(address(routerProxy), true);

// 4. Authorize new AgentRouter in BalanceManager
BalanceManager(balanceManager).addAuthorizedOperator(address(routerProxy));

// 5. Authorize new AgentRouter in all 8 OrderBooks
address[8] memory orderBooks = [...];
for (uint256 i = 0; i < orderBooks.length; i++) {
    PoolManager(poolManager).addAuthorizedRouterToOrderBook(orderBooks[i], address(routerProxy));
}

// 6. CRITICAL: Deauthorize OLD AgentRouter from BalanceManager + OrderBooks
BalanceManager(balanceManager).removeAuthorizedOperator(0xE9c1a6665364294194aa3B1CE89654926b338493);
for (uint256 i = 0; i < orderBooks.length; i++) {
    PoolManager(poolManager).removeAuthorizedRouterFromOrderBook(orderBooks[i], 0xE9c1a6665364294194aa3B1CE89654926b338493);
}
```

> **Research Insights:**
> - **Architecture Strategist + Pattern Recognition:** The actual function names are `setAuthorizedRouter(address, bool)` (not `authorizeRouter()`) and `addAuthorizedOperator()` (not `authorize()`). Verified in `DeployPhase5.s.sol:179,185`.
> - **Data Integrity Guardian (CRITICAL):** Old AgentRouter at `0xE9c1...` MUST be deauthorized from BalanceManager and all OrderBooks. If left authorized, it could still move funds.
> - **Pattern Recognition:** Deployment script should include a return struct, `_updateDeploymentJson()`, and JSON helper functions following existing `DeployPhase5.s.sol` patterns.
> - **Deployment Verification Agent:** Verify authorization with cast commands post-deployment (see Phase 5).

##### 2.2 Deploy on Base Sepolia

Run the deployment script. Record all new contract addresses.

##### 2.3 Update Deployment JSON

**File:** `deployments/84532.json`

Update with new addresses:
- `AgentRouter` (proxy + impl + beacon)
- `PolicyFactory` (proxy + impl + beacon)
- `IdentityRegistry` -> canonical `0x8004A...`
- `ReputationRegistry` -> canonical `0x8004B...`
- `ValidationRegistry` -> canonical `0x8004C...`

**Deliverable:** New contracts deployed, authorized, old contracts deauthorized, addresses recorded.

---

#### Phase 3: Agent Registration + Metadata

**Goal:** Register agents on canonical registry with ERC-8004 compliant metadata.

##### 3.1 Update Metadata JSON Files

Update the 7 agent metadata files on R2 (`agents.scalex.money/agents/{id}/metadata.json`) to ERC-8004 compliant format:

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
  "name": "Smart Money Tracker",
  "description": "Monitors whale wallet activity and mirrors their trades on Base Sepolia",
  "image": "https://agents.scalex.money/agents/1/avatar.png",
  "services": [
    { "name": "A2A", "endpoint": "https://agent.scalex.money/1/.well-known/agent-card.json", "version": "0.3.0" },
    { "name": "MCP", "endpoint": "https://agent.scalex.money/1/mcp", "version": "2025-06-18" },
    { "name": "web", "endpoint": "https://scalex.money/agents/1" }
  ],
  "active": true,
  "supportedTrust": ["reputation"],
  "updatedAt": 1709596800
}
```

> **Research Insights (Best Practices Researcher):**
> - Use `services` not `endpoints` (spec renamed in Jan 2026, `endpoints` triggers WA031 deprecation warning)
> - Add `"web"` service pointing to frontend agent page
> - Add `updatedAt` timestamp
> - `description` should be 50-500 chars for optimal 8004scan display
> - `image` should be 512x512 PNG/SVG/WebP
> - Set `x402Support: false` explicitly for testnet (our agents are DeFi trading agents, not API service agents)
> - Set R2 response headers: `Content-Type: application/json`, `Cache-Control: public, max-age=3600`, `Access-Control-Allow-Origin: *`

Upload via `rclone` or Cloudflare dashboard.

##### 3.2 Register Agents on Canonical Registry

**File:** Update `shellscripts/agents/register-showcase-agents.sh`

Update line 55:
```bash
IDENTITY_REGISTRY="0x8004A818BFB912233c491871b3d84c89A494BD9e"
```

Script calls `register(string agentURI)` from each agent wallet. **Capture new token IDs** from `Registered` event logs.

> **Research Insight (Best Practices):** Register from the agent wallet itself (not deployer EOA). The `register()` function mints to `msg.sender`. Your script already does this correctly using derived keys from `SEED_PHRASE`.

##### 3.3 Post-Registration: Update Metadata with `registrations` Array

> **Research Insight (Best Practices - MUST):** After registration, update each agent's metadata to include a `registrations` array for 8004scan verification loop:

```json
{
  "registrations": [
    {
      "agentId": 11,
      "agentRegistry": "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e"
    }
  ]
}
```

This is a **two-step process** (you can't know the token ID before registration):
1. Register agent -> get canonical token ID N
2. Update metadata JSON to include `registrations[].agentId: N`
3. Re-upload to R2

Without this field, agents appear on 8004scan but with reduced trust indicators.

##### 3.4 Verify Self-Feedback Guard

Verify that the new `AgentRouter` address is NOT an approved operator on any agent NFT in canonical registry:

```bash
# For each agent wallet
cast call 0x8004A818BFB912233c491871b3d84c89A494BD9e \
  "isApprovedForAll(address,address)(bool)" \
  $AGENT_WALLET $NEW_AGENT_ROUTER \
  --rpc-url https://sepolia.base.org
# Must return false for all agent wallets
```

> **Research Insight (Security + Best Practices - CRITICAL):** This is the #1 pitfall. If the AgentRouter is an approved operator on the IdentityRegistry for any agent NFT, ALL `giveFeedback()` calls from that router will revert with "Self-feedback not allowed". Since this is a fresh deployment and we never call `setApprovalForAll`, this should be safe - but verify.

##### 3.5 Set Up Agent Authorizations

For test users, call `authorize()` on new AgentRouter with new token IDs and policies.

##### 3.6 Optional: Host `.well-known/agent-registration.json`

> **Research Insight (Best Practices - SHOULD):** Since metadata is on `agents.scalex.money` but service endpoints are on `agent.scalex.money` (different subdomain), host a `.well-known/agent-registration.json` on `agent.scalex.money` for domain verification:

```json
{
  "registrations": [
    { "agentId": 11, "agentRegistry": "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e" },
    { "agentId": 12, "agentRegistry": "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e" }
  ]
}
```

**Deliverable:** 7 agents registered on canonical, metadata updated with `registrations`, authorized on new AgentRouter.

---

#### Phase 4: Indexer + Frontend Updates

##### 4.1 Update Indexer Environment

**File:** `../clob-indexer/ponder/.env.base-sepolia`

```bash
IDENTITYREGISTRY_CONTRACT_SCALEX_CORE_DEVNET_ADDRESS=0x8004A818BFB912233c491871b3d84c89A494BD9e
REPUTATIONREGISTRY_CONTRACT_SCALEX_CORE_DEVNET_ADDRESS=0x8004B663056A597Dffe9eCcC1965A193B7388713
VALIDATIONREGISTRY_CONTRACT_SCALEX_CORE_DEVNET_ADDRESS=0x8004Cb1BF31DAf7788923b405b754f57acEB4272
AGENTROUTER_CONTRACT_SCALEX_CORE_DEVNET_ADDRESS=<new AgentRouter proxy address>
POLICYFACTORY_CONTRACT_SCALEX_CORE_DEVNET_ADDRESS=<new PolicyFactory proxy address>
```

Update `SCALEX_CORE_DEVNET_START_BLOCK` to the deployment block.

> **Research Insight (Performance Oracle):** The canonical IdentityRegistry has 10+ agents from other projects. Your indexer should filter to only your agents by whitelisting known agent wallet addresses or token IDs, rather than indexing all agents on canonical. Add an `AGENT_WHITELIST` env var or filter in the event handler.

##### 4.2 Add ReputationRegistry to Ponder Config

**File:** `../clob-indexer/ponder/core-chain-ponder.config.ts`

Add `ReputationRegistry` contract entry with canonical address and ABI. Wire `NewFeedback`, `FeedbackRevoked`, `ResponseAppended` events.

> **Research Insight (Pattern Recognition):** Indexer needs 4 files updated: `core-chain-ponder.config.ts` (contract entry), `types.ts` (new types), `reputationRegistryHandler.ts` (new handler), `index.ts` (re-export).

##### 4.3 Add Reputation Event Handlers

**File:** `../clob-indexer/ponder/src/handlers/reputationRegistryHandler.ts` (new)

Handle `NewFeedback` events to populate reputation data (extend `agent_stats` or add `agent_reputation` table).

##### 4.4 Verify ABI Compatibility

Confirm canonical IdentityRegistry emits the same events (`Registered`, `URIUpdated`, `MetadataSet`) with identical indexed parameters as the custom registry. Both are based on the same `IdentityRegistryUpgradeable.sol` - should be identical.

##### 4.5 Update Frontend Contract Addresses

**File:** `../frontend/apps/web/src/configs/contracts.ts`

```typescript
agentRouterAddress: '<new AgentRouter proxy>' as HexAddress,
identityRegistryAddress: '0x8004A818BFB912233c491871b3d84c89A494BD9e' as HexAddress,
```

##### 4.6 Update scalex-8004

**File:** `../scalex-8004/src/register.ts`

Remove `registryOverrides` (or clear `IDENTITY_REGISTRY` / `REPUTATION_REGISTRY` env vars) so the Agent0 SDK uses canonical defaults.

Update `Agent Docs.md` with new contract addresses.

##### 4.7 Update Shell Scripts

**File:** `shellscripts/agents/register-showcase-agents.sh` (line 55)

```bash
IDENTITY_REGISTRY="0x8004A818BFB912233c491871b3d84c89A494BD9e"
```

**Deliverable:** Full stack pointing to canonical registries and new contracts.

---

#### Phase 5: Verification

##### 5.1 Deployment Verification Checklist

> **Research Insight (Deployment Verification Agent):** Run these cast verification commands:

```bash
# === GREEN: Verify new contracts ===

# New AgentRouter is authorized in BalanceManager
cast call $BALANCE_MANAGER "isAuthorizedOperator(address)(bool)" $NEW_ROUTER --rpc-url $RPC

# New AgentRouter is authorized in each OrderBook
for OB in $ORDERBOOK_1 $ORDERBOOK_2 ... $ORDERBOOK_8; do
  cast call $POOL_MANAGER "isAuthorizedRouter(address,address)(bool)" $OB $NEW_ROUTER --rpc-url $RPC
done

# PolicyFactory points to canonical IdentityRegistry
cast call $NEW_POLICY_FACTORY "identityRegistry()(address)" --rpc-url $RPC
# Expected: 0x8004A818BFB912233c491871b3d84c89A494BD9e

# AgentRouter points to canonical registries
cast call $NEW_ROUTER "getIdentityRegistry()(address)" --rpc-url $RPC
cast call $NEW_ROUTER "getReputationRegistry()(address)" --rpc-url $RPC

# === RED: Verify old contracts deauthorized ===

OLD_ROUTER=0xE9c1a6665364294194aa3B1CE89654926b338493
cast call $BALANCE_MANAGER "isAuthorizedOperator(address)(bool)" $OLD_ROUTER --rpc-url $RPC
# Expected: false

for OB in $ORDERBOOK_1 $ORDERBOOK_2 ... $ORDERBOOK_8; do
  cast call $POOL_MANAGER "isAuthorizedRouter(address,address)(bool)" $OB $OLD_ROUTER --rpc-url $RPC
  # Expected: false
done
```

##### 5.2 Verify on 8004scan

Check `https://testnet.8004scan.io/agents` for all 7 agents.

> **Research Insight (Best Practices):** If not appearing after 5-10 minutes, check:
> - Metadata URL returns 200 with `Content-Type: application/json`
> - `type` field is exactly `"https://eips.ethereum.org/EIPS/eip-8004#registration-v1"`
> - `registrations` array has correct `agentId` and `agentRegistry` in CAIP-10 format

##### 5.3 End-to-End Test

1. Agent places a limit order via new AgentRouter -> verify order succeeds
2. Order fills -> verify reputation `giveFeedback()` call succeeds (no self-feedback revert) or silently fails via try/catch
3. Check indexer picks up `Registered` and `NewFeedback` events from canonical
4. Check frontend agent pages display correct data from new contracts
5. Check agent metadata resolves correctly from `tokenURI()` on canonical

##### 5.4 Verify Reputation on 8004scan

Execute a test trade and confirm the reputation feedback appears on 8004scan's agent detail page.

##### 5.5 On-Chain Verification Commands

```bash
# Verify token exists and URI is set
cast call 0x8004A818BFB912233c491871b3d84c89A494BD9e \
  "tokenURI(uint256)(string)" $TOKEN_ID --rpc-url $RPC

# Verify owner is correct agent wallet
cast call 0x8004A818BFB912233c491871b3d84c89A494BD9e \
  "ownerOf(uint256)(address)" $TOKEN_ID --rpc-url $RPC

# Verify metadata is fetchable and valid
curl -s https://agents.scalex.money/agents/1/metadata.json | python3 -m json.tool
```

---

## System-Wide Impact

### Interaction Graph

```
User authorize() --> AgentRouter (NEW) --> PolicyFactory (NEW).installPolicyFor()
                                           --> Canonical IdentityRegistry.ownerOf()
Agent execute()  --> AgentRouter (NEW) --> Canonical IdentityRegistry.ownerOf()
                                       --> OrderBook.placeOrder() (stores new agentTokenId)
                                       --> Canonical ReputationRegistry.giveFeedback() [try/catch]
                                       --> BalanceManager.transferFrom()
```

> **Research Insight (Architecture Strategist):** OrderBook stores `agentTokenId` in its order struct. New canonical token IDs will be different from old ones. Since we're doing fresh deployment, there are no orders with old token IDs to worry about, but the indexer should not mix old and new token IDs.

### Error Propagation

- If AgentRouter is not authorized in BalanceManager/OrderBooks -> execution reverts
- If `giveFeedback()` fails (self-feedback guard or other) -> silently caught by try/catch, trade succeeds
- Old AgentRouter/PolicyFactory are deauthorized and abandoned

### State Lifecycle Risks

- Fresh deployment = no stale state
- Old contracts remain deployed but deauthorized (cannot move funds)
- OrderBook authorizations must include new AgentRouter address

> **Research Insight (Security Sentinel):** Cross-contract trust consideration: The canonical registries at `0x8004...` are owned and upgradeable by a third party (AltLayer/8004 team). In theory, they could upgrade the registry logic. This is an accepted trust assumption for testnet. For mainnet, verify the canonical registry's upgrade governance.

## Security Considerations

> **Research Insights (Security Sentinel):**

### CRITICAL: credential.txt Exposure

**File:** `credential.txt` in repo root contains hardcoded credentials. Add to `.gitignore` immediately and rotate any exposed secrets.

### HIGH: int128 Cast Overflow

PnL calculation `int128(int256(amountOut) - int256(amountIn))` can silently truncate if the difference exceeds `type(int128).max`. Added bounds check in Phase 1.3.

### HIGH: Circuit Breaker Non-Functional

`_getPortfolioValue()` returns 0 (TODO), so the circuit breaker never triggers and validation calls are unreachable. This is pre-existing dead code, not introduced by this migration.

### MEDIUM: No Reentrancy Guards

AgentRouter's `executeSwap()`, `executeBorrow()`, `executeRepay()` lack `nonReentrant` modifiers. While `giveFeedback()` on the canonical registry is not known to have callback vectors, adding reentrancy guards is defensive best practice. **Defer to separate PR.**

### MEDIUM: Pool Struct Not Validated

`AgentRouterStorage` pool struct accepts arbitrary token/orderbook addresses without validation. Pre-existing issue, not introduced by migration.

## Performance Considerations

> **Research Insights (Performance Oracle):**

| Operation | Gas Cost | Impact |
|-----------|---------|--------|
| `giveFeedback()` per trade | ~65,000-90,000 gas | +15% to swap gas |
| `register()` per agent | ~120,000-180,000 gas | One-time |
| `getSummary()` view call | Scales with feedback count | Don't use on-chain past 10K feedbacks |

The try/catch wrapping adds negligible gas (~200 gas for the try/catch frame).

## Acceptance Criteria

### Functional Requirements

- [ ] All 7 agents visible on testnet.8004scan.io
- [ ] Agent metadata resolves to ERC-8004 compliant JSON (has `type`, `services`, `registrations`)
- [ ] AgentRouter.execute*() calls succeed with canonical token IDs
- [ ] Reputation `giveFeedback()` calls succeed after trades (or fail silently via try/catch)
- [ ] PolicyFactory.installPolicy() works with canonical token IDs
- [ ] Indexer correctly indexes events from canonical registries
- [ ] Frontend agent pages display agents with correct data
- [ ] `GET /api/agents` returns agents from canonical registry
- [ ] Old AgentRouter deauthorized from BalanceManager and all OrderBooks

### Non-Functional Requirements

- [x] All existing Foundry tests pass with updated interfaces
- [ ] No security regressions (self-feedback guard verified)
- [ ] credential.txt added to .gitignore

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Canonical registry has unexpected behavior differences | Low | High | Same source code, verified on-chain |
| Self-feedback guard blocks reputation recording | Medium | High | Verify AgentRouter is not an NFT operator; try/catch wrapping |
| R2 metadata not fetched by 8004scan | Medium | Medium | Follow best-practices.8004scan.io format exactly; add `registrations` array |
| New AgentRouter not authorized in OrderBooks | High (if missed) | Critical | Explicitly included in deployment script with verification commands |
| BalanceManager authorization missing | High (if missed) | Critical | Explicitly included in deployment script with verification commands |
| Old AgentRouter not deauthorized | Medium | High | Explicit deauthorization step + verification |
| PnL overflow on int128 cast | Low | Medium | Bounds check added |
| Canonical registry upgrade by third party | Very Low | High | Accepted trust assumption for testnet |

## References & Research

### Internal References

- AgentRouter storage: `src/ai-agents/storages/AgentRouterStorage.sol:15-17`
- Broken reputation interface: `src/ai-agents/interfaces/IERC8004Reputation.sol:10-105`
- Broken validation interface: `src/ai-agents/interfaces/IERC8004Validation.sol`
- Reputation recording: `src/ai-agents/AgentRouter.sol:740-769`
- Deployment pattern: `script/deployments/DeployPhase5.s.sol`
- PolicyFactory identity check: `src/ai-agents/PolicyFactory.sol:108-109`
- PolicyFactory auth function: `src/ai-agents/PolicyFactory.sol:570` (`setAuthorizedRouter`)
- Canonical contracts: `lib/erc-8004-contracts/contracts/`
- Agent registration script: `script/agents/CreateMultipleAgents.s.sol`
- Shell registration: `shellscripts/agents/register-showcase-agents.sh`
- Frontend contracts config: `../frontend/apps/web/src/configs/contracts.ts:24`
- Indexer env: `../clob-indexer/ponder/.env.base-sepolia:57-62`
- scalex-8004 registration: `../scalex-8004/src/register.ts`

### External References

- [ERC-8004 Specification](https://eips.ethereum.org/EIPS/eip-8004)
- [8004scan Best Practices - Agent Metadata](https://best-practices.8004scan.io/docs/01-agent-metadata-standard)
- [8004scan Best Practices - Feedback Data Profile](https://best-practices.8004scan.io/docs/02-feedback-standard)
- [8004scan Testnet](https://testnet.8004scan.io/)
- [AltLayer 8004scan Docs](https://docs.altlayer.io/altlayer-documentation/8004-scan/overview)
- [Composable Security - ERC-8004 Practical Explainer](https://composable-security.com/blog/erc-8004-a-practical-explainer-for-trustless-agents/)
- [x402 Payment Protocol](https://www.x402.org/)

### Brainstorm

- [ERC-8004 Canonical Migration Brainstorm](../brainstorms/2026-03-04-erc8004-canonical-migration-brainstorm.md)

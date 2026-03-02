---
title: "feat: Add Yield-Bearing Price Prediction Markets"
type: feat
status: active
date: 2026-03-03
brainstorm: docs/brainstorms/2026-03-03-price-prediction-markets-brainstorm.md
---

# ✨ feat: Add Yield-Bearing Price Prediction Markets

## Overview

Add a `PricePrediction.sol` contract that lets users stake sxUSDC on short-term binary price outcomes (UP/DOWN or Above/Below a strike price) derived from the existing `Oracle.sol` TWAP. Funds remain locked in the unified BalanceManager pool during the prediction, so yield accrues to all participants — only the principal is at risk. Settlement is handled trustlessly by a **Chainlink CRE** workflow that reads the on-chain oracle and submits a signed report via `KeystoneForwarder`.

**Unique value proposition**: Yield-bearing predictions — participants earn lending APY even while their funds are locked in a prediction. Losers lose their principal but keep accrued yield.

---

## Problem Statement

The current protocol supports two activities with the unified liquidity pool: trading (via `OrderBook`) and lending (via `LendingManager`). Adding prediction markets as a third activity:
- Increases TVL and protocol revenue via a 2% fee on prize pools
- Improves capital efficiency (idle funds earn yield)
- Creates a differentiator vs. platforms like Polymarket where funds sit idle
- Leverages existing infrastructure (`BalanceManager`, `Oracle`) with minimal new dependencies

---

## Proposed Solution

### Two Market Types

1. **Directional** — "Will ETH/USDC go UP or DOWN in 5 minutes?" (compares TWAP at endTime vs startTime)
2. **Absolute** — "Will ETH/USDC be above $3,500 in 5 minutes?" (compares TWAP at endTime vs strikePrice)

### Fund Flow

```
predict()             settleMarket()              claim()
    │                      │                          │
lock(user, sxUSDC, n)   [CRE → onReport()]      unlock(user, sxUSDC, stake)
    │                      │                     + receive winnings share
    │ yield accrues         │                     OR lose principal
    └──────────────────────┘                     (but keep yield)
```

### Architecture Diagram

```
BalanceManager (unified pool)
  /          |           \
OrderBook  PricePrediction  LendingManager
(trading)  (predictions)    (yield source)
               |
               | IReceiver.onReport()
               │
         KeystoneForwarder  ←──  Chainlink CRE Workflow
               │                  (reads Oracle.getTWAP, signs result)
               │
           Oracle.sol
         (getTWAP — from orderbook trades)
```

---

## Technical Approach

### Architecture

#### `PricePredictionStorage.sol`
ERC-7201 namespaced storage for upgrade safety:

```solidity
// src/core/storages/PricePredictionStorage.sol
/// @custom:storage-location erc7201:scalex.clob.storage.priceprediction
abstract contract PricePredictionStorage {
    // keccak256(abi.encode(uint256(keccak256("scalex.clob.storage.priceprediction")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = <computed>;

    enum MarketType { Directional, Absolute }
    enum MarketStatus { Open, SettlementRequested, Settled, Cancelled }

    struct Market {
        PoolKey poolKey;          // Which trading pair
        MarketType marketType;
        uint256 strikePrice;      // Only used for Absolute type (8 decimals)
        uint256 startTWAP;        // TWAP at creation (for Directional comparison)
        uint256 startTime;
        uint256 endTime;
        uint256 totalUp;          // sxUSDC staked on UP/YES side
        uint256 totalDown;        // sxUSDC staked on DOWN/NO side
        MarketStatus status;
        bool outcome;             // true = UP/YES won
        uint256 maxTVL;           // admin-configured cap
    }

    struct Position {
        uint256 amount;
        bool isUp;
        bool claimed;
    }

    struct Storage {
        mapping(uint256 => Market) markets;
        mapping(uint256 => mapping(address => Position)) positions;
        uint256 nextMarketId;
        address balanceManager;
        address oracle;
        address keystoneForwarder;  // Chainlink CRE forwarder address
        Currency predictionCurrency;// sxUSDC currency ID
        address feeReceiver;
        uint256 feeBps;             // e.g. 200 = 2%
        uint256 minStake;           // e.g. 10e18
        uint256 settlementGracePeriod; // how long before re-request allowed
    }

    function getStorage() internal pure returns (Storage storage $) { ... }
}
```

#### `PricePrediction.sol`
Main contract following the project's standard inheritance chain:

```solidity
// src/core/PricePrediction.sol
contract PricePrediction is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PricePredictionStorage,
    IReceiver          // Chainlink CRE IReceiver interface
{
    function initialize(
        address owner,
        address balanceManager,
        address oracle,
        address keystoneForwarder,
        Currency predictionCurrency,
        address feeReceiver
    ) external initializer { ... }

    // Admin: create new prediction market
    function createMarket(PoolKey calldata poolKey, MarketType marketType,
        uint256 strikePrice, uint256 duration, uint256 maxTVL)
        external onlyOwner returns (uint256 marketId) { ... }

    // User: stake sxUSDC on outcome
    function predict(uint256 marketId, bool isUp, uint256 amount)
        external nonReentrant { ... }

    // Anyone: request settlement after endTime
    function requestSettlement(uint256 marketId) external { ... }

    // Chainlink CRE → KeystoneForwarder → here
    function onReport(bytes calldata metadata, bytes calldata report)
        external override { ... }

    // User: claim winnings (or just yield recovery for losers)
    function claim(uint256 marketId) external nonReentrant { ... }

    // Admin: cancel market (if no participants on one side, or oracle stale)
    function cancelMarket(uint256 marketId) external onlyOwner { ... }

    // ERC-165 required by IReceiver
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) { ... }
}
```

#### CRE Workflow
TypeScript workflow compiled to WASM, deployed to Chainlink DON:

```typescript
// cre-workflows/price-prediction/src/index.ts
import { EVMClient, handler, getNetwork, hexToBase64, bytesToHex,
         type Runtime, type EVMLog, Runner } from "@chainlink/cre-sdk"
import { keccak256, toBytes, decodeEventLog, parseAbi,
         encodeFunctionData, decodeFunctionResult,
         encodeAbiParameters, parseAbiParameters } from "viem"

// Listen for SettlementRequested events, read Oracle TWAP, submit signed result
const onSettlementRequested = (runtime: Runtime<Config>, log: EVMLog) => {
    // 1. Decode event → get marketId, poolKey, strikePrice, marketType, startTWAP
    // 2. Call oracle.getTWAP(token, 300) for current price
    // 3. Determine outcome
    // 4. runtime.report() + evmClient.writeReport() → KeystoneForwarder → onReport()
}
```

---

### Implementation Phases

#### Phase 1: Storage & Interface Design

**Files to create:**
- `src/core/storages/PricePredictionStorage.sol`
- `src/core/interfaces/IPricePrediction.sol`

**Tasks:**
- [ ] Compute ERC-7201 storage slot for `"scalex.clob.storage.priceprediction"`
- [ ] Define all structs: `Market`, `Position`
- [ ] Define all events: `MarketCreated`, `PredictionPlaced`, `SettlementRequested`, `MarketSettled`, `PrizeClaimed`, `MarketCancelled`
- [ ] Define all errors: `MarketNotOpen`, `MarketNotExpired`, `AlreadyClaimed`, `InsufficientStake`, `OraclePriceStale`, `ZeroSidePool`, `TVLExceeded`, `NotForwarder`
- [ ] Import `IReceiver` from Chainlink (or vendor locally at `src/core/interfaces/chainlink/IReceiver.sol`)
- [ ] Define `IPricePrediction.sol` interface

**Critical note — IReceiver vendoring**: Chainlink's `IReceiver` requires `IERC165`. Vendor both under `src/core/interfaces/chainlink/` to avoid npm dependency in Foundry. The interface is:
```solidity
interface IReceiver is IERC165 {
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
```

---

#### Phase 2: `PricePrediction.sol` Implementation

**File to create:** `src/core/PricePrediction.sol`

**Function specs:**

**`createMarket()`** — admin only
- Check `marketType == Absolute → strikePrice > 0`
- Capture `startTWAP = oracle.getTWAP(baseToken, 300)` for Directional markets
- Guard: `!oracle.isPriceStale(baseToken)` — revert `OraclePriceStale` if stale
- Set `endTime = block.timestamp + duration`
- Emit `MarketCreated(marketId, poolKey, marketType, strikePrice, endTime)`

**`predict(marketId, isUp, amount)`**
- Guards: market is `Open`, `block.timestamp < endTime`, `amount >= $.minStake`
- Guard: `market.totalUp + market.totalDown + amount <= market.maxTVL`
- Call `IBalanceManager($.balanceManager).lock(msg.sender, $.predictionCurrency, amount)`
- Record `positions[marketId][msg.sender] = {amount, isUp, false}`
- Update `market.totalUp` or `market.totalDown`
- Emit `PredictionPlaced(marketId, msg.sender, isUp, amount)`

**`requestSettlement(marketId)`**
- Guards: `block.timestamp >= market.endTime`, `market.status == Open`
- If either side has 0 participants: auto-cancel market (emit `MarketCancelled`, set status = `Cancelled`)
- Set `market.status = SettlementRequested`
- Emit `SettlementRequested(marketId, poolKey, marketType, market.strikePrice, market.startTWAP)`
- Track `market.settlementRequestedAt` for grace period enforcement

**`onReport(metadata, report)` — Chainlink CRE entry point**
- Guard: `msg.sender == $.keystoneForwarder` — revert `NotForwarder`
- Decode report: `(uint256 marketId, bool outcome, bool priceStale)`
- If `priceStale == true`: cancel market instead of settling (prevents bad resolution)
- Set `market.outcome = outcome`, `market.status = Settled`
- Emit `MarketSettled(marketId, outcome)`

**`claim(marketId)`**
- Guards: market is `Settled` or `Cancelled`, position not yet claimed
- Mark position as claimed
- **If Cancelled**: `IBalanceManager.unlock(msg.sender, sxUSDC, position.amount)` — full refund + yield
- **If Settled, Loser**: `IBalanceManager.unlock(msg.sender, sxUSDC, 0)` — yield only, 0 principal

  > ⚠️ **Implementation Note**: `unlock(user, sxUSDC, 0)` must be verified to work correctly (the implementation should handle zero-amount unlocks as a pure yield-claim). If `unlock` reverts on amount=0, use an alternative: check if BalanceManager exposes a `claimYield(user)` function, or call `unlock` with amount=0 only if the function allows it. See `src/core/BalanceManager.sol:415` for the exact implementation check.

  > For the loser's principal stake: it must be made available to winners. **Critical implementation question**: Does `IBalanceManager` expose `transferLockedFrom(address from, Currency currency, uint256 amount, address to)` for moving locked funds between accounts? Check `src/core/interfaces/IBalanceManager.sol` and `src/core/BalanceManager.sol`. If not, consider adding this function to BalanceManager, or redesign using contract-level accounting (see Alternative A below).

- **If Settled, Winner**:
  - `losingPool = isUp won ? market.totalDown : market.totalUp`
  - `feeAmount = losingPool * $.feeBps / 10000`
  - `distributedPool = losingPool - feeAmount`
  - `winShare = (position.amount * distributedPool) / (isUp won ? market.totalUp : market.totalDown)`
  - `totalPayout = position.amount + winShare`
  - `IBalanceManager.unlock(msg.sender, sxUSDC, totalPayout)` — if locked exactly `totalPayout` is available

  > ⚠️ **Implementation Note**: Winners receive MORE than their locked stake. `unlock(winner, sxUSDC, position.amount + winShare)` will fail if only `position.amount` was locked. Two approaches:
  > - **Option A (Preferred)**: `unlock(winner, sxUSDC, position.amount)` for their stake, then use `transferLockedFrom` on each loser's locked funds to credit winners (claim-batch approach)
  > - **Option B**: Do not use `lock()` — instead transfer user funds into PricePrediction's own BalanceManager account during `predict()`, run the pool as a contract-held balance, distribute on claim. Simpler but funds yield goes to contract not user individually.

**`cancelMarket(marketId)`** — admin only
- Set `status = Cancelled`; individual users call `claim()` to recover via `unlock`

---

#### Phase 3: Chainlink CRE Workflow

**Directory:** `cre-workflows/price-prediction/`

**Files to create:**
- `cre-workflows/price-prediction/package.json`
- `cre-workflows/price-prediction/workflow.yaml`
- `cre-workflows/price-prediction/src/index.ts`
- `cre-workflows/price-prediction/src/oracle.ts` — Oracle.sol ABI + callContract helper

**Key workflow logic** (`src/index.ts`):

```typescript
const SETTLEMENT_REQUESTED_TOPIC = keccak256(
    toBytes("SettlementRequested(uint256,bytes32,uint8,uint256,uint256)")
    //                           marketId, poolId, type, strikePrice, startTWAP
)

const oracleAbi = parseAbi([
    "function getTWAP(address token, uint256 window) view returns (uint256)",
    "function isPriceStale(address token) view returns (bool)",
])

const onSettlementRequested = (runtime: Runtime<Config>, log: EVMLog): string => {
    // 1. Decode SettlementRequested event
    const { marketId, poolId, marketType, strikePrice, startTWAP } = decodeEvent(log)

    // 2. Check oracle health
    const isStale = callContract(runtime, oracle, "isPriceStale", [baseToken])
    const currentTWAP = callContract(runtime, oracle, "getTWAP", [baseToken, 300n])

    // 3. Determine outcome
    let outcome: boolean
    if (isStale || currentTWAP === 0n) {
        // Submit with priceStale=true → contract will cancel instead of settle
        outcome = false
        submitSettlement(runtime, marketId, outcome, true)
        return "cancelled-stale"
    }

    if (marketType === MarketType.Directional) {
        outcome = currentTWAP >= startTWAP  // true = UP
    } else {
        outcome = currentTWAP >= strikePrice  // true = ABOVE
    }

    // 4. Submit signed settlement
    submitSettlement(runtime, marketId, outcome, false)
    return `settled-market-${marketId}-outcome-${outcome}`
}
```

**`workflow.yaml`:**
```yaml
targets:
  base-sepolia:
    settings:
      chainSelectorName: "base-testnet-sepolia"
      predictionContractAddress: "<deployed PricePrediction address>"
      oracleAddress: "<deployed Oracle address>"
      gasLimit: "500000"
```

**Local testing:**
```bash
# Simulate against a real testnet tx that emitted SettlementRequested
cre workflow simulate cre-workflows/price-prediction \
  --non-interactive \
  --trigger-index 0 \
  --evm-tx-hash <tx_that_emitted_SettlementRequested> \
  --evm-event-index 0 \
  --target base-sepolia
```

---

#### Phase 4: Deployment Script

**File to create:** `script/deployment/DeployPricePrediction.s.sol`

```solidity
// Follows exact pattern of DeployPhase5.s.sol:
// 1. Deploy PricePrediction implementation
// 2. Deploy UpgradeableBeacon
// 3. Deploy BeaconProxy with initialize() call
// 4. Authorize in BalanceManager:
//    BalanceManager(balanceManager).addAuthorizedOperator(address(predictionProxy));
// 5. Write to deployments/{chainId}.json
```

**File to create:** `script/configuration/AuthorizePricePrediction.s.sol`

- Standalone script to add PricePrediction as an authorized operator after-the-fact
- Follows pattern from `AuthorizeScaleXRouter.s.sol`

---

#### Phase 5: Tests

**File to create:** `test/core/PricePredictionTest.t.sol`

Uses `BeaconDeployer.t.sol` helper (at `test/core/helpers/BeaconDeployer.t.sol`).

**Unit test cases:**
```solidity
// Market lifecycle
testCreateMarket_directional()
testCreateMarket_absolute()
testCreateMarket_revertsIfNotOwner()
testCreateMarket_revertsIfStaleOracle()

// Predictions
testPredict_up_locksBalance()
testPredict_down_locksBalance()
testPredict_revertsIfBelowMinStake()
testPredict_revertsIfTVLExceeded()
testPredict_revertsIfMarketClosed()

// Settlement
testRequestSettlement_emitsEvent()
testRequestSettlement_revertsIfBeforeEndTime()
testRequestSettlement_cancelsIfOneSideEmpty()
testOnReport_settlesMarket_upWon()
testOnReport_settlesMarket_downWon()
testOnReport_cancelsIfPriceStale()
testOnReport_revertsIfNotForwarder()

// Claims
testClaim_winner_receivesStakePlusPrizeShare()
testClaim_winner_yieldAlsoClaimed()
testClaim_loser_receivesYieldOnly()
testClaim_cancelled_receivesFullRefund()
testClaim_revertsIfAlreadyClaimed()
testClaim_protocolFeeDeducted()

// Fee
testFee_collected_onSettlement()
testFee_configurable_byOwner()
```

**Integration test:**
`test/integration/PricePredictionIntegrationTest.t.sol`
- Full flow: deposit → create market → predict → settle (mock forwarder) → claim
- Multi-user: 3 UP bettors, 2 DOWN bettors, UP wins — verify proportional distribution
- Verify yield is distributed to all participants at claim time

---

## System-Wide Impact

### Interaction Graph
```
predict()
  → BalanceManager.lock(user, sxUSDC, amount)
    → $.balanceOf[user][sxUSDC] -= amount
    → $.lockedBalanceOf[user][PricePrediction][sxUSDC] += amount
    (No LendingManager interaction — funds stay in vault, only accounting changes)

onReport() [called by KeystoneForwarder]
  → PricePrediction._processReport(report)
    → market.status = Settled
    → emits MarketSettled

claim() — winner
  → BalanceManager.unlock(winner, sxUSDC, stake)
    → $.lockedBalanceOf[winner][PricePrediction][sxUSDC] -= stake
    → $.balanceOf[winner][sxUSDC] += stake
    → _claimUserYield(winner) fires → LendingManager yield credited
  → [OPEN: transfer loser stakes to winners via TBD mechanism]

claim() — loser
  → BalanceManager.unlock(loser, sxUSDC, 0) [TBD: verify amount=0 is valid]
    → _claimUserYield(loser) fires → LendingManager yield credited
```

### Error Propagation
- `lock()` fails: insufficient balance → transaction reverts, user informed
- `getTWAP` returns 0 (no history): CRE workflow detects, cancels market gracefully
- `onReport()` called by wrong address: `NotForwarder` revert — prediction remains unresolved
- CRE workflow fails to execute: market stays in `SettlementRequested` status — after `settlementGracePeriod`, anyone can call `requestSettlement()` again (re-emit event to re-trigger CRE)

### State Lifecycle Risks
- **Stuck market**: If CRE never settles and grace period expires, admin can `cancelMarket()` to allow refunds
- **Partial settlement**: `onReport()` is atomic — either market fully settles or reverts
- **Double-claim**: `position.claimed = true` guard prevents double-claim; checked before any state change

### API Surface Parity
- PricePrediction follows the same authorized-operator pattern as `OrderBook` and `AgentRouter`
- `lock()` / `unlock()` called identically to how OrderBook uses them
- New `addAuthorizedOperator` call needed in deployment script

### Integration Test Scenarios
1. **Full happy path**: Admin creates directional market → 5 users predict (3 UP, 2 DOWN) → market expires → requestSettlement() → mock forwarder calls onReport(UP won) → all claim → verify UP bettors got proportional winnings, DOWN bettors got yield only
2. **Stale oracle at settlement**: Oracle hasn't had trades in >1 hour → CRE detects stale → submits `priceStale=true` → market cancelled → all users get full refund via claim()
3. **One-sided market**: 5 UP bets, 0 DOWN bets → requestSettlement() auto-cancels → all UP bettors get refund
4. **Liquidation during prediction**: User has 1000 sxUSDC, locks 900 in prediction, borrows against remaining 100, gets liquidated → seizeCollateral() works on available balance; locked prediction funds are seizable (default behavior, no special handling)
5. **CRE outage / grace period**: Settlement not received within grace period → anyone re-calls requestSettlement() → emits new SettlementRequested event → CRE picks it up on retry

---

## Acceptance Criteria

### Functional Requirements
- [ ] Admin can create directional and absolute prediction markets on any supported pool
- [ ] Users can stake sxUSDC (min 10 USDC) on UP/YES or DOWN/NO
- [ ] Locked funds remain in BalanceManager and earn lending yield during prediction window
- [ ] Chainlink CRE automatically resolves markets using Oracle.getTWAP() at endTime
- [ ] Winners receive proportional share of losers' principal (minus 2% protocol fee)
- [ ] All participants (winners and losers) receive accrued yield on claim
- [ ] Markets with zero participants on one side auto-cancel on requestSettlement()
- [ ] Stale oracle price at settlement time causes market cancellation (full refund)
- [ ] Re-settlement request available after grace period if CRE fails

### Non-Functional Requirements
- [ ] `predict()` gas cost < 150k gas
- [ ] `claim()` gas cost < 100k gas
- [ ] Contract is upgradeable (Beacon Proxy + ERC-7201)
- [ ] All admin functions protected by `onlyOwner`
- [ ] `onReport()` protected by `msg.sender == keystoneForwarder` check
- [ ] Reentrancy protection on `predict()` and `claim()`
- [ ] No raw ECDSA signature verification needed on-chain (KeystoneForwarder handles it)

### Quality Gates
- [ ] Foundry test suite with ≥90% line coverage on `PricePrediction.sol`
- [ ] Integration test covering full market lifecycle
- [ ] `addAuthorizedOperator` call included in deployment script
- [ ] Contract deployed as Beacon Proxy (upgradeable)
- [ ] CRE workflow simulated locally against testnet events before deployment

---

## Dependencies & Prerequisites

| Dependency | Status | Notes |
|---|---|---|
| BalanceManager `lock/unlock` | ✅ Exists | `src/core/BalanceManager.sol:381-438` |
| Oracle `getTWAP` | ✅ Exists | `src/core/Oracle.sol:318` — check `isPriceStale` first |
| BalanceManager `transferLockedFrom` | ❓ Unknown | Must verify existence in `IBalanceManager.sol` — critical for prize distribution |
| Chainlink `IReceiver` + `ReceiverTemplate` | ⬇️ Need to vendor | Vendor from Chainlink github into `src/core/interfaces/chainlink/` |
| Chainlink CRE Early Access | ⚠️ Gated | Request at chain.link/chainlink-runtime-environment before workflow deployment |
| KeystoneForwarder address (Base Sepolia) | ⬇️ Need to find | Check docs.chain.link/cre for forwarder address on Base Sepolia testnet |
| `@chainlink/cre-sdk` npm package | ⬇️ Need to install | For CRE workflow TypeScript code |

---

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `transferLockedFrom` doesn't exist in BalanceManager | Medium | High | Check `IBalanceManager.sol` first; if missing, use contract-level accounting (Option B) or add function to BalanceManager |
| TWAP manipulation on 5-min window | Low | High | Admin should only create markets on high-volume pools; market creation can include minimum volume check |
| Chainlink CRE Early Access delay | Medium | Medium | Use mock forwarder for local testing; mainnet launch can be after CRE access is granted |
| `unlock(user, sxUSDC, 0)` reverts | Low | Medium | Check `BalanceManager.sol:415` — if amount=0 is rejected, route loser yield-claim differently |
| Prize pool distribution gas cost | Low | Low | Claim-per-user model means gas is paid by claimer; no batch operations needed |
| KeystoneForwarder address changes | Low | Low | Store in upgradeable storage; admin can update via `setForwarder()` |

---

## Future Considerations

- Support additional collateral currencies (sxETH, sxBTC) once USD accounting is solved
- Batch market creation for recurring markets (e.g., auto-create new 5-min market on resolution)
- Leveraged predictions via auto-borrow (OrderBook already has this pattern)
- Range predictions (price between $X and $Y)
- Agent-powered auto-predict (AgentRouter extension)

---

## References & Research

### Internal References
- BalanceManager lock/unlock: `src/core/BalanceManager.sol:381-438`
- BalanceManager authorized operators: `src/core/BalanceManager.sol:96-113`
- Oracle.getTWAP: `src/core/Oracle.sol:318`
- Oracle.isPriceStale: `src/core/Oracle.sol` (check exact line)
- ERC-7201 storage pattern: `src/core/storages/BalanceManagerStorage.sol`
- Beacon Proxy deploy pattern: `script/deployment/DeployPhase5.s.sol`
- Authorization pattern: `docs/AUTHORIZATION_CHECKLIST.md`
- Test setup helper: `test/core/helpers/BeaconDeployer.t.sol`
- AgentRouter authorization (precedent): `script/deployment/DeployPhase5.s.sol:184-185`

### External References
- Chainlink CRE docs: https://docs.chain.link/cre
- Chainlink CRE EVM Log Trigger (TypeScript): https://docs.chain.link/cre/reference/sdk/triggers/evm-log-trigger-ts
- Chainlink CRE on-chain consumer pattern: https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts
- Chainlink CRE prediction market demo: https://docs.chain.link/cre/demos/prediction-market
- Chainlink CRE supported networks: https://docs.chain.link/cre/supported-networks-ts
- KeystoneForwarder addresses: https://docs.chain.link/cre (check per-network forwarder directory)
- CRE SDK TypeScript: https://github.com/smartcontractkit/cre-sdk-typescript

### Files to Create

```
src/core/
  PricePrediction.sol
  storages/PricePredictionStorage.sol
  interfaces/IPricePrediction.sol
  interfaces/chainlink/IReceiver.sol      ← vendored
  interfaces/chainlink/IERC165.sol        ← vendored

cre-workflows/price-prediction/
  package.json
  workflow.yaml
  src/index.ts
  src/oracle.ts

test/core/
  PricePredictionTest.t.sol
test/integration/
  PricePredictionIntegrationTest.t.sol

script/deployment/
  DeployPricePrediction.s.sol
script/configuration/
  AuthorizePricePrediction.s.sol
```

---

---

## Phase 6: Shell Script Integration

The existing `shellscripts/deployment/deploy.sh` runs Foundry deployment scripts in phases (Phase1A/B/C → Phase2 → Phase3 → Phase4 → Phase5 → ConfigureAllOracleTokens). PricePrediction must be added as a new phase.

### 6.1 Update `shellscripts/deployment/deploy.sh`

Add a **Phase 6 block** after the existing Phase 5 (`DeployPhase5.s.sol`) block, following the exact same pattern:

```bash
# Phase 6: Deploy PricePrediction Contract
echo "📋 Phase 6: Deploying PricePrediction..."
if eval "forge script script/deployments/DeployPricePrediction.s.sol:DeployPricePrediction \
    --rpc-url \"${SCALEX_CORE_RPC}\" --broadcast --private-key \$PRIVATE_KEY \
    --gas-estimate-multiplier 120 $SLOW_FLAG $VERIFY_FLAGS"; then
    echo "✅ PricePrediction deployed successfully"
else
    echo "⚠️  PricePrediction deployment failed (non-fatal)"
fi
```

Also update the JSON address reading section to load `PRICE_PREDICTION_ADDRESS`:
```bash
PRICE_PREDICTION_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.PricePrediction // ""')
```

And print it in the deployment summary at the end of `deploy.sh`.

### 6.2 New Script: `shellscripts/predictions/create-prediction-markets.sh`

Admin script to create initial markets after deployment:

```bash
#!/bin/bash
# Creates prediction markets on deployed PricePrediction contract
# Usage: bash shellscripts/predictions/create-prediction-markets.sh
#
# ENV vars:
#   SCALEX_CORE_RPC - RPC URL
#   CORE_CHAIN_ID   - chain ID
#   PRIVATE_KEY     - admin private key (owner of PricePrediction)

# Read PricePrediction address from deployments/{chainId}.json
PRICE_PREDICTION_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.PricePrediction')

# Create ETH/USDC Directional 5-minute market
# createMarket(poolKey, marketType=0 (Directional), strikePrice=0, duration=300, maxTVL=100000e18)
cast send $PRICE_PREDICTION_ADDRESS "createMarket((address,address,uint24,int24),uint8,uint256,uint256,uint256)" \
    "($WETH_ADDRESS,$USDC_ADDRESS,3000,60)" 0 0 300 "100000000000000000000000" \
    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY

# Create ETH/USDC Absolute 5-minute market (strike = current price)
# Admin fetches current TWAP first, then creates market
cast send $PRICE_PREDICTION_ADDRESS "createMarket((address,address,uint24,int24),uint8,uint256,uint256,uint256)" \
    "($WETH_ADDRESS,$USDC_ADDRESS,3000,60)" 1 "$CURRENT_ETH_PRICE" 300 "100000000000000000000000" \
    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY

echo "✅ Prediction markets created"
```

### 6.3 New Script: `shellscripts/predictions/populate-predictions.sh`

Simulates test users placing predictions (for local dev, mirrors populate-data.sh pattern):

```bash
#!/bin/bash
# Populates prediction markets with test activity
# Usage: bash shellscripts/predictions/populate-predictions.sh
#
# ENV vars:
#   SCALEX_CORE_RPC, CORE_CHAIN_ID
#   PRIMARY_TRADER_PRIVATE_KEY, SECONDARY_TRADER_PRIVATE_KEY

PRICE_PREDICTION_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.PricePrediction')
PREDICTION_MARKET_ID=1  # First ETH/USDC directional market

# Trader 1 bets UP (10 USDC = 10e18)
cast send $PRICE_PREDICTION_ADDRESS "predict(uint256,bool,uint256)" \
    $PREDICTION_MARKET_ID true "10000000000000000000" \
    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIMARY_TRADER_PRIVATE_KEY

# Trader 2 bets DOWN (10 USDC)
cast send $PRICE_PREDICTION_ADDRESS "predict(uint256,bool,uint256)" \
    $PREDICTION_MARKET_ID false "10000000000000000000" \
    --rpc-url "${SCALEX_CORE_RPC}" --private-key $SECONDARY_TRADER_PRIVATE_KEY

echo "✅ Test predictions placed"
```

### 6.4 Update `shellscripts/trading/populate-data.sh`

At the end of the populate-data.sh script, add an optional section:

```bash
# Optional: Populate prediction market test data
if [[ -n "$PRICE_PREDICTION_ADDRESS" && "$PRICE_PREDICTION_ADDRESS" != "null" && "$PRICE_PREDICTION_ADDRESS" != "" ]]; then
    print_step "Populating prediction market test data..."
    source "${SCRIPT_DIR}/../predictions/populate-predictions.sh" || true
else
    print_warning "PricePrediction not deployed — skipping prediction data population"
fi
```

### Files to Create/Modify for Shell Scripts

| Action | File |
|--------|------|
| Modify | `shellscripts/deployment/deploy.sh` — add Phase 6 block + read PricePrediction address |
| Create | `shellscripts/predictions/create-prediction-markets.sh` |
| Create | `shellscripts/predictions/populate-predictions.sh` |
| Modify | `shellscripts/trading/populate-data.sh` — add optional prediction population at end |

---

---

## Phase 7: Base Sepolia Deployment

The existing Base Sepolia deployment (chain ID 84532) has all core contracts already live. PricePrediction is a **new contract** — not an upgrade of an existing one. However, if BalanceManager needs a new function (e.g., `transferLockedFrom`), that would require an **upgrade** of the existing BalanceManager beacon.

### Existing Base Sepolia Addresses (from `deployments/84532.json`)

| Contract | Address |
|---|---|
| BalanceManager | `0x466C3fbb7e87A22393508bd436fb7253965D493A` |
| Oracle | `0xFD36dD7A4c08587c17CD675b883133c0D87AE38A` |
| ScaleXRouter | `0x686F847C23a8cda17d4eaa2DEd396e718f8883BF` |
| LendingManager | `0xb4BF0964f99b70e01e885C0cf737fbE8a17ce72A` |

### 7.1 Conditional: Upgrade BalanceManager (if needed)

**Only required if** `transferLockedFrom` or other new function must be added.

Follow the existing pattern from `script/maintenance/UpgradeScaleXContract.s.sol`:

```bash
# Get BalanceManager beacon address from EIP-1967 slot
BEACON_SLOT="0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50"
BM_BEACON=$(cast storage 0x466C3fbb7e87A22393508bd436fb7253965D493A $BEACON_SLOT \
  --rpc-url https://sepolia.base.org)

# Run upgrade via UpgradeBalanceManager.s.sol (or UpgradeScaleXContract.s.sol)
BEACON_ADDRESS=$BM_BEACON CONTRACT_TYPE=BalanceManager \
  forge script script/maintenance/UpgradeScaleXContract.s.sol:UpgradeScaleXContract \
  --rpc-url https://sepolia.base.org --broadcast --private-key $PRIVATE_KEY \
  --verify --etherscan-api-key $ETHERSCAN_API_KEY --chain 84532
```

**Create upgrade shell script:** `shellscripts/deployment/upgrade-balance-manager.sh`
- Mirrors existing `upgrade_router.sh` pattern exactly
- Reads BalanceManager proxy from `deployments/84532.json`
- Reads beacon via EIP-1967 slot
- Deploys new impl + upgrades beacon
- Includes Etherscan + Tenderly verification support

### 7.2 Deploy PricePrediction on Base Sepolia

**Create shell script:** `shellscripts/deployment/deploy-price-prediction.sh`

Standalone script for deploying PricePrediction to any network (including Base Sepolia), following the `upgrade_router.sh` structure:

```bash
#!/bin/bash
# Deploy PricePrediction contract to Base Sepolia (or any network)
# Usage:
#   SCALEX_CORE_RPC="https://sepolia.base.org" \
#   PRIVATE_KEY=0x... \
#   ETHERSCAN_API_KEY=... \
#   KEYSTONE_FORWARDER=0x... \   ← from Chainlink docs for Base Sepolia
#   bash shellscripts/deployment/deploy-price-prediction.sh

# Reads from deployments/${CORE_CHAIN_ID}.json:
#   - BalanceManager address
#   - Oracle address
#   - sxIDRX currency ID (prediction currency)

# Steps:
# 1. forge script script/deployments/DeployPricePrediction.s.sol \
#      --rpc-url $SCALEX_CORE_RPC --broadcast --private-key $PRIVATE_KEY \
#      --verify --etherscan-api-key $ETHERSCAN_API_KEY --chain 84532
# 2. Read new PricePrediction address from deployments/${CORE_CHAIN_ID}.json
# 3. Verify: cast call $PRICE_PREDICTION "owner()" --rpc-url $SCALEX_CORE_RPC
# 4. Verify authorization: cast call $BALANCE_MANAGER \
#      "isAuthorizedOperator(address)" $PRICE_PREDICTION --rpc-url $SCALEX_CORE_RPC
# 5. Print summary with all deployed addresses
```

### 7.3 Base Sepolia Deployment Order

```
Step 1: Verify BalanceManager has transferLockedFrom (or decide on Option B)
          cast call 0x466C3f... "transferLockedFrom(address,address,uint256,address)" ...

Step 2 (if needed): Upgrade BalanceManager
          bash shellscripts/deployment/upgrade-balance-manager.sh

Step 3: Deploy PricePrediction (fresh contract)
          SCALEX_CORE_RPC=https://sepolia.base.org \
          KEYSTONE_FORWARDER=<forwarder-from-chainlink-docs> \
          bash shellscripts/deployment/deploy-price-prediction.sh

Step 4: Update deployments/84532.json with PricePrediction address
          (done automatically by DeployPricePrediction.s.sol)

Step 5: Create prediction markets on Base Sepolia
          SCALEX_CORE_RPC=https://sepolia.base.org \
          bash shellscripts/predictions/create-prediction-markets.sh

Step 6: Deploy CRE workflow targeting Base Sepolia
          cd cre-workflows/price-prediction
          cre workflow deploy --target base-sepolia
```

### 7.4 KeystoneForwarder Address for Base Sepolia

The CRE KeystoneForwarder address for Base Sepolia must be retrieved from the [Chainlink CRE supported networks page](https://docs.chain.link/cre/supported-networks-ts) before deployment. Store it in:
- `KEYSTONE_FORWARDER` env var for deployment scripts
- `$.keystoneForwarder` in PricePrediction storage (admin-updatable via `setForwarder()`)

### Files to Create/Modify for Base Sepolia

| Action | File |
|--------|------|
| Create | `shellscripts/deployment/deploy-price-prediction.sh` |
| Create | `shellscripts/deployment/upgrade-balance-manager.sh` (conditional) |
| Auto-update | `deployments/84532.json` — adds `PricePrediction` key via `vm.writeFile` |

---

## Phase 8: Indexer (Ponder)

The indexer lives at `../clob-indexer/ponder/` and uses **Ponder** (TypeScript blockchain indexing framework) with PostgreSQL. New contracts are registered in `core-chain-ponder.config.ts`, schemas defined in `ponder.schema.ts`, and handlers live in `src/handlers/`.

### 8.1 ABI — `ponder/deployments/PricePrediction.json`

Copy `PricePrediction.sol` ABI to `../clob-indexer/ponder/deployments/PricePrediction.json` after the contract is compiled. This is the entry point for the indexer to know what events to listen for.

### 8.2 Contract Registration — `core-chain-ponder.config.ts`

```typescript
import PricePredictionABI from "./deployments/PricePrediction.json"

// Add to contracts section:
PricePrediction: {
  abi: PricePredictionABI,
  network: {
    coreDevnet: {
      address: "0x<deployed-address-from-84532.json>",
      startBlock: <deployment-block>,
    }
  }
}
```

### 8.3 Schema — `ponder.schema.ts`

Add three new tables following the existing `onchainTable()` pattern:

```typescript
// Prediction markets
export const predictionMarkets = onchainTable(
  "prediction_markets",
  (t) => ({
    id: t.bigint().primaryKey(),          // marketId
    poolId: t.hex().notNull(),
    marketType: t.integer().notNull(),    // 0=Directional, 1=Absolute
    strikePrice: t.bigint(),              // null for Directional
    startTWAP: t.bigint(),               // reference price at creation
    startTime: t.bigint().notNull(),
    endTime: t.bigint().notNull(),
    totalUp: t.bigint().default(0n),
    totalDown: t.bigint().default(0n),
    status: t.varchar().notNull().default("open"), // open|settlement_requested|settled|cancelled
    outcome: t.boolean(),                // null until settled
    maxTVL: t.bigint().notNull(),
    feeBps: t.integer().notNull(),
    createdAt: t.bigint().notNull(),
    settledAt: t.bigint(),
    transactionHash: t.hex().notNull(),
  }),
  (table) => ({
    poolIdIdx: index().on(table.poolId),
    statusIdx: index().on(table.status),
    endTimeIdx: index().on(table.endTime),
  })
)

// Individual user positions
export const predictionPositions = onchainTable(
  "prediction_positions",
  (t) => ({
    id: t.text().primaryKey(),           // `${marketId}-${userAddress}`
    marketId: t.bigint().notNull(),
    userAddress: t.hex().notNull(),
    isUp: t.boolean().notNull(),
    amount: t.bigint().notNull(),
    claimed: t.boolean().notNull().default(false),
    claimedAt: t.bigint(),
    payout: t.bigint(),                  // filled on claim
    transactionHash: t.hex().notNull(),
  }),
  (table) => ({
    marketIdIdx: index().on(table.marketId),
    userIdx: index().on(table.userAddress),
    marketUserIdx: index().on(table.marketId, table.userAddress),
  })
)

// Settlement events (for audit/history)
export const predictionSettlements = onchainTable(
  "prediction_settlements",
  (t) => ({
    id: t.bigint().primaryKey(),          // marketId
    marketId: t.bigint().notNull(),
    outcome: t.boolean().notNull(),
    settlementTWAP: t.bigint(),           // price used for settlement
    priceStale: t.boolean().notNull(),    // true = cancelled due to stale price
    transactionHash: t.hex().notNull(),
    settledAt: t.bigint().notNull(),
  }),
  (table) => ({
    marketIdIdx: index().on(table.marketId),
  })
)
```

### 8.4 Handler — `src/handlers/predictionMarketHandler.ts`

```typescript
// Pattern mirrors orderBookHandler.ts

export async function handleMarketCreated(context: Context, event: Event) {
  const { marketId, poolId, marketType, strikePrice, startTWAP, endTime, maxTVL } = event.args
  await context.db.insert(schema.predictionMarkets).values({
    id: marketId,
    poolId, marketType, strikePrice, startTWAP,
    startTime: event.block.timestamp,
    endTime, maxTVL,
    status: "open",
    feeBps: 200,  // read from contract or event
    createdAt: event.block.timestamp,
    transactionHash: event.transaction.hash,
  })
}

export async function handlePredictionPlaced(context: Context, event: Event) {
  const { marketId, user, isUp, amount } = event.args
  const id = `${marketId}-${user}`
  await context.db.insert(schema.predictionPositions).values({
    id, marketId, userAddress: user, isUp, amount,
    claimed: false,
    transactionHash: event.transaction.hash,
  })
  // Update market totals
  const field = isUp ? "totalUp" : "totalDown"
  await context.db.update(schema.predictionMarkets, { id: marketId })
    .set({ [field]: sql`${field} + ${amount}` })
}

export async function handleMarketSettled(context: Context, event: Event) {
  const { marketId, outcome } = event.args
  await context.db.update(schema.predictionMarkets, { id: marketId })
    .set({ status: "settled", outcome, settledAt: event.block.timestamp })
  await context.db.insert(schema.predictionSettlements).values({
    id: marketId, marketId, outcome, priceStale: false,
    settledAt: event.block.timestamp,
    transactionHash: event.transaction.hash,
  })
}

export async function handleMarketCancelled(context: Context, event: Event) {
  const { marketId } = event.args
  await context.db.update(schema.predictionMarkets, { id: marketId })
    .set({ status: "cancelled" })
}

export async function handlePrizeClaimed(context: Context, event: Event) {
  const { marketId, user, payout } = event.args
  const id = `${marketId}-${user}`
  await context.db.update(schema.predictionPositions, { id })
    .set({ claimed: true, claimedAt: event.block.timestamp, payout })
}
```

### 8.5 Registration — `src/index.ts`

```typescript
import * as predictionMarketHandler from "./handlers/predictionMarketHandler"

ponder.on("PricePrediction:MarketCreated",    withEventValidator(predictionMarketHandler.handleMarketCreated,    "marketCreated"))
ponder.on("PricePrediction:PredictionPlaced", withEventValidator(predictionMarketHandler.handlePredictionPlaced, "predictionPlaced"))
ponder.on("PricePrediction:MarketSettled",    withEventValidator(predictionMarketHandler.handleMarketSettled,    "marketSettled"))
ponder.on("PricePrediction:MarketCancelled",  withEventValidator(predictionMarketHandler.handleMarketCancelled,  "marketCancelled"))
ponder.on("PricePrediction:PrizeClaimed",     withEventValidator(predictionMarketHandler.handlePrizeClaimed,     "prizeClaimed"))
ponder.on("PricePrediction:SettlementRequested", withEventValidator(predictionMarketHandler.handleSettlementRequested, "settlementRequested"))
```

### 8.6 REST API Endpoints — `api/src/routes/predictions.routes.ts`

New routes following the existing Elysia pattern:

| Endpoint | Description |
|---|---|
| `GET /api/predictions` | All markets (filter by status, poolId) |
| `GET /api/predictions/:marketId` | Single market detail + totals |
| `GET /api/predictions/:marketId/positions` | All positions for a market |
| `GET /api/user/:address/predictions` | User's prediction history |
| `GET /api/predictions/active` | Open markets not yet expired |

### Indexer Files to Create/Modify

| Action | File |
|--------|------|
| Create | `../clob-indexer/ponder/deployments/PricePrediction.json` |
| Modify | `../clob-indexer/ponder/core-chain-ponder.config.ts` — add PricePrediction contract |
| Modify | `../clob-indexer/ponder/ponder.schema.ts` — add 3 new tables |
| Create | `../clob-indexer/ponder/src/handlers/predictionMarketHandler.ts` |
| Modify | `../clob-indexer/ponder/src/index.ts` — register 6 event handlers |
| Create | `../clob-indexer/api/src/routes/predictions.routes.ts` |
| Modify | `../clob-indexer/api/src/index.ts` — register prediction routes |

---

## Phase 9: Frontend

The frontend lives at `../frontend/` and is a **Vite + React 19 + TanStack React Router** monorepo. New features follow the domain-driven structure in `apps/web/src/features/<feature>/`.

### 9.1 New Feature Module — `apps/web/src/features/predictions/`

```
features/predictions/
├── components/
│   ├── PredictionMarketList.tsx    # Grid of available markets
│   ├── PredictionMarketCard.tsx    # Single market (countdown, pool sizes, % odds)
│   ├── PredictionDetail.tsx        # Market detail with stake form
│   ├── PredictionStakeForm.tsx     # UP/DOWN selection + amount input
│   ├── UserPositions.tsx           # User's active + past positions
│   ├── SettlementCountdown.tsx     # Live countdown timer to endTime
│   └── PrizeClaimButton.tsx        # Claim button (appears after settlement)
├── hooks/
│   ├── usePredictionMarkets.ts     # Fetch markets from indexer
│   ├── useUserPositions.ts         # Fetch user positions
│   ├── usePredictionContract.ts    # Write calls (predict, requestSettlement, claim)
│   └── useMarketCountdown.ts       # Real-time countdown logic
├── types/
│   └── index.ts                    # PredictionMarket, Position, MarketType enums
└── utils/
    └── predictions.ts              # Format odds, payout calculation display
```

### 9.2 Page — `apps/web/src/pages/predictions.tsx`

```typescript
import { lazy } from "react"
import { WebSocketProvider } from "@/providers/websocketProvider"
const PredictionMarketList = lazy(() => import("@/features/predictions/components/PredictionMarketList"))

export default function PredictionsPage() {
  return (
    <WebSocketProvider url={Endpoints.websocket}>
      <div className="w-full min-h-screen">
        <PredictionMarketList />
      </div>
    </WebSocketProvider>
  )
}
```

### 9.3 Route Registration — `apps/web/src/router.tsx`

```typescript
const PredictionsPage = React.lazy(() => import("@/pages/predictions"))

const predictionsRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/predictions",
  component: withSuspense(PredictionsPage),
})

// Add predictionsRoute to the route tree
```

Also add navigation link in the existing sidebar/nav component (reference wherever `trade`, `lending`, `agents` nav items are defined).

### 9.4 Data Hooks

**`usePredictionMarkets.ts`** — fetch from indexer:
```typescript
export const usePredictionMarkets = (filters?: { status?: string; poolId?: string }) => {
  return useQuery({
    queryKey: ["predictions", filters],
    queryFn: () => fetchIndexerAPI<PredictionMarket[]>(`/predictions?${new URLSearchParams(filters)}`),
    refetchInterval: 10_000,  // poll every 10s for status changes
  })
}
```

**`usePredictionContract.ts`** — write calls using wagmi/viem:
```typescript
export const usePredictMarket = () => {
  const { writeContractAsync } = useWriteContract()
  return async (marketId: bigint, isUp: boolean, amount: bigint) => {
    return writeContractAsync({
      address: PRICE_PREDICTION_ADDRESS,
      abi: PricePredictionABI,
      functionName: "predict",
      args: [marketId, isUp, amount],
    })
  }
}
```

### 9.5 Contract Config — `apps/web/src/configs/contracts.ts`

Add PricePrediction ABI and address (keyed by chain ID):
```typescript
export const PREDICTION_CONTRACT = {
  84532: "0x<address-from-84532.json>",
} as const

export { PricePredictionABI } from "@/abis/PricePrediction"
```

### 9.6 Key UI Components

**`PredictionMarketCard.tsx`** — the core user interaction:
- Market name (e.g., "ETH/USDC · 5 min · UP/DOWN")
- Live countdown to end time
- Pool sizes: "UP: 500 USDC (55%) / DOWN: 400 USDC (45%)"
- Potential multiplier: "UP wins → 1.78x your stake"
- Stake button → opens `PredictionStakeForm`

**`PredictionStakeForm.tsx`**:
- Toggle: **UP** | **DOWN** (or **YES** | **NO** for Absolute markets)
- Amount input (min 10 USDC, max shows available balance)
- Shows yield note: "Your 100 USDC earns ~5% APY while locked"
- Confirm button → calls `usePredictMarket()`

**`PrizeClaimButton.tsx`**:
- Shows after market is settled
- Winner: "Claim 178 USDC (78 USDC winnings + yield)"
- Loser: "Claim yield (~0.014 USDC accumulated)"

### Frontend Files to Create/Modify

| Action | File |
|--------|------|
| Create | `../frontend/apps/web/src/features/predictions/` (entire directory) |
| Create | `../frontend/apps/web/src/pages/predictions.tsx` |
| Modify | `../frontend/apps/web/src/router.tsx` — add `/predictions` route |
| Modify | `../frontend/apps/web/src/configs/contracts.ts` — add PricePrediction ABI + address |
| Create | `../frontend/apps/web/src/abis/PricePrediction.ts` — export ABI as const |
| Modify | Nav/sidebar component — add Predictions link |
| Modify | `.env.base-sepolia` — add `VITE_PREDICTION_CONTRACT_ADDRESS` |

---

## ⚠️ Critical Pre-Implementation Checks

Before writing any code, verify these two items by reading the actual source:

1. **`IBalanceManager.sol`**: Does `transferLockedFrom(address from, Currency currency, uint256 amount, address to)` exist? This determines whether the prize pool distribution mechanism (Option A vs Option B) is viable.

2. **`BalanceManager.sol:415`**: Does `unlock(user, currency, 0)` succeed (for yield-only claim on loss), or does it revert on zero amount?

These two answers determine the exact implementation path for `claim()`.

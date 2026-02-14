# Agent Flows and Smart Contract Functions

Complete guide to AI agent workflows and the smart contract functions used at each step.

## 📋 Table of Contents

1. [Agent Lifecycle Flow](#agent-lifecycle-flow)
2. [Trading Flows](#trading-flows)
3. [Lending Flows](#lending-flows)
4. [Smart Contract Function Reference](#smart-contract-function-reference)
5. [Interaction Patterns](#interaction-patterns)
6. [Complete Example Flows](#complete-example-flows)

---

## 1. Agent Lifecycle Flow

### 1.1 Agent Registration Flow

```
Owner → IdentityRegistry.registerAgent()
  ↓
ERC-721 NFT Minted (Agent Token ID assigned)
  ↓
Agent Identity Created
```

**Smart Contract Functions:**
```solidity
// IdentityRegistry.sol
function registerAgent(address owner) external returns (uint256 agentTokenId)
```

**What Happens:**
- Mints an ERC-721 NFT representing the agent identity
- Returns unique `agentTokenId`
- Owner becomes the agent owner
- Agent is now registered but not yet installed with a policy

---

### 1.2 Policy Installation Flow

```
Owner → PolicyFactory.installAgent()
  ↓
Policy Template Applied
  ↓
Agent Installed Event Emitted
  ↓
Agent Ready for Trading
```

**Smart Contract Functions:**
```solidity
// PolicyFactory.sol
function installAgent(
    uint256 agentTokenId,
    string memory templateName,
    bytes memory encodedPolicy
) external returns (address policyAddress)
```

**Parameters:**
- `agentTokenId` - The agent's NFT token ID
- `templateName` - Policy template (e.g., "conservative", "aggressive")
- `encodedPolicy` - Encoded policy parameters (limits, restrictions)

**What Happens:**
- Verifies owner owns the agent NFT
- Creates BeaconProxy for the agent's policy
- Stores policy configuration
- Emits `AgentInstalled` event
- Agent can now execute trades within policy limits

---

### 1.3 Executor Authorization Flow

```
Owner → AgentRouter.authorizeExecutor()
  ↓
Executor Address Added
  ↓
Executor Can Trade on Behalf of Agent
```

**Smart Contract Functions:**
```solidity
// AgentRouter.sol
function authorizeExecutor(
    uint256 agentTokenId,
    address executor
) external onlyAgentOwner(agentTokenId)
```

**What Happens:**
- Verifies caller owns the agent
- Authorizes executor address
- Executor can now call agent trading functions

---

## 2. Trading Flows

### 2.1 Agent Limit Order Flow

```
Executor → AgentRouter.placeLimitOrder()
  ↓
Policy Validation (limits, restrictions)
  ↓
OrderBook.placeLimitOrder() [with agent tracking]
  ↓
Order Placed with agentTokenId & executor recorded
  ↓
Events: AgentLimitOrderPlaced + OrderPlaced
```

**Smart Contract Functions:**
```solidity
// AgentRouter.sol
function placeLimitOrder(
    uint256 agentTokenId,
    address orderBook,
    address baseToken,
    address quoteToken,
    uint256 price,
    uint256 quantity,
    bool isBuy,
    uint256 expiry
) external returns (uint256 orderId)

// Internal call to:
// OrderBook.sol
function placeLimitOrder(
    address user,
    uint256 price,
    uint256 quantity,
    bool isBuy,
    uint256 expiry,
    uint256 agentTokenId,    // Agent tracking
    address executor         // Executor tracking
) external returns (uint256 orderId)
```

**Flow Details:**
1. **Executor calls** `AgentRouter.placeLimitOrder()`
2. **AgentRouter validates:**
   - Executor is authorized for this agent
   - Agent policy allows this trade
   - Order within policy limits
3. **AgentRouter calls** `OrderBook.placeLimitOrder()` with agent tracking
4. **OrderBook:**
   - Records order with `agentTokenId` and `executor`
   - Emits `OrderPlaced` event
5. **AgentRouter emits** `AgentLimitOrderPlaced` event

---

### 2.2 Agent Swap (Market Order) Flow

```
Executor → AgentRouter.executeSwap()
  ↓
Policy Validation
  ↓
ScaleXRouter.swap() [with agent tracking]
  ↓
Swap Executed with agent tracking
  ↓
Event: AgentSwapExecuted
```

**Smart Contract Functions:**
```solidity
// AgentRouter.sol
function executeSwap(
    uint256 agentTokenId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    uint256 deadline
) external returns (uint256 amountOut)

// Internal call to:
// ScaleXRouter.sol
function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    address to,
    uint256 deadline,
    uint256 agentTokenId,    // Agent tracking
    address executor         // Executor tracking
) external returns (uint256 amountOut)
```

**Flow Details:**
1. **Executor calls** `AgentRouter.executeSwap()`
2. **Policy validation** for swap limits
3. **ScaleXRouter.swap()** executed with agent tracking
4. **Swap matched** against orderbook
5. **Event emitted** with agent and executor information

---

### 2.3 Cancel Order Flow

```
Executor → AgentRouter.cancelOrder()
  ↓
Verify Order Ownership (by agent)
  ↓
OrderBook.cancelOrder() [with agent verification]
  ↓
Order Cancelled
  ↓
Event: AgentOrderCancelled
```

**Smart Contract Functions:**
```solidity
// AgentRouter.sol
function cancelOrder(
    uint256 agentTokenId,
    address orderBook,
    uint256 orderId
) external

// Internal call to:
// OrderBook.sol
function cancelOrder(uint256 orderId) external
```

---

## 3. Lending Flows

### 3.1 Agent Borrow Flow

```
Executor → AgentRouter.executeBorrow()
  ↓
Policy Validation (borrow limits, collateral ratio)
  ↓
AutoBorrowHelper.borrow() [with agent tracking]
  ↓
Borrow Executed
  ↓
Event: AgentBorrowExecuted
```

**Smart Contract Functions:**
```solidity
// AgentRouter.sol
function executeBorrow(
    uint256 agentTokenId,
    address asset,
    uint256 amount,
    address onBehalfOf
) external returns (uint256 borrowAmount)

// Internal call to:
// AutoBorrowHelper.sol
function borrow(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint256 agentTokenId
) external returns (uint256)
```

**Flow Details:**
1. **Executor calls** `AgentRouter.executeBorrow()`
2. **Policy checks:**
   - Borrow amount within limits
   - Collateral ratio maintained
   - Health factor > minimum
3. **AutoBorrowHelper.borrow()** executed
4. **Agent receives** borrowed tokens
5. **Event emitted** with agent tracking

---

### 3.2 Agent Repay Flow

```
Executor → AgentRouter.executeRepay()
  ↓
Policy Validation
  ↓
AutoBorrowHelper.repay() [with agent tracking]
  ↓
Debt Repaid
  ↓
Event: AgentRepayExecuted
```

**Smart Contract Functions:**
```solidity
// AgentRouter.sol
function executeRepay(
    uint256 agentTokenId,
    address asset,
    uint256 amount,
    address onBehalfOf
) external returns (uint256 repaidAmount)

// Internal call to:
// AutoBorrowHelper.sol
function repay(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint256 agentTokenId
) external returns (uint256)
```

---

### 3.3 Agent Supply Collateral Flow

```
Executor → AgentRouter.supplyCollateral()
  ↓
Policy Validation
  ↓
AutoBorrowHelper.supply() [with agent tracking]
  ↓
Collateral Supplied
  ↓
Event: AgentCollateralSupplied
```

**Smart Contract Functions:**
```solidity
// AgentRouter.sol
function supplyCollateral(
    uint256 agentTokenId,
    address asset,
    uint256 amount,
    address onBehalfOf
) external returns (uint256 suppliedAmount)

// Internal call to:
// AutoBorrowHelper.sol
function supply(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint256 agentTokenId
) external returns (uint256)
```

---

### 3.4 Agent Withdraw Collateral Flow

```
Executor → AgentRouter.withdrawCollateral()
  ↓
Policy Validation (health factor check)
  ↓
AutoBorrowHelper.withdraw() [with agent tracking]
  ↓
Collateral Withdrawn
  ↓
Event: AgentCollateralWithdrawn
```

**Smart Contract Functions:**
```solidity
// AgentRouter.sol
function withdrawCollateral(
    uint256 agentTokenId,
    address asset,
    uint256 amount,
    address to
) external returns (uint256 withdrawnAmount)

// Internal call to:
// AutoBorrowHelper.sol
function withdraw(
    address asset,
    uint256 amount,
    address to,
    uint256 agentTokenId
) external returns (uint256)
```

---

## 4. Smart Contract Function Reference

### 4.1 IdentityRegistry Functions

| Function | Purpose | Access Control |
|----------|---------|----------------|
| `registerAgent(address owner)` | Register new agent, mint NFT | Public |
| `ownerOf(uint256 agentTokenId)` | Get agent owner | Public (View) |
| `transferFrom(address from, address to, uint256 tokenId)` | Transfer agent ownership | Owner only |

---

### 4.2 PolicyFactory Functions

| Function | Purpose | Access Control |
|----------|---------|----------------|
| `installAgent(uint256, string, bytes)` | Install agent with policy | Agent owner |
| `uninstallAgent(uint256)` | Uninstall agent | Agent owner |
| `updatePolicy(uint256, bytes)` | Update agent policy | Agent owner |
| `getAgentPolicy(uint256)` | Get policy address | Public (View) |

---

### 4.3 AgentRouter Functions

#### Trading Functions
| Function | Purpose | Access Control |
|----------|---------|----------------|
| `placeLimitOrder(...)` | Place limit order | Authorized executor |
| `executeSwap(...)` | Execute market swap | Authorized executor |
| `cancelOrder(...)` | Cancel agent's order | Authorized executor |

#### Lending Functions
| Function | Purpose | Access Control |
|----------|---------|----------------|
| `executeBorrow(...)` | Borrow assets | Authorized executor |
| `executeRepay(...)` | Repay debt | Authorized executor |
| `supplyCollateral(...)` | Supply collateral | Authorized executor |
| `withdrawCollateral(...)` | Withdraw collateral | Authorized executor |

#### Authorization Functions
| Function | Purpose | Access Control |
|----------|---------|----------------|
| `authorizeExecutor(uint256, address)` | Add executor | Agent owner |
| `revokeExecutor(uint256, address)` | Remove executor | Agent owner |
| `isAuthorizedExecutor(uint256, address)` | Check authorization | Public (View) |

---

### 4.4 OrderBook Functions (with Agent Tracking)

| Function | Purpose | Agent Params |
|----------|---------|--------------|
| `placeLimitOrder(...)` | Place order | `agentTokenId`, `executor` |
| `cancelOrder(uint256 orderId)` | Cancel order | Verified via orderId |
| `getOrder(uint256 orderId)` | Get order details | Returns agent data |

**Order Structure:**
```solidity
struct Order {
    uint256 id;
    address user;           // Agent owner
    uint256 price;
    uint256 quantity;
    uint256 filled;
    bool isBuy;
    OrderStatus status;
    uint256 timestamp;
    uint256 expiry;
    // Agent tracking fields
    uint256 agentTokenId;   // 0 for non-agent orders
    address executor;       // Executor who placed the order
}
```

---

## 5. Interaction Patterns

### 5.1 Agent Owner Actions

**What Owners Can Do:**
```solidity
// 1. Register Agent
identityRegistry.registerAgent(ownerAddress);

// 2. Install Policy
policyFactory.installAgent(agentTokenId, "conservative", encodedPolicy);

// 3. Authorize Executor
agentRouter.authorizeExecutor(agentTokenId, executorAddress);

// 4. Transfer Agent
identityRegistry.transferFrom(owner, newOwner, agentTokenId);

// 5. Uninstall Agent
policyFactory.uninstallAgent(agentTokenId);
```

---

### 5.2 Executor Actions

**What Executors Can Do:**
```solidity
// 1. Place Limit Order
agentRouter.placeLimitOrder(
    agentTokenId,
    orderBookAddress,
    baseToken,
    quoteToken,
    price,
    quantity,
    isBuy,
    expiry
);

// 2. Execute Swap
agentRouter.executeSwap(
    agentTokenId,
    tokenIn,
    tokenOut,
    amountIn,
    minAmountOut,
    deadline
);

// 3. Borrow
agentRouter.executeBorrow(
    agentTokenId,
    asset,
    amount,
    onBehalfOf
);

// 4. Supply Collateral
agentRouter.supplyCollateral(
    agentTokenId,
    asset,
    amount,
    onBehalfOf
);
```

---

## 6. Complete Example Flows

### Example 1: Agent Trading Flow (End-to-End)

```
Step 1: Register Agent
-----------------------
Owner → IdentityRegistry.registerAgent(ownerAddress)
Returns: agentTokenId = 100

Step 2: Install Policy
----------------------
Owner → PolicyFactory.installAgent(
    agentTokenId: 100,
    template: "conservative",
    policy: encodedPolicyData
)
Returns: policyAddress

Step 3: Authorize Executor
--------------------------
Owner → AgentRouter.authorizeExecutor(
    agentTokenId: 100,
    executor: 0xExecutorAddress
)

Step 4: Fund Agent
-----------------
Owner → Transfer WETH to agent owner address
Owner → Approve OrderBook to spend WETH

Step 5: Place Order
------------------
Executor → AgentRouter.placeLimitOrder(
    agentTokenId: 100,
    orderBook: 0xOrderBookAddress,
    baseToken: WETH,
    quoteToken: IDRX,
    price: 300000 (0.3 IDRX per WETH),
    quantity: 10000000000000000 (0.01 WETH),
    isBuy: true,
    expiry: timestamp + 90 days
)

Flow Inside:
  → AgentRouter validates executor authorization
  → AgentRouter checks policy limits
  → AgentRouter calls OrderBook.placeLimitOrder()
  → OrderBook records order with agentTokenId=100 and executor
  → OrderBook emits OrderPlaced event
  → AgentRouter emits AgentLimitOrderPlaced event

Result:
  → Order placed successfully
  → Order ID: 6
  → Visible in indexer with agent tracking
```

---

### Example 2: Agent Lending Flow (End-to-End)

```
Step 1-3: Same as Example 1 (Register, Install, Authorize)

Step 4: Supply Collateral
-------------------------
Executor → AgentRouter.supplyCollateral(
    agentTokenId: 100,
    asset: WETH,
    amount: 1 ether,
    onBehalfOf: agentOwner
)

Flow Inside:
  → Validates executor
  → Checks policy allows collateral supply
  → Calls AutoBorrowHelper.supply() with agent tracking
  → LendingManager records collateral
  → Emits AgentCollateralSupplied event

Step 5: Borrow
-------------
Executor → AgentRouter.executeBorrow(
    agentTokenId: 100,
    asset: IDRX,
    amount: 100000 (1000 IDRX),
    onBehalfOf: agentOwner
)

Flow Inside:
  → Validates executor
  → Checks policy borrow limits
  → Validates health factor
  → Calls AutoBorrowHelper.borrow() with agent tracking
  → LendingManager records debt
  → Transfers IDRX to agent owner
  → Emits AgentBorrowExecuted event

Step 6: Repay
------------
Executor → AgentRouter.executeRepay(
    agentTokenId: 100,
    asset: IDRX,
    amount: 50000 (500 IDRX),
    onBehalfOf: agentOwner
)

Flow Inside:
  → Validates executor
  → Calls AutoBorrowHelper.repay() with agent tracking
  → LendingManager reduces debt
  → Emits AgentRepayExecuted event
```

---

## 7. Event Tracking

All agent operations emit events for indexing:

```solidity
// Policy Events
event AgentInstalled(address indexed owner, uint256 indexed agentTokenId, string templateUsed, uint256 timestamp);
event AgentUninstalled(address indexed owner, uint256 indexed agentTokenId, uint256 timestamp);

// Trading Events
event AgentSwapExecuted(address indexed owner, uint256 indexed agentTokenId, address executor, ...);
event AgentLimitOrderPlaced(address indexed owner, uint256 indexed agentTokenId, address executor, ...);
event AgentOrderCancelled(address indexed owner, uint256 indexed agentTokenId, address executor, ...);

// Lending Events
event AgentBorrowExecuted(address indexed owner, uint256 indexed agentTokenId, address executor, ...);
event AgentRepayExecuted(address indexed owner, uint256 indexed agentTokenId, address executor, ...);
event AgentCollateralSupplied(address indexed owner, uint256 indexed agentTokenId, address executor, ...);
event AgentCollateralWithdrawn(address indexed owner, uint256 indexed agentTokenId, address executor, ...);
```

**All events include:**
- `owner` - Agent owner address
- `agentTokenId` - Agent NFT ID
- `executor` - Who executed the transaction
- Operation-specific details

---

## 8. Contract Addresses (Base Sepolia)

```
IdentityRegistry: 0x97EE6eaa3e9B0D33813102554f7B9CC4D521e89D
PolicyFactory:    0x4605f626dF4A684139186B7fF15C8cABD8178EC8
AgentRouter:      0x36f229515bf0e4c74165b214c56bE8c0b49a1574
AutoBorrowHelper: 0x0Fb09456C73faBEd6e557eCCDB5D7F8e4D6B8E90

OrderBook (WETH-IDRX): 0x629a14Ee7dc9D29a5EB676fbCEF94e989bc0dEa1
ScaleXRouter:          0xc882b5af2B1AFB37CDe4D1f696fb112979cf98EE
```

---

## 9. Quick Reference

**Agent Setup:**
1. `IdentityRegistry.registerAgent()` → Get agentTokenId
2. `PolicyFactory.installAgent()` → Install policy
3. `AgentRouter.authorizeExecutor()` → Authorize executor

**Trading:**
- Limit Order: `AgentRouter.placeLimitOrder()`
- Market Swap: `AgentRouter.executeSwap()`
- Cancel: `AgentRouter.cancelOrder()`

**Lending:**
- Supply: `AgentRouter.supplyCollateral()`
- Borrow: `AgentRouter.executeBorrow()`
- Repay: `AgentRouter.executeRepay()`
- Withdraw: `AgentRouter.withdrawCollateral()`

---

**Last Updated:** February 13, 2026
**Network:** Base Sepolia (Chain ID: 84532)
**ERC Standard:** ERC-8004 (AI Agent Identity & Delegation)

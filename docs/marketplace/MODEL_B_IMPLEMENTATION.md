# Model B: Agent-Based Authorization Implementation

## Overview

Model B allows users to authorize AI agents by their Agent ID (NFT token ID) instead of authorizing executor wallet addresses. This enables a more intuitive marketplace where users "hire" agents directly.

---

## The Model

### User Flow

```
1. Alice owns Agent #500
2. Alice registers executor wallet for Agent #500
3. Bob subscribes to Agent #500's strategy
4. Bob authorizes Agent #500 (by ID, not wallet address)
5. Alice's executor can now trade for Bob
6. Alice's service checks: Has Bob paid?
   ├── YES → Execute trades for Bob
   └── NO → Skip Bob
```

### Key Difference from Model A

**Model A (Current):**
```
Bob authorizes: 0xALICE_EXECUTOR (wallet address)
└── Bob needs to know Alice's executor wallet address
```

**Model B (New):**
```
Bob authorizes: Agent #500 (agent ID)
└── Bob only needs to know agent ID from marketplace
└── Contract looks up which wallet can execute for Agent #500
```

---

## Smart Contract Changes Required

### 1. AgentRouter.sol - Add Agent Registration

```solidity
// New state: Map agent ID to its executor wallet
mapping(uint256 => address) public agentExecutors;

// New event
event AgentExecutorRegistered(uint256 indexed agentTokenId, address indexed executor);

/**
 * @notice Agent owner registers executor wallet for their agent
 * @dev Only the agent owner can register/update executor
 * @param agentTokenId The agent's token ID
 * @param executor The wallet address that will execute trades for this agent
 */
function registerAgentExecutor(uint256 agentTokenId, address executor) external {
    require(identityRegistry.ownerOf(agentTokenId) == msg.sender, "Not agent owner");
    require(executor != address(0), "Invalid executor");

    agentExecutors[agentTokenId] = executor;
    emit AgentExecutorRegistered(agentTokenId, executor);
}

/**
 * @notice Get executor wallet for an agent
 * @param agentTokenId The agent's token ID
 * @return executor The registered executor wallet
 */
function getAgentExecutor(uint256 agentTokenId) external view returns (address) {
    return agentExecutors[agentTokenId];
}
```

### 2. AgentRouter.sol - Add Agent-Based Authorization

```solidity
// New state: Users authorize strategy agents (not executor wallets)
mapping(address => mapping(uint256 => bool)) public authorizedStrategyAgents;

// New event
event StrategyAgentAuthorized(address indexed user, uint256 indexed userAgentId, uint256 indexed strategyAgentId);
event StrategyAgentRevoked(address indexed user, uint256 indexed userAgentId, uint256 indexed strategyAgentId);

/**
 * @notice User authorizes a strategy agent (simple interface!)
 * @dev User (msg.sender) authorizes the STRATEGY agent (e.g., Agent #500)
 * @param strategyAgentId Developer's strategy agent ID to authorize
 *
 * Policy restrictions come from user's personal agent during execution
 */
function authorize(uint256 strategyAgentId) external {
    require(agentExecutors[strategyAgentId] != address(0), "Strategy agent has no executor");

    authorizedStrategyAgents[msg.sender][strategyAgentId] = true;
    emit StrategyAgentAuthorized(msg.sender, 0, strategyAgentId);
}

/**
 * @notice User revokes authorization for a strategy agent
 */
function revoke(uint256 strategyAgentId) external {
    authorizedStrategyAgents[msg.sender][strategyAgentId] = false;
    emit StrategyAgentRevoked(msg.sender, 0, strategyAgentId);
}

/**
 * @notice Check if user authorized a strategy agent
 */
function isAuthorized(address user, uint256 strategyAgentId) external view returns (bool) {
    return authorizedStrategyAgents[user][strategyAgentId];
}
```

### 3. AgentRouter.sol - Update Trade Execution

```solidity
/**
 * @notice Execute limit order using agent-based authorization
 * @param userAgentId User's personal agent ID (e.g., Bob's Agent #101)
 * @param strategyAgentId Strategy agent ID being used (e.g., Alice's Agent #500)
 */
function executeLimitOrder(
    uint256 userAgentId,
    uint256 strategyAgentId,  // NEW PARAMETER
    IPoolManager.Pool memory pool,
    uint256 price,
    uint256 quantity,
    IOrderBook.Side side,
    IOrderBook.TimeInForce timeInForce,
    bool autoRepay,
    bool autoBorrow
) external returns (uint48 orderId) {
    // Get user (owner of personal agent)
    address user = identityRegistry.ownerOf(userAgentId);

    // CRITICAL CHECK: Verify executor authorization via strategy agent
    address strategyExecutor = agentExecutors[strategyAgentId];
    require(strategyExecutor != address(0), "Strategy agent has no executor");
    require(msg.sender == strategyExecutor, "Not strategy executor");
    require(authorizedStrategyAgents[user][strategyAgentId], "Strategy agent not authorized");

    // Get user's policy (enforced on user's personal agent)
    PolicyFactory.Policy memory policy = policyFactory.getPolicy(user, userAgentId);
    require(policy.enabled, "Agent disabled");
    require(block.timestamp <= policy.expiryTimestamp, "Agent expired");

    // Rest of execution logic...
    // (policy enforcement, balance checks, order placement)
}
```

---

## Complete Flow Example

### Setup Phase

**Alice (Developer):**
```solidity
// 1. Alice registers her strategy agent
uint256 strategyAgentId = identityRegistry.register();
// Returns: 500

// 2. Alice registers her executor wallet for Agent #500
agentRouter.registerAgentExecutor(500, 0xALICE_EXECUTOR);
```

**Bob (User):**
```solidity
// 1. Bob registers his personal agent
uint256 userAgentId = identityRegistry.register();
// Returns: 101

// 2. Bob installs his own policy
policyFactory.installAgentFromTemplate(
    101,
    "conservative",
    customizations
);

// 3. Bob authorizes Agent #500 (Alice's strategy)
// Simple! Just authorize(strategyAgentId)
agentRouter.authorize(500);
// Now Agent #500 can trade for Bob (using Bob's Agent #101 policy)
```

### Execution Phase

**Alice's Trading Service:**
```javascript
// Off-chain: Check if Bob has paid subscription
const hasPaid = await checkSubscription(bob, strategyAgentId: 500);

if (hasPaid) {
    // Execute trade for Bob using his Agent #101
    await agentRouter.executeLimitOrder(
        userAgentId: 101,        // Bob's personal agent
        strategyAgentId: 500,    // Alice's strategy agent
        pool,
        price,
        quantity,
        side,
        timeInForce,
        autoRepay,
        autoBorrow
    );
}
```

### Smart Contract Checks

```solidity
function executeLimitOrder(
    uint256 userAgentId,      // 101 (Bob's agent)
    uint256 strategyAgentId,  // 500 (Alice's strategy)
    ...
) {
    // 1. Get user
    address user = identityRegistry.ownerOf(101);
    // Returns: 0xBOB...

    // 2. Get strategy executor
    address executor = agentExecutors[500];
    // Returns: 0xALICE_EXECUTOR

    // 3. Verify caller is strategy executor
    require(msg.sender == executor);
    // msg.sender must be 0xALICE_EXECUTOR

    // 4. Verify Bob authorized Agent #500
    require(authorizedStrategyAgents[0xBOB...][500]);
    // Bob must have called authorizeStrategyAgent(101, 500)

    // 5. Get Bob's policy (from his Agent #101)
    Policy memory policy = policyFactory.getPolicy(0xBOB..., 101);

    // 6. Enforce Bob's policy limits
    require(quantity <= policy.maxOrderSize);

    // 7. Execute trade using Bob's funds
    // ...
}
```

---

## Database Schema Updates

### New Table: agent_executors

```sql
CREATE TABLE agent_executors (
    agent_id BIGINT PRIMARY KEY,
    executor_address VARCHAR(42) NOT NULL,
    registered_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(agent_id)
);

CREATE INDEX idx_executor_address ON agent_executors(executor_address);
```

### Update subscriptions table

```sql
ALTER TABLE subscriptions
ADD COLUMN strategy_agent_id BIGINT NOT NULL REFERENCES agents(agent_id);

-- Bob subscribes to Agent #500
INSERT INTO subscriptions (
    user_wallet,
    user_agent_id,
    strategy_agent_id,
    paid_until
) VALUES (
    '0xBOB...',
    101,
    500,
    '2026-03-15'
);
```

---

## Migration Path

### Phase 1: Deploy Updated Contracts

1. Update `AgentRouter.sol` with new functions
2. Deploy new version (upgradeable)
3. Test on testnet

### Phase 2: Data Migration

1. Existing executor authorizations remain valid
2. Developers register their agent executors:
   ```solidity
   agentRouter.registerAgentExecutor(strategyAgentId, executorWallet);
   ```
3. Users migrate to agent-based authorization:
   ```solidity
   agentRouter.authorizeStrategyAgent(userAgentId, strategyAgentId);
   ```

### Phase 3: Deprecation

1. Support both models during transition period
2. Eventually deprecate wallet-based authorization
3. Require agent-based authorization for new users

---

## Advantages of Model B

### 1. Better UX
```
User sees: "Subscribe to Agent #500"
User authorizes: Agent #500

vs.

User sees: "Subscribe to Agent #500"
User needs to find: Executor wallet address
User authorizes: 0xALICE_EXECUTOR (confusing!)
```

### 2. Developer Flexibility
```
Alice can change executor wallet without users re-authorizing:
├── Old: 0xALICE_EXECUTOR_OLD
└── New: 0xALICE_EXECUTOR_NEW

Alice calls: registerAgentExecutor(500, NEW_WALLET)
Bob's authorization still valid (authorized Agent #500, not wallet)
```

### 3. Marketplace Integration
```
Marketplace shows:
┌─────────────────────────────┐
│ 🤖 Agent #500               │
│ "WETH/IDRX Strategy"        │
│                             │
│ [Subscribe] ← One click     │
│   └── Calls: authorizeStrategyAgent(userAgentId, 500)
└─────────────────────────────┘
```

### 4. Clear Separation
```
Strategy Agent #500:
├── Registered executor: 0xALICE_EXECUTOR
└── Users authorize: Agent #500 (not wallet)

User Agent #101:
├── Owner: Bob
├── Policy: Conservative
└── Authorized strategies: [Agent #500]
```

---

## Security Considerations

### 1. Agent Owner Control
- Only agent owner can register/change executor
- Prevents unauthorized executor changes

### 2. User Authorization
- Users explicitly authorize strategy agents
- Can revoke at any time
- Per-strategy authorization (not blanket)

### 3. Policy Enforcement
- User's policy still enforced on their personal agent
- Strategy can't bypass user's risk limits

### 4. Fund Custody
- User maintains custody via BalanceManager
- Executor can only trade within policy limits
- User can withdraw funds anytime

---

## Testing Requirements

### Unit Tests

1. **Agent Executor Registration**
   - Only owner can register
   - Can update executor
   - Cannot set zero address

2. **Strategy Authorization**
   - User can authorize strategy
   - User can revoke strategy
   - Non-owner cannot authorize

3. **Trade Execution**
   - Executor can trade if authorized
   - Non-executor cannot trade
   - Revoked authorization blocks trades

### Integration Tests

1. **Complete Flow**
   - Developer registers agent + executor
   - User registers agent + policy
   - User authorizes strategy agent
   - Executor places order successfully
   - Policy enforced correctly

2. **Edge Cases**
   - Executor change mid-subscription
   - Multiple strategies per user
   - Authorization revocation
   - Expired policies

---

## Summary

### What Changes

**Smart Contracts:**
- ✅ AgentRouter: Add agent executor registration
- ✅ AgentRouter: Add strategy agent authorization
- ✅ AgentRouter: Update executeLimitOrder signature

**Database:**
- ✅ New table: agent_executors
- ✅ Update subscriptions table

**Frontend:**
- ✅ UI for agent authorization (not wallet authorization)
- ✅ Show strategy agent ID in marketplace

### What Stays the Same

- ✅ ERC-8004 agent NFTs
- ✅ PolicyFactory (users still set own policies)
- ✅ BalanceManager (fund custody)
- ✅ Order execution logic
- ✅ Off-chain payment verification

### Timeline

- Week 1-2: Smart contract updates
- Week 3: Testing and deployment
- Week 4: Backend integration
- Week 5-6: Frontend updates
- Week 7: Migration and launch

---

## Next Steps

1. Update `AgentRouter.sol` with Model B functions
2. Create comprehensive tests
3. Deploy to testnet
4. Create verification script
5. Update documentation
6. Plan migration strategy

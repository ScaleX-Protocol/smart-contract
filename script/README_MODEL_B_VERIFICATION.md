# Model B Verification Script - Agent-Based Authorization

## Overview

Model B enables users to authorize AI agents by their **Agent ID** (NFT token ID) instead of executor wallet addresses. This creates a more intuitive marketplace where users "hire" agents directly.

## Key Difference: Model A vs Model B

### Model A (Legacy - Wallet Authorization)

```
User authorizes: 0xALICE_EXECUTOR (wallet address)
Problem: User needs to know/trust the wallet address
```

### Model B (New - Agent Authorization)

```
User authorizes: Agent #500 (agent ID)
Advantage: User only needs to know agent ID from marketplace
Contract automatically looks up which wallet executes for Agent #500
```

---

## What This Script Proves

✅ Developer can register strategy agent and executor wallet
✅ User can authorize strategy AGENT (not wallet)
✅ Executor can trade for user using agent-based authorization
✅ User's policy is enforced correctly
✅ Users maintain custody of their funds
✅ Marketplace UX is simpler (authorize by agent ID)

---

## Prerequisites

### Environment Variables

```bash
# Network
SCALEX_CORE_RPC=https://base-sepolia.infura.io/v3/YOUR_KEY

# Developer wallet (will register strategy agent)
PRIVATE_KEY=0x...

# User wallet (will subscribe to strategy)
PRIVATE_KEY_2=0x...

# Executor wallet (will trade on behalf of users)
AGENT_EXECUTOR_1_KEY=0x...
```

### Required Balances

- Developer wallet: ~0.05 ETH for gas
- User wallet: ~0.05 ETH for gas
- Executor wallet: ~0.01 ETH for gas

---

## Running the Script

### Step 1: Dry Run (Simulation)

Test without broadcasting transactions:

```bash
forge script script/VerifyMarketplaceModelB.s.sol:VerifyMarketplaceModelB \
  --rpc-url $SCALEX_CORE_RPC \
  -vvvv
```

### Step 2: Execute on Testnet

Actually execute the transactions:

```bash
forge script script/VerifyMarketplaceModelB.s.sol:VerifyMarketplaceModelB \
  --rpc-url $SCALEX_CORE_RPC \
  --broadcast \
  -vvvv
```

---

## What The Script Does

### STEP 1: Developer (Alice) Setup

**1a. Register Strategy Agent**
- Developer calls `IdentityRegistry.register()`
- Gets Strategy Agent NFT (e.g., Agent #500)
- This is Alice's trading strategy identity

**1b. Register Executor Wallet**
- Developer calls `agentRouter.registerAgentExecutor(500, 0xALICE_EXECUTOR)`
- Links Agent #500 to executor wallet
- This tells contract: "Agent #500 is operated by 0xALICE_EXECUTOR"

**Key Point:**
```
Strategy Agent #500:
├── Owner: Alice
├── Executor: 0xALICE_EXECUTOR (registered)
└── Policy: NONE (strategy agents don't have policies!)
```

### STEP 2: User (Bob) Setup

**2a. Register Personal Agent**
- User calls `IdentityRegistry.register()`
- Gets Personal Agent NFT (e.g., Agent #101)
- This is Bob's trading account

**2b. Install Personal Policy**
- User calls `PolicyFactory.installAgentFromTemplate()`
- Installs CONSERVATIVE policy:
  - Max order size: 1,000 IDRX
  - Daily volume limit: 5,000 IDRX
- This is BOB'S risk management, not Alice's

**Key Point:**
```
User Agent #101:
├── Owner: Bob
├── Policy: CONSERVATIVE (Bob's choice)
└── Funds: Will hold Bob's money
```

### STEP 3: User Authorizes Strategy Agent

**User calls:**
```solidity
agentRouter.authorizeStrategyAgent(
    userAgentId: 101,        // Bob's personal agent
    strategyAgentId: 500     // Alice's strategy agent
);
```

**What this means:**
- Bob is saying: "Agent #500 can manage my Agent #101"
- Bob does NOT need to know Alice's executor wallet address
- Bob only needs to know Agent #500's ID (from marketplace)

**Smart Contract Records:**
```
authorizedStrategyAgents[BOB][500] = true
```

### STEP 4: Fund User

- Deployer mints 10,000 IDRX to Bob
- Bob approves BalanceManager
- Bob deposits 10,000 IDRX to BalanceManager

### STEP 5: Executor Places Order

**Executor calls:**
```solidity
agentRouter.executeLimitOrder(
    userAgentId: 101,        // Bob's personal agent
    strategyAgentId: 500,    // Alice's strategy agent
    pool,
    price,
    quantity,
    ...
);
```

**Smart Contract Checks:**

1. **Get user:**
   ```solidity
   address user = identityRegistry.ownerOf(101);
   // Returns: 0xBOB...
   ```

2. **Get strategy executor:**
   ```solidity
   address executor = agentExecutors[500];
   // Returns: 0xALICE_EXECUTOR
   ```

3. **Verify caller is strategy executor:**
   ```solidity
   require(msg.sender == executor);
   // msg.sender must be 0xALICE_EXECUTOR
   ```

4. **Verify Bob authorized Agent #500:**
   ```solidity
   require(authorizedStrategyAgents[BOB][500]);
   // Bob must have called authorizeStrategyAgent
   ```

5. **Get Bob's policy:**
   ```solidity
   Policy memory policy = policyFactory.getPolicy(BOB, 101);
   // Returns: Bob's CONSERVATIVE policy
   ```

6. **Enforce Bob's policy:**
   ```solidity
   require(quantity <= policy.maxOrderSize);
   // 1000 IDRX ✓, 2000 IDRX ❌
   ```

7. **Execute trade using Bob's funds**

**Tests:**

- **Test A:** 2,000 IDRX order → REJECTED (exceeds Bob's 1,000 limit)
- **Test B:** 1,000 IDRX order → SUCCESS (within Bob's limit)

---

## Expected Output

```
================================================
MODEL B VERIFICATION
(Agent-Based Authorization)
================================================

STEP 1: Developer (Alice) Setup
------------------------------------------------
1a. Developer registering strategy agent...
  Strategy Agent ID: 500
  Owner: 0xALICE...
1b. Developer registering executor wallet...
  Executor wallet: 0xALICE_EXECUTOR...
  ✓ Executor registered for Strategy Agent #500
  ✓ Executor registration verified

Note: Strategy agent has NO policy (it's just an identity)

STEP 2: User (Bob) Setup
------------------------------------------------
2a. User registering personal agent...
  User Agent ID: 101
  Owner: 0xBOB...
2b. User installing CONSERVATIVE policy...
  Policy template: conservative
  Max order size: 1,000 IDRX
  Daily volume limit: 5,000 IDRX
  ✓ Policy installed and verified

STEP 3: User Authorizes Strategy Agent
------------------------------------------------
User authorizing Strategy Agent #500
  User's Personal Agent: #101
  Strategy Agent to authorize: #500
  ✓ Strategy agent authorized
  ✓ Authorization verified

Note: User authorized Agent #500
      NOT wallet address 0xALICE_EXECUTOR...

STEP 4: Fund User
------------------------------------------------
Minting 10,000 IDRX to user...
User depositing to BalanceManager...
  User balance: 10000 IDRX
  ✓ User funded with 10,000 IDRX

STEP 5: Executor Places Order for User
------------------------------------------------
Executor wallet: 0xALICE_EXECUTOR...
Strategy Agent ID: 500
User Agent ID: 101

Test A: Placing 2000 IDRX order (exceeds user's 1000 limit)
  ✓ Order rejected (policy violation)

Test B: Placing 1000 IDRX order (within user's limit)
  ✓ Order placed successfully!
  Order ID: 42
  User Agent ID: 101
  Strategy Agent ID: 500
  Executor: 0xALICE_EXECUTOR...
  User (owner): 0xBOB...
  Amount: 1000 IDRX (enforced by user's policy)

  KEY INSIGHT:
  - User authorized Agent #500
  - Contract looked up executor wallet for Agent #500
  - Found executor: 0xALICE_EXECUTOR...
  - Executor successfully traded for user

================================================
✓ MODEL B VERIFICATION COMPLETE
================================================
```

---

## Success Criteria

✅ Developer registers strategy agent
✅ Developer registers executor for strategy agent
✅ User registers personal agent
✅ User installs personal policy
✅ User authorizes strategy AGENT (not wallet)
✅ Executor's excessive order rejected by user's policy
✅ Executor's valid order succeeds
✅ Order uses user's funds
✅ Order tracked with user's agent ID
✅ Reputation tracked on strategy agent ID

---

## Advantages of Model B

### 1. Better User Experience

**Model A:**
```
Marketplace shows: "Agent #500 by Alice"
User needs to find: "Executor wallet: 0xALICE_EXECUTOR..."
User authorizes: 0xALICE_EXECUTOR (confusing!)
```

**Model B:**
```
Marketplace shows: "Agent #500 by Alice"
User clicks: [Subscribe]
User authorizes: Agent #500 (intuitive!)
```

### 2. Developer Flexibility

Alice can change her executor wallet without users re-authorizing:

```solidity
// Alice upgrades her infrastructure
agentRouter.registerAgentExecutor(500, NEW_WALLET);

// Bob's authorization still valid!
// Bob authorized Agent #500, not the wallet
```

### 3. Clear Marketplace Listings

```
┌─────────────────────────────┐
│ 🤖 Agent #500               │
│ "WETH/IDRX Market Maker"    │
│ by Alice                    │
│                             │
│ Performance: +15% APY       │
│ Risk: Moderate              │
│ Subscribers: 142            │
│                             │
│ [Subscribe Now]             │
│   └── Authorizes Agent #500 │
└─────────────────────────────┘
```

### 4. Trustless Discovery

Users can:
- Browse marketplace by agent ID
- Check agent's on-chain performance
- Authorize agent by ID (not wallet)
- Revoke authorization anytime

No need to trust wallet addresses!

---

## Security Considerations

### 1. Agent Owner Control

- Only agent owner can register/change executor
- Prevents unauthorized executor changes
- Users can verify executor on-chain

### 2. User Authorization

- Users explicitly authorize strategy agents
- Can revoke at any time
- Per-strategy authorization (granular control)

### 3. Policy Enforcement

- User's policy enforced on personal agent
- Strategy cannot bypass user's risk limits
- Each user has different policy

### 4. Fund Custody

- User maintains custody via BalanceManager
- Executor can only trade within policy
- User can withdraw funds anytime

---

## Comparison: Model A vs Model B

| Aspect | Model A (Wallet Auth) | Model B (Agent Auth) |
|--------|----------------------|---------------------|
| **User authorizes** | Executor wallet address | Strategy agent ID |
| **UX** | Need to find wallet address | Just click agent ID |
| **Developer flexibility** | Wallet change = re-auth | Wallet change = no re-auth |
| **Marketplace** | Shows wallet addresses | Shows agent IDs |
| **Trust model** | Trust wallet address | Trust agent identity |
| **Contract changes** | ❌ None (current) | ✅ Required |

---

## Migration Path (If Deploying Model B)

### Phase 1: Update Contracts

1. Deploy updated `AgentRouter` with Model B functions
2. Test on testnet
3. Run this verification script

### Phase 2: Developer Adoption

1. Existing developers register executors:
   ```solidity
   agentRouter.registerAgentExecutor(agentId, executorWallet);
   ```

2. Marketplace updated to show:
   - Agent IDs (not wallet addresses)
   - Subscribe button → `authorizeStrategyAgent()`

### Phase 3: User Migration

1. Support both models during transition
2. New users: Use Model B (authorize by agent ID)
3. Existing users: Can continue with Model A or migrate

### Phase 4: Sunset Model A (Optional)

1. Deprecate wallet-based authorization
2. All new subscriptions use Model B
3. Legacy authorizations honored but not created

---

## Troubleshooting

### "Strategy agent has no executor"

- Developer must call `registerAgentExecutor()` first
- Check `agentRouter.getStrategyExecutor(agentId)` returns non-zero

### "Not strategy executor"

- msg.sender must be the registered executor
- Check `agentExecutors[strategyAgentId] == msg.sender`

### "Strategy agent not authorized"

- User must call `authorizeStrategyAgent()` first
- Check `agentRouter.isStrategyAgentAuthorized(user, strategyAgentId)`

### "Order too large" (policy violation)

- User's policy enforced correctly!
- Order exceeds `policy.maxOrderSize`
- Try smaller order within limit

---

## Next Steps

After verification succeeds:

1. ✅ Model B works with updated contracts
2. → Update frontend marketplace UI
3. → Update backend to track agent-user subscriptions
4. → Update developer documentation
5. → Plan migration for existing users
6. → Deploy to mainnet

---

## Related Documentation

- Model B Implementation Plan: `/docs/marketplace/MODEL_B_IMPLEMENTATION.md`
- Agent Flows: `/docs/agent-system/AGENT_FLOWS_AND_FUNCTIONS.md`
- Marketplace Model: `/docs/marketplace/MARKETPLACE_MODEL_EXPLAINED.md`
- Two Types of Agents: `/docs/marketplace/TWO_TYPES_OF_AGENTS_EXPLAINED.md`

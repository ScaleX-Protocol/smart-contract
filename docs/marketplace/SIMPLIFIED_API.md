# Simplified API - Model B

## The Simplest Possible Interface

Based on user feedback, Model B now uses the **simplest possible API** for authorization:

```solidity
// User authorizes a strategy agent
agentRouter.authorize(strategyAgentId);

// User revokes authorization
agentRouter.revoke(strategyAgentId);

// Check if authorized
bool isAuth = agentRouter.isAuthorized(userAddress, strategyAgentId);
```

**That's it!** No need to pass user agent ID during authorization.

---

## How It Works

### 1. User Authorization (Simple!)

```solidity
// Bob wants to subscribe to Alice's Strategy Agent #500
agentRouter.authorize(500);
```

**What happens:**
- `msg.sender` (Bob) is recorded as authorizing Agent #500
- Contract stores: `authorizedStrategyAgents[BOB][500] = true`
- Bob's policy comes from his personal agent during execution

### 2. Trade Execution (Policy-Aware)

```solidity
// Alice's executor trades for Bob
agentRouter.executeLimitOrder(
    userAgentId: 101,        // Bob's personal agent (has policy!)
    strategyAgentId: 500,    // Alice's strategy agent
    pool,
    price,
    quantity,
    ...
);
```

**What happens:**
1. Contract gets user: `user = ownerOf(101)` → `0xBOB`
2. Contract checks: `authorizedStrategyAgents[BOB][500]` → `true` ✓
3. Contract gets policy: `policy = getPolicy(BOB, 101)` → Bob's conservative policy
4. Contract enforces: `quantity <= policy.maxOrderSize` ✓
5. Trade executes!

---

## Complete Flow Example

### Setup Phase

**Alice (Developer):**
```solidity
// 1. Register strategy agent
uint256 strategyAgentId = identityRegistry.register();
// Returns: 500

// 2. Register executor wallet
agentRouter.registerAgentExecutor(500, 0xALICE_EXECUTOR);
```

**Bob (User):**
```solidity
// 1. Register personal agent
uint256 userAgentId = identityRegistry.register();
// Returns: 101

// 2. Install policy on personal agent
policyFactory.installAgentFromTemplate(
    101,
    "conservative",
    PolicyCustomization({
        maxOrderSize: 1000e6,
        dailyVolumeLimit: 5000e6,
        ...
    })
);

// 3. Authorize strategy agent (ONE LINE!)
agentRouter.authorize(500);
```

### Execution Phase

**Alice's Service:**
```javascript
// Check payment (off-chain)
const hasPaid = await db.query(`
    SELECT * FROM subscriptions
    WHERE user_address = $1
    AND strategy_agent_id = 500
    AND paid_until > NOW()
`, [bobAddress]);

if (hasPaid) {
    // Execute trade
    await agentRouter.executeLimitOrder(
        101,  // Bob's agent (determines policy)
        500,  // Alice's strategy (determines executor)
        ...
    );
}
```

**Smart Contract:**
```solidity
function executeLimitOrder(uint256 userAgentId, uint256 strategyAgentId, ...) {
    // 1. Verify authorization
    address user = identityRegistry.ownerOf(userAgentId);  // Bob
    address executor = agentExecutors[strategyAgentId];    // Alice's executor

    require(msg.sender == executor, "Not executor");
    require(authorizedStrategyAgents[user][strategyAgentId], "Not authorized");

    // 2. Get and enforce policy
    Policy memory policy = policyFactory.getPolicy(user, userAgentId);
    require(quantity <= policy.maxOrderSize, "Order too large");

    // 3. Execute trade
    // ...
}
```

---

## Why This Design?

### Problem: Original Design Was Too Complex

```solidity
// ❌ Too many parameters!
authorizeStrategyAgent(userAgentId, strategyAgentId)
```

Users asked: "Why do I need to pass my agent ID? You already know it's me (msg.sender)!"

### Solution: Simplified Interface

```solidity
// ✅ Simple and intuitive!
authorize(strategyAgentId)
```

**Benefits:**
- **Simpler UX:** One parameter instead of two
- **Less error-prone:** Can't pass wrong userAgentId
- **Clearer intent:** "I want to authorize this strategy"
- **Frontend simplicity:** Just `authorize(agentId)`

---

## Frontend Code

### Ultra-Simple Subscribe Button

```javascript
async function subscribeToStrategy(strategyAgentId) {
    try {
        // Just one function call with one parameter!
        const tx = await agentRouter.authorize(strategyAgentId);
        await tx.wait();

        console.log(`✓ Subscribed to Agent #${strategyAgentId}`);
    } catch (error) {
        console.error('Subscription failed:', error);
    }
}
```

```jsx
// React component
function StrategyCard({ strategy }) {
    const [isSubscribed, setIsSubscribed] = useState(false);

    const handleSubscribe = async () => {
        await agentRouter.authorize(strategy.id);
        setIsSubscribed(true);
    };

    return (
        <div className="strategy-card">
            <h3>Agent #{strategy.id}</h3>
            <p>{strategy.name}</p>
            <button onClick={handleSubscribe}>
                {isSubscribed ? '✓ Subscribed' : 'Subscribe'}
            </button>
        </div>
    );
}
```

**Clean, simple, no confusion!**

---

## Policy Enforcement

### The Key Insight

**Authorization is separate from policy:**

```
Authorization:
└─ "Which strategy can trade for me?"
    └─ authorize(500) → "Agent #500 can trade for me"

Policy:
└─ "What limits apply to my trades?"
    └─ Stored on userAgentId (e.g., Agent #101)
    └─ Enforced during execution
```

### Example

```solidity
// Bob authorizes Agent #500
authorize(500);  // Simple!

// Later, Alice's executor trades
executeLimitOrder(
    userAgentId: 101,      // Bob's agent → determines policy
    strategyAgentId: 500,  // Alice's agent → determines executor
    quantity: 2000
);

// Contract checks:
// 1. Is Agent #500 authorized by Bob? YES ✓
// 2. What's Bob's policy? (from Agent #101)
// 3. Max order size? 1000 IDRX
// 4. Is 2000 > 1000? YES → REJECT ❌

// Result: Trade rejected, Bob protected!
```

---

## State Diagram

```
┌─────────────────────────────────────────────────┐
│              AUTHORIZATION STATE                │
└─────────────────────────────────────────────────┘

Initial State:
├─ authorizedStrategyAgents[BOB][500] = false
└─ Bob cannot use Agent #500

Bob calls: authorize(500)
├─ authorizedStrategyAgents[BOB][500] = true
└─ Bob can now use Agent #500

During execution:
├─ Contract checks: authorizedStrategyAgents[BOB][500]
├─ Returns: true ✓
├─ Contract gets policy from Bob's Agent #101
├─ Enforces Bob's limits
└─ Trade executes

Bob calls: revoke(500)
├─ authorizedStrategyAgents[BOB][500] = false
└─ Bob can no longer use Agent #500
```

---

## Comparison with Original

### Before (Too Complex)

```solidity
// User needs to know their agent ID
function authorizeStrategyAgent(uint256 userAgentId, uint256 strategyAgentId)

// Frontend
await agentRouter.authorizeStrategyAgent(myAgentId, strategyId);
// User asks: "Wait, which agent ID is mine?"
```

### After (Simple!)

```solidity
// Just the strategy ID!
function authorize(uint256 strategyAgentId)

// Frontend
await agentRouter.authorize(strategyId);
// User thinks: "I want Agent #500" - done!
```

---

## Database Schema

```sql
-- Track authorizations (off-chain mirror)
CREATE TABLE strategy_authorizations (
    user_address VARCHAR(42) NOT NULL,
    strategy_agent_id BIGINT NOT NULL,
    authorized_at TIMESTAMP DEFAULT NOW(),
    revoked_at TIMESTAMP,
    PRIMARY KEY (user_address, strategy_agent_id)
);

-- Track subscriptions (with payment)
CREATE TABLE subscriptions (
    id SERIAL PRIMARY KEY,
    user_address VARCHAR(42) NOT NULL,
    user_agent_id BIGINT NOT NULL,        -- Bob's Agent #101 (has policy)
    strategy_agent_id BIGINT NOT NULL,    -- Alice's Agent #500
    paid_until TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),

    -- User must have authorized this strategy
    CONSTRAINT authorized_check
        FOREIGN KEY (user_address, strategy_agent_id)
        REFERENCES strategy_authorizations(user_address, strategy_agent_id)
);
```

---

## Security Notes

### 1. User Control

```solidity
// Only msg.sender can authorize for themselves
function authorize(uint256 strategyAgentId) external {
    authorizedStrategyAgents[msg.sender][strategyAgentId] = true;
}
// No one can authorize on behalf of others ✓
```

### 2. Policy Enforcement

```solidity
// Policy comes from userAgentId during execution
function executeLimitOrder(uint256 userAgentId, ...) {
    address user = identityRegistry.ownerOf(userAgentId);
    Policy memory policy = policyFactory.getPolicy(user, userAgentId);

    // User's policy ALWAYS enforced
    require(quantity <= policy.maxOrderSize);
}
// Strategy can't bypass user's limits ✓
```

### 3. Revocation

```solidity
// User can revoke anytime
agentRouter.revoke(500);
// Immediate effect on next trade ✓
```

---

## Summary

**The Simplified API:**

```solidity
// Authorization (user side)
authorize(strategyAgentId)    // One parameter!
revoke(strategyAgentId)       // One parameter!

// Execution (executor side)
executeLimitOrder(
    userAgentId,      // Determines policy
    strategyAgentId,  // Determines executor
    ...
)
```

**Key Benefits:**
1. ✅ **Simple:** One parameter for authorization
2. ✅ **Clear:** Intent is obvious
3. ✅ **Safe:** Policy still enforced
4. ✅ **Flexible:** Can authorize multiple strategies
5. ✅ **Clean:** Beautiful frontend code

**This is the right design.** 🎯

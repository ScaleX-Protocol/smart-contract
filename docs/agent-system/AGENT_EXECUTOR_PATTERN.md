# Agent Executor Pattern

## 🎯 **Architecture: Executors Trade on Behalf of Primary Wallet**

This is the **recommended pattern** for AI agent trading:

```
┌────────────────────────────────────────────────────────────┐
│                   Primary Wallet                            │
│           (Human Owner / Fund Manager)                      │
│                                                             │
│  Owns:                                                      │
│  ├─ Agent NFT (ERC-8004 identity)                          │
│  ├─ Trading Policy                                          │
│  └─ 10,000 IDRX in BalanceManager                         │
│                                                             │
│  Controls: Authorizes/revokes executors                    │
└─────────────┬───────────────────────────────────────────────┘
              │
              │ Authorizes
              ↓
┌──────────────────────────────────────────────────────────────┐
│                  Agent Executors                             │
│            (AI Trading Algorithms)                           │
├──────────────────────────────────────────────────────────────┤
│  Executor 1: Conservative Strategy                           │
│  ├─ Has: Own private key (pays gas)                         │
│  ├─ Can: Trade using Primary's 10k IDRX                     │
│  └─ Policy: 10% max drawdown, 5k daily volume               │
│                                                              │
│  Executor 2: Aggressive Strategy                            │
│  ├─ Has: Own private key (pays gas)                         │
│  ├─ Can: Trade using Primary's 10k IDRX                     │
│  └─ Policy: 25% max drawdown, 50k daily volume              │
│                                                              │
│  Executor 3: Market Making                                  │
│  ├─ Has: Own private key (pays gas)                         │
│  ├─ Can: Trade using Primary's 10k IDRX                     │
│  └─ Policy: 5% max drawdown, 2k daily volume                │
└──────────────────────────────────────────────────────────────┘

Fund Flow:
  - ALL executors share Primary's 10,000 IDRX
  - Executors pay their own gas
  - Profits/losses accrue to Primary wallet
```

---

## ✅ **Why This Pattern?**

### Advantages:

1. **✅ Centralized Fund Management**
   - Primary wallet controls all capital
   - Easy to reallocate between strategies
   - Simple accounting (one balance)

2. **✅ Flexible Strategy Deployment**
   - Deploy/remove agents without moving funds
   - Test new strategies with live capital
   - A/B test multiple strategies

3. **✅ Gas Efficiency**
   - Executors pay their own gas from separate wallets
   - Primary wallet not drained by gas costs
   - Can have dedicated gas wallets

4. **✅ Security**
   - Primary wallet can revoke executor access instantly
   - Executors can't withdraw funds (only trade)
   - Clear audit trail (all trades linked to agent ID)

5. **✅ Professional Setup**
   - Matches institutional trading architecture
   - Clear separation: ownership vs execution
   - Easy compliance and reporting

---

## 🚀 **Quick Start**

### Step 1: Setup `.env`

```bash
# Primary wallet (owns funds and agent)
PRIMARY_WALLET_KEY=0x1111...  # Needs: 10k IDRX + gas

# Agent executors (trade on behalf of primary)
AGENT_EXECUTOR_1_KEY=0x2222...  # Needs: only gas
AGENT_EXECUTOR_2_KEY=0x3333...  # Needs: only gas
AGENT_EXECUTOR_3_KEY=0x4444...  # Needs: only gas

# Network config
SCALEX_CORE_RPC=https://base-sepolia.infura.io/v3/YOUR_KEY
QUOTE_SYMBOL=IDRX
```

### Step 2: Generate Keys

```bash
# Generate primary wallet key
cast wallet new
# Save as PRIMARY_WALLET_KEY

# Generate executor keys
cast wallet new  # Save as AGENT_EXECUTOR_1_KEY
cast wallet new  # Save as AGENT_EXECUTOR_2_KEY
cast wallet new  # Save as AGENT_EXECUTOR_3_KEY
```

### Step 3: Fund Wallets

```bash
# Get addresses
PRIMARY=$(cast wallet address --private-key $PRIMARY_WALLET_KEY)
EXEC1=$(cast wallet address --private-key $AGENT_EXECUTOR_1_KEY)
EXEC2=$(cast wallet address --private-key $AGENT_EXECUTOR_2_KEY)
EXEC3=$(cast wallet address --private-key $AGENT_EXECUTOR_3_KEY)

# Fund primary wallet
# Transfer: 10,000 IDRX + 0.1 ETH for gas

# Fund executors (small amounts for gas only)
# Transfer: 0.01 ETH to each executor
```

### Step 4: Setup

```bash
./shellscripts/setup-agent-executors.sh
```

This will:
1. ✅ Mint agent identity for primary wallet
2. ✅ Create trading policy
3. ✅ Deposit 10,000 IDRX to BalanceManager
4. ✅ Authorize all 3 executors

### Step 5: Trade!

```bash
# Trade with Executor 1 (Conservative)
export EXECUTOR_PRIVATE_KEY=$AGENT_EXECUTOR_1_KEY
export PRIMARY_WALLET_ADDRESS=$PRIMARY
./shellscripts/agent-executor-trade.sh

# Trade with Executor 2 (Aggressive)
export EXECUTOR_PRIVATE_KEY=$AGENT_EXECUTOR_2_KEY
./shellscripts/agent-executor-trade.sh

# Trade with Executor 3 (Market Maker)
export EXECUTOR_PRIVATE_KEY=$AGENT_EXECUTOR_3_KEY
./shellscripts/agent-executor-trade.sh
```

---

## 🔄 **Transaction Flow**

### When Executor Places Order:

```solidity
// 1. Executor signs transaction
vm.startBroadcast(executorPrivateKey);  // Executor pays gas

// 2. Call AgentRouter.executeMarketOrder
AgentRouter(agentRouter).executeMarketOrder(
    agentId,      // Primary wallet's agent ID
    pool,
    side,
    quantity,
    minOutAmount,
    autoRepay,
    autoBorrow
);

// 3. AgentRouter checks:
//    - Is executor authorized for this agentId? ✓
//    - Does PRIMARY wallet own agentId? ✓
//    - Does policy allow this trade? ✓
//    - Does PRIMARY wallet have enough balance? ✓

// 4. Execute trade:
//    - Deduct funds from PRIMARY wallet's BalanceManager account
//    - Execute order on OrderBook
//    - Credit proceeds to PRIMARY wallet's account

// 5. Emit event:
event AgentSwapExecuted(
    address indexed owner,        // Primary wallet
    uint256 indexed agentTokenId, // Agent ID
    address indexed executor,     // Executor who signed
    ...
);

vm.stopBroadcast();
```

---

## 📊 **Fund Flow Example**

### Initial State:

```
Primary Wallet Balance: 10,000 IDRX
Executor 1 Balance: 0 IDRX (not needed)
Executor 2 Balance: 0 IDRX (not needed)
Executor 3 Balance: 0 IDRX (not needed)
```

### Executor 1 Buys 0.1 WETH:

```
Transaction:
  - Signed by: Executor 1 (pays ~$0.10 gas)
  - Funds used: Primary wallet's 10,000 IDRX
  - Cost: ~300 IDRX (at $3000/WETH)

After:
  - Primary: 9,700 IDRX + 0.1 WETH
  - Executor 1: 0 IDRX (unchanged)
```

### Executor 2 Sells 0.05 WETH:

```
Transaction:
  - Signed by: Executor 2 (pays ~$0.10 gas)
  - Funds used: Primary wallet's 0.1 WETH
  - Proceeds: ~150 IDRX

After:
  - Primary: 9,850 IDRX + 0.05 WETH
  - Executor 2: 0 IDRX (unchanged)
```

### Net Result:

```
Primary Wallet:
  - Started: 10,000 IDRX
  - Ended: 9,850 IDRX + 0.05 WETH
  - P&L: -150 IDRX + 0.05 WETH

Gas Paid:
  - Executor 1: ~$0.10
  - Executor 2: ~$0.10
  - Primary: $0 (didn't sign any transactions)
```

---

## 🔐 **Authorization & Security**

### Authorize Executor:

```solidity
// Primary wallet authorizes executor
agentRouter.authorizeExecutor(
    agentId,           // Agent token ID
    executorAddress,   // Executor to authorize
    true               // true = authorize, false = revoke
);
```

### Revoke Executor:

```solidity
// Primary wallet revokes executor immediately
agentRouter.authorizeExecutor(
    agentId,
    executorAddress,
    false  // Revoke
);
// Executor can no longer trade
```

### Check Authorization:

```bash
AGENT_ROUTER=$(cat deployments/84532.json | jq -r '.AgentRouter')
AGENT_ID=1
EXECUTOR=0x...

cast call $AGENT_ROUTER \
  "authorizedExecutors(uint256,address)" \
  $AGENT_ID $EXECUTOR \
  --rpc-url $SCALEX_CORE_RPC

# Returns: 0x01 (authorized) or 0x00 (not authorized)
```

---

## 📈 **Use Cases**

### 1. **Multi-Strategy Fund**

```
Primary Wallet: $100k USDC
├─ Executor 1: Mean Reversion Strategy (25% allocation)
├─ Executor 2: Trend Following Strategy (50% allocation)
├─ Executor 3: Market Making Strategy (25% allocation)
└─ All share the same $100k pool
```

### 2. **AI Agent Portfolio**

```
Primary Wallet: $50k IDRX
├─ AI Agent 1: GPT-4 based trading (conservative)
├─ AI Agent 2: Custom ML model (aggressive)
└─ AI Agent 3: Statistical arbitrage
```

### 3. **Development & Testing**

```
Primary Wallet: $1k USDC (test funds)
├─ Executor 1: Production strategy (live)
├─ Executor 2: Beta strategy (testing)
└─ Executor 3: Development strategy (experimental)
```

### 4. **Delegated Trading**

```
Primary Wallet: Your funds
├─ Trusted Trader 1: Authorized executor
├─ Trusted Trader 2: Authorized executor
└─ You retain ownership, they execute trades
```

---

## 🎛️ **Management Commands**

### View All Executors:

```bash
# List all executor addresses (need to track separately)
echo "Executor 1: $(cast wallet address --private-key $AGENT_EXECUTOR_1_KEY)"
echo "Executor 2: $(cast wallet address --private-key $AGENT_EXECUTOR_2_KEY)"
echo "Executor 3: $(cast wallet address --private-key $AGENT_EXECUTOR_3_KEY)"
```

### Check Primary Balance:

```bash
PRIMARY=$(cast wallet address --private-key $PRIMARY_WALLET_KEY)
BALANCE_MANAGER=$(cat deployments/84532.json | jq -r '.BalanceManager')
IDRX=$(cat deployments/84532.json | jq -r '.IDRX')

cast call $BALANCE_MANAGER \
  "getBalance(address,address)" \
  $PRIMARY $IDRX \
  --rpc-url $SCALEX_CORE_RPC
```

### Revoke Executor:

```bash
# Run from primary wallet
AGENT_ID=1
EXECUTOR_TO_REVOKE=0x...

cast send $AGENT_ROUTER \
  "authorizeExecutor(uint256,address,bool)" \
  $AGENT_ID $EXECUTOR_TO_REVOKE false \
  --rpc-url $SCALEX_CORE_RPC \
  --private-key $PRIMARY_WALLET_KEY
```

---

## ⚡ **Comparison: Executor Pattern vs Separate Wallets**

| Feature | Executor Pattern ⭐ | Separate Wallets |
|---------|-------------------|------------------|
| **Fund Management** | Centralized (easy) | Distributed (complex) |
| **Capital Reallocation** | Instant | Requires transfers |
| **Accounting** | Simple (one balance) | Complex (multiple balances) |
| **Strategy Testing** | Easy (just authorize) | Hard (need to fund) |
| **Gas Costs** | Executors pay own gas | Each wallet pays gas |
| **Security** | Revoke access instantly | Must drain wallet |
| **Setup Complexity** | Medium | Low |
| **Best For** | Multi-strategy, professional | Simple, isolated agents |

---

## 🚨 **Important Notes**

### ✅ **Shared Balance**

All executors share the PRIMARY wallet's balance:
- If Executor 1 uses 5k, Executor 2 has 5k left
- No per-executor limits (unless in policy)
- Monitor total usage across all executors

### ⚠️ **Gas Management**

Executors need ETH for gas:
- Each executor pays gas from own wallet
- Monitor executor gas balances
- Refill when low (doesn't need much)

### 🔐 **Authorization Control**

Primary wallet has full control:
- Can authorize new executors anytime
- Can revoke executors instantly
- Executors can ONLY trade (no withdraw)

### 📊 **Tracking**

Monitor via events:
```solidity
event AgentSwapExecuted(
    address indexed owner,     // Primary wallet
    uint256 indexed agentTokenId,
    address indexed executor,  // Which executor traded
    ...
);
```

---

## 🎯 **Summary**

**Executor Pattern = Professional Trading Architecture**

```
✅ Primary wallet owns and controls funds
✅ Agent executors trade on behalf of primary
✅ Executors pay their own gas
✅ Instant authorization/revocation
✅ Clean separation: ownership vs execution
✅ Easy to deploy multiple strategies
✅ Professional fund management
```

**Ready to set up your agent executors?**

```bash
# 1. Configure .env with keys
nano .env

# 2. Fund primary wallet (10k IDRX + gas)
# Transfer tokens to primary wallet

# 3. Fund executors (small ETH for gas)
# Transfer 0.01 ETH to each executor

# 4. Run setup
./shellscripts/setup-agent-executors.sh

# 5. Start trading!
export EXECUTOR_PRIVATE_KEY=$AGENT_EXECUTOR_1_KEY
export PRIMARY_WALLET_ADDRESS=$(cast wallet address --private-key $PRIMARY_WALLET_KEY)
./shellscripts/agent-executor-trade.sh
```

---

*This is the recommended pattern for AI agent trading on the platform!*

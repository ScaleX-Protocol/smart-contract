# Agent Account Architecture - Fixing Fund Isolation

## 🚨 **Problem Statement**

**Current Design Flaw**: All agents owned by one wallet share the same BalanceManager funds.

### Critical Issues:
1. ❌ No per-agent capital limits
2. ❌ No per-agent P&L tracking
3. ❌ No risk isolation between agents
4. ❌ One agent's failure affects all others
5. ❌ Impossible to properly manage multi-agent portfolios

---

## ✅ **Solution: Per-Agent Virtual Accounts**

Modify BalanceManager to track balances as `(owner, agentId, token)` instead of just `(owner, token)`.

---

## 📋 **Implementation Plan**

### **Option 1: Virtual Sub-Accounts (RECOMMENDED)** ⭐

Add agent-aware balance tracking to BalanceManager while maintaining backward compatibility.

#### Storage Changes

```solidity
// src/core/storages/BalanceManagerStorage.sol

struct Storage {
    // ===== EXISTING (Keep for backward compatibility) =====
    mapping(address => mapping(uint256 => uint256)) balanceOf;
    mapping(address => mapping(address => mapping(uint256 => uint256))) lockedBalanceOf;

    // ===== NEW: Agent-specific balances =====
    // Per-agent balances: owner => agentId => currencyId => balance
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) agentBalanceOf;

    // Per-agent locked balances: owner => agentId => operator => currencyId => balance
    mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => uint256)))) agentLockedBalanceOf;

    // Agent-mode flag: if true, enforces agent-specific accounting
    mapping(address => bool) useAgentAccounting;

    // Agent registry address (for validation)
    address agentRegistry;

    // ... rest of existing storage
}
```

#### New Functions

```solidity
// src/core/BalanceManager.sol

/**
 * @notice Enable agent-specific accounting for this owner
 * @dev Once enabled, all balances tracked per-agent
 */
function enableAgentAccounting() external {
    Storage storage $ = getStorage();
    $.useAgentAccounting[msg.sender] = true;
    emit AgentAccountingEnabled(msg.sender);
}

/**
 * @notice Deposit funds to specific agent's account
 * @param agentId Agent token ID
 * @param currency Token to deposit
 * @param amount Amount to deposit
 */
function depositToAgent(uint256 agentId, Currency currency, uint256 amount) external nonReentrant {
    Storage storage $ = getStorage();

    // Verify msg.sender owns this agent
    require(_ownsAgent(msg.sender, agentId), "Not agent owner");

    uint256 currencyId = _resolveCurrencyId(currency);

    // Transfer tokens from user
    currency.transfer(msg.sender, address(this), amount);

    // Credit agent's account
    $.agentBalanceOf[msg.sender][agentId][currencyId] += amount;

    emit AgentDeposit(msg.sender, agentId, currency, amount);
}

/**
 * @notice Get agent's balance
 */
function getAgentBalance(address owner, uint256 agentId, Currency currency)
    external
    view
    returns (uint256)
{
    Storage storage $ = getStorage();
    uint256 currencyId = _resolveCurrencyId(currency);
    return $.agentBalanceOf[owner][agentId][currencyId];
}

/**
 * @notice Transfer funds between agents (same owner)
 */
function transferBetweenAgents(
    uint256 fromAgentId,
    uint256 toAgentId,
    Currency currency,
    uint256 amount
) external nonReentrant {
    Storage storage $ = getStorage();

    require(_ownsAgent(msg.sender, fromAgentId), "Not owner of from agent");
    require(_ownsAgent(msg.sender, toAgentId), "Not owner of to agent");

    uint256 currencyId = _resolveCurrencyId(currency);

    require($.agentBalanceOf[msg.sender][fromAgentId][currencyId] >= amount, "Insufficient balance");

    $.agentBalanceOf[msg.sender][fromAgentId][currencyId] -= amount;
    $.agentBalanceOf[msg.sender][toAgentId][currencyId] += amount;

    emit AgentTransfer(msg.sender, fromAgentId, toAgentId, currency, amount);
}

/**
 * @notice Internal: Check if address owns agent
 */
function _ownsAgent(address owner, uint256 agentId) internal view returns (bool) {
    Storage storage $ = getStorage();
    if ($.agentRegistry == address(0)) return true; // No registry = allow

    try IERC721($.agentRegistry).ownerOf(agentId) returns (address tokenOwner) {
        return tokenOwner == owner;
    } catch {
        return false;
    }
}
```

#### Modified AgentRouter

```solidity
// src/ai-agents/AgentRouter.sol

function executeMarketOrder(
    uint256 agentTokenId,
    IPoolManager.Pool calldata pool,
    IOrderBook.Side side,
    uint128 quantity,
    uint128 minOutAmount,
    bool autoRepay,
    bool autoBorrow
) external returns (uint48 orderId, uint128 filled) {
    address owner = identityRegistry.ownerOf(agentTokenId);

    // Verify executor is authorized
    require(msg.sender == owner || authorizedExecutors[agentTokenId][msg.sender], "Unauthorized");

    // Check policy
    PolicyFactory.Policy memory policy = policyFactory.getPolicy(owner, agentTokenId);
    _validatePolicy(policy, pool, side, quantity, owner, agentTokenId);

    // Check agent's balance (NOT owner's balance)
    Currency requiredCurrency = side == IOrderBook.Side.BUY ? pool.quoteCurrency : pool.baseCurrency;
    uint256 agentBalance = balanceManager.getAgentBalance(owner, agentTokenId, requiredCurrency);

    uint256 requiredAmount = _calculateRequiredAmount(side, quantity, pool);
    require(agentBalance >= requiredAmount, "Insufficient agent balance");

    // Execute order using agent's funds
    (orderId, filled) = _executeOrder(
        agentTokenId,  // Pass agent ID to BalanceManager
        pool,
        side,
        quantity,
        minOutAmount,
        autoRepay,
        autoBorrow
    );

    emit AgentSwapExecuted(owner, agentTokenId, msg.sender, ...);
}
```

---

## 🏗️ **Architecture Diagram**

### Before (Current - BROKEN):
```
Owner: 0xAAA...
├─ BalanceManager Account:
│   ├─ IDRX: 10,000  ← SHARED BY ALL AGENTS!
│   ├─ WETH: 1.0     ← SHARED BY ALL AGENTS!
│   └─ WBTC: 0.1     ← SHARED BY ALL AGENTS!
│
├─ Agent #1 (agentId: 1) 🤖
│   └─ Uses owner's shared funds ❌
│
├─ Agent #2 (agentId: 2) 🤖
│   └─ Uses owner's shared funds ❌
│
└─ Agent #3 (agentId: 3) 🤖
    └─ Uses owner's shared funds ❌
```

### After (Proposed - FIXED):
```
Owner: 0xAAA...
│
├─ Agent #1 (agentId: 1) 🤖
│   ├─ IDRX: 1,000   ← ISOLATED FUNDS ✅
│   ├─ WETH: 0.1     ← ISOLATED FUNDS ✅
│   └─ WBTC: 0.01    ← ISOLATED FUNDS ✅
│
├─ Agent #2 (agentId: 2) 🤖
│   ├─ IDRX: 5,000   ← ISOLATED FUNDS ✅
│   ├─ WETH: 0.5     ← ISOLATED FUNDS ✅
│   └─ WBTC: 0.05    ← ISOLATED FUNDS ✅
│
└─ Agent #3 (agentId: 3) 🤖
    ├─ IDRX: 500     ← ISOLATED FUNDS ✅
    ├─ WETH: 0.05    ← ISOLATED FUNDS ✅
    └─ WBTC: 0.005   ← ISOLATED FUNDS ✅

Total Owner Funds: Sum of all agent accounts
Can track P&L per agent independently ✅
Can enforce capital limits per agent ✅
Agent failures isolated ✅
```

---

## 📊 **Usage Examples**

### Setup Agent Accounts

```solidity
// 1. Enable agent accounting
balanceManager.enableAgentAccounting();

// 2. Deposit to specific agents
balanceManager.depositToAgent(1, IDRX, 1000e6);  // Agent #1 gets 1000 IDRX
balanceManager.depositToAgent(2, IDRX, 5000e6);  // Agent #2 gets 5000 IDRX
balanceManager.depositToAgent(3, IDRX, 500e6);   // Agent #3 gets 500 IDRX

// 3. Check balances
uint256 agent1Balance = balanceManager.getAgentBalance(owner, 1, IDRX);
uint256 agent2Balance = balanceManager.getAgentBalance(owner, 2, IDRX);
```

### Trade with Isolated Funds

```solidity
// Agent #1 trades - uses only its 1000 IDRX
agentRouter.executeMarketOrder(
    1,     // agentId
    pool,
    IOrderBook.Side.BUY,
    0.1e18,  // Buy 0.1 WETH
    0,
    false,
    false
);
// ✅ Uses agent #1's funds only
// ✅ Other agents unaffected

// Agent #3 trades - uses only its 500 IDRX
agentRouter.executeMarketOrder(
    3,     // agentId
    pool,
    IOrderBook.Side.BUY,
    0.01e18,  // Buy 0.01 WETH
    0,
    false,
    false
);
// ✅ Uses agent #3's funds only
// ✅ Can't accidentally use agent #1 or #2's funds
```

### Transfer Between Agents

```solidity
// Reallocate capital: move 200 IDRX from Agent #1 to Agent #2
balanceManager.transferBetweenAgents(
    1,     // from agent
    2,     // to agent
    IDRX,
    200e6
);
```

### Track P&L Per Agent

```solidity
// Get agent's portfolio value
function getAgentPortfolioValue(uint256 agentId) external view returns (uint256) {
    uint256 totalValue = 0;

    // IDRX balance (1:1 USD)
    totalValue += balanceManager.getAgentBalance(owner, agentId, IDRX);

    // WETH balance (priced by oracle)
    uint256 wethBalance = balanceManager.getAgentBalance(owner, agentId, WETH);
    uint256 wethPrice = oracle.getSpotPrice(sxWETH);
    totalValue += (wethBalance * wethPrice) / 1e18;

    return totalValue;
}

// Track agent performance
uint256 agent1InitialCapital = 1000e6;
uint256 agent1CurrentValue = getAgentPortfolioValue(1);
int256 agent1PnL = int256(agent1CurrentValue) - int256(agent1InitialCapital);
uint256 agent1Return = (agent1PnL * 10000) / agent1InitialCapital; // BPS
```

---

## 🔄 **Migration Strategy**

### For Existing Deployments:

1. **Deploy New BalanceManager Implementation**
   ```bash
   # Deploy with agent accounting support
   forge create src/core/BalanceManager.sol:BalanceManager
   ```

2. **Upgrade via Beacon**
   ```bash
   cast send <BEACON> "upgradeTo(address)" <NEW_IMPL>
   ```

3. **Enable Agent Accounting**
   ```bash
   cast send <BALANCE_MANAGER> "enableAgentAccounting()"
   ```

4. **Migrate Funds to Agent Accounts**
   ```bash
   # Withdraw from shared account
   cast send <BALANCE_MANAGER> "withdraw(address,uint256)" <TOKEN> <AMOUNT>

   # Deposit to agent accounts
   cast send <BALANCE_MANAGER> "depositToAgent(uint256,address,uint256)" \
       <AGENT_ID> <TOKEN> <AMOUNT>
   ```

### For Fresh Deployments:

Enable agent accounting from the start:
```solidity
// In deployment script after BalanceManager deployed
balanceManager.enableAgentAccounting();
```

---

## 🔐 **Security Considerations**

### ✅ **Implemented Safeguards**

1. **Ownership Verification**: Only agent owner can deposit/withdraw
2. **Agent Validation**: Verifies agentId exists in IdentityRegistry
3. **Balance Checks**: Can't overdraw agent's account
4. **Isolated Risk**: One agent's failure doesn't affect others
5. **Backward Compatible**: Existing code still works

### ⚠️ **Additional Protections Needed**

1. **Reentrancy Guards**: Add to all new functions
2. **Pause Mechanism**: Emergency stop per agent
3. **Transfer Limits**: Optional limits on inter-agent transfers
4. **Audit**: Full security audit of new code

---

## 📈 **Benefits**

### For Developers:
- ✅ Proper multi-agent portfolio management
- ✅ Clean P&L tracking per agent
- ✅ Easier debugging and monitoring
- ✅ Better risk management

### For Users:
- ✅ Isolated agent strategies
- ✅ Can allocate specific capital per agent
- ✅ One agent's loss doesn't affect others
- ✅ Clear performance attribution

### For Protocol:
- ✅ More sophisticated agent strategies possible
- ✅ Better compliance (clear fund separation)
- ✅ Easier liquidation management
- ✅ Professional-grade multi-agent support

---

## 🚀 **Next Steps**

### Phase 1: Implementation (1 week)
- [ ] Modify BalanceManagerStorage with new mappings
- [ ] Implement new functions in BalanceManager
- [ ] Update AgentRouter to use agent-specific balances
- [ ] Add migration utilities

### Phase 2: Testing (1 week)
- [ ] Unit tests for new functions
- [ ] Integration tests with AgentRouter
- [ ] Migration tests
- [ ] Gas optimization

### Phase 3: Deployment (3 days)
- [ ] Deploy to testnet
- [ ] Test migration path
- [ ] Deploy to mainnet
- [ ] Update documentation

---

## 🔍 **Alternative Solutions**

### **Option 2: Separate Smart Contract Wallets**

Deploy a smart contract wallet for each agent (ERC-4337 style).

**Pros**:
- ✅ True wallet separation
- ✅ Can use existing wallet infrastructure
- ✅ More flexible execution logic

**Cons**:
- ❌ Higher gas costs (wallet deployment + execution)
- ❌ More complex
- ❌ Harder to manage multiple agents

### **Option 3: Multi-Owner Wallets**

Use one wallet per agent (separate private keys).

**Pros**:
- ✅ Complete isolation
- ✅ Simple to understand

**Cons**:
- ❌ Key management nightmare
- ❌ No shared liquidity benefits
- ❌ Expensive to fund multiple wallets

---

## 📊 **Comparison**

| Solution | Isolation | Complexity | Gas Cost | Migration |
|----------|-----------|------------|----------|-----------|
| **Virtual Sub-Accounts** ⭐ | ✅ Strong | 🟡 Medium | 🟢 Low | 🟢 Easy |
| Smart Contract Wallets | ✅ Complete | 🔴 High | 🔴 High | 🔴 Hard |
| Multi-Owner Wallets | ✅ Complete | 🟢 Low | 🟡 Medium | 🟢 Easy |

---

## 💡 **Recommendation**

**Implement Option 1: Virtual Sub-Accounts**

This provides the best balance of:
- Strong fund isolation
- Manageable complexity
- Low gas costs
- Easy migration path
- Maintains composability with existing contracts

---

## 📝 **Code Structure**

```
src/core/
├── BalanceManager.sol           (Modified - add agent functions)
├── storages/
│   └── BalanceManagerStorage.sol (Modified - add agent mappings)
│
src/ai-agents/
├── AgentRouter.sol              (Modified - use agent balances)
│
script/
├── agents/
│   ├── MigrateToAgentAccounts.s.sol (New - migration script)
│   └── TestAgentIsolation.s.sol     (New - test script)
│
test/
└── agents/
    └── AgentAccountIsolation.t.sol  (New - unit tests)
```

---

**Want me to implement this solution?** I can:
1. Create the modified BalanceManager with agent account support
2. Update AgentRouter to use agent-specific balances
3. Write migration scripts
4. Create comprehensive tests

This will properly fix the fund isolation issue! 🎯

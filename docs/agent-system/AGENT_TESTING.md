# Testing Agent Order Placement

## Quick Start

To test if your agent infrastructure is working end-to-end, run:

```bash
./shellscripts/test-agent-order.sh
```

This will:
1. ✅ Check if you have an agent (mint one if needed)
2. ✅ Create a trading policy (if one doesn't exist)
3. ✅ Deposit funds to BalanceManager
4. ✅ Place a test market order via AgentRouter

---

## What the Test Does

### Step 1: Agent Identity
```
Checks if your address owns an ERC-8004 agent token
├─ If YES: Uses existing agent
└─ If NO: Mints new agent identity NFT
```

### Step 2: Trading Policy
```
Checks if agent has a trading policy configured
├─ If YES: Uses existing policy
└─ If NO: Creates default policy with:
    ├─ Max Daily Volume: 100,000 USD
    ├─ Max Drawdown: 20%
    ├─ Min Health Factor: 1.3x
    ├─ Max Slippage: 5%
    └─ Min Cooldown: 60 seconds
```

### Step 3: Fund Deposit
```
Checks BalanceManager balance
├─ If sufficient: Skips deposit
└─ If insufficient: Deposits 1,000 USDC/IDRX
```

### Step 4: Order Execution
```
Places test market BUY order via AgentRouter
├─ Asset: WETH
├─ Quantity: 0.01 WETH
├─ Type: Market order (instant execution)
└─ Verifies full integration: Policy → Authorization → Execution
```

---

## Prerequisites

### 1. Tokens Required

You need quote currency tokens (USDC or IDRX) in your wallet:

```bash
# Check your balance
cast balance $YOUR_ADDRESS --erc20 <QUOTE_TOKEN_ADDRESS> --rpc-url $SCALEX_CORE_RPC

# If you need test tokens, use the faucet:
forge script script/faucet/MintTestTokens.s.sol --rpc-url $SCALEX_CORE_RPC --broadcast --private-key $PRIVATE_KEY
```

### 2. Environment Setup

Ensure `.env` contains:
```bash
PRIVATE_KEY=your_private_key_here
SCALEX_CORE_RPC=https://base-sepolia.infura.io/v3/YOUR_KEY
QUOTE_SYMBOL=USDC  # or IDRX
```

---

## Manual Testing Steps

If you prefer to test manually:

### 1. Mint an Agent Identity

```bash
cast send <IDENTITY_REGISTRY> "mint(address)" $YOUR_ADDRESS \
  --rpc-url $SCALEX_CORE_RPC \
  --private-key $PRIVATE_KEY

# Get your agent token ID
cast call <IDENTITY_REGISTRY> "tokenOfOwnerByIndex(address,uint256)" $YOUR_ADDRESS 0 \
  --rpc-url $SCALEX_CORE_RPC
```

### 2. Create a Policy

```solidity
// Example policy creation call
policyFactory.createPolicy(
    agentTokenId,
    assetLimits,      // Array of asset limits
    100000e6,         // maxDailyVolume: 100k USD
    2000,             // maxDrawdownBps: 20%
    300,              // minHealthFactor: 1.3x
    500,              // maxSlippageBps: 5%
    60                // minCooldownSeconds: 1 min
);
```

### 3. Deposit Funds

```bash
# Approve BalanceManager
cast send <QUOTE_TOKEN> "approve(address,uint256)" <BALANCE_MANAGER> $(cast max-uint) \
  --rpc-url $SCALEX_CORE_RPC \
  --private-key $PRIVATE_KEY

# Deposit funds
cast send <BALANCE_MANAGER> "deposit(address,uint256)" <QUOTE_TOKEN> 1000000000 \
  --rpc-url $SCALEX_CORE_RPC \
  --private-key $PRIVATE_KEY
```

### 4. Place an Order

```bash
# Use the AgentRouter to place a market order
cast send <AGENT_ROUTER> \
  "executeMarketOrder(uint256,(address,address),uint8,uint128,uint128,bool,bool)" \
  $AGENT_TOKEN_ID \
  "(<BASE_TOKEN>,<QUOTE_TOKEN>)" \
  0 \
  10000000000000000 \
  0 \
  false \
  false \
  --rpc-url $SCALEX_CORE_RPC \
  --private-key $PRIVATE_KEY
```

---

## Expected Output

### Successful Test

```
=== TESTING AGENT ORDER PLACEMENT ===

Loaded addresses:
  AgentRouter: 0x9113...
  PolicyFactory: 0x2917...
  ...

Step 1: Checking for existing agent...
[OK] Found existing agent token ID: 1

Step 2: Checking for existing policy...
[OK] Policy already exists
  Max Daily Volume: 100000000000
  Max Drawdown BPS: 2000

Step 3: Depositing funds to BalanceManager...
Current balance: 1000000000
[OK] Sufficient balance already exists

Step 4: Placing test order via AgentRouter...
Order details:
  Pool: 0x629A...
  Side: BUY
  Quantity: 10000000000000000
  Agent Token ID: 1
[OK] Order executed successfully!
  Order ID: 42
  Filled: 10000000000000000

[SUCCESS] Agent order test completed!
```

### Common Issues

#### Issue 1: Insufficient Balance
```
[WARN] Insufficient token balance. Need to mint or acquire tokens first.
       Required: 1000000000
       Available: 0
```

**Solution**: Mint test tokens or transfer tokens to your address

#### Issue 2: Policy Violation
```
[FAIL] Order failed: Daily volume limit exceeded
```

**Solution**: Wait for the next day or increase policy limits

#### Issue 3: Authorization Failed
```
[FAIL] Order failed: Unauthorized executor
```

**Solution**: Authorize your address as an executor for the agent

---

## Troubleshooting

### Check Agent Ownership

```bash
# Get agent owner
cast call <IDENTITY_REGISTRY> "ownerOf(uint256)" $AGENT_TOKEN_ID \
  --rpc-url $SCALEX_CORE_RPC
```

### Check Policy

```bash
# Get agent policy
cast call <POLICY_FACTORY> "getPolicy(address,uint256)" $YOUR_ADDRESS $AGENT_TOKEN_ID \
  --rpc-url $SCALEX_CORE_RPC
```

### Check Balance

```bash
# Get BalanceManager balance
cast call <BALANCE_MANAGER> "getBalance(address,address)" $YOUR_ADDRESS <TOKEN> \
  --rpc-url $SCALEX_CORE_RPC
```

### Check Authorization

```bash
# Check if AgentRouter is authorized
cast call <ORDERBOOK> "isAuthorizedRouter(address)" <AGENT_ROUTER> \
  --rpc-url $SCALEX_CORE_RPC
```

---

## Advanced Testing

### Test Different Order Types

#### Limit Order
```solidity
agentRouter.executeLimitOrder(
    agentTokenId,
    pool,
    side,
    quantity,
    limitPrice,
    expiry,
    autoRepay
);
```

#### Auto-Borrow Order
```solidity
agentRouter.executeMarketOrder(
    agentTokenId,
    pool,
    IOrderBook.Side.BUY,
    quantity,
    minOutAmount,
    false,  // autoRepay
    true    // autoBorrow - borrows if needed
);
```

#### Auto-Repay Order
```solidity
agentRouter.executeMarketOrder(
    agentTokenId,
    pool,
    IOrderBook.Side.SELL,
    quantity,
    minOutAmount,
    true,   // autoRepay - repays loans from proceeds
    false
);
```

### Test Policy Enforcement

Try exceeding limits to verify policy works:

```bash
# Place very large order (should fail with volume limit exceeded)
# Place order with excessive slippage (should fail)
# Place order too quickly after previous (should fail with cooldown)
```

### Monitor Events

Watch for agent-specific events:

```bash
cast logs --from-block latest \
  --address <AGENT_ROUTER> \
  --event "AgentSwapExecuted(address,uint256,address,address,address,uint256,uint256,uint256)" \
  --rpc-url $SCALEX_CORE_RPC
```

---

## Integration Testing Checklist

- [ ] Agent identity can be minted
- [ ] Policy can be created with custom limits
- [ ] Funds can be deposited to BalanceManager
- [ ] Market orders execute successfully
- [ ] Limit orders can be placed
- [ ] Orders can be cancelled
- [ ] Policy limits are enforced
- [ ] Circuit breakers trigger on drawdown
- [ ] Events are emitted correctly
- [ ] Auto-borrow works when enabled
- [ ] Auto-repay works when enabled

---

## Next Steps

Once the test passes:

1. **Integrate with AI Agent**: Connect your AI trading logic to AgentRouter
2. **Deploy Production Policies**: Create policies with real risk limits
3. **Set Up Monitoring**: Watch events and track performance
4. **Scale Up**: Deploy multiple agents with different strategies

---

## Related Scripts

- `script/verification/VerifyAgentConfiguration.s.sol` - Verify infrastructure setup
- `script/agents/TestAgentOrder.s.sol` - Full order placement test
- `script/agents/CreateAgentPolicy.s.sol` - Create custom policies
- `shellscripts/test-agent-order.sh` - Quick test runner

---

*For more details, see: [AGENT_CONFIGURATION.md](AGENT_CONFIGURATION.md)*

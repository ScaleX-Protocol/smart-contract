# Marketplace Model Verification Script

## Purpose

Verifies that the current smart contracts support the marketplace/copy-trading model where:
1. User starts with NO agent
2. User registers their own agent and installs their own policy
3. User authorizes a developer's executor wallet
4. Executor can place orders for the user within the user's policy limits

## What This Proves

✅ No smart contract changes needed for marketplace model
✅ One executor can trade for multiple users
✅ Each user's policy is enforced correctly
✅ Users maintain custody of their funds
✅ Orders are tracked with correct agent IDs

## Prerequisites

### Environment Variables

Make sure your `.env` has:

```bash
# Network
SCALEX_CORE_RPC=https://base-sepolia.infura.io/v3/YOUR_KEY

# User wallet (will register agent and subscribe)
PRIVATE_KEY_2=0x...

# Executor wallet (will trade on behalf of user)
AGENT_EXECUTOR_1_KEY=0x...

# Deployer wallet (for minting test tokens)
PRIVATE_KEY=0x...
```

### Required Balances

- User wallet needs ~0.05 ETH for gas
- Executor wallet needs ~0.01 ETH for gas
- Deployer wallet needs ~0.01 ETH for gas (to mint IDRX)

## Running the Script

### Step 1: Dry Run (Simulation)

Test without broadcasting transactions:

```bash
forge script script/VerifyMarketplaceModel.s.sol:VerifyMarketplaceModel \
  --rpc-url $SCALEX_CORE_RPC \
  -vvvv
```

### Step 2: Execute on Testnet

Actually execute the transactions:

```bash
forge script script/VerifyMarketplaceModel.s.sol:VerifyMarketplaceModel \
  --rpc-url $SCALEX_CORE_RPC \
  --broadcast \
  -vvvv
```

## What The Script Does

### STEP 1: Verify User Has No Agent
- Confirms user doesn't own any agent NFT yet
- Shows user's address

### STEP 2: User Registers Agent & Installs Policy
- User calls `IdentityRegistry.register()` → Gets Agent NFT
- User calls `PolicyFactory.installAgentFromTemplate()` with:
  - Template: "conservative"
  - Max order size: 1,000 IDRX
  - Daily volume limit: 5,000 IDRX
- Verifies policy is installed correctly

### STEP 3: User Authorizes Executor
- User calls `AgentRouter.authorizeExecutor(agentId, executorAddress)`
- Verifies executor is authorized for user's agent

### STEP 4: Fund User
- Deployer mints 10,000 IDRX to user
- User approves BalanceManager
- User deposits 10,000 IDRX to BalanceManager

### STEP 5: Executor Places Order
- **Test A:** Executor tries to place 2,000 IDRX order
  - Expected: REJECTED (exceeds user's 1,000 IDRX limit)
  - Proves policy enforcement works

- **Test B:** Executor places 1,000 IDRX order
  - Expected: SUCCESS (within user's limit)
  - Proves executor can trade for user

## Expected Output

```
================================================
MARKETPLACE MODEL VERIFICATION
================================================

STEP 1: Verify User Has No Agent
------------------------------------------------
User address: 0x...
User does NOT own any agent NFT yet

STEP 2: User Registers Agent & Installs Policy
------------------------------------------------
2a. User registering agent...
  Agent ID: 101
  Owner: 0x...
2b. User installing CONSERVATIVE policy...
  Policy template: conservative
  Max order size: 1,000 IDRX
  Daily volume limit: 5,000 IDRX
  ✓ Policy installed and verified

STEP 3: User Authorizes Executor
------------------------------------------------
User authorizing executor wallet...
  Executor address: 0x...
  ✓ Executor authorized
  ✓ Authorization verified

STEP 4: Fund User
------------------------------------------------
Minting 10,000 IDRX to user...
User depositing to BalanceManager...
  User balance: 10000 IDRX
  ✓ User funded with 10,000 IDRX

STEP 5: Executor Places Order for User
------------------------------------------------
Test A: Placing 2000 IDRX order (exceeds user's 1000 limit)
  ✓ Order rejected (policy violation)

Test B: Placing 1000 IDRX order (within user's limit)
  ✓ Order placed successfully!
  Order ID: 7
  Agent ID: 101
  Executor: 0x...
  User (owner): 0x...
  Amount: 1000 IDRX (enforced by user's policy)

================================================
✓ VERIFICATION COMPLETE
================================================
```

## Success Criteria

✅ User registers their own agent
✅ User installs their own policy
✅ User authorizes executor
✅ Executor's excessive order is rejected by user's policy
✅ Executor's valid order succeeds
✅ Order uses user's funds
✅ Order tracked with user's agent ID

## Troubleshooting

### "Agent disabled" or "Agent expired"
- Policy might not be installed correctly
- Check `policyFactory.getPolicy(user, agentId)` returns `enabled: true`

### "Not authorized executor"
- Executor authorization might have failed
- Check `agentRouter.authorizedExecutors(agentId, executor)` returns `true`

### "Insufficient balance"
- User might not have deposited funds
- Check `balanceManager.getBalance(user, IDRX)` shows correct amount

### Transaction fails with no reason
- Check gas limits
- Verify all contracts are deployed correctly
- Check that pool exists and has liquidity

## Next Steps

After verification succeeds:
1. ✅ Proves marketplace model works with current contracts
2. ✅ No smart contract changes needed
3. → Build off-chain backend (subscriptions, payments)
4. → Build frontend marketplace
5. → Build developer trading service template

## Related Documentation

- Implementation Plan: `/docs/marketplace/IMPLEMENTATION_PLAN.md`
- Agent Flows: `/docs/agent-system/AGENT_FLOWS_AND_FUNCTIONS.md`
- Smart Contract Reference: `/docs/agent-system/`

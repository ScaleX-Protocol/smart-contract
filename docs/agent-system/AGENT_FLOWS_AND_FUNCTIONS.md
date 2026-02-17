# Agent Flows and Smart Contract Functions

Complete guide to AI agent workflows and the smart contract functions used at each step.

---

## 🔗 Smart Contract Addresses (Base Sepolia - Chain 84532)

### Core Agent System Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| **IdentityRegistry** (Proxy) | `0x97EE6eaa3e9B0D33813102554f7B9CC4D521e89D` | ERC-8004 Identity Registry - Agent NFTs |
| IdentityRegistry Implementation | `0xD15C0379a5574604Ec57e34Cc5221B2AC85CAa27` | Implementation contract |
| **PolicyFactory** | `0x4605f626dF4A684139186B7fF15C8cABD8178EC8` | Policy management and installation |
| **AgentRouter** | `0x36f229515bf0e4c74165b214c56bE8c0b49a1574` | Agent execution layer - Main entry point |
| **ReputationRegistry** (Proxy) | `0x10F9A586B3F9e8386801dF49964cAa7Cd98F9287` | ERC-8004 Reputation tracking |
| ReputationRegistry Implementation | `0xf432acBe98A3560617581305C602266338d60c09` | Implementation contract |
| **ValidationRegistry** (Proxy) | `0x63135F3c5958a601fA83D0B347E8A17831b19A21` | ERC-8004 Validation logic |
| ValidationRegistry Implementation | `0xaF0a275e17F059CC26e238D6DA3FcC8254dbdd26` | Implementation contract |

### Core Platform Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| **PoolManager** | `0x630D8C79407CB90e0AFE68E3841eadd3F94Fc81F` | Pool management and creation |
| **BalanceManager** | `0xeeAd362bCdB544636ec3ae62A114d846981cEbaf` | User balance tracking |
| **LendingManager** | `0x448d522C17A84aBFa00DED4b4dFd76c43251013D` | Lending protocol integration |
| **ScaleXRouter** | `0xc882b5af2B1AFB37CDe4D1f696fb112979cf98EE` | Standard user router (not for agents) |
| **AutoBorrowHelper** | `0xd22C3b2ceF6BcD601f371052208C7a283FCFaA4E` | Phase 4 auto-borrow functionality |
| **Oracle** | `0xbF1ec59A11dFd00C29a258216E890FA89253325b` | Price oracle |
| **TokenRegistry** | `0x7917D5E85136a41937A8eca8816991b87893139A` | Token registration |

### Example OrderBook Addresses

| Pool | OrderBook Address | Base/Quote |
|------|------------------|------------|
| **WETH/IDRX** | `0x629A14ee7dC9D29A5EB676FBcEF94E989Bc0DEA1` | Most tested pool |
| WBTC/IDRX | `0xF436bE2abbf4471d7E68a6f8d93B4195b1c6FbE3` | Bitcoin pool |
| GOLD/IDRX | `0x5EF80d453CED464E135B4b25e9eD423b033ad87F` | Tokenized gold |
| NVIDIA/IDRX | `0x0026812e5DFaA969f1827748003A3b5A3CcBA084` | Synthetic equity |

### Token Addresses

| Token | Address | Type |
|-------|---------|------|
| **IDRX** | `0xe7Cc2615374bbA52FC7bC8aF4aeF0E74f3D2559d` | Quote currency (stablecoin) |
| **WETH** | `0x80C143FE62b45B83b7113c366BE21331Ba080FA8` | Wrapped Ethereum |
| **WBTC** | `0x9E63dA9c18d7427dE5D7954A3c1499c21E77A425` | Wrapped Bitcoin |
| **sxIDRX** | `0x7770cA54914d53A4AC8ef4618A36139141B7546A` | Synthetic IDRX (lending) |
| **sxWETH** | `0x498509897F5359dd8C74aecd7Ed3a44523df9B9e` | Synthetic WETH (lending) |

### Deployment Information

- **Network:** Base Sepolia (Chain ID: 84532)
- **Deployer:** `0x27dD1eBE7D826197FD163C134E79502402Fd7cB7`
- **Deployment Block:** 37,555,440
- **Deployment Date:** January 2026
- **Agent System Version:** ERC-8004 Phase 4 + Lending Integration

---

## 🧪 Test Wallet Setup (Base Sepolia Examples)

⚠️ **TESTNET ONLY** - These are example wallets used for testing on Base Sepolia. Never use these addresses/keys on mainnet.

### Deployer Wallet (Token Minter - Has Initial Assets)

| Property | Value |
|----------|-------|
| **Address** | `0x27dD1eBE7D826197FD163C134E79502402Fd7cB7` |
| **Private Key** | Stored in `.env` as `PRIVATE_KEY` |
| **Role** | Contract deployer, token minter, system admin |
| **Permissions** | Can mint IDRX, WETH, WBTC, GOLD, etc. |
| **Purpose** | Deploys contracts, mints tokens, funds other wallets |
| **Also used as** | `OWNER_ADDRESS`, `FOUNDRY_SENDER`, `FEE_RECEIVER_ADDRESS` |

**This is the address that initially has all assets** - it has minting permission for all tokens.

### Primary Agent Owner Wallet

| Property | Value |
|----------|-------|
| **Address** | `0x85C67299165117acAd97C2c5ECD4E642dFbF727E` |
| **Private Key** | Stored in `.env` as `PRIMARY_WALLET_KEY` |
| **Purpose** | Owns Agent NFT, controls funds, authorizes executors |
| **Funding** | 0.1 ETH + 10,000 IDRX |
| **Agent Token ID** | `100` (registered and active) |

### Executor Wallets

| Executor | Address | Private Key (.env) | Purpose | Funding |
|----------|---------|-------------------|---------|---------|
| **Executor 1** | `0xfc98C3eD81138d8A5f35b30A3b735cB5362e14Dc` | `AGENT_EXECUTOR_1_KEY` | Conservative trading | 0.01 ETH |
| **Executor 2** | `0x6CDD4354114Eae313972C99457E4f85eb6dc5295` | `AGENT_EXECUTOR_2_KEY` | Aggressive trading | 0.01 ETH |
| **Executor 3** | `0xfA1Bb09a1318459061ECca7Cf23021843d5dB9c2` | `AGENT_EXECUTOR_3_KEY` | Market making | 0.01 ETH |

### Example .env Configuration

```bash
# Deployer wallet (contract deployer, token minter)
PRIVATE_KEY=0x... # Deployer private key - can mint tokens
OWNER_ADDRESS=0x27dD1eBE7D826197FD163C134E79502402Fd7cB7
FOUNDRY_SENDER=0x27dD1eBE7D826197FD163C134E79502402Fd7cB7
FEE_RECEIVER_ADDRESS=0x27dD1eBE7D826197FD163C134E79502402Fd7cB7

# Primary agent owner wallet (owns Agent NFT #100)
PRIMARY_WALLET_KEY=0x1234567890abcdef... # Your private key here
PRIMARY_WALLET_ADDRESS=0x85C67299165117acAd97C2c5ECD4E642dFbF727E

# Executor wallets (authorized to trade on behalf of agent)
AGENT_EXECUTOR_1_KEY=0xabcdef1234567890... # Your private key here
AGENT_EXECUTOR_2_KEY=0x9876543210fedcba... # Your private key here
AGENT_EXECUTOR_3_KEY=0xfedcba0123456789... # Your private key here
```

### Deriving Addresses from Private Keys

```bash
# Verify address matches private key
cast wallet address --private-key $PRIMARY_WALLET_KEY
# Output: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E

# Check balance
cast balance 0x85C67299165117acAd97C2c5ECD4E642dFbF727E --rpc-url $SCALEX_CORE_RPC
```

### Complete Wallet Hierarchy

```
Deployer (0x27dd...7cB7) - INITIAL ASSET HOLDER
├── Role: Contract deployer, token minter
├── Has: PRIVATE_KEY in .env
├── Can: Mint unlimited IDRX, WETH, WBTC, etc.
│
└── Mints & Transfers Tokens
    │
    ▼
Agent Owner (0x85C6...727E) - AGENT CONTROLLER
├── Role: Owns Agent NFT #100, controls funds
├── Has: PRIMARY_WALLET_KEY in .env
├── Received: 10,000 IDRX from deployer
├── Owns: Agent ERC-721 NFT (Token ID 100)
├── Deposited: 10,000 IDRX in BalanceManager
│
└── Authorizes Executors
    │
    ├── Executor 1: 0xfc98C3...e14Dc (Conservative)
    │   ├── Has: AGENT_EXECUTOR_1_KEY
    │   ├── Funding: 0.01 ETH (gas only)
    │   ├── Authorized via: authorizeExecutor(100, 0xfc98C3...e14Dc)
    │   ├── Can: Execute trades within policy limits
    │   └── Uses: Owner's 10,000 IDRX (not own funds)
    │
    ├── Executor 2: 0x6CDD43...5295 (Aggressive)
    │   ├── Has: AGENT_EXECUTOR_2_KEY
    │   └── Purpose: Higher-risk trading strategies
    │
    └── Executor 3: 0xfA1Bb0...9c2 (Market Maker)
        ├── Has: AGENT_EXECUTOR_3_KEY
        └── Purpose: Market making operations
```

### Complete Setup Flow (Who Does What)

```
Step 1: Deployer mints tokens
─────────────────────────────
Deployer (0x27dd...7cB7)
└── Calls: IDRX.mint(0x85C6...727E, 10000000000) // 10,000 IDRX
    └── Result: Agent Owner receives 10,000 IDRX
    └── Role: Fund provider only

Step 2: Agent Owner registers agent
────────────────────────────────────
Agent Owner (0x85C6...727E)
└── Calls: IdentityRegistry.register()
    └── Result: Mints ERC-721 NFT to msg.sender
        └── Returns: agentTokenId = 100
        └── Owner: 0x85C6...727E

Step 3: Agent Owner installs policy ⭐
──────────────────────────────────────
Agent Owner (0x85C6...727E) - MUST own the NFT
└── Calls: PolicyFactory.installAgentFromTemplate(
        agentTokenId: 100,
        templateName: "conservative",
        customizations: {...}
    )
    └── Check: identityRegistry.ownerOf(100) == msg.sender? ✅
        └── Result: Policy installed, agent ready to trade

Step 4: Agent Owner deposits to BalanceManager
───────────────────────────────────────────────
Agent Owner (0x85C6...727E)
├── Approves: BalanceManager to spend IDRX
└── Deposits: 10,000 IDRX to BalanceManager
    └── Result: Funds available for trading

Step 5: Agent Owner authorizes executor
────────────────────────────────────────
Agent Owner (0x85C6...727E) - MUST own the NFT
└── Calls: AgentRouter.authorizeExecutor(100, 0xfc98...14Dc)
    └── Check: identityRegistry.ownerOf(100) == msg.sender? ✅
        └── Result: Executor can now trade for Agent #100

Step 6: Executor places order using owner's funds
──────────────────────────────────────────────────
Executor 1 (0xfc98...14Dc)
└── Calls: AgentRouter.placeLimitOrder(agentTokenId: 100, ...)
    └── AgentRouter checks: Is executor authorized? ✅
        └── OrderBook uses: Owner's 10,000 IDRX balance
            └── Result: Order placed with agent tracking
```

### Key Permission Summary

| Action | Required Permission | Who in Our Setup |
|--------|-------------------|------------------|
| Mint tokens | Token minter role | Deployer (`0x27dd...7cB7`) |
| Register agent | Anyone (becomes owner) | Agent Owner (`0x85C6...727E`) |
| **Install policy** | **Must own agent NFT** | **Agent Owner** (`0x85C6...727E`) ⭐ |
| Authorize executor | Must own agent NFT | Agent Owner (`0x85C6...727E`) |
| Execute trades | Owner or authorized executor | Executor (`0xfc98...14Dc`) |

**Important:** The Deployer cannot install policies or authorize executors unless they own the agent NFT. These actions require NFT ownership.

### Funding Test Wallets

```bash
# Get testnet ETH from faucet
# https://www.alchemy.com/faucets/base-sepolia

# Fund wallets using script
./shellscripts/fund-agent-wallets.sh

# Check balances
./shellscripts/check-agent-wallets.sh

# Expected output:
# Primary Wallet: 0x85C6...727E
#   ETH: 0.1
#   IDRX: 10000.00
#   Status: Has ETH ✅
#
# Executor 1: 0xfc98...14Dc
#   ETH: 0.01
#   Status: Has ETH ✅
```

### Real Transaction Examples

**Agent Registration:**
- Transaction: Agent #100 registered
- Block: 37,588,057
- Owner: `0x85C67299165117acAd97C2c5ECD4E642dFbF727E`

**Executor Authorization:**
- Transaction: Authorized executor for Agent #100
- Executor: `0xfc98C3eD81138d8A5f35b30A3b735cB5362e14Dc`
- Caller: Owner (0x85C6...727E)

**Agent Order Placement:**
- Transaction Hash: `0xc271d5811f5fef7fc498c3e177a8a17b3ed8455f08d3325d6507b677a88c6402`
- Block: 37,601,733
- Order ID: 6
- Agent Token ID: 100
- Executor: `0xfc98C3eD81138d8A5f35b30A3b735cB5362e14Dc`
- Owner: `0x85C67299165117acAd97C2c5ECD4E642dFbF727E`
- Status: Successfully placed and tracked

---

## 📋 Table of Contents

1. [Agent Lifecycle Flow](#agent-lifecycle-flow)
2. [Trading Flows](#trading-flows)
3. [Lending Flows](#lending-flows)
4. [Smart Contract Function Reference](#smart-contract-function-reference)
5. [Interaction Patterns](#interaction-patterns)
6. [Complete Example Flows](#complete-example-flows)

---

## 1. Agent Lifecycle Flow

### Prerequisites Table

| Action | Requires Agent NFT | Requires Policy | Requires Executor Auth* |
|--------|-------------------|-----------------|----------------------|
| `registerAgent()` | ❌ Creates it | ❌ | ❌ |
| `installAgent()` | ✅ | ❌ Creates it | ❌ |
| `authorizeExecutor()` | ✅ | ❌ | ❌ |
| `placeLimitOrder()` | ✅ | ✅ | ✅* |
| `executeSwap()` | ✅ | ✅ | ✅* |
| `executeBorrow()` | ✅ | ✅ | ✅* |
| `cancelOrder()` | ✅ | ✅ | ✅* |

**\*Important:** Executor authorization is ONLY required if the executor wallet is **different** from the owner wallet.

**Three Ways to Be Authorized (without calling `authorizeExecutor()`):**
1. ✅ **You own the Agent NFT** - Owner is always authorized automatically
2. ✅ **You are the agentWallet** - Set via `setAgentWallet()` in IdentityRegistry (ERC-8004 standard)
3. ✅ **Owner explicitly authorized you** - Via `authorizeExecutor()` in AgentRouter

**Key Insights:**
- Owner wallet can always execute - no authorization step needed!
- You can authorize an executor before installing a policy, but the executor cannot trade until the policy is installed.

---

### Authorization Logic (Who Can Execute?)

The `AgentRouter` checks authorization in this order:

```solidity
function _isAuthorizedExecutor(agentTokenId, owner, executor) {
    // Check #1: Is the executor the owner?
    if (executor == owner) return true;  // ✅ ALWAYS AUTHORIZED

    // Check #2: Is executor the agentWallet (ERC-8004 standard)?
    address agentWallet = identityRegistry.getAgentWallet(agentTokenId);
    if (executor == agentWallet) return true;  // ✅ AUTHORIZED

    // Check #3: Did owner explicitly authorize this executor?
    return authorizedExecutors[agentTokenId][executor];  // ✅ if true
}
```

**Visual Decision Tree:**

```
msg.sender wants to execute for Agent #100
           |
           v
    Does msg.sender own Agent NFT #100?
           |
     YES ──┴── NO
      |         |
      v         v
  ✅ AUTHORIZED   Is msg.sender the agentWallet?
                 |
           YES ──┴── NO
            |         |
            v         v
        ✅ AUTHORIZED   Did owner call authorizeExecutor()?
                       |
                 YES ──┴── NO
                  |         |
                  v         v
              ✅ AUTHORIZED  ❌ REJECTED
```

**Practical Examples:**

```
Agent #100 owned by: 0x85C6...727E

Scenario A: Owner executes
--------------------------
msg.sender: 0x85C6...727E (owner)
Result: ✅ AUTHORIZED (Check #1 passes)
Authorization step needed: NO

Scenario B: Separate executor (not yet authorized)
--------------------------
msg.sender: 0xfc98...14dc (different wallet)
Result: ❌ REJECTED (all checks fail)
Authorization step needed: YES - must call authorizeExecutor()

Scenario C: Separate executor (after authorization)
--------------------------
Owner called: authorizeExecutor(100, 0xfc98...14dc)
msg.sender: 0xfc98...14dc
Result: ✅ AUTHORIZED (Check #3 passes)
```

---

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

⚠️ **THIS STEP IS OPTIONAL** - Only needed if you want a **separate wallet** to execute on behalf of the agent owner.

**When to Skip This Step:**
- ✅ Owner wants to execute trades themselves
- ✅ Owner's wallet will be the executor

**When This Step IS Needed:**
- AI agent needs a dedicated execution wallet (separate from owner)
- Want to delegate execution to a different address
- Multiple executors needed for the same agent

```
Owner → AgentRouter.authorizeExecutor()
  ↓
Executor Address Added
  ↓
Executor Authorized (but needs policy to trade)
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
- Verifies caller owns the agent (via IdentityRegistry)
- Authorizes executor address
- Stores authorization in mapping
- Executor can now act on behalf of owner (within policy limits)

**Important Notes:**
- ✅ **Policy NOT required** to authorize executor
- ⚠️ **Policy IS required** for executor to actually trade
- 💡 **Owner is ALWAYS authorized** - no need to authorize themselves

**Valid Setup Options:**
```
Option A (Owner Executes Themselves - Simplest):
1. Register Agent
2. Install Policy
→ Owner can trade immediately, no authorization needed!

Option B (Separate Executor - For AI Agents):
1. Register Agent
2. Install Policy
3. Authorize Executor → Executor can trade immediately

Option C (Authorize First):
1. Register Agent
2. Authorize Executor → Authorized but cannot trade yet
3. Install Policy → Now can trade
```

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
   - ✅ Executor is authorized for this agent (checks authorization mapping)
   - ✅ Policy is installed (reverts if not installed)
   - ✅ Agent policy allows this trade (calls policy validation)
   - ✅ Order within policy limits (price, quantity, asset restrictions)
3. **AgentRouter calls** `OrderBook.placeLimitOrder()` with agent tracking
4. **OrderBook:**
   - Records order with `agentTokenId` and `executor`
   - Emits `OrderPlaced` event
5. **AgentRouter emits** `AgentLimitOrderPlaced` event

**Validation Order:**
```solidity
// 1. Check executor authorization
require(isAuthorizedExecutor(agentTokenId, msg.sender), "Not authorized");

// 2. Get and verify policy exists
IAgentPolicy policy = policyFactory.getAgentPolicy(agentTokenId);
require(address(policy) != address(0), "No policy installed");

// 3. Validate trade against policy
policy.validateTrade(baseToken, quoteToken, price, quantity, isBuy);
```

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

## 6. Real-World Wallet Examples

### 6.1 Actual Setup from Testing

**Agent Owner Wallet:**
```
Address: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
Role: Agent Owner
Owns: Agent Token ID 100
Capabilities:
- Register agents
- Install/uninstall policies
- Authorize/revoke executors
- Transfer agent ownership
- Fund the agent (deposits, collateral)
```

**Executor Wallet:**
```
Address: 0xfc98c3ed81138d8a5f35b30a3b735cb5362e14dc
Role: Authorized Executor
Agent: Token ID 100
Capabilities:
- Place limit orders on behalf of agent
- Execute swaps for agent
- Borrow/repay for agent
- Supply/withdraw collateral for agent
- Cancel agent's orders
```

**Agent Configuration:**
```
Agent Token ID: 100
Owner: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
Policy Template: conservative
Authorized Executors: [0xfc98c3ed81138d8a5f35b30a3b735cb5362e14dc]
Status: Active
Installed At: Block 37588057 (Feb 12, 2026)
```

### 6.2 Example Order Placed

**Order Details:**
```
Order ID: 6
Agent Token ID: 100
Executor: 0xfc98c3ed81138d8a5f35b30a3b735cb5362e14dc
User Address (Owner): 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
Pool: WETH-IDRX (0x629a14Ee7dc9D29a5EB676fbCEF94e989bc0dEa1)
Side: Buy
Price: 300000 (0.3 IDRX per WETH)
Quantity: 10000000000000000 (0.01 WETH)
Status: OPEN
Transaction: 0xc271d5811f5fef7fc498c3e177a8a17b3ed8455f08d3325d6507b677a88c6402
```

**How This Was Created:**
```bash
# Executor called AgentRouter.placeLimitOrder() with:
agentTokenId: 100
orderBook: 0x629a14Ee7dc9D29a5EB676fbCEF94e989bc0dEa1
baseToken: WETH
quoteToken: IDRX
price: 300000
quantity: 10000000000000000
isBuy: true
expiry: 90 days

# Result: Order successfully placed and indexed
# Visible via API: GET /api/agents/100/orders
```

### 6.3 Key Relationships

```
┌─────────────────────────────────────────┐
│  Agent Owner                            │
│  0x85C6...727E                         │
│                                         │
│  Owns:                                  │
│  - Agent NFT #100                       │
│  - Funds (WETH, IDRX)                  │
│  - Control over policy & executors      │
└─────────────────┬───────────────────────┘
                  │
                  │ authorizes
                  ↓
┌─────────────────────────────────────────┐
│  Executor                               │
│  0xfc98...14dc                         │
│                                         │
│  Can Execute:                           │
│  - Trading operations                   │
│  - Lending operations                   │
│  - Order management                     │
│                                         │
│  Limited By:                            │
│  - Agent's policy rules                 │
│  - Policy template (conservative)       │
└─────────────────┬───────────────────────┘
                  │
                  │ places orders via
                  ↓
┌─────────────────────────────────────────┐
│  AgentRouter                            │
│  0x36f2...1574                         │
│                                         │
│  Validates:                             │
│  - Executor authorization               │
│  - Policy compliance                    │
│  - Trade limits                         │
│                                         │
│  Routes To:                             │
│  - OrderBook (for limit orders)         │
│  - ScaleXRouter (for swaps)            │
│  - AutoBorrowHelper (for lending)      │
└─────────────────────────────────────────┘
```

---

## 7. Complete Example Flows

### Example 1: Simple Agent Trading (Owner as Executor)

**⭐ Simplest Setup - Owner executes their own trades:**

```
Step 1: Register Agent
-----------------------
Owner (0x85C6...727E) → IdentityRegistry.registerAgent(0x85C6...727E)
Transaction: Mints ERC-721 NFT
Returns: agentTokenId = 100
Block: 37588057

Step 2: Install Policy
----------------------
Owner (0x85C6...727E) → PolicyFactory.installAgent(
    agentTokenId: 100,
    template: "conservative",
    policy: encodedPolicyData
)
Returns: policyAddress (BeaconProxy created)
Event: AgentInstalled emitted
Agent Status: ✅ READY TO TRADE (no authorization step needed!)

Step 3: Fund Agent
-----------------
Owner → Transfer 1 WETH to 0x85C6...727E
Owner → Approve OrderBook to spend WETH
Balances ready for trading

Step 4: Place Order (Owner executes directly)
---------------------------------------------
Owner (0x85C6...727E) → AgentRouter.placeLimitOrder(
    agentTokenId: 100,
    orderBook: 0x629a14Ee...,
    baseToken: WETH,
    quoteToken: IDRX,
    price: 300000,
    quantity: 10000000000000000,
    isBuy: true,
    expiry: 1778747754
)

Flow Inside:
  ✅ AgentRouter checks: msg.sender == owner? YES → Authorized!
  ✅ No authorizeExecutor() was needed - owner is always authorized
  ✅ AgentRouter checks policy compliance
  ✅ OrderBook records order with agentTokenId: 100
  ✅ Events emitted

Result: Order placed successfully by owner
```

---

### Example 2: AI Agent with Separate Executor Wallet

**🤖 For AI agents that need dedicated execution wallet:**

```
Step 1: Register Agent
-----------------------
Owner (0x85C6...727E) → IdentityRegistry.registerAgent(0x85C6...727E)
Transaction: Mints ERC-721 NFT
Returns: agentTokenId = 100
Block: 37588057

Step 2: Install Policy
----------------------
Owner (0x85C6...727E) → PolicyFactory.installAgent(
    agentTokenId: 100,
    template: "conservative",
    policy: encodedPolicyData
)
Returns: policyAddress (BeaconProxy created)
Event: AgentInstalled emitted
Agent Status: Ready to trade

Step 3: Authorize Executor ⚠️ REQUIRED for separate wallet
--------------------------
Owner (0x85C6...727E) → AgentRouter.authorizeExecutor(
    agentTokenId: 100,
    executor: 0xfc98c3ed81138d8a5f35b30a3b735cb5362e14dc
)
Result: Executor 0xfc98...14dc can now trade for Agent #100

Step 4: Fund Agent
-----------------
Owner → Transfer 1 WETH to 0x85C6...727E
Owner → Approve OrderBook (0x629a14Ee...) to spend WETH
Balances ready for trading

Step 5: Place Order (The Real Transaction)
------------------------------------------
Executor (0xfc98...14dc) → AgentRouter.placeLimitOrder(
    agentTokenId: 100,
    orderBook: 0x629a14Ee7dc9D29a5EB676fbCEF94e989bc0dEa1,
    baseToken: 0xWETH_ADDRESS,
    quoteToken: 0xIDRX_ADDRESS,
    price: 300000,              // 0.3 IDRX per WETH
    quantity: 10000000000000000, // 0.01 WETH
    isBuy: true,
    expiry: 1778747754          // 90 days from placement
)

Transaction Hash: 0xc271d5811f5fef7fc498c3e177a8a17b3ed8455f08d3325d6507b677a88c6402
Block: 37601733

Flow Inside:
  ✅ AgentRouter validates executor (0xfc98...14dc) is authorized
  ✅ AgentRouter checks policy compliance (conservative template)
  ✅ AgentRouter calls OrderBook.placeLimitOrder() with agent tracking
  ✅ OrderBook records order with:
     - agentTokenId: 100
     - executor: 0xfc98c3ed81138d8a5f35b30a3b735cb5362e14dc
     - userAddress: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
  ✅ OrderBook emits OrderPlaced event
  ✅ AgentRouter emits AgentLimitOrderPlaced event

Result:
  → Order placed successfully
  → Order ID: 6
  → Status: OPEN
  → Visible in indexer with agent tracking
  → Query via: GET /api/agents/100/orders
  → Query via: GET /api/agent-orders?executor=0xfc98...14dc
```

**Verification:**
```bash
# Check in indexer
curl -s 'http://localhost:42070/api/agents/100/orders' | jq '.'

# Returns:
{
  "success": true,
  "data": [
    {
      "orderId": "6",
      "agentTokenId": "100",
      "executor": "0xfc98c3ed81138d8a5f35b30a3b735cb5362e14dc",
      "userAddress": "0x85C67299165117acAd97C2c5ECD4E642dFbF727E",
      "side": "Buy",
      "price": "300000",
      "quantity": "10000000000000000",
      "status": "OPEN"
    }
  ]
}
```

---

### Example 2: Agent Lending Flow (End-to-End)

**Using Real Addresses from Our Setup:**

```
Step 1-3: Same as Example 1 (Register, Install, Authorize)
  Agent Token ID: 100
  Owner: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
  Executor: 0xfc98c3ed81138d8a5f35b30a3b735cb5362e14dc

Step 4: Supply Collateral
-------------------------
Executor (0xfc98...14dc) → AgentRouter.supplyCollateral(
    agentTokenId: 100,
    asset: 0xWETH_ADDRESS,
    amount: 1000000000000000000,  // 1 WETH
    onBehalfOf: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
)

Flow Inside:
  ✅ Validates executor (0xfc98...14dc) is authorized for Agent #100
  ✅ Checks policy allows collateral supply (conservative template permits)
  ✅ Calls AutoBorrowHelper.supply() with agentTokenId=100
  ✅ LendingManager records collateral for 0x85C6...727E
  ✅ Emits AgentCollateralSupplied event

Result:
  → 1 WETH supplied as collateral
  → Agent can now borrow against this collateral
  → Health factor calculated

Step 5: Borrow IDRX
------------------
Executor (0xfc98...14dc) → AgentRouter.executeBorrow(
    agentTokenId: 100,
    asset: 0xIDRX_ADDRESS,
    amount: 100000000000000000000000,  // 1000 IDRX (assuming 2 decimals * 10^18)
    onBehalfOf: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
)

Flow Inside:
  ✅ Validates executor authorization
  ✅ Checks policy borrow limits (conservative: max 50% LTV)
  ✅ Validates health factor > 1.0
  ✅ Calls AutoBorrowHelper.borrow() with agentTokenId=100
  ✅ LendingManager records debt for 0x85C6...727E
  ✅ Transfers 1000 IDRX to 0x85C6...727E
  ✅ Emits AgentBorrowExecuted event

Result:
  → 1000 IDRX borrowed
  → Debt recorded with agent tracking
  → Health factor updated
  → IDRX available in agent owner wallet

Step 6: Partial Repay
--------------------
Executor (0xfc98...14dc) → AgentRouter.executeRepay(
    agentTokenId: 100,
    asset: 0xIDRX_ADDRESS,
    amount: 50000000000000000000000,  // 500 IDRX
    onBehalfOf: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
)

Flow Inside:
  ✅ Validates executor authorization
  ✅ Calls AutoBorrowHelper.repay() with agentTokenId=100
  ✅ LendingManager reduces debt from 1000 to 500 IDRX
  ✅ Health factor improves
  ✅ Emits AgentRepayExecuted event

Result:
  → 500 IDRX repaid
  → Remaining debt: 500 IDRX
  → Better health factor
  → More borrowing capacity

Step 7: Withdraw Some Collateral
--------------------------------
Executor (0xfc98...14dc) → AgentRouter.withdrawCollateral(
    agentTokenId: 100,
    asset: 0xWETH_ADDRESS,
    amount: 200000000000000000,  // 0.2 WETH
    to: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
)

Flow Inside:
  ✅ Validates executor authorization
  ✅ Checks health factor remains > 1.0 after withdrawal
  ✅ Calls AutoBorrowHelper.withdraw() with agentTokenId=100
  ✅ LendingManager reduces collateral
  ✅ Transfers 0.2 WETH to owner
  ✅ Emits AgentCollateralWithdrawn event

Result:
  → 0.2 WETH withdrawn
  → Remaining collateral: 0.8 WETH
  → Still maintains healthy position
```

**Final Position:**
```
Agent #100 (Owner: 0x85C6...727E)
├── Collateral: 0.8 WETH
├── Debt: 500 IDRX
├── Health Factor: ~1.6 (healthy)
└── Available to Borrow: More IDRX if needed
```

**Verification via API:**
```bash
# Check agent lending activity
curl -s 'http://localhost:42070/api/agents/100/lending' | jq '.'

# Returns all supply, borrow, repay, withdraw events
# Each event includes:
# - agentTokenId: 100
# - executor: 0xfc98c3ed81138d8a5f35b30a3b735cb5362e14dc
# - owner: 0x85C67299165117acAd97C2c5ECD4E642dFbF727E
# - eventType, asset, amount, timestamp
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

## 8. Marketplace / Copy Trading Use Case

### Scenario: One Executor Trading for Multiple Users

**Use Case:** Developer creates an AI trading agent, multiple users subscribe and copy the strategy.

### Architecture

```
Developer's Setup:
├── Agent #500 (identity/reputation ONLY - no policy)
├── Executor Wallet: 0xDEV_EXECUTOR
└── Off-chain trading service (AI/LLM analysis)

Subscribers (each with their OWN policy):
├── Alice: Agent #100
│   ├── Policy: Conservative (installed by Alice)
│   ├── Authorized executor: 0xDEV_EXECUTOR
│   └── Funds: 10,000 IDRX in BalanceManager
│
├── Bob: Agent #200
│   ├── Policy: Aggressive (installed by Bob)
│   ├── Authorized executor: 0xDEV_EXECUTOR
│   └── Funds: 50,000 IDRX in BalanceManager
│
└── Carol: Agent #300
    ├── Policy: Moderate (installed by Carol)
    ├── Authorized executor: 0xDEV_EXECUTOR
    └── Funds: 5,000 IDRX in BalanceManager

Result: 0xDEV_EXECUTOR executes same strategy for all,
        but each user's policy enforces their own limits!
```

### Complete Flow

```
Step 1: Developer Setup (One Time)
───────────────────────────────────
Developer (0xDEV...):
├── Registers Agent #500 (for identity/reputation only)
│   └── IdentityRegistry.register()
│       └── Returns: agentTokenId = 500
│   └── NO policy installed - Agent #500 is just for tracking
│
└── Runs off-chain trading service
    ├── Executor wallet: 0xDEV_EXECUTOR
    ├── Analyzes market using AI/LLM
    └── Executes trades for all subscribers

Step 2: Alice Subscribes
────────────────────────
Off-chain (your platform):
├── Alice visits marketplace webpage
├── Sees Developer's Agent #500:
│   ├── 90-day return: +15%
│   ├── Win rate: 65%
│   └── Subscription: 100 IDRX/month
│
├── Alice pays subscription fee (Stripe/crypto)
└── Your backend adds Alice to active subscribers list

On-chain (Alice executes):
├── 1. Register her own agent:
│   └── IdentityRegistry.register()
│       └── Returns: Alice's agentTokenId = 100
│
├── 2. Install HER OWN policy (Alice chooses her risk level):
│   └── PolicyFactory.installAgentFromTemplate(
│           agentTokenId: 100,
│           templateName: "conservative",  // ⭐ Alice's choice
│           customizations: {
│               maxOrderSize: 1000 IDRX,
│               dailyVolumeLimit: 5000 IDRX
│           }
│       )
│   └── This policy will be enforced when developer's executor trades
│
├── 3. Authorize developer's executor:
│   └── AgentRouter.authorizeExecutor(100, 0xDEV_EXECUTOR)
│
└── 4. Deposit funds:
    └── BalanceManager.deposit(10000 IDRX)

Step 3: Developer's Service Executes Trades
────────────────────────────────────────────
Developer's off-chain service (runs every 5 min):

// Pseudocode
async function runTradingLoop() {
    // 1. Get active subscribers from your database
    const subscribers = await db.query(`
        SELECT agentTokenId
        FROM subscriptions
        WHERE developerAgentId = 500
        AND active = true
        AND paidUntil > NOW()
    `);
    // Returns: [100, 200, 300] (Alice, Bob, Carol)

    // 2. Analyze market
    const signal = await analyzeMarketWithAI();

    // 3. If trade signal, execute for ALL subscribers
    if (signal.shouldTrade) {
        for (const agentId of subscribers) {
            await agentRouter.placeLimitOrder(
                agentId,           // 100, then 200, then 300
                signal.baseToken,
                signal.quoteToken,
                signal.price,
                signal.quantity,
                signal.isBuy,
                signal.expiry,
                { from: DEV_EXECUTOR }  // Same executor for all!
            );
        }

        // Result: 3 trades executed:
        // - Agent #100 (Alice's funds)
        // - Agent #200 (Bob's funds)
        // - Agent #300 (Carol's funds)
    }
}

Step 4: Bob Also Subscribes (with different policy)
───────────────────────────────────────────────────
Bob:
├── Pays subscription (off-chain)
├── Registers Agent #200
├── Installs AGGRESSIVE policy (his choice)
│   └── PolicyFactory.installAgentFromTemplate(
│           agentTokenId: 200,
│           templateName: "aggressive",  // ⭐ Different from Alice!
│           customizations: {
│               maxOrderSize: 10000 IDRX,  // 10x Alice's limit
│               dailyVolumeLimit: 100000 IDRX
│           }
│       )
├── Authorizes 0xDEV_EXECUTOR
└── Deposits 50,000 IDRX

Now developer's service executes for Alice + Bob:
├── Same trading strategy
├── But Alice's conservative policy limits her trades
└── While Bob's aggressive policy allows larger trades

Step 5: Alice Unsubscribes
───────────────────────────
Off-chain:
└── Alice cancels subscription on website
    └── Your backend updates: subscriptions.active = false
    └── Developer's service stops executing for Agent #100

On-chain (optional):
└── Alice: AgentRouter.revokeExecutor(100, 0xDEV_EXECUTOR)
```

### Key Points

**Developer's Agent #500:**
- ℹ️ Identity/reputation ONLY (no policy)
- ℹ️ Tracks performance history
- ℹ️ Listed on marketplace
- ❌ Does NOT have a policy installed

**User's Agents (#100, #200, #300):**
- ✅ Each user installs THEIR OWN policy when subscribing
- ✅ Policy reflects user's risk tolerance (conservative/aggressive/moderate)
- ✅ Policy is enforced when developer's executor trades for them
- ✅ Same strategy, different limits per user!

**On-Chain (Handled by Smart Contracts):**
✅ Agent identity (ERC-8004 NFTs)
✅ Executor authorization
✅ **Policy enforcement (user-level)**
✅ Trade execution
✅ Fund management (BalanceManager)

**Off-Chain (Your Responsibility):**
❌ Subscription management
❌ Payment processing (monthly fees, performance fees)
❌ Performance tracking and analytics
❌ Marketplace listings
❌ Active subscriber list
❌ Trading strategy/AI logic

### Developer Revenue Model

```
Costs per month:
├── AI/LLM tokens: $50
├── Gas fees: $300 (for all trades)
├── Server costs: $100
└── Total: $450

Revenue per month:
├── Alice: 100 IDRX/month subscription
├── Bob: 100 IDRX/month subscription
├── Carol: 100 IDRX/month subscription
├── Performance fees: 20% of profits
└── Total: ~$800

Profit: ~$350/month
```

### Benefits of This Model

**For Developers:**
- Build once, serve many users
- Recurring revenue from subscriptions
- Performance fees from successful trades
- Reputation tracked on-chain (Agent #500)

**For Users:**
- Access to proven trading strategies
- Keep custody of their funds
- Can unsubscribe anytime
- On-chain performance history

**Platform Advantages:**
- No need for complex on-chain subscription logic
- Lower gas costs
- Flexible payment options (fiat, crypto, etc.)
- Easy to add features (analytics, leaderboards, etc.)

---

**Last Updated:** February 13, 2026
**Network:** Base Sepolia (Chain ID: 84532)
**ERC Standard:** ERC-8004 (AI Agent Identity & Delegation)

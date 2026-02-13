# ERC-8004 Agent System - Complete Architecture & Business Model

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Setup Flow](#setup-flow)
4. [Place Order Flow](#place-order-flow)
5. [Business Model](#business-model)
6. [Future Features](#future-features)

---

# Overview

## Key Concept: ERC-8004 Dual Address System

**Each agent has TWO addresses:**
1. **Owner Address** - The human/entity that owns the agent NFT
2. **Agent Wallet Address** - The wallet controlled by the agent itself (stored in `evm_address` field)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ERC-8004 DUAL ADDRESS SYSTEM                         │
└─────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐                  ┌──────────────────┐
│  Owner Wallet    │                  │  Agent Wallet    │
│ 0x27dD...7cB7    │                  │ 0xABCD...EFGH    │
└────────┬─────────┘                  └────────┬─────────┘
         │                                     │
         │ Owns NFT                            │ Controlled by AI Agent
         │ Sets Policy                         │ Signs Transactions
         │ Owns Trading Capital                │ Executes Orders
         │                                     │
         └──────────┬──────────────────────────┘
                    │
                    │ Both linked to
                    ▼
         ┌─────────────────────┐
         │  Agent NFT Token #1 │
         │  (ERC-8004)         │
         └─────────────────────┘
```

---

# Architecture

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        FULL SYSTEM ARCHITECTURE                         │
└─────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Owner Wallet    │  (Primary Trader - Human/Entity)
│ 0x27dD...7cB7    │
└────────┬─────────┘
         │
         │ 1. Mints Agent NFT
         │ 2. Registers Agent Wallet Address
         │ 3. Sets Policy
         │ 4. Deposits Trading Capital
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                   IdentityRegistry (ERC-8004 ERC-721)                   │
│                                                                         │
│  Token ID: 1                                                            │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │ owner: 0x27dD...7cB7           ← NFT owner (human)            │     │
│  │ agentWallet: 0xABCD...EFGH     ← Agent's wallet (AI)          │     │
│  │ metadataURI: "ipfs://..."                                     │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│  Key Functions:                                                         │
│  - ownerOf(1) → 0x27dD...7cB7                                           │
│  - getAgentWallet(1) → 0xABCD...EFGH                                    │
└─────────────────────────────────────────────────────────────────────────┘
         │                                    │
         │ Owner Link                         │ Agent Wallet Link
         ▼                                    ▼
┌──────────────────────┐         ┌───────────────────────┐
│   PolicyFactory      │         │    Agent Wallet       │
│                      │         │  0xABCD...EFGH        │
│  Policy for Agent #1:│         │                       │
│  - Owner: 0x27dD..  │         │  Private Key:         │
│  - Max: 10 ETH       │         │  Controlled by AI     │
│  - Daily: 100 ETH    │         │                       │
└──────────────────────┘         └───────┬───────────────┘
         │                               │
         │ Policy Enforcement            │ Executes Transactions
         │                               │
         └──────────┬────────────────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │    AgentRouter      │
         │  Authorization:     │
         │  1. Check owner     │
         │  2. Check agent     │
         │     wallet from     │
         │     registry        │
         │  3. Enforce policy  │
         └──────────┬──────────┘
                    │
                    │ Places order with owner address
                    ▼
         ┌─────────────────────┐
         │     OrderBook       │
         │  Order owner:       │
         │  0x27dD...7cB7      │
         └──────────┬──────────┘
                    │
                    │ Deducts from owner balance
                    ▼
         ┌─────────────────────┐
         │   BalanceManager    │
         │  Account:           │
         │  0x27dD...7cB7      │
         └─────────────────────┘
```

## ERC-8004 Data Structure

**Off-Chain Metadata (JSON):**
```json
{
  "agent_id": "agent.eth#1",
  "name": "TradingAgent",
  "owner": "0x27dD1eBE7D826197FD163C134E79502402Fd7cB7",
  "evm_address": "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
  "capabilities": ["trading", "risk-management"],
  "metadata_uri": "ipfs://Qm..."
}
```

**On-Chain Storage (IdentityRegistry):**
```solidity
_owners[1] = 0x27dD...7cB7                // ownerOf(1)
_agentWallets[1] = 0xABCD...EFGH           // getAgentWallet(1)  ← NEW!
_tokenURIs[1] = "ipfs://Qm..."             // tokenURI(1)
```

---

# Setup Flow

## Step-by-Step Agent Initialization

```
┌─────────────────────────────────────────────────────────────────────────┐
│                 STEP 1: Create Agent Wallet (Off-Chain)                 │
└─────────────────────────────────────────────────────────────────────────┘

Off-Chain: AI Agent Infrastructure generates keypair
├─ Private Key: 0x1234567890abcdef... (stored securely in TEE/HSM)
└─ Public Address: 0xABCD...EFGH

┌─────────────────────────────────────────────────────────────────────────┐
│             STEP 2: Owner Mints Agent NFT with Wallet Address           │
└─────────────────────────────────────────────────────────────────────────┘

┌────────────────┐
│  Owner Wallet  │
└───────┬────────┘
        │
        │ tx: identityRegistry.mintWithWallet(
        │       to: 0x27dD...7cB7,           // Owner address
        │       tokenId: 1,
        │       agentWallet: 0xABCD...EFGH,   // Agent's wallet ← KEY!
        │       metadataURI: "ipfs://..."
        │     )
        │ msg.sender: 0x27dD...7cB7
        │ gas paid by: Owner
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      IdentityRegistry                                   │
│                                                                         │
│  mintWithWallet():                                                      │
│    _owners[1] = 0x27dD...7cB7        ← Owner of NFT                    │
│    _agentWallets[1] = 0xABCD...EFGH  ← Agent's wallet ← KEY!           │
│    _tokenURIs[1] = "ipfs://..."                                         │
│    _exists[1] = true                                                    │
│                                                                         │
│  emit AgentIdentityCreated(1, 0x27dD...7cB7, "ipfs://...")             │
│  emit AgentWalletSet(1, 0xABCD...EFGH)                                  │
└─────────────────────────────────────────────────────────────────────────┘

Result: ✓ Agent NFT #1 created
        ✓ Owner: 0x27dD...7cB7
        ✓ Agent Wallet: 0xABCD...EFGH (stored in registry)


┌─────────────────────────────────────────────────────────────────────────┐
│                    STEP 3: Install Policy                               │
└─────────────────────────────────────────────────────────────────────────┘

Owner → PolicyFactory.installAgentFromTemplate(
  agentTokenId: 1,
  template: "moderate",
  customization: {
    maxOrderSize: 10 ether,
    dailyVolumeLimit: 100 ether,
    expiryTimestamp: 0,
    whitelistedTokens: []
  }
)

Result: ✓ Policy installed with limits


┌─────────────────────────────────────────────────────────────────────────┐
│              STEP 4: Deposit Funds to BalanceManager                    │
└─────────────────────────────────────────────────────────────────────────┘

Owner → IDRX.approve(balanceManager, 50000)
Owner → BalanceManager.depositLocal(IDRX, 50000, owner)

Result: ✓ Owner has 50,000 IDRX in BalanceManager


┌─────────────────────────────────────────────────────────────────────────┐
│              STEP 5: Fund Agent Wallet with Gas (Optional)              │
└─────────────────────────────────────────────────────────────────────────┘

Owner → payable(0xABCD...EFGH).transfer(0.1 ether)

Result: ✓ Agent wallet has gas to execute transactions

┌─────────────────────────────────────────────────────────────────────────┐
│                      SETUP COMPLETE                                     │
│                                                                         │
│  ✓ Agent NFT #1 minted and owned by 0x27dD...7cB7                      │
│  ✓ Agent wallet 0xABCD...EFGH registered in ERC-8004                   │
│  ✓ Policy installed with 10 ETH max order, 100 ETH daily limit         │
│  ✓ Owner deposited 50,000 IDRX to BalanceManager                       │
│  ✓ Agent wallet funded with gas                                        │
│                                                                         │
│  Ready to place orders!                                                │
└─────────────────────────────────────────────────────────────────────────┘
```

---

# Place Order Flow

## Complete Transaction Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                STEP 1: Agent Wallet Submits Transaction                 │
└─────────────────────────────────────────────────────────────────────────┘

┌────────────────┐
│  Agent Wallet  │  (AI-controlled wallet)
│ 0xABCD...EFGH  │
└───────┬────────┘
        │
        │ AI Agent signs transaction with its private key
        │
        │ tx: agentRouter.executeLimitOrder(
        │       agentTokenId: 1,
        │       pool: WETH/IDRX,
        │       price: 200000,
        │       quantity: 3000000000000000,
        │       side: BUY,
        │       ...
        │     )
        │ msg.sender: 0xABCD...EFGH  ← Agent wallet signs!
        │ gas paid by: Agent Wallet
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                    executeLimitOrder(...)                               │
└─────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────┐
│              STEP 2: Get Owner from IdentityRegistry                    │
└─────────────────────────────────────────────────────────────────────────┘

AgentRouter (Line 265):
  address owner = identityRegistry.ownerOf(1)
                  └─ returns 0x27dD...7cB7  ← NFT owner


┌─────────────────────────────────────────────────────────────────────────┐
│          STEP 3: Check Authorization (ERC-8004 COMPLIANT)               │
└─────────────────────────────────────────────────────────────────────────┘

AgentRouter (Line 273-276):
  require(
    msg.sender == owner ||
    _isAuthorizedExecutor(agentTokenId, owner, msg.sender),
    "Not authorized executor"
  );

  Check 1: msg.sender == owner?
          0xABCD...EFGH == 0x27dD...7cB7?  → false

  Check 2: _isAuthorizedExecutor(1, 0x27dD...7cB7, 0xABCD...EFGH)?
          ├─ Get agent wallet from registry:
          │  identityRegistry.getAgentWallet(1)
          │  └─ returns 0xABCD...EFGH
          │
          └─ Compare: executor == agentWallet?
             0xABCD...EFGH == 0xABCD...EFGH?  → true ✓

  Authorization passed! ✓


┌─────────────────────────────────────────────────────────────────────────┐
│                    STEP 4: Load & Validate Policy                       │
└─────────────────────────────────────────────────────────────────────────┘

AgentRouter:
  policy = policyFactory.getPolicy(owner, agentTokenId)

  Checks:
  ✓ policy.enabled == true
  ✓ block.timestamp < expiryTimestamp (or no expiry)
  ✓ policy.allowLimitOrders == true
  ✓ policy.allowPlaceLimitOrder == true


┌─────────────────────────────────────────────────────────────────────────┐
│                    STEP 5: Enforce Order Limits                         │
└─────────────────────────────────────────────────────────────────────────┘

AgentRouter._enforceLimitOrderPermissions():

  Check 1: Order size within limit?
    quantity <= policy.maxOrderSize
    0.003 WETH <= 10 WETH  ✓

  Check 2: Daily volume within limit?
    dailyVolume + quantity <= policy.dailyVolumeLimit
    0.003 WETH <= 100 WETH  ✓

  All checks passed ✓


┌─────────────────────────────────────────────────────────────────────────┐
│            STEP 6: Place Order on OrderBook (Owner as Owner)            │
└─────────────────────────────────────────────────────────────────────────┘

AgentRouter → OrderBook.placeOrder(
    price: 200000,
    quantity: 3000000000000000,
    side: BUY,
    owner: 0x27dD...7cB7,    ← OWNER, not agent wallet!
    timeInForce: GTC,
    autoRepay: false,
    autoBorrow: false
  );

OrderBook:
  ✓ Verify caller is authorized router (AgentRouter)
  ✓ Calculate quote amount needed: 600 IDRX
  ✓ Check minimum trade amount: 600 >= 500 ✓
  ✓ Create order with owner = 0x27dD...7cB7
  ✓ Call BalanceManager to lock funds


┌─────────────────────────────────────────────────────────────────────────┐
│                  STEP 7: Lock Funds in BalanceManager                   │
└─────────────────────────────────────────────────────────────────────────┘

OrderBook → BalanceManager.lockForOrder(
    owner: 0x27dD...7cB7,    ← Owner's account
    currency: IDRX,
    amount: 600
  )

BalanceManager:
  ✓ Check owner has sufficient balance
  ✓ Lock 600 IDRX from owner's account
  ✓ emit BalanceLocked(0x27dD...7cB7, IDRX, 600)


┌─────────────────────────────────────────────────────────────────────────┐
│              STEP 8: Update Tracking & Emit Events                      │
└─────────────────────────────────────────────────────────────────────────┘

AgentRouter:
  ✓ Update daily volume tracking
  ✓ Update last trade time

  emit AgentLimitOrderPlaced(
    owner: 0x27dD...7cB7,         ← Primary trader
    agentTokenId: 1,
    executor: 0xABCD...EFGH,      ← Agent wallet
    orderId: 3,
    ...
  );

┌─────────────────────────────────────────────────────────────────────────┐
│                      ORDER PLACEMENT COMPLETE                           │
│                                                                         │
│  ✓ Agent wallet 0xABCD...EFGH executed transaction                     │
│  ✓ Owner 0x27dD...7cB7 owns the order                                  │
│  ✓ Owner's funds locked in BalanceManager (600 IDRX)                   │
│  ✓ Order ID 3 placed on WETH/IDRX OrderBook                            │
│  ✓ Policy limits enforced                                              │
│  ✓ Agent wallet only paid gas fees                                     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Authorization Flow Diagram

```
Agent Wallet (0xABCD...EFGH) calls executeLimitOrder()
         │
         ▼
    AgentRouter
         │
         ├─ Get owner: identityRegistry.ownerOf(1) → 0x27dD...7cB7
         │
         ├─ Check authorization:
         │  ├─ Is msg.sender == owner? NO
         │  │
         │  └─ Is msg.sender == agent wallet from registry?
         │     ├─ Get agent wallet: identityRegistry.getAgentWallet(1)
         │     │                     → 0xABCD...EFGH
         │     │
         │     └─ Compare: 0xABCD...EFGH == 0xABCD...EFGH? YES ✓
         │
         ├─ Check policy limits ✓
         │
         └─ Place order with owner = 0x27dD...7cB7
                    │
                    ▼
              OrderBook (owner field = 0x27dD...7cB7)
                    │
                    ▼
            BalanceManager (deduct from owner's account)
```

## Summary Table

| Aspect | Value | Source |
|--------|-------|--------|
| **NFT Owner** | 0x27dD...7cB7 | `identityRegistry.ownerOf(1)` |
| **Agent Wallet** | 0xABCD...EFGH | `identityRegistry.getAgentWallet(1)` ← KEY! |
| **Transaction Signer** | Agent Wallet | `msg.sender` in tx |
| **Order Owner** | NFT Owner | `owner` param in placeOrder() |
| **Funds Source** | NFT Owner | BalanceManager account |
| **Gas Payer** | Agent Wallet | tx.origin |

---

# Business Model

## Multi-Owner Architecture

### Can Same Agent Wallet Control Different Owners?

**Answer: YES** ✅

This design enables **Agent-as-a-Service** business models:

```
Agent Wallet: 0xABCD...EFGH (shared across clients)

┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│  Agent NFT #1                   │    │  Agent NFT #2                   │
│  ├─ owner: 0x1111...1111        │    │  ├─ owner: 0x2222...2222        │
│  ├─ agentWallet: 0xABCD...EFGH  │    │  ├─ agentWallet: 0xABCD...EFGH  │
│  └─ policy: 10 ETH max          │    │  └─ policy: 5 ETH max           │
└─────────────────────────────────┘    └─────────────────────────────────┘
              ▲                                     ▲
              │                                     │
              └──────────┬──────────────────────────┘
                         │
                   Same Agent Wallet!
              ┌──────────┴──────────┐
              │  TradingBot LLC     │
              │  0xABCD...EFGH      │
              └─────────────────────┘
```

### Managed Trading Service Example

```
TradingBot LLC (Agent Wallet: 0xABCD...EFGH)
│
├─ Client A (NFT #1)
│  ├─ Balance: $100K
│  ├─ Policy: 10 ETH max order
│  └─ Fees: 20% performance
│
├─ Client B (NFT #2)
│  ├─ Balance: $50K
│  ├─ Policy: 5 ETH max order
│  └─ Fees: 15% performance
│
└─ Client C (NFT #3)
   ├─ Balance: $200K
   ├─ Policy: 20 ETH max order
   └─ Fees: 25% performance

Benefits:
✓ Each client has own balance (isolated)
✓ Each client has own policy (customized)
✓ All clients benefit from same AI strategy
✓ Agent wallet manages all efficiently
✓ Fees collected in one wallet
```

---

# Future Features

## Feature 1: Management Fees

### Fee Models

#### Model A: Performance-Based Fee
```
Profit = Final Balance - Initial Balance
Management Fee = Profit * fee_percentage

Example:
- Initial: $100,000
- Final: $110,000
- Profit: $10,000
- Fee (20%): $2,000
- Owner keeps: $108,000
```

#### Model B: Subscription Fee
```
Monthly Fee = Fixed amount (e.g., 100 IDRX/month)

Agent automatically deducts from owner's BalanceManager account
```

#### Model C: Per-Trade Fee
```
Fee per order = 0.1% of trade volume

Example:
- Order: Buy 1 WETH for 2000 IDRX
- Trade volume: 2000 IDRX
- Fee: 2 IDRX
- Paid to agent wallet: 0xABCD...EFGH
```

### Implementation Approach

```solidity
// In AgentRouter or new FeeManager contract
struct FeeConfig {
    uint256 performanceFeeBps;      // 2000 = 20%
    uint256 monthlySubscription;     // 100 IDRX
    uint256 perTradeFeeBps;          // 10 = 0.1%
    address feeRecipient;            // Agent wallet
}

mapping(uint256 => FeeConfig) public agentFees;

function executeLimitOrder(...) {
    // ... execute order ...

    // Calculate and deduct fee
    uint256 fee = calculateFee(agentTokenId, tradeVolume);
    balanceManager.transferForUser(
        owner,              // From owner
        feeRecipient,       // To agent wallet
        quoteCurrency,
        fee
    );

    emit FeePaid(owner, agentTokenId, fee, feeRecipient);
}
```

### Revenue Model for Agent Operators

```
TradingBot LLC manages 50 clients
Each client:
- Average balance: $100K
- Performance fee: 20%
- Monthly return: 5%

Monthly revenue calculation:
- Total AUM: $5M
- Monthly profit: $250K (5% of $5M)
- Performance fees: $50K (20% of $250K)

Annual revenue: $600K+
```

---

## Feature 2: Agent Marketplace & Transferability

### Overview
Agent NFTs can be bought/sold. Buyers get access to proven trading agents.

### Transfer Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AGENT NFT MARKETPLACE                            │
└─────────────────────────────────────────────────────────────────────────┘

BEFORE SALE:
┌─────────────────────────────────┐
│  Agent NFT #1                   │
│  ├─ owner: Owner A              │
│  ├─ agentWallet: 0xABCD...EFGH  │
│  ├─ track record: 50% APY       │
│  └─ 1,247 trades executed       │
└─────────────────────────────────┘

SALE TRANSACTION:
Owner A lists NFT #1 for 10 ETH
Owner B purchases NFT #1

AFTER SALE:
┌─────────────────────────────────┐
│  Agent NFT #1                   │
│  ├─ owner: Owner B ← NEW!       │
│  ├─ agentWallet: 0xABCD...EFGH  │  ← Unchanged!
│  ├─ track record: 50% APY       │  ← Preserved!
│  └─ 1,247 trades executed       │  ← Preserved!
└─────────────────────────────────┘

Owner B Setup:
1. Install new policy
2. Deposit capital to BalanceManager
3. Agent starts trading for Owner B
```

### Marketplace Listing Example

```
┌──────────────────────────────────────────────────────────────────────┐
│  Agent #1                                          Price: 10 ETH     │
│  ├─ Performance: 50% APY (verified on-chain)                        │
│  ├─ Total Trades: 1,247                                             │
│  ├─ Win Rate: 68%                                                    │
│  ├─ Max Drawdown: 12%                                                │
│  ├─ Active Since: 6 months                                           │
│  ├─ Agent Wallet: 0xABCD...EFGH                                      │
│  └─ Management Fee: 20% performance                                  │
│                                                                      │
│  [Buy Now for 10 ETH] [Make Offer]                                   │
└──────────────────────────────────────────────────────────────────────┘
```

### Agent Pricing Factors

**Performance Metrics:**
- APY: 50% → Premium price
- Win Rate: 68% → Good
- Sharpe Ratio: 2.5 → Excellent
- Max Drawdown: 12% → Safe

**Track Record:**
- 6+ months history → Trusted
- 1000+ trades → Proven
- Multiple market conditions → Robust

**Example Pricing:**
```
Basic Agent (3 months, 20% APY): 1 ETH
Good Agent (6 months, 35% APY): 5 ETH
Elite Agent (12 months, 50% APY): 15 ETH
Legendary Agent (24 months, 100% APY): 50+ ETH
```

### Track Record Verification

```solidity
// On-chain agent statistics
struct AgentStats {
    uint256 totalTrades;
    uint256 totalProfit;      // In quote currency
    uint256 totalLoss;
    uint256 winningTrades;
    uint256 losingTrades;
    uint256 activeSince;
    address[] previousOwners; // History preserved!
}

mapping(uint256 => AgentStats) public agentStats;

// Buyers can verify performance before purchase
function getAgentPerformance(uint256 agentTokenId)
    external view returns (
        uint256 apy,
        uint256 winRate,
        uint256 totalTrades,
        uint256 sharpeRatio
    );
```

---

## Full Lifecycle Example

### Phase 1: Agent Creation (TradingBot LLC)
```
1. Develop AI trading strategy
2. Create agent wallet: 0xABCD...EFGH
3. Backtest and validate
4. Launch on mainnet
5. Mint Agent NFT #1
6. Set management fee: 20% performance
```

### Phase 2: Client Acquisition
```
1. Client A discovers agent on marketplace
2. Reviews track record: 45% APY over 3 months
3. Purchases agent NFT #1 for 5 ETH
4. Installs policy (max 10 ETH per order)
5. Deposits 100,000 IDRX
6. Agent starts trading
```

### Phase 3: Operations (3 Months)
```
Month 1: +8,000 IDRX profit
  - Performance fee: 1,600 IDRX → Agent wallet
  - Client keeps: 6,400 IDRX

Month 2: +12,000 IDRX profit
  - Performance fee: 2,400 IDRX → Agent wallet
  - Client keeps: 9,600 IDRX

Month 3: +15,000 IDRX profit
  - Performance fee: 3,000 IDRX → Agent wallet
  - Client keeps: 12,000 IDRX

Total client profit: 28,000 IDRX (after fees)
Total agent revenue: 7,000 IDRX
```

### Phase 4: Agent NFT Resale
```
Client A wants to exit:
1. Lists Agent NFT #1 for 8 ETH
   - 6-month track record
   - 45% APY verified on-chain
   - 1,500 trades executed

2. Client B buys for 8 ETH
   - Client A profit: 3 ETH (8 - 5 initial)
   - Agent continues for Client B
   - Track record preserved

3. TradingBot receives 2% royalty: 0.16 ETH
```

### Phase 5: Scale (50 Clients)
```
TradingBot LLC expands:
- 50 clients using same agent wallet
- Each paying 20% performance fee
- Total AUM: $5M
- Monthly revenue: $50K+ in fees
- NFT royalties from secondary sales
- Platform becomes Agent-as-a-Service
```

---

## Comparison: Traditional vs Agent NFT Model

### Traditional Managed Fund
```
❌ Fund manager controls client funds
❌ Custody risk
❌ Limited transparency
❌ High minimum investment
❌ Hard to exit
❌ No asset ownership
```

### Agent NFT Model
```
✅ No custody - owner controls funds
✅ Permissioned access via policy
✅ All trades on-chain (transparent)
✅ No minimum investment
✅ Exit anytime (revoke or sell NFT)
✅ NFT is transferable asset
✅ Agent has value independent of capital
✅ Can sell agent for profit
```

---

## Revenue Streams

### For Agent Operators (e.g., TradingBot LLC)

1. **Management Fees**
   - Performance fees: 15-25% of profits
   - Subscription fees: $100-1000/month per client
   - Per-trade fees: 0.1-0.5% of volume

2. **NFT Sales**
   - Initial mint/sale of agent NFTs
   - Premium pricing for proven agents
   - Royalties on secondary sales (2-10%)

3. **Premium Services**
   - Advanced strategies: Higher fees
   - Custom policies: Setup fees
   - Priority execution: Subscription

### For Platform (ScaleX)

1. **Trading Fees**
   - Maker/taker fees on all agent trades
   - Same structure as human traders

2. **NFT Marketplace Fees**
   - 2.5% on agent NFT sales
   - Listing fees for featured placement

3. **Policy Factory**
   - Fees for premium policy templates
   - Custom policy creation

---

## Why This Design is Perfect

✅ **ERC-8004 Compliant**
- Agent wallet stored in NFT registry
- Standard-compliant identity system
- Interoperable with other ERC-8004 systems

✅ **Multi-Owner Support**
- One agent serves many clients
- Efficient for managed services
- Scales to enterprise

✅ **NFT Transferability**
- Built-in with ERC-721
- Agents become valuable assets
- Creates marketplace liquidity
- Track record preserved across sales

✅ **Owner Preservation**
- Orders always owned by current NFT owner
- Clear audit trail
- No custody risk
- Funds always in owner's control

✅ **Policy Isolation**
- Each owner has own limits
- Agent can't exceed permissions
- Owner can revoke anytime
- Separate balances per owner

✅ **Fee-Ready**
- Agent wallet can receive payments
- Easy to add fee logic later
- Supports multiple fee models
- Automatic fee collection

✅ **Marketplace-Ready**
- Track record verification on-chain
- Performance metrics immutable
- Transfer preserves history
- Royalties for creators

---

## Technical Implementation Status

### ✅ Completed
- [x] ERC-8004 IdentityRegistry with agent wallet storage
- [x] AgentRouter with registry-based authorization
- [x] PolicyFactory with per-agent policies
- [x] Multi-owner support (same wallet, multiple agents)
- [x] Owner preservation in all orders
- [x] NFT transferability (ERC-721 standard)

### 🚧 Future Implementation

**Management Fees:**
- [ ] Add FeeManager contract
- [ ] Fee calculation logic
- [ ] Fee payment in executeLimitOrder()
- [ ] Fee configuration per agent
- [ ] Fee tracking events

**Agent Marketplace:**
- [ ] Marketplace UI
- [ ] Listing/delisting functions
- [ ] Purchase/offer system
- [ ] Royalty payments (ERC-2981)
- [ ] Agent statistics tracking
- [ ] Performance verification queries

**Track Record System:**
- [ ] Trade tracking per agent
- [ ] Performance metrics calculation
- [ ] Historical data storage
- [ ] Stats preserved across transfers
- [ ] Verification API for buyers

---

## Summary

This ERC-8004 agent system enables a complete **Agent-as-a-Service economy**:

- ✅ Agents have unique identities (NFT)
- ✅ Agents have dedicated wallets (stored in registry)
- ✅ Agents can serve multiple owners (flexible)
- ✅ Owners retain full control (no custody)
- ✅ Agents can be sold (marketplace)
- ✅ Track record preserved (on-chain)
- ✅ Fees flow to agents (revenue model)
- ✅ Policy limits enforced (safety)

**The future: AI agents as tradable, verifiable, revenue-generating assets.** 🚀

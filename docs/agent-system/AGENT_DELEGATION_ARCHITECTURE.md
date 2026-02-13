# Agent Delegation Architecture

## Overview
This document describes how agents use dedicated wallets to execute orders on behalf of their owners.

## Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AGENT DELEGATION SYSTEM                         │
└─────────────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  Owner Wallet    │  (Primary Trader)
│ 0x27dD...7cB7    │
└────────┬─────────┘
         │
         │ 1. Owns Agent NFT
         │ 2. Sets Policy
         │ 3. Authorizes Agent Wallet
         │ 4. Funds BalanceManager
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        IdentityRegistry (ERC-721)                       │
│  Agent NFT Token ID: 1                                                  │
│  Owner: 0x27dD...7cB7                                                   │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ Agent Identity
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           PolicyFactory                                 │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │ Policy for Agent #1:                                          │     │
│  │ - Owner: 0x27dD...7cB7                                        │     │
│  │ - Template: "moderate"                                        │     │
│  │ - Max Order Size: 10 ETH                                      │     │
│  │ - Daily Volume Limit: 100 ETH                                 │     │
│  │ - Allowed Actions: limitOrders, cancelOrders, etc.            │     │
│  │ - Enabled: true                                               │     │
│  └───────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
         │
         │ Policy Controls
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           AgentRouter                                   │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │ Delegation Mapping:                                           │     │
│  │ authorizedExecutors[1][0xABCD...] = true                      │     │
│  │                                                               │     │
│  │ Authorization Check:                                          │     │
│  │ 1. Is msg.sender the owner? OR                                │     │
│  │ 2. Is msg.sender an authorized executor?                      │     │
│  └───────────────────────────────────────────────────────────────┘     │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ Authorized to Execute
         │
         ▼
┌──────────────────┐
│  Agent Wallet    │  (Dedicated AI Wallet)
│ 0xABCD...EFGH    │
└────────┬─────────┘
         │
         │ Calls: executeLimitOrder(agentTokenId=1, ...)
         │ msg.sender = 0xABCD...EFGH (agent wallet)
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           AgentRouter                                   │
│                                                                         │
│  executeLimitOrder(agentTokenId, pool, price, qty, side, ...)          │
│                                                                         │
│  Step 1: Get owner from IdentityRegistry                               │
│          owner = identityRegistry.ownerOf(1)  // 0x27dD...7cB7         │
│                                                                         │
│  Step 2: Check authorization                                            │
│          require(msg.sender == owner ||                                 │
│                  authorizedExecutors[1][msg.sender])  ✓                 │
│                                                                         │
│  Step 3: Get & validate policy                                          │
│          policy = policyFactory.getPolicy(owner, 1)                     │
│          require(policy.enabled)  ✓                                     │
│          require(qty <= policy.maxOrderSize)  ✓                         │
│          require(dailyVolume <= policy.dailyVolumeLimit)  ✓             │
│                                                                         │
│  Step 4: Place order on behalf of owner                                │
│          orderBook.placeOrder(price, qty, side, owner, ...)            │
│          //                                    ^^^^^ owner, not agent   │
│                                                                         │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ placeOrder(owner=0x27dD...7cB7, ...)
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           OrderBook                                     │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │ Order #123:                                                   │     │
│  │ - Owner: 0x27dD...7cB7  ← Primary trader, NOT agent wallet    │     │
│  │ - Quantity: 0.003 WETH                                        │     │
│  │ - Price: 2000 IDRX                                            │     │
│  │ - Side: BUY                                                   │     │
│  └───────────────────────────────────────────────────────────────┘     │
│                                                                         │
│  Deducts balance from: 0x27dD...7cB7 (owner's BalanceManager account)  │
└─────────────────────────────────────────────────────────────────────────┘
         │
         │ Deducts from owner balance
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         BalanceManager                                  │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │ Account: 0x27dD...7cB7                                        │     │
│  │ - IDRX Balance: 50,000 → 49,400 (after order)                │     │
│  │ - WETH Balance: 0                                             │     │
│  └───────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Key Points

### 1. Owner Preservation
- **Agent wallet** (`0xABCD...EFGH`) executes transactions
- **Owner wallet** (`0x27dD...7cB7`) owns all orders and balances
- All on-chain data shows owner, not agent

### 2. Authorization Flow
```
Owner → authorizeExecutor(agentTokenId, agentWallet)
     → AgentRouter.authorizedExecutors[1][agentWallet] = true
```

### 3. Execution Flow
```
Agent Wallet calls AgentRouter.executeLimitOrder(...)
  → Check: Is agent wallet authorized? ✓
  → Check: Does policy allow this? ✓
  → OrderBook.placeOrder(owner=owner, ...)
  → BalanceManager deducts from owner's account
```

### 4. Security Model
```
┌────────────────────────────────────────────┐
│  Layer 1: Ownership                        │
│  - Only NFT owner can authorize executors  │
└────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────┐
│  Layer 2: Authorization                    │
│  - Only authorized executors can act       │
└────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────┐
│  Layer 3: Policy Enforcement               │
│  - Orders must comply with policy limits   │
└────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────┐
│  Layer 4: Balance Manager                  │
│  - Orders must have sufficient balance     │
└────────────────────────────────────────────┘
```

## Flow 1: Setup Flow (One-Time Initialization)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          SETUP FLOW                                     │
│                    (Owner performs these steps)                         │
└─────────────────────────────────────────────────────────────────────────┘

STEP 1: Mint Agent NFT
┌────────────────┐
│  Owner Wallet  │
└───────┬────────┘
        │
        │ tx: identityRegistry.mint()
        │ msg.sender: 0x27dD...7cB7
        │ gas paid by: Owner
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      IdentityRegistry (ERC-721)                         │
│                                                                         │
│  mint() → agentTokenId = 1                                              │
│  ownerOf(1) = 0x27dD...7cB7                                             │
│                                                                         │
│  emit Transfer(address(0), 0x27dD...7cB7, 1)                            │
└─────────────────────────────────────────────────────────────────────────┘

Result: ✓ Agent NFT #1 owned by 0x27dD...7cB7


STEP 2: Install Policy
┌────────────────┐
│  Owner Wallet  │
└───────┬────────┘
        │
        │ tx: policyFactory.installAgentFromTemplate(
        │       agentTokenId: 1,
        │       template: "moderate",
        │       customization: {
        │         maxOrderSize: 10 ether,
        │         dailyVolumeLimit: 100 ether,
        │         expiryTimestamp: 0,
        │         whitelistedTokens: []
        │       }
        │     )
        │ msg.sender: 0x27dD...7cB7
        │ gas paid by: Owner
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         PolicyFactory                                   │
│                                                                         │
│  installAgentFromTemplate()                                             │
│    1. require(identityRegistry.ownerOf(1) == msg.sender) ✓              │
│    2. Load template "moderate"                                          │
│    3. Apply customization overrides                                     │
│    4. Store policy:                                                     │
│       policies[0x27dD...7cB7][1] = Policy({                             │
│         enabled: true,                                                  │
│         template: "moderate",                                           │
│         maxOrderSize: 10 ether,                                         │
│         dailyVolumeLimit: 100 ether,                                    │
│         allowLimitOrders: true,                                         │
│         allowPlaceLimitOrder: true,                                     │
│         allowCancelOrder: true,                                         │
│         ...                                                             │
│       })                                                                │
│                                                                         │
│  emit AgentInstalled(0x27dD...7cB7, 1, "moderate", timestamp)           │
└─────────────────────────────────────────────────────────────────────────┘

Result: ✓ Policy installed for Agent #1


STEP 3: Deposit Funds to BalanceManager
┌────────────────┐
│  Owner Wallet  │
└───────┬────────┘
        │
        │ tx 1: IDRX.approve(balanceManager, 50000)
        │ msg.sender: 0x27dD...7cB7
        │ gas paid by: Owner
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            IDRX Token                                   │
│  allowance[0x27dD...7cB7][balanceManager] = 50000                       │
└─────────────────────────────────────────────────────────────────────────┘
        │
        │ tx 2: balanceManager.depositLocal(IDRX, 50000, 0x27dD...7cB7)
        │ msg.sender: 0x27dD...7cB7
        │ gas paid by: Owner
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        BalanceManager                                   │
│                                                                         │
│  depositLocal(IDRX, 50000, 0x27dD...7cB7)                               │
│    1. IERC20(IDRX).transferFrom(msg.sender, this, 50000) ✓              │
│    2. balances[0x27dD...7cB7][IDRX] += 50000                            │
│                                                                         │
│  emit Deposit(0x27dD...7cB7, IDRX, 50000)                               │
└─────────────────────────────────────────────────────────────────────────┘

Result: ✓ Owner has 50,000 IDRX in BalanceManager


STEP 4: Create & Fund Agent Wallet
┌────────────────┐
│  Owner Wallet  │
└───────┬────────┘
        │
        │ Off-chain: Generate new wallet
        │ agentWallet = 0xABCD...EFGH
        │ privateKey = 0x1234... (stored securely by AI agent)
        │
        │ tx: payable(0xABCD...EFGH).transfer(0.1 ether)
        │ msg.sender: 0x27dD...7cB7
        │ gas paid by: Owner
        ▼
┌────────────────┐
│  Agent Wallet  │
│ 0xABCD...EFGH  │
│                │
│ Balance:       │
│ 0.1 ETH (gas)  │
└────────────────┘

Result: ✓ Agent wallet funded with gas


STEP 5: Authorize Agent Wallet
┌────────────────┐
│  Owner Wallet  │
└───────┬────────┘
        │
        │ tx: agentRouter.authorizeExecutor(
        │       agentTokenId: 1,
        │       executor: 0xABCD...EFGH
        │     )
        │ msg.sender: 0x27dD...7cB7
        │ gas paid by: Owner
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                                                                         │
│  authorizeExecutor(1, 0xABCD...EFGH)                                    │
│    1. owner = identityRegistry.ownerOf(1)  // 0x27dD...7cB7            │
│    2. require(msg.sender == owner) ✓                                    │
│    3. require(executor != address(0)) ✓                                 │
│    4. require(!authorizedExecutors[1][0xABCD...EFGH]) ✓                 │
│    5. authorizedExecutors[1][0xABCD...EFGH] = true                      │
│                                                                         │
│  emit ExecutorAuthorized(0x27dD...7cB7, 1, 0xABCD...EFGH, timestamp)   │
└─────────────────────────────────────────────────────────────────────────┘

Result: ✓ Agent wallet 0xABCD...EFGH authorized to execute for Agent #1

┌─────────────────────────────────────────────────────────────────────────┐
│                      SETUP COMPLETE                                     │
│                                                                         │
│  ✓ Agent NFT #1 minted and owned by 0x27dD...7cB7                      │
│  ✓ Policy installed with 10 ETH max order, 100 ETH daily limit         │
│  ✓ Owner deposited 50,000 IDRX to BalanceManager                       │
│  ✓ Agent wallet 0xABCD...EFGH created and funded with gas              │
│  ✓ Agent wallet authorized to execute on behalf of owner               │
│                                                                         │
│  Ready to place orders!                                                │
└─────────────────────────────────────────────────────────────────────────┘
```

## Flow 2: Place Order Flow (Ongoing Operations)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        PLACE ORDER FLOW                                 │
│               (Agent wallet executes on behalf of owner)                │
└─────────────────────────────────────────────────────────────────────────┘

STEP 1: Agent Wallet Submits Transaction
┌────────────────┐
│  Agent Wallet  │  (AI agent's dedicated wallet)
│ 0xABCD...EFGH  │
└───────┬────────┘
        │
        │ tx: agentRouter.executeLimitOrder(
        │       agentTokenId: 1,
        │       pool: {
        │         baseCurrency: WETH,
        │         quoteCurrency: IDRX,
        │         orderBook: 0x629A...DEA1
        │       },
        │       price: 200000,        // 2000 IDRX (2 decimals)
        │       quantity: 3000000000000000,  // 0.003 WETH
        │       side: BUY,
        │       timeInForce: GTC,
        │       autoRepay: false,
        │       autoBorrow: false
        │     )
        │ msg.sender: 0xABCD...EFGH
        │ gas paid by: Agent Wallet
        ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                    executeLimitOrder(...)                               │
└─────────────────────────────────────────────────────────────────────────┘


STEP 2: Get Owner from Agent NFT
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                                                                         │
│  Line 265: address owner = identityRegistry.ownerOf(agentTokenId);      │
│            owner = identityRegistry.ownerOf(1)                          │
│            // Query IdentityRegistry                                    │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      IdentityRegistry                                   │
│  ownerOf(1) returns 0x27dD...7cB7                                       │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ owner = 0x27dD...7cB7
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│  owner = 0x27dD...7cB7  ✓                                               │
└─────────────────────────────────────────────────────────────────────────┘


STEP 3: Load & Validate Policy
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                                                                         │
│  Line 266: PolicyFactory.Policy memory policy =                         │
│              policyFactory.getPolicy(owner, agentTokenId);              │
│            // Query PolicyFactory                                       │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         PolicyFactory                                   │
│  getPolicy(0x27dD...7cB7, 1) returns:                                   │
│    Policy({                                                             │
│      enabled: true,                                                     │
│      maxOrderSize: 10 ether,                                            │
│      dailyVolumeLimit: 100 ether,                                       │
│      allowLimitOrders: true,                                            │
│      allowPlaceLimitOrder: true,                                        │
│      expiryTimestamp: 0 (no expiry),                                    │
│      ...                                                                │
│    })                                                                   │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ policy loaded
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                                                                         │
│  Line 269: require(policy.enabled, "Agent disabled");                   │
│            require(true) ✓                                              │
│                                                                         │
│  Line 270: require(block.timestamp < policy.expiryTimestamp,            │
│                    "Agent expired");                                    │
│            require(now < 0) → require(false) → skip (no expiry) ✓       │
│                                                                         │
│  Line 279: require(policy.allowLimitOrders, "...");                     │
│            require(true) ✓                                              │
│                                                                         │
│  Line 280: require(policy.allowPlaceLimitOrder, "...");                 │
│            require(true) ✓                                              │
└─────────────────────────────────────────────────────────────────────────┘


STEP 4: Check Authorization
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                                                                         │
│  Line 273-276: require(                                                 │
│    msg.sender == owner ||                                               │
│    _isAuthorizedExecutor(agentTokenId, owner, msg.sender),              │
│    "Not authorized executor"                                            │
│  );                                                                     │
│                                                                         │
│  Check: msg.sender == owner?                                            │
│         0xABCD...EFGH == 0x27dD...7cB7?  → false                        │
│                                                                         │
│  Check: _isAuthorizedExecutor(1, 0x27dD...7cB7, 0xABCD...EFGH)?        │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                _isAuthorizedExecutor(1, owner, executor)                │
│                                                                         │
│  Line 842: if (executor == owner) return true;                          │
│            if (0xABCD...EFGH == 0x27dD...7cB7) → false                  │
│                                                                         │
│  Line 846: return authorizedExecutors[agentTokenId][executor];          │
│            return authorizedExecutors[1][0xABCD...EFGH];                │
│            return true  ✓                                               │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ Authorization check passed ✓
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│  require(false || true, "Not authorized executor")                      │
│  require(true) ✓                                                        │
└─────────────────────────────────────────────────────────────────────────┘


STEP 5: Enforce Order Limits
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│              _enforceLimitOrderPermissions(...)                         │
│                                                                         │
│  Check 1: Order size within limit?                                      │
│    quantity <= policy.maxOrderSize                                      │
│    0.003 WETH <= 10 WETH  ✓                                             │
│                                                                         │
│  Check 2: Daily volume within limit?                                    │
│    today = block.timestamp / 1 days                                     │
│    currentVolume = dailyVolumes[1][today]                               │
│    newVolume = currentVolume + 0.003 WETH                               │
│    newVolume <= policy.dailyVolumeLimit                                 │
│    0.003 WETH <= 100 WETH  ✓                                            │
│                                                                         │
│  Check 3: Token whitelisted? (if whitelist exists)                      │
│    whitelistedTokens.length == 0 → skip check ✓                         │
│                                                                         │
│  All checks passed ✓                                                    │
└─────────────────────────────────────────────────────────────────────────┘


STEP 6: Place Order on OrderBook (Owner as Order Owner)
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                                                                         │
│  Line 298-306: orderId = orderBook.placeOrder(                          │
│    price: 200000,                                                       │
│    quantity: 3000000000000000,                                          │
│    side: BUY,                                                           │
│    owner: 0x27dD...7cB7,    ← OWNER, not agent wallet!                 │
│    timeInForce: GTC,                                                    │
│    autoRepay: false,                                                    │
│    autoBorrow: false                                                    │
│  );                                                                     │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ Call OrderBook with owner parameter
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      OrderBook (WETH/IDRX)                              │
│            placeOrder(price, qty, side, owner, ...)                     │
│                                                                         │
│  Verify caller is authorized router:                                    │
│    require(msg.sender == router, "UnauthorizedRouter")                  │
│    require(0x1c2A...c7C0 == 0x1c2A...c7C0) ✓                            │
│    // AgentRouter is authorized!                                        │
│                                                                         │
│  Calculate quote amount needed:                                         │
│    quoteAmount = price * quantity / priceScale                          │
│    quoteAmount = 200000 * 0.003e18 / 1e18 (after decimal conversion)   │
│    quoteAmount = 600 IDRX (with 2 decimals)                             │
│                                                                         │
│  Check minimum trade amount:                                            │
│    require(quoteAmount >= minTradeAmount, "OrderTooSmall")              │
│    require(600 >= 500) ✓                                                │
│                                                                         │
│  Create order:                                                          │
│    orderId = nextOrderId++  // orderId = 3                              │
│    orders[3] = Order({                                                  │
│      owner: 0x27dD...7cB7,    ← Primary trader, NOT agent!             │
│      price: 200000,                                                     │
│      quantity: 3000000000000000,                                        │
│      side: BUY,                                                         │
│      timeInForce: GTC,                                                  │
│      ...                                                                │
│    })                                                                   │
│                                                                         │
│  Call BalanceManager to lock funds:                                     │
│    balanceManager.lockForOrder(                                         │
│      owner: 0x27dD...7cB7,    ← Owner's account                        │
│      currency: IDRX,                                                    │
│      amount: 600                                                        │
│    )                                                                    │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        BalanceManager                                   │
│              lockForOrder(0x27dD...7cB7, IDRX, 600)                     │
│                                                                         │
│  Check balance:                                                         │
│    availableBalance = balances[0x27dD...7cB7][IDRX] - locked           │
│    require(availableBalance >= 600) ✓                                   │
│                                                                         │
│  Lock funds:                                                            │
│    lockedBalances[0x27dD...7cB7][IDRX] += 600                           │
│    // Owner's funds locked, not agent's!                                │
│                                                                         │
│  emit BalanceLocked(0x27dD...7cB7, IDRX, 600)                           │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ Funds locked ✓
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      OrderBook (WETH/IDRX)                              │
│  emit OrderPlaced(orderId: 3, owner: 0x27dD...7cB7, ...)                │
│  return orderId = 3                                                     │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ orderId = 3
         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│  orderId = 3  ✓                                                         │
└─────────────────────────────────────────────────────────────────────────┘


STEP 7: Update Tracking & Emit Event
┌─────────────────────────────────────────────────────────────────────────┐
│                         AgentRouter                                     │
│                                                                         │
│  Line 309: _updateTracking(owner, agentTokenId, quantity);              │
│    today = block.timestamp / 1 days                                     │
│    dailyVolumes[1][today] += 0.003 WETH                                 │
│    lastTradeTime[1] = block.timestamp                                   │
│                                                                         │
│  Line 311-322: emit AgentLimitOrderPlaced(                              │
│    owner: 0x27dD...7cB7,         ← Primary trader                      │
│    agentTokenId: 1,                                                     │
│    executor: 0xABCD...EFGH,      ← Agent wallet                        │
│    orderId: bytes32(3),                                                 │
│    tokenIn: IDRX,                                                       │
│    tokenOut: WETH,                                                      │
│    quantity: 3000000000000000,                                          │
│    price: 200000,                                                       │
│    isBuy: true,                                                         │
│    timestamp: block.timestamp                                           │
│  );                                                                     │
│                                                                         │
│  return orderId = 3                                                     │
└────────┬────────────────────────────────────────────────────────────────┘
         │
         │ Success! Return to agent wallet
         ▼
┌────────────────┐
│  Agent Wallet  │
│ 0xABCD...EFGH  │
└───────┬────────┘
        │
        │ Transaction successful!
        │ Order ID: 3
        │ Gas paid: ~0.001 ETH
        ▼

┌─────────────────────────────────────────────────────────────────────────┐
│                      ORDER PLACEMENT COMPLETE                           │
│                                                                         │
│  ✓ Agent wallet 0xABCD...EFGH executed transaction                     │
│  ✓ Owner 0x27dD...7cB7 owns the order                                  │
│  ✓ Owner's funds locked in BalanceManager (600 IDRX)                   │
│  ✓ Order ID 3 placed on WETH/IDRX OrderBook                            │
│  ✓ Policy limits enforced                                              │
│  ✓ Agent wallet only paid gas fees                                     │
│                                                                         │
│  Order Details:                                                         │
│    Owner: 0x27dD...7cB7 (primary trader)                               │
│    Executor: 0xABCD...EFGH (agent wallet)                              │
│    Side: BUY                                                            │
│    Quantity: 0.003 WETH                                                 │
│    Price: 2000 IDRX/WETH                                                │
│    Status: Open                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Comparison: Before vs After

### Before (Owner Direct Execution)
```
Owner Wallet → Router → OrderBook
   └─ Owner signs tx
   └─ Owner pays gas
   └─ Owner owns order
```

### After (Agent Delegated Execution)
```
Owner Wallet → AgentRouter.authorizeExecutor(agentWallet)
                    ↓
Agent Wallet → AgentRouter → OrderBook
   └─ Agent signs tx
   └─ Agent pays gas
   └─ Owner owns order ← Key difference!
```

## Gas & Funding

### Owner Wallet Needs:
- Funds in BalanceManager (for trading)
- Gas for authorization transaction (one-time)
- Gas for policy updates (occasional)

### Agent Wallet Needs:
- Gas for executing orders (frequent)
- NO trading funds needed
- NO BalanceManager deposits needed

### Funding Agent Wallet:
```solidity
// Owner sends gas to agent wallet
payable(agentWallet).transfer(0.1 ether);

// Or agent wallet funded separately
// (in production, this would be managed by the AI agent infrastructure)
```

## Revocation

### Owner can revoke agent access:
```solidity
agentRouter.revokeExecutor(agentTokenId: 1, executor: 0xABCD...EFGH);
```

### Or disable agent entirely:
```solidity
policyFactory.uninstallAgent(agentTokenId: 1);
```

## Events

### Authorization Events:
```solidity
event ExecutorAuthorized(owner, agentTokenId, executor, timestamp);
event ExecutorRevoked(owner, agentTokenId, executor, timestamp);
```

### Execution Events:
```solidity
event AgentLimitOrderPlaced(
    owner,           // 0x27dD...7cB7 (primary trader)
    agentTokenId,    // 1
    executor,        // 0xABCD...EFGH (agent wallet)
    orderId,         // 123
    ...
);
```

## Deployment Plan

### Phase 1: Upgrade AgentRouter ✓ (Code ready)
- Add `authorizedExecutors` mapping
- Add `authorizeExecutor()` function
- Add `revokeExecutor()` function
- Add `isExecutorAuthorized()` view function
- Update `_isAuthorizedExecutor()` logic

### Phase 2: Deploy to Base Sepolia
1. Deploy new AgentRouter
2. Update PoolManager to authorize new AgentRouter on OrderBook
3. Update deployment JSON

### Phase 3: Re-authorize Agent
1. Owner installs policy (if needed)
2. Owner authorizes agent wallet

### Phase 4: Test
1. Run TestAgentWithDedicatedWallet.s.sol
2. Verify order shows owner, not agent
3. Verify balance deducted from owner

## Security Considerations

### ✅ Protected Against:
- Unauthorized executors (requires owner authorization)
- Policy violations (enforced before execution)
- Overdrawing balance (BalanceManager checks)
- Expired policies (timestamp check)
- Disabled agents (enabled flag check)

### ⚠️ Owner Responsibilities:
- Securely manage agent wallet private key
- Monitor agent behavior
- Revoke access if compromised
- Set appropriate policy limits

### 🔒 Smart Contract Guarantees:
- Owner always owns orders
- Owner's funds always used
- Policy limits always enforced
- Only authorized executors can act

## Summary of Key Points

### Setup Flow (5 Steps, One-Time)
1. **Mint Agent NFT** - Owner gets ERC-721 agent token
2. **Install Policy** - Owner sets limits (max order size, daily volume, etc.)
3. **Deposit Funds** - Owner deposits trading capital to BalanceManager
4. **Create Agent Wallet** - Generate dedicated wallet for AI agent
5. **Authorize Agent** - Owner authorizes agent wallet to execute on their behalf

### Place Order Flow (7 Steps, Per Order)
1. **Agent Submits Transaction** - Agent wallet calls `executeLimitOrder()` with order details
2. **Get Owner** - AgentRouter looks up owner from agent NFT: `identityRegistry.ownerOf(agentTokenId)`
3. **Load Policy** - AgentRouter loads policy from PolicyFactory: `getPolicy(owner, agentTokenId)`
4. **Check Authorization** - Verify agent wallet is authorized: `authorizedExecutors[agentTokenId][agentWallet] == true`
5. **Enforce Limits** - Check order size ≤ maxOrderSize, daily volume ≤ dailyVolumeLimit
6. **Place Order** - OrderBook creates order with `owner` parameter (NOT `msg.sender`)
7. **Lock Funds** - BalanceManager locks owner's funds for the order

### Critical Design Properties

| Aspect | Value | Notes |
|--------|-------|-------|
| **Order Owner** | Primary Trader (0x27dD...7cB7) | NEVER agent wallet |
| **Funds Source** | Owner's BalanceManager account | Agent doesn't need trading capital |
| **Gas Payer** | Agent Wallet (0xABCD...EFGH) | Agent needs gas only |
| **Authorization** | Owner must explicitly authorize | Can revoke anytime |
| **Policy Enforcement** | Every order checked | No bypass possible |
| **msg.sender in placeOrder()** | AgentRouter (0x1c2A...c7C0) | Must be authorized router |
| **owner param in placeOrder()** | Primary Trader (0x27dD...7cB7) | Preserved from agent call |

### Transaction Count & Gas Costs

**Setup Phase (One-Time):**
- 5 transactions (all signed by owner)
- Estimated total gas: ~0.015 ETH on Base Sepolia
- Plus: 0.1 ETH to fund agent wallet (refillable)

**Operation Phase (Per Order):**
- 1 transaction (signed by agent wallet)
- Estimated gas per order: ~0.001 ETH
- Owner pays: 0 gas ✓
- Agent pays: gas only ✓

### On-Chain Data Verification

To verify owner preservation on-chain:
```solidity
// Check order owner
Order memory order = orderBook.getOrder(3);
assert(order.owner == 0x27dD...7cB7);  // Owner, not agent!

// Check event
AgentLimitOrderPlaced event:
  - owner: 0x27dD...7cB7 (primary trader)
  - executor: 0xABCD...EFGH (agent wallet)
  - Shows both addresses clearly!

// Check balance deduction
uint256 balance = balanceManager.getBalance(0x27dD...7cB7, IDRX);
// Owner's balance reduced, not agent's
```

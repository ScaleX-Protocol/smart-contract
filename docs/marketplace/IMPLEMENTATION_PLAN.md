# Agent Marketplace Implementation Plan

**Goal:** Build a platform where developers create AI trading agents and users subscribe to copy their strategies.

**Model:**
- Developer creates AI trading agent (off-chain strategy + on-chain identity)
- Users subscribe by authorizing developer's executor + installing their own policy
- One executor trades for multiple users, each with different risk policies
- Subscriptions/payments/performance tracking handled off-chain
- Smart contracts enforce user-level policies

---

## Phase 1: Verification & Testing

### 1.1 Verify Current Smart Contracts Support Marketplace Model

**Goal:** Confirm no smart contract changes needed

**Tasks:**
- [ ] Audit `IdentityRegistry.sol` - verify multiple users can register agents
- [ ] Audit `PolicyFactory.sol` - verify each user can install their own policy
- [ ] Audit `AgentRouter.sol` - verify:
  - Multiple users can authorize same executor address
  - Policy enforcement is per-user (not per-executor)
  - `_isAuthorizedExecutor()` correctly validates
  - No conflicts when one executor trades for multiple agents
- [ ] Review all events - confirm tracking capabilities
- [ ] Check BalanceManager - verify fund isolation per user

**Expected Outcome:** ✅ Current contracts already support marketplace model

**Files to Review:**
- `/Users/renaka/gtx/clob-dex/src/ai-agents/registries/IdentityRegistryUpgradeable.sol`
- `/Users/renaka/gtx/clob-dex/src/ai-agents/PolicyFactory.sol`
- `/Users/renaka/gtx/clob-dex/src/ai-agents/AgentRouter.sol`
- `/Users/renaka/gtx/clob-dex/src/core/BalanceManager.sol`

---

### 1.2 Write Marketplace Model Test

**Goal:** Prove one executor can trade for multiple users with different policies

**Create:** `test/marketplace/AgentMarketplace.t.sol`

**Test Scenario:**
```solidity
function testOneExecutorMultipleUsers() public {
    // Setup
    address developer = address(0xDEV);
    address executor = address(0xEXEC);
    address alice = address(0xALICE);
    address bob = address(0xBOB);

    // Developer registers strategy agent (no policy)
    vm.prank(developer);
    uint256 strategyAgentId = identityRegistry.register();
    // strategyAgentId = 500

    // Alice subscribes with conservative policy
    vm.prank(alice);
    uint256 aliceAgentId = identityRegistry.register(); // 100

    vm.prank(alice);
    policyFactory.installAgentFromTemplate(
        aliceAgentId,
        "conservative",
        PolicyCustomization({
            maxOrderSize: 1000e6, // 1000 IDRX
            dailyVolumeLimit: 5000e6,
            expiryTimestamp: 0,
            whitelistedTokens: new address[](0)
        })
    );

    vm.prank(alice);
    agentRouter.authorizeExecutor(aliceAgentId, executor);

    // Alice deposits funds
    vm.prank(alice);
    balanceManager.deposit(IDRX, 10000e6);

    // Bob subscribes with aggressive policy
    vm.prank(bob);
    uint256 bobAgentId = identityRegistry.register(); // 200

    vm.prank(bob);
    policyFactory.installAgentFromTemplate(
        bobAgentId,
        "aggressive",
        PolicyCustomization({
            maxOrderSize: 10000e6, // 10x Alice
            dailyVolumeLimit: 100000e6,
            expiryTimestamp: 0,
            whitelistedTokens: new address[](0)
        })
    );

    vm.prank(bob);
    agentRouter.authorizeExecutor(bobAgentId, executor);

    vm.prank(bob);
    balanceManager.deposit(IDRX, 50000e6);

    // Executor tries to place 5000 IDRX order for both
    vm.startPrank(executor);

    // For Alice - should be limited by conservative policy
    uint48 aliceOrderId = agentRouter.placeLimitOrder(
        aliceAgentId,
        address(orderBook),
        WETH,
        IDRX,
        300000, // price
        5000e6, // quantity - exceeds Alice's limit!
        true,
        block.timestamp + 1 days
    );

    // Verify Alice's order was capped at 1000 IDRX
    // (or rejected, depending on policy enforcement)

    // For Bob - should succeed with full amount
    uint48 bobOrderId = agentRouter.placeLimitOrder(
        bobAgentId,
        address(orderBook),
        WETH,
        IDRX,
        300000,
        5000e6, // within Bob's 10000 limit
        true,
        block.timestamp + 1 days
    );

    vm.stopPrank();

    // Verify both orders tracked with correct agentTokenId
    // Verify Alice's order limited by her policy
    // Verify Bob's order allowed by his policy
}
```

**Success Criteria:**
- ✅ One executor can trade for multiple users
- ✅ Each user's policy is enforced correctly
- ✅ Orders tracked with correct agentTokenId
- ✅ Funds isolated per user

---

## Phase 2: Architecture & Design

### 2.1 Database Schema Design

**Create:** `docs/marketplace/DATABASE_SCHEMA.md`

**Tables:**

```sql
-- Developer strategies listed on marketplace
CREATE TABLE strategies (
    id SERIAL PRIMARY KEY,
    agent_token_id BIGINT NOT NULL UNIQUE,
    developer_address VARCHAR(42) NOT NULL,
    executor_address VARCHAR(42) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    strategy_type VARCHAR(50), -- 'market_making', 'arbitrage', 'trend_following'
    risk_category VARCHAR(20), -- 'conservative', 'moderate', 'aggressive'
    subscription_fee_monthly DECIMAL(20, 6), -- in IDRX
    performance_fee_bps INTEGER, -- basis points (e.g., 2000 = 20%)
    min_subscription_amount DECIMAL(20, 6),
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- User subscriptions to strategies
CREATE TABLE subscriptions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    user_wallet_address VARCHAR(42) NOT NULL,
    user_agent_id BIGINT NOT NULL,
    strategy_id INTEGER REFERENCES strategies(id),
    strategy_agent_id BIGINT NOT NULL,
    policy_template VARCHAR(50), -- 'conservative', 'aggressive', etc.
    deposited_amount DECIMAL(20, 6),
    active BOOLEAN DEFAULT true,
    paid_until TIMESTAMP,
    subscribed_at TIMESTAMP DEFAULT NOW(),
    unsubscribed_at TIMESTAMP
);

-- Performance metrics (computed from on-chain data)
CREATE TABLE performance_metrics (
    id SERIAL PRIMARY KEY,
    agent_token_id BIGINT NOT NULL,
    period VARCHAR(20), -- '7d', '30d', '90d', 'all_time'
    total_pnl DECIMAL(30, 6),
    total_volume DECIMAL(30, 6),
    total_trades INTEGER,
    winning_trades INTEGER,
    losing_trades INTEGER,
    win_rate DECIMAL(5, 2), -- percentage
    sharpe_ratio DECIMAL(10, 4),
    max_drawdown DECIMAL(10, 4),
    avg_trade_size DECIMAL(20, 6),
    computed_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(agent_token_id, period)
);

-- User accounts
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(42) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE,
    username VARCHAR(50),
    is_developer BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP
);

-- Payment history (off-chain payments)
CREATE TABLE payments (
    id SERIAL PRIMARY KEY,
    subscription_id INTEGER REFERENCES subscriptions(id),
    amount DECIMAL(20, 6),
    currency VARCHAR(10), -- 'IDRX', 'USD', etc.
    payment_type VARCHAR(20), -- 'subscription', 'performance_fee'
    payment_method VARCHAR(50), -- 'crypto', 'stripe', etc.
    status VARCHAR(20), -- 'pending', 'completed', 'failed'
    tx_hash VARCHAR(66), -- if crypto payment
    paid_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_strategies_developer ON strategies(developer_address);
CREATE INDEX idx_strategies_active ON strategies(active);
CREATE INDEX idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_strategy ON subscriptions(strategy_id);
CREATE INDEX idx_subscriptions_active ON subscriptions(active);
CREATE INDEX idx_performance_agent ON performance_metrics(agent_token_id);
```

---

### 2.2 API Endpoints Design

**Create:** `docs/marketplace/API_ENDPOINTS.md`

**Public Endpoints (No Auth):**

```
GET /api/marketplace/strategies
  Query params:
    - sort: 'performance' | 'subscribers' | 'newest'
    - risk: 'conservative' | 'moderate' | 'aggressive'
    - type: 'market_making' | 'arbitrage' | 'trend_following'
    - limit: number (default 20)
    - offset: number (default 0)
  Response:
    {
      success: true,
      data: [
        {
          agentTokenId: 500,
          developer: "0xDEV...",
          executor: "0xEXEC...",
          name: "WETH/IDRX Market Maker Pro",
          description: "...",
          riskCategory: "moderate",
          subscriptionFee: 100,
          performanceFee: 2000, // 20%
          subscribers: 15,
          performance: {
            return90d: 3.5, // %
            winRate: 65,
            sharpe: 1.8,
            volume90d: 500000
          }
        }
      ],
      pagination: { total: 50, limit: 20, offset: 0 }
    }

GET /api/marketplace/strategies/:agentTokenId
  Response:
    {
      success: true,
      data: {
        agentTokenId: 500,
        developer: "0xDEV...",
        executor: "0xEXEC...",
        name: "...",
        description: "...",
        strategyType: "market_making",
        riskCategory: "moderate",
        pricing: {
          subscriptionFee: 100,
          performanceFee: 2000,
          minSubscription: 5000
        },
        performance: {
          "7d": { return: 0.8, winRate: 70, volume: 50000 },
          "30d": { return: 2.1, winRate: 68, volume: 180000 },
          "90d": { return: 3.5, winRate: 65, volume: 500000 }
        },
        stats: {
          totalSubscribers: 15,
          totalVolumeTraded: 5000000,
          createdAt: "2025-11-15"
        }
      }
    }
```

**Authenticated Endpoints (Require JWT/Signature):**

```
POST /api/marketplace/subscribe
  Body:
    {
      strategyAgentId: 500,
      policyTemplate: "conservative",
      depositAmount: 10000
    }
  Response:
    {
      success: true,
      message: "Subscription initiated",
      steps: [
        {
          step: 1,
          action: "Register your agent",
          tx: { to: "0xIDENTITY_REGISTRY", data: "0x..." }
        },
        {
          step: 2,
          action: "Install policy",
          tx: { to: "0xPOLICY_FACTORY", data: "0x..." }
        },
        {
          step: 3,
          action: "Authorize executor",
          tx: { to: "0xAGENT_ROUTER", data: "0x...",
               params: { executor: "0xEXEC..." } }
        },
        {
          step: 4,
          action: "Deposit funds",
          tx: { to: "0xBALANCE_MANAGER", data: "0x..." }
        }
      ],
      subscriptionId: 123
    }

GET /api/marketplace/my-subscriptions
  Response:
    {
      success: true,
      data: [
        {
          subscriptionId: 123,
          strategy: {
            agentTokenId: 500,
            name: "WETH/IDRX Market Maker Pro"
          },
          myAgentId: 100,
          policyTemplate: "conservative",
          depositedAmount: 10000,
          currentPnL: 150, // +1.5%
          subscribedAt: "2026-01-15",
          paidUntil: "2026-02-15",
          active: true
        }
      ]
    }

DELETE /api/marketplace/subscriptions/:id
  Response:
    {
      success: true,
      message: "Subscription cancelled",
      optional_tx: {
        action: "Revoke executor authorization",
        tx: { to: "0xAGENT_ROUTER", data: "0x..." }
      }
    }
```

**Developer Endpoints:**

```
POST /api/marketplace/strategies
  Body:
    {
      agentTokenId: 500,
      executorAddress: "0xEXEC...",
      name: "WETH/IDRX Market Maker Pro",
      description: "...",
      strategyType: "market_making",
      riskCategory: "moderate",
      subscriptionFee: 100,
      performanceFee: 2000,
      minSubscription: 5000
    }
  Response:
    {
      success: true,
      strategyId: 15,
      status: "pending_approval" // or "live" if auto-approved
    }

GET /api/marketplace/my-strategy
  Response:
    {
      success: true,
      data: {
        agentTokenId: 500,
        name: "...",
        subscribers: 15,
        totalAUM: 750000, // Assets under management
        revenue: {
          thisMonth: 1200,
          lastMonth: 950,
          allTime: 15000
        },
        activeSubscribers: [
          {
            userAgentId: 100,
            depositedAmount: 10000,
            subscribedAt: "2026-01-15"
          }
        ]
      }
    }
```

**Internal Endpoints (For Trading Service):**

```
GET /api/internal/active-subscribers/:strategyAgentId
  Auth: API key
  Response:
    {
      success: true,
      data: [
        {
          userAgentId: 100,
          policyTemplate: "conservative",
          depositedAmount: 10000,
          paidUntil: "2026-02-15"
        },
        {
          userAgentId: 200,
          policyTemplate: "aggressive",
          depositedAmount: 50000,
          paidUntil: "2026-02-20"
        }
      ]
    }
```

---

### 2.3 User Flow Documentation

**Create:** `docs/marketplace/USER_FLOW.md`

**User Journey:**

1. **Browse Marketplace**
   - View list of available strategies
   - Filter by risk, type, performance
   - Sort by returns, subscribers, etc.

2. **View Strategy Details**
   - Performance charts (7d, 30d, 90d)
   - Win rate, Sharpe ratio, max drawdown
   - Pricing (subscription + performance fee)
   - Developer info
   - Current subscribers count
   - Historical trades (if public)

3. **Subscribe**
   - Click "Subscribe" button
   - Select policy template (conservative/moderate/aggressive)
   - Or customize policy parameters
   - Enter deposit amount
   - Review pricing: subscription fee + performance fee
   - Confirm subscription (off-chain payment)

4. **On-Chain Setup (Guided)**
   - **Step 1:** Approve transaction to register agent
     - User signs: `IdentityRegistry.register()`
     - Receives agent NFT (e.g., Agent #100)

   - **Step 2:** Approve transaction to install policy
     - User signs: `PolicyFactory.installAgentFromTemplate(100, "conservative", ...)`
     - Policy installed on user's agent

   - **Step 3:** Approve transaction to authorize executor
     - User signs: `AgentRouter.authorizeExecutor(100, 0xDEV_EXECUTOR)`
     - Developer's executor can now trade for user

   - **Step 4:** Approve transaction to deposit funds
     - User signs: `BalanceManager.deposit(IDRX, 10000)`
     - Funds available for trading

5. **Monitor Performance**
   - View personal dashboard
   - See P&L, trades executed
   - Compare vs strategy's overall performance
   - View fees paid

6. **Unsubscribe**
   - Cancel subscription (stops payment)
   - Optionally revoke executor authorization
   - Withdraw remaining funds

**Error Handling:**
- Transaction failure at any step → retry or cancel
- Insufficient funds → prompt to add funds
- Executor already authorized → skip step
- Agent already registered → use existing agent

---

### 2.4 Developer Flow Documentation

**Create:** `docs/marketplace/DEVELOPER_FLOW.md`

**Developer Journey:**

1. **Build & Test Strategy**
   - Develop AI trading strategy (off-chain)
   - Register agent on-chain: `IdentityRegistry.register()` → Agent #500
   - Trade with own funds to build track record
   - Accumulate performance history (90+ days recommended)

2. **Prepare for Launch**
   - Create executor wallet (dedicated address)
   - Document strategy:
     - Name, description
     - Strategy type (market making, arbitrage, etc.)
     - Risk category
     - Target markets
   - Set pricing:
     - Monthly subscription fee
     - Performance fee (% of profits)
     - Minimum subscription amount

3. **Submit to Marketplace**
   - Fill application form on platform
   - Provide:
     - Agent token ID (500)
     - Executor address
     - Strategy metadata
     - Pricing
   - Submit for review (if manual approval required)

4. **Go Live**
   - Strategy appears on marketplace
   - Users can browse and subscribe
   - Monitor subscriber list via API

5. **Manage Subscribers**
   - Query active subscribers: `GET /api/internal/active-subscribers/500`
   - Get list of user agent IDs to trade for
   - Execute trades for all active subscribers
   - Monitor AUM (assets under management)

6. **Trading Service Implementation**
   ```javascript
   // Example trading service
   async function runStrategy() {
     // 1. Get active subscribers
     const { data } = await fetch('/api/internal/active-subscribers/500');
     const subscribers = data; // [{ userAgentId: 100 }, { userAgentId: 200 }]

     // 2. Analyze market
     const signal = await analyzeMarket();

     // 3. If trade signal, execute for all
     if (signal.shouldTrade) {
       for (const sub of subscribers) {
         await agentRouter.placeLimitOrder(
           sub.userAgentId,
           signal.baseToken,
           signal.quoteToken,
           signal.price,
           signal.quantity,
           signal.isBuy,
           signal.expiry,
           { from: EXECUTOR_WALLET }
         );
       }
     }
   }

   // Run every 5 minutes
   setInterval(runStrategy, 5 * 60 * 1000);
   ```

7. **Revenue Tracking**
   - View revenue dashboard
   - Subscription fees collected
   - Performance fees from profitable subscribers
   - Total AUM

8. **Update Strategy**
   - Update metadata (description, pricing)
   - Cannot change agent ID or executor (linked on-chain)
   - Notify existing subscribers of changes

---

## Phase 3: Implementation

### 3.1 Backend API Development

**Tech Stack:**
- Node.js + Express/Fastify
- PostgreSQL for database
- Redis for caching
- JWT for authentication

**Create:** `marketplace-backend/` directory

**Structure:**
```
marketplace-backend/
├── src/
│   ├── routes/
│   │   ├── strategies.ts
│   │   ├── subscriptions.ts
│   │   ├── users.ts
│   │   └── internal.ts
│   ├── services/
│   │   ├── blockchain.ts      # Web3 interactions
│   │   ├── performance.ts     # Calculate metrics
│   │   └── payments.ts        # Handle payments
│   ├── database/
│   │   ├── schema.sql
│   │   └── migrations/
│   ├── middleware/
│   │   ├── auth.ts
│   │   └── validation.ts
│   └── index.ts
├── package.json
└── .env.example
```

**Tasks:**
- [ ] Set up Express/Fastify server
- [ ] Implement database schema & migrations
- [ ] Create API routes per design doc
- [ ] Add authentication middleware
- [ ] Integrate Web3 for on-chain data
- [ ] Implement performance metrics calculation
- [ ] Add Redis caching for performance
- [ ] Write API tests

---

### 3.2 Frontend Development

**Tech Stack:**
- Next.js 14 (React)
- TailwindCSS
- RainbowKit/Wagmi for Web3
- TanStack Query for data fetching

**Create:** `marketplace-frontend/` directory

**Pages:**
```
/                          # Home/Browse strategies
/strategies/:agentId       # Strategy details
/subscribe/:agentId        # Subscription flow
/dashboard                 # User dashboard
/my-subscriptions          # User's subscriptions
/developer/dashboard       # Developer dashboard
/developer/strategy/new    # Create new strategy
```

**Components:**
```
components/
├── StrategyCard.tsx       # Strategy listing card
├── StrategyDetails.tsx    # Full strategy details
├── PerformanceChart.tsx   # Performance visualization
├── SubscriptionFlow.tsx   # Multi-step subscription
├── PolicySelector.tsx     # Policy template selector
├── TransactionStatus.tsx  # Track tx approval
└── DeveloperDashboard.tsx # Developer stats
```

**Tasks:**
- [ ] Set up Next.js project
- [ ] Create layout and navigation
- [ ] Build marketplace listing page
- [ ] Build strategy details page
- [ ] Implement subscription flow with tx tracking
- [ ] Create user dashboard
- [ ] Create developer dashboard
- [ ] Add wallet connection (RainbowKit)
- [ ] Integrate smart contract interactions
- [ ] Add loading states & error handling
- [ ] Write component tests

---

### 3.3 Developer Trading Service Template

**Create:** `developer-trading-service-template/`

**Purpose:** Reference implementation for developers

**Structure:**
```
developer-trading-service/
├── src/
│   ├── strategy/
│   │   ├── analyze.ts         # Market analysis
│   │   └── signals.ts         # Trading signals
│   ├── execution/
│   │   ├── subscriber.ts      # Get subscribers
│   │   └── trade.ts           # Execute trades
│   ├── monitoring/
│   │   └── performance.ts     # Track performance
│   └── index.ts
├── config/
│   ├── strategy.json          # Strategy parameters
│   └── .env.example
└── README.md
```

**Example Implementation:**
```typescript
// src/index.ts
import { ethers } from 'ethers';
import { analyzeMarket } from './strategy/analyze';
import { getActiveSubscribers } from './execution/subscriber';
import { executeTradeForAgent } from './execution/trade';

const STRATEGY_AGENT_ID = 500;
const EXECUTOR_PRIVATE_KEY = process.env.EXECUTOR_PRIVATE_KEY;
const API_BASE_URL = process.env.API_BASE_URL;

async function main() {
  // 1. Get active subscribers
  const response = await fetch(
    `${API_BASE_URL}/api/internal/active-subscribers/${STRATEGY_AGENT_ID}`,
    {
      headers: { 'X-API-Key': process.env.API_KEY }
    }
  );
  const { data: subscribers } = await response.json();

  console.log(`Trading for ${subscribers.length} subscribers`);

  // 2. Analyze market
  const signal = await analyzeMarket();

  if (!signal.shouldTrade) {
    console.log('No trade signal, waiting...');
    return;
  }

  console.log(`Signal: ${signal.action} ${signal.quantity} @ ${signal.price}`);

  // 3. Execute for all subscribers
  const wallet = new ethers.Wallet(EXECUTOR_PRIVATE_KEY, provider);
  const agentRouter = new ethers.Contract(AGENT_ROUTER_ADDRESS, ABI, wallet);

  for (const subscriber of subscribers) {
    try {
      const tx = await agentRouter.placeLimitOrder(
        subscriber.userAgentId,
        signal.orderParams
      );
      console.log(`✓ Executed for agent ${subscriber.userAgentId}: ${tx.hash}`);
    } catch (error) {
      console.error(`✗ Failed for agent ${subscriber.userAgentId}:`, error);
    }
  }
}

// Run every 5 minutes
setInterval(main, 5 * 60 * 1000);
main(); // Run immediately
```

**Tasks:**
- [ ] Create service template structure
- [ ] Implement subscriber fetching
- [ ] Implement trade execution logic
- [ ] Add error handling & retries
- [ ] Add performance monitoring
- [ ] Write deployment guide
- [ ] Create Docker setup

---

## Phase 4: Testing & Deployment

### 4.1 Integration Testing

**Tasks:**
- [ ] Test complete user subscription flow (testnet)
- [ ] Test developer strategy publishing flow
- [ ] Test trading service with multiple subscribers
- [ ] Test policy enforcement (conservative vs aggressive)
- [ ] Test unsubscribe flow
- [ ] Load testing (100+ subscribers per strategy)

**Test Scenarios:**
1. Alice subscribes to strategy (conservative policy)
2. Bob subscribes to same strategy (aggressive policy)
3. Developer's service executes trade
4. Verify Alice's trade limited by policy
5. Verify Bob's trade succeeds with full amount
6. Verify both tracked correctly
7. Alice unsubscribes
8. Verify service no longer trades for Alice

---

### 4.2 Security Audit

**Tasks:**
- [ ] Smart contract audit (if any changes made)
- [ ] Backend API security review
- [ ] Authentication/authorization testing
- [ ] SQL injection testing
- [ ] XSS/CSRF protection verification
- [ ] Rate limiting implementation
- [ ] API key security
- [ ] Executor wallet security best practices

---

### 4.3 Deployment

**Testnet Deployment (Base Sepolia):**
- [ ] Deploy backend API to staging
- [ ] Deploy frontend to Vercel/staging
- [ ] Test with real users (alpha)
- [ ] Iterate based on feedback

**Mainnet Deployment:**
- [ ] Deploy backend API to production
- [ ] Deploy frontend to production
- [ ] Monitor smart contract interactions
- [ ] Set up alerting for errors
- [ ] Create runbooks for common issues

---

## Phase 5: Documentation & Launch

### 5.1 User Documentation

**Create:**
- [ ] User guide: How to subscribe
- [ ] User guide: Understanding policies
- [ ] User guide: Monitoring performance
- [ ] FAQ for users

### 5.2 Developer Documentation

**Create:**
- [ ] Developer guide: Publishing strategies
- [ ] Developer guide: Running trading service
- [ ] API documentation (OpenAPI/Swagger)
- [ ] Best practices for strategy development
- [ ] FAQ for developers

### 5.3 Marketing Materials

**Create:**
- [ ] Landing page copy
- [ ] Demo videos
- [ ] Case studies (successful strategies)
- [ ] Blog posts explaining marketplace

---

## Success Metrics

**Platform Metrics:**
- Number of strategies listed
- Number of active subscribers
- Total AUM (assets under management)
- Total trading volume
- Number of active developers

**Quality Metrics:**
- Average strategy performance
- User retention rate
- Developer retention rate
- Platform uptime
- Average subscription duration

**Revenue Metrics:**
- Platform fees collected
- Developer revenue
- User ROI

---

## Timeline Estimate

**Phase 1 (Verification & Testing):** 1 week
- Verify contracts ✓
- Write marketplace test ✓

**Phase 2 (Architecture & Design):** 2 weeks
- Database design ✓
- API design ✓
- Flow documentation ✓

**Phase 3 (Implementation):** 6-8 weeks
- Backend API: 3 weeks
- Frontend: 3 weeks
- Trading service template: 1 week
- Integration: 1 week

**Phase 4 (Testing & Deployment):** 2-3 weeks
- Testing: 1 week
- Security audit: 1 week
- Deployment: 1 week

**Phase 5 (Documentation & Launch):** 1 week
- Documentation ✓
- Marketing materials

**Total:** 12-15 weeks (3-4 months)

---

## Current Status

✅ Smart contracts already support marketplace model (no changes needed)
✅ Documentation updated with marketplace use case
⏳ Ready to start Phase 1: Verification & Testing

## Next Steps

1. **Immediate:** Run verification audit of current smart contracts
2. **This Week:** Write marketplace model test
3. **Next Week:** Finalize database schema and API design
4. **Month 1:** Begin backend API implementation
5. **Month 2:** Begin frontend implementation
6. **Month 3:** Integration testing and security audit
7. **Month 4:** Deploy to production

---

**Last Updated:** February 13, 2026
**Status:** Planning Phase
**Smart Contracts:** ✅ Ready (Base Sepolia 84532)

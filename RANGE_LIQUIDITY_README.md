# Range Liquidity Manager - Implementation Guide

## Overview

The Range Liquidity Manager enables users to provide concentrated liquidity to CLOB orderbooks similar to CLMM/DLMM protocols, but using real limit orders instead of virtual AMM liquidity.

## Files Created

```
src/core/
├── RangeLiquidityManager.sol              # Main implementation
├── interfaces/
│   └── IRangeLiquidityManager.sol         # Interface definition
├── storages/
│   └── RangeLiquidityManagerStorage.sol   # Storage layout (ERC-7201)
└── libraries/
    └── RangeLiquidityDistribution.sol     # Distribution calculations
```

## Core Features

### 1. Non-Transferable Position Tokens
- Positions are account-bound (cannot be transferred)
- Each user can only have 1 position per pool
- Simple ownership tracking via mappings

### 2. Distribution Strategies

**UNIFORM (50/50)**
- 50% capital in buy orders below current price
- 50% capital in sell orders above current price
- Equal distribution across all ticks

**BID_HEAVY (70/30)**
- 70% capital in buy orders (accumulation mode)
- 30% capital in sell orders
- Good for market making when expecting price to rise

**ASK_HEAVY (30/70)**
- 30% capital in buy orders
- 70% capital in sell orders (distribution mode)
- Good for market making when expecting price to fall

### 3. Position Management

#### Create Position
```solidity
function createPosition(PositionParams calldata params) external returns (uint256 positionId)

struct PositionParams {
    PoolKey poolKey;              // Which pool (e.g., BTC/USDC)
    Strategy strategy;            // UNIFORM, BID_HEAVY, or ASK_HEAVY
    uint128 lowerPrice;           // Range start (e.g., 70,000)
    uint128 upperPrice;           // Range end (e.g., 80,000)
    uint16 tickCount;             // Number of ticks (max 100)
    uint256 depositAmount;        // Total amount to deploy
    Currency depositCurrency;     // Which token to deposit
    bool autoRebalance;           // Enable bot rebalancing
    uint16 rebalanceThresholdBps; // Drift % to trigger rebalance (in bps)
}
```

#### Close Position
```solidity
function closePosition(uint256 positionId) external
```
- Cancels all unfilled orders
- Returns all capital (base + quote) to user
- Marks position as inactive

#### Rebalance Position
```solidity
function rebalancePosition(uint256 positionId) external
```
- Can be called by owner or authorized bot
- Cancels all orders
- Recalculates range around current price
- Places new orders with same strategy

### 4. Bot Authorization

Users can authorize a bot to rebalance on their behalf:

```solidity
function setAuthorizedBot(uint256 positionId, address bot) external
function revokeBot(uint256 positionId) external
```

**Bot rebalancing rules:**
- Only triggers if price drift >= `rebalanceThresholdBps`
- Must be enabled via `autoRebalance = true`
- Owner can always rebalance manually

### 5. View Functions

```solidity
// Get full position details
function getPosition(uint256 positionId) external view returns (RangePosition memory)

// Get position value breakdown
function getPositionValue(uint256 positionId) external view returns (PositionValue memory)

// Get all user positions
function getUserPositions(address user) external view returns (uint256[] memory)

// Check if position can be rebalanced
function canRebalance(uint256 positionId) external view returns (bool, uint256 driftBps)
```

## Usage Examples

### Example 1: Create UNIFORM Position

```solidity
// User wants to provide liquidity for BTC/USDC from 70k-80k
IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
    poolKey: PoolKey({
        baseCurrency: Currency.wrap(BTC_ADDRESS),
        quoteCurrency: Currency.wrap(USDC_ADDRESS)
    }),
    strategy: IRangeLiquidityManager.Strategy.UNIFORM,
    lowerPrice: 70_000_00000000,  // 70k with 8 decimals
    upperPrice: 80_000_00000000,  // 80k with 8 decimals
    tickCount: 20,                // 20 price levels
    depositAmount: 100_000e6,     // 100k USDC
    depositCurrency: Currency.wrap(USDC_ADDRESS),
    autoRebalance: true,
    rebalanceThresholdBps: 500    // 5% drift
});

uint256 positionId = rangeLiquidityManager.createPosition(params);

// Result:
// - 50k USDC worth of buy orders from 70k-75k (current price)
// - 50k USDC worth of sell orders from 75k-80k
// - 20 Post-Only orders placed across the range
```

### Example 2: BID_HEAVY for Accumulation

```solidity
// Market maker wants to accumulate BTC at lower prices
IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
    poolKey: btcUsdcPoolKey,
    strategy: IRangeLiquidityManager.Strategy.BID_HEAVY,
    lowerPrice: 65_000_00000000,
    upperPrice: 75_000_00000000,
    tickCount: 30,
    depositAmount: 500_000e6,     // 500k USDC
    depositCurrency: Currency.wrap(USDC_ADDRESS),
    autoRebalance: false,         // Manual rebalancing only
    rebalanceThresholdBps: 0
});

// Result:
// - 350k USDC in buy orders (70%)
// - 150k USDC in sell orders (30%)
```

### Example 3: Set Up Bot Rebalancing

```solidity
// Create position with auto-rebalance enabled
uint256 positionId = rangeLiquidityManager.createPosition(params);

// Authorize keeper bot
rangeLiquidityManager.setAuthorizedBot(positionId, KEEPER_BOT_ADDRESS);

// Bot monitors and rebalances when drift >= 5%
// Bot calls:
(bool canReb, uint256 drift) = rangeLiquidityManager.canRebalance(positionId);
if (canReb) {
    rangeLiquidityManager.rebalancePosition(positionId);
}
```

### Example 4: Close Position

```solidity
// User closes position to withdraw all funds
rangeLiquidityManager.closePosition(positionId);

// All unfilled orders cancelled
// User receives:
// - Remaining BTC from unfilled sell orders
// - Remaining USDC from unfilled buy orders
// - USDC from filled sell orders
// - BTC from filled buy orders
```

## Key Constraints

1. **One Position Per Pool**: Each user can only have 1 active position per pool pair
2. **Max 100 Ticks**: Maximum 100 price levels per position (gas optimization)
3. **Post-Only Orders**: All orders are Post-Only to provide liquidity, not take it
4. **Single-Sided Deposits**: Users deposit one token, system distributes across buys/sells
5. **Non-Transferable**: Positions are locked to the creator's address

## Gas Considerations

- **Position creation**: Gas scales with `tickCount` (each tick = 1-2 orders)
- **Rebalancing**: 2x gas of creation (cancel all + place new)
- **Recommended tick counts**:
  - Light: 10-20 ticks (lower gas)
  - Medium: 20-40 ticks (balanced)
  - Heavy: 40-100 ticks (maximum depth, high gas)

## Integration Steps

1. **Deploy Contracts**:
   ```bash
   # Deploy RangeLiquidityManager
   # Initialize with PoolManager, BalanceManager, Router addresses
   ```

2. **User Approvals**:
   ```solidity
   // User approves BalanceManager to spend tokens
   USDC.approve(balanceManager, type(uint256).max);
   BTC.approve(balanceManager, type(uint256).max);
   ```

3. **Create Position**:
   ```solidity
   uint256 positionId = rangeLiquidityManager.createPosition(params);
   ```

4. **Monitor & Rebalance**:
   ```solidity
   // Off-chain keeper monitors positions
   // Rebalances when drift threshold met
   ```

## Events

```solidity
event PositionCreated(uint256 indexed positionId, address indexed owner, ...);
event PositionRebalanced(uint256 indexed positionId, ...);
event PositionClosed(uint256 indexed positionId, ...);
event BotAuthorized(uint256 indexed positionId, address indexed bot);
event BotRevoked(uint256 indexed positionId, address indexed bot);
```

## Security Considerations

1. **Reentrancy Protection**: All state-changing functions use `nonReentrant`
2. **Access Control**: Only owner or authorized bot can rebalance
3. **Validation**: All parameters validated before execution
4. **Slippage**: Consider adding slippage protection for rebalancing
5. **Oracle Dependency**: Price fetching relies on Oracle or orderbook mid-price

## Future Enhancements (Not in MVP)

- [ ] Position NFTs for transferability
- [ ] Advanced distribution curves (Gaussian, custom)
- [ ] Fee tracking and analytics
- [ ] Impermanent loss calculations
- [ ] Multi-pool positions
- [ ] Auto-compound fees into position
- [ ] Position merging/splitting
- [ ] Limit orders with stop-loss

## Testing Checklist

- [ ] Create position with all 3 strategies
- [ ] Close position and verify withdrawals
- [ ] Manual rebalancing
- [ ] Bot authorization and auto-rebalancing
- [ ] Drift threshold enforcement
- [ ] Edge cases: price out of range, all orders filled
- [ ] Gas benchmarks for different tick counts
- [ ] One position per pool constraint
- [ ] View functions return correct data

## License

MIT

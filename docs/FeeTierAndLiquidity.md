# Fee Tier and Liquidity Provider System

## Overview

The ScaleX protocol implements a Uniswap v3-style concentrated liquidity market maker (CLMM) with fee tiers. This system allows liquidity providers to earn yields from trading fees while providing liquidity across specific price ranges.

## Fee Tiers

The protocol supports two default fee tiers:

| Fee Tier | Basis Points | Percentage | Tick Spacing | Use Case |
|----------|--------------|------------|--------------|----------|
| Low      | 20 bps       | 0.2%       | 50           | Stable pairs, high volume |
| Medium   | 50 bps       | 0.5%       | 200          | Volatile pairs, lower volume |

### Fee Tier Constants

```solidity
// In FeeTier.sol and Pool.sol
uint24 public constant FEE_TIER_LOW = 20;      // 0.2%
uint24 public constant FEE_TIER_MEDIUM = 50;   // 0.5%
```

## Tick Spacing

Tick spacing determines the granularity of price levels for liquidity provision:

| Tick Spacing | Fee Tier | Description |
|--------------|----------|-------------|
| 50           | 0.2%     | Finer price granularity for stable pairs |
| 200          | 0.5%     | Coarser price granularity for volatile pairs |

### Tick Spacing Constants

```solidity
// In FeeTier.sol and Pool.sol
uint16 public constant TICK_SPACING_LOW = 50;     // For 0.2% fee tier
uint16 public constant TICK_SPACING_MEDIUM = 200; // For 0.5% fee tier
```

## LP Yield Mechanism

### How LPs Earn Yield

The spread between the **fee tier** and the **ScaleX protocol fee** represents the yield for liquidity providers:

```
LP Yield = Fee Tier - Protocol Fee
```

**Example:**
- Fee Tier: 0.5% (50 bps)
- Protocol Fee: 0.1% (10 bps)
- **LP Yield: 0.4% (40 bps)**

This means:
- For every trade that occurs in the pool, 0.5% fee is charged
- 0.1% goes to the protocol
- 0.4% goes to the liquidity providers (LPs)

### Fee Collection Flow

1. **Trade Execution**: When a trade occurs, a fee is charged based on the pool's fee tier
2. **Fee Split**: The total fee is split between protocol and LPs
   - Protocol receives: `(totalFee × protocolFeeBps) / feeTier`
   - LPs receive: `totalFee - protocolFee`
3. **Fee Accumulation**: LP fees accumulate in the position's fee tracking
4. **Fee Claiming**: LPs can call `collectFees()` to withdraw accumulated fees

### Fee Distribution Example

For a trade of 10,000 USDC in a 0.5% fee tier pool:

```
Trade Amount: 10,000 USDC
Fee Tier: 0.5% (50 bps)
Total Fee: 10,000 × 0.005 = 50 USDC

Protocol Fee: 0.1% (10 bps)
Protocol Share: 50 × (10/50) = 10 USDC

LP Fee: 0.4% (40 bps)
LP Share: 50 - 10 = 40 USDC
```

## Creating a Liquidity Position

When creating a position, you must specify:

```solidity
struct PositionParams {
    PoolKey poolKey;          // Includes feeTier
    Strategy strategy;         // UNIFORM, BID_HEAVY, or ASK_HEAVY
    uint128 lowerPrice;       // Lower bound of price range
    uint128 upperPrice;       // Upper bound of price range
    uint16 tickCount;         // Number of ticks in range
    uint16 tickSpacing;       // 50 or 200
    uint256 depositAmount;    // Amount to deposit
    Currency depositCurrency; // Which token to deposit
    bool autoRebalance;       // Enable auto-rebalancing
    uint16 rebalanceThresholdBps; // Rebalance trigger threshold
}
```

### Example: Creating a Position

```solidity
// For a stable pair with 0.2% fee tier
PositionParams memory params = PositionParams({
    poolKey: PoolKey({
        baseCurrency: WETH,
        quoteCurrency: USDC,
        feeTier: 20  // 0.2%
    }),
    strategy: Strategy.UNIFORM,
    lowerPrice: 1900e8,
    upperPrice: 2100e8,
    tickCount: 10,
    tickSpacing: 50,  // Matches 0.2% fee tier
    depositAmount: 10000e6,  // 10,000 USDC
    depositCurrency: USDC,
    autoRebalance: true,
    rebalanceThresholdBps: 500  // 5%
});

uint256 positionId = rangeLiquidityManager.createPosition(params);
```

## Collecting Fees

LPs can collect accumulated fees at any time:

```solidity
// Collect fees for position ID 123
rangeLiquidityManager.collectFees(123);
```

This will:
1. Calculate accumulated fees in both base and quote currencies
2. Transfer fees to the position owner
3. Emit a `FeesCollected` event
4. Update the position's fee tracking

## Position Value Breakdown

Query position value to see fees earned:

```solidity
PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);

// Returns:
// - totalValueInQuote: Total position value
// - baseAmount: Amount in base currency
// - quoteAmount: Amount in quote currency
// - lockedInOrders: Amount locked in active orders
// - freeBalance: Available balance
// - feesEarnedBase: Total fees earned in base currency
// - feesEarnedQuote: Total fees earned in quote currency
```

## LP Yield Calculation

Get the LP yield for a position:

```solidity
uint24 lpYieldBps = rangeLiquidityManager.getLPYield(positionId);
// Returns yield in basis points (e.g., 40 = 0.4%)
```

## Protocol Configuration

### Setting Protocol Fee (Owner Only)

```solidity
// Set protocol fee to 0.15% (15 bps)
rangeLiquidityManager.setProtocolFee(15);
```

### Getting Current Protocol Fee

```solidity
uint16 protocolFeeBps = rangeLiquidityManager.getProtocolFee();
```

## Fee Tier Selection Guidelines

### 0.2% Fee Tier (Tick Spacing 50)
**Best for:**
- Stablecoin pairs (USDC/USDT, DAI/USDC)
- Wrapped assets (WETH/stETH)
- Highly correlated pairs
- High volume, low volatility

**Characteristics:**
- Lower fees attract more traders
- Tighter spreads
- More frequent rebalancing may be needed
- Higher capital efficiency

### 0.5% Fee Tier (Tick Spacing 200)
**Best for:**
- Volatile pairs (ETH/BTC, ETH/ALT)
- Exotic pairs
- Lower volume pairs
- Higher price volatility

**Characteristics:**
- Higher fees compensate for risk
- Wider spreads acceptable
- Less frequent rebalancing needed
- Lower capital efficiency but higher fee income

## Important Notes

1. **Fee Tier Validation**: Only 0.2% (20 bps) and 0.5% (50 bps) fee tiers are supported
2. **Tick Spacing Validation**: Only 50 and 200 tick spacing values are allowed
3. **Matching Requirements**: Tick spacing must match the fee tier:
   - 0.2% fee tier → 50 tick spacing
   - 0.5% fee tier → 200 tick spacing
4. **Fee Collection**: Fees accumulate automatically and can be collected at any time
5. **Protocol Fee**: Currently set to 0.1% (10 bps) by default, adjustable by owner

## Smart Contract Integration

### Key Contracts

- **RangeLiquidityManager**: Main contract for managing positions
- **FeeTier**: Helper library for fee calculations
- **Pool**: Pool library with fee tier constants
- **RangeLiquidityDistribution**: Distribution calculations with tick spacing

### Events

```solidity
event PositionCreated(
    uint256 indexed positionId,
    address indexed owner,
    PoolKey poolKey,
    uint128 lowerPrice,
    uint128 upperPrice,
    uint256 totalLiquidity,
    Strategy strategy,
    uint16 tickSpacing,
    uint24 feeTier
);

event FeesCollected(
    uint256 indexed positionId,
    uint256 baseAmount,
    uint256 quoteAmount
);

event PositionClosed(
    uint256 indexed positionId,
    address indexed owner,
    uint256 baseReturned,
    uint256 quoteReturned,
    uint256 feesEarnedBase,
    uint256 feesEarnedQuote
);
```

## Migration Notes

### For Existing Positions

Existing positions created before the fee tier update will need to:
1. Close old positions
2. Create new positions with fee tier specification
3. Fees from old positions should be collected before migration

### For Pool Creation

When creating new pools, the fee tier must be specified:

```solidity
poolManager.createPool(
    baseCurrency,
    quoteCurrency,
    tradingRules,
    20  // Fee tier: 0.2%
);
```

## Security Considerations

1. **Fee Validation**: All fee tiers are validated on position creation
2. **Tick Spacing Validation**: Tick spacing must match fee tier
3. **Protocol Fee Cap**: Protocol fee cannot exceed 10% (1000 bps)
4. **Ownership Checks**: Only position owners can collect fees
5. **Reentrancy Protection**: All functions use `nonReentrant` modifier

## Gas Optimization

- Fee calculations use efficient basis point arithmetic
- Fee accumulation happens off-chain in storage
- Collection is batched (both base and quote fees at once)
- No loops for fee distribution

## Future Enhancements

Potential improvements:
1. Additional fee tiers (0.05%, 1%)
2. Dynamic fee adjustment based on volatility
3. Fee sharing with governance token holders
4. Time-weighted fee distribution
5. Fee rebates for high-volume LPs

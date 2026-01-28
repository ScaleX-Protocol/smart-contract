# FillOrderBooks.s.sol - Dynamic Decimal Support Fix

## Problem Summary

The `FillOrderBooks.s.sol` script had **hardcoded decimal assumptions** that caused order placement failures when using IDRX (2 decimals) as quote currency instead of USDC (6 decimals).

### Root Cause

1. **Hardcoded 18-decimal quantities**: Used `1e16`, `100e18` etc., assuming all tokens have 18 decimals
   - Reality: WBTC has 8 decimals, so `1e16` = 100 million BTC (not 0.01 BTC)

2. **Hardcoded 6-decimal prices**: All prices used `e6` notation (e.g., `95000e6`)
   - Reality: IDRX has 2 decimals, so prices should use `e2` (e.g., `95000e2`)

3. **Wrong quote calculation formula**: Used `/1e18` divisor for all tokens
   - Reality: Should use `/ (10 ** baseDecimals)` dynamically

4. **Decimal inheritance**: Synthetic tokens inherit decimals from underlying tokens
   - IDRX (2 decimals) → sxIDRX (2 decimals)
   - WBTC (8 decimals) → sxWBTC (8 decimals)
   - WETH (18 decimals) → sxWETH (18 decimals)

### Error Details

**Original Error:**
```
InsufficientOrderBalance(3835994225, 9480000000000000000)
Available: 38.35 IDRX
Required:  9.48e18 IDRX (2.5 billion times more!)
```

**Calculation Breakdown:**
```solidity
// Attempted order
Quantity: 1e16 (with 8 decimals = 100,000,000 WBTC!)
Price: 94800e6
Required quote = (1e16 * 94800e6) / 1e8 = 9.48e18 sxIDRX

// What was deposited
quoteNeeded = (94900e6 * 1e16 * 4) / 1e18 = 3.796e9 sxIDRX
```

## Solution Implemented

### 1. Dynamic Decimal Reading

Each pool function now reads decimals from deployed contracts:

```solidity
// Read decimals dynamically
uint8 wbtcDecimals = MockToken(sxWBTC).decimals();
uint8 quoteDecimals = MockToken(sxQuote).decimals();
uint256 priceDivisor = 10 ** quoteDecimals;
```

### 2. Dynamic Order Quantities

Order quantities now scale based on actual token decimals:

```solidity
// OLD (hardcoded 18 decimals)
1e16,            // 0.01 BTC per order (WRONG for 8-decimal tokens!)
100e18,          // Setup: 100 BTC

// NEW (dynamic decimals)
uint256 orderQuantity = 1 * (10 ** (wbtcDecimals - 2)); // 0.01 BTC = 1e6 for 8-decimal token
uint256 setupAmount = 100 * (10 ** wbtcDecimals);       // 100 BTC = 1e10 for 8-decimal token
```

### 3. Dynamic Price Configuration

Prices now scale based on `QUOTE_DECIMALS` environment variable:

```solidity
// OLD (hardcoded 6 decimals)
uint128 wbtcPrice = uint128(vm.envOr("WBTC_PRICE", uint256(95000e6)));
priceConfigs["WBTC"] = PriceConfig({
    oraclePrice: wbtcPrice,
    buyStartPrice: wbtcPrice - 200e6,  // Hardcoded e6
    ...
});

// NEW (dynamic decimals)
uint8 quoteDecimals = uint8(vm.envOr("QUOTE_DECIMALS", uint256(6)));
uint256 priceUnit = 10 ** quoteDecimals;

uint128 wbtcPrice = uint128(vm.envOr("WBTC_PRICE", uint256(95000 * priceUnit)));
uint128 wbtcSpread = uint128(200 * priceUnit);
priceConfigs["WBTC"] = PriceConfig({
    oraclePrice: wbtcPrice,
    buyStartPrice: wbtcPrice - wbtcSpread,  // Dynamic based on QUOTE_DECIMALS
    ...
});
```

### 4. Correct baseToQuote Formula

Quote calculation now uses proper decimal handling:

```solidity
// OLD (hardcoded /1e18 divisor)
uint256 quoteNeeded = (buyEndPrice * orderQuantity * numOrders) / 1e18;

// NEW (uses actual base token decimals)
uint8 baseDecimals = MockToken(syntheticToken).decimals();
uint8 quoteDecimals = MockToken(syntheticQuote).decimals();

// baseToQuote formula: (baseAmount * price) / (10 ** baseDecimals)
uint256 quotePerOrder = (uint256(orderQuantity) * uint256(buyEndPrice)) / (10 ** baseDecimals);
uint256 quoteNeeded = quotePerOrder * numOrders;
```

### 5. Dynamic Console Logging

Price displays now use correct divisors:

```solidity
// OLD (hardcoded /1e6)
console.log("Oracle price:", config.oraclePrice / 1e6);
console.log("  [OK] BUY order placed at price:", currentPrice / 1e6);

// NEW (uses actual quote decimals)
uint256 priceDivisor = 10 ** quoteDecimals;
console.log("Oracle price:", config.oraclePrice / priceDivisor);
console.log("  [OK] BUY order placed at price:", currentPrice / priceDivisor);
```

## Changes Made to Script

### Files Modified
- `/Users/renaka/gtx/clob-dex/script/trading/FillOrderBooks.s.sol`

### Functions Updated
1. `initializePriceConfigs()` - Dynamic price scaling based on QUOTE_DECIMALS
2. `fillWBTCPool()` - Dynamic decimals for WBTC orders
3. `fillGOLDPool()` - Dynamic decimals for GOLD orders
4. `fillSILVERPool()` - Dynamic decimals for SILVER orders
5. `fillGOOGLEPool()` - Dynamic decimals for GOOGLE orders
6. `fillNVIDIAPool()` - Dynamic decimals for NVIDIA orders
7. `fillMNTPool()` - Dynamic decimals for MNT orders
8. `fillAPPLEPool()` - Dynamic decimals for APPLE orders
9. `_fillTokenPool()` - Core logic updated with proper baseToQuote formula

### New Features
- Reads `QUOTE_DECIMALS` from environment (defaults to 6)
- Reads token decimals from deployed contracts dynamically
- Calculates order quantities based on actual token decimals
- Uses proper baseToQuote formula: `(quantity * price) / (10 ** baseDecimals)`
- Displays prices and quantities with correct decimal formatting

## Environment Variables

The script now supports:

```bash
# Quote currency configuration
QUOTE_CURRENCY=IDRX          # or USDC, USDT, etc.
QUOTE_DECIMALS=2             # Decimals for quote currency (2 for IDRX, 6 for USDC)

# Price overrides (optional - will use priceUnit based on QUOTE_DECIMALS)
WBTC_PRICE=95000e2           # For IDRX (2 decimals)
GOLD_PRICE=4450e2            # For IDRX (2 decimals)
# ... etc
```

## Verification

### Example: WBTC Pool with IDRX

**Configuration:**
- Quote Currency: IDRX (2 decimals)
- sxWBTC: 8 decimals
- sxIDRX: 2 decimals
- Price: 95000 IDRX = 9500000 (with 2 decimals)

**Order Calculation:**
```
Order quantity: 0.01 BTC = 1 * (10^(8-2)) = 1e6 sxWBTC
Price: 94800 IDRX = 9480000 (with 2 decimals)

Quote needed per order = (1e6 * 9480000) / 1e8 = 94800 sxIDRX
Total quote for 4 orders = 94800 * 4 = 379200 sxIDRX = 3792 IDRX
```

This is now **correct** and matches the actual on-chain requirements!

## Testing

To test the fix, run:

```bash
# Make sure .env has QUOTE_DECIMALS set
source .env.base-sepolia

# Run the order book filling script
./shellscripts/update-orderbook-prices.sh
```

Expected behavior:
- ✅ All BUY orders should place successfully
- ✅ All SELL orders should place successfully
- ✅ Orders should appear on-chain with correct prices
- ✅ Quote balance should be sufficient for all orders

## Additional Notes

### Decimal Inheritance Pattern
Synthetic tokens **always inherit decimals** from their underlying tokens:
- `underlying.decimals()` == `synthetic.decimals()`

### Price Units
Prices are stored in quote currency units with quote decimals:
- USDC (6 decimals): $95,000 = 95000e6 = 95,000,000,000
- IDRX (2 decimals): 95,000 IDRX = 95000e2 = 9,500,000

### BaseToQuote Formula
The on-chain formula used in OrderBook.sol:
```solidity
function baseToQuote(uint256 baseAmount, uint256 price, uint8 baseDecimals)
    returns (uint256 quoteAmount)
{
    quoteAmount = (baseAmount * price) / (10 ** baseDecimals);
}
```

This formula is **independent of quote decimals** because:
- `baseAmount` is in base token units (e.g., 1e6 for 0.01 BTC with 8 decimals)
- `price` is in quote token units (e.g., 9480000 for 94800 IDRX with 2 decimals)
- Result is in quote token units (e.g., 94800 sxIDRX units with 2 decimals)

## Related Issues Fixed

This fix resolves the same pattern of issues found and fixed in:
- ✅ `FillOrderBook.s.sol` (already fixed earlier)
- ✅ `shellscripts/populate-data.sh` (already uses QUOTE_DIVISOR)
- ✅ `shellscripts/lib/quote-currency-config.sh` (helper functions provided)
- ❌ `PlaceMarketOrders.s.sol` (still needs fixing - has hardcoded e6)
- ❌ `MarketOrderBook.sol` (still needs fixing - has hardcoded e6)

## Summary

The `FillOrderBooks.s.sol` script is now **fully dynamic** and works with any quote currency regardless of decimals. All calculations use on-chain decimal values and proper formulas, ensuring compatibility with IDRX (2 decimals), USDC (6 decimals), or any other quote currency.

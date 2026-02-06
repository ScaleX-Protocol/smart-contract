# Price Conversion Bug: OrderBook → Oracle

## The Problem

The Oracle receives prices from OrderBook trades but **doesn't convert the format**!

### What's Happening:

1. **OrderBook Format**: Prices are in "quote currency per base currency"
   - Example: `194900` = **1949.00 IDRX per WETH** (2 decimals)
   - This is the trading pair price format

2. **Oracle Format**: Prices should be in "USD per token"
   - Example: `300000000000` = **$3000.00 USD per WETH** (8 decimals)
   - This is what health factor calculations expect

3. **The Bug**: Oracle stores OrderBook price **directly without conversion**
   ```solidity
   // OrderBook.sol line 1258-1260
   $.oracle.updatePriceFromTrade(
       Currency.unwrap($.poolKey.baseCurrency), // sxWETH
       tradePrice,  // ❌ 194900 (IDRX per WETH)
       tradeVolume
   );
   
   // Oracle.sol line 225
   _storePricePoint(token, uint256(price), block.timestamp);
   // ❌ Stores 194900 directly as USD price!
   ```

### The Math:

**Correct conversion:**
```
OrderBook price: 194900 (raw value)
               ÷ 100 (2 decimals) 
               = 1949 IDRX per WETH
               × $1.00 (IDRX USD value)
               = $1949 USD per WETH
               × 100000000 (8 decimals)
               = 194900000000 (correct Oracle format)
```

**What actually happens:**
```
OrderBook price: 194900
Oracle stores:   194900 (interpreted as 8 decimals)
Result:          $0.001949 USD per WETH ❌ (1 million times too low!)
```

## Why This Breaks Health Factor:

With wrong price ($0.001949 instead of $1949):
```
Collateral: 100 IDRX × $1.00 = $100
Borrow: 0.0206 WETH × $0.001949 = $0.00004 
HF = $100 / $0.00004 = 2,500,000 (should be ~1.37!)
```

But we see HF = 0.0327, which means there are **additional decimal/calculation errors** compounding the problem.

## The Fix Options:

### Option 1: Fix Oracle to Convert Prices (Proper Fix)
Modify `updatePriceFromTrade()` to:
1. Get quote currency from OrderBook
2. Get USD price of quote currency
3. Convert: `orderbook_price × quote_usd_value ×  decimals_adjustment`

### Option 2: Disable Auto-Updates (Quick Fix)
```solidity
oracle.setAuthorizedOrderBook(sxWETH, orderBook, false);
oracle.setPrice(sxWETH, 300000000000); // Manually set $3000
```

### Option 3: Fix OrderBook to Send USD Prices
Modify OrderBook to convert prices before calling oracle.

## Impact:

- ✅ Manual `setPrice()` calls work correctly
- ❌ Trade-based price updates are broken (wrong by 1,000,000x)
- ❌ Health factor calculations fail when using trade-based prices
- ❌ Auto-borrow feature is blocked

## Recommended Solution:

**Disable automatic price updates until proper conversion is implemented:**

1. Revoke OrderBook authorization to update Oracle
2. Set correct prices manually
3. Implement proper price conversion logic
4. Re-enable automatic updates


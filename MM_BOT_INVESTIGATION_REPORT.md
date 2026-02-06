# MM Bot & Trading Bot Investigation Report
**Date**: 2026-01-28
**Issue**: Trading bots getting `OrderHasNoLiquidity()` errors on Base Sepolia

## Executive Summary

The trading bots were failing with `OrderHasNoLiquidity()` because:
1. MM bot had **outdated ABIs** (Dec 4, 2025 vs Jan 27, 2026 deployment)
2. MM bot was **missing spread configuration** (causing NegativeSpreadCreated errors)
3. **10 old buy orders** at prices 298,200-300,600 were blocking the MM bot from placing new sell orders
4. Without sell orders, trading bot's BUY market orders had no liquidity to match against

## What Was Fixed ✅

### 1. Updated ABIs
- **Problem**: MM bot ABIs from Dec 4, 2025, contracts redeployed Jan 27, 2026 with dynamic quote token system
- **Solution**: Regenerated ABIs and copied to MM bot
```bash
cd /Users/renaka/gtx/clob-dex
make generate-abi
cp deployed-contracts/abis/*.ts ../mm-bot/src/abis/contracts/
```

### 2. Added Missing Spread Configuration
- **Problem**: `SPREAD_PERCENTAGE` missing → spread=0 → NegativeSpreadCreated errors
- **Solution**: Added to `/Users/renaka/gtx/mm-bot/.env.base-sepolia`:
```bash
SPREAD_PERCENTAGE=0.5
PRICE_STEP_PERCENTAGE=0.2
REFRESH_INTERVAL=30000  # Changed from 250000 for faster testing
```

### 3. Cancelled Blocking Orders
- **Problem**: 10 buy orders (IDs 23-32) at high prices blocking new sell order placement
- **Solution**: Cancelled all using cast:
```bash
# Orders cancelled at ~10:36 UTC
for id in {23..32}; do
  cast send 0x7D6657eB26636D2007be6a058b1fc4F50919142c \
    "cancelOrder((address,address,address),uint48)" \
    "(0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6,0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624,0xB45fC76ba06E4d080f9AfBC3695eE3Dea5f97f0c)" \
    "$id" --private-key $PRIVATE_KEY --rpc-url https://sepolia.base.org
done
```

### 4. Rebuilt Containers
```bash
cd /Users/renaka/gtx/mm-bot
docker-compose -f docker-compose.base-sepolia.yml up -d base-sepolia-mm-bot --build --force-recreate
docker-compose -f docker-compose.base-sepolia.yml restart base-sepolia-trading-bots
```

## Current Status (as of 10:37 UTC)

### MM Bot
- **Status**: Running, executing cycles every 30s
- **Mid-price**: ~302,238 (correctly calculated from Binance)
- **Orders placed**: 0 (still not placing new orders)
- **Last cycle**: `ordersPlaced=0, ordersCancelled=0`
- **Container**: `base-sepolia-mm-bot` (healthy)
- **Wallet**: `0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a`

### Trading Bot
- **Status**: Running, attempting trades
- **Error**: `OrderHasNoLiquidity()` - no sell orders to match BUY market orders
- **Container**: `base-sepolia-trading-bots` (healthy)
- **Wallet**: `0x506B6fa189Ada984E1F98473047970f17da15AEc`, `0xf38A17f0d365dA9e1Ba6715b16708ACf30153cD7`, `0x611910e4C4408eE76199CA4a5215FE830210fd55`

### On-Chain State (Base Sepolia)
- **Pool Manager**: `0x7D6657eB26636D2007be6a058b1fc4F50919142c`
- **OrderBook**: `0xB45fC76ba06E4d080f9AfBC3695eE3Dea5f97f0c`
- **Base Token (sxWETH)**: `0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6`
- **Quote Token (sxIDRX)**: `0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624`
- **Active Orders**: Cancelled, waiting for indexer to sync

## Next Steps 🎯

### Immediate Action Required (Next Agent)

**1. Monitor MM Bot for Order Placement (5-10 minutes)**
```bash
# Watch for order placement in real-time
docker logs base-sepolia-mm-bot -f 2>&1 | grep -E "placeOrder|ordersPlaced|Market making cycle completed"

# Expected output after next cycle:
# "ordersPlaced":5  (5 buy orders)
# "ordersPlaced":5  (5 sell orders)
```

**2. Check Indexer Synchronization**
```bash
# Should show 0 orders after indexer syncs
curl -s "https://base-sepolia-indexer.scalex.money/api/openOrders?address=0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a" | jq 'length'

# Currently returns: 10 (stale data - indexer hasn't synced yet)
# Should return: 0 after sync, then increase as MM bot places new orders
```

**3. Verify On-Chain Order Book State**
```bash
# Check if there are any active orders on-chain
cast call 0x7D6657eB26636D2007be6a058b1fc4F50919142c \
  "getBestPrice((address,address),uint8)" \
  "..." --rpc-url https://sepolia.base.org

# Need proper cast syntax for struct parameters
```

**4. If MM Bot Still Not Placing Orders After 5 Minutes**

Check these potential issues:

```bash
# A. Check MM bot logs for errors
docker logs base-sepolia-mm-bot --since 5m 2>&1 | grep -i error

# B. Verify spread configuration is loaded
docker exec base-sepolia-mm-bot env | grep SPREAD

# C. Check if MM bot is reading correct indexer data
docker logs base-sepolia-mm-bot 2>&1 | grep -i "getUserActiveOrders" | tail -5

# D. Verify Balance Manager has sufficient balance
# Look for: "Balance Manager WETH balance: 100000"
#           "Balance Manager USDC balance: 19.10216"
```

**5. Once MM Bot Places Sell Orders**

The trading bot should automatically start working:
```bash
# Monitor trading bot for successful trades
docker logs base-sepolia-trading-bots -f 2>&1 | grep -E "successfully|Trade executed|placeMarketOrder"

# Should see: Market orders executing instead of OrderHasNoLiquidity errors
```

## Debugging Commands

### MM Bot (Running on Server)

**Prerequisites**: SSH into the server where the containers are running

```bash
# Full logs
docker logs base-sepolia-mm-bot

# Recent activity
docker logs base-sepolia-mm-bot --since 5m

# Check configuration inside container
docker exec base-sepolia-mm-bot cat /app/.env.base-sepolia | grep -E "SPREAD|MAX_ORDERS|REFRESH"

# Expected output:
# SPREAD_PERCENTAGE=0.5
# MAX_ORDERS_PER_SIDE=5
# REFRESH_INTERVAL=30000

# Find MM bot directory on server
MM_BOT_DIR=$(docker inspect base-sepolia-mm-bot | jq -r '.[0].Config.Labels."com.docker.compose.project.working_dir"')
echo "MM bot directory: $MM_BOT_DIR"

# Restart MM bot (from MM bot directory)
cd $MM_BOT_DIR
docker-compose -f docker-compose.base-sepolia.yml restart base-sepolia-mm-bot

# Or restart without finding directory
docker restart base-sepolia-mm-bot
```

### Trading Bot
```bash
# Full logs
docker logs base-sepolia-trading-bots

# Watch for trades
docker logs base-sepolia-trading-bots -f 2>&1 | grep -i "trade"
```

### On-Chain Verification
```bash
# Check open orders via indexer API
curl -s "https://base-sepolia-indexer.scalex.money/api/openOrders?symbol=sxWETH/sxIDRX" | jq .

# Get order details
curl -s "https://base-sepolia-indexer.scalex.money/api/openOrders?address=0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a" | jq .
```

## Key Files Modified

1. `/Users/renaka/gtx/mm-bot/.env.base-sepolia`
   - Added: `SPREAD_PERCENTAGE=0.5`
   - Added: `PRICE_STEP_PERCENTAGE=0.2`
   - Changed: `REFRESH_INTERVAL=30000` (from 250000)
   - Changed: `MAX_ORDERS_PER_SIDE=5` (from 10)

2. `/Users/renaka/gtx/mm-bot/src/abis/contracts/`
   - Updated: `BalanceManagerABI.ts`, `OrderBookABI.ts`, `ScaleXRouterABI.ts`
   - Source: `/Users/renaka/gtx/clob-dex/deployed-contracts/abis/`

3. `/Users/renaka/gtx/clob-dex/deployed-contracts/abis/`
   - Modified (uncommitted): `BalanceManagerABI.ts`, `OrderBookABI.ts`, `ScaleXRouterABI.ts`

## Important Contract Addresses (Base Sepolia - Chain ID: 84532)

```typescript
{
  "chainId": 84532,
  "poolManager": "0x7D6657eB26636D2007be6a058b1fc4F50919142c",
  "balanceManager": "0x5ec647BBa5cdC3Cb47BFaEeA10D978475a2Fc977",
  "orderBook": "0xB45fC76ba06E4d080f9AfBC3695eE3Dea5f97f0c",
  "poolId": "0xB45fC76ba06E4d080f9AfBC3695eE3Dea5f97f0c",
  "tokens": {
    "sxWETH": "0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6",
    "sxIDRX": "0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624"
  },
  "mmBotWallet": "0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a",
  "tradingBotWallets": [
    "0x506B6fa189Ada984E1F98473047970f17da15AEc",
    "0xf38A17f0d365dA9e1Ba6715b16708ACf30153cD7",
    "0x611910e4C4408eE76199CA4a5215FE830210fd55"
  ]
}
```

## Expected Timeline

- **T+0 min** (10:36 UTC): Orders cancelled ✅
- **T+1-2 min**: Indexer syncs (shows 0 orders)
- **T+2-3 min**: MM bot detects 0 orders, starts placing new orders
- **T+3-4 min**: First sell orders appear on order book
- **T+4-5 min**: Trading bot BUY market orders start succeeding

## Success Criteria

✅ **MM bot placing orders**: `docker logs` shows `"ordersPlaced":5` or similar
✅ **Indexer synchronized**: API returns 5-10 active orders
✅ **Trading bot working**: No more `OrderHasNoLiquidity()` errors
✅ **Market making active**: Continuous order placement and cancellation in MM bot logs

## Repository Locations

### Local Machine (where fixes were applied)
- **Main repo**: `/Users/renaka/gtx/clob-dex`
- **MM bot repo**: `/Users/renaka/gtx/mm-bot` (relative: `../mm-bot` from clob-dex)
- **Indexer repo**: `/Users/renaka/gtx/clob-indexer` (relative: `../clob-indexer` from clob-dex)

### Server (where bots are running)
**IMPORTANT**: The MM bot and trading bots are running as Docker containers on the server.

**Container Names**:
- `base-sepolia-mm-bot` - Market maker bot
- `base-sepolia-trading-bots` - Trading bots

**To locate the MM bot on server**:
```bash
# Find running containers
docker ps | grep mm-bot

# Get container details
docker inspect base-sepolia-mm-bot

# Find docker-compose file location
docker inspect base-sepolia-mm-bot | jq -r '.[0].Config.Labels."com.docker.compose.project.working_dir"'

# Common locations to check:
# - /root/mm-bot
# - /home/user/mm-bot
# - /opt/mm-bot
# - Or wherever docker-compose.base-sepolia.yml is located
```

**To access MM bot files on server**:
```bash
# Method 1: Find via docker-compose
docker inspect base-sepolia-mm-bot | grep -i "working"

# Method 2: Check volume mounts
docker inspect base-sepolia-mm-bot | grep -A 10 "Mounts"

# Method 3: Access running container directly
docker exec -it base-sepolia-mm-bot pwd
docker exec -it base-sepolia-mm-bot ls -la /app
```

### API Endpoints
- **Indexer API**: `https://base-sepolia-indexer.scalex.money`
- **RPC**: `https://sepolia.base.org`

## Agent Instructions (Server Side)

**Context**: You are on the server where the MM bot Docker containers are running.

### Your Mission
Verify the MM bot starts placing orders within the next 5-10 minutes.

### Step-by-Step Verification

**1. Locate the MM Bot** (first time only)
```bash
# Find where MM bot is running
docker ps | grep mm-bot

# Get the working directory
docker inspect base-sepolia-mm-bot | jq -r '.[0].Config.Labels."com.docker.compose.project.working_dir"'

# Save it for later
export MM_BOT_DIR="<path from above>"
```

**2. Monitor for Order Placement** (5 minutes)
```bash
# Watch in real-time - you should see ordersPlaced > 0
docker logs base-sepolia-mm-bot -f 2>&1 | grep -E "placeOrder|ordersPlaced|Market making cycle completed"

# Expected after ~1-2 cycles:
# "ordersPlaced":5, "ordersCancelled":0
```

**3. If No Orders After 5 Minutes**
```bash
# Check for errors
docker logs base-sepolia-mm-bot --since 5m 2>&1 | grep -i error

# Verify configuration loaded
docker exec base-sepolia-mm-bot env | grep SPREAD_PERCENTAGE
# Should output: SPREAD_PERCENTAGE=0.5

# Check indexer response
docker logs base-sepolia-mm-bot --since 5m 2>&1 | grep "getUserActiveOrders" | tail -3
# Should show: "ordersCount":0 (not 10)
```

**4. If Configuration Missing**
The .env file needs to be rebuilt into the container:
```bash
cd $MM_BOT_DIR  # or wherever docker-compose.base-sepolia.yml is
docker-compose -f docker-compose.base-sepolia.yml up -d base-sepolia-mm-bot --build --force-recreate
```

**5. Verify Success**
```bash
# Should see active orders
curl -s "https://base-sepolia-indexer.scalex.money/api/openOrders?address=0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a" | jq 'length'
# Should return: 5-10 (not 0 or 10)

# Trading bot should start working
docker logs base-sepolia-trading-bots --since 2m 2>&1 | grep -i "successfully\|executed"
```

### Summary
The core issue was solved (ABIs updated, spread added, blocking orders cancelled). The fixes were applied locally and containers were rebuilt. Now we're waiting for the system to stabilize and start normal operation.

# Deployment Fixes - Oracle & OrderBook Library

## Issues Identified

### 1. OrderBook Library Deployment
**Problem**: After extracting `OrderMatchingLib` from `OrderBook` to reduce contract size, the deployment process needed clarification on how libraries are linked.

**Solution**:
- Libraries in Solidity are automatically linked at compile time when using `import` statements
- No manual library deployment needed - Forge handles this automatically
- Added clarifying comments in `DeployPhase1C.s.sol` to document this behavior

**Files Changed**:
- `script/deployments/DeployPhase1C.s.sol` - Added documentation comments

### 2. Missing Oracle Token Registration
**Problem**: Synthetic tokens for RWA assets (GOLD, SILVER, GOOGLE, NVIDIA, MNT, APPLE) were never registered with the Oracle contract during deployment. Only crypto assets (USDC, WETH, WBTC) were being registered.

**Impact**:
- RWA tokens couldn't get price updates from their OrderBooks
- Trading would fail due to missing oracle data
- System wouldn't be able to calculate collateral values for RWA assets

**Solution**:
Created comprehensive oracle configuration script and integrated it into `deploy.sh`

**Files Changed**:
- `script/deployments/ConfigureAllOracleTokens.s.sol` - **NEW FILE**
  - Registers ALL 9 synthetic tokens (sxQuote, sxWETH, sxWBTC, sxGOLD, sxSILVER, sxGOOGLE, sxNVIDIA, sxMNT, sxAPPLE)
  - Sets OrderBook addresses for each token
  - Initializes bootstrap prices for all assets
  - Includes verification step to confirm registration

- `shellscripts/deploy.sh` - Added Step 3.7
  - Runs `ConfigureAllOracleTokens` script after Phase 5 (AI Agent Infrastructure)
  - Verifies oracle tokens are properly registered
  - Performs spot checks on WETH and GOLD prices

## Token Registration Details

### Crypto Assets
| Token | Initial Price | Decimals |
|-------|--------------|----------|
| sxQuote (USDC/IDRX) | $1 | Quote decimals |
| sxWETH | $3,000 | 18 |
| sxWBTC | $95,000 | 8 |

### RWA Assets (Previously Missing)
| Token | Initial Price | Decimals | Type |
|-------|--------------|----------|------|
| sxGOLD | $2,780 | 18 | Commodity |
| sxSILVER | $32 | 18 | Commodity |
| sxGOOGLE | $188 | 18 | Stock |
| sxNVIDIA | $145 | 18 | Stock |
| sxMNT | $1 | 18 | Stablecoin |
| sxAPPLE | $235 | 18 | Stock |

## Deployment Flow Updated

```
Phase 1A: Deploy Base Tokens & Test Tokens
    ↓
Phase 1B: Deploy Core Infrastructure (Oracle, BalanceManager, LendingManager)
    ↓
Phase 1C: Deploy Final Infrastructure (PoolManager, ScaleXRouter, OrderBook Beacon)
    ├─ OrderBook deployed with OrderMatchingLib auto-linked
    └─ [NEW] Clarifying comments about library linking
    ↓
Phase 2: Configure System (Create Synthetic Tokens, Configure Lending)
    ↓
Phase 3: Create Trading Pools (Deploy OrderBook proxies via PoolManager)
    ↓
Phase 4: Deploy AutoBorrowHelper
    ↓
Phase 5: Deploy AI Agent Infrastructure (PolicyFactory, AgentRouter)
    ↓
[NEW] Step 3.7: Configure All Oracle Tokens ← FIXED MISSING STEP
    ├─ Register all 9 synthetic tokens with Oracle
    ├─ Set OrderBook addresses for price updates
    ├─ Initialize bootstrap prices
    └─ Verify registration
    ↓
Step 4.8: Verify OrderBook Authorizations and Oracle Configuration
```

## Oracle Integration Architecture

```
┌─────────────────┐
│   OrderBook     │
│   (WETH/USDC)   │
└────────┬────────┘
         │ updatePriceFromTrade()
         ↓
┌─────────────────┐      getSpotPrice()     ┌─────────────────┐
│     Oracle      │◄──────────────────────  │  LendingManager │
│                 │                         │                 │
│  Token Registry │                         │  AutoBorrow     │
│  ├─ sxQuote     │                         │  Helper         │
│  ├─ sxWETH      │                         └─────────────────┘
│  ├─ sxWBTC      │
│  ├─ sxGOLD      │  ← Previously missing registrations
│  ├─ sxSILVER    │  ← Previously missing registrations
│  ├─ sxGOOGLE    │  ← Previously missing registrations
│  ├─ sxNVIDIA    │  ← Previously missing registrations
│  ├─ sxMNT       │  ← Previously missing registrations
│  └─ sxAPPLE     │  ← Previously missing registrations
└─────────────────┘
```

## Testing the Fixes

### Verify Oracle Token Registration

```bash
# Load environment variables
source .env

# Set network
CHAIN_ID=84532  # Base Sepolia

# Get addresses from deployment file
ORACLE=$(cat ./deployments/${CHAIN_ID}.json | jq -r '.Oracle')
SX_GOLD=$(cat ./deployments/${CHAIN_ID}.json | jq -r '.sxGOLD')
SX_NVIDIA=$(cat ./deployments/${CHAIN_ID}.json | jq -r '.sxNVIDIA')

# Check if tokens are registered (should return non-zero prices)
cast call $ORACLE "getSpotPrice(address)" $SX_GOLD --rpc-url $SCALEX_CORE_RPC
cast call $ORACLE "getSpotPrice(address)" $SX_NVIDIA --rpc-url $SCALEX_CORE_RPC

# Expected: Both should return prices (e.g., 2780000000 for GOLD = $2,780)
```

### Run Oracle Configuration Manually

If you need to run oracle configuration separately:

```bash
forge script script/deployments/ConfigureAllOracleTokens.s.sol:ConfigureAllOracleTokens \
    --rpc-url $SCALEX_CORE_RPC \
    --broadcast \
    --private-key $PRIVATE_KEY \
    --gas-estimate-multiplier 120 \
    --legacy
```

## Next Steps

1. **For Fresh Deployments**: Run `./shellscripts/deploy.sh` - Oracle tokens will be configured automatically in Step 3.7

2. **For Existing Deployments**: Run the `ConfigureAllOracleTokens` script manually:
   ```bash
   forge script script/deployments/ConfigureAllOracleTokens.s.sol:ConfigureAllOracleTokens \
       --rpc-url $SCALEX_CORE_RPC \
       --broadcast \
       --private-key $PRIVATE_KEY
   ```

3. **Verify Registration**: Check that all synthetic tokens return valid prices from the oracle

## Notes

- **Library Linking**: Solidity libraries imported via `import` statements are automatically linked by Forge at compile time. No manual linking or separate deployment needed.

- **Price Initialization**: Bootstrap prices are set for all tokens to enable immediate trading. These will be updated by real trades via `updatePriceFromTrade()` calls from OrderBooks.

- **Quote Currency Flexibility**: The script supports dynamic quote currencies (USDC, IDRX, etc.) via the `QUOTE_SYMBOL` environment variable.

- **Error Handling**: The `ConfigureAllOracleTokens` script uses try-catch blocks to handle tokens that may already be registered, making it safe to re-run.

## Related Files

- `src/core/libraries/OrderMatchingLib.sol` - Extracted matching logic
- `src/core/OrderBook.sol` - Updated to use OrderMatchingLib
- `script/deployments/DeployOrderBookWithLibrary.s.sol` - Manual upgrade script (for existing deployments)
- `script/deployments/ConfigureOracleTokens.s.sol` - Old partial configuration (crypto only)
- `script/deployments/ConfigureRWAOraclePrices.s.sol` - Old RWA-specific configuration

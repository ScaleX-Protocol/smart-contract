# Cross-Chain Deposit Fix Documentation

## Issue Summary
Cross-chain deposits from Rise Sepolia and Arbitrum Sepolia were failing to relay through Hyperlane, causing users to be unable to deposit tokens from these chains to the BalanceManager on Rari.

## Root Cause Analysis

### 1. Missing Token Mappings (Rise Sepolia)
- **Problem**: Rise Sepolia had 0 token mappings registered in TokenRegistry
- **Impact**: When deposits arrived at BalanceManager, `TokenRegistry.getSyntheticToken()` returned `address(0)`
- **Result**: BalanceManager couldn't mint synthetic tokens, causing relay failures

### 2. Incorrect Token Mappings (Arbitrum Sepolia)  
- **Problem**: Arbitrum had some mappings but pointing to wrong synthetic token addresses
- **Impact**: Deposits would attempt to mint incorrect synthetic tokens
- **Result**: Potential failures or minting of unused tokens

### 3. BalanceManager Configuration
- **Problem**: BalanceManager's TokenRegistry was set to `address(0)`
- **Impact**: BalanceManager couldn't access any token mappings
- **Result**: Additional failure point for all cross-chain deposits

## Solution Implemented

### Phase 1: Token Mapping Registration
**Script**: `RegisterMappingsSimple.s.sol`

**Strategy**: Create temporary synthetic tokens through SyntheticTokenFactory, then update mappings to point to existing gUSDT/gWETH/gWBTC tokens.

**Actions**:
1. **Rise Sepolia Mappings** (created new):
   - `0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6` (USDT) → `0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d` (gUSDT)
   - `0x567a076BEEF17758952B05B1BC639E6cDd1A31EC` (WETH) → `0x3ffE82D34548b9561530AFB0593d52b9E9446fC8` (gWETH)
   - `0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E` (WBTC) → `0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748` (gWBTC)

2. **Arbitrum Sepolia Mappings** (updated existing):
   - `0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a` (USDT) → `0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d` (gUSDT)
   - `0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7` (WETH) → `0x3ffE82D34548b9561530AFB0593d52b9E9446fC8` (gWETH)
   - `0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A` (WBTC) → `0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748` (gWBTC)

### Phase 2: BalanceManager Configuration
**Script**: `FixBalanceManagerTokenRegistry.s.sol`

**Action**: Set BalanceManager's TokenRegistry to `0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E`

## Technical Details

### Approach Used: SyntheticTokenFactory Method
Since TokenRegistry is owned by SyntheticTokenFactory (`0x2594C4ca1B552ad573bcc0C4c561FAC6a87987fC`), and we own the SyntheticTokenFactory, we used the following approach:

1. **Create temporary synthetic tokens** via `SyntheticTokenFactory.createSyntheticToken()`
   - This automatically registers token mappings in TokenRegistry
2. **Update mappings** via `SyntheticTokenFactory.updateTokenMapping()`
   - This points the mappings to existing gUSDT/gWETH/gWBTC tokens
3. **Result**: All chains mint the same synthetic tokens

### Why This Approach Was Chosen
- ✅ **Preserves existing tokens**: All chains use the same gUSDT/gWETH/gWBTC
- ✅ **No pool updates needed**: Existing trading pools remain valid
- ✅ **Works within current ownership structure**: Uses SyntheticTokenFactory ownership
- ✅ **Clean and auditable**: Clear transaction history of changes

### Alternative Approaches Considered
1. **TokenRegistry Upgrade**: Would have provided direct owner control but required more complex proxy upgrades
2. **Ownership Transfer**: Temporary approach but adds complexity and risk
3. **New Synthetic Tokens**: Would have required new pools and fragmented liquidity

## Results

### Before Fix
- **Rise**: 0 token mappings → All deposits failed
- **Arbitrum**: Wrong mappings → Deposits failed or minted wrong tokens  
- **Appchain**: 3 correct mappings → Deposits worked

### After Fix
- **Rise**: 3 correct mappings → ✅ Deposits should work
- **Arbitrum**: 6 correct mappings → ✅ Deposits should work
- **Appchain**: 3 correct mappings → ✅ Deposits continue to work
- **BalanceManager**: TokenRegistry configured → ✅ All deposits should work

### Verification
```solidity
// Rise mappings
Rise USDT -> gUSDT: YES ✅
Rise WETH -> gWETH: YES ✅ 
Rise WBTC -> gWBTC: YES ✅

// Arbitrum mappings  
Arbitrum USDT -> gUSDT: YES ✅
Arbitrum WETH -> gWETH: YES ✅
Arbitrum WBTC -> gWBTC: YES ✅

// BalanceManager
TokenRegistry: 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E ✅
```

## Scripts Used

1. **`RegisterMappingsSimple.s.sol`**: Main fix script for token mappings
2. **`FixBalanceManagerTokenRegistry.s.sol`**: BalanceManager configuration fix
3. **`CheckTokenRegistry.s.sol`**: Verification script

## Future Enhancements

1. **TokenRegistry Upgrade**: Add direct owner control for easier mapping management
2. **Governance Integration**: Move ownership to governance contracts
3. **Automated Monitoring**: Add alerts for missing token mappings
4. **Multi-chain Token Discovery**: Automatic detection of new tokens needing mappings

## Deployment Updates

Updated `deployments/rari.json`:
- Added Rise and Arbitrum to `sourceChains` for all synthetic tokens
- Added `tokenMappingFixes` section documenting the fix
- Recorded temporary synthetic token addresses (unused but created during process)

## Testing

**Recommended Test**: Try a small deposit from Rise or Arbitrum to verify the fix works:
```bash
# Test Rise deposit
forge script script/TestRiseDeposit.s.sol --rpc-url https://indexing.testnet.riselabs.xyz/ --broadcast

# Test Arbitrum deposit  
forge script script/TestArbitrumDeposit.s.sol --rpc-url https://arb-sepolia.g.alchemy.com/v2/jBG4sMyhez7V13jNTeQKfVfgNa54nCmF --broadcast
```

**Expected Result**: Deposits should now relay successfully and mint gUSDT/gWETH/gWBTC on Rari.
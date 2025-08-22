# Deployment Addresses

This directory tracks all deployed contract addresses across different networks.

## Networks Status ✅

All networks are **FULLY OPERATIONAL** with successful cross-chain bridging to Rari testnet.

### Rari Testnet (Chain ID: 1918988905) - **HOST CHAIN** ✅
- **RPC**: `${RARI_ENDPOINT}` (see .env)
- **Domain ID**: 1918988905
- **Mailbox**: 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358
- **Status**: ✅ Operational
- **Role**: Destination chain for synthetic token minting

### Appchain Testnet (Chain ID: 4661) - **SOURCE CHAIN** ✅  
- **RPC**: `${APPCHAIN_ENDPOINT}` (see .env)
- **Domain ID**: 4661
- **Mailbox**: 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1
- **Status**: ✅ Operational - All tokens working (USDT, WETH, WBTC)

### Rise Sepolia (Chain ID: 11155931) - **SOURCE CHAIN** ✅
- **RPC**: `${RISE_SEPOLIA_ENDPOINT}` (see .env)  
- **Domain ID**: 11155931
- **Mailbox**: 0xD377bFbea110cDbc3D31EaFB146AE6fA5b3190E3
- **Status**: ✅ Operational - All tokens working (USDT, WETH, WBTC)

### Arbitrum Sepolia (Chain ID: 421614) - **SOURCE CHAIN** ✅ **RECENTLY FIXED**
- **RPC**: `${ARBITRUM_SEPOLIA_ENDPOINT}` (see .env)
- **Domain ID**: 421614  
- **Mailbox**: 0x8DF6aDE95d25855ed0FB927ECD6a1D5Bb09d2145 ⚠️ **UPDATED**
- **Status**: ✅ Operational - Verified working (USDT, WBTC tested)
- **ChainBalanceManager**: 0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A ⚠️ **NEW DEPLOYMENT**

## Recent Fixes (2024-12-19)

- **Fixed Arbitrum Sepolia mailbox**: Changed from `0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766` to `0x8DF6aDE95d25855ed0FB927ECD6a1D5Bb09d2145`
- **Deployed new ChainBalanceManager**: `0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A` with correct mailbox
- **Verified cross-chain deposits**: USDT and WBTC successfully bridged to Rari
- **Security enhancement**: All RPC endpoints moved to environment variables

## Deployment Files

- `rari.json` - Rari testnet deployments (host chain)
- `appchain.json` - Appchain testnet deployments  
- `rise-sepolia.json` - Rise Sepolia deployments
- `arbitrum-sepolia.json` - Arbitrum Sepolia deployments

## Testing Cross-Chain Deposits & Withdrawals

To test how deposits and withdrawals work across chains, use these example scripts:

### Cross-Chain Deposit Flow
```bash
# 1. Deposit from Appchain to Rari
forge script script/TestDeposit.s.sol:TestDeposit --rpc-url ${APPCHAIN_ENDPOINT} --broadcast --legacy

# 2. Check if tokens were minted on Rari  
forge script script/CheckBalance.s.sol:CheckBalance --rpc-url ${RARI_ENDPOINT} --legacy
```

### Cross-Chain Withdrawal Flow
```bash
# 1. Withdraw from Rari back to source chain
forge script script/TestWithdraw.s.sol:TestWithdraw --rpc-url ${RARI_ENDPOINT} --broadcast --legacy

# 2. Verify tokens burned on Rari and received on source chain
forge script script/CheckBalance.s.sol:CheckBalance --rpc-url ${APPCHAIN_ENDPOINT} --legacy
```

### Key Interactions Required

**For Deposits:**
1. **Source Chain**: Call `ChainBalanceManager.deposit(token, amount)` 
2. **Destination Chain**: BalanceManager receives cross-chain message and mints real ERC20 tokens
3. **Result**: User gets tradeable ERC20 tokens on destination chain

**For Withdrawals:**
1. **Destination Chain**: Call `BalanceManager.withdraw(token, amount, destinationChain)`
2. **Source Chain**: ChainBalanceManager receives message and releases original tokens
3. **Result**: ERC20 tokens burned on destination, original tokens released on source

### Contract Addresses to Interact With

- **Source Chains (Appchain, Arbitrum Sepolia, Rise Sepolia)**: Use `ChainBalanceManager` address
- **Destination Chain (Rari)**: Use `BalanceManager` proxy address
- **Token Contracts**: Mock tokens on source chains, real ERC20 synthetic tokens on Rari

## Deployed Contracts Summary

### Rari Testnet (Chain ID: 1918988905) - Destination Chain

| Contract | Type | Address | Purpose |
|----------|------|---------|---------|
| **BalanceManager** | BeaconProxy | `0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5` | Cross-chain message handling, V2 minting |
| **PoolManager** | BeaconProxy | `0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b` | AMM liquidity pools and swaps |
| **Router** | BeaconProxy | `0xF38489749c3e65c82a9273c498A8c6614c34754b` | User-facing swap interface |
| **TokenRegistry** | Implementation | `0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E` | Token registration and currency IDs |
| **SyntheticTokenFactory** | Implementation | `0x2594C4ca1B552ad573bcc0C4c561FAC6a87987fC` | Creates synthetic ERC20 tokens |
| **ChainRegistry** | Implementation | `0x0a1Ced1539C9FB81aBdDF870588A4fEfBf461bBB` | Multi-chain configuration |

### Synthetic Tokens (Real ERC20s)
| Token | Address | Type |
|-------|---------|------|
| **gsUSDT** | `0x6fcf28b801C7116cA8b6460289e259aC8D9131F3` | Synthetic USDT |
| **gsWETH** | `0xC7A1777e80982E01e07406e6C6E8B30F5968F836` | Synthetic WETH |
| **gsWBTC** | `0xfAcf2E43910f93CE00d95236C23693F73FdA3Dcf` | Synthetic WBTC |

### Beacon Infrastructure (Admin Only)
| Beacon | Address | Controls |
|--------|---------|----------|
| **BalanceManagerBeacon** | `0xF1A53bC852bB9e139a8200003B55164592695395` | BalanceManager upgrades |
| **PoolManagerBeacon** | `0x6F97F295D78373FE7555Fd809f3Bb5c146cC8CF7` | PoolManager upgrades |
| **RouterBeacon** | `0x00BF70ab9Fb9f330E9Bb66d6E3A11F8Cf51F737a` | Router upgrades |
| **OrderBookBeacon** | `0xa8630B75d92814b79dE1C5A170d00Ef0714b3C28` | OrderBook upgrades |

### Source Chains - ChainBalanceManager Addresses

| Chain | Chain ID | ChainBalanceManager | Purpose |
|-------|----------|-------------------|---------|
| **Appchain Testnet** | 4661 | `0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7` | Deposit initiation |
| **Arbitrum Sepolia** | 421614 | `0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A` | Deposit initiation |
| **Rise Sepolia** | 11155931 | `0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745` | Deposit initiation |

## Cross-Chain Token Mappings

All source chains bridge to synthetic tokens on Rari:

| Source Token | Source Chains | Synthetic Token (Rari) | Address |
|-------------|---------------|----------------------|---------|
| USDT | Appchain, Rise, Arbitrum | gsUSDT | `0x6fcf28b801C7116cA8b6460289e259aC8D9131F3` |
| WETH | Appchain, Rise, Arbitrum | gsWETH | `0xC7A1777e80982E01e07406e6C6E8B30F5968F836` |  
| WBTC | Appchain, Rise, Arbitrum | gsWBTC | `0xfAcf2E43910f93CE00d95236C23693F73FdA3Dcf` |

## Contract Interaction Guide

### For Users/Frontend:
- ✅ **Interact with BeaconProxy addresses** (BalanceManager, PoolManager, Router)
- ✅ **Use Implementation ABIs** (BalanceManagerABI, PoolManagerABI, etc.)
- ❌ **Never call Implementation contracts directly**

### For Admins:
- 🔧 **Use Beacon contracts** for upgrades and configuration
- 🔧 **Monitor Implementation versions** for upgrade tracking

## Security Features

- **RPC Endpoints**: All stored in environment variables for security
- **Hyperlane Integration**: Verified mailbox addresses with contract code
- **Upgradeable Contracts**: Beacon proxy pattern for easy upgrades
- **Cross-Chain Verification**: All deposit flows tested and operational

Each file contains:
```json
{
  "network": "rari",
  "chainId": 1918988905,
  "contracts": {
    "BalanceManager": "0x...",
    "ChainRegistry": "0x...",
    "TokenRegistry": "0x...",
    "SyntheticTokenFactory": "0x...",
    "gsUSDT": "0x...",
    "gsWETH": "0x...",
    "gsWBTC": "0x..."
  },
  "deployedAt": "2024-01-01T00:00:00Z"
}
```
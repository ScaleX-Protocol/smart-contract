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

## Cross-Chain Token Mappings

All source chains bridge to synthetic tokens on Rari:

| Source Token | Source Chains | Synthetic Token (Rari) | Address |
|-------------|---------------|----------------------|---------|
| USDT | Appchain, Rise, Arbitrum | gsUSDT | 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68 |
| WETH | Appchain, Rise, Arbitrum | gsWETH | 0xC7A1777e80982E01e07406e6C6E8B30F5968F836 |  
| WBTC | Appchain, Rise, Arbitrum | gsWBTC | 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF |

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
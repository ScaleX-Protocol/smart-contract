# Deployment Addresses

This directory tracks all deployed contract addresses across different networks.

## Networks

### Rari Testnet (Chain ID: 1918988905)
- **RPC**: https://rari.caff.testnet.espresso.network
- **Domain ID**: 1918988905
- **Mailbox**: 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358

### Appchain Testnet (Chain ID: 4661) 
- **RPC**: https://appchain.caff.testnet.espresso.network
- **Domain ID**: 4661
- **Mailbox**: 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1

### Arbitrum Sepolia (Chain ID: 421614)
- **RPC**: https://sepolia-rollup.arbitrum.io/rpc
- **Domain ID**: 421614
- **Mailbox**: 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766

## Deployment Files

- `rari.json` - Rari testnet deployments (host chain)
- `appchain.json` - Appchain testnet deployments
- `arbitrum-sepolia.json` - Arbitrum Sepolia deployments

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
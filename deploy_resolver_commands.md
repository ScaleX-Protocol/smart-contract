# Deploy Pool Manager Resolver Commands

## Networks Setup

The script automatically detects the network based on `block.chainid` and reads existing deployments:

- **Rari (1918988905)**: Uses `deployments/rari.json`
- **Rise Sepolia (11155931)**: Uses `deployments/11155931.json`  
- **Appchain (4661)**: Uses `deployments/appchain.json`
- **Arbitrum Sepolia (421614)**: Uses `deployments/arbitrum-sepolia.json`

## Deployment Commands

### 1. Deploy to Rari
```bash
# Make sure you have RARI_ENDPOINT in your .env
forge script script/DeployPoolManagerResolver.s.sol --fork-url $RARI_ENDPOINT --broadcast --verify
```

### 2. Deploy to Rise Sepolia
```bash
# Make sure you have RISE_SEPOLIA_ENDPOINT in your .env
forge script script/DeployPoolManagerResolver.s.sol --fork-url $RISE_SEPOLIA_ENDPOINT --broadcast --verify
```

### 3. Deploy to Appchain
```bash
# Make sure you have APPCHAIN_ENDPOINT in your .env
forge script script/DeployPoolManagerResolver.s.sol --fork-url $APPCHAIN_ENDPOINT --broadcast --verify
```

### 4. Deploy to Arbitrum Sepolia
```bash
# Make sure you have ARBITRUM_SEPOLIA_ENDPOINT in your .env
forge script script/DeployPoolManagerResolver.s.sol --fork-url $ARBITRUM_SEPOLIA_ENDPOINT --broadcast --verify
```

## What the Script Does

1. **Auto-detects network** based on chain ID
2. **Reads existing deployments** from the appropriate JSON file
3. **Checks for existing resolver** - skips if already deployed
4. **Finds existing PoolManager** for testing
5. **Deploys PoolManagerResolver** (stateless contract)
6. **Tests functionality** if PoolManager exists
7. **Provides usage instructions**

## For Rari Specifically

Since Rari already has:
- PoolManager: `0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b`
- Active trading pools
- But no resolver in the JSON

The script will:
1. Deploy the resolver
2. Test it with the existing PoolManager
3. Give you the address to add to `rari.json`

## Example Output for Rari
```
========== DEPLOYING POOL MANAGER RESOLVER ==========
Deployer: 0x123...
Network: 1918988905
Detected: Rari Testnet
Reading existing deployments from: deployments/rari.json
Found existing PoolManager at: 0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b
No existing PoolManagerResolver found - proceeding with deployment

Deploying PoolManagerResolver...

=== DEPLOYMENT COMPLETE ===
PoolManagerResolver deployed at: 0xNewResolverAddress

=== TESTING RESOLVER ===
Testing with PoolManager: 0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b
✅ Resolver working - can create pool keys

=== USAGE INSTRUCTIONS ===
Add to deployment JSON:
"PoolManagerResolver": "0xNewResolverAddress"
```

## Manual JSON Update

After deployment, add to `deployments/rari.json`:
```json
{
  "contracts": {
    "PoolManagerResolver": "0xYourNewResolverAddress",
    // ... existing contracts
  }
}
```
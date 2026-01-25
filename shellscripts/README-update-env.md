# Update Environment Configuration Script

## Overview

The `update-env.sh` script automates the process of updating contract addresses across multiple projects after a deployment. It updates configuration files in:

1. **clob-indexer** - Indexer environment files
2. **mm-bot** - Market maker bot environment files
3. **frontend** - Frontend contract configuration

## Usage

### Basic Usage

```bash
./shellscripts/update-env.sh <chain-id> [deployment-output-file]
```

### Interactive Mode

Enter contract addresses manually:

```bash
./shellscripts/update-env.sh 84532
```

The script will prompt you for each contract address.

### Parse from Deployment Log

Automatically extract addresses from deployment output:

```bash
./shellscripts/update-env.sh 84532 deployment.log
```

## Supported Chains

| Chain ID | Chain Name     | Config Files Updated  |
| -------- | -------------- | --------------------- |
| 84532    | base-sepolia   | `.env.base-sepolia`   |
| 1116     | core-chain     | `.env.core-chain`     |
| 5003     | mantle-sepolia | `.env.mantle-sepolia` |
| 11155111 | sepolia        | `.env.sepolia`        |
| 1        | mainnet        | `.env.mainnet`        |
| 31337    | local          | `.env.local`          |
| 31338    | anvil          | `.env.anvil`          |

## Contract Addresses Updated

### Required Addresses

- **BalanceManager** - Core balance management contract
- **ScaleXRouter** - Main router contract
- **PoolManager** - Pool management contract

### Optional Addresses

- **Faucet** - Test token faucet (testnet only)
- **LendingManager** - Lending protocol contract
- **Oracle** - Price oracle contract
- **TokenRegistry** - Token registry contract

### Automatic START_BLOCK Detection

- **START_BLOCK** - Auto-detected from `deployments/<chain-id>.json`
- Used by indexer to determine blockchain scanning start point
- Falls back to manual input if not found in deployment file
- Updates: `START_BLOCK`, `SCALEX_CORE_DEVNET_START_BLOCK`, `FAUCET_START_BLOCK`

## Files Updated

### 1. Indexer Environment (`../clob-indexer/ponder/.env.<chain-name>`)

Updates:

- `POOLMANAGER_CONTRACT_RARI_ADDRESS`
- `BALANCEMANAGER_CONTRACT_RARI_ADDRESS`
- `ScaleXROUTER_CONTRACT_RARI_ADDRESS`
- `LENDINGMANAGER_CONTRACT_ADDRESS` (optional)
- `ORACLE_CONTRACT_ADDRESS` (optional)
- `TOKENREGISTRY_CONTRACT_ADDRESS` (optional)
- `START_BLOCK` (auto-detected from deployment JSON)
- `SCALEX_CORE_DEVNET_START_BLOCK` (auto-detected)
- `FAUCET_START_BLOCK` (auto-detected)

### 2. MM-Bot Environment (`../mm-bot/.env.<chain-name>`)

Updates:

- `PROXY_POOL_MANAGER`
- `PROXY_GTX_ROUTER`
- `PROXY_BALANCE_MANAGER`

### 3. Frontend Config (`/Users/renaka/gtx/frontend/apps/web/src/configs/contracts.ts`)

Updates the contract addresses for the specified chain ID in the TypeScript configuration.

## Examples

### Example 1: Update Base Sepolia after deployment

```bash
# Run deployment
make deploy network=base_sepolia > deployment.log

# Update all configs
./shellscripts/update-env.sh 84532 deployment.log
```

### Example 2: Update Core Chain manually

```bash
./shellscripts/update-env.sh 1116

# Enter addresses when prompted:
# BalanceManager address: 0xe0A7B4952CC52B11634B1813630CFcaa342c4176
# ScaleXRouter address: 0xb18ee780254Ba127Ac32c09afbB88de45E36cFfC
# PoolManager address: 0x8bf3AEBA32723Bbd8e8f7c66ceC95d14c544E760
# ...
```

### Example 3: Pipe deployment output directly

```bash
make deploy network=base_sepolia 2>&1 | tee deployment.log && ./shellscripts/update-env.sh 84532 deployment.log
```

## Safety Features

1. **Backups**: Creates timestamped backups of all modified files

   - Format: `.env.base-sepolia.backup.20260108_194500`

2. **Confirmation**: Prompts for confirmation before making changes

3. **Validation**: Checks for required addresses before proceeding

4. **Error Handling**: Safe failure modes with descriptive error messages

## Workflow Integration

### After Deployment

```bash
# 1. Deploy contracts
make deploy network=base_sepolia | tee deployment.log

# 2. Update environments
./shellscripts/update-env.sh 84532 deployment.log

# 3. Review changes
git diff ../clob-indexer/ponder/.env.base-sepolia
git diff ../mm-bot/.env.base-sepolia
git diff /Users/renaka/gtx/frontend/apps/web/src/configs/contracts.ts

# 4. Test configurations
cd ../clob-indexer && npm run dev
cd ../mm-bot && npm run start
cd /Users/renaka/gtx/frontend && npm run dev

# 5. Commit changes
git add .
git commit -m "chore: update contract addresses for base-sepolia deployment"
```

## Troubleshooting

### Chain ID not found

```bash
Error: Unknown chain ID: 12345
```

**Solution**: Add the chain ID to the `CHAIN_ID_TO_NAME` mapping in the script.

### File not found

```bash
Warning: File not found: ../clob-indexer/ponder/.env.new-chain
Create new file? (y/n):
```

**Solution**: Confirm to create a new file or update the path.

### Missing required addresses

```bash
Error: Required addresses missing (BalanceManager, ScaleXRouter, PoolManager)
```

**Solution**: Ensure all three required addresses are provided.

## Adding New Chains

To add support for a new chain:

1. Edit `shellscripts/update-env.sh`
2. Add to `CHAIN_ID_TO_NAME` mapping:

```bash
declare -A CHAIN_ID_TO_NAME=(
    # ... existing chains
    ["12345"]="new-chain-name"
)
```

3. Create corresponding `.env` files in indexer and mm-bot projects
4. Test the update script with the new chain ID

## Related Scripts

- `deploy.sh` - Main deployment script
- `validate-deployment.sh` - Validates deployed contracts
- `populate-data.sh` - Populates initial data after deployment

## Maintenance

When adding new contract types:

1. Update the `get_contract_addresses()` function to parse new addresses
2. Add update logic in `update_indexer_env()`, `update_mmbot_env()`, or `update_frontend_config()`
3. Update this README with the new contract information

# Agent Infrastructure Deployment Guide

## Overview

The deployment script (`deploy.sh`) includes **full AI Agent infrastructure deployment** as Phase 5, using upgradeable ERC-8004 contracts.

---

## What Gets Deployed (Phase 5)

### Agent Infrastructure (Upgradeable)

**ERC-8004 Registries (UUPS Proxies):**
- ✅ `IdentityRegistry` - Manages agent identities as NFTs
- ✅ `ReputationRegistry` - Tracks agent reputation and feedback
- ✅ `ValidationRegistry` - Handles agent validation tasks

**Core Agent Contracts:**
- ✅ `PolicyFactory` - Creates and manages agent policies
- ✅ `AgentRouter` - Routes trades through agents with policy enforcement (Model B only)

**Implementation:**
```
script/deployments/DeployPhase5.s.sol
```

**All registries use UUPS upgradeable proxy pattern for production use.**

---

## Usage

### Basic Deployment

```bash
# Deploy complete system including agent infrastructure
bash shellscripts/deploy.sh
```

This will deploy:
1. **Phases 1-4:** Core DEX + Lending
2. **Phase 5:** Upgradeable Agent Infrastructure (ERC-8004)

### With Verification (Testnet/Mainnet)

```bash
# Deploy to Base Sepolia with Etherscan verification
SCALEX_CORE_RPC="https://sepolia.base.org" \
ETHERSCAN_API_KEY="your_key" \
bash shellscripts/deploy.sh
```

### Local Development

```bash
# Deploy to local node
SCALEX_CORE_RPC="http://localhost:8545" \
bash shellscripts/deploy.sh
```

---

## Deployment Output

### Successful Deployment

```
=== PHASE 5: AI AGENT INFRASTRUCTURE DEPLOYMENT ===

Step 1: Deploying IdentityRegistry (ERC-8004 Upgradeable)...
[OK] IdentityRegistry Implementation: 0x...
[OK] IdentityRegistry Proxy: 0x...
[OK] IdentityRegistry initialized

Step 2: Deploying ReputationRegistry (ERC-8004 Upgradeable)...
[OK] ReputationRegistry Implementation: 0x...
[OK] ReputationRegistry Proxy: 0x...
[OK] ReputationRegistry initialized

Step 3: Deploying ValidationRegistry (ERC-8004 Upgradeable)...
[OK] ValidationRegistry Implementation: 0x...
[OK] ValidationRegistry Proxy: 0x...
[OK] ValidationRegistry initialized

Step 4: Deploying PolicyFactory...
[OK] PolicyFactory deployed: 0x...

Step 5: Deploying AgentRouter...
[OK] AgentRouter deployed: 0x...

✅ Phase 5 AI Agent Infrastructure deployment completed successfully

Agent Infrastructure deployed successfully:
  📋 Core Contracts:
    - PolicyFactory: 0x...
    - AgentRouter: 0x...
  🔐 ERC-8004 Registries (Upgradeable):
    - IdentityRegistry: 0x...
    - ReputationRegistry: 0x...
    - ValidationRegistry: 0x...
```

---

## Deployment File

After successful deployment, all addresses are saved to:

```
deployments/<chain-id>.json
```

### Example Content

```json
{
  "IdentityRegistry": "0x...",
  "IdentityImplementation": "0x...",
  "ReputationRegistry": "0x...",
  "ReputationImplementation": "0x...",
  "ValidationRegistry": "0x...",
  "ValidationImplementation": "0x...",
  "PolicyFactory": "0x...",
  "AgentRouter": "0x...",
  ...
}
```

---

## Authorizations (Automatic)

Phase 5 deployment **automatically authorizes AgentRouter** in all required contracts:

1. ✅ **PolicyFactory** - For policy enforcement
2. ✅ **BalanceManager** - For fund management
3. ✅ **LendingManager** - For borrow/repay operations
4. ✅ **PoolManager** - For trading operations

**Previous authorization issues are now fixed!** See `/docs/AUTHORIZATION_CHECKLIST.md` for details.

---

## Verification

### Post-Deployment Checks

The script automatically verifies:

1. ✅ PolicyFactory address is not zero
2. ✅ AgentRouter address is not zero
3. ✅ IdentityRegistry address is not zero
4. ✅ ReputationRegistry address is not zero
5. ✅ ValidationRegistry address is not zero
6. ✅ All authorizations completed

### Manual Verification

```bash
# Read deployed addresses
CHAIN_ID=$(cast chain-id --rpc-url $SCALEX_CORE_RPC)
cat deployments/${CHAIN_ID}.json | jq '.'

# Verify IdentityRegistry
cast call <IdentityRegistry> "totalSupply()" --rpc-url $SCALEX_CORE_RPC

# Verify AgentRouter has correct PolicyFactory
cast call <AgentRouter> "policyFactory()" --rpc-url $SCALEX_CORE_RPC
```

---

## Upgrade Path

Since deployment uses UUPS proxies, you can upgrade implementations:

### Upgrade IdentityRegistry

```bash
forge script script/upgrades/UpgradeIdentityRegistry.s.sol \
  --rpc-url $SCALEX_CORE_RPC \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### Upgrade ReputationRegistry

```bash
forge script script/upgrades/UpgradeReputationRegistry.s.sol \
  --rpc-url $SCALEX_CORE_RPC \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### Upgrade ValidationRegistry

```bash
forge script script/upgrades/UpgradeValidationRegistry.s.sol \
  --rpc-url $SCALEX_CORE_RPC \
  --broadcast \
  --private-key $PRIVATE_KEY
```

---

## Troubleshooting

### Error: "Deployment file not found"

**Cause:** Phases 1-4 haven't been deployed yet.

**Solution:**
```bash
# Deploy all phases
bash shellscripts/deploy.sh
```

### Error: "PoolManager address is zero"

**Cause:** Phase 2 deployment failed.

**Solution:**
```bash
# Check deployment file
cat deployments/<chain-id>.json | jq '.PoolManager'

# Re-deploy if needed
bash shellscripts/deploy.sh
```

### Error: "Agent Infrastructure deployment failed"

**Cause:** Could be gas issues, RPC problems, or contract compilation errors.

**Solution:**
```bash
# 1. Check gas settings
FORGE_GAS_LIMIT=30000000 bash shellscripts/deploy.sh

# 2. Enable slow mode (for public RPCs)
FORGE_SLOW_MODE="true" bash shellscripts/deploy.sh

# 3. Check compiler
forge build --force
```

---

## What's Next?

After successful deployment:

1. ✅ **Agent infrastructure is deployed**
2. → **Test the marketplace model:**
   ```bash
   forge script script/VerifyMarketplaceModelB.s.sol \
     --rpc-url $SCALEX_CORE_RPC \
     --broadcast
   ```
3. → **Create policies** using PolicyFactory
4. → **Register agents** using IdentityRegistry
5. → **Authorize agents** using AgentRouter.authorize()
6. → **Build marketplace frontend**

### Documentation

- `/docs/marketplace/` - Complete marketplace documentation
- `/docs/marketplace/CLEAN_MODEL_B_ONLY.md` - Model B implementation
- `/docs/marketplace/SIMPLIFIED_API.md` - API reference

### Verification Script

```bash
# Verify complete marketplace flow
forge script script/VerifyMarketplaceModelB.s.sol \
  --rpc-url $SCALEX_CORE_RPC \
  --broadcast \
  -vvvv
```

---

## Agent Infrastructure Details

### IdentityRegistry (ERC-8004)
- **Purpose:** Agent identity as NFT
- **Pattern:** UUPS upgradeable proxy
- **Features:** Mint agent NFTs, transfer ownership, query agents

### ReputationRegistry (ERC-8004)
- **Purpose:** Track agent performance and feedback
- **Pattern:** UUPS upgradeable proxy
- **Features:** Submit feedback, query reputation, calculate scores

### ValidationRegistry (ERC-8004)
- **Purpose:** Validation tasks and proof submission
- **Pattern:** UUPS upgradeable proxy
- **Features:** Request validation, submit proofs, verify agents

### PolicyFactory
- **Purpose:** Create and manage agent policies
- **Features:** Template-based policies, custom configurations, policy enforcement

### AgentRouter
- **Purpose:** Execute trades through agents
- **Model:** Model B only (agent-based authorization)
- **Features:**
  - `registerAgentExecutor()` - Developer registers executor
  - `authorize()` - User authorizes strategy agent
  - `revoke()` - User revokes authorization
  - `executeLimitOrder()` - Execute trades with policy enforcement
  - `executeBorrow()` - Lending operations
  - All trading/lending functions

---

## Summary

**The deploy.sh script includes:**

✅ Full agent infrastructure deployment (Phase 5)
✅ Upgradeable ERC-8004 contracts (UUPS pattern)
✅ PolicyFactory for agent policies
✅ AgentRouter with Model B authorization
✅ Automatic verification
✅ Production-ready deployment

**Quick start:**
```bash
# Deploy everything
bash shellscripts/deploy.sh

# Verify marketplace model
forge script script/VerifyMarketplaceModelB.s.sol \
  --rpc-url $SCALEX_CORE_RPC \
  --broadcast
```

**Ready to deploy!** 🚀

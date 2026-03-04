# ERC-8004 Canonical Registry Migration + Agent Listing

**Date**: 2026-03-04
**Status**: Brainstorm
**Author**: AI-assisted

## What We're Building

Migrate our ERC-8004 agent system from custom-deployed registries to the **canonical ERC-8004 registries** so agents appear on [8004scan.io](https://testnet.8004scan.io/), and enhance our platform's agent listing capabilities.

### Problem Statement

Our project deployed **custom registry instances** at non-canonical addresses:
- Custom IdentityRegistry: `0xC2A65565d9E4D901B80a38872688B23B2F8d0975` (7 agents registered)
- Custom ReputationRegistry: `0xc62a83231635e32f12A451D141670Af746716808`
- Custom ValidationRegistry: `0xecC6FC85d5008344D0d0B38BA0d26Ce9CA8b396F`

8004scan indexes the **canonical registries** at vanity addresses:
- Canonical IdentityRegistry: `0x8004A818BFB912233c491871b3d84c89A494BD9e` (10+ agents from other projects)
- Canonical ReputationRegistry: `0x8004B663056A597Dffe9eCcC1965A193B7388713`
- Canonical ValidationRegistry: `0x8004Cb1BF31DAf7788923b405b754f57acEB4272`

Result: our 7 agents are invisible on 8004scan.

### Existing Infrastructure (from scalex-8004 reference)

The `scalex-8004` project already has:
- **Cloudflare R2 bucket** at `agents.scalex.money` serving metadata (e.g., `agents.scalex.money/agents/1/metadata.json`)
- **Agent0 SDK** integration for ERC-8004 registration (`src/register.ts`)
- **Per-agent metadata files** in `assets/agents/{id}/metadata.json`
- **8 agent instances** deployed via Docker + Traefik on Base Sepolia

However, the scalex-8004 agents are also registered on the **custom registry** (not canonical), and the metadata format is **not ERC-8004 compliant** (missing `type` field and `services` array, using non-standard `service_url` and `attributes`).

### Additional Issue

The `AgentRouter` has a **broken reputation interface**: its `IERC8004Reputation` uses `submitFeedback()` with enums, but the actual `ReputationRegistryUpgradeable` uses `giveFeedback()` with `int128 value`. This must be fixed as part of migration.

## Why This Approach

**Full migration to canonical registries** was chosen over dual-registration because:
1. Single source of truth - no dual identity management
2. Full 8004scan integration including reputation visibility
3. Cleaner architecture long-term
4. Reputation from trading activity flows naturally to 8004scan

## Key Decisions

### 1. Migration Strategy: Full Migration to Canonical
- Point AgentRouter to canonical `0x8004A...` IdentityRegistry
- Re-register all 7 agents on canonical registry
- Update indexer to watch canonical addresses
- Post trading reputation to canonical `0x8004B...` ReputationRegistry
- Agent IDs will change (new NFTs on canonical = new token IDs)

### 2. Agent Metadata: Update Existing R2 Files
- R2 bucket at `agents.scalex.money` already exists and serves metadata
- **Update metadata format** to be ERC-8004 compliant:
  ```json
  {
    "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
    "name": "Smart Money Tracker",
    "description": "Monitors whale wallet activity...",
    "image": "https://agents.scalex.money/agents/1/avatar.png",
    "services": [
      { "name": "a2a", "endpoint": "https://agent.scalex.money/1" },
      { "name": "mcp", "endpoint": "https://agent.scalex.money/1/mcp" }
    ],
    "x402Support": true,
    "active": true,
    "supportedTrust": ["reputation"]
  }
  ```
- Follow [8004scan best practices](https://best-practices.8004scan.io/docs/README.html)

### 3. Reputation: Post to Canonical Registry
- Fix `IERC8004Reputation` interface to match canonical `giveFeedback()` signature
- AgentRouter's `_recordTradeToReputation()` will call canonical ReputationRegistry
- Trading activity (swaps, borrows, repays) generates on-chain reputation visible on 8004scan

### 4. Frontend + API: Update Existing Agent Pages
- Frontend at `../frontend` already has 3 agent pages, 16 components, 11 hooks
- Update contract addresses in config to point to canonical registries
- Update metadata fetching to handle updated URI format
- Update indexer to watch canonical registry events

## Scope of Changes

### Contract Changes (clob-dex)

1. **Fix `IERC8004Reputation` interface** (`src/ai-agents/interfaces/IERC8004Reputation.sol`)
   - Replace `submitFeedback()` with `giveFeedback(uint256 agentId, int128 value, uint8 valueDecimals, string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash)`
   - Remove enum-based feedback types

2. **Update `AgentRouter`** (`src/ai-agents/AgentRouter.sol`)
   - Update `_recordTradeToReputation()` to call `giveFeedback()` with proper parameters
   - Map trade types to tag strings (e.g., tag1="trade", tag2="swap")
   - Change identity/reputation registry addresses to canonical ones (via upgrade)

3. **Upgrade Script** - Deploy new AgentRouter implementation pointing to canonical registries

4. **Re-registration Script** - Register all 7 agents on canonical `0x8004A...` IdentityRegistry with ERC-8004 compliant metadata URIs

### Metadata Changes (scalex-8004 / R2)

1. **Update metadata JSON format** - Add `type`, `services`, `x402Support`, `supportedTrust` fields
2. **Upload updated files** to existing R2 bucket at `agents.scalex.money`

### Indexer Changes (clob-indexer)

1. **Update ponder config** - Change IdentityRegistry address from `0xC2A6...` to `0x8004A...`
2. **Add ReputationRegistry indexing** - Watch canonical `0x8004B...` for `NewFeedback` events
3. **Add ValidationRegistry indexing** - Watch canonical `0x8004C...` for events
4. **Update agent_registry schema** - Handle new token IDs from canonical registry
5. **Update API** - Ensure `/api/agents` reads from canonical registry data

### Frontend Changes (frontend)

1. **Update contract addresses** - Point to canonical registries in config
2. **Verify agent pages work** - Existing pages should work with minimal changes since metadata format is similar

### scalex-8004 Changes

1. **Update registration script** - Remove `registryOverrides` to use canonical defaults, or set canonical addresses
2. **Update Agent Docs.md** - Reflect new canonical registry addresses

## Assumptions

- Canonical ERC-8004 registries are already deployed and initialized on Base Sepolia (verified: `0x8004A...` has code and 10+ agents).
- Old custom registries will remain deployed but unused after migration. No cleanup needed.
- Agent token IDs will change since they're new NFTs on canonical. All references (indexer, frontend, AgentRouter policies) must use new IDs.
- The R2 bucket at `agents.scalex.money` is already configured with proper CORS and public access.

## Migration Steps (Ordered)

1. Update metadata JSON files to ERC-8004 compliant format
2. Upload updated metadata to R2 (`agents.scalex.money`)
3. Fix reputation interface in contracts
4. Re-register all 7 agents on canonical `0x8004A...` IdentityRegistry (note new token IDs)
5. Create upgrade script for AgentRouter with canonical registry addresses
6. Deploy upgraded AgentRouter (brief downtime during cutover)
7. Re-authorize agents on AgentRouter with new token IDs
8. Update indexer config to watch canonical addresses
9. Update frontend contract addresses
10. Update scalex-8004 registration script
11. Verify agents appear on testnet.8004scan.io

## Resolved Questions

- **Hosting**: Reuse existing R2 bucket at `agents.scalex.money` (already set up)
- **Reputation**: Post to canonical registry via fixed `giveFeedback()` interface
- **Frontend**: Update existing pages (already comprehensive), no new pages needed
- **Historical data**: Start fresh on canonical. Old data stays in custom registries and indexer DB.
- **Agent ownership**: Same wallets re-register on canonical. All private keys available.
- **Downtime**: Acceptable during migration.

## Open Questions

None - all questions resolved.

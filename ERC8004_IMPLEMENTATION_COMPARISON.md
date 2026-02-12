# ERC-8004 Implementation Comparison

## Official Specification vs Our Mock Implementation

### Source
- Official Spec: [EIP-8004: Trustless Agents](https://eips.ethereum.org/EIPS/eip-8004)
- Official Contracts: [erc-8004/erc-8004-contracts](https://github.com/erc-8004/erc-8004-contracts)

---

## Identity Registry Comparison

### ✅ What We Have (MockERC8004Identity.sol)

```solidity
// Basic ERC-721 functionality
function ownerOf(uint256 tokenId) external view returns (address)
function tokenURI(uint256 tokenId) external view returns (string memory)
function mint(address to, uint256 tokenId, string calldata metadataURI) external
function mintAuto(address to, string calldata metadataURI) external returns (uint256)
function exists(uint256 tokenId) external view returns (bool)
function transferFrom(address from, address to, uint256 tokenId) external
function balanceOf(address owner) external view returns (uint256)

// Agent wallet (our addition)
function mintWithWallet(address to, uint256 tokenId, address agentWallet, string calldata metadataURI) external
function getAgentWallet(uint256 tokenId) external view returns (address)
function setAgentWallet(uint256 tokenId, address agentWallet) external
```

### ❌ What We're Missing (From Official Spec)

```solidity
// Registration (should auto-increment and return ID)
function register(string agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId)
function register(string agentURI) external returns (uint256 agentId)
function register() external returns (uint256 agentId)

// URI Management
function setAgentURI(uint256 agentId, string calldata newURI) external

// Agent Wallet with Signature Verification ← CRITICAL!
function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external
function unsetAgentWallet(uint256 agentId) external

// Metadata Storage (Key-Value)
function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory)
function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external

// Events
event Registered(uint256 indexed agentId, string agentURI, address indexed owner)
event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy)
event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue)
```

---

## Critical Differences

### 1. Agent Wallet Security ⚠️

**Official Spec (Secure):**
```solidity
// Requires cryptographic signature to change agent wallet
function setAgentWallet(
    uint256 agentId,
    address newWallet,
    uint256 deadline,
    bytes calldata signature  // EIP-712 or ERC-1271 signature
) external
```

**Our Mock (Insecure):**
```solidity
// Anyone can call (no signature verification!)
function setAgentWallet(uint256 tokenId, address agentWallet) external {
    require(_exists[tokenId], "Token does not exist");
    require(agentWallet != address(0), "Invalid agent wallet");
    // Missing: require(msg.sender == _owners[tokenId] || msg.sender == admin)

    _agentWallets[tokenId] = agentWallet;
}
```

**Why This Matters:**
- Official: Agent wallet can only be changed with signed approval (prevents unauthorized changes)
- Ours: Missing access control (security vulnerability!)

### 2. Agent Wallet Behavior on Transfer 🔄

**Official Spec:**
```
Upon token transfer (NFT ownership change):
- Agent wallet is AUTOMATICALLY CLEARED
- New owner must re-verify and set new agent wallet
- Prevents old owner's agent from accessing new owner's funds
```

**Our Mock:**
```solidity
function transferFrom(address from, address to, uint256 tokenId) external override {
    require(_exists[tokenId], "Token does not exist");
    require(_owners[tokenId] == from, "Not token owner");
    require(to != address(0), "Transfer to zero address");

    _balances[from]--;
    _balances[to]++;
    _owners[tokenId] = to;

    // Missing: Clear agent wallet!
    // Should add: delete _agentWallets[tokenId];

    emit AgentTransferred(tokenId, from, to);
}
```

**Security Risk:**
- If NFT is sold, old owner's agent wallet can still execute for new owner!
- Critical vulnerability!

### 3. Registration Flow 📝

**Official Spec:**
```solidity
// Auto-increments agent ID
uint256 agentId = register("ipfs://...");  // Returns 1
uint256 agentId2 = register("ipfs://...");  // Returns 2

// Agent wallet defaults to owner
address wallet = getAgentWallet(agentId);  // Returns owner address
```

**Our Mock:**
```solidity
// Manual token ID assignment
mint(owner, 1, "ipfs://...");
mintWithWallet(owner, 1, agentWallet, "ipfs://...");

// Agent wallet must be manually set
// No default behavior
```

### 4. Metadata System 🗂️

**Official Spec:**
```solidity
// Flexible key-value storage
setMetadata(agentId, "strategy", "momentum-trading");
setMetadata(agentId, "riskLevel", "moderate");
setMetadata(agentId, "maxAUM", "1000000");

bytes memory strategy = getMetadata(agentId, "strategy");
```

**Our Mock:**
```solidity
// No metadata system
// Only stores URI string
```

---

## Feature Comparison Table

| Feature | Official Spec | Our Mock | Status |
|---------|---------------|----------|--------|
| **Core ERC-721** | ✓ | ✓ | ✅ Complete |
| **URI Storage** | ✓ (setAgentURI) | ✓ (tokenURI) | ✅ Complete |
| **Auto-increment ID** | ✓ (register) | ✓ (mintAuto) | ✅ Complete |
| **Agent Wallet Storage** | ✓ | ✓ | ✅ Complete |
| **Agent Wallet Security** | ✓ (signature) | ❌ | 🚨 Critical Gap |
| **Agent Wallet Clear on Transfer** | ✓ | ❌ | 🚨 Critical Gap |
| **Agent Wallet Default (owner)** | ✓ | ❌ | ⚠️ Missing |
| **Metadata Key-Value** | ✓ | ❌ | ⚠️ Missing |
| **URI Updates** | ✓ (setAgentURI) | ❌ | ⚠️ Missing |
| **Upgradeability** | ✓ | ❌ | ⚠️ Missing |
| **Event Emissions** | ✓ | Partial | ⚠️ Incomplete |

---

## Security Issues in Our Mock

### 🚨 Critical Issues

1. **No Agent Wallet Authorization**
   ```solidity
   // Current: Anyone can change agent wallet!
   function setAgentWallet(uint256 tokenId, address agentWallet) external {
       _agentWallets[tokenId] = agentWallet;  // No checks!
   }
   ```

2. **Agent Wallet Not Cleared on Transfer**
   ```solidity
   // Current: Old owner's agent can still access new owner's funds!
   function transferFrom(address from, address to, uint256 tokenId) external {
       _owners[tokenId] = to;
       // Missing: delete _agentWallets[tokenId];
   }
   ```

### ⚠️ Missing Features

3. **No Signature Verification (EIP-712/ERC-1271)**
   - Can't prove agent wallet is authorized by owner
   - No protection against unauthorized changes

4. **No Metadata System**
   - Can't store agent capabilities, strategies, etc.
   - Limited extensibility

5. **No Upgradeability**
   - Can't fix bugs or add features without redeployment

---

## Recommendation

### Option A: Use Official Contracts ✅ (STRONGLY RECOMMENDED)

**Why:**
1. ✅ **Security:** Proper signature verification (EIP-712/ERC-1271)
2. ✅ **Safety:** Auto-clears agent wallet on transfer
3. ✅ **Standard:** Fully ERC-8004 compliant
4. ✅ **Extensibility:** Metadata key-value system
5. ✅ **Upgradeable:** Can fix issues without redeployment
6. ✅ **Battle-tested:** Used by other projects
7. ✅ **Maintained:** Regular updates from core team

**Action:**
```bash
# Install official contracts
forge install erc-8004/erc-8004-contracts

# Use in deployment
import {IdentityRegistryUpgradeable} from "@erc-8004/contracts/IdentityRegistryUpgradeable.sol";
```

### Option B: Fix Our Mock Implementation ⚠️ (NOT RECOMMENDED)

**What needs to be added:**
1. Agent wallet signature verification (EIP-712)
2. Auto-clear agent wallet on transfer
3. Access control for setAgentWallet
4. Metadata key-value system
5. URI update functions
6. Upgradeability pattern
7. Complete event emissions
8. Security audit

**Effort:** High
**Risk:** High (security vulnerabilities)
**Maintenance:** Ongoing

---

## Implementation Plan (Recommended: Option A)

### Phase 1: Install Official Contracts

```bash
cd /Users/renaka/gtx/clob-dex
forge install erc-8004/erc-8004-contracts
```

### Phase 2: Update Remappings

```solidity
// foundry.toml or remappings.txt
@erc8004/=lib/erc-8004-contracts/contracts/
```

### Phase 3: Update DeployPhase5.s.sol

```solidity
// Old (Mock)
import {MockERC8004Identity} from "@scalexagents/mocks/MockERC8004Identity.sol";

// New (Official)
import {IdentityRegistryUpgradeable} from "@erc8004/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "@erc8004/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "@erc8004/ValidationRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Deploy with proxy pattern
IdentityRegistryUpgradeable identityImpl = new IdentityRegistryUpgradeable();
ERC1967Proxy identityProxy = new ERC1967Proxy(
    address(identityImpl),
    abi.encodeWithSelector(IdentityRegistryUpgradeable.initialize.selector)
);
IdentityRegistryUpgradeable identityRegistry = IdentityRegistryUpgradeable(address(identityProxy));
```

### Phase 4: Update AgentRouter

```solidity
// No changes needed!
// AgentRouter already uses IERC8004Identity interface
// Official contracts implement the same interface
```

### Phase 5: Update Test Scripts

```solidity
// Old: mintWithWallet(owner, tokenId, agentWallet, uri)
identityRegistry.mintWithWallet(owner, 1, agentWallet, "ipfs://...");

// New: register() + setAgentWallet() with signature
uint256 agentId = identityRegistry.register("ipfs://...");

// Generate signature for agent wallet
bytes32 digest = keccak256(abi.encodePacked(
    "\x19\x01",
    domainSeparator,
    keccak256(abi.encode(SET_AGENT_WALLET_TYPEHASH, agentId, agentWallet, deadline))
));
(uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
bytes memory signature = abi.encodePacked(r, s, v);

identityRegistry.setAgentWallet(agentId, agentWallet, deadline, signature);
```

### Phase 6: Keep Mock for Testing Only

```
src/ai-agents/
├── mocks/
│   ├── MockERC8004Identity.sol      ← Keep for unit tests
│   ├── MockERC8004Reputation.sol
│   └── MockERC8004Validation.sol
└── (use official contracts for production)
```

---

## Migration Checklist

- [ ] Install official ERC-8004 contracts
- [ ] Update imports in DeployPhase5.s.sol
- [ ] Add proxy deployment pattern
- [ ] Update test scripts with signature generation
- [ ] Test on local network
- [ ] Deploy to Base Sepolia
- [ ] Verify contracts on Basescan
- [ ] Update documentation
- [ ] Archive old Mock implementations

---

## Conclusion

**We MUST use official ERC-8004 contracts for production.**

Our Mock implementation has critical security vulnerabilities:
1. 🚨 No agent wallet authorization
2. 🚨 Agent wallet not cleared on transfer
3. ⚠️ Missing signature verification
4. ⚠️ No metadata system

The official contracts are:
- ✅ Production-ready
- ✅ Security-audited
- ✅ Fully ERC-8004 compliant
- ✅ Used by other projects
- ✅ Maintained by core team

**Next Step:** Install official contracts and update deployment scripts.

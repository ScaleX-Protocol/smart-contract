# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Build & Development Commands

### Core Commands

```bash
# Build project with full info
make build
# OR
forge clean && forge build --build-info --build-info-path out/build-info/

# Compile contracts
make compile
# OR
forge compile

# Run all tests
make test
# OR
forge test

# Run single test
forge test --match-test <test_name> -vvv

# Run test contract
forge test --match-contract <contract_name> -vvv

# Lint/format code
make lint
# OR
forge fmt

# Generate ABI files
make generate-abi
# OR
node script/utils/generateTsAbis.js

# Deploy contracts
make deploy

# Deploy and verify
make deploy-verify

# Run specific test contracts
forge test --match-contract OrderMatchingTest -v
forge test --match-contract ChainBalanceManagerTest -v
forge test --match-contract LendingManagerTest -v
```

### Network-Specific Commands

```bash
# Set network via environment or make parameter
NETWORK=scalex_core_devnet make deploy
# OR
make deploy network=scalex_core_devnet

# Cross-chain operations
make test-cross-chain-deposit network=scalex_side_devnet
make test-local-deposit network=scalex_core_devnet
```

## Code Style Guidelines

### Solidity Style

- **Pragma Version**: Use `^0.8.26` for main contracts, `^0.8.0` for libraries/interfaces
- **License**: `UNLICENSED` for all contracts
- **Indentation**: 4 spaces (no tabs)
- **Line Length**: 120 characters max
- **Quote Style**: Double quotes for strings

### Import Organization

```solidity
// 1. External dependencies (OpenZeppelin, etc.)
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

// 2. Internal interfaces
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";

// 3. Internal libraries
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";

// 4. Storage contracts
import {OrderBookStorage} from "./storages/OrderBookStorage.sol";
```

### Contract Structure

```solidity
// 1. SPDX license identifier
// 2. Pragma
// 3. Imports (organized as above)
// 4. Contract definition
// 5. Using statements
// 6. Constructor (with unsafe constructor comment for upgradeable)
// 7. Modifiers
// 8. External functions
// 9. Public functions
// 10. Internal functions
// 11. Private functions
```

### Naming Conventions

- **Contracts**: PascalCase (e.g., `OrderBook`, `BalanceManager`)
- **Functions**: camelCase (e.g., `placeLimitOrder`, `calculatePrice`)
- **Variables**: camelCase for local/state variables, snake_case for constants
- **Interfaces**: Prefix with `I` (e.g., `IOrderBook`, `IBalanceManager`)
- **Errors**: PascalCase describing the error (e.g., `UnauthorizedRouter`, `InsufficientBalance`)
- **Events**: PascalCase with past tense (e.g., `OrderPlaced`, `OrderExecuted`)

### Storage Patterns

- Use dedicated storage contracts for upgradeable contracts
- Follow the storage contract pattern: `contract ContractNameStorage { struct Storage { ... } }`
- Access storage via `getStorage()` function

### Upgradeable Contracts

- Use OpenZeppelin upgradeable contracts
- Include `/// @custom:oz-upgrades-unsafe-allow constructor` comment
- Initialize with `__Ownable_init()`, `__ReentrancyGuard_init()`, etc.
- Use `initializer` modifier on `initialize` functions

### Error Handling

- Define custom errors in interfaces
- Use descriptive error messages
- Include relevant context in error parameters
- Prefer custom errors over revert strings for gas efficiency

### Testing Guidelines

- Test files should end with `.t.sol`
- Use `Test` contract from `forge-std/Test.sol`
- Arrange-Act-Assert pattern in tests
- Use descriptive test function names
- Include setup functions for common test state

### Gas Optimization

- Use `uint256` instead of smaller uint types unless storage is critical
- Pack structs when possible
- Use events for off-chain data instead of storage
- Consider view functions for read-only operations

### Security Best Practices

- Use `ReentrancyGuardUpgradeable` for external calls
- Implement proper access control (onlyOwner, onlyRouter, etc.)
- Validate all inputs in public/external functions
- Use Checks-Effects-Interactions pattern
- Include emergency pause mechanisms where appropriate

## Project Structure

```
src/
├── core/           # Core trading logic
│   ├── interfaces/ # Core interfaces
│   ├── libraries/  # Internal libraries
│   ├── storages/   # Storage contracts for upgradeability
│   └── upgrade/    # V2 upgrade contracts
├── token/          # Token contracts
├── yield/          # Lending protocol
├── incentives/     # Voting escrow and gauge system
├── faucet/         # Testnet faucet
├── marketmaker/    # Market maker contracts
├── mocks/          # Mock contracts for testing
└── interfaces/     # External interfaces

test/
├── core/           # Core functionality tests
├── integration/    # Cross-component tests
├── incentives/    # Incentive system tests
└── yield/          # Lending protocol tests

script/
├── deployments/   # Deployment scripts
├── configuration/ # Configuration scripts
├── trading/       # Trading operation scripts
├── lending/       # Lending operation scripts
└── utils/         # Utility scripts
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

Always use 'bd' for task tracking

<!-- bv-agent-instructions-v1 -->

---

## Beads Workflow Integration

This project uses [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) for issue tracking. Issues are stored in `.beads/` and tracked in git.

### Essential Commands

```bash
# View issues (launches TUI - avoid in automated sessions)
bv

# CLI commands for agents (use these instead)
bd ready              # Show issues ready to work (no blockers)
bd list --status=open # All open issues
bd show <id>          # Full issue details with dependencies
bd create --title="..." --type=task --priority=2
bd update <id> --status=in_progress
bd close <id> --reason="Completed"
bd close <id1> <id2>  # Close multiple issues at once
bd sync               # Commit and push changes
```

### Workflow Pattern

1. **Start**: Run `bd ready` to find actionable work
2. **Claim**: Use `bd update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `bd close <id>`
5. **Sync**: Always run `bd sync` at session end

### Key Concepts

- **Dependencies**: Issues can block other issues. `bd ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers, not words)
- **Types**: task, bug, feature, epic, question, docs
- **Blocking**: `bd dep add <issue> <depends-on>` to add dependencies

### Session Protocol

**Before ending any session, run this checklist:**

```bash
git status              # Check what changed
git add <files>         # Stage code changes
bd sync                 # Commit beads changes
git commit -m "..."     # Commit code
bd sync                 # Commit any new beads changes
git push                # Push to remote
```

### Best Practices

- Check `bd ready` at session start to find available work
- Update status as you work (in_progress → closed)
- Create new issues with `bd create` when you discover tasks
- Use descriptive titles and set appropriate priority/type
- Always `bd sync` before ending session

<!-- end-bv-agent-instructions -->

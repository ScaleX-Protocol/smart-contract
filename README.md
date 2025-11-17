# 🚀 ScaleX - Unified CLOB DEX-Lending Protocol

> 💰 Unified CLOB DEX-Lending protocol with automated yield generation and portfolio-backed borrowing

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status](https://img.shields.io/badge/Status-OPERATIONAL-brightgreen)](README.md)

## 🌟 Vision

A revolutionary DeFi protocol that seamlessly combines CLOB trading with integrated lending. ScaleX enables **zero-capital trading** through auto-borrow/auto-repay mechanisms while users earn yield on deposits. Place limit orders without owning assets and let the system automatically handle borrowing and repayment. ScaleX brings together the best of CEX performance, DEX trustlessness, and innovative lending integration in a single protocol.

## 🎯 **System Status: OPERATIONAL** 

The ScaleX unified CLOB DEX-Lending protocol is **fully deployed and working**!

- 📊 **CLOB trading**: Operational with advanced order book
- 💰 **Auto-yield generation**: Deposits automatically lent for yield
- 🏦 **Portfolio-backed borrowing**: Borrow against your deposited assets
- 🔒 **Liquidity management**: Unified liquidity across lending and trading

📋 [View detailed documentation](docs/ARCHITECTURE_OVERVIEW.md)

## 🏗️ ScaleX Protocol Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   SCALEX PROTOCOL                           │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │   CLOB Engine   │  │  Lending Engine │  │   Oracle     │ │
│  │                 │  │                 │  │   System     │ │
│  │ • OrderBook     │  │ • LendingManager│  │ • PriceFeed  │ │
│  │ • SCALEXRouter     │  │ • YieldTracker  │  │ • TokenReg   │ │
│  │ • PoolManager   │  │ • Liquidator    │  │              │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘  │
│           │                       │                       │
│           └───────────────────────┼───────────────────────┘
│                                   │
│  ┌─────────────────────────────────┼─────────────────────────┐
│  │           BALANCEMANAGER       │                         │
│  │  ┌─────────────────────────────┴─────────────────────────┐│
│  │  │           USER ACCOUNTS & PORTFOLIOS                 ││
│  │  │ • Auto-yield on deposits                              ││
│  │  │ • Portfolio-backed borrowing                         ││
│  │  │ • Unified balance management                          ││
│  │  └───────────────────────────────────────────────────────┘│
│  └───────────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────────┘
```

### **Core Components**
- **BalanceManager**: Unified account management with auto-yield and borrowing capabilities
- **OrderBook**: High-performance CLOB with Red-Black Tree for efficient order matching
- **SCALEXRouter**: User-friendly interface for trading and lending operations
- **LendingManager**: Automated lending protocol with yield generation
- **Oracle**: Real-time price feeds for accurate asset valuation and liquidation

## 💎 Core Features

### 💰 Automated Lending & Yield Generation

- **Auto-Lend on Deposit**: All deposited assets are automatically lent out to generate yield
- **Real-time Yield Tracking**: Continuously accrue and track yield earnings for all depositors
- **Dynamic Interest Rates**: Market-driven interest rates based on supply and demand
- **Portfolio-Backed Borrowing**: Borrow against your deposited portfolio with automated health monitoring

### 🚀 Revolutionary CLOB-Lending Integration

- **🔄 Auto-Borrow for Limit Orders**: Place limit orders without owning the assets! ScaleX automatically borrows from the lending protocol when your order executes
- **⚡ Auto-Repay on Order Match**: When your sell orders are filled, ScaleX automatically repays your debt from the lending protocol using the proceeds
- **📈 Zero-Capital Trading**: Start trading immediately without needing to pre-fund your account - just maintain sufficient collateral
- **🎯 Smart Debt Management**: Automatically optimize borrowing and repayment to minimize interest costs while maximizing trading opportunities

### 🗃️ Optimized Order Management

- **Packed Order Structure**
  ```solidity
  struct Order {
      address user;         // User who placed the order
      uint48 id;            // Unique identifier
      uint48 next;          // Next order in queue
      uint128 quantity;     // Total order quantity
      uint128 filled;       // Filled amount
      uint128 price;        // Order price
      uint48 prev;          // Previous order in queue
      uint48 expiry;        // Expiration timestamp
      Status status;        // Current status
      OrderType orderType;  // LIMIT or MARKET
      Side side;            // BUY or SELL
  }
  ```

- **Order Queue Management**: Double-linked list implementation for FIFO order execution
  ```solidity
  struct OrderQueue {
      uint256 totalVolume;  // Total volume at price level
      uint48 orderCount;    // Number of orders
      uint48 head;          // First order in queue
      uint48 tail;          // Last order in queue
  }
  ```

### 🔑 Efficient Data Structures

- **Price Level Indexing**: Red-Black Tree for O(log n) price lookup
  ```solidity
  mapping(Side => RedBlackTreeLib.Tree) private priceTrees;
  ```

- **Order Storage**: Optimized for gas efficiency and quick access
  ```solidity
  mapping(uint48 => Order) private orders;
  mapping(Side => mapping(uint128 => OrderQueue)) private orderQueues;
  ```

### 💰 Unified Balance & Portfolio Management

- **Balance Tracking**: Per-user balance tracking for multiple currencies
  ```solidity
  mapping(address => mapping(uint256 => uint256)) private balanceOf;
  ```

- **Auto-Yield Integration**: Deposits automatically enter lending pools
  ```solidity
  mapping(address => mapping(uint256 => uint256)) private depositedBalance;
  mapping(address => mapping(uint256 => uint256)) private earnedYield;
  ```

- **Portfolio-Backed Borrowing**: Borrow against your total portfolio value
  ```solidity
  mapping(address => mapping(uint256 => uint256)) private borrowedAmount;
  mapping(address => uint256) private healthFactor;
  ```

- **Order Lock System**: Balance locking prevents double-spending
  ```solidity
  mapping(address => mapping(address => mapping(uint256 => uint256))) private lockedBalanceOf;
  ```

## ⛽ Gas Optimization Techniques

1. **Optimized Storage Access**
    - Packed struct layouts reduce storage operations
    - Minimized SSTOREs through strategic updates
    - Efficient order data retrieval patterns

2. **Advanced Data Structures**
    - Red-Black Tree for price levels (O(log n) operations)
    - Double-linked list for order queue management
    - Automatic price level cleanup for unused levels

3. **Balance Management**
    - Lock-and-execute pattern prevents unnecessary transfers
    - Direct balance transfers between users within the contract

## 🔒 Security Features

1. **Balance Protection**
    - Order amount locking before placement
    - Atomicity in balance operations
    - Authorization checks for operators

2. **Lending Protocol Security**
    - Automated health factor monitoring
    - Real-time liquidation protection
    - Over-collateralization requirements for borrowing
    - Interest rate risk management

3. **Order Integrity**
    - Order ownership validation
    - Expiration handling
    - Time-in-force constraints enforcement

4. **Access Control**
    - Router authorization for order operations
    - Owner-only configuration changes
    - Operator-limited permissions

## 📊 Market Order Execution

1. **Efficient Matching**
    - Best price traversal using Red-Black Tree
    - Volume-based execution across price levels
    - Auto-cancellation of unfilled IOC/FOK orders

2. **Multi-Currency Support**
    - Automatic currency conversion for trades
    - Multi-hop swap routing
    - Intermediary currency support

## 🔄 Order Lifecycle Management

1. **Order Placement**
    - Validation of parameters (price, quantity, trading rules)
    - Balance locking
    - Insertion into appropriate price level queue

2. **Order Matching**
    - FIFO execution against opposite side orders
    - Partial fills tracking
    - Balance transfers between counterparties

3. **Order Cancellation/Expiration**
    - Removal from order queue
    - Balance unlocking
    - Automatic price level cleanup

The implementation ensures efficient order management while maintaining robust security measures and optimizing for gas usage across all operations.

## 📜 Contract Addresses

The contract addresses are stored in JSON files under the `deployments/<chain_id>.json`. Example folder:

- 🔗 **Local Development**: `deployments/31337.json` (Anvil network)
- 🌐 **SCALEX Dev Network**: `deployments/31337.json` (SCALEX Development)
- 🚀 **Rise Network**: `deployments/11155931.json` (Rise Sepolia)
- 🌟 **Pharos Network**: `deployments/50002.json` (Pharos Devnet)

To access contract addresses for a specific network:
1. Locate the appropriate JSON file for your target network
2. Parse the JSON to find the contract you need (e.g., `SCALEXRouter`, `PoolManager`)
3. Use the address in your frontend or for contract interactions

## 📜 Contract ABIs

The contract ABIs are stored in the `deployed-contracts/deployedContracts.ts` file.

**Note**: This file is automatically generated using the `generate-abi` target in the `Makefile`. Ensure you run the appropriate Makefile command to update or regenerate the ABIs when needed.

## Foundry Smart Contract Setup Guide

This document provides a comprehensive guide for setting up, deploying, and upgrading smart contracts using Foundry. Follow the instructions below to get started.

---

## Prerequisites

Before proceeding, ensure you have the following installed:

- [Foundry](https://book.getfoundry.sh/)
- Node.js (required for generating ABI files)
- A compatible Ethereum wallet for broadcasting transactions
- A `.env` file to configure network and wallet details

---

## Installation and Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Great-Trading-eXperience/clob-dex.git
   cd clob-dex
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

3. Duplicate the `.env.example` file in the root directory, rename it to `.env`, and set the required variables.

## 🚀 Quick Start - Zero-Capital Trading with Auto-Borrow

### **Step 1: Deposit Collateral (Auto-Yield Enabled)**
```solidity
// Deposit USDT - automatically starts earning yield
balanceManager.deposit(
    USDT_ADDRESS,  // Your token address
    amount,
    recipient
);
// Yield automatically starts accruing!
```

### **Step 2: Place Limit Orders WITHOUT Owning Assets! 🚀**
```solidity
// Place a BUY order for WETH without having USDT!
// ScaleX auto-borrows when your order is matched
router.placeLimitOrder(
    WETH,      // Asset you want to buy
    USDT,      // Asset you're selling (will be auto-borrowed)
    price,     // Your desired price
    quantity,  // Amount of WETH you want
    true       // enableAutoBorrow: true
);
```

### **Step 4: Watch the Magic Happen! ✨**

- 🔄 **Order Matched**: ScaleX automatically borrows funds to fulfill your order
- 💰 **Order Filled**: When your sell orders execute, debt is auto-repaid from proceeds
- 📊 **Interest Optimization**: System minimizes borrowing time to reduce interest costs
- 🔒 **Risk Management**: Health factor monitoring ensures safe operation at all times

## 🎯 Why ScaleX is Revolutionary

### **Traditional DEX vs ScaleX**
| Feature | Traditional DEX | ScaleX |
|---------|----------------|--------|
| **Require Assets to Trade** | Yes | **No - Auto-Borrow!** |
| **Yield on Deposits** | No | **Auto-Yield** |
| **Manual Debt Management** | N/A | **Auto-Repay** |
| **Capital Efficiency** | Low | **Maximum** |

### **Use Cases Enabled**
- 🚀 **Zero-Capital Trading**: Start trading immediately with just collateral
- 📈 **Leverage Trading**: Borrow to amplify positions without manual management
- ⚡ **Flash Trading**: Execute arbitrage without pre-funding
- 🔄 **Automated Strategies**: Let the system handle borrowing/repayment while you focus on prices

### **Contract Addresses**

| Network | Contract | Description |
|---------|----------|-------------|
| **Local** | BalanceManager | `0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5` |
| **Local** | SCALEXRouter | `0xF38489749c3e65c82a9273c498A8c6614c34754b` |
| **Local** | OrderBook | `0x...` |
| **Local** | LendingManager | `0x...` |
| **Local** | Oracle | `0x...` |

---

## Deployment Guide

For complete deployment instructions, see **[📋 DEPLOYMENT.md](docs/DEPLOYMENT.md)**

### Quick Deployment
```bash
# Deploy and validate the ScaleX protocol
make validate-deployment           # Validate core deployment
```

### Single Network Deployment
To deploy contracts to a single network:
```bash
make deploy network=<network_name>
```
- Example:
  ```bash
  make deploy network=riseSepolia
  ```

### Deploying and Verifying Contracts
To deploy and verify contracts:
```bash
make deploy-verify network=<network_name>
```

---

## Data Population

For populating the system with demo trading data, see **[📊 DATA_POPULATION.md](docs/DATA_POPULATION.md)**

### Quick Data Population
```bash
# Populate system with traders, liquidity, and trading activity
make validate-data-population
```

---

## Mock Contracts Deployment

### Deploying Mocks
To deploy mock contracts, use:
```bash
make deploy-mocks network=<network_name>
```

### Deploying and Verifying Mocks
To deploy and verify mock contracts:
```bash
make deploy-mocks-verify network=<network_name>
```

### Fill Mock Order Book
To populate the ETH/USDC order book with sample orders:
```bash
make fill-orderbook network=<network_name>
```

## Contract Upgrades

### Upgrading Contracts
To upgrade contracts:
```bash
make upgrade network=<network_name>
```

### Upgrading and Verifying Contracts
To upgrade and verify contracts:
```bash
make upgrade-verify network=<network_name>
```

---

## Additional Commands

- **Compile Contracts**
  ```bash
  make compile
  ```

- **Run Tests**
  ```bash
  make test
  ```

- **Lint Code**
  ```bash
  make lint
  ```

- **Generate ABI Files**
  ```bash
  make generate-abi
  ```

- **Help**
  Display all Makefile targets:
  ```bash
  make help
  ```

---

## Notes

- Replace `<network_name>` with the desired network (e.g., `arbitrumSepolia`, `mainnet`).
- Ensure your `.env` file is correctly configured to avoid deployment errors.
- Use the `help` target to quickly review all available commands:
  ```bash
  make help
  ```

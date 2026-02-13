# Multi-Agent Setup with Isolated Funds

## 🎯 **Solution: One Wallet Per Agent**

Instead of fixing BalanceManager, use **different wallets for different agents**.

### Simple Architecture:

```
Wallet 1 (Private Key 1) → Agent #1 → BalanceManager[Wallet1] = 1,000 IDRX ✅
Wallet 2 (Private Key 2) → Agent #2 → BalanceManager[Wallet2] = 5,000 IDRX ✅
Wallet 3 (Private Key 3) → Agent #3 → BalanceManager[Wallet3] = 500 IDRX ✅

Each wallet = separate BalanceManager account = isolated funds!
```

---

## 🚀 **Quick Start**

### 1. Generate Private Keys

```bash
# Generate 3 private keys
cast wallet new
# Save the private key (0x...)
# Repeat 3 times for 3 agents
```

### 2. Add to `.env`

```bash
# Agent private keys (DIFFERENT for each agent)
AGENT1_PRIVATE_KEY=0x1111111111111111111111111111111111111111111111111111111111111111
AGENT2_PRIVATE_KEY=0x2222222222222222222222222222222222222222222222222222222222222222
AGENT3_PRIVATE_KEY=0x3333333333333333333333333333333333333333333333333333333333333333

# Network config
SCALEX_CORE_RPC=https://base-sepolia.infura.io/v3/YOUR_KEY
QUOTE_SYMBOL=IDRX
```

### 3. Fund the Wallets

Each wallet needs quote tokens:
```bash
# Get wallet addresses
AGENT1=$(cast wallet address --private-key $AGENT1_PRIVATE_KEY)
AGENT2=$(cast wallet address --private-key $AGENT2_PRIVATE_KEY)
AGENT3=$(cast wallet address --private-key $AGENT3_PRIVATE_KEY)

# Transfer tokens to each wallet
# Agent 1: 1,000 IDRX
# Agent 2: 5,000 IDRX
# Agent 3: 500 IDRX
```

### 4. Create Agents

```bash
./shellscripts/create-multiple-agents.sh
```

This will:
- ✅ Mint agent identity for each wallet
- ✅ Create custom policy per agent
- ✅ Deposit funds to each wallet's BalanceManager account

---

## 📊 **Fund Isolation**

### How It Works:

```
BalanceManager Storage:
├─ balances[Wallet1][IDRX] = 1,000  ← Agent #1's funds
├─ balances[Wallet2][IDRX] = 5,000  ← Agent #2's funds
└─ balances[Wallet3][IDRX] = 500    ← Agent #3's funds

When Agent #1 trades:
  ├─ Uses Wallet1's private key
  ├─ Spends from balances[Wallet1]
  └─ Cannot touch Wallet2 or Wallet3's funds ✅

When Agent #2 trades:
  ├─ Uses Wallet2's private key
  ├─ Spends from balances[Wallet2]
  └─ Cannot touch Wallet1 or Wallet3's funds ✅
```

---

## 🔑 **Trading with Different Agents**

### Trade with Agent #1 (Conservative):

```bash
# Set private key to Agent 1's
export PRIVATE_KEY=$AGENT1_PRIVATE_KEY

# Place order (uses Agent 1's funds only)
./shellscripts/test-agent-order.sh
```

### Trade with Agent #2 (Aggressive):

```bash
# Switch to Agent 2's private key
export PRIVATE_KEY=$AGENT2_PRIVATE_KEY

# Place order (uses Agent 2's funds only)
./shellscripts/test-agent-order.sh
```

### Trade with Agent #3 (Test):

```bash
# Switch to Agent 3's private key
export PRIVATE_KEY=$AGENT3_PRIVATE_KEY

# Place order (uses Agent 3's funds only)
./shellscripts/test-agent-order.sh
```

---

## 📋 **Agent Profiles**

### Agent #1: Conservative Trader
```yaml
Wallet: Derived from AGENT1_PRIVATE_KEY
Capital: 1,000 IDRX
Policy:
  - Max Daily Volume: 5,000 IDRX
  - Max Drawdown: 10%
  - Min Health Factor: 1.3x
  - Max Slippage: 3%
  - Cooldown: 2 minutes
Strategy: Low-risk, stable returns
```

### Agent #2: Aggressive Trader
```yaml
Wallet: Derived from AGENT2_PRIVATE_KEY
Capital: 5,000 IDRX
Policy:
  - Max Daily Volume: 50,000 IDRX
  - Max Drawdown: 25%
  - Min Health Factor: 1.25x
  - Max Slippage: 5%
  - Cooldown: 30 seconds
Strategy: High-risk, high-reward
```

### Agent #3: Test Agent
```yaml
Wallet: Derived from AGENT3_PRIVATE_KEY
Capital: 500 IDRX
Policy:
  - Max Daily Volume: 2,000 IDRX
  - Max Drawdown: 5%
  - Min Health Factor: 1.35x
  - Max Slippage: 2%
  - Cooldown: 5 minutes
Strategy: Safe testing environment
```

---

## 🔍 **Verification**

### Check Agent Balances:

```bash
# Load addresses
AGENT1=$(cast wallet address --private-key $AGENT1_PRIVATE_KEY)
AGENT2=$(cast wallet address --private-key $AGENT2_PRIVATE_KEY)
AGENT3=$(cast wallet address --private-key $AGENT3_PRIVATE_KEY)

BALANCE_MANAGER=$(cat deployments/84532.json | jq -r '.BalanceManager')
IDRX=$(cat deployments/84532.json | jq -r '.IDRX')

# Check balances (should be isolated)
echo "Agent 1 Balance:"
cast call $BALANCE_MANAGER "getBalance(address,address)" $AGENT1 $IDRX --rpc-url $SCALEX_CORE_RPC

echo "Agent 2 Balance:"
cast call $BALANCE_MANAGER "getBalance(address,address)" $AGENT2 $IDRX --rpc-url $SCALEX_CORE_RPC

echo "Agent 3 Balance:"
cast call $BALANCE_MANAGER "getBalance(address,address)" $AGENT3 $IDRX --rpc-url $SCALEX_CORE_RPC
```

### Verify Policies:

```bash
POLICY_FACTORY=$(cat deployments/84532.json | jq -r '.PolicyFactory')
IDENTITY=$(cat deployments/84532.json | jq -r '.IdentityRegistry')

# Get agent IDs
AGENT1_ID=$(cast call $IDENTITY "tokenOfOwnerByIndex(address,uint256)" $AGENT1 0 --rpc-url $SCALEX_CORE_RPC)
AGENT2_ID=$(cast call $IDENTITY "tokenOfOwnerByIndex(address,uint256)" $AGENT2 0 --rpc-url $SCALEX_CORE_RPC)
AGENT3_ID=$(cast call $IDENTITY "tokenOfOwnerByIndex(address,uint256)" $AGENT3 0 --rpc-url $SCALEX_CORE_RPC)

# Check policies
cast call $POLICY_FACTORY "getPolicy(address,uint256)" $AGENT1 $AGENT1_ID --rpc-url $SCALEX_CORE_RPC
```

---

## 📊 **Tracking P&L**

### Per-Agent Performance:

```bash
# Script to track each agent's performance
cat > track-agents.sh << 'EOF'
#!/bin/bash

AGENT1=$(cast wallet address --private-key $AGENT1_PRIVATE_KEY)
AGENT2=$(cast wallet address --private-key $AGENT2_PRIVATE_KEY)
AGENT3=$(cast wallet address --private-key $AGENT3_PRIVATE_KEY)

BALANCE_MANAGER=$(cat deployments/84532.json | jq -r '.BalanceManager')
IDRX=$(cat deployments/84532.json | jq -r '.IDRX')

echo "=== Agent Performance ==="
echo ""

# Agent 1
BAL1=$(cast call $BALANCE_MANAGER "getBalance(address,address)" $AGENT1 $IDRX --rpc-url $SCALEX_CORE_RPC)
BAL1_DEC=$(echo "scale=2; $BAL1 / 1000000" | bc)
PNL1=$(echo "scale=2; $BAL1_DEC - 1000" | bc)
echo "Agent 1 (Conservative):"
echo "  Initial: 1,000 IDRX"
echo "  Current: $BAL1_DEC IDRX"
echo "  P&L: $PNL1 IDRX"
echo ""

# Agent 2
BAL2=$(cast call $BALANCE_MANAGER "getBalance(address,address)" $AGENT2 $IDRX --rpc-url $SCALEX_CORE_RPC)
BAL2_DEC=$(echo "scale=2; $BAL2 / 1000000" | bc)
PNL2=$(echo "scale=2; $BAL2_DEC - 5000" | bc)
echo "Agent 2 (Aggressive):"
echo "  Initial: 5,000 IDRX"
echo "  Current: $BAL2_DEC IDRX"
echo "  P&L: $PNL2 IDRX"
echo ""

# Agent 3
BAL3=$(cast call $BALANCE_MANAGER "getBalance(address,address)" $AGENT3 $IDRX --rpc-url $SCALEX_CORE_RPC)
BAL3_DEC=$(echo "scale=2; $BAL3 / 1000000" | bc)
PNL3=$(echo "scale=2; $BAL3_DEC - 500" | bc)
echo "Agent 3 (Test):"
echo "  Initial: 500 IDRX"
echo "  Current: $BAL3_DEC IDRX"
echo "  P&L: $PNL3 IDRX"
EOF

chmod +x track-agents.sh
./track-agents.sh
```

---

## 🎮 **Managing Multiple Agents**

### Quick Switch Script:

```bash
# switch-agent.sh
case $1 in
  1)
    export PRIVATE_KEY=$AGENT1_PRIVATE_KEY
    echo "Switched to Agent 1 (Conservative)"
    ;;
  2)
    export PRIVATE_KEY=$AGENT2_PRIVATE_KEY
    echo "Switched to Agent 2 (Aggressive)"
    ;;
  3)
    export PRIVATE_KEY=$AGENT3_PRIVATE_KEY
    echo "Switched to Agent 3 (Test)"
    ;;
  *)
    echo "Usage: source switch-agent.sh [1|2|3]"
    ;;
esac
```

Usage:
```bash
source switch-agent.sh 1   # Switch to Agent 1
./shellscripts/test-agent-order.sh

source switch-agent.sh 2   # Switch to Agent 2
./shellscripts/test-agent-order.sh
```

---

## ⚠️ **Important Notes**

### ✅ **Pros of This Approach:**
- ✅ **Simple**: No code changes needed
- ✅ **Isolated**: True fund separation
- ✅ **Works Now**: Deploy today
- ✅ **Clear P&L**: Easy to track per-agent

### ⚠️ **Cons:**
- ⚠️ **Key Management**: Need to manage 3+ private keys
- ⚠️ **Gas Costs**: Each wallet pays gas separately
- ⚠️ **Manual Switching**: Need to change env var to switch agents
- ⚠️ **No Shared Liquidity**: Can't pool funds across agents

### 🔐 **Security:**
- Store private keys securely
- Use hardware wallet for production
- Never commit private keys to git
- Consider using a key management system

---

## 🚀 **Production Deployment**

For production with many agents:

### Option 1: Environment Variables (3-5 agents)
```bash
AGENT1_PRIVATE_KEY=...
AGENT2_PRIVATE_KEY=...
AGENT3_PRIVATE_KEY=...
```

### Option 2: JSON Config File (5+ agents)
```json
{
  "agents": [
    {
      "name": "Conservative",
      "privateKey": "0x...",
      "capital": "1000000000",
      "policy": { ... }
    },
    {
      "name": "Aggressive",
      "privateKey": "0x...",
      "capital": "5000000000",
      "policy": { ... }
    }
  ]
}
```

### Option 3: Key Management Service (Production)
- Use AWS KMS, Google Cloud KMS, or similar
- Never store private keys in plaintext
- Rotate keys regularly

---

## 📈 **Scaling to More Agents**

To add Agent #4:

```bash
# 1. Generate new private key
cast wallet new

# 2. Add to .env
AGENT4_PRIVATE_KEY=0x...

# 3. Fund the wallet
# Transfer tokens to new wallet

# 4. Modify CreateMultipleAgents.s.sol
# Add Agent 4 to the agents array

# 5. Run setup
./shellscripts/create-multiple-agents.sh
```

---

## 🎯 **Summary**

**This approach solves the fund isolation problem by:**
- ✅ Using separate wallets (private keys) per agent
- ✅ Each wallet has its own BalanceManager account
- ✅ Natural fund isolation without code changes
- ✅ Works with existing infrastructure

**Trade-offs:**
- Need to manage multiple private keys
- Slight operational complexity
- But: Simple, secure, works today

---

**Ready to set up your isolated agents?**

```bash
# 1. Add private keys to .env
nano .env

# 2. Fund the wallets
# Transfer tokens to each wallet

# 3. Create agents
./shellscripts/create-multiple-agents.sh

# 4. Start trading!
source switch-agent.sh 1
./shellscripts/test-agent-order.sh
```

---

*For long-term solution with virtual sub-accounts, see: [AGENT_ACCOUNT_ARCHITECTURE.md](AGENT_ACCOUNT_ARCHITECTURE.md)*

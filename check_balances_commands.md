# Check Token Balances Script

## Overview

The `CheckTokenBalances.s.sol` script checks:
1. **BalanceManager internal balances** for a specific user
2. **ERC20 wallet balances** for synthetic tokens
3. **Total supply** of synthetic tokens to verify minting
4. **Summary** of which tokens are minted

## Setup

### 1. Set Recipient Address

Edit the constant in `script/CheckTokenBalances.s.sol`:
```solidity
// Set this to the user address you want to check
address constant RECIPIENT_TO_CHECK = 0x1234567890123456789012345678901234567890; // Replace with actual address
```

### 2. Run Commands

#### Check Balances on Rari
```bash
forge script script/CheckTokenBalances.s.sol --fork-url $RARI_ENDPOINT
```

#### Check Balances on Rise Sepolia  
```bash
forge script script/CheckTokenBalances.s.sol --fork-url $RISE_SEPOLIA_ENDPOINT
```

#### Check Balances on Appchain
```bash
forge script script/CheckTokenBalances.s.sol --fork-url $APPCHAIN_ENDPOINT
```

#### Check Balances on Arbitrum Sepolia
```bash
forge script script/CheckTokenBalances.s.sol --fork-url $ARBITRUM_SEPOLIA_ENDPOINT
```

## What It Shows

### Balance Types Explained

1. **BalanceManager balance**: Internal accounting balance in the BalanceManager contract
   - This is what users can trade with
   - Updated when cross-chain deposits are processed

2. **ERC20 wallet balance**: Actual token balance in user's wallet
   - Direct ERC20 token ownership
   - Can be transferred, approved, etc.

3. **Total supply**: Total amount of synthetic tokens minted
   - `> 0` means tokens have been minted somewhere
   - `= 0` means no tokens minted yet

### Example Output
```
========== TOKEN BALANCE CHECKER ==========
Checking balances for recipient: 0x123...
Network: 1918988905
Detected: Rari Testnet
BalanceManager address: 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5

=== BALANCE MANAGER BALANCES ===

Token: gsUSDT at 0x6fcf28b801C7116cA8b6460289e259aC8D9131F3
  BalanceManager balance: 1000000000000000000 (≈1.0)
  ERC20 wallet balance: 0
  Total supply: 5000000000000000000 (≈5.0)
  Status: MINTED

Token: gsWBTC at 0xfAcf2E43910f93CE00d95236C23693F73FdA3Dcf
  BalanceManager balance: 0
  ERC20 wallet balance: 0  
  Total supply: 0
  Status: NOT MINTED

=== SUMMARY ===
Minted synthetic tokens: 1 of 3
Some synthetic tokens are minted, others may not be
```

## Understanding the Results

### Cross-Chain Flow
When users deposit on source chains (like Appchain), the flow is:
1. User deposits real tokens to ChainBalanceManager
2. ChainBalanceManager sends cross-chain message
3. BalanceManager on Rari **mints synthetic tokens to itself**
4. BalanceManager **credits user's internal balance**

So you'll typically see:
- **BalanceManager balance > 0** (user can trade)
- **ERC20 wallet balance = 0** (tokens held by BalanceManager)
- **Total supply > 0** (tokens were minted)

### Direct Minting Flow
If tokens were minted directly to user's wallet:
- **BalanceManager balance = 0** (unless deposited to BalanceManager)
- **ERC20 wallet balance > 0** (user owns tokens directly)
- **Total supply > 0** (tokens were minted)

## Usage Tips

1. **Change recipient address** to check different users
2. **Run on multiple networks** to see cross-chain state
3. **Compare before/after** cross-chain operations
4. **Check BalanceManager balance** to see tradeable amounts
5. **Check total supply** to verify minting is working

## Troubleshooting

- **"Could not read BalanceManager"**: Contract might not be deployed or ABI mismatch
- **"Could not read ERC20 balance"**: Token address might be wrong or not deployed
- **"ERROR - Could not read"**: Network connection or contract issues
- **All balances = 0**: No deposits/minting has occurred yet
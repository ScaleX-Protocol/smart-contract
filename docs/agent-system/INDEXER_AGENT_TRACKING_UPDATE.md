# Indexer Agent Tracking Update Summary

## Overview
Updated the clob-indexer to capture ERC-8004 agent tracking information from all enhanced events.

## Schema Updates (ponder.schema.ts)

### Tables Enhanced with Agent Tracking

All core event tables now include:
```typescript
agentTokenId: t.bigint(), // 0 for non-agent operations
executor: t.hex(), // Address of executor (for agent operations)
```

#### Updated Tables:
1. **orders** - Order placement and matching
2. **deposits** - Token deposits to BalanceManager
3. **withdrawals** - Token withdrawals from BalanceManager
4. **lockEvents** - Balance locking events
5. **unlockEvents** - Balance unlocking events
6. **lendingEvents** - All lending operations (supply, borrow, repay, withdraw, liquidate)

### New Indexes Added

For each table, added indexes for efficient agent queries:
```typescript
agentTokenIdIdx: index().on(table.agentTokenId),
executorIdx: index().on(table.executor),
agentUserIdx: index().on(table.agentTokenId, table.userAddress),
```

Additional indexes for lending events:
```typescript
agentActionIdx: index().on(table.agentTokenId, table.action),
```

## Handler Updates

### 1. orderHelpers.ts
- **createOrderData()**: Added agent tracking fields from event args
  - `agentTokenId: (args as any).agentTokenId ?? BigInt(0)`
  - `executor: (args as any).executor ?? null`

### 2. balanceManagerHandler.ts

#### Updated Functions:
- **handleDeposit()**: Captures agent info for deposits
- **handleWithdrawal()**: Captures agent info for withdrawals
- **handleLock()**: Captures agent info for locks
- **handleUnlock()**: Captures agent info for unlocks
- **recordLendingTransferEvents()**: Updated to accept and store agent parameters

### 3. lendingManagerHandler.ts

#### Updated Functions:
- **handleSupply()**: Captures agent info for supply operations
- **handleBorrow()**: Captures agent info for borrow operations
- **handleRepay()**: Captures agent info for repay operations
- **handleWithdraw()**: Captures agent info for withdraw operations
- **handleLiquidation()**: Captures agent info for liquidation events

## Query Capabilities

The indexer now supports querying:

### Agent Activity Queries
```graphql
# Get all orders placed by a specific agent
query AgentOrders($agentTokenId: BigInt!) {
  orders(where: { agentTokenId: $agentTokenId }) {
    id
    userAddress
    executor
    price
    quantity
    status
    timestamp
  }
}

# Get all lending operations by agent
query AgentLendingActivity($agentTokenId: BigInt!) {
  lendingEvents(where: { agentTokenId: $agentTokenId }) {
    id
    userAddress
    executor
    action
    token
    amount
    timestamp
  }
}

# Get all deposits by a specific executor
query ExecutorDeposits($executor: String!) {
  deposits(where: { executor: $executor }) {
    id
    userAddress
    currency
    amount
    agentTokenId
    timestamp
  }
}
```

### Audit Trail Queries
```graphql
# Complete audit trail for an agent
query AgentAuditTrail($agentTokenId: BigInt!) {
  orders(where: { agentTokenId: $agentTokenId }) { ... }
  deposits(where: { agentTokenId: $agentTokenId }) { ... }
  withdrawals(where: { agentTokenId: $agentTokenId }) { ... }
  lendingEvents(where: { agentTokenId: $agentTokenId }) { ... }
}
```

## Benefits

1. **Complete Audit Trail**: Every agent action is tracked with both agent ID and executor address
2. **Performance**: Indexed queries for fast agent activity lookups
3. **Compliance**: Full ERC-8004 compliance for AI agent operations
4. **Backward Compatible**: Non-agent operations have agentTokenId=0 and executor=null
5. **Comprehensive Coverage**: All core operations (trading, deposits, lending) tracked

## Migration Notes

- Existing data will have `agentTokenId: null` and `executor: null`
- New events will populate these fields automatically
- Indexes will be created on first sync after schema update
- No data loss - fully backward compatible

## Testing Recommendations

1. Deploy contracts with agent tracking
2. Run populate-data.sh with agent operations
3. Query indexer for agent data
4. Verify all agent operations are captured correctly


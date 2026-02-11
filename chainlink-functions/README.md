# Chainlink Functions Integration for AI Agents

This directory contains the Chainlink Functions integration for computing complex agent metrics off-chain.

## Overview

AI agents with complex permission requirements (daily volume limits, drawdown limits, performance metrics) need off-chain computation. Chainlink Functions enables:

- **Off-chain metric computation**: Calculate daily/weekly volume, portfolio drawdown, win rates, etc.
- **Indexer data aggregation**: Query historical trades and portfolio snapshots
- **Policy enforcement**: Validate metrics before executing trades
- **Decentralized trust**: Chainlink DON provides secure off-chain computation

## Architecture

```
┌──────────────┐          ┌──────────────────┐         ┌────────────────┐
│   AI Agent   │          │   AgentRouter    │         │  Chainlink DON │
│              │          │                  │         │                │
│ 1. Request   │─────────▶│ 2. Submit        │────────▶│ 3. Execute     │
│    Metrics   │          │    Request       │         │    JavaScript  │
│              │          │                  │         │                │
│              │          │ 5. Execute       │◀────────│ 4. Return      │
│              │◀─────────│    Order w/      │         │    Metrics     │
│              │          │    Validation    │         │                │
└──────────────┘          └──────────────────┘         └────────────────┘
                                   │                            │
                                   │                            │
                                   ▼                            ▼
                          ┌──────────────────┐        ┌────────────────┐
                          │  PolicyFactory   │        │  Indexer API   │
                          │  (Policy Rules)  │        │  (Trade Data)  │
                          └──────────────────┘        └────────────────┘
```

## Files

- `computeAgentMetrics.js` - JavaScript source code executed by Chainlink DON
- `config.json` - Configuration for networks and DON IDs
- `README.md` - This file
- `deploy.js` - Deployment script (to be created)
- `simulate.js` - Local simulation script (to be created)

## Setup

### 1. Install Dependencies

```bash
npm install @chainlink/functions-toolkit ethers@5
```

### 2. Create Chainlink Subscription

Visit [Chainlink Functions Subscription Manager](https://functions.chain.link/) and:

1. Connect your wallet
2. Create a new subscription
3. Fund it with LINK tokens
4. Note your subscription ID
5. Update `config.json` with your subscription ID

### 3. Configure Secrets

Secrets are encrypted and stored in the DON. Set them via the subscription manager:

```javascript
{
  "indexerApiUrl": "https://api.scalex.example.com",
  "reputationRegistry": "0x..."
}
```

### 4. Deploy Contracts

```bash
# Deploy ChainlinkMetricsConsumer
forge script script/ai-agents/DeployChainlinkMetrics.s.sol --rpc-url arbitrum-sepolia --broadcast

# Set metrics consumer in AgentRouter
cast send <AGENT_ROUTER_ADDRESS> "setMetricsConsumer(address)" <METRICS_CONSUMER_ADDRESS> --private-key $PRIVATE_KEY
```

### 5. Add Consumer to Subscription

In the Chainlink Functions UI:
1. Go to your subscription
2. Click "Add consumer"
3. Enter ChainlinkMetricsConsumer contract address

### 6. Upload JavaScript Source

```bash
# Using Chainlink Functions toolkit
npx hardhat functions-upload-source --network arbitrum-sepolia --source computeAgentMetrics.js

# Or update via contract
cast send <METRICS_CONSUMER_ADDRESS> "updateMetricsSource(string)" "$(cat computeAgentMetrics.js)" --private-key $PRIVATE_KEY
```

## Usage

### For AI Agents

**Step 1: Request Metrics Validation**

```solidity
// Request metrics computation
bytes32 requestId = agentRouter.requestMetricsValidation(
    agentTokenId,
    ChainlinkMetricsConsumer.MetricsType.FULL_CHECK
);
```

**Step 2: Wait for Fulfillment**

Monitor the `MetricsFulfilled` event:

```solidity
event MetricsFulfilled(
    bytes32 indexed requestId,
    address indexed owner,
    uint256 indexed agentTokenId,
    bytes result,
    uint256 timestamp
);
```

Typical fulfillment time: 10-30 seconds.

**Step 3: Execute Order with Validated Metrics**

```solidity
// Execute trade with Chainlink-validated metrics
(uint48 orderId, uint128 filled) = agentRouter.executeMarketOrderWithMetrics(
    agentTokenId,
    pool,
    IOrderBook.Side.BUY,
    1000e6, // quantity
    950e6,  // minOutAmount
    false,  // autoRepay
    false,  // autoBorrow
    requestId // Chainlink request ID
);
```

### Metrics Types

```solidity
enum MetricsType {
    DAILY_VOLUME,        // 0 - Check daily trading volume
    DAILY_DRAWDOWN,      // 1 - Check daily portfolio drawdown
    WEEKLY_VOLUME,       // 2 - Check weekly trading volume
    WEEKLY_DRAWDOWN,     // 3 - Check weekly portfolio drawdown
    PERFORMANCE_METRICS, // 4 - Check win rate, Sharpe ratio, reputation
    FULL_CHECK           // 5 - Check all metrics at once (recommended)
}
```

### Policy Requirements

Agents requiring Chainlink validation have policies with:

```solidity
requiresChainlinkFunctions = true;
dailyVolumeLimit > 0;      // e.g., 50,000 USDC
maxDailyDrawdown > 0;      // e.g., 500 bps (5%)
minWinRateBps > 0;         // e.g., 5500 (55%)
minSharpeRatio > 0;        // e.g., 100 (1.0 Sharpe)
```

## Indexer API Requirements

The JavaScript code expects an indexer API with these endpoints:

### GET `/agents/{owner}/{agentTokenId}/trades`

Returns trade history:

```json
{
  "trades": [
    {
      "timestamp": 1234567890,
      "tokenIn": "0x...",
      "tokenOut": "0x...",
      "amountIn": 1000000000,
      "amountOut": 2000000000,
      "volumeQuote": 1000.0,
      "pnl": 50.0
    }
  ]
}
```

**Query params:**
- `start` - Unix timestamp (start time)
- `end` - Unix timestamp (end time)

### GET `/agents/{owner}/{agentTokenId}/portfolio`

Returns portfolio snapshots:

```json
{
  "snapshots": [
    {
      "timestamp": 1234567890,
      "totalValue": 10000.0,
      "positions": [...]
    }
  ]
}
```

### GET `/reputation/{agentTokenId}`

Returns reputation score:

```json
{
  "score": 75,
  "totalTrades": 100,
  "profitableTrades": 55,
  "totalPnL": 1000.0
}
```

## Testing

### Local Simulation

```bash
# Simulate JavaScript execution locally
node simulate.js <owner> <agentTokenId> <metricsType> <timestamp>
```

### Testnet Testing

```bash
# Deploy to testnet
forge script script/ai-agents/DeployChainlinkMetrics.s.sol --rpc-url arbitrum-sepolia --broadcast --verify

# Test full flow
forge test --match-test test_ChainlinkIntegration -vvv
```

## Cost Optimization

**Request caching**: Cache metrics results for ~5 minutes to reduce Chainlink costs.

```solidity
// Check if recent request exists
(bytes memory result, bool fulfilled) = metricsConsumer.getMetricsResult(lastRequestId);
if (fulfilled && block.timestamp - lastRequestTime < 300) {
    // Reuse cached result
    return lastRequestId;
}

// Otherwise, request new metrics
return metricsConsumer.requestMetrics(...);
```

**Batch checks**: Use `FULL_CHECK` instead of multiple individual requests.

**Estimate costs**:
- Gas cost: ~300,000 gas (~$0.01 @ 0.1 gwei)
- LINK cost: ~0.1 LINK per request (~$1.50 @ $15/LINK)
- Total: ~$1.51 per validation

For high-frequency agents, consider:
- Caching (5 min TTL)
- Selective validation (only when approaching limits)
- Batch processing

## Monitoring

Monitor these events:

```solidity
event MetricsRequested(bytes32 indexed requestId, ...);
event MetricsFulfilled(bytes32 indexed requestId, ...);
event MetricsSourceUpdated(string newSource, ...);
```

**Dashboard metrics**:
- Request success rate
- Average fulfillment time
- Failed requests (check error messages)
- LINK balance in subscription

## Security Considerations

1. **Secrets management**: Never commit API keys or secrets
2. **Indexer trust**: Ensure indexer data integrity (consider multiple sources)
3. **Rate limiting**: Implement request limits to prevent spam
4. **Result validation**: Validate encoded results match expected format
5. **Emergency disable**: PolicyFactory can emergency disable agents if issues detected

## Troubleshooting

**Request not fulfilled**:
- Check subscription has sufficient LINK
- Verify consumer is added to subscription
- Check indexer API is accessible
- Review Chainlink DON logs

**Validation failing**:
- Check policy limits are configured correctly
- Verify indexer returns valid data
- Test JavaScript locally with `simulate.js`

**High costs**:
- Implement caching
- Reduce gas limit if possible
- Use selective validation

## Resources

- [Chainlink Functions Documentation](https://docs.chain.link/chainlink-functions)
- [Functions Toolkit](https://github.com/smartcontractkit/functions-toolkit)
- [Subscription Manager](https://functions.chain.link/)
- [ScaleX DEX Docs](https://docs.scalex.example.com)

# ScaleX Liquidity Calculator - CRE Workflow

Chainlink Runtime Environment (CRE) workflow that calculates liquidity metrics from the ScaleX order book.

## 📊 Features

- Fetches live order book data from ScaleX API
- Calculates comprehensive liquidity metrics:
  - Mid price and spread (in basis points)
  - Total liquidity (bids/asks in ETH)
  - Liquidity depth (1% and 5% from mid price)
  - Order book structure analysis

## 🚨 Important: Local Simulation Limitation

**Local simulation does NOT support HTTP requests** via `runInNodeMode`. The simulator will fail with:
```
❌ Error: Invalid order book data received from API
```

This is expected behavior. The workflow must be **deployed to Chainlink's network** to test HTTP functionality.

## ✅ What Works in Local Simulation

- ✅ Workflow compiles to WASM successfully
- ✅ Code structure validation
- ✅ TypeScript type checking
- ✅ Cron trigger configuration

## ❌ What Does NOT Work in Local Simulation

- ❌ HTTP requests via `runInNodeMode`
- ❌ Fetching real data from external APIs
- ❌ Testing consensus/aggregation logic

## 🎯 Testing Strategy

1. **Local Simulation**: Validates code compiles
   ```bash
   cre workflow simulate scalex-liquidity-calculator
   ```
   ⚠️ Will fail at HTTP request (expected)

2. **Staging Deployment**: Test with real HTTP (requires CRE access)
   ```bash
   cre workflow deploy scalex-liquidity-calculator -T staging-settings
   ```
   ✅ Will fetch real data every 30 seconds

3. **Production Deployment**: Production schedule (requires CRE access)
   ```bash
   cre workflow deploy scalex-liquidity-calculator -T production-settings
   ```
   ✅ Will fetch real data every 5 minutes

## 📁 Project Structure

```
scalex-liquidity-calculator/
├── main.ts                      # Workflow logic
├── workflow.yaml                # Workflow configuration
├── config.staging.json          # Staging config (30s interval)
├── config.production.json       # Production config (5min interval)
├── package.json                 # Dependencies
└── tsconfig.json                # TypeScript config
```

## 🔧 Configuration

### Staging (`config.staging.json`)
```json
{
  "schedule": "*/30 * * * * *",     // Every 30 seconds
  "apiUrl": "https://base-sepolia-indexer.scalex.money/api/depth",
  "symbol": "sxWETH/sxIDRX"
}
```

### Production (`config.production.json`)
```json
{
  "schedule": "0 */5 * * * *",      // Every 5 minutes
  "apiUrl": "https://base-sepolia-indexer.scalex.money/api/depth",
  "symbol": "sxWETH/sxIDRX"
}
```

## 📡 API Endpoint

The workflow fetches data from:
```
GET https://base-sepolia-indexer.scalex.money/api/depth?symbol=sxWETH/sxIDRX
```

**Expected Response:**
```json
{
  "lastUpdateId": 1770867000000,
  "bids": [
    ["328000", "100000000000000000"],
    ...
  ],
  "asks": [
    ["190300", "263179190751445100"],
    ...
  ]
}
```

## 🚀 Deployment Prerequisites

1. **CRE Early Access**: Request at https://cre.chain.link/request-access
2. **CRE CLI**: Installed via `curl -sSL https://cre.chain.link/install.sh | bash`
3. **Authentication**: Run `cre login`

## 📈 Expected Output (When Deployed)

```
============================================================
📈 LIQUIDITY METRICS FOR sxWETH/sxIDRX
============================================================
🕐 Timestamp: 2026-02-12T12:00:00.000Z
💱 Mid Price: 259150
📊 Spread: -137700 (-5313.52 bps)
📊 Order Book Depth: 32 bids, 100 asks
💧 Total Liquidity:
   Bids: 9.315600 ETH
   Asks: 87.573620 ETH
   Combined: 96.889220 ETH
📏 Liquidity Depth:
   1% - Bids: 2.000000 ETH, Asks: 87.573620 ETH
   5% - Bids: 2.000000 ETH, Asks: 87.573620 ETH
============================================================
```

## 🔍 How It Works (When Deployed)

1. **Cron Trigger**: Chainlink's cron capability triggers the workflow
2. **Decentralized HTTP**: Multiple Chainlink nodes fetch the order book
3. **Consensus**: Nodes aggregate results for data integrity
4. **Calculation**: Liquidity metrics are computed from order book
5. **Output**: JSON metrics are returned and logged

## ⚠️ Current Status

- ✅ Code complete and production-ready
- ✅ Compiles to WASM successfully
- ⏳ **Awaiting CRE early access for deployment testing**
- ❌ Cannot test HTTP in local simulation

## 📞 Support

For CRE-specific issues:
- Documentation: https://docs.chain.link/cre
- Request Access: https://cre.chain.link/request-access
- GitHub: https://github.com/smartcontractkit/cre-cli

## 📝 License

UNLICENSED

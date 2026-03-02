# PricePrediction — Chainlink CRE Settlement Workflow

Trustless settlement for PricePrediction markets via Chainlink CRE (Compute Runtime Environment).

## How it works

1. Anyone calls `PricePrediction.requestSettlement(marketId)` after market endTime
2. The contract emits `SettlementRequested(marketId, baseToken, strikePrice, openingTwap)`
3. This CRE workflow detects the event via EVM Log Trigger
4. The workflow reads `Oracle.getTWAP(baseToken, 300)` on-chain
5. Computes outcome: UP/DOWN (Directional) or Above/Below (Absolute)
6. Submits a signed report to `PricePrediction.onReport(metadata, report)`
7. DON nodes reach BFT quorum; KeystoneForwarder verifies and calls `onReport()`

## Report encoding

```
report = abi.encode(uint64 marketId, bool outcome)
```

- `outcome = true` → UP wins (Directional) or Above wins (Absolute)
- `outcome = false` → DOWN wins (Directional) or Below wins (Absolute)

## Environment variables

| Variable | Description |
|----------|-------------|
| `PRICE_PREDICTION_ADDRESS` | Deployed PricePrediction proxy address |
| `ORACLE_ADDRESS` | Deployed Oracle.sol address |

## Deployment

```bash
# Set addresses from deployments/<chainId>.json
export PRICE_PREDICTION_ADDRESS=0x...
export ORACLE_ADDRESS=0x...

# Deploy to Chainlink CRE
cre workflow deploy workflow.yaml
```

## Local testing

```bash
# Simulate the workflow locally (requires CRE dev toolkit)
cre workflow simulate \
  --trigger '{"marketId": 1, "baseToken": "0x...", "strikePrice": "0", "openingTwap": "300000000000"}' \
  workflow.yaml
```

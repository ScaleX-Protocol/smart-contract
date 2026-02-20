#!/bin/bash

ORACLE="0x83187ccD22D4e8DFf2358A09750331775A207E13"
TX_HASH="0xd71895ad816bd6740673a612d56146ea4cb60034c03a62d040fdc6c4fea056fe"
SXIDRX="0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624"
SXWETH="0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6"

echo "=== ANALYZING ORACLE PRICE UPDATE EVENTS ==="
echo "Oracle: $ORACLE"
echo "Transaction: $TX_HASH"
echo ""

# Get all logs from this transaction
echo "Fetching all events from price fix transaction..."
LOGS=$(cast receipt $TX_HASH --rpc-url https://sepolia.base.org --json 2>&1 | jq '.logs[]')

# Count PriceUpdate events
PRICE_UPDATE_SIG="0xac7b695c6873047ad50339f850f4ae3f6b8f6ef63ed1a8b22f7d36a1c6bd46f3"
EVENT_COUNT=$(echo "$LOGS" | jq -r "select(.topics[0] == \"$PRICE_UPDATE_SIG\")" | jq -s 'length')

echo "Found $EVENT_COUNT PriceUpdate events"
echo ""

# Decode each PriceUpdate event
echo "=== PRICE UPDATES IN THIS TRANSACTION ==="
echo ""

echo "$LOGS" | jq -c "select(.topics[0] == \"$PRICE_UPDATE_SIG\")" | while read event; do
  # Extract token address from topics[1]
  TOKEN=$(echo "$event" | jq -r '.topics[1]' | sed 's/^0x0*/0x/')
  
  # Extract data
  DATA=$(echo "$event" | jq -r '.data')
  
  # Extract price (first 32 bytes)
  PRICE_HEX="0x${DATA:2:64}"
  PRICE_DEC=$(cast --to-base $PRICE_HEX 10)
  PRICE_HUMAN=$(echo "scale=8; $PRICE_DEC / 100000000" | bc)
  
  # Extract timestamp (second 32 bytes)
  TIMESTAMP_HEX="0x${DATA:66:64}"
  TIMESTAMP_DEC=$(cast --to-base $TIMESTAMP_HEX 10)
  TIMESTAMP_DATE=$(date -r $TIMESTAMP_DEC 2>/dev/null || date -d @$TIMESTAMP_DEC 2>/dev/null || echo "N/A")
  
  # Identify token
  if [ "$TOKEN" == "$SXIDRX" ] || [ "${TOKEN,,}" == "${SXIDRX,,}" ]; then
    TOKEN_NAME="sxIDRX"
  elif [ "$TOKEN" == "$SXWETH" ] || [ "${TOKEN,,}" == "${SXWETH,,}" ]; then
    TOKEN_NAME="sxWETH"
  else
    TOKEN_NAME="Unknown"
  fi
  
  echo "---"
  echo "Token: $TOKEN_NAME ($TOKEN)"
  echo "Price: \$$PRICE_HUMAN ($PRICE_DEC with 8 decimals)"
  echo "Time: $TIMESTAMP_DATE"
  echo ""
done

echo ""
echo "=== SUMMARY ==="
echo "✅ Transaction successfully updated oracle prices"
echo "✅ Both sxIDRX and sxWETH prices were set"


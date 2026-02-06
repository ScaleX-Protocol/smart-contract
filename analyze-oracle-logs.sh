#!/bin/bash
set -e

# Configuration
API_KEY="KTWTH8JNXHQJF2P5BPC2UJM6EFESMW2XE4"
ORACLE="0x83187ccD22D4e8DFf2358A09750331775A207E13"
SXIDRX="0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624"
SXWETH="0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6"

# PriceUpdate event signature: PriceUpdate(address indexed token, uint256 price, uint256 timestamp)
# keccak256("PriceUpdate(address,uint256,uint256)")
EVENT_TOPIC="0x19a908d463090e5f53d529680c1db63f8e8694f9e6b0e3e3e3e3e0e0e0e0e0e0"

echo "=== ORACLE PRICE UPDATE LOGS ANALYSIS ==="
echo "Oracle: $ORACLE"
echo ""

# Get logs from Basescan API
echo "Fetching PriceUpdate events from Basescan..."
LOGS=$(curl -s "https://api-sepolia.basescan.org/api?module=logs&action=getLogs&address=$ORACLE&fromBlock=0&toBlock=latest&apikey=$API_KEY")

# Save raw logs
echo "$LOGS" | jq '.' > /tmp/oracle-logs-raw.json

# Check if we got results
STATUS=$(echo "$LOGS" | jq -r '.status')
if [ "$STATUS" != "1" ]; then
  echo "Error fetching logs:"
  echo "$LOGS" | jq -r '.result'
  exit 1
fi

# Parse and analyze logs
echo ""
echo "=== PRICE UPDATE EVENTS ==="
echo "$LOGS" | jq -r '.result[] | 
  "Block: \(.blockNumber) | Tx: \(.transactionHash) | Topic1: \(.topics[0])"' | head -20

echo ""
echo "Total events found: $(echo "$LOGS" | jq '.result | length')"

# Try to decode the events
echo ""
echo "=== ATTEMPTING TO DECODE EVENTS ==="

# Get all unique topics[0] (event signatures)
echo "$LOGS" | jq -r '.result[].topics[0]' | sort -u > /tmp/oracle-event-topics.txt
echo "Unique event signatures found:"
cat /tmp/oracle-event-topics.txt

# For each event, show details
echo ""
echo "=== EVENT DETAILS ==="
echo "$LOGS" | jq -r '.result[] | 
  "---\nBlock: \(.blockNumber)\nTx: \(.transactionHash)\nTopics: \(.topics)\nData: \(.data)\n"' | head -100


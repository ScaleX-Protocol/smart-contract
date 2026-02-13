#!/bin/bash

ORACLE="0x83187ccD22D4e8DFf2358A09750331775A207E13"
SXWETH="0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6"
UPDATE_BLOCK=37305972
CURRENT_BLOCK=$(cast block-number --rpc-url https://sepolia.base.org)

echo "=== SEARCHING FOR PRICE OVERWRITES ==="
echo "Looking for PriceUpdate events for sxWETH"
echo "From block: $UPDATE_BLOCK"
echo "To block: $CURRENT_BLOCK"
echo ""

# Search in smaller chunks to avoid RPC issues
CHUNK_SIZE=100
for ((START=$UPDATE_BLOCK; START<=$CURRENT_BLOCK; START+=CHUNK_SIZE)); do
  END=$((START + CHUNK_SIZE - 1))
  if [ $END -gt $CURRENT_BLOCK ]; then
    END=$CURRENT_BLOCK
  fi
  
  echo "Checking blocks $START to $END..."
  
  # Try to get logs
  RESULT=$(cast logs \
    --from-block $START \
    --to-block $END \
    --address $ORACLE \
    --rpc-url https://sepolia.base.org \
    "PriceUpdate(address indexed,uint256,uint256)" \
    $SXWETH 2>&1 || echo "RPC_ERROR")
  
  if [ "$RESULT" != "RPC_ERROR" ] && [ ! -z "$RESULT" ]; then
    echo "FOUND EVENTS:"
    echo "$RESULT"
    break
  fi
  
  sleep 0.5
done


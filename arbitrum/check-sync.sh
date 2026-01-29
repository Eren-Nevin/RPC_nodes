#!/bin/bash
# Arbitrum sync monitor - notifies when sync is complete

RPC_URL="http://localhost:8547"
CHECK_INTERVAL=60  # seconds between checks

while true; do
    SYNC_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        "$RPC_URL" 2>/dev/null)

    if [ -z "$SYNC_STATUS" ]; then
        echo "$(date): RPC not responding, waiting..."
        sleep $CHECK_INTERVAL
        continue
    fi

    # Check if syncing is false (means fully synced)
    IS_SYNCED=$(echo "$SYNC_STATUS" | jq -r '.result')

    if [ "$IS_SYNCED" = "false" ]; then
        BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "$RPC_URL" | jq -r '.result' | xargs printf "%d")

        echo ""
        echo "=========================================="
        echo "  ARBITRUM NODE SYNC COMPLETE!"
        echo "  Block: $BLOCK"
        echo "  Time: $(date)"
        echo "=========================================="

        # Desktop notification (if available)
        command -v notify-send &>/dev/null && notify-send "Arbitrum Sync Complete" "Block: $BLOCK"

        # Terminal bell
        echo -e "\a"

        exit 0
    fi

    # Show progress
    CURRENT=$(echo "$SYNC_STATUS" | jq -r '.result.blockNum // empty')
    if [ -n "$CURRENT" ]; then
        LATEST=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "https://arb1.arbitrum.io/rpc" 2>/dev/null | jq -r '.result' | xargs printf "%d" 2>/dev/null)

        if [ -n "$LATEST" ] && [ "$LATEST" -gt 0 ]; then
            BEHIND=$((LATEST - CURRENT))
            PCT=$(echo "scale=2; $CURRENT * 100 / $LATEST" | bc)
            echo "$(date): Block $CURRENT / $LATEST ($PCT%) - $BEHIND blocks behind"
        else
            echo "$(date): Block $CURRENT (syncing...)"
        fi
    fi

    sleep $CHECK_INTERVAL
done

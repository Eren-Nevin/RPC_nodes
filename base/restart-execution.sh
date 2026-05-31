#!/bin/bash
# Periodic restart of base-execution to reclaim memory leaked by glibc malloc.
# base-reth-node grows to ~90 GiB after ~17h despite MALLOC_ARENA_MAX=2 and
# engine cache limits, eventually starving the host and triggering hl-visor's
# low-memory watchdog. Restarting freezes RSS back to <5 GiB.
#
# Downtime: ~10-15 seconds. base-consensus buffers unsafe payloads and replays
# them via engine_newPayload after execution comes back — no missed blocks.

set -eu

LOG=/var/log/base-execution-restart.log

log() {
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" | sudo tee -a "$LOG"
}

# Pre-restart state
pre_block=$(curl -s -X POST http://127.0.0.1:8645 -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' --max-time 5 \
    | python3 -c 'import sys,json; print(int(json.load(sys.stdin)["result"],16))' 2>/dev/null || echo "unknown")
pre_mem=$(docker stats base-execution-1 --no-stream --format '{{.MemUsage}}' 2>/dev/null || echo "unknown")
log "pre-restart: block=$pre_block mem=$pre_mem"

# Restart
docker restart base-execution-1 >/dev/null

# Wait for RPC to respond again (max 2 min)
deadline=$(( $(date +%s) + 120 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if curl -s -X POST http://127.0.0.1:8645 -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' --max-time 3 2>/dev/null \
      | grep -q '"result"'; then
    break
  fi
  sleep 2
done

post_block=$(curl -s -X POST http://127.0.0.1:8645 -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' --max-time 5 \
    | python3 -c 'import sys,json; print(int(json.load(sys.stdin)["result"],16))' 2>/dev/null || echo "unknown")
post_mem=$(docker stats base-execution-1 --no-stream --format '{{.MemUsage}}' 2>/dev/null || echo "unknown")
log "post-restart: block=$post_block mem=$post_mem"

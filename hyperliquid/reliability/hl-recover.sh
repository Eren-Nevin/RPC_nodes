#!/bin/bash
# Full HL recovery — the proven manual fix (07-13/07-23), automated.
# Called by hl-monitor.sh on a true stall (with cooldown), or run manually.
# Steps: kill any contention (Base/Polygon) -> refresh gossip roots -> clean-slate re-sync.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
HLDIR=/home/mvp/Running/RPC_nodes/hyperliquid

log "=== hl-recover START ==="
notify "🔧 RECOVERY started — HL stalled; freeing resources + clean re-sync"

# 1. Ensure contention sources are GONE (they must not steal I/O during HL's re-sync).
docker rm -f base-execution-1 base-node-1 polygon-bor polygon-heimdall >/dev/null 2>&1 || true

# 2. Refresh gossip roots from the live API (current, plentiful state-servers).
"$DIR/hl-refresh-roots.sh" || log "WARN root refresh failed, continuing with existing roots"

# 3. Clean-slate re-sync: stop node, clear stale/corrupt state mount, rebuild+recreate.
cd "$HLDIR" || { log "ERROR cd $HLDIR"; exit 1; }
docker compose stop node >>"$LOG" 2>&1
rm -rf /data/rpc_nodes/hyperliquid-hlstate
mkdir -p /data/rpc_nodes/hyperliquid-hlstate
chown 10000:10000 /data/rpc_nodes/hyperliquid-hlstate
docker compose build node >>"$LOG" 2>&1
docker compose up -d --force-recreate --no-deps node >>"$LOG" 2>&1

nroots=$(python3 -c 'import json;print(len(json.load(open("'"$HLDIR"'/override_gossip_config.json"))["root_node_ips"]))' 2>/dev/null)
log "=== hl-recover restart issued (${nroots} roots) ==="
notify "🔧 RECOVERY restart issued (${nroots} gossip roots) — re-syncing; monitor will send all-clear when applying again."

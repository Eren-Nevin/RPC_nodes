#!/bin/bash
# Hyperliquid node lag watchdog. Checks the gap between HL chain head time
# (from the public API) and our local node's latest applied block_time (from
# the event-server). If lag exceeds the threshold, restart hyperliquid-node.
#
# Failure mode this catches: on 2026-06-01 the hl-node fell behind chain over
# ~70 min (gradual slowdown of block application, then state-sync, then
# post-sync rate too slow to catch up). It went undetected until a user
# checked. A fresh restart cleared it instantly.
#
# Schedule: every 5 min via /etc/cron.d/hl-lag-watchdog

set -eu

LOG=/var/log/hl-lag-watchdog.log
THRESHOLD_MIN=10                          # restart if lag > this many minutes
COOLDOWN_FILE=/tmp/hl-lag-watchdog.cooldown
COOLDOWN_SEC=1800                         # 30 min: covers state-sync + catchup

log() {
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" | sudo tee -a "$LOG" >/dev/null
}

# --- Read chain head from HL public API ---
chain_ts_ms=$(curl -s -X POST https://api.hyperliquid.xyz/info \
    -H 'Content-Type: application/json' \
    -d '{"type":"l2Book","coin":"BTC"}' \
    --max-time 5 2>/dev/null \
    | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("time", 0))
except Exception:
    print(0)' 2>/dev/null)
chain_ts_ms=${chain_ts_ms:-0}

if [ "$chain_ts_ms" = "0" ]; then
  log "WARN failed to fetch HL chain head, skipping"
  exit 0
fi

# --- Read latest local block_time from event-server ---
local_ts_ms=$(curl -s --max-time 3 'http://127.0.0.1:3002/fills/latest?n=1' 2>/dev/null \
    | python3 -c '
import sys, json, datetime
try:
    d = json.load(sys.stdin)
    if not d:
        print(0)
    else:
        bt = d[0].get("block_time", "")
        dt = datetime.datetime.fromisoformat(bt[:26]).replace(tzinfo=datetime.timezone.utc)
        print(int(dt.timestamp() * 1000))
except Exception:
    print(0)
' 2>/dev/null)
local_ts_ms=${local_ts_ms:-0}

if [ "$local_ts_ms" = "0" ]; then
  log "WARN failed to read local block_time, skipping"
  exit 0
fi

lag_ms=$((chain_ts_ms - local_ts_ms))
lag_min=$((lag_ms / 60000))

if [ "$lag_min" -lt "$THRESHOLD_MIN" ]; then
  # Healthy. Log lightly (only every 30 min) to keep the file small.
  minute=$(date -u +%M)
  case "$minute" in
    00|30) log "ok lag=${lag_min}min" ;;
  esac
  exit 0
fi

# --- Lag exceeds threshold: check cooldown ---
if [ -f "$COOLDOWN_FILE" ]; then
  last_restart=$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ $((now - last_restart)) -lt "$COOLDOWN_SEC" ]; then
    log "WARN lag=${lag_min}min > ${THRESHOLD_MIN}min but cooldown active, skipping"
    exit 0
  fi
fi

log "ERROR lag=${lag_min}min > ${THRESHOLD_MIN}min, restarting hyperliquid-node"
if docker restart hyperliquid-node >/dev/null 2>&1; then
  date +%s | sudo tee "$COOLDOWN_FILE" >/dev/null
  log "restart complete (cooldown ${COOLDOWN_SEC}s)"
else
  log "ERROR docker restart failed"
fi

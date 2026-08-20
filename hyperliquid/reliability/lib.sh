#!/bin/bash
# Shared helpers for the HL reliability scripts (monitor / recover / refresh-roots).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG=/var/log/hl-monitor.log
# Telegram creds (gitignored). Copy alert.conf.example -> alert.conf and fill in.
[ -f "$DIR/alert.conf" ] && source "$DIR/alert.conf"

log(){ echo "$(date -u +%FT%TZ) $*" >> "$LOG" 2>/dev/null; }

# notify "message" — push to Telegram (if configured) + log. Always logs even without creds.
notify(){
  local msg="[HL $(hostname -s 2>/dev/null)] $1"
  log "NOTIFY: $1"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -s -m10 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode chat_id="${TELEGRAM_CHAT_ID}" \
      --data-urlencode text="$msg" >/dev/null 2>&1 || log "WARN telegram send failed"
  fi
}

# --- HL health probes ---
hl_fills_block(){  # latest fill block number, 0 on empty/glitch
  curl -s -m6 'http://127.0.0.1:3002/fills/latest?n=1' 2>/dev/null \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[-1].get("block_number") if isinstance(d,list) and d else 0)' 2>/dev/null
}
# NOTE: never pipe `docker logs` straight into `grep -q` here. The callers run with
# `set -o pipefail`, and `grep -q` exits on its FIRST match, which SIGPIPEs docker logs
# (exit 141) and makes pipefail report the whole pipeline as failed — so the probe
# returns false exactly when it matched. That silently disabled this fallback since the
# system was built: every event-server read glitch became a phantom stall and triggered
# a destructive recovery. Capture the output first, then match it.
hl_applying(){  # 0/true if an "applied block" log appeared since about the last tick
  # 70s, not 20s: the monitor ticks every 60s, and while catching up HL applies in bursts
  # (a peer connects, streams a batch, drops). A 20s window samples a third of the interval
  # and misses the gaps, so a node that IS applying reads as stalled and the stall counter
  # creeps toward a needless recovery. Cover the whole gap between ticks, with margin.
  local out; out=$(docker logs hyperliquid-node --since 70s 2>&1) || true
  grep -qE 'applied block [0-9]+' <<<"$out"
}
hl_child_restarts(){  # hl-node child restart counter (crash-loop indicator)
  docker logs hyperliquid-node 2>&1 | grep -oE 'n_restarts: [0-9]+' | tail -1 | grep -oE '[0-9]+'
}
hl_lag_min(){  # chain head vs latest local fill, in minutes; 999 on API glitch
  local chain lc
  chain=$(curl -s -X POST https://api.hyperliquid.xyz/info -H 'Content-Type: application/json' \
    -d '{"type":"l2Book","coin":"BTC"}' --max-time 5 2>/dev/null \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("time",0))' 2>/dev/null)
  lc=$(curl -s --max-time 3 'http://127.0.0.1:3002/fills/latest?n=1' 2>/dev/null \
    | python3 -c 'import sys,json,datetime as dt;d=json.load(sys.stdin);print(int(dt.datetime.fromisoformat(d[0]["block_time"][:26]).replace(tzinfo=dt.timezone.utc).timestamp()*1000))' 2>/dev/null)
  if [ -n "$chain" ] && [ "$chain" != "0" ] && [ -n "$lc" ]; then echo $(( (chain-lc)/60000 )); else echo 999; fi
}
# Same pipefail/SIGPIPE hazard as above — compare captured output instead of piping.
hl_running(){ local out; out=$(docker ps --filter name=hyperliquid-node --filter status=running -q 2>/dev/null) || true; [ -n "$out" ]; }

# --- re-sync progress probes ---
# A state re-sync legitimately produces NO blocks for many minutes: the node streams a
# ~1GB abci "greeting" from a peer, then ingests it into the state db (log goes silent
# while it does, so logs alone can't see it). If the monitor fires another clean-slate
# recovery during that window it throws the progress away and starts from zero — which
# is exactly what turned one outage into three recovery cycles on 2026-08-20.
HLSTATE_DIR=/data/rpc_nodes/hyperliquid-hlstate
hl_state_bytes(){ du -sb "$HLSTATE_DIR" 2>/dev/null | cut -f1; }   # ~10ms, ~850 files
hl_downloading(){  # streaming the greeting / handshaking with a state-server peer
  local out; out=$(docker logs hyperliquid-node --since 150s 2>&1) || true
  grep -qE 'abci_stream|abci greeting|abci state' <<<"$out"
}

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
hl_applying(){  # 0/true if an "applied block" log appeared in the last 20s
  docker logs hyperliquid-node --since 20s 2>&1 | grep -qE 'applied block [0-9]+'
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
hl_running(){ docker ps --filter name=hyperliquid-node --filter status=running -q | grep -q . ; }

# --- re-sync progress probes ---
# A state re-sync legitimately produces NO blocks for many minutes: the node streams a
# ~1GB abci "greeting" from a peer, then ingests it into the state db (log goes silent
# while it does, so logs alone can't see it). If the monitor fires another clean-slate
# recovery during that window it throws the progress away and starts from zero — which
# is exactly what turned one outage into three recovery cycles on 2026-08-20.
HLSTATE_DIR=/data/rpc_nodes/hyperliquid-hlstate
hl_state_bytes(){ du -sb "$HLSTATE_DIR" 2>/dev/null | cut -f1; }   # ~10ms, ~850 files
hl_downloading(){  # streaming the greeting / handshaking with a state-server peer
  docker logs hyperliquid-node --since 150s 2>&1 | grep -qE 'abci_stream|abci greeting|abci state'
}

#!/bin/bash
# HL health monitor — runs every 1 min via /etc/cron.d/hl-monitor.
# Ground truth = "is HL producing data?" (fills advancing OR applied-block log).
#  - healthy            -> clear stall counter; send RECOVERED all-clear if we had alerted.
#  - not producing       -> increment stall; after STALL_LIMIT min: ALERT (once) + auto-recover (cooldown).
#  - producing but lagging-> soft LAG warning (deduped), no restart (it's catching up on its own).
# Replaces the old lag-watchdog (which restarted on transient lag and TRIGGERED the fragile re-sync).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
STATE=/var/lib/hl-monitor; mkdir -p "$STATE"
LASTF="$STATE/lastfills"; STALLC="$STATE/stallcount"; DOWN="$STATE/alerted_down"; LAGA="$STATE/alerted_lag"; COOL="$STATE/recover_cooldown"

STALL_LIMIT=4         # consecutive minutes with no data production = a real stall
LAG_WARN=10           # minutes; warn (not restart) if producing but this far behind
COOLDOWN_SEC=2400     # 40 min minimum between auto-recoveries

# Container not even running? -> hard down, try compose up, alert.
if ! hl_running; then
  if [ ! -f "$DOWN" ]; then notify "🔴 DOWN — hyperliquid-node container not running. Starting it."; touch "$DOWN"; fi
  (cd /home/mvp/Running/RPC_nodes/hyperliquid && docker compose up -d --no-deps node) >>"$LOG" 2>&1
  exit 0
fi

fills=$(hl_fills_block); fills=${fills:-0}
last=$(cat "$LASTF" 2>/dev/null || echo 0)
lag=$(hl_lag_min)
producing=0
{ [ "$fills" -gt "$last" ] 2>/dev/null; } && producing=1
[ "$producing" = 0 ] && hl_applying && producing=1     # robust to the fills-read glitch
[ "$fills" -gt 0 ] && echo "$fills" > "$LASTF"

if [ "$producing" = 1 ]; then
  echo 0 > "$STALLC"
  if [ -f "$DOWN" ]; then notify "✅ RECOVERED — HL applying again (fills=$fills, lag=${lag}min)"; rm -f "$DOWN"; fi
  # soft lag warning while healthy (deduped): only when API gave a real number
  if [ "$lag" != 999 ] && [ "$lag" -ge "$LAG_WARN" ] 2>/dev/null; then
    [ -f "$LAGA" ] || { notify "⚠️ HL lagging ${lag}min behind (still applying, catching up)"; touch "$LAGA"; }
  else
    rm -f "$LAGA"
  fi
  exit 0
fi

# --- not producing this minute ---
stall=$(( $(cat "$STALLC" 2>/dev/null || echo 0) + 1 )); echo "$stall" > "$STALLC"
[ "$stall" -lt "$STALL_LIMIT" ] && exit 0     # tolerate brief pauses (network fetch, hour rollover)

# real stall
nr=$(hl_child_restarts)
if [ ! -f "$DOWN" ]; then
  notify "🔴 DOWN — HL not producing for ${stall}min (fills stuck=$fills, lag=${lag}min, child_restarts=${nr}). Auto-recovery starting."
  touch "$DOWN"
fi
now=$(date +%s); lastrec=$(cat "$COOL" 2>/dev/null || echo 0)
if [ $((now-lastrec)) -ge "$COOLDOWN_SEC" ]; then
  echo "$now" > "$COOL"
  log "stall=${stall} -> triggering hl-recover.sh"
  nohup "$DIR/hl-recover.sh" >>"$LOG" 2>&1 &
else
  log "stall=${stall} but recover cooldown active ($(( (COOLDOWN_SEC-(now-lastrec))/60 ))min left)"
fi

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
STATEB="$STATE/statebytes"; RESYNC="$STATE/resync_since"

STALL_LIMIT=4         # consecutive minutes with no data production = a real stall
LAG_WARN=10           # minutes; warn (not restart) if producing but this far behind
COOLDOWN_SEC=2400     # 40 min minimum between auto-recoveries
RESYNC_MAX_MIN=120    # give an in-flight re-sync this long before overriding the guard

# Container not even running? -> hard down, try compose up, alert.
if ! hl_running; then
  if [ ! -f "$DOWN" ]; then notify "🔴 DOWN — hyperliquid-node container not running. Starting it."; touch "$DOWN"; fi
  (cd /home/mvp/Running/RPC_nodes/hyperliquid && docker compose up -d --no-deps node) >>"$LOG" 2>&1
  exit 0
fi

# Sample the state-db size EVERY tick (cheap), so "is it growing?" always compares
# against the previous minute rather than a stale reading from the last stall.
sb=$(hl_state_bytes); sbprev=$(cat "$STATEB" 2>/dev/null || echo 0)
[ -n "$sb" ] && echo "$sb" > "$STATEB"
state_growing=0
{ [ -n "$sb" ] && [ "$sb" -gt "$sbprev" ]; } 2>/dev/null && state_growing=1

fills=$(hl_fills_block); fills=${fills:-0}
last=$(cat "$LASTF" 2>/dev/null || echo 0)
lag=$(hl_lag_min)
producing=0
{ [ "$fills" -gt "$last" ] 2>/dev/null; } && producing=1
[ "$producing" = 0 ] && hl_applying && producing=1     # robust to the fills-read glitch
[ "$fills" -gt 0 ] && echo "$fills" > "$LASTF"

if [ "$producing" = 1 ]; then
  echo 0 > "$STALLC"; rm -f "$RESYNC"
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
now=$(date +%s)

# --- re-sync guard ---
# If the node is mid-re-sync (streaming the greeting, or silently ingesting it — the
# state db keeps growing), it is NOT stuck: it is working and just can't produce blocks
# yet. Firing hl-recover.sh here wipes the state dir and restarts the download from
# zero, so a slow-but-healthy re-sync never finishes. Hold off until it lands, or until
# RESYNC_MAX_MIN proves it really is wedged.
if [ "$state_growing" = 1 ] || hl_downloading; then
  [ -f "$RESYNC" ] || echo "$now" > "$RESYNC"
  held=$(( (now - $(cat "$RESYNC")) / 60 ))
  if [ "$held" -lt "$RESYNC_MAX_MIN" ]; then
    if [ ! -f "$DOWN" ]; then
      notify "🔄 RE-SYNCING — HL not producing for ${stall}min but state is still growing ($(( ${sb:-0}/1073741824 ))GB). Holding off recovery so it can finish."
      touch "$DOWN"
    fi
    log "stall=${stall} but re-sync in progress (${held}min, state=${sb:-?}B) -> recovery suppressed"
    exit 0
  fi
  notify "⏱️ RE-SYNC STUCK — ${held}min without producing despite activity. Overriding guard, forcing recovery."
  rm -f "$RESYNC"
fi

if [ ! -f "$DOWN" ]; then
  notify "🔴 DOWN — HL not producing for ${stall}min (fills stuck=$fills, lag=${lag}min, child_restarts=${nr}). Auto-recovery starting."
  touch "$DOWN"
fi
lastrec=$(cat "$COOL" 2>/dev/null || echo 0)
if [ $((now-lastrec)) -ge "$COOLDOWN_SEC" ]; then
  echo "$now" > "$COOL"
  log "stall=${stall} -> triggering hl-recover.sh"
  nohup "$DIR/hl-recover.sh" >>"$LOG" 2>&1 &
else
  log "stall=${stall} but recover cooldown active ($(( (COOLDOWN_SEC-(now-lastrec))/60 ))min left)"
fi

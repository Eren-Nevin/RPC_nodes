#!/bin/bash
# Logs polygon-bor RAM every run so we can see how far it climbs under GOMEMLIMIT=50GiB
# (set 2026-07-05). Installed via /etc/cron.d/bor-ram-monitor (every 6h, as root).
LOG=/var/log/bor-ram.log
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mem=$(docker stats polygon-bor --no-stream --format '{{.MemUsage}} ({{.MemPerc}}) CPU={{.CPUPerc}}' 2>/dev/null)
pid=$(docker inspect polygon-bor --format '{{.State.Pid}}' 2>/dev/null)
anon=$(awk '/RssAnon/{print $2" "$3}' /proc/"$pid"/status 2>/dev/null)
echo "$ts  RssAnon=$anon  MemUsage=$mem" >> "$LOG"

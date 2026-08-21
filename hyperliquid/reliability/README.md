# HL reliability system

Three layers to keep the Hyperliquid node up, recover it fast if it stops, and alert fast.
Built 2026-07-23 after repeated stuck-resync outages (see `../TROUBLESHOOTING.md`).

## 1. Don't stop (prevention)
- **No storage contention**: Base + Polygon are removed (`docker compose down`), so they can't
  auto-restart on a host/docker reboot and steal I/O. HL stays at the tip; its state stays fresh,
  so any restart recovers from **local** state (fast) instead of the fragile network re-sync.
- **12h pruner retention** (`../pruner/scripts/prune.sh`): keeps enough `replica_cmds`/
  `periodic_abci_states` that the visor self-recovers locally after a restart within 12h.
- **Wide, fresh gossip roots**: `hl-refresh-roots.sh` (daily cron) keeps `../override_gossip_config.json`
  populated with the live `gossipRootIps` + operator roots, so if a re-sync *is* needed it completes.

## 2. Recover fast (if it stops)
- **`hl-monitor.sh`** (every 1 min, `/etc/cron.d/hl-monitor`) is the ground-truth health check:
  is HL producing data (fills advancing / applied-block log)?
  - healthy → clear stall counter, send ✅ RECOVERED if it had alerted.
  - not producing for 4 min → 🔴 alert + trigger `hl-recover.sh` (40-min cooldown).
  - container not running → start it + alert.
  It does **not** restart on transient lag (the old lag-watchdog did, which *triggered* the
  fragile re-sync). Lag while still applying → soft ⚠️ warning only.
- **`hl-recover.sh`** = the proven manual fix, automated: remove Base/Polygon → refresh gossip
  roots from the live API → clear the stale state mount → rebuild + recreate the node for a clean
  re-sync. Run automatically by the monitor, or manually: `sudo ./hl-recover.sh`.

## 3. Get notified fast
- **Telegram** via `notify()` in `lib.sh`. Creds in `alert.conf` (gitignored; see
  `alert.conf.example`). Alerts: 🔴 DOWN, ✅ RECOVERED, ⚠️ lagging, 🔧 recovery started/issued.
  Logs to `/var/log/hl-monitor.log` even without creds.

## Files
| file | what |
|---|---|
| `lib.sh` | shared: `notify()` (Telegram) + HL health probes |
| `hl-monitor.sh` | 1-min health check → alert + auto-recover |
| `hl-recover.sh` | full clean-slate recovery (no-contention → fresh roots → re-sync) |
| `hl-refresh-roots.sh` | refresh `override_gossip_config.json` roots from live API |
| `alert.conf(.example)` | Telegram bot token + chat id (gitignored) |
| `cron.d/` | cron **templates** (`__RELDIR__` placeholder) — installed by `install.sh`, not copied by hand |

## Install on a fresh host
```bash
cp alert.conf.example alert.conf   # fill in TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
sudo ./install.sh    # creates the log + state dir, installs both cron jobs
```
Manual recovery any time: `sudo ./hl-recover.sh`. Test alert: `source lib.sh && notify "test"`.

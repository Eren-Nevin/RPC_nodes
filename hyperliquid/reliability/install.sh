#!/bin/bash
# install.sh — install the HL reliability system on this host.
#
# Cron needs absolute paths, so the tracked cron.d files are templates carrying a
# __RELDIR__ placeholder; this substitutes the real checkout path. That is what makes
# the repo deployable anywhere instead of only under /home/mvp/Running/RPC_nodes.
#
# Usage: sudo ./install.sh
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run with sudo (writes /etc/cron.d, /var/log, /var/lib)." >&2
  exit 1
fi

echo "Installing HL reliability system from ${DIR}"

# 1. Telegram credentials (gitignored; alerts are skipped but logged without them).
if [ ! -f "$DIR/alert.conf" ]; then
  echo "WARN: $DIR/alert.conf missing — Telegram alerts disabled."
  echo "      cp alert.conf.example alert.conf and fill in the token/chat id."
fi

# 2. Log file the scripts append to, and the monitor's state dir.
touch /var/log/hl-monitor.log
chmod 666 /var/log/hl-monitor.log
mkdir -p /var/lib/hl-monitor

# 3. Cron jobs, with __RELDIR__ resolved to this checkout.
for job in hl-monitor hl-roots-refresh; do
  sed "s#__RELDIR__#${DIR}#g" "$DIR/cron.d/${job}" > "/etc/cron.d/${job}"
  chmod 0644 "/etc/cron.d/${job}"
  echo "  installed /etc/cron.d/${job}"
done

echo
echo "Done. Verify with:"
echo "  tail -f /var/log/hl-monitor.log"

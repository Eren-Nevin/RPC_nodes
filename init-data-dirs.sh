#!/bin/sh
# init-data-dirs.sh — create all RPC node data directories with correct ownership.
# Called by the 'init' service in root docker-compose.yml.
# Override the root with: DATA_ROOT=/your/path docker compose up init

set -e

DATA_ROOT="${DATA_ROOT:-/data/rpc_nodes}"

echo "Creating data directories under ${DATA_ROOT} ..."

# Most clients run as UID 1000 inside their container.
UID_1000_DIRS="
eth-data
arbitrum
base-data
polygon-data
bsc-data
tron-data
bitcoin-data
"

# Hyperliquid's container runs as hluser (UID 10000), not 1000. Both its data dir
# and its separate consensus-state mount must be owned by 10000 or hl-visor cannot
# write and the node never starts.
UID_10000_DIRS="
hyperliquid-data
hyperliquid-hlstate
"

for d in $UID_1000_DIRS; do
  mkdir -p "${DATA_ROOT}/${d}"
  # Deliberately NOT recursive: these dirs can hold multiple TB, and a recursive
  # chown here would both take hours and stomp on ownership the clients rely on
  # (notably Hyperliquid's 10000). Snapshot extraction sets ownership for content.
  chown 1000:1000 "${DATA_ROOT}/${d}"
done

for d in $UID_10000_DIRS; do
  mkdir -p "${DATA_ROOT}/${d}"
  chown 10000:10000 "${DATA_ROOT}/${d}"
done

chown 1000:1000 "${DATA_ROOT}" 2>/dev/null || true

echo "Done. Directory layout:"
find "${DATA_ROOT}" -maxdepth 1 -type d | sort

#!/bin/sh
# init-data-dirs.sh — create all RPC node data directories with correct ownership.
# Called by the 'init' service in root docker-compose.yml.
# Override the root with: DATA_ROOT=/your/path docker compose up init

set -e

DATA_ROOT="${DATA_ROOT:-/data/rpc_nodes}"

echo "Creating data directories under ${DATA_ROOT} ..."

mkdir -p \
  "${DATA_ROOT}/eth-data" \
  "${DATA_ROOT}/arbitrum" \
  "${DATA_ROOT}/base-data" \
  "${DATA_ROOT}/polygon-data" \
  "${DATA_ROOT}/bsc-data" \
  "${DATA_ROOT}/tron-data" \
  "${DATA_ROOT}/hyperliquid-data" \
  "${DATA_ROOT}/bitcoin-data"

chown -R 1000:1000 "${DATA_ROOT}"

echo "Done. Directory layout:"
find "${DATA_ROOT}" -type d | sort

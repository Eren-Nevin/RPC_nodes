#!/bin/sh
# init-data-dirs.sh — create all RPC node data directories with correct ownership.
# Called by the 'init' service in root docker-compose.yml.
# Override the root with: DATA_ROOT=/your/path docker compose up init

set -e

DATA_ROOT="${DATA_ROOT:-/data/rpc_nodes}"

echo "Creating data directories under ${DATA_ROOT} ..."

mkdir -p \
  "${DATA_ROOT}/eth-data/reth" \
  "${DATA_ROOT}/eth-data/lighthouse" \
  "${DATA_ROOT}/arbitrum" \
  "${DATA_ROOT}/base-data/reth/snapshots/mainnet/download" \
  "${DATA_ROOT}/polygon-data/heimdall/data" \
  "${DATA_ROOT}/polygon-data/bor/bor/chaindata" \
  "${DATA_ROOT}/bsc-data"

chown -R 1000:1000 "${DATA_ROOT}"

echo "Done. Directory layout:"
find "${DATA_ROOT}" -type d | sort

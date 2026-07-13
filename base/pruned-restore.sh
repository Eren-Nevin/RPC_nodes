#!/bin/bash
# Resumable download + extract of Base pruned reth snapshot into the datadir.
# Pruned fits easily (~1.16 TB tarball -> ~2.3 TB extracted) so we use aria2c
# (resumable, 16-conn) to a file, then extract, then delete the tarball.
set -o pipefail
DD=/data/rpc_nodes/base-data/reth
TMP=/data/rpc_nodes/base-data
LOG=/home/mvp/Running/RPC_nodes/base/pruned-restore.log

URL="https://mainnet-reth-pruned-snapshots.base.org/$(curl -s https://mainnet-reth-pruned-snapshots.base.org/latest)"
BASENAME=$(basename "$URL")
F="$TMP/$BASENAME"

{
  echo "==================================="
  echo "$(date -u) START url=$URL"
} >> "$LOG"

sudo mkdir -p "$DD"

# Resumable multi-connection download
sudo aria2c -c -x16 -s16 --summary-interval=120 --console-log-level=warn \
  -d "$TMP" -o "$BASENAME" "$URL" >> "$LOG" 2>&1
echo "$(date -u) DOWNLOAD exit=$?" >> "$LOG"

# Extract (tarball carries snapshots/mainnet/download/ prefix -> lands under reth/)
zstd -dc "$F" | sudo tar -x -C "$DD" >> "$LOG" 2>&1
echo "$(date -u) EXTRACT exit=$? (pipestatus ${PIPESTATUS[*]})" >> "$LOG"

sudo rm -f "$F"
echo "$(date -u) DONE tarball removed; extracted into $DD" >> "$LOG"

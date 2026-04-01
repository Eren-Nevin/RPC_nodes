#!/usr/bin/env bash
# download-historical.sh — download Hyperliquid historical fills and misc events from S3
#
# Usage:
#   ./download-historical.sh [-d <data-root>] [-t fills|misc|all]
#
# Options:
#   -d  Data root (default: /data/rpc_nodes/hyperliquid-data)
#   -t  What to download: fills, misc, or all (default: all)
#   -h  Show this help
#
# Requires: aws cli configured with credentials (requester-pays bucket)
# Cost estimate: ~$12 for fills (~136 GB), ~$3 for misc (~31 GB)

set -euo pipefail

DATA_ROOT="/data/rpc_nodes/hyperliquid-data"
TARGET="all"
BUCKET="s3://hl-mainnet-node-data"

usage() {
  grep '^#' "$0" | sed 's/^# \?//' | head -15
  exit "${1:-0}"
}

while getopts "d:t:h" opt; do
  case "$opt" in
    d) DATA_ROOT="$OPTARG" ;;
    t) TARGET="$OPTARG" ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done

case "$TARGET" in
  fills|misc|all) ;;
  *) echo "ERROR: Unknown target '${TARGET}'. Must be fills, misc, or all." >&2; exit 1 ;;
esac

if ! command -v aws &>/dev/null; then
  echo "ERROR: aws cli is not installed or not in PATH." >&2
  exit 1
fi

# Verify credentials work
if ! aws sts get-caller-identity &>/dev/null; then
  echo "ERROR: AWS credentials not configured. Run 'aws configure' first." >&2
  exit 1
fi

download_fills() {
  local dest="${DATA_ROOT}/historical/fills"
  mkdir -p "$dest"
  echo "==> Downloading node_fills_by_block → ${dest}/"
  echo "    Source: ${BUCKET}/node_fills_by_block/"
  echo "    This is ~136 GB (LZ4 compressed), estimated cost ~\$12"
  echo ""
  aws s3 sync "${BUCKET}/node_fills_by_block/" "$dest/" \
    --request-payer requester \
    --no-progress
  echo "==> Fills download complete: ${dest}/"
}

download_misc() {
  local dest="${DATA_ROOT}/historical/misc"
  mkdir -p "$dest"
  echo "==> Downloading misc_events_by_block → ${dest}/"
  echo "    Source: ${BUCKET}/misc_events_by_block/"
  echo "    This is ~31 GB (LZ4 compressed), estimated cost ~\$3"
  echo ""
  aws s3 sync "${BUCKET}/misc_events_by_block/" "$dest/" \
    --request-payer requester \
    --no-progress
  echo "==> Misc events download complete: ${dest}/"
}

echo "=== download-historical: target=${TARGET} data_root=${DATA_ROOT} ==="

case "$TARGET" in
  fills) download_fills ;;
  misc)  download_misc ;;
  all)
    download_fills
    echo ""
    download_misc
    ;;
esac

echo ""
echo "=== Done ==="
echo "Data is in ${DATA_ROOT}/historical/"
echo "Format: newline-delimited JSON, LZ4 compressed"
echo "  Decompress: unlz4 <file>.lz4"

#!/bin/bash
DATA_PATH="/home/hluser/hl/data"

# Folders to exclude from pruning (keep forever).
# Only visor_child_stderr (tiny, kept for crash debugging). Everything else,
# including evm_block_and_receipts, is pruned to the retention window below
# since historical data is backfilled from S3.
EXCLUDES=("visor_child_stderr")

echo "$(date): Prune script started" >> /proc/1/fd/1

if [ ! -d "$DATA_PATH" ]; then
    echo "$(date): Error: Data directory $DATA_PATH does not exist." >> /proc/1/fd/1
    exit 1
fi

echo "$(date): Starting pruning process at $(date)" >> /proc/1/fd/1

size_before=$(du -sh "$DATA_PATH" | cut -f1)
files_before=$(find "$DATA_PATH" -type f | wc -l)
echo "$(date): Size before pruning: $size_before with $files_before files" >> /proc/1/fd/1

# Build the -prune arguments for excluding directories
PRUNE_ARGS=()
for dir in "${EXCLUDES[@]}"; do
    PRUNE_ARGS+=(-path "*/$dir" -prune -o)
done

# Delete data older than 12 hours. 2h(2026-07-04)->4h->12h(2026-07-23): keep enough
# replica_cmds/abci_states that the visor can self-recover LOCALLY (replay from a
# retained periodic_abci_state) after a restart, instead of the fragile/slow full
# NETWORK re-sync (abci_stream) that repeatedly caused multi-hour outages when peers
# were flaky. 12h of HL data is ~150G (disk has ample room). Backfill older from S3.
MINUTES=$((60*12))
find "$DATA_PATH" -mindepth 1 "${PRUNE_ARGS[@]}" -type f -mmin +$MINUTES -exec rm {} +

# Remove empty dated subdirectories left behind after their files are pruned.
# -mindepth 2 keeps the top-level data folders (replica_cmds, etc.) intact;
# the node recreates dated subdirs as needed.
find "$DATA_PATH" -mindepth 2 -type d -empty -mmin +$MINUTES -delete 2>/dev/null

size_after=$(du -sh "$DATA_PATH" | cut -f1)
files_after=$(find "$DATA_PATH" -type f | wc -l)
echo "$(date): Size after pruning: $size_after with $files_after files" >> /proc/1/fd/1
echo "$(date): Pruning completed. Reduced from $size_before to $size_after ($(($files_before - $files_after)) files removed)." >> /proc/1/fd/1

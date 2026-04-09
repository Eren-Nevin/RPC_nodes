#!/bin/bash
DATA_PATH="/home/hluser/hl/data"

# Folders to exclude from pruning (keep forever)
EXCLUDES=("visor_child_stderr" "evm_block_and_receipts")

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

# Delete data older than 24 hours
MINUTES=$((60*24*1))
find "$DATA_PATH" -mindepth 1 "${PRUNE_ARGS[@]}" -type f -mmin +$MINUTES -exec rm {} +

size_after=$(du -sh "$DATA_PATH" | cut -f1)
files_after=$(find "$DATA_PATH" -type f | wc -l)
echo "$(date): Size after pruning: $size_after with $files_after files" >> /proc/1/fd/1
echo "$(date): Pruning completed. Reduced from $size_before to $size_after ($(($files_before - $files_after)) files removed)." >> /proc/1/fd/1

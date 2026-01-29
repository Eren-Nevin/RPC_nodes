#!/bin/bash
# Wait for extraction to complete and start Ethereum node

DATA_DIR="/data/rpc_nodes/eth-data/reth"

echo "Monitoring extraction progress..."
echo "Compressed: ~961 GB → Extracted: ~2.4 TB"
echo ""

while pgrep -f "tar.*zstd.*snapshot.tar.zst" > /dev/null; do
    SIZE=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
    echo "$(date '+%H:%M:%S') - Extracted: $SIZE"
    sleep 60
done

echo ""
echo "Extraction complete!"
echo "Final size: $(du -sh $DATA_DIR | cut -f1)"
echo ""

# Fix ownership for container
echo "Setting ownership to 1000:1000..."
sudo chown -R 1000:1000 /data/rpc_nodes/eth-data/

echo "Starting Ethereum node..."
cd /home/mvp/Running/RPC_nodes/eth
docker compose up -d

echo ""
echo "Node started! Check logs with:"
echo "  docker logs -f eth-reth"
echo "  docker logs -f eth-lighthouse"

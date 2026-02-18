# Base RPC Node - Reth

## Overview

| Setting | Value |
|---------|-------|
| Client | Reth (OP Stack) |
| Data Directory | `/data/rpc_nodes/base-data/reth/snapshots/mainnet/download` |
| Network | Base Mainnet |
| HTTP RPC | `http://localhost:8645` |
| WebSocket | `ws://localhost:8646` |
| op-node RPC | `http://localhost:7545` |

## Directory Structure

```
base/
├── docker-compose.yml    # Custom ports and build context
├── .env                  # All node configuration
├── README.md
└── base-node/            # Git submodule (upstream, do not modify)
```

## Setup

### 1. Initialize Submodule

```bash
git submodule update --init --recursive
```

### 2. Download Snapshot

Base offers two snapshot types:

**Archive snapshot** (~4.3 TB compressed, ~7-8 TB extracted) - full history from genesis:
```bash
mkdir -p /data/rpc_nodes/base-data/reth/snapshots/mainnet/download
cd /data/rpc_nodes/base-data/reth/snapshots/mainnet/download
curl -sL "https://mainnet-reth-archive-snapshots.base.org/$(curl -s https://mainnet-reth-archive-snapshots.base.org/latest)" | zstd -d | tar -xf -
```

**Pruned snapshot** (~1.5 TB compressed, ~3 TB extracted) - recent state only:
```bash
mkdir -p /data/rpc_nodes/base-data/reth/snapshots/mainnet/download
cd /data/rpc_nodes/base-data/reth/snapshots/mainnet/download
curl -sL "https://mainnet-reth-pruned-snapshots.base.org/$(curl -s https://mainnet-reth-pruned-snapshots.base.org/latest)" | zstd -d | tar -xf -
```

Or download first with aria2c (supports resume):
```bash
SNAPSHOT=$(curl -s https://mainnet-reth-archive-snapshots.base.org/latest)
aria2c -x 16 -s 16 -d /data/rpc_nodes/base-data/ "https://mainnet-reth-archive-snapshots.base.org/$SNAPSHOT"
zstd -d /data/rpc_nodes/base-data/$SNAPSHOT --stdout | tar -xf - -C /data/rpc_nodes/base-data/reth/snapshots/mainnet/download
```

### 3. Verify Snapshot

```bash
ls /data/rpc_nodes/base-data/reth/snapshots/mainnet/download/
# Should show: db, static_files, etc.
```

### 4. Configure

Edit `base/.env`:

```bash
# Point to your L1 Ethereum RPC
OP_NODE_L1_ETH_RPC=http://172.17.0.1:8555        # local eth node
OP_NODE_L1_BEACON=https://ethereum-beacon-api.publicnode.com

# Or use a provider
OP_NODE_L1_ETH_RPC=https://mainnet.infura.io/v3/YOUR_KEY
OP_NODE_L1_RPC_KIND=infura
```

### 5. Build and Start

```bash
cd /path/to/RPC_nodes/base
docker compose up -d --build
```

First build takes ~10 minutes (compiles Reth from source).

### 6. Verify

```bash
# Check sync status
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' \
  http://localhost:7545 | python3 -m json.tool

# Check latest block
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8645
```

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8645 | HTTP | RPC endpoint |
| 8646 | WebSocket | WS endpoint |
| 7545 | HTTP | op-node RPC |
| 30403 | TCP/UDP | P2P (execution) |
| 9222 | TCP/UDP | P2P (op-node) |
| 7300 | HTTP | op-node metrics |
| 7301 | HTTP | execution metrics |

## Storage

- Archive: ~7-8 TB (growth ~50-100 GB/week)
- Pruned: ~3 TB (growth ~20-40 GB/week)

## Logs

```bash
docker compose logs -f execution   # Reth logs
docker compose logs -f node        # op-node logs
```

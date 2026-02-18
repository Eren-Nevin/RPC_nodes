# Ethereum L1 Mainnet Node

## Overview

| Setting | Value |
|---------|-------|
| Execution client | Reth v1.10.0 |
| Consensus client | Lighthouse v8.0.1 |
| Network | Mainnet |
| HTTP RPC | `http://localhost:8555` |
| WebSocket | `ws://localhost:8556` |
| Beacon API | `http://localhost:5052` |
| Execution data | `/data/rpc_nodes/eth-data/reth` |
| Consensus data | `/data/rpc_nodes/eth-data/lighthouse` |

## Full Node vs Archive Node

Reth stores all blocks, transactions, receipts, and logs regardless of mode. The only difference is **historical state**:

| Data type | Full node | Archive node |
|-----------|-----------|--------------|
| Blocks, txs, receipts, logs | All history | All history |
| `eth_getBalance` at old block | Last ~128 blocks only | All history |
| `eth_call` at old block | Last ~128 blocks only | All history |

For most use-cases (indexing, relaying, tracing transactions) a full node is sufficient. Both modes are ~2.4 TB extracted with Reth — archive is not meaningfully larger.

## Setup

### 1. Create data directories

```bash
sudo mkdir -p /data/rpc_nodes/eth-data/{reth,lighthouse}
```

### 2. JWT secret

A `jwt.hex` is already committed. To regenerate:

```bash
openssl rand -hex 32 > jwt.hex
```

### 3. Download a snapshot

Syncing from genesis takes weeks. Use a snapshot instead.

#### Archive node snapshots

**Option A — ethPandaOps (recommended, free, ~961 GB compressed → ~2.4 TB)**

Stream-extract directly to avoid needing 2× disk space:

```bash
BLOCK=$(curl -sL https://snapshots.ethpandaops.io/mainnet/reth/latest)
curl -L "https://snapshots.ethpandaops.io/mainnet/reth/${BLOCK}/snapshot.tar.zst" \
  | pv | zstd -d | tar -xf - -C /data/rpc_nodes/eth-data/reth
```

Or download first if you want resume support:

```bash
BLOCK=$(curl -sL https://snapshots.ethpandaops.io/mainnet/reth/latest)
aria2c -x 16 -s 16 -d /data/rpc_nodes/eth-data \
  "https://snapshots.ethpandaops.io/mainnet/reth/${BLOCK}/snapshot.tar.zst"

# Then extract
tar -I zstd -xvf /data/rpc_nodes/eth-data/snapshot.tar.zst \
  -C /data/rpc_nodes/eth-data/reth
```

**Option B — Merkle.io (~1.34 TB compressed → ~2.4 TB, updated Mon/Thu)**

Browse available snapshots at https://snapshots.merkle.io/ and download:

```bash
# Replace <url> with the .tar.lz4 URL from the Merkle snapshot page
curl -L "<url>" | pv | lz4 -d | tar -xf - -C /data/rpc_nodes/eth-data/reth
```

**Option C — Reth built-in downloader**

```bash
docker run --rm \
  -v /data/rpc_nodes/eth-data/reth:/root/.local/share/reth/mainnet \
  ghcr.io/paradigmxyz/reth:v1.10.0 \
  download --chain mainnet
```

#### Full (pruned) node snapshots

**PublicNode (~950 GB compressed, updated every 24–48 hours)**

Browse https://publicnode.com/snapshots, select Reth mainnet full node, and stream-extract:

```bash
# Replace <url> with the current URL from PublicNode
curl -L "<url>" | pv | zstd -d | tar -xf - -C /data/rpc_nodes/eth-data/reth
```

> PublicNode also offers an archive snapshot (~2.1 TB compressed, v1.9.3, updated weekly).

#### Consensus layer — no snapshot needed

Lighthouse uses **checkpoint sync** and catches up in minutes:

```bash
# Verified public checkpoint endpoints:
# https://beaconstate.ethstaker.cc        (configured in docker-compose.yml)
# https://mainnet-checkpoint-sync.attestant.io
# https://mainnet.checkpoint.sigp.io
```

### 4. Fix ownership

Reth and Lighthouse run as UID 1000 inside the containers:

```bash
sudo chown -R 1000:1000 /data/rpc_nodes/eth-data
```

### 5. Start

```bash
cd /path/to/RPC_nodes/eth
docker compose up -d
```

Lighthouse starts after Reth (`depends_on`) and begins checkpoint sync automatically.

### 6. Verify

```bash
# Execution layer — false means synced
curl -s http://localhost:8555 \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Consensus layer
curl -s http://localhost:5052/eth/v1/node/syncing
```

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8555 | HTTP | Execution JSON-RPC |
| 8556 | WebSocket | Execution WS RPC |
| 30303 | TCP/UDP | Execution P2P |
| 5052 | HTTP | Beacon Node REST API |
| 9100 | TCP/UDP | Lighthouse P2P |
| 8551 | HTTP | Engine API (internal, JWT-protected) |

RPC ports (8555, 8556, 5052) are bound to localhost only. Public access is handled by the shared nginx reverse proxy — see [`nginx/`](../nginx/).

## Storage

| Mode | Compressed | Extracted | Monthly growth |
|------|-----------|-----------|----------------|
| Archive | ~961 GB | ~2.4 TB | ~15 GB |
| Full (pruned) | ~950 GB | ~2.4 TB | ~15 GB |
| Consensus (Lighthouse) | — (checkpoint sync) | ~200–400 GB | ~5 GB |

NVMe is strongly recommended. Extraction is I/O-bound — expect several hours even on fast disks.

## Logs

```bash
docker compose logs -f reth        # Execution layer
docker compose logs -f lighthouse  # Consensus layer
```

## Helper script

`start-after-extract.sh` monitors an ongoing `tar | zstd` extraction, prints progress every 60 seconds, fixes ownership when done, and starts the node automatically:

```bash
bash start-after-extract.sh
```

Useful when running extraction in a separate terminal and you want the node to start hands-free.

## Updating client versions

```bash
# Edit docker-compose.yml image tags, then:
docker compose pull
docker compose up -d
```

Check Reth and Lighthouse release notes before upgrading — breaking DB migrations occasionally require a resync.

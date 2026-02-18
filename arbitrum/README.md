# Arbitrum One Node

## Overview

| Setting | Value |
|---------|-------|
| Client | Nitro v3.9.4 |
| Network | Arbitrum One (chain ID 42161) |
| HTTP RPC | `http://localhost:8547` |
| WebSocket | `ws://localhost:8548` |
| Node data | `/data/rpc_nodes/arbitrum` |

## Archive vs Pruned

**Archive snapshots were discontinued in May 2024** due to unsustainable growth (~850 GB/month). Only pruned snapshots are available. This means:

- All blocks, transactions, receipts, and logs are available
- Historical state (`eth_call` / `eth_getBalance` at old blocks) is **not available**
- `--execution.rpc.log-history=0` is set — no historical state is stored

## Prerequisites

Arbitrum Nitro requires **both** an Ethereum L1 execution RPC and an L1 Beacon API endpoint to function. Set these in `.env` before starting.

```env
# arbitrum/.env
L1_RPC_URL=https://mainnet.infura.io/v3/<YOUR_KEY>
L1_BEACON_URL=https://ethereum-beacon-api.publicnode.com
```

You can also point `L1_RPC_URL` at your local Ethereum node once it is synced:

```env
L1_RPC_URL=http://<host-ip>:8555
L1_BEACON_URL=http://<host-ip>:5052
```

## Setup

### 1. Create data directory

```bash
sudo mkdir -p /data/rpc_nodes/arbitrum
sudo chown -R 1000:1000 /data/rpc_nodes/arbitrum
```

### 2. Configure L1 endpoints

Edit `arbitrum/.env` with your L1 RPC and Beacon API URLs (see Prerequisites above).

### 3. Download the pruned snapshot

Arbitrum publishes multi-part tar snapshots. Check `snapshot-urls.txt` for the current URLs, or find the latest at:

```
https://snapshot.arbitrum.foundation/arb1/
```

The URL pattern is:
```
https://snapshot.arbitrum.foundation/arb1/<DATE>-<HASH>/pruned.tar.part0000
https://snapshot.arbitrum.foundation/arb1/<DATE>-<HASH>/pruned.tar.part0001
...
```

**Download all parts in parallel and extract:**

```bash
BASE="https://snapshot.arbitrum.foundation/arb1/2026-01-17-4d52ed3d"

# Download all parts (update BASE to the latest date from snapshot-urls.txt)
aria2c -x 16 -s 16 -d /tmp/arb-snapshot \
  "${BASE}/pruned.tar.part0000" \
  "${BASE}/pruned.tar.part0001" \
  "${BASE}/pruned.tar.part0002" \
  "${BASE}/pruned.tar.part0003"

# Combine and stream-extract
cat /tmp/arb-snapshot/pruned.tar.part* \
  | tar -xf - -C /data/rpc_nodes/arbitrum
```

Or with wget (sequential, supports resume per part):

```bash
BASE="https://snapshot.arbitrum.foundation/arb1/2026-01-17-4d52ed3d"

for part in 0000 0001 0002 0003; do
  wget --continue -P /tmp/arb-snapshot "${BASE}/pruned.tar.part${part}"
done

cat /tmp/arb-snapshot/pruned.tar.part* \
  | tar -xf - -C /data/rpc_nodes/arbitrum
```

> Check `snapshot-urls.txt` for the current snapshot date. The Arbitrum Foundation publishes new snapshots periodically — using a stale snapshot is fine but means a longer catch-up sync.

### 4. Fix ownership

```bash
sudo chown -R 1000:1000 /data/rpc_nodes/arbitrum
```

### 5. Start

```bash
cd /path/to/RPC_nodes/arbitrum
docker compose up -d
```

### 6. Verify

```bash
# false = fully synced
curl -s http://localhost:8547 \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Current block number
curl -s http://localhost:8547 \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8547 | HTTP | JSON-RPC |
| 8548 | WebSocket | WS JSON-RPC |

> No P2P ports are needed for a Nitro full node. Arbitrum Nitro syncs from the L1 chain and the sequencer feed, not from peers.

## Storage

| Type | Size | Monthly growth |
|------|------|----------------|
| Pruned (only option) | ~2–3 TB | ~200 GB |

NVMe is strongly recommended. The snapshot parts total several hundred GB — extraction is I/O-bound.

## Logs

```bash
docker compose logs -f arbitrum
```

## Helper script

`check-sync.sh` polls `eth_syncing` every 60 seconds, prints block progress, and exits with a desktop notification when the node is fully synced:

```bash
bash check-sync.sh
```

## Gotchas

- **Both L1 endpoints are required.** Nitro uses the L1 execution RPC to read rollup state and the Beacon API to fetch blob data (EIP-4844). Without either, the node will not start or will stall.
- **Pruned only.** Do not attempt `eth_call` at old blocks — it will return an error.
- **Snapshot parts must be combined in order.** `cat part0000 part0001 ...` produces a single tar stream. Do not extract parts individually.
- **`--node.staker.enable=false`** — this is a non-validating read-only node.

## Updating client version

```bash
# Edit image tag in docker-compose.yml, then:
docker compose pull
docker compose up -d
```

Check the [Nitro release notes](https://github.com/OffchainLabs/nitro/releases) for breaking changes before upgrading.

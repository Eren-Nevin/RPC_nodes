# RPC Node Monorepo

Self-hosted RPC node infrastructure for multiple blockchain networks. Each chain lives in its own directory with a `docker-compose.yml`, snapshot URLs, and helper scripts.

## Supported Chains

| Chain | Clients | Type | Storage | Monthly Growth | RPC Port |
|-------|---------|------|---------|----------------|----------|
| Ethereum L1 | Reth + Lighthouse | Full/Archive | ~2.4 TB | ~15 GB | 8555 |
| Arbitrum One | Nitro | Pruned | ~2-3 TB | ~200 GB | 8547 |
| Base (OP Stack) | Reth / Geth / Nethermind + op-node | Archive | ~7-8 TB | 50-100 GB/week | 8645 |
| Polygon PoS | Bor + Heimdall | Full | ~6 TB | ~3 TB | 8745 |

## Prerequisites

- Docker and Docker Compose
- Sufficient disk space (see table above; plan for **20-25 TB** total across all chains)
- An Ethereum L1 RPC endpoint (e.g. Infura) -- required by Arbitrum, Base, and Polygon
- An Ethereum Beacon API endpoint (e.g. PublicNode) -- required by Arbitrum and Base
- `rclone` (for Polygon snapshot downloads)
- `aria2c` and `lz4` (for BSC snapshot downloads)

## Directory Layout

```
.
├── eth/                # Ethereum L1 (Reth + Lighthouse)
├── arbitrum/           # Arbitrum One (Nitro)
├── base/               # Base L2 (OP Stack, git submodule)
├── polygon/            # Polygon PoS (Bor + Heimdall)
├── bsc/                # BSC (snapshot tooling, WIP)
├── chains_self_host.md # Detailed hardware/software specs for 22+ chains
├── RPC_ENDPOINTS.md    # Port mapping reference
└── RPC_NODE.md         # Deployment template / version pinning
```

### Data directory on disk

All chain data lives under `/data/rpc_nodes/`:

```
/data/rpc_nodes/
├── eth-data/
│   ├── reth/
│   └── lighthouse/
├── arbitrum/
├── base-data/
│   └── reth/snapshots/mainnet/download/
└── polygon-data/
    ├── heimdall/
    └── bor/
```

---

## RPC Endpoints

Once running, nodes expose:

| Chain | Protocol | Port | URL |
|-------|----------|------|-----|
| Ethereum | HTTP | 8555 | `http://localhost:8555` |
| Ethereum | WebSocket | 8556 | `ws://localhost:8556` |
| Ethereum | Beacon API | 5052 | `http://localhost:5052` |
| Arbitrum | HTTP | 8547 | `http://localhost:8547` |
| Base | HTTP | 8645 | `http://localhost:8645` |
| Base | WebSocket | 8646 | `ws://localhost:8646` |
| Base | op-node | 7545 | `http://localhost:7545` |
| Polygon | HTTP | 8745 | `http://localhost:8745` |
| Polygon | WebSocket | 8746 | `ws://localhost:8746` |
| Polygon | Heimdall | 26657 | `http://localhost:26657` |

---

## Per-Chain Setup

### Ethereum L1

**Stack:** Reth v1.10.0 (execution) + Lighthouse v8.0.1 (consensus)

#### 1. Generate or use the JWT secret

A `jwt.hex` file is required for authenticated communication between Reth and Lighthouse. One is already provided in `eth/`. To generate a new one:

```bash
openssl rand -hex 32 > eth/jwt.hex
```

#### 2. Download a snapshot (recommended)

Syncing from genesis takes weeks. Use a snapshot instead.

**Option A -- ethPandaOps Reth Archive (recommended):**

```bash
# Get the latest snapshot URL
LATEST=$(curl -sL https://snapshots.ethpandaops.io/mainnet/reth/latest)
URL="https://snapshots.ethpandaops.io/mainnet/reth/${LATEST}/snapshot.tar.zst"

# Stream-extract directly to avoid needing 2x disk space
curl -L "$URL" | pv | zstd -d | tar -xf - -C /data/rpc_nodes/eth-data/reth
```

**Option B -- Merkle.io Reth Archive:**
- ~1.34 TB compressed, ~2.4 TB extracted (lz4)
- Updated Monday and Thursday
- Browse: https://snapshots.merkle.io/

**Option C -- PublicNode Reth Full Node:**
- ~950 GB compressed
- Updated every 24-48 hours
- Browse: https://publicnode.com/snapshots

> **Full vs Archive:** A full node stores all blocks, transactions, receipts, and logs. An archive node adds all historical state, which is required for historical `eth_call` at arbitrary block heights. Most use-cases only need a full node.

#### 3. Fix ownership and start

```bash
# Snapshot data must be owned by UID 1000 (the user inside the container)
sudo chown -R 1000:1000 /data/rpc_nodes/eth-data/reth

cd eth
docker compose up -d
```

Lighthouse uses **checkpoint sync** (`https://beaconstate.ethstaker.cc`) so the beacon chain catches up in minutes rather than days.

#### 4. Verify

```bash
# Execution layer
curl -s http://localhost:8555 \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Consensus layer
curl -s http://localhost:5052/eth/v1/node/syncing
```

#### Helper script

`eth/start-after-extract.sh` monitors an ongoing tar extraction, fixes ownership, and auto-starts the node when extraction finishes.

---

### Arbitrum One

**Stack:** Nitro v3.9.4

#### 1. Configure L1 endpoints

Copy or edit `arbitrum/.env`:

```env
L1_RPC_URL=https://mainnet.infura.io/v3/<YOUR_KEY>
L1_BEACON_URL=https://ethereum-beacon-api.publicnode.com
```

You can also point `L1_RPC_URL` at your local Ethereum node (`http://<host>:8555`) once it is synced.

#### 2. Download a snapshot

Arbitrum provides multi-part pruned snapshots. Check `arbitrum/snapshot-urls.txt` for current URLs.

```bash
# Download all parts
for i in 0000 0001 0002 0003; do
  wget "https://snapshot.arbitrum.foundation/arb1/<DATE>/pruned.tar.part${i}" \
    -P /tmp/arb-snapshot/
done

# Combine and extract
cat /tmp/arb-snapshot/pruned.tar.part* | tar -xf - -C /data/rpc_nodes/arbitrum
```

> **Archive snapshots are discontinued** since May 2024 due to unsustainable growth (~850 GB/month). Only pruned snapshots are available.

#### 3. Start

```bash
cd arbitrum
docker compose up -d
```

#### 4. Monitor sync

```bash
# One-shot check
curl -s http://localhost:8547 \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Continuous monitoring (polls every 60s, desktop notification on completion)
bash arbitrum/check-sync.sh
```

#### Gotchas

- The node requires **both** an L1 execution RPC and an L1 Beacon API endpoint.
- `--node.staker.enable=false` -- this is a non-validating node. Do not enable staking unless you know what you're doing.
- Log history is set to `0` (no historical state). This is a pruned node; you cannot do `eth_call` at old blocks.

---

### Base (OP Stack L2)

**Stack:** Reth (recommended), Geth, or Nethermind + op-node

Base uses the official [base/node](https://github.com/base/node) repository as a **git submodule** under `base/base-node/`.

#### 1. Initialize the submodule

```bash
git submodule update --init --recursive
```

#### 2. Configure environment

Create or edit `base/base-node/.env.custom` (or use the existing `.env.mainnet`):

```env
CLIENT=reth
HOST_DATA_DIR=/data/rpc_nodes/base-data/reth/snapshots/mainnet/download
NETWORK_ENV=.env.custom

OP_NODE_L1_ETH_RPC=https://mainnet.infura.io/v3/<YOUR_KEY>
OP_NODE_L1_BEACON=https://ethereum-beacon-api.publicnode.com
OP_NODE_L1_RPC_KIND=infura

OP_NODE_L2_ENGINE_AUTH_RAW=<random 64-char hex>
```

Generate the engine JWT:

```bash
openssl rand -hex 32
```

#### 3. Download a snapshot

```bash
# Stream the latest Reth archive snapshot directly
SNAPSHOT_URL=$(curl -sL https://mainnet-reth-archive-snapshots.base.org/latest)
curl -L "$SNAPSHOT_URL" | pv | zstd -d | tar -xf - -C /data/rpc_nodes/base-data/reth/snapshots/mainnet/download
```

This is ~4.3 TB compressed and expands to 7-8 TB.

#### 4. Start

```bash
cd base/base-node

# Reth on mainnet (recommended)
CLIENT=reth NETWORK_ENV=.env.custom docker compose up --build -d

# Or Geth on mainnet
docker compose up --build -d

# Or Nethermind on Sepolia testnet
CLIENT=nethermind NETWORK_ENV=.env.sepolia docker compose up --build -d
```

#### 5. Verify

```bash
# Execution layer
curl -s http://localhost:8645 \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# op-node
curl -s http://localhost:7545 \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}'
```

#### Gotchas

- **Use Reth, not Geth** for archive nodes. Geth archive for Base grows to ~46 TB and is impractical.
- The Base node runs **two containers**: an execution client and `op-node` (OP Stack consensus). Both must be running.
- `OP_NODE_L2_ENGINE_AUTH_RAW` must be the **same** JWT token in both the execution client and op-node configs.
- Sync mode is `execution-layer` -- the node syncs execution data and derives consensus from L1.
- The submodule pins a specific version. To update: `cd base/base-node && git fetch && git checkout <tag>`.
- Growth is 50-100 GB/week; monitor disk usage.

---

### Polygon PoS

**Stack:** Bor v2.5.7 (execution) + Heimdall v2.0.0-beta4 (consensus)

Polygon requires **two** services that must run together. Heimdall handles consensus (Tendermint-based) and Bor handles EVM execution.

#### 1. Configure L1 endpoint

Edit `polygon/.env`:

```env
ETH_RPC_URL=https://mainnet.infura.io/v3/<YOUR_KEY>
```

#### 2. Download snapshots

Polygon needs **two separate snapshots**: one for Heimdall (~1 TB) and one for Bor (~4.7 TB). Total: ~6 TB.

**Recommended: StakeCraft via rclone (stream-extract to save disk space)**

First, configure rclone with the StakeCraft R2 bucket. Add to `~/.config/rclone/rclone.conf`:

```ini
[r2]
type = s3
provider = Cloudflare
access_key_id = 849df1cd0e8666858df4b1e182a4b2cd
secret_access_key = 568a53f5d4ca2b3d38780cd3e7a11ce2d6fe2887fbbe04405a96fc77021e917c
endpoint = https://dd74dc687a5ce54107082a6849814c19.r2.cloudflarestorage.com
```

Then stream-extract both snapshots:

```bash
# Heimdall (~1 TB)
rclone cat "r2:sc-snapshots/heimdall-mainnet_2026-01-28.tar.gz" \
  | pv | tar -xzf - -C /data/rpc_nodes/polygon-data/heimdall

# Bor (~4.7 TB)
rclone cat "r2:sc-snapshots/bor-pebble-mainnet_2026-01-26.tar" \
  | pv | tar -xf - -C /data/rpc_nodes/polygon-data/bor/chaindata
```

Check `polygon/snapshot-urls.txt` for updated snapshot dates and alternative providers (PublicNode, All4Nodes).

#### 3. Start

```bash
cd polygon
docker compose up -d
```

Heimdall starts first (Bor has `depends_on: heimdall`).

#### 4. Verify

```bash
# Bor (execution)
curl -s http://localhost:8745 \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Heimdall (consensus)
curl -s http://localhost:26657/status
```

#### Gotchas

- **Both Heimdall and Bor must run together.** Bor depends on Heimdall for consensus checkpoints. If Heimdall is down, Bor will stall.
- **Storage growth is extreme** (~3 TB/month). Archive mode is no longer practical. Plan for regular pruning or expanding storage.
- Heimdall needs an Ethereum L1 RPC to verify checkpoints. This is the `ETH_RPC_URL` in `.env`.
- Bor uses the `pebble` database engine with compression enabled to reduce disk usage.
- Snapshot dates in `rclone` commands are point-in-time. Check the StakeCraft bucket for the latest: `rclone ls r2:sc-snapshots/ | grep polygon` or check `polygon/snapshot-urls.txt`.
- Heimdall seeds are hardcoded in the compose file. If they become stale, check the [Polygon docs](https://wiki.polygon.technology/) for updated seeds.

---

## Shared L1 Dependency

Arbitrum, Base, and Polygon all require an Ethereum L1 RPC endpoint. You have two options:

1. **External provider** (Infura, Alchemy, QuickNode, etc.) -- simpler, but adds a dependency and potential rate limits.
2. **Your own Ethereum node** -- point `.env` files at `http://<eth-host>:8555` once the Ethereum node in this repo is synced. This is the recommended long-term setup.

For Base and Arbitrum, you also need an **L1 Beacon API** endpoint. Options:
- Your own Lighthouse: `http://<eth-host>:5052`
- PublicNode: `https://ethereum-beacon-api.publicnode.com`

---

## General Gotchas

### Disk I/O

NVMe SSDs are strongly recommended. Spinning disks and SATA SSDs will bottleneck sync and query performance. Snapshot extraction is also I/O-bound -- expect multi-hour extraction times even on NVMe.

### Snapshot streaming

When possible, **stream-extract** snapshots rather than downloading then extracting. This avoids needing 2x the disk space:

```bash
# Good -- stream extract (needs 1x space)
curl -L "$URL" | pv | zstd -d | tar -xf - -C /target

# Bad -- download then extract (needs 2x space)
wget "$URL" -O snapshot.tar.zst
tar -xf snapshot.tar.zst -C /target
```

### Container ownership

Reth and other clients run as UID `1000` inside containers. After extracting snapshots, fix ownership:

```bash
sudo chown -R 1000:1000 /data/rpc_nodes/<chain-data>
```

### Port conflicts

Each chain uses unique ports to avoid conflicts. See the [RPC Endpoints](#rpc-endpoints) table. If you change ports in a compose file, update your reverse proxy or firewall accordingly.

### Firewall

Open P2P ports for peering. Without these, your node won't find peers and syncing will be slow or stall:

| Chain | P2P Ports |
|-------|-----------|
| Ethereum | 30303/tcp+udp, 9100/tcp+udp |
| Arbitrum | (no P2P needed for Nitro full node) |
| Base | 30403/tcp+udp, 9222/tcp+udp |
| Polygon | 30503/tcp+udp, 26656/tcp |

Keep RPC ports (8545, 8547, etc.) **closed** to the public internet unless behind authentication or a reverse proxy.

### Monitoring sync progress

All nodes expose `eth_syncing` on their RPC port. A response of `false` means the node is synced. Anything else shows current vs. target block.

```bash
curl -s http://localhost:<PORT> \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

### Updating client versions

Pin versions in docker-compose files. To upgrade:

1. Check release notes for breaking changes
2. Update the image tag in `docker-compose.yml`
3. `docker compose pull && docker compose up -d`

For Base (submodule): `cd base/base-node && git fetch --tags && git checkout <new-tag>`

---

## Client Versions

| Chain | Component | Version |
|-------|-----------|---------|
| Ethereum | Reth | v1.10.0 |
| Ethereum | Lighthouse | v8.0.1 |
| Arbitrum | Nitro | v3.9.4-7f582c3 |
| Base | op-node | v1.16.2 |
| Base | op-reth | v1.9.3 |
| Base | op-geth | v1.101603.5 |
| Base | Nethermind | 1.35.3 |
| Polygon | Bor | v2.5.7 |
| Polygon | Heimdall | v2.0.0-beta4 |

---

## Helper Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `start-after-extract.sh` | `eth/` | Monitors snapshot extraction, fixes ownership, auto-starts Ethereum node |
| `check-sync.sh` | `arbitrum/` | Polls sync status every 60s with desktop notification on completion |
| `fetch-snapshot.sh` | `bsc/` | Downloads, verifies, and extracts BSC snapshots (aria2c + lz4) |

---

## Quick Start (all chains)

```bash
# 1. Clone with submodules
git clone --recurse-submodules <repo-url>
cd RPC_nodes

# 2. Create data directories
sudo mkdir -p /data/rpc_nodes/{eth-data/{reth,lighthouse},arbitrum,base-data,polygon-data/{heimdall,bor}}
sudo chown -R 1000:1000 /data/rpc_nodes

# 3. Set up .env files with your L1 endpoints
#    - arbitrum/.env
#    - polygon/.env
#    - base/base-node/.env.custom (or .env.mainnet)

# 4. Download snapshots for each chain (see per-chain sections above)

# 5. Start all nodes
cd eth && docker compose up -d && cd ..
cd arbitrum && docker compose up -d && cd ..
cd base/base-node && CLIENT=reth NETWORK_ENV=.env.custom docker compose up --build -d && cd ../..
cd polygon && docker compose up -d && cd ..
```

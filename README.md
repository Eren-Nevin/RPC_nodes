# RPC Node Monorepo

Self-hosted RPC node infrastructure for multiple blockchain networks. Each chain lives in its own directory with a `docker-compose.yml`, snapshot URLs, and helper scripts.

---

## Initial Setup

```bash
# 1. Clone with submodules
git clone --recurse-submodules https://github.com/Eren-Nevin/RPC_nodes.git
cd RPC_nodes

# 2. Create data directories and start nginx
#    (creates /data/rpc_nodes/** with correct ownership, then starts nginx)
docker compose up -d
```

`docker compose up -d` runs two services:
- **init** — creates all data directories under `/data/rpc_nodes/` with `chown 1000:1000`
- **nginx** — starts the shared reverse proxy (depends on `init` completing first)

To re-run just the directory init (e.g. after adding a new chain):

```bash
docker compose run --rm init
```

---

## Supported Chains

| Chain | Clients | Type | Storage | Monthly Growth | RPC Port |
|-------|---------|------|---------|----------------|----------|
| Ethereum L1 | Reth + Lighthouse | Full/Archive | ~2.4 TB | ~15 GB | 8555 |
| Arbitrum One | Nitro | Pruned | ~2-3 TB | ~200 GB | 8547 |
| Base (OP Stack) | Reth / Geth / Nethermind + op-node | Archive | ~7-8 TB | 50-100 GB/week | 8645 |
| Polygon PoS | Bor + Heimdall | Full | ~6 TB | ~3 TB | 8745 |

---

## Directory Layout

```
.
├── init-data-dirs.sh   # Creates /data/rpc_nodes/** (called by docker-compose init service)
├── open-ports.sh       # Configures UFW firewall rules (run once on host)
├── docker-compose.yml  # Root compose: init + nginx services
├── download-snapshot   # Snapshot download/extract script (see below)
├── eth/                # Ethereum L1 (Reth + Lighthouse)
├── arbitrum/           # Arbitrum One (Nitro)
├── base/               # Base L2 (OP Stack, git submodule)
├── polygon/            # Polygon PoS (Bor + Heimdall)
├── bsc/                # BSC (snapshot tooling, WIP)
├── nginx/              # Shared reverse proxy config (rpc.defistream.dev)
└── chains_self_host.md # Hardware/storage reference for 22+ chains
```

### Docker Compose locations

| Chain | Compose file |
|-------|-------------|
| Nginx + init | `docker-compose.yml` |
| Ethereum | `eth/docker-compose.yml` |
| Arbitrum | `arbitrum/docker-compose.yml` |
| Base | `base/base-node/docker-compose.yml` |
| Polygon | `polygon/docker-compose.yml` |

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
├── polygon-data/
│   ├── heimdall/data/
│   └── bor/bor/chaindata/
└── bsc-data/
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
| Arbitrum | WebSocket | 8548 | `ws://localhost:8548` |
| Base | HTTP | 8645 | `http://localhost:8645` |
| Base | WebSocket | 8646 | `ws://localhost:8646` |
| Base | op-node | 7545 | `http://localhost:7545` |
| Polygon | HTTP | 8745 | `http://localhost:8745` |
| Polygon | WebSocket | 8746 | `ws://localhost:8746` |
| Polygon | Heimdall | 26657 | `http://localhost:26657` |

---

## Reverse Proxy (public access)

All chains are exposed publicly through a single nginx container at **`rpc.defistream.dev`** using path-based routing. The nginx service is part of the root `docker-compose.yml`.

| Public URL | Chain | Protocol |
|-----------|-------|----------|
| `https://rpc.defistream.dev/eth` | Ethereum | HTTP JSON-RPC |
| `wss://rpc.defistream.dev/eth` | Ethereum | WebSocket |
| `https://rpc.defistream.dev/arbitrum` | Arbitrum One | HTTP JSON-RPC |
| `wss://rpc.defistream.dev/arbitrum` | Arbitrum One | WebSocket |
| `https://rpc.defistream.dev/base` | Base | HTTP JSON-RPC |
| `wss://rpc.defistream.dev/base` | Base | WebSocket |
| `https://rpc.defistream.dev/polygon` | Polygon PoS | HTTP JSON-RPC |
| `wss://rpc.defistream.dev/polygon` | Polygon PoS | WebSocket |

HTTP and WebSocket share the same URL — nginx detects `Upgrade: websocket` and routes to the correct backend port automatically.

The entire `/etc/letsencrypt` directory is mounted read-only so that symlinks in `live/` (pointing into `archive/`) resolve correctly. The container uses `network_mode: host` and reaches all node ports on `127.0.0.1` directly.

### Certificate setup

```bash
# First-time certificate issuance (run before starting nginx)
sudo certbot certonly --standalone -d rpc.defistream.dev

# Verify certs exist
ls /etc/letsencrypt/live/defistream.dev/
# fullchain.pem  privkey.pem  cert.pem  chain.pem
```

### nginx config files

```
nginx/
├── nginx.conf                          # events/http block
└── conf.d/
    └── rpc.defistream.dev.conf         # TLS, path routing, backends
```

### nginx operations

```bash
# Test config before reloading
docker compose exec nginx nginx -t

# Graceful reload (no downtime)
docker compose exec nginx nginx -s reload

# Tail logs
docker compose logs -f nginx
```

### Adding a new chain

1. Bind the node to a new host port (e.g. `8847` HTTP, `8848` WS).
2. Add a `location` block in `nginx/conf.d/rpc.defistream.dev.conf` routing `/chainname` to the new backend.
3. Run `docker compose exec nginx nginx -s reload`.

---

## Snapshot Download

Use the `download-snapshot` script to download and extract snapshots for any supported chain.

```
./download-snapshot -n <node> [-t full|pruned] [-x] [-d <data-root>]

  -n  Node (required): eth | arb | base | polygon
  -t  Snapshot type: full (default) | pruned
  -x  Extract-only: scan data dir for already-downloaded files and extract them
  -d  Override data root (default: /data/rpc_nodes)
  -h  Help
```

**Required tools:** `aria2c`, `zstd`, `lz4`

```bash
# Install on Ubuntu/Debian
apt-get install aria2 zstd lz4
```

### Per-chain snapshot support

| Node | `full` | `pruned` | Source |
|------|--------|----------|--------|
| eth | ✅ ~2.4 TB | ❌ | ethPandaOps (auto-resolved) |
| arb | ❌ | ✅ ~2-3 TB | Arbitrum Foundation (multi-part) |
| base | ✅ ~7-8 TB | ✅ ~4-5 TB | base.org (auto-resolved) |
| polygon | ✅ ~6 TB | ❌ | PublicNode (3 × lz4, auto-discovered) |

### Examples

```bash
# Ethereum — download and extract full archive
./download-snapshot -n eth

# Arbitrum — pruned is the only option
./download-snapshot -n arb -t pruned

# Base — archive (full)
./download-snapshot -n base -t full

# Base — pruned / full-node size
./download-snapshot -n base -t pruned

# Polygon — downloads 3 lz4 files (heimdall + bor-base + bor-part)
./download-snapshot -n polygon

# Extract-only mode (files already downloaded, just extract)
./download-snapshot -n eth -x
./download-snapshot -n arb -t pruned -x
./download-snapshot -n polygon -x
```

> **Tip:** Run inside `screen` or `tmux` — downloads can take many hours.

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

Syncing from genesis takes weeks. Use the snapshot script instead:

```bash
./download-snapshot -n eth
```

This resolves the latest ethPandaOps Reth archive URL automatically, downloads with aria2c (16 connections), extracts to `/data/rpc_nodes/eth-data/reth/`, and fixes ownership.

#### 3. Start

```bash
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

Arbitrum provides multi-part pruned snapshots only (archive discontinued May 2024). URLs are stored in `arbitrum/snapshot-urls.txt`.

```bash
./download-snapshot -n arb -t pruned
```

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
- `--node.staker.enable=false` — this is a non-validating node. Do not enable staking unless you know what you're doing.
- Log history is set to `0` (no historical state). This is a pruned node; you cannot do `eth_call` at old blocks.

---

### Base (OP Stack L2)

**Stack:** Reth (recommended), Geth, or Nethermind + op-node

Base uses the official [base/node](https://github.com/base/node) repository as a **git submodule** under `base/base-node/`.

#### 1. Initialize the submodule

Submodule source: `https://github.com/base/node.git`

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
# Archive (7-8 TB extracted)
./download-snapshot -n base -t full

# Or pruned / full-node size
./download-snapshot -n base -t pruned
```

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
- Sync mode is `execution-layer` — the node syncs execution data and derives consensus from L1.
- The submodule pins a specific version. To update: `cd base/base-node && git fetch && git checkout <tag>`.
- Growth is 50-100 GB/week; monitor disk usage.

---

### Polygon PoS

**Stack:** Bor v2.5.7 (execution) + Heimdall v0.6.0 (consensus)

Polygon requires **two** services that must run together. Heimdall handles consensus (Tendermint-based) and Bor handles EVM execution.

#### 1. Configure L1 endpoint

Edit `polygon/.env`:

```env
ETH_RPC_URL=https://mainnet.infura.io/v3/<YOUR_KEY>
```

#### 2. Download snapshots

Polygon needs **two separate snapshots**: one for Heimdall (~1 TB) and one for Bor (~4.7 TB). Total: ~6 TB.

```bash
./download-snapshot -n polygon
```

This auto-discovers the latest PublicNode URLs (heimdall + bor-base + bor-part), downloads all three with aria2c (16 connections each), and extracts them to the correct directories. Falls back to `polygon/snapshot-urls.txt` if auto-discovery fails.

See `polygon/snapshot-urls.txt` for alternative providers (StakeCraft rclone, all4nodes.io).

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
- Heimdall seeds are hardcoded in the compose file. If they become stale, check the [Polygon docs](https://wiki.polygon.technology/) for updated seeds.

---

## Shared L1 Dependency

Arbitrum, Base, and Polygon all require an Ethereum L1 RPC endpoint. You have two options:

1. **External provider** (Infura, Alchemy, QuickNode, etc.) — simpler, but adds a dependency and potential rate limits.
2. **Your own Ethereum node** — point `.env` files at `http://<eth-host>:8555` once the Ethereum node in this repo is synced. This is the recommended long-term setup.

For Base and Arbitrum, you also need an **L1 Beacon API** endpoint. Options:
- Your own Lighthouse: `http://<eth-host>:5052`
- PublicNode: `https://ethereum-beacon-api.publicnode.com`

---

## General Gotchas

### Disk I/O

NVMe SSDs are strongly recommended. Spinning disks and SATA SSDs will bottleneck sync and query performance. Snapshot extraction is also I/O-bound — expect multi-hour extraction times even on NVMe.

### Snapshot streaming

When possible, **stream-extract** snapshots rather than downloading then extracting. This avoids needing 2x the disk space. The `download-snapshot` script downloads first then extracts (supports resume via aria2c). For stream-extract, see the manual commands in each chain's `snapshot-urls.txt`.

### Container ownership

Reth and other clients run as UID `1000` inside containers. The `download-snapshot` script runs `chown -R 1000:1000` automatically after extraction. The `init` service also sets correct ownership on all data directories at startup.

### Port conflicts

Each chain uses unique ports to avoid conflicts. See the [RPC Endpoints](#rpc-endpoints) table. If you change ports in a compose file, update your reverse proxy or firewall accordingly.

### Firewall

Run `open-ports.sh` once on the host to configure UFW:

```bash
sudo ./open-ports.sh
```

This opens ports 80/443 (nginx) and all P2P peering ports. RPC ports are not exposed publicly — external traffic reaches them only via nginx `proxy_pass` on `127.0.0.1`.

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
| Polygon | Heimdall | v0.6.0 |

---

## Helper Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `download-snapshot` | root | Download and extract snapshots for any chain |
| `init-data-dirs.sh` | root | Create `/data/rpc_nodes/**` with correct ownership |
| `open-ports.sh` | root | Configure UFW firewall rules (run once on host) |
| `start-after-extract.sh` | `eth/` | Monitors snapshot extraction, fixes ownership, auto-starts Ethereum node |
| `check-sync.sh` | `arbitrum/` | Polls sync status every 60s with desktop notification on completion |
| `fetch-snapshot.sh` | `bsc/` | Downloads, verifies, and extracts BSC snapshots (aria2c + lz4) |

---

## Quick Start (all chains)

```bash
# 1. Clone with submodules
git clone --recurse-submodules https://github.com/Eren-Nevin/RPC_nodes.git
cd RPC_nodes

# 2. Create data directories and start nginx
docker compose up -d

# 3. Set up .env files with your L1 endpoints
#    - arbitrum/.env
#    - polygon/.env
#    - base/base-node/.env.custom (or .env.mainnet)

# 4. Download snapshots (each takes many hours — run in screen/tmux)
./download-snapshot -n eth
./download-snapshot -n arb -t pruned
./download-snapshot -n base -t full
./download-snapshot -n polygon

# 5. Start each chain node
cd eth && docker compose up -d && cd ..
cd arbitrum && docker compose up -d && cd ..
cd base/base-node && CLIENT=reth NETWORK_ENV=.env.custom docker compose up --build -d && cd ../..
cd polygon && docker compose up -d && cd ..
```

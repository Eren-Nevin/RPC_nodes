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
| Arbitrum One | Nitro | Full | ~2.8 TB | ~200 GB | 8547 |
| Base (OP Stack) | Reth / Geth / Nethermind + op-node | Archive | ~7-8 TB | 50-100 GB/week | 8645 |
| Polygon PoS | Bor + Heimdall | Full | ~6 TB | ~3 TB | 8745 |
| Tron | java-tron | Full / Lite | ~2.9 TB / ~57 GB | ~200 GB | 8190 |

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
├── tron/               # Tron (java-tron)
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
| Tron | `tron/docker-compose.yml` |

### Data directory on disk

All chain data lives under `/data/rpc_nodes/`:

```
/data/rpc_nodes/
├── eth-data/        # populated by download-snapshot / Reth + Lighthouse
├── arbitrum/        # populated by download-snapshot / Nitro
├── base-data/       # populated by download-snapshot / op-reth
├── polygon-data/    # populated by download-snapshot / Bor + Heimdall
├── bsc-data/
└── tron-data/       # populated by download-snapshot / java-tron
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
| Tron | HTTP RPC | 8190 | `http://localhost:8190` |
| Tron | gRPC | 50051 | `localhost:50051` |

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

  -n  Node (required): eth | arb | base | polygon | bsc | tron
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

> **Note:** The script writes to `/data/rpc_nodes/` and sets ownership, so it must be run with `sudo`.

### Per-chain snapshot support

| Node | `full` | `pruned` | Source |
|------|--------|----------|--------|
| eth | ✅ ~2.4 TB | ❌ | ethPandaOps (auto-resolved) |
| arb | ✅ ~2.8 TB | ❌ | PublicNode (base + part lz4, auto-discovered) |
| base | ✅ ~7-8 TB | ✅ ~4-5 TB | base.org (auto-resolved) |
| polygon | ✅ ~6 TB | ❌ | PublicNode (3 × lz4, auto-discovered) |
| tron | ✅ ~2.875 TB | ✅ ~57 GB | TRON Foundation servers (auto-discovered) |

### Examples

```bash
# Ethereum — download and extract full archive
sudo ./download-snapshot -n eth

# Arbitrum — full is the only option
sudo ./download-snapshot -n arb

# Base — archive (full)
sudo ./download-snapshot -n base -t full

# Base — pruned / full-node size
sudo ./download-snapshot -n base -t pruned

# Polygon — downloads 3 lz4 files (heimdall + bor-base + bor-part)
sudo ./download-snapshot -n polygon

# Tron — full node (~2.875 TB)
sudo ./download-snapshot -n tron -t full

# Tron — lite fullnode (downloaded then extracted, ~57 GB)
sudo ./download-snapshot -n tron -t pruned

# Extract-only mode (files already downloaded, just extract)
sudo ./download-snapshot -n eth -x
sudo ./download-snapshot -n arb -x
sudo ./download-snapshot -n polygon -x
sudo ./download-snapshot -n tron -x
```

> **Tip:** Run inside `screen` or `tmux` — downloads can take many hours.

---

## Per-Chain Setup

### Ethereum L1

**Stack:** Reth v1.10.0 (execution) + Lighthouse v8.0.1 (consensus)

#### 1. JWT secret

A pre-generated `eth/jwt.hex` is committed to the repo — no action needed. It is used only for local engine API communication between Reth and Lighthouse inside Docker.

#### 2. Download a snapshot (recommended)

Syncing from genesis takes weeks. Use the snapshot script instead:

```bash
sudo ./download-snapshot -n eth
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

```bash
cp arbitrum/.env.example arbitrum/.env
# then edit L1_RPC_URL if not using the local eth node
```

`arbitrum/.env` has a single variable — the Beacon URL defaults to PublicNode:

```env
L1_RPC_URL=http://172.17.0.1:8555
```

#### 2. Download a snapshot

Arbitrum full snapshots are sourced from PublicNode (lz4 format). The script auto-discovers current URLs from `publicnode.com/snapshots` and falls back to `arbitrum/snapshot-urls.txt`.

```bash
sudo ./download-snapshot -n arb
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

**Stack:** Reth + op-node

Base uses the official [base/node](https://github.com/base/node) repository as a **git submodule** under `base/base-node/`.

#### 1. Initialize the submodule

Submodule source: `https://github.com/base/node.git`

```bash
git submodule update --init --recursive
```

#### 2. Configure environment

```bash
cp base/.env.example base/.env
# then edit OP_NODE_L1_ETH_RPC if not using the local eth node
```

`base/.env` has a single variable:

```env
OP_NODE_L1_ETH_RPC=http://172.17.0.1:8555
```

All other settings (JWT, network, P2P bootnodes, beacon URLs, etc.) are pre-configured defaults in `base/docker-compose.yml`.

#### 3. Download a snapshot

```bash
# Archive (7-8 TB extracted)
sudo ./download-snapshot -n base -t full

# Or pruned / full-node size
sudo ./download-snapshot -n base -t pruned
```

#### 4. Start

```bash
cd base
docker compose up -d
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

- The Base node runs **two containers**: an execution client (Reth) and `op-node` (OP Stack consensus). Both must be running.
- The JWT (`OP_NODE_L2_ENGINE_AUTH_RAW`) is pre-set in `docker-compose.yml` and shared automatically between the execution client and op-node — no manual generation needed.
- Sync mode is `consensus-layer` — op-node derives safe/finalized heads from L1 and gets unsafe blocks via P2P. This avoids EL sync state machine issues with Reth snapshots.
- `OP_NODE_L1_RPC_KIND` is set to `basic` since the local L1 is Reth (not Geth). Use `debug_geth` for Geth, `alchemy`/`infura` for hosted providers.
- **Beacon archiver**: Post-Ecotone, Base derivation requires L1 blob data. Local Lighthouse prunes blobs after ~18 days. `OP_NODE_L1_BEACON_ARCHIVER` must point to a public endpoint (e.g. `https://ethereum-beacon-api.publicnode.com`) for historical blob retrieval, while `OP_NODE_L1_BEACON` can remain on the local beacon node for recent data.
- **Restart both containers together** when changing L1 RPC or sync settings — Reth's engine state must reset alongside op-node. Use `docker compose up -d --force-recreate` (not `restart`) to pick up env var changes.
- The submodule pins a specific version. To update: `cd base/base-node && git fetch && git checkout <tag>`.
- Growth is 50-100 GB/week; monitor disk usage.

---

### Polygon PoS

**Stack:** Bor v2.5.7 (execution) + Heimdall v0.6.0 (consensus)

Polygon requires **two** services that must run together. Heimdall handles consensus (Tendermint-based) and Bor handles EVM execution.

#### 1. Configure L1 endpoint

Heimdall reads its L1 RPC URL from `config/app.toml` inside the heimdall home directory (set during init). Edit after running `heimdall init`:

```toml
# /data/rpc_nodes/polygon-data/heimdall/config/app.toml
eth_rpc_url = "http://172.17.0.1:8555"
bor_rpc_url = "http://172.17.0.1:8745"
```

#### 2. Download snapshots

Polygon needs **two separate snapshots**: one for Heimdall (~1 TB) and one for Bor (~4.7 TB). Total: ~6 TB.

```bash
sudo ./download-snapshot -n polygon
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

### Tron

**Stack:** java-tron v4.8.1

#### 1. Download a snapshot

Tron snapshots are served by the TRON Foundation (~3x/week). The script auto-discovers the latest dated directory from the server index and falls back to `tron/snapshot-urls.txt`.

```bash
# Full node (~2.875 TB, streamed directly into data dir — no temp file needed)
sudo ./download-snapshot -n tron -t full

# Lite fullnode / pruned (~57 GB, downloaded then extracted)
sudo ./download-snapshot -n tron -t pruned
```

#### 2. Start

```bash
cd tron
docker compose up -d
```

#### 3. Verify

```bash
# Check node info via HTTP RPC
curl -s http://localhost:8190/wallet/getnodeinfo | python3 -m json.tool | head -30

# Check block height
curl -s http://localhost:8190/wallet/getnowblock | python3 -m json.tool | grep -E '"number"'
```

#### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8190 (→8090) | HTTP | JSON-RPC (wallet API) |
| 50051 | TCP | gRPC |
| 18888 | TCP/UDP | P2P peering |

#### Gotchas

- The data volume is mounted at `/java-tron/output-directory` inside the container. Extracted snapshot contents land directly there.
- Full snapshots are LevelDB format (~2.875 TB); lite snapshots are also LevelDB but contain only recent state (~57 GB).
- Snapshot servers are updated roughly every 2-3 days. If auto-discovery fails, update `tron/snapshot-urls.txt` with the latest `backup{YYYYMMDD}` directory from `http://34.86.86.229/` (full) or `http://34.143.247.77/` (lite).
- java-tron does not expose a standard `eth_syncing` endpoint. Use `/wallet/getnodeinfo` to check sync status.

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
| Tron | java-tron | v4.8.1 (GreatVoyage) |

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

# 3. Set up .env files (only L1 RPC URL needed for each)
cp arbitrum/.env.example arbitrum/.env
cp base/.env.example base/.env
# Edit L1_RPC_URL / OP_NODE_L1_ETH_RPC in each file
# Polygon: also edit /data/rpc_nodes/polygon-data/heimdall/config/app.toml after heimdall init

# 4. Download snapshots (each takes many hours — run in screen/tmux)
sudo ./download-snapshot -n eth
sudo ./download-snapshot -n arb
sudo ./download-snapshot -n base -t full
sudo ./download-snapshot -n polygon
sudo ./download-snapshot -n tron -t pruned   # or -t full for full node

# 5. Start each chain node
cd eth && docker compose up -d && cd ..
cd arbitrum && docker compose up -d && cd ..
cd base && docker compose up -d && cd ..
cd polygon && docker compose up -d && cd ..
cd tron && docker compose up -d && cd ..
```

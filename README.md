# RPC Node Monorepo

Self-hosted RPC node infrastructure for multiple blockchain networks. Each chain lives in its
own directory with a `docker-compose.yml`, snapshot URLs, and helper scripts. A single shared
nginx container reverse-proxies all of them under `rpc.defistream.dev`.

Chain data lives **outside** the repo, under `/data/rpc_nodes/`.

---

## Deployment status

Not every chain in this repo is running. The configs for stopped chains are kept deliberately so
they can be brought back, but do not assume a directory here means a live node.

**As of 2026-08-21:**

| Chain | Client(s) | Status | RPC port | Data on disk |
|-------|-----------|--------|----------|--------------|
| Ethereum L1 | Reth + Lighthouse | ✅ **running**, synced | 8555 | 1.9 TB |
| Arbitrum One | Nitro | ✅ **running**, synced | 8547 | 6.4 TB |
| Hyperliquid | hl-visor + pruner + event-server | ✅ **running**, at tip | 3001 / 3002 | 236 GB + 24 GB state |
| BSC | Geth | ⏸️ **stopped** (was synced) | 8845 | 7.1 TB (retained) |
| Base (OP Stack) | op-reth + base-consensus | ❌ **off**, data deleted | 8645 | — |
| Polygon PoS | Bor + Heimdall | ❌ **off**, data deleted | 8745 | — |
| Tron | java-tron | ❌ never deployed | 8190 | — |
| Bitcoin | Bitcoin Core | ❌ never deployed | 8332 | — |

Host array `/dev/md1` is 28 TB, ~59% used.

### Why Base and Polygon are off

Both were removed because their disk I/O destabilised the Hyperliquid node. HL has no snapshot —
it bootstraps by streaming ~1 GB of consensus state from gossip peers, and I/O contention made
that re-sync fail, which spiralled into multi-hour outages (2026-07-10 Polygon removal,
2026-07-23 Base removal after HL crash-looped with `n_restarts: 2499`).

Restoring either means a full re-sync from a fresh snapshot, and re-testing HL stability
alongside it. Do not simply `docker compose up` them. Note that a later 2026-08-20 outage had
*nothing* to do with contention (see `hyperliquid/TROUBLESHOOTING.md`) — check disk utilisation
before blaming I/O for an HL problem.

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

## Directory Layout

```
.
├── init-data-dirs.sh   # Creates /data/rpc_nodes/** (called by docker-compose init service)
├── open-ports.sh       # Configures UFW firewall rules (run once on host)
├── docker-compose.yml  # Root compose: init + nginx services
├── download-snapshot   # Snapshot download/extract script (see below)
├── eth/                # Ethereum L1 (Reth + Lighthouse)
├── arbitrum/           # Arbitrum One (Nitro)
├── base/               # Base L2 (OP Stack; base/node vendored as a git submodule)
├── polygon/            # Polygon PoS (Bor + Heimdall)
├── bsc/                # BSC (Geth)
├── tron/               # Tron (java-tron)
├── bitcoin/            # Bitcoin Core
├── hyperliquid/        # Hyperliquid (hl-visor, non-validator) + reliability system
├── nginx/              # Shared reverse proxy config
└── chains_self_host.md # Hardware/storage reference for 22+ chains (planning doc)
```

### Docker Compose locations

| Chain | Compose file |
|-------|-------------|
| Nginx + init | `docker-compose.yml` |
| Ethereum | `eth/docker-compose.yml` |
| Arbitrum | `arbitrum/docker-compose.yml` |
| Base | `base/docker-compose.yml` |
| Polygon | `polygon/docker-compose.yml` |
| BSC | `bsc/docker-compose.yml` |
| Tron | `tron/docker-compose.yml` |
| Bitcoin | `bitcoin/docker-compose.yml` |
| Hyperliquid | `hyperliquid/docker-compose.yml` |

### Data directory on disk

```
/data/rpc_nodes/
├── eth-data/            # Reth + Lighthouse
├── arbitrum/            # Nitro
├── base-data/           # op-reth (currently absent — Base is off)
├── polygon-data/        # Bor + Heimdall (currently absent — Polygon is off)
├── bsc-data/full/       # Geth
├── tron-data/           # java-tron
├── bitcoin-data/        # Bitcoin Core
├── hyperliquid-data/    # hl-visor L1/EVM data (pruned to 12h — see below)
└── hyperliquid-hlstate/ # hl-visor consensus state (persisted across container recreates)
```

---

## RPC Endpoints (local)

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
| BSC | HTTP | 8845 | `http://localhost:8845` |
| BSC | WebSocket | 8846 | `ws://localhost:8846` |
| Tron | HTTP RPC | 8190 | `http://localhost:8190` |
| Tron | gRPC | 50051 | `localhost:50051` |
| Bitcoin | HTTP JSON-RPC | 8332 | `http://localhost:8332` |
| Hyperliquid | EVM RPC | 3001 | `http://localhost:3001/evm` |
| Hyperliquid | Info API | 3001 | `http://localhost:3001/info` |
| Hyperliquid | Event server | 3002 | `http://localhost:3002` (HTTP + WS) |

---

## Reverse Proxy (public access)

All chains are exposed through a single nginx container at **`rpc.defistream.dev`** using
path-based routing. The nginx service is part of the root `docker-compose.yml`.

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
| `https://rpc.defistream.dev/bsc` | BSC | HTTP JSON-RPC |
| `wss://rpc.defistream.dev/bsc` | BSC | WebSocket |
| `https://rpc.defistream.dev/bitcoin` | Bitcoin | HTTP JSON-RPC |
| `https://rpc.defistream.dev/hyperliquid/evm` | Hyperliquid | EVM JSON-RPC |
| `https://rpc.defistream.dev/hyperliquid/info` | Hyperliquid | Info API |
| `https://rpc.defistream.dev/hyperliquid/events` | Hyperliquid | Event server (HTTP + WS) |

> Routes for stopped chains stay configured and will return **502** until the node is started.

HTTP and WebSocket share the same URL — nginx detects `Upgrade: websocket` and routes to the
correct backend port automatically.

The entire `/etc/letsencrypt` directory is mounted read-only so that symlinks in `live/`
(pointing into `archive/`) resolve correctly. The container uses `network_mode: host` and reaches
all node ports on `127.0.0.1` directly.

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
├── nginx.conf                          # events/http block, WS upgrade map, proxy buffers
└── conf.d/
    └── rpc.defistream.dev.conf         # TLS, path routing, backends
```

`nginx/conf.d/.gitignore` excludes non-RPC vhosts, so other sites served by this same nginx
(e.g. `projects.erennevin.xyz`, `tradernick.defistream.dev`) live on the host but are not
tracked in this repo.

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

1. Bind the node to a new host port (e.g. `8947` HTTP, `8948` WS).
2. Add a `map` + `location` block in `nginx/conf.d/rpc.defistream.dev.conf`.
3. Run `docker compose exec nginx nginx -s reload`.

---

## Snapshot Download

Use the `download-snapshot` script to download and extract snapshots for any supported chain.

```
./download-snapshot -n <node> [-t full|pruned] [-x] [-d <data-root>]

  -n  Node (required): eth | arb | base | polygon | bsc | tron | bitcoin
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
| bsc | ✅ ~5 TB (PBSS, full history) | ✅ ~964 GB (48Club, no log index) | bnb-chain / 48Club |
| tron | ✅ ~2.875 TB | ✅ ~57 GB | TRON Foundation servers (auto-discovered) |
| bitcoin | ✅ base + incremental | — (`-t` ignored) | PublicNode (auto-discovered) |

Each chain also has a `snapshot-urls.txt` used as a fallback when auto-discovery fails.

### Examples

```bash
sudo ./download-snapshot -n eth              # Ethereum full archive
sudo ./download-snapshot -n arb              # Arbitrum (full only)
sudo ./download-snapshot -n base -t pruned   # Base pruned (~2.3 TB extracted)
sudo ./download-snapshot -n polygon          # heimdall + bor-base + bor-part
sudo ./download-snapshot -n bsc -t pruned    # BSC 48Club pruned
sudo ./download-snapshot -n tron -t pruned   # Tron lite fullnode (~57 GB)
sudo ./download-snapshot -n bitcoin          # Bitcoin base + incremental

sudo ./download-snapshot -n eth -x           # Extract-only (already downloaded)
```

> **Tip:** Run inside `screen` or `tmux` — downloads can take many hours.

---

## Per-Chain Setup

### Ethereum L1

**Stack:** Reth v1.10.0 (execution) + Lighthouse v8.0.1 (consensus)

This is the L1 that Arbitrum, Base and Polygon all depend on, so it should be the first node up
and the last one taken down.

#### 1. JWT secret

A pre-generated `eth/jwt.hex` is committed to the repo — no action needed. It is used only for
local engine API communication between Reth and Lighthouse.

#### 2. Download a snapshot (recommended)

```bash
sudo ./download-snapshot -n eth
```

Resolves the latest ethPandaOps Reth archive URL automatically, downloads with aria2c
(16 connections), extracts to `/data/rpc_nodes/eth-data/reth/`, and fixes ownership.

#### 3. Start

```bash
cd eth && docker compose up -d
```

Lighthouse uses **checkpoint sync** (`https://beaconstate.ethstaker.cc`) so the beacon chain
catches up in minutes rather than days.

#### 4. Verify

```bash
curl -s http://localhost:8555 -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

curl -s http://localhost:5052/eth/v1/node/syncing
```

#### Gotchas

- **Lighthouse runs as a PeerDAS supernode** (`--supernode`). Post-Fulu, blobs are erasure-coded
  into 128 data columns and a normal full node custodies only ~4 — it then **cannot reconstruct
  blobs** and returns HTTP 500 on `/eth/v1/beacon/blobs/<slot>`. Base's derivation needs those
  blobs. Do not remove this flag while Base depends on this node.
- Supernode custody is **forward-only**: a freshly-enabled supernode only has columns for slots
  received after it started, and retention is ~18 days regardless. Historical blobs need an
  external archive endpoint.

#### Helper script

`eth/start-after-extract.sh` monitors an ongoing tar extraction, fixes ownership, and auto-starts
the node when extraction finishes.

---

### Arbitrum One

**Stack:** Nitro v3.11.3-beb2108

#### 1. Configure L1 endpoints

```bash
cp arbitrum/.env.example arbitrum/.env
# then edit L1_RPC_URL if not using the local eth node
```

```env
L1_RPC_URL=http://172.17.0.1:8555
```

`L1_BEACON_URL` is optional and defaults to PublicNode.

#### 2. Download a snapshot

```bash
sudo ./download-snapshot -n arb
```

#### 3. Start

```bash
cd arbitrum && docker compose up -d
```

#### 4. Monitor sync

```bash
curl -s http://localhost:8547 -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Continuous monitoring (polls every 60s, desktop notification on completion)
bash arbitrum/check-sync.sh
```

#### Gotchas

- **Nitro must keep up with ArbOS upgrades or it halts.** On 2026-08-20 Arbitrum One activated
  ArbOS 52; v3.9.4 only supported up to ArbOS 51 and hard-failed every block with
  *"the chain is upgrading to unsupported ArbOS version 52"*, stopping the chain dead. Watch
  Offchain Labs release notes for ArbOS activations and upgrade **before** they land.
- The node requires **both** an L1 execution RPC and an L1 Beacon API endpoint.
- `--node.staker.enable=false` — this is a non-validating node.
- `--execution.rpc.log-history=0` — no historical logs. This is a pruned node; you cannot
  `eth_call` at old blocks.

---

### Base (OP Stack L2) — currently OFF

**Stack:** op-reth + base-consensus, both built from source via the
[`base/node`](https://github.com/base/node) submodule, pinned to **v1.1.1**.

> Base is not running (see [Deployment status](#deployment-status)). Bringing it back means a
> fresh snapshot restore and re-validating that Hyperliquid stays stable under its I/O.

**`base/README.md` is the authoritative deploy/operate doc** — it covers the snapshot restore
path, the PeerDAS blob requirement, the memory-recycling cron, and the large-gap snapshot
deadlock. Only the essentials are repeated here.

#### Configure

```bash
cp base/.env.example base/.env
# set BASE_NODE_L1_ETH_RPC to your L1 execution RPC
```

Note the variable is **`BASE_NODE_L1_ETH_RPC`** (the compose file falls back to the older
`OP_NODE_L1_ETH_RPC` name if only that is set). Everything else — JWT, network, P2P bootnodes,
sync mode — is pre-configured in `base/docker-compose.yml`.

#### Build and start

```bash
cd base
docker compose build      # long: compiles reth from source
docker compose up -d
```

#### Gotchas

- Runs **two containers**: execution (op-reth) and consensus (base-consensus). Both required.
- **Minimum base/node v1.1.0.** Older builds never issue the `forkchoiceUpdated` that sets
  reth's sync target and deadlock when catching up a large gap from a snapshot.
- **Blobs:** during initial catch-up from an old snapshot, point `BASE_NODE_L1_BEACON` at a blob
  archive (`https://ethereum-beacon-api.publicnode.com`); the local lighthouse only has columns
  for slots it saw after supernode mode was enabled. Revert to local once caught up.
- **Memory:** base-reth leaks via glibc arena fragmentation (~90 GiB after ~17h).
  `MALLOC_ARENA_MAX=2` plus the 4-hourly restart cron (`base/base-execution-restart.cron`,
  currently installed as `.disabled`) mitigate it. Keep the cron **off** during a snapshot
  restore — it can restart reth onto a half-written datadir.
- Restart both containers together with `up -d --force-recreate` when changing env vars;
  `docker compose restart` does not pick them up.

---

### Polygon PoS — currently OFF

**Stack:** Bor v2.8.0 (execution) + Heimdall-v2 v0.9.0 (consensus)

> Polygon is not running and its ~8.3 TB of data was deleted on 2026-07-10 (its heimdall
> cometbft writes were the single largest source of random disk I/O on the host, ~49 MB/s, and
> destabilised Hyperliquid). Restoring it means a full snapshot restore and heimdall re-init.

#### 1. Configure L1 endpoint

Heimdall reads its L1 RPC URL from `config/app.toml` inside the heimdall home directory. Edit
after running `heimdall init`:

```toml
# /data/rpc_nodes/polygon-data/heimdall/config/app.toml
eth_rpc_url = "http://172.17.0.1:8555"
bor_rpc_url = "http://172.17.0.1:8745"
```

#### 2. Download snapshots

Polygon needs **two** snapshots: Heimdall (~1 TB) and Bor (~4.7 TB). Total ~6 TB.

```bash
sudo ./download-snapshot -n polygon
```

#### 3. Start

```bash
cd polygon && docker compose up -d
```

Heimdall starts first (Bor has `depends_on: heimdall`).

#### 4. Verify

```bash
curl -s http://localhost:8745 -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

curl -s http://localhost:26657/status
```

#### Gotchas

- **Track heimdall hardforks.** On 2026-06-26 the node missed the Zurich hardfork: heimdall-v2
  `0.7.1-beta` executed block 47,880,000 with pre-Zurich rules, produced the wrong AppHash and
  halted consensus, taking Bor down with it. Recovery required upgrading to v0.9.0 **and**
  `heimdalld rollback` one block. Never run `-beta` builds on mainnet.
- **Both Heimdall and Bor must run together.** If Heimdall is down, Bor stalls.
- **Storage growth is extreme** (~3 TB/month).
- `GOMEMLIMIT=50GiB` caps Bor's Go heap so it returns memory to the OS instead of climbing to
  ~100 GB over weeks.
- Bor uses the `pebble` database engine (PBSS). Offline `bor snapshot prune-block` is **not
  safe** on this configuration.

---

### BSC — currently stopped

**Stack:** Geth v1.7.3 (`ghcr.io/bnb-chain/bsc`)

The node was synced and its ~7.1 TB datadir is retained, so it can be restarted without a
re-sync (subject to catching up the gap).

```bash
cd bsc
docker compose start        # restart the existing container
docker compose stop -t 300  # stop it — give geth time to flush state
```

Node settings live in `bsc/config.toml` (HTTP 8845, WS 8846, P2P 30603), not on the command
line. Geth logs to a file inside the container via `[Node.LogConfig]`, so `docker logs` is
mostly empty — check the exit code to confirm a clean shutdown (`0` = graceful, `137` = killed).

#### Gotchas

- **Always stop with a long timeout.** A SIGKILL mid-write leaves the PBSS datadir dirty and
  costs a long recovery on next start.
- BSC ships hardforks frequently; check release notes before they activate.

---

### Tron — not deployed

**Stack:** java-tron v4.8.1 (GreatVoyage)

```bash
sudo ./download-snapshot -n tron -t pruned   # lite fullnode ~57 GB
sudo ./download-snapshot -n tron -t full     # full node ~2.875 TB
cd tron && docker compose up -d
```

#### Verify

```bash
curl -s http://localhost:8190/wallet/getnodeinfo | python3 -m json.tool | head -30
curl -s http://localhost:8190/wallet/getnowblock | python3 -m json.tool | grep -E '"number"'
```

#### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8190 (→8090) | HTTP | JSON-RPC (wallet API) |
| 50051 | TCP | gRPC |
| 18888 | TCP/UDP | P2P peering |

#### Gotchas

- The data volume mounts at `/java-tron/output-directory`; extracted snapshot contents land
  directly there.
- java-tron has no standard `eth_syncing`. Use `/wallet/getnodeinfo`.
- Snapshot servers update every 2-3 days. If auto-discovery fails, update
  `tron/snapshot-urls.txt` with the latest `backup{YYYYMMDD}` directory.

---

### Bitcoin — not deployed

**Stack:** Bitcoin Core 30.2 (`btcpayserver/bitcoin`)

```bash
sudo ./download-snapshot -n bitcoin
cd bitcoin && docker compose up -d
```

Configuration is passed via `BITCOIN_EXTRA_ARGS` in the compose file (the image builds its own
config from that env var); `bitcoin/bitcoin.conf` mirrors the same settings for reference.
`txindex=1` and `coinstatsindex=1` are enabled, ZMQ publishes on 28332/28333, and upload is
capped at 1 GB/day.

> The committed `rpcauth` line is a salted hash for user `rpc`. Set your own before exposing the
> RPC anywhere beyond localhost.

---

### Hyperliquid

**Stack:** hl-visor (proprietary, auto-updating) — non-validator node

Hyperliquid is a custom L1 (HyperBFT consensus) with an embedded EVM (HyperEVM, chain ID 999).
The binary is closed-source and Ubuntu-24.04-only. **There is no database snapshot** — the node
bootstraps by streaming state from gossip peers, which is the single most fragile thing in this
repo and the source of every HL outage to date.

**Read `hyperliquid/TROUBLESHOOTING.md` before touching a misbehaving HL node**, and
`hyperliquid/reliability/README.md` for the monitoring system.

#### 1. Build and start

```bash
cd hyperliquid && docker compose up -d --build
```

Three containers:
- **node** — `hl-visor run-non-validator` with EVM RPC, Info API, fills and misc-event writing
- **event-server** — Sanic app on 3002 serving fills/misc events over HTTP + WebSocket
- **pruner** — hourly cron enforcing the retention window

#### 2. Verify

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:3001/evm

curl -s -X POST -H "Content-Type: application/json" \
  -d '{"type":"exchangeStatus"}' http://localhost:3001/info

curl -s http://localhost:3002/health
```

#### Reliability system

`hyperliquid/reliability/` keeps the node up and alerts on Telegram. Install on a fresh host:

```bash
cd hyperliquid/reliability
cp alert.conf.example alert.conf     # fill in TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
sudo touch /var/log/hl-monitor.log && sudo chmod 666 /var/log/hl-monitor.log
sudo cp cron.d/hl-monitor cron.d/hl-roots-refresh /etc/cron.d/
```

- `hl-monitor.sh` — every minute; ground truth is "is HL producing data". Alerts and
  auto-recovers on a real stall, but **holds off while a re-sync is in flight** (a re-sync
  legitimately produces no blocks for 30-70 minutes while it streams and ingests a ~1 GB state
  greeting).
- `hl-recover.sh` — the proven manual fix, automated: free contention → refresh gossip roots →
  clean-slate re-sync. Run manually with `sudo ./hl-recover.sh`.
- `hl-refresh-roots.sh` — daily; repopulates `override_gossip_config.json` from the live
  `gossipRootIps` API so a re-sync always has healthy state-servers to pull from.

#### Storage and retention

| Component | Size | Notes |
|-----------|------|-------|
| `hyperliquid-data/` | ~236 GB | L1 + EVM data, pruned to a **12-hour** window |
| `hyperliquid-hlstate/` | ~24 GB | visor consensus state, persisted across recreates |

Raw growth is ~100 GB/day without pruning. The pruner (`pruner/scripts/prune.sh`) runs **hourly**
and deletes files older than 12 hours, keeping only `visor_child_stderr`. The window has been
tuned 24h → 2h → 4h → **12h**: too short and a restarted node cannot replay locally and is forced
into the fragile network re-sync. Historical data is backfilled from S3, not kept on disk.

Rebuild the pruner after editing:

```bash
cd hyperliquid && docker compose build pruner && docker compose up -d --no-deps pruner
```

Always use `--no-deps` so `hyperliquid-node` is never recreated mid-bootstrap.

#### Historical data (optional)

The node only serves data from when it started streaming. Backfill from S3 (requester-pays):

```bash
# Fills and misc events (~136 GB + ~31 GB, ~$15 in transfer)
./hyperliquid/download-historical.sh -t all

# EVM blocks, via hyperliquid-dex/block-importer
aws s3 sync s3://hl-mainnet-evm-blocks/ ./evm-blocks --request-payer requester
```

See `hyperliquid/hyper-plantir.md` for full historical state reconstruction, and
`hyperliquid/api_doc.md` for the event-server API.

#### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 3001 | HTTP | EVM RPC (`/evm`) + Info API (`/info`) |
| 3002 | HTTP/WS | Event server (fills, misc events) |
| 4001-4002 | TCP | P2P gossip — **must be reachable from the internet** |

#### Gotchas

- **Not a standard EVM chain.** `hl-visor` is proprietary and auto-updates `hl-node` at runtime.
- **UID 10000.** The container runs as `hluser` (UID 10000), not 1000 like other chains.
- **No WebSocket** on the node's own RPC (3001). The event-server (3002) does provide WS.
- **Info API is state-only** locally — no historical time series, no subscriptions.
- **Do not restart it repeatedly when it looks stuck.** Each restart throws away an in-progress
  state download and re-triggers the re-sync. Check `/var/log/hl-monitor.log` first.
- HL is **I/O sensitive during recovery**. Keep heavy chains off its storage, or expect the
  re-sync to fail.

---

## Shared L1 Dependency

Arbitrum, Base and Polygon all require an Ethereum L1 RPC endpoint:

1. **Your own Ethereum node** (recommended) — point the `.env` files at `http://<eth-host>:8555`.
2. **External provider** (Infura, Alchemy, QuickNode) — simpler, but adds a dependency and rate limits.

Base and Arbitrum also need an **L1 Beacon API**:
- Your own Lighthouse: `http://<eth-host>:5052` (must be a supernode for Base — see above)
- PublicNode: `https://ethereum-beacon-api.publicnode.com` (also serves historical blobs)

---

## General Gotchas

### Client upgrades are not optional

Two of the worst outages in this repo's history were missed upgrades — Polygon's Zurich hardfork
(2026-06-26) and Arbitrum's ArbOS 52 (2026-08-20). Both halted the chain completely. Subscribe to
release notes for every chain you run.

### Disk I/O

NVMe SSDs are strongly recommended. Chains on shared storage contend with each other, and
Hyperliquid in particular fails in hard-to-diagnose ways when starved (see its section above).
Snapshot extraction is also I/O-bound — expect multi-hour extraction times even on NVMe.

### Container ownership

Most clients run as UID `1000` inside their containers (Hyperliquid is the exception at `10000`).
`download-snapshot` runs `chown -R 1000:1000` after extraction, and the `init` service sets
ownership on all data directories at startup.

### Port conflicts

Each chain uses unique ports — see [RPC Endpoints](#rpc-endpoints-local). If you change ports in a
compose file, update the nginx config and firewall accordingly.

### Firewall

`open-ports.sh` writes UFW rules for nginx (80/443) plus P2P peering for a subset of the
chains here:

```bash
sudo ./open-ports.sh
```

Before relying on it, extend it with the P2P ports of whatever else you run — several chains in
this repo peer on ports the script does not cover (each chain's section lists its own). The
script only adds rules; enabling UFW is a separate host-level step.

RPC ports are not exposed publicly — external traffic reaches them only via nginx `proxy_pass`
on `127.0.0.1`.

### Monitoring sync progress

All EVM nodes expose `eth_syncing` on their RPC port. `false` means synced.

```bash
curl -s http://localhost:<PORT> -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

### Updating client versions

Pin versions in compose files. To upgrade:

1. Check release notes for breaking changes
2. Update the image tag in `docker-compose.yml`
3. `docker compose pull && docker compose up -d`

For Base (submodule): `cd base/base-node && git fetch --tags && git checkout <tag>`, then rebuild.

---

## Client Versions

| Chain | Component | Version | Pinned in |
|-------|-----------|---------|-----------|
| Ethereum | Reth | v1.10.0 | `eth/docker-compose.yml` |
| Ethereum | Lighthouse | v8.0.1 | `eth/docker-compose.yml` |
| Arbitrum | Nitro | v3.11.3-beb2108 | `arbitrum/docker-compose.yml` |
| Base | base/node (op-reth + base-consensus) | v1.1.1 | `base/base-node` submodule |
| Polygon | Bor | v2.8.0 | `polygon/docker-compose.yml` |
| Polygon | Heimdall-v2 | v0.9.0 | `polygon/docker-compose.yml` |
| BSC | Geth | v1.7.3 | `bsc/docker-compose.yml` |
| Tron | java-tron | v4.8.1 (GreatVoyage) | `tron/docker-compose.yml` |
| Bitcoin | Bitcoin Core | 30.2 | `bitcoin/docker-compose.yml` |
| Hyperliquid | hl-visor | auto-updating | fetched at image build |
| — | nginx | 1.27-alpine | `docker-compose.yml` |

---

## Helper Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `download-snapshot` | root | Download and extract snapshots for any chain |
| `init-data-dirs.sh` | root | Create `/data/rpc_nodes/**` with correct ownership |
| `open-ports.sh` | root | Configure UFW firewall rules (run once on host) |
| `start-after-extract.sh` | `eth/` | Monitor snapshot extraction, fix ownership, auto-start |
| `check-sync.sh` | `arbitrum/` | Poll sync status every 60s, notify on completion |
| `pruned-restore.sh` | `base/` | Resumable download + extract of the Base pruned snapshot |
| `restart-execution.sh` | `base/` | Periodic restart of base-execution to reclaim leaked memory |
| `prune.sh` | `hyperliquid/pruner/scripts/` | Hourly retention pruning (12h window) |
| `event-server.py` | `hyperliquid/` | Fills / misc events over HTTP + WebSocket (port 3002) |
| `download-historical.sh` | `hyperliquid/` | Backfill historical fills and misc events from S3 |
| `hl-monitor.sh` | `hyperliquid/reliability/` | 1-min health check → alert + auto-recover |
| `hl-recover.sh` | `hyperliquid/reliability/` | Full clean-slate HL recovery |
| `hl-refresh-roots.sh` | `hyperliquid/reliability/` | Refresh gossip roots from the live API |
| `log-bor-ram.sh` | `polygon/` | Log Bor RAM usage (used while tuning `GOMEMLIMIT`) |

### Cron files

Installed copies live in `/etc/cron.d/`; the tracked originals are:

| File | Schedule | Status |
|------|----------|--------|
| `hyperliquid/reliability/cron.d/hl-monitor` | every 1 min | installed |
| `hyperliquid/reliability/cron.d/hl-roots-refresh` | daily 04:30 UTC | installed |
| `base/base-execution-restart.cron` | every 4h | installed as `.disabled` (Base is off) |

---

## Further Reading

| Doc | Covers |
|-----|--------|
| `base/README.md` | Base deploy, snapshot restore, PeerDAS blobs, known issues |
| `hyperliquid/TROUBLESHOOTING.md` | HL stuck-resync diagnosis and recovery playbook |
| `hyperliquid/reliability/README.md` | HL monitoring, auto-recovery and alerting |
| `hyperliquid/api_doc.md` | Event-server HTTP + WebSocket API |
| `hyperliquid/hyper-plantir.md` | HL historical state reconstruction |
| `chains_self_host.md` | Storage/RAM/bandwidth planning for 22+ chains |

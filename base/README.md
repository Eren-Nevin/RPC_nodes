# Base (OP Stack) RPC Node

A Base mainnet archive/full node: **op-reth** execution client + **base-consensus** (Base's
op-node/kona fork), both compiled from source. This directory is a thin deploy wrapper around
the upstream [`base/node`](https://github.com/base/node) repo (vendored as the `base-node`
git submodule).

- **Execution RPC:** `http://<host>:8645` (WS `8646`)
- **op-node RPC:** `http://<host>:7545`
- Pinned version: **base/node `v1.1.1`** → base-reth-node & base-consensus `v1.1.1` (reth `v2.3.0`).
  See `base-node/versions.env`.

> ⚠️ **Minimum version:** run **base/node ≥ v1.1.0 (reth 2.x)**. Older builds (e.g. v0.16.1 /
> base-consensus 0.9.1) fail to issue the `forkchoiceUpdated` that sets reth's sync target and
> **deadlock** when catching up a large gap from a snapshot. See [Known issues](#known-issues).

---

## Prerequisites

- Docker + Docker Compose, and a machine with plenty of cores (the build does a full
  `cargo --profile maxperf` compile of reth — ~30–60 min) and RAM.
- **Disk:** ~2.5 TB+ for the pruned datadir (much more for archive), plus headroom for the
  snapshot download/extract. Data lives under `/data/rpc_nodes/base-data/`.
- **An L1 Ethereum node** reachable from this host:
  - Execution RPC (e.g. `eth-reth` on `:8555`) → `BASE_NODE_L1_ETH_RPC`.
  - **Consensus/beacon that can serve blobs.** Post-Fulu (PeerDAS) blobs are erasure-coded into
    128 data columns; a normal full node custodies only ~4 and **cannot reconstruct blobs**.
    Run your L1 lighthouse as a **supernode**: add `--supernode` (custodies all 128 columns).
    See [Blobs / PeerDAS](#blobs--peerdas).

---

## Deploy on a fresh server

```bash
# 1. Clone with submodules (base-node is a submodule pinned to a base/node tag)
git clone --recursive <this-repo>
cd RPC_nodes/base
# (if already cloned) git submodule update --init --recursive

# 2. Configure the L1 endpoint
cp .env.example .env
$EDITOR .env          # set BASE_NODE_L1_ETH_RPC to your L1 execution RPC

# 3. Restore a snapshot (see below) into /data/rpc_nodes/base-data/...
#    Syncing from genesis is impractical; always bootstrap from a snapshot.

# 4. Build the images (long — compiles reth 2.3.0 + base-consensus + basectl)
docker compose build

# 5. Start
docker compose up -d
```

### Snapshot restore

Base publishes reth snapshots. The datadir the compose mounts is
`/data/rpc_nodes/base-data/reth/snapshots/mainnet/download` (bind-mounted to `/data` in the
container). The snapshot tarball already contains the `snapshots/mainnet/download/` path prefix,
so extract it with `-C .../reth/` and it lands in the right place.

```bash
DD=/data/rpc_nodes/base-data/reth
mkdir -p "$DD"

# Pruned snapshot (matches a ~2.2 TB full node). Use mainnet-reth-archive-snapshots for archive.
URL="https://mainnet-reth-pruned-snapshots.base.org/$(curl -s https://mainnet-reth-pruned-snapshots.base.org/latest)"

# Option A — resumable (recommended): download then extract
aria2c -c -x16 -s16 -d /tmp "$URL"
zstd -dc "/tmp/$(basename "$URL")" | sudo tar -x -C "$DD"      # extracts snapshots/mainnet/download/*
rm "/tmp/$(basename "$URL")"

# Option B — stream (no archive on disk, but NOT resumable if the connection drops)
# curl -fL "$URL" | zstd -dc | sudo tar -x -C "$DD"
```

> **Do not** let anything (re)start the execution container while the datadir is being wiped or
> extracted — a concurrent reth process corrupts the static_files. Stop base + **disable the
> restart cron** (below) during a restore.

---

## Blobs / PeerDAS

Base derivation needs L1 blobs. Two facts bite on a fresh deploy:

1. **Your L1 lighthouse must be a supernode** (`--supernode`, `custody_group_count: 128`) or it
   returns HTTP 500 on `/eth/v1/beacon/blobs/<slot>` ("Insufficient data columns to reconstruct
   blobs") and derivation stalls.
2. **Supernode custody is forward-only.** A freshly-enabled supernode only has columns for slots
   it received *after* it started. Catching up from a snapshot whose L1 origin predates that (or
   predates lighthouse's ~18-day retention) means those blobs aren't reconstructable locally.

**During initial catch-up**, point the op-node at a blob-archive that retains history. Set in `.env`:

```
BASE_NODE_L1_BEACON=https://ethereum-beacon-api.publicnode.com
```

Once caught up to tip, remove that line and `docker compose up -d node` so it uses the local
supernode lighthouse (default `http://127.0.0.1:5052`), with publicnode kept as the archiver
fallback (`BASE_NODE_L1_BEACON_ARCHIVER`).

---

## Memory / periodic restart

base-reth grows RSS over time (glibc arena fragmentation). Mitigations:
- `MALLOC_ARENA_MAX=2` (set in compose).
- `base-execution-restart.cron` restarts the execution container every 4h (~10–15s downtime;
  the op-node buffers unsafe payloads and replays them, no missed blocks). Install:

```bash
sudo install -o root -g root -m 644 base-execution-restart.cron \
    /etc/cron.d/base-execution-restart
```

> Keep this cron **disabled during a snapshot restore or catch-up** (it can restart reth onto a
> half-written datadir). Re-enable it only once Base is fully synced.

---

## Ports

| Port | Proto | Purpose |
|------|-------|---------|
| 8645 | TCP | execution JSON-RPC (HTTP) |
| 8646 | TCP | execution JSON-RPC (WS) |
| 8551 | TCP | engine API (authrpc, JWT) |
| 7545 | TCP | op-node RPC |
| 30403 | TCP/UDP | reth P2P (discv5 on 9200) |
| 9222 | TCP/UDP | op-node P2P |
| 7300 / 7301 | TCP | op-node / reth metrics |

---

## Verify sync

```bash
# execution head vs public tip
curl -s -XPOST http://localhost:8645 -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
curl -s -XPOST https://mainnet.base.org -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# op-node sync status
curl -s -XPOST http://localhost:7545 -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}'
```

While reth pipeline-syncs from a snapshot, `eth_blockNumber` stays at the snapshot block and the
op-node logs `AwaitingELSyncCompletion`; watch `docker logs base-execution-1` for
`Committed stage progress` (stages x/14, `checkpoint` climbing toward `target`). The head jumps to
tip once all stages finish, then it follows live.

---

## Upgrading / known issues

- **Upgrade** by bumping the `base-node` submodule to a newer `base/node` tag, then rebuild:
  ```bash
  cd base-node && git fetch --tags && git checkout <tag> && cd ..
  docker compose build && docker compose up -d
  ```
  reth 1.x → 2.x reads the existing datadir (it heals static_files on first open).
- **Large-gap snapshot deadlock (fixed in v1.1.0):** on base/node ≤ v0.16.1 (base-consensus 0.9.1,
  reth 1.11.x), the op-node inserts the live payloads as `unsafe` but never sends reth the
  `forkchoiceUpdated` to the tip, so reth sits at `target: None` and never snap-syncs. There is no
  syncmode flag to force full derivation. **Fix: upgrade to ≥ v1.1.0.**

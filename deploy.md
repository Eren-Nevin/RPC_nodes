# Deploying ETH, Arbitrum and Hyperliquid on a new server

A from-scratch runbook for standing up the three chains this repo actively runs. Everything
here is host-agnostic: no path in the repo is tied to a particular checkout location or data
mount any more, so a plain `git clone` anywhere works.

For *what each chain is* and per-chain background, see [`README.md`](README.md). This document
is only about getting them running somewhere new.

> **Base and Polygon are deliberately not covered.** They are off, their data was deleted, and
> their scripts still contain absolute paths. See [Known gaps](#known-gaps).

---

## 1. What you need

### Hardware

| Chain | Disk (data) | Snapshot download | RAM in steady state |
|-------|-------------|-------------------|---------------------|
| Ethereum L1 (Reth + Lighthouse) | ~1.9 TB | ~2.4 TB | ~34 GB |
| Arbitrum One (Nitro) | ~6.4 TB | ~2.8 TB | ~12 GB |
| Hyperliquid (hl-visor) | ~310 GB @ 12 h retention | none — streams from peers | ~21 GB |

- **NVMe, not spinning disk, and ideally not shared.** Hyperliquid is the sensitive one; the
  history in this repo is a string of outages caused by other chains' I/O starving it.
- **64 GB RAM minimum** for all three; the reference host has 251 GB across 64 cores.
- **1 Gbit/s** is enough. HL's state transfer runs at single-digit MB/s and is peer-limited,
  not link-limited.

### Software

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2 git curl python3 aria2 zstd lz4
```

`aria2`, `zstd` and `lz4` are only needed for snapshot downloads (ETH and Arbitrum).
Python 3 is used by the HL reliability scripts. Hyperliquid's own image is Ubuntu-24.04-based
and builds from the repo — nothing extra on the host.

---

## 2. Clone and choose a data root

```bash
git clone https://github.com/Eren-Nevin/RPC_nodes.git
cd RPC_nodes
```

Chain data lives **outside** the repo. The default root is `/data/rpc_nodes`. To put it
elsewhere, export `DATA_ROOT` and keep it exported for every command below:

```bash
export DATA_ROOT=/mnt/big/rpc_nodes     # optional; defaults to /data/rpc_nodes
```

Every compose file reads `${DATA_ROOT:-/data/rpc_nodes}`, so an unset variable is fine and a
set one relocates all three chains together. To make it permanent per chain, put
`DATA_ROOT=...` in that chain's `.env`.

### Create the directories

```bash
docker compose run --rm init
```

This creates every chain's directory under `$DATA_ROOT` with the ownership its container
expects. **The ownership is not uniform** — most clients run as UID 1000, but Hyperliquid runs
as `hluser` (UID 10000) and will fail to start on a directory owned by 1000. The init service
handles both; do not `chown -R 1000:1000` the data root by hand.

### Firewall

```bash
sudo ./open-ports.sh     # writes UFW rules; does not enable UFW itself
```

Opens 80/443 plus P2P for the chains here, including Hyperliquid's **4001/4002 — these must be
reachable from the internet** or the node cannot bootstrap its consensus state. If you run a
cloud firewall or security group instead of UFW, replicate the same rules there.

---

## 3. Ethereum L1

Bring this up **first**: Arbitrum depends on it. Reth (execution) + Lighthouse (consensus).

```bash
sudo ./download-snapshot -n eth      # ~2.4 TB, hours; run under screen/tmux
cd eth && docker compose up -d
```

`eth/jwt.hex` is committed and needs no action — it only authenticates the local engine API
between Reth and Lighthouse. Lighthouse checkpoint-syncs from `beaconstate.ethstaker.cc`, so
the beacon side is ready in minutes rather than days.

**Verify:**

```bash
curl -s http://localhost:8555 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'      # false == synced
curl -s http://localhost:5052/eth/v1/node/syncing                        # sync_distance: "0"
```

**Gotcha — the `--supernode` flag.** Lighthouse runs as a PeerDAS supernode so it custodies all
128 data columns and can serve blobs. Only remove it if nothing consumes blobs from this node.
Supernode custody is forward-only (~18 days), so historical blobs still need an external
archive endpoint.

---

## 4. Arbitrum One

```bash
cp arbitrum/.env.example arbitrum/.env
```

Edit `arbitrum/.env` and set `L1_RPC_URL` to your Ethereum node. With `network_mode: host`
that is `http://127.0.0.1:8555` on the same machine. **This is required** — compose now fails
with an explicit message rather than starting a broken node if it is unset.

`L1_BEACON_URL` is optional and defaults to PublicNode; point it at your own Lighthouse
(`http://127.0.0.1:5052`) once ETH is synced.

```bash
sudo ./download-snapshot -n arb      # ~2.8 TB
cd arbitrum && docker compose up -d
```

**Verify:**

```bash
curl -s http://localhost:8547 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
bash arbitrum/check-sync.sh          # polls every 60s
```

**Gotcha — ArbOS upgrades are not optional.** Nitro halts completely on an ArbOS version it
does not support (this stopped the chain dead on 2026-08-20). Track Offchain Labs releases and
upgrade the pinned image *before* an activation lands.

---

## 5. Hyperliquid

The most involved of the three, and the one with no snapshot: it bootstraps by streaming
~1 GB of consensus state from gossip peers. Read
[`hyperliquid/TROUBLESHOOTING.md`](hyperliquid/TROUBLESHOOTING.md) before you need it.

### 5.1 Start the node

```bash
cd hyperliquid
docker compose up -d --build
```

Three containers come up:

| Container | Role |
|-----------|------|
| `hyperliquid-node` | `hl-visor run-non-validator` — EVM RPC + Info API on 3001, P2P on 4001/4002 |
| `hyperliquid-event-server` | Sanic app on 3002 serving fills / misc events over HTTP + WS |
| `hyperliquid-pruner` | hourly cron enforcing the 12-hour retention window |

The gossip bootstrap peers are baked into the image from `override_gossip_config.json` at
**build** time, so changing that file requires `docker compose build node` followed by
`docker compose up -d --force-recreate --no-deps node`. Always pass `--no-deps` so the node is
never recreated as a side effect of touching another service.

### 5.2 Install the reliability system

Not optional in practice — every HL outage in this repo's history needed it.

```bash
cp reliability/alert.conf.example reliability/alert.conf
# fill in TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID (gitignored)
sudo reliability/install.sh
```

`install.sh` creates `/var/log/hl-monitor.log` and `/var/lib/hl-monitor/`, then generates the
cron jobs with this checkout's path substituted in. The tracked files under `reliability/cron.d/`
are **templates** containing a `__RELDIR__` placeholder — do not copy them to `/etc/cron.d`
directly, or cron will run a path that does not exist on this host.

Installed jobs:

| Job | Schedule | Purpose |
|-----|----------|---------|
| `hl-monitor` | every minute | Detect stalls, alert, auto-recover — with a guard that holds off while a re-sync is legitimately in flight |
| `hl-roots-refresh` | 04:30 UTC daily | Repopulate gossip roots from the live API so a re-sync always has healthy state-servers |

### 5.3 Verify

```bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:3001/evm
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"type":"exchangeStatus"}' http://localhost:3001/info
curl -s http://localhost:3002/health
tail -f /var/log/hl-monitor.log
```

First sync takes **30–70 minutes** and produces no blocks the whole time. That is normal.

### 5.4 The rules that matter

- **Do not restart it because it looks stuck.** Each restart discards an in-progress state
  download and re-triggers the fragile re-sync. Check `/var/log/hl-monitor.log` first.
- **`/health` must answer.** The monitor's ground truth reads
  `http://127.0.0.1:3002/fills/latest` from the event-server. If that server is wedged, the
  monitor silently degrades to a weaker fallback and its lag numbers become meaningless.
- **Keep the storage uncontended.** Running heavy chains on the same disks is what knocked HL
  over repeatedly in 2026.
- Retention is 12 hours (`pruner/scripts/prune.sh`). Shortening it means a restarted node
  cannot replay locally and is forced into the network re-sync — the exact thing you want to
  avoid. Historical data is backfilled from S3, not kept on disk.

---

## 6. Public exposure with nginx (optional)

Only needed if these RPCs should be reachable from outside the host.

`nginx/conf.d/rpc.defistream.dev.conf` is written for the domain `rpc.defistream.dev` and
reads certificates from `/etc/letsencrypt/live/defistream.dev/`. For a new deployment:

1. Point your own DNS name at the host.
2. Issue a certificate: `sudo certbot certonly --standalone -d <your-domain>`
3. Edit `server_name` and both `ssl_certificate*` paths in that file to match.
4. `docker compose up -d nginx`, then `docker compose exec nginx nginx -t` before any reload.

The container runs `network_mode: host` and proxies to `127.0.0.1`, so node RPC ports never
need to be exposed publicly themselves.

---

## 7. Post-deploy checklist

```bash
# all three synced?
curl -s http://localhost:8555 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
curl -s http://localhost:8547 -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:3001/evm

docker ps                                  # 5 containers + nginx
curl -s http://localhost:3002/health       # must answer, not hang
tail -5 /var/log/hl-monitor.log            # monitor is ticking
sudo crontab -l -u root; ls /etc/cron.d/   # hl-monitor + hl-roots-refresh present
```

Ports in use: **8555/8556/5052** (ETH), **8547/8548** (Arbitrum), **3001/3002** and
**4001/4002** (Hyperliquid).

---

## Known gaps

- **Base and Polygon are not deployable from this repo as-is.** `base/pruned-restore.sh` and
  `base/base-execution-restart.cron` still hardcode `/home/mvp/Running/RPC_nodes`, and the
  `base/base-node` submodule is checked out at v0.16.0 while the docs specify v1.1.1. Both
  chains also need a re-validation of Hyperliquid stability before being run alongside it.
- **`open-ports.sh` only adds rules; it does not enable UFW,** and it does not cover chains
  beyond those listed. Check `sudo ufw status` afterwards.
- **The nginx vhost is not parameterised** — domain and certificate paths are edited by hand
  (step 6).

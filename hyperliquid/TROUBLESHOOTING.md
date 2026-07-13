# Hyperliquid node — troubleshooting & recovery playbook

## Symptom: node stuck re-syncing / not applying blocks
Signs:
- `event-server /health` shows `fills_file_exists: false` for the current hour; `/fills/latest` returns nothing.
- Node logs loop on: `could not load VisorAbciState ... missing file`, `abci_stream ... deadline has elapsed`,
  `could not read abci state ... early eof`, `error connecting to candidate peer ... Peer full`.
- `docker stats hyperliquid-node` shows low CPU (idle, network-waiting) and MEM stuck low (~50 MiB = state not loaded).
- Lag (chain head vs latest fill) grows; the lag-watchdog may fire.

## Root cause (learned 2026-07-13, ~11h outage)
The node bootstraps its gossip/state peers from `root_node_ips` in **`override_gossip_config.json`**
(baked into the image via the Dockerfile `COPY`). It had only **5 roots + `n_gossip_peers: 8`**.
During a period of **HL-network state-serving congestion**, those few peers were all "Peer full" or
dropped the ~1 GB `abci_stream` state transfer mid-way → the node could never complete a re-sync and
never got enough live gossip blocks to stay at the tip. It was **block-starved**, not resource-starved
(our disk/CPU/bandwidth were all idle; ports 4001/4002 fine; not rate-limited).

## The fix (proven) — expand the gossip roots
1. **Get the current live root peers** from the HL API:
   ```bash
   curl -s -X POST --header "Content-Type: application/json" \
     --data '{"type":"gossipRootIps"}' https://api.hyperliquid.xyz/info
   ```
2. Put **all** of those (plus HL's dedicated operator roots — ASXN / B-Harvest / Nansen / Hypurrscan,
   listed in https://github.com/hyperliquid-dex/node README) into `override_gossip_config.json`
   `root_node_ips`, and bump `n_gossip_peers` (we use **16**). Keep `try_new_peers: true`.
   (Current committed config has 37 roots — refresh it from `gossipRootIps` if this recurs.)
3. Apply: `docker compose build node && docker compose up -d --force-recreate --no-deps node`
   (the `hyperliquid_data` mount persists state across the recreate — see below).
Result: with enough healthy state-servers to choose from, the node loaded **local** state and caught
up (~29 blk/s) to the tip in minutes.

## Recovery playbook / do's & don'ts
- **DON'T restart repeatedly.** Each restart resets an in-progress state download and re-triggers the
  fragile P2P re-sync. If it's mid-`recv greeting: N/993…` download, leave it — let it finish.
- **DON'T let the watchdog thrash it** while it's grinding. Temporarily disable, then re-enable when healthy:
  ```bash
  sudo mv /etc/cron.d/hl-lag-watchdog /etc/cron.d/hl-lag-watchdog.disabled   # disable
  sudo mv /etc/cron.d/hl-lag-watchdog.disabled /etc/cron.d/hl-lag-watchdog   # re-enable when at tip
  ```
- **First** widen the gossip roots (above) — that's the highest-leverage fix for the stuck-resync loop.
- If the node has been **down a long time** (state stale), the visor deletes `visor_abci_state.json` and
  forces a full network re-sync — expect it; the roots fix is what lets that re-sync actually complete.
- If a prior recovery attempt left **stale data** in the state mount, a clean fresh re-sync helps:
  stop node → `sudo rm -rf /data/rpc_nodes/hyperliquid-hlstate/* && sudo chown 10000:10000 /data/rpc_nodes/hyperliquid-hlstate` → start.

## State persistence (`hyperliquid_data` mount, added 2026-07-13)
`docker-compose.yml` mounts `/data/rpc_nodes/hyperliquid-hlstate -> /home/hluser/hl/hyperliquid_data`
so the visor state + EVM DBs survive a container **recreate** (previously ephemeral). NOTE: this does
**not** by itself prevent the stuck-resync (the visor still deletes *stale* state and re-syncs); the
gossip-roots width is what fixes the re-sync completing.

## Separately: I/O contention (see memory `polygon-removed-base-retry-2026-07-10`)
HL is I/O-sensitive: running Polygon or Base on the **same storage** repeatedly knocked it over
(lag → watchdog restart → re-sync). Both are currently OFF/removed. Keep HL uncontended, or give it
dedicated storage, so it stays at the tip and never needs the fragile re-sync in the first place.

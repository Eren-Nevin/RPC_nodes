#!/bin/bash
# Refresh override_gossip_config.json root_node_ips from the LIVE HL gossipRootIps API,
# merged with HL's dedicated operator roots. Keeps the bootstrap peer set current so a
# re-sync always has plentiful, healthy state-servers (stale roots = failed re-syncs).
#
# Run daily via cron to keep the file fresh (applied to the running node on its next
# recreate — hl-recover.sh rebuilds+recreates, so recovery always uses the freshest roots).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
CFG=/home/mvp/Running/RPC_nodes/hyperliquid/override_gossip_config.json

python3 - "$CFG" <<'PY' 2>>"$LOG"
import json,sys,urllib.request
cfg=sys.argv[1]
# Dedicated operator roots (high-capacity, meant to serve non-validators) from HL docs.
OPERATORS=["64.31.48.111","64.31.51.137","180.189.55.18","180.189.55.19",
           "72.46.86.185","72.46.86.159","13.230.78.76","52.195.133.97"]
try:
    req=urllib.request.Request("https://api.hyperliquid.xyz/info",
        data=json.dumps({"type":"gossipRootIps"}).encode(),
        headers={"Content-Type":"application/json"})
    live=json.load(urllib.request.urlopen(req,timeout=10))
except Exception as e:
    print("ERROR fetching gossipRootIps:",e); sys.exit(1)
ips=list(dict.fromkeys([str(x) for x in live]+OPERATORS))   # dedupe, keep order
d=json.load(open(cfg))
old=len(d.get("root_node_ips",[]))
d["root_node_ips"]=[{"Ip":ip} for ip in ips]
d["n_gossip_peers"]=16
d["try_new_peers"]=True
json.dump(d,open(cfg,"w"),indent=2)
print(f"roots refreshed: {old} -> {len(ips)} ({len(live)} live + {len(OPERATORS)} operator)")
PY
log "hl-refresh-roots done"

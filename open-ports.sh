#!/bin/bash
# open-ports.sh — configure UFW firewall rules for RPC node infrastructure.
# Run once on the host after installing UFW.
#
# Opens: 443/tcp, 80/tcp (nginx public), P2P ports for each chain

set -e

echo "=== Configuring UFW rules for RPC nodes ==="

# Public-facing ports (nginx)
ufw allow 80/tcp   comment 'nginx HTTP redirect'
ufw allow 443/tcp  comment 'nginx HTTPS/WSS'

# Ethereum P2P
ufw allow 30303/tcp comment 'eth p2p'
ufw allow 30303/udp comment 'eth p2p'
ufw allow 9100/tcp  comment 'lighthouse p2p'
ufw allow 9100/udp  comment 'lighthouse p2p'

# Base P2P
ufw allow 30403/tcp comment 'base p2p'
ufw allow 30403/udp comment 'base p2p'

# Polygon P2P
ufw allow 30503/tcp comment 'polygon bor p2p'
ufw allow 30503/udp comment 'polygon bor p2p'
ufw allow 26656/tcp comment 'polygon heimdall p2p'

# Bitcoin P2P
ufw allow 8333/tcp  comment 'bitcoin p2p'

# Hyperliquid P2P gossip — REQUIRED. The node bootstraps its consensus state by
# streaming ~1GB from gossip peers; if these are unreachable it cannot re-sync and
# falls into the stuck-resync loop documented in hyperliquid/TROUBLESHOOTING.md.
ufw allow 4001/tcp comment 'hyperliquid p2p gossip'
ufw allow 4002/tcp comment 'hyperliquid p2p gossip'

echo "=== Current UFW status ==="
ufw status verbose

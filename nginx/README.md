# nginx Reverse Proxy

Single nginx container that fronts all RPC nodes on `rpc.defistream.dev`. All chains share one TLS termination point; clients use path-based routing.

## Endpoints

| Path | Chain | HTTP port | WS port |
|------|-------|-----------|---------|
| `/eth` | Ethereum L1 | 8555 | 8556 |
| `/arbitrum` | Arbitrum One | 8547 | 8548 |
| `/base` | Base | 8645 | 8646 |
| `/polygon` | Polygon PoS | 8745 | 8746 |

HTTP and WebSocket share the same path — the proxy detects the `Upgrade: websocket` header and routes to the correct backend port automatically.

```
https://rpc.defistream.dev/eth       →  JSON-RPC HTTP
wss://rpc.defistream.dev/eth         →  JSON-RPC WebSocket
```

## Directory structure

```
nginx/
├── docker-compose.yml
├── nginx.conf                          # main config (events, http block)
├── conf.d/
│   └── rpc.defistream.dev.conf         # vhost: TLS, path routing, backends
└── certs/
    ├── rpc.defistream.dev.crt          # add manually
    └── rpc.defistream.dev.key          # add manually
```

## Setup

### 1. Add TLS certificate and key

Place the certificate and private key in `certs/`:

```
nginx/certs/rpc.defistream.dev.crt
nginx/certs/rpc.defistream.dev.key
```

The `certs/` directory is mounted read-only into the container.

### 2. Start

```bash
cd nginx
docker compose up -d
```

The container uses `network_mode: host` so it can reach all node ports on `127.0.0.1` directly without any extra network configuration.

### 3. Verify

```bash
# Health check
curl -s https://rpc.defistream.dev/

# Ethereum RPC
curl -s https://rpc.defistream.dev/eth \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Arbitrum RPC
curl -s https://rpc.defistream.dev/arbitrum \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

## Firewall

```bash
# HTTPS and HTTP redirect — open to everyone
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# P2P ports — open to everyone (required for node peering)
sudo ufw allow 30303/tcp comment 'eth p2p'
sudo ufw allow 30303/udp comment 'eth p2p'
sudo ufw allow 9100/tcp  comment 'lighthouse p2p'
sudo ufw allow 9100/udp  comment 'lighthouse p2p'
sudo ufw allow 26656/tcp comment 'polygon heimdall p2p'

# Raw RPC ports — block direct external access
sudo ufw deny 8555/tcp
sudo ufw deny 8556/tcp
sudo ufw deny 8547/tcp
sudo ufw deny 8548/tcp
sudo ufw deny 8645/tcp
sudo ufw deny 8646/tcp
sudo ufw deny 8745/tcp
sudo ufw deny 8746/tcp
```

## Adding a new chain

1. Bind the new node to a host port (e.g. `8847` HTTP, `8848` WS).
2. Add a `map` block in `conf.d/rpc.defistream.dev.conf` for the new chain.
3. Add a `location` block routing `/chainname` to the new backend.
4. `docker compose exec nginx nginx -s reload`

## Reloading config without downtime

```bash
docker compose exec nginx nginx -t          # test config
docker compose exec nginx nginx -s reload   # graceful reload
```

## Logs

```bash
docker compose logs -f nginx
```

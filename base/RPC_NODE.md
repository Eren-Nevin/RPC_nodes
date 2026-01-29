# Base RPC Node Deployment - Reth Archive

## Configuration Summary

| Setting | Value |
|---------|-------|
| Client | Reth Archive |
| Data Directory | `/mnt/viper/reth-data` |
| Network | Base Mainnet |
| RPC Access | Public (0.0.0.0:8545) |
| WebSocket | Disabled |
| Snapshot Size | ~4.3TB compressed, ~7-8TB extracted |

## Supported RPC Methods (Full History from Genesis)

- `eth_getBlockByNumber` / `eth_getBlockByHash`
- `eth_getTransactionByHash` / `eth_getTransactionReceipt`
- `eth_getLogs` - Query historical logs with filters
- `eth_call` - Execute calls against current state
- `eth_chainId`, `eth_blockNumber`, `net_version`
- `eth_gasPrice`, `eth_estimateGas`

## Quick Start

### 1. Download and Extract Snapshot (Stream Method)

This streams directly to disk without storing the compressed file:

```bash
cd /mnt/viper/reth-data
curl -L "https://mainnet-reth-archive-snapshots.base.org/$(curl -s https://mainnet-reth-archive-snapshots.base.org/latest)" | zstd -d | tar -xf -
```

Or download first, then extract:
```bash
cd /mnt/viper
SNAPSHOT=$(curl -s https://mainnet-reth-archive-snapshots.base.org/latest)
wget "https://mainnet-reth-archive-snapshots.base.org/$SNAPSHOT"
zstd -d "$SNAPSHOT" -o snapshot.tar && tar -xf snapshot.tar -C reth-data/ && rm snapshot.tar "$SNAPSHOT"
```

### 2. Verify Snapshot Structure

```bash
ls /mnt/viper/reth-data/
# Should show: db, static_files, etc.
```

### 3. Configure L1 Endpoints

Edit `/home/mvp/Running/RPC/base/base-node/.env.custom`:

```bash
OP_NODE_L1_ETH_RPC=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
OP_NODE_L1_BEACON=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY/beacon
OP_NODE_L1_BEACON_ARCHIVER=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY/beacon
OP_NODE_L1_RPC_KIND=alchemy  # or: infura, quicknode, etc.
```

### 4. Start the Node

```bash
cd /home/mvp/Running/RPC/base/base-node
CLIENT=reth NETWORK_ENV=.env.custom docker compose up --build -d
```

### 5. Verify Node Status

```bash
# Check sync status (op-node)
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' \
  http://localhost:7545

# Check latest block (reth)
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

# Test getLogs from genesis
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getLogs","params":[{"fromBlock":"0x1","toBlock":"0x10"}],"id":1}' \
  http://localhost:8545
```

## RPC Endpoints

| Endpoint | Port | Purpose |
|----------|------|---------|
| HTTP RPC | 8545 | Main RPC for web3 queries |
| op-node RPC | 7545 | Optimism-specific queries |

## Firewall Configuration

```bash
sudo ufw allow 8545/tcp   # HTTP RPC
sudo ufw allow 30303/tcp  # P2P
sudo ufw allow 30303/udp  # P2P
sudo ufw allow 9222/tcp   # op-node P2P
sudo ufw allow 9222/udp   # op-node P2P
```

## Maintenance

```bash
cd /home/mvp/Running/RPC/base/base-node

# View logs
docker compose logs -f

# View execution client logs only
docker compose logs -f execution

# Restart
docker compose restart

# Stop
docker compose down

# Check disk usage
df -h /mnt/viper
```

## Storage Notes

- Reth Archive: ~7-8TB (much smaller than Geth Archive ~46TB)
- Growth rate: ~50-100GB/week
- Your 11TB RAID0 provides good headroom for growth

## Files Modified

| File | Purpose |
|------|---------|
| `.env.custom` | Environment configuration |
| `docker-compose.override.yml` | Volume mounts and ports |
| `reth/reth-entrypoint-rpc` | Custom entrypoint (no WebSocket) |
| `reth/Dockerfile` | Updated to include RPC entrypoint |

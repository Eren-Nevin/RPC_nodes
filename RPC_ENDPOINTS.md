# RPC Node Endpoints

| Chain    | Type     | Host Port | URL                          |
|----------|----------|-----------|------------------------------|
| Ethereum | HTTP RPC | 8555      | http://localhost:8555        |
| Ethereum | WebSocket| 8556      | ws://localhost:8556          |
| Ethereum | Beacon   | 5052      | http://localhost:5052        |
| Arbitrum | HTTP RPC | 8547      | http://localhost:8547        |
| Base     | HTTP RPC | 8645      | http://localhost:8645        |
| Base     | WebSocket| 8646      | ws://localhost:8646          |
| Base     | op-node  | 7545      | http://localhost:7545        |
| Polygon  | HTTP RPC | 8745      | http://localhost:8745        |
| Polygon  | WebSocket| 8746      | ws://localhost:8746          |
| Polygon  | Heimdall | 26657     | http://localhost:26657       |

## Docker Compose Locations

| Chain    | Compose File                                              |
|----------|-----------------------------------------------------------|
| Ethereum | ~/Running/RPC_nodes/eth/docker-compose.yml                |
| Arbitrum | ~/Running/RPC_nodes/arbitrum/docker-compose.yml           |
| Base     | ~/Running/RPC_nodes/base/base-node/docker-compose.yml     |
| Polygon  | ~/Running/RPC_nodes/polygon/docker-compose.yml            |

## Data Directories

| Chain    | Path                                                        |
|----------|-------------------------------------------------------------|
| Ethereum | /data/rpc_nodes/eth-data/reth                               |
| Arbitrum | /data/rpc_nodes/arbitrum                                    |
| Base     | /data/rpc_nodes/base-data/reth/snapshots/mainnet/download   |
| Polygon  | /data/rpc_nodes/polygon-data                                |

## Clients

| Chain    | Execution Client          | Consensus Client       |
|----------|---------------------------|------------------------|
| Ethereum | Reth v1.10.0 (archive)    | Lighthouse v8.0.1      |
| Arbitrum | Nitro v3.9.4              | N/A (uses L1 via Infura) |
| Base     | base-reth-node v0.3.0     | op-node v1.16.2        |
| Polygon  | Bor v2.5.7                | Heimdall v2.0.0-beta4  |

# Blockchain Node Self-Hosting Guide

Comprehensive comparison of storage requirements, hardware specs, and self-hosting feasibility for major blockchain networks (January 2025).

---

## Quick Reference Table

| Chain | Type | Download | Running Size | RAM | Growth | Self-Host? |
|-------|------|----------|--------------|-----|--------|------------|
| **Ethereum L1** | Full | ~1.3 TB | ~1.6 TB | 32 GB | 15 GB/mo | Yes |
| **Ethereum L1** | Archive | ~2.4 TB | ~2.4-3 TB | 32 GB | 15 GB/mo | Yes |
| **Base** | Archive | 4.3 TB | ~7-8 TB | 32 GB | 200 GB/mo | Yes |
| **Polygon** | Full | 5.7 TB | ~6-7 TB | 64 GB | 3 TB/mo | Yes |
| **BSC** | Full (Geth) | 1 TB | ~1.5 TB | 32 GB | 150 GB/mo | Yes |
| **BSC** | Full (Reth) | 4.3 TB | ~5-6 TB | 32 GB | 150 GB/mo | Yes |
| **BSC** | Archive (Reth) | 9.7 TB | ~10+ TB | 32 GB | 150 GB/mo | Yes |
| **Arbitrum** | Full | ~1.8 TB | ~2-3 TB | 16 GB | 200 GB/mo | Yes |
| **Arbitrum** | Archive | N/A | ~15+ TB | 32 GB | 850 GB/mo | Difficult |
| **TRON** | Full | ~2.3 TB | ~2.5-3 TB | 32 GB | 50 GB/mo | Yes |
| **Sui** | Full+Index | ~2.5 TB | ~2.5-4 TB | 128 GB | 300 GB-1.2 TB/mo | Yes |
| **Sei** | Pruned | ~150 GB | ~200 GB | 32 GB | Low | Yes |
| **Sei** | Archive | N/A | 10+ TB | 32 GB | High | Yes |
| **Avalanche** | Pruned | ~500 GB | ~1 TB | 16 GB | Variable | Yes |
| **Avalanche** | Archive | N/A | ~12.5 TB | 16 GB | High | Yes |
| **Monad** | Full | ~2.5 TB | ~2.5 TB | 32 GB | TBD | Yes (bare metal) |
| **Mantle** | Archive | N/A | ~2-5 TB | 32 GB | TBD | Yes |
| **Unichain** | Archive | N/A | ~1-3 TB | 32 GB | TBD | Yes |
| **Starknet** | Full (Juno) | N/A | ~125 GB | 32 GB | Low | Yes |
| **Starknet** | Full (Pathfinder) | N/A | ~713 GB | 32 GB | Low | Yes |
| **Scroll** | Archive | ~2 TB | ~2 TB | 32 GB | TBD | Yes |
| **TON** | Full | N/A | ~1 TB | 256 GB | 40 GB/mo | Yes |
| **TON** | Archive | N/A | ~12-14 TB | 256 GB | High | Yes |
| **NEAR** | Archive | ~60 TB | ~60-115 TB | 32 GB | High | Expensive |
| **Solana** | Pruned | N/A | 2-4 TB | 512 GB | Variable | Yes |
| **Solana** | Archive | N/A | ~400 TB | 1 TB | 80-95 TB/yr | No |
| **Hyperliquid** | Archive | S3 sync | ~10-30+ TB | 64 GB | 3 TB/mo | Difficult |
| **Plasma** | Any | Unknown | Unknown | - | - | Not open |
| **Lighter** | Any | N/A | N/A | - | - | App-specific |

---

## Server Planning Guide

### 80TB Server - Can It Fit Everything?

**Short Answer: No** - All chains (excluding NEAR/Solana) total ~105 TB.

#### Full Calculation (Excluding NEAR & Solana)

| Chain | Type | Storage | Monthly Growth |
|-------|------|---------|----------------|
| Ethereum L1 | Archive | 3 TB | 15 GB |
| Base | Archive | 8 TB | 200 GB |
| Polygon | Full | 7 TB | 3 TB |
| BSC | Full | 6 TB | 150 GB |
| Arbitrum | Full | 3 TB | 200 GB |
| TRON | Full | 3 TB | 50 GB |
| Sui | Full+Index | 4 TB | 500 GB |
| Monad | Full | 2.5 TB | TBD |
| Mantle | Archive | 4 TB | TBD |
| Unichain | Archive | 2 TB | TBD |
| Starknet | Juno | 0.2 TB | Low |
| Scroll | Archive | 2 TB | TBD |
| Sei | Archive | 10 TB | High |
| Avalanche | Archive | 12.5 TB | High |
| TON | Archive | 13 TB | 40 GB |
| Hyperliquid | Archive | 25 TB | 3 TB |
| **TOTAL** | | **~105 TB** | **~7+ TB/mo** |

#### Recommended 80TB Setup

Drop high-growth and problematic chains, use pruned where archive not essential:

| Chain | Type | Size | Notes |
|-------|------|------|-------|
| Ethereum L1 | Archive | 3 TB | Full history |
| Base | Archive | 8 TB | Full history |
| BSC | Full | 6 TB | Full history |
| Arbitrum | Full | 3 TB | Full history |
| TRON | Full | 3 TB | Full history |
| Sui | Full | 4 TB | Full history |
| Monad | Full | 2.5 TB | Full history |
| Mantle | Archive | 4 TB | Full history |
| Unichain | Archive | 2 TB | Full history |
| Starknet | Juno | 0.2 TB | Full history |
| Scroll | Archive | 2 TB | Full history |
| Avalanche | Pruned | 1 TB | Recent only |
| Sei | Pruned | 0.2 TB | Recent only |
| TON | Full | 1 TB | Recent only |
| **Subtotal** | | **~40 TB** | |
| **Growth Buffer** | | **~40 TB** | 1-2 years |

**Dropped from 80TB setup:**
- Polygon (3 TB/month growth - unsustainable)
- Hyperliquid (S3 sync, not traditional node)
- Avalanche Archive (use pruned instead)
- Sei Archive (use pruned instead)
- TON Archive (use full instead)

---

## Lite Mode Requirements (Tip-Following Only)

For running nodes that follow the chain tip without serving historical queries. Useful when historical data has been extracted separately.

### Lite Mode Storage & RAM (Excluding NEAR & Solana)

| Chain | Lite Storage (TB) | RAM (GB) | Notes |
|-------|-------------------|----------|-------|
| Ethereum L1 | 1.0 | 16 | Pruned Geth/Reth |
| Base | 0.8 | 16 | Pruned Reth |
| Polygon | 2.0 | 32 | Fast blocks = larger pruned state |
| BSC | 1.5 | 32 | 3-sec blocks, large state |
| Arbitrum | 0.8 | 16 | Pruned Nitro |
| TRON | 0.5 | 16 | Lite fullnode mode |
| Sui | 1.0 | 32 | Full node (no indexer) |
| Monad | 0.5 | 32 | Full node (TBD) |
| Mantle | 0.5 | 16 | Pruned OP Stack |
| Unichain | 0.5 | 16 | Pruned OP Stack |
| Starknet | 0.1 | 8 | Juno lite |
| Scroll | 0.5 | 16 | Pruned |
| Sei | 1.5 | 32 | Pruned Cosmos |
| Avalanche | 2.0 | 32 | Pruned C-chain |
| TON | 0.5 | 16 | Validator lite |
| Hyperliquid | 2.0 | 32 | Full node (not archive) |
| **TOTAL** | **~15.7 TB** | **~350 GB** | |

### Archive vs Lite Comparison

| Resource | Archive Mode | Lite Mode | Savings |
|----------|--------------|-----------|---------|
| **SSD** | 105.2 TB | ~15.7 TB | 85% less |
| **RAM** | ~500 GB | ~350 GB | 30% less |

### Bandwidth Requirements

#### Steady State (All Chains Running)

| Chain | Steady State (Mbps) | Initial Sync (Mbps) | Notes |
|-------|---------------------|---------------------|-------|
| Ethereum L1 | 10-20 | 100-200 | P2P gossip heavy |
| Base | 5-10 | 50-100 | L2, pulls from L1 |
| Polygon | 30-50 | 200-500 | 2-sec blocks, high throughput |
| BSC | 30-50 | 200-500 | 3-sec blocks, large blocks |
| Arbitrum | 5-10 | 50-100 | L2, moderate |
| TRON | 10-20 | 100-200 | Moderate P2P |
| Sui | 30-50 | 200-500 | High TPS chain |
| Monad | 50-100 | 500+ | 10k TPS target, very high |
| Mantle | 5-10 | 50-100 | L2, low overhead |
| Unichain | 5-10 | 50-100 | L2, low overhead |
| Starknet | 5-10 | 50-100 | ZK rollup, compressed |
| Scroll | 5-10 | 50-100 | ZK rollup, compressed |
| Sei | 20-30 | 200-300 | Fast Cosmos chain |
| Avalanche | 30-50 | 200-500 | High throughput |
| TON | 10-20 | 100-200 | Sharded, moderate |
| Hyperliquid | 50-100 | 500+ | High frequency trading data |

#### Bandwidth Totals

| Scenario | Bandwidth Required |
|----------|-------------------|
| **Steady state (all chains)** | **300-500 Mbps** |
| **Initial sync (parallel)** | **2-4 Gbps** |
| **Serving public RPC** | **+500 Mbps to 2 Gbps** (depends on load) |

#### Direction Breakdown

| Direction | Steady State | With Public RPC |
|-----------|--------------|-----------------|
| **Ingress** | 200-350 Mbps | 300-500 Mbps |
| **Egress** | 150-250 Mbps | 1-3 Gbps |

#### Monthly Data Transfer

| Mode | Monthly Transfer |
|------|------------------|
| Steady state only | ~100-150 TB/month |
| With moderate RPC serving | ~300-500 TB/month |
| High volume RPC | 1+ PB/month |

### Lite Mode Server Recommendation

For running all 16 chains in lite mode:

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **SSD** | 20 TB | 25-30 TB |
| **RAM** | 384 GB | 512 GB |
| **CPU** | 48 cores | 64+ cores |
| **Network** | 1 Gbps | 2.5-5 Gbps |

**Example Server Configuration:**
- 2x 15.36TB NVMe (~30TB usable)
- 512GB DDR5 RAM
- AMD EPYC or Intel Xeon with 64+ cores
- 2.5-5 Gbps unmetered bandwidth

**Key Tradeoff:** Lite nodes can only answer queries about recent state (last few days/weeks). Historical queries require external archive or separately stored data.

---

## Detailed Chain Information

### Ethereum L1

| Component | Full Node | Archive Node |
|-----------|-----------|--------------|
| Storage | ~1.6 TB | ~2.4-3 TB (Reth) |
| RAM | 32 GB | 32 GB |
| CPU | 4+ cores | 4+ cores |
| Recommended Client | Reth/Geth | Reth/Erigon |

**Snapshot Sources:**
- Merkle.io: ~1.34 TB compressed
- ethPandaOps: https://ethpandaops.io/data/snapshots/

**Notes:**
- Full nodes keep all blocks, transactions, receipts (logs)
- Archive only needed for `debug_traceTransaction` or historical `eth_call`

---

### Base (OP Stack L2)

| Component | Value |
|-----------|-------|
| Download Size | 4.3 TB (compressed) |
| Extracted Size | ~7-8 TB |
| RAM | 32 GB |
| CPU | 8+ cores |
| Recommended Client | Reth Archive |

**Snapshot URL:**
```
https://mainnet-reth-archive-snapshots.base.org/latest
```

**Notes:**
- Geth archive no longer recommended (performance issues)
- Requires L1 Ethereum endpoints (execution + beacon)

---

### Polygon (Bor + Heimdall)

| Component | Size |
|-----------|------|
| Bor (pebble) | ~4.7 TB |
| Heimdall | ~1.0 TB |
| Total | ~5.7 TB |
| Growth Rate | ~3 TB/month (high!) |

**Hardware:**
- RAM: 64 GB recommended
- CPU: 8+ cores

**Notes:**
- Requires TWO separate components running together
- Very high growth rate - plan storage accordingly
- **Warning:** 3 TB/month growth makes long-term self-hosting challenging

---

### BSC (BNB Chain)

| Type | Client | Size |
|------|--------|------|
| Fast (Pruned) | Geth | ~375 GB |
| Full | Geth | ~1 TB |
| Full | Reth | ~4.3 TB |
| Archive | Reth | ~9.7 TB |

**Hardware:**
- RAM: 32 GB
- CPU: 8+ cores
- Storage: NVMe SSD required

**Snapshot Sources:**
- 48Club (Geth + Reth): https://github.com/48Club/bsc-snapshots
- BNB Chain (Geth): https://github.com/bnb-chain/bsc-snapshots

**48Club Snapshot URLs:**
| File | Size | URL |
|------|------|-----|
| geth.fast (pruned) | 375 GB | `https://complete.snapshots.48.club/geth.fast.77830000.tar.zst` |
| geth.full | 1009 GB | `https://complete.snapshots.48.club/geth.full.77830000.tar.zst` |
| reth.full | 4289 GB | `https://complete.snapshots.48.club/reth.full.70572117.tar.zst` |
| reth.archive | 9701 GB | `https://complete.snapshots.48.club/reth.archive.70012269.tar.zst` |

**Download:**
```
aria2c -s4 -x4 -k1024M -o snapshot.tar.zst $SNAPSHOT_URL
```

**Extract:**
```
pv snapshot.tar.zst | tar --use-compress-program="zstd -d --long=31" -xf -
```

**Verify:**
```
pv snapshot.tar.zst | openssl md5
```

---

### Arbitrum One

| Type | Size | Notes |
|------|------|-------|
| Pruned | ~560 GB | Recent data only |
| Full | ~2-3 TB | All blocks/logs/txs |
| Archive | ~15+ TB | No longer maintained |

**Warning:** Archive snapshots discontinued since May 2024 due to rapid growth (~850 GB/month).

**Snapshot Source:**
- https://snapshot-explorer.arbitrum.io/

---

### TRON

| Type | Size |
|------|------|
| Lite FullNode | ~200-500 GB |
| Full Node | ~2.3-2.8 TB |
| Archive | ~80+ TB (not implemented) |

**Hardware:**
- CPU: 16 cores
- RAM: 32 GB
- Storage: 2.5 TB+ SSD

**Snapshot Source:**
- https://developers.tron.network/docs/main-net-database-snapshots

**Notes:**
- Lite FullNode only has last ~65K blocks
- Archive node not yet implemented in java-tron

---

### Sui

| Type | Size | Notes |
|------|------|-------|
| Formal Snapshot | ~30 GB | Recent epochs only |
| DB Snapshot (Pruned) | ~2.5 TB | With indexes |
| Recommended Disk | 4 TB NVMe | Official recommendation |

**Hardware:**
- CPU: 8 cores / 16 vCPUs
- RAM: 128 GB
- Growth: 10-40 GB/day depending on TPS

**Snapshot Sources:**
- S3: `s3://mysten-mainnet-snapshots/`
- GCS: `gs://mysten-mainnet-snapshots/`

**Notes:**
- Object-based storage (not traditional EVM)
- Formal snapshots don't support historical queries

---

### Sei

| Type | Size |
|------|------|
| Pruned | ~150-165 GB |
| Archive | 10+ TB minimum |

**Snapshot Providers:**
- Polkachu: ~163 GB (pruned)
- kjnodes: ~150 GB (pruned)
- CryptoCrew: Full archive

---

### Avalanche

| Type | Size |
|------|------|
| State Sync (Pruned) | ~500 GB initial |
| Pruned Running | ~1 TB |
| Full Archive | ~12.5 TB |

**Hardware:**
- CPU: 8 cores
- RAM: 16 GB
- Storage: NVMe SSD (3000+ IOPS required)

**Critical:** Must use local NVMe SSD - cloud block storage causes poor performance.

---

### Monad

| Component | Requirement |
|-----------|-------------|
| CPU | 16 cores, 4.5 GHz+ |
| RAM | 32 GB+ |
| TrieDB Storage | 2 TB NVMe |
| MonadBFT/OS Storage | 500 GB NVMe |
| Bandwidth | 100 Mbps (full) / 300 Mbps (validator) |

**Critical Requirements:**
- Bare metal servers ONLY (no cloud/VM)
- Samsung 980/990 Pro SSDs recommended
- ~$1,500 total hardware cost

**Notes:**
- Full nodes have all historical transactions/blocks/receipts
- Limited historical state (~40K blocks on 2TB)

---

### Mantle (OP Stack + EigenDA)

| Component | Estimated |
|-----------|-----------|
| Storage (Full) | ~500 GB - 2 TB |
| Storage (Archive) | ~2-5 TB |
| RAM | 16-32 GB |

**Notes:**
- Uses EigenDA for data availability (smaller than other OP Stack chains)
- Official requirements not publicly documented
- Verifier nodes available; sequencer centralized

---

### Unichain (OP Stack L2)

| Component | Estimated |
|-----------|-----------|
| Storage (Full) | ~100 GB - 1 TB |
| Storage (Archive) | ~1-3 TB |
| RAM | 8-32 GB |
| CPU | 4-8+ cores |

**Notes:**
- Launched late 2024 (newer chain, smaller storage)
- OP Stack based (similar to Base/Optimism)
- Requires Ethereum L1 RPC endpoint
- Will grow over time

**Resources:**
- GitHub: https://github.com/Uniswap/unichain-node
- Docs: https://docs.unichain.org/

---

### Starknet (ZK Rollup)

| Client | Storage | Notes |
|--------|---------|-------|
| **Juno** | ~125 GB | Recommended (5.7x smaller) |
| **Pathfinder** | ~713 GB | SQLite-based |

**Hardware:**
- CPU: 8 cores
- RAM: 16-32 GB
- Storage: 1-2 TB SSD

**Snapshot Sources:**
- Pathfinder: Weekly snapshots
- Juno: Weekly snapshots

**Notes:**
- Juno is significantly more storage-efficient
- Sync from snapshot: ~2-4 hours
- Sync from genesis: ~3-4 days
- Requires Ethereum L1 WebSocket RPC

---

### Scroll (ZK Rollup)

| Component | Value |
|-----------|-------|
| Archive Snapshot | ~2 TB |
| Minimum Disk | 4 TB (for download + extract) |
| RAM | 32 GB |
| Instance | AWS t3.2xlarge equivalent |

**Snapshot URL:**
```
https://scroll-geth-snapshot.s3.us-west-2.amazonaws.com/mpt/latest.tar
```

**Notes:**
- zkEVM based
- Requires Ethereum Mainnet RPC endpoint
- Docker deployment available

---

### TON (The Open Network)

| Type | Storage | RAM |
|------|---------|-----|
| Full Node | ~1 TB | 256 GB |
| Validator | ~1 TB | 256 GB |
| **Archive** | **~12-14 TB** | 256 GB |

**Hardware:**
- CPU: Dual processor, 8+ cores each
- Fast Storage (SSD): 512 GB+
- Archive Storage (HDD OK): 8+ TB
- Network: 1 Gbit/s+

**Storage Tips:**
- Use ZFS with compression (~1.08x ratio)
- Archive data can be on slower HDD
- Hot data should be on SSD

**Notes:**
- Full node grows ~10 GB/week
- Datacenter-grade server recommended

---

### NEAR Protocol

| Component | Recommended | Minimal |
|-----------|-------------|---------|
| CPU | 8 cores / 16 threads | 8 cores |
| RAM | 32 GB DDR4 | 24 GB |
| Hot Storage | 3 TB SSD | 1.5 TB SSD |
| Cold Storage | 115 TB (HDD OK) | 105 TB |

**Architecture:** Split Storage (Hot + Cold databases)

| Database | Size | Type |
|----------|------|------|
| Hot DB | ~1.5-3 TB | NVMe required |
| Cold DB | ~105-115 TB | HDD acceptable |
| Total Archive Snapshot | ~60 TB | 1M+ files |

**Monthly Costs (Cloud):**
- AWS: ~$1,500/mo
- GCP: ~$2,500/mo
- Azure: ~$734/mo

**Notes:**
- FastNEAR is sole snapshot provider since Jan 2025
- Free snapshot service deprecated June 2025

---

### Solana

| Type | Storage | RAM |
|------|---------|-----|
| Full RPC (Pruned) | 2-4 TB | 512 GB |
| Archive | ~400 TB | 1 TB |

**Hardware Requirements:**
- CPU: 12-24+ cores, 2.8 GHz+
- Accounts Storage: 500 GB+ NVMe (separate drive)
- Ledger Storage: 1-2 TB+ NVMe (separate drive)
- Network: 1-10 Gbps

**Critical:**
- Enterprise-grade NVMe SSDs required (Micron 7450/7500)
- Consumer SSDs degrade quickly
- Accounts and Ledger must be on separate drives

**Archive Node:**
- ~400 TB current size
- Growing 80-95 TB/year
- Self-hosting impractical - use RPC providers

---

### Hyperliquid

| Metric | Value |
|--------|-------|
| Daily Data Generation | ~100 GB/day |
| Archive Size (estimated) | ~10-30+ TB |
| Monthly Growth | ~3 TB |

**Architecture:**
- HyperCore (L1): Order book engine
- HyperEVM (L2): EVM-compatible layer

**Data Access:**
- S3 sync (requester pays): `s3://hl-mainnet-node-data/`
- No traditional snapshot downloads

**Providers for Historical Data:**
- Dwellir (indexed queries)
- QuickNode
- Amberdata

---

### Plasma

| Status | Value |
|--------|-------|
| Node Access | Not publicly available |
| Hardware Requirements | Not documented |
| Validators | Centralized (progressive decentralization) |

**Current Options:**
- Public RPC: `https://rpc.plasma.to`
- Managed: Chainstack, Alchemy, QuickNode

---

### Lighter

| Property | Value |
|----------|-------|
| Type | Application-Specific ZK Rollup |
| Purpose | Perpetuals DEX only |
| Public Nodes | Not available |
| Self-Hosting | Not supported |

**Notes:**
- Not a general-purpose L2
- Custom ZK circuits for order matching
- No EVM, no standard RPC
- Access via trading API only

---

## Storage Combinations

### 11TB Server Examples

| Combination | Total | Fits? |
|-------------|-------|-------|
| Base (Archive) | ~8 TB | Yes |
| Monad + Arbitrum + Ethereum + TRON | ~8 TB | Yes |
| BSC + Monad + Sui | ~10 TB | Yes |
| Polygon + Monad | ~9 TB | Yes |
| Base + TRON | ~10-11 TB | Tight |
| Base + Arbitrum | ~10-11 TB | Tight |

### 80TB Server - Recommended Setup

| Chain | Type | Size |
|-------|------|------|
| Ethereum L1 | Archive | 3 TB |
| Base | Archive | 8 TB |
| BSC | Full | 6 TB |
| Arbitrum | Full | 3 TB |
| TRON | Full | 3 TB |
| Sui | Full | 4 TB |
| Monad | Full | 2.5 TB |
| Mantle | Archive | 4 TB |
| Unichain | Archive | 2 TB |
| Starknet (Juno) | Full | 0.2 TB |
| Scroll | Archive | 2 TB |
| Avalanche | Pruned | 1 TB |
| Sei | Pruned | 0.2 TB |
| TON | Full | 1 TB |
| **Total** | | **~40 TB** |
| **Buffer** | | **~40 TB** |

---

## Chains by Difficulty

### Easy to Self-Host (< 5TB)
- Ethereum L1 (Full/Archive)
- Arbitrum (Full)
- TRON (Full)
- Monad (Full)
- Mantle (Archive)
- Unichain (Archive)
- Starknet (Juno/Pathfinder)
- Scroll (Archive)
- Sei (Pruned)
- Avalanche (Pruned)
- TON (Full)

### Moderate (5-15TB)
- Base (Archive)
- Polygon (Full) - **Warning: 3TB/month growth**
- BSC (Full)
- Sui (Full+Index)
- Sei (Archive)
- Avalanche (Archive)
- TON (Archive)

### Difficult/Expensive (15TB+)
- Arbitrum (Archive) - snapshots discontinued
- NEAR (Archive) - 60-115TB
- Hyperliquid (Archive) - S3 sync only

### Impractical for Self-Hosting
- Solana (Archive) - 400TB
- Plasma - not open to public
- Lighter - app-specific rollup

---

## Useful Links

### Snapshot Providers
- PublicNode: https://publicnode.com/snapshots
- Polkachu: https://polkachu.com/tendermint_snapshots
- kjnodes: https://services.kjnodes.com

### Documentation
- Base: https://docs.base.org/chain/node-snapshots
- Arbitrum: https://docs.arbitrum.io/run-arbitrum-node/nitro/nitro-database-snapshots
- Solana: https://docs.solanalabs.com/operations/requirements
- NEAR: https://near-nodes.io/archival/hardware-archival
- Sui: https://docs.sui.io/guides/operator/snapshots
- Avalanche: https://build.avax.network/docs/nodes/system-requirements
- Starknet: https://docs.starknet.io/secure/quickstart/running-a-node
- Scroll: https://docs.scroll.io/en/developers/guides/running-a-scroll-node/
- TON: https://docs.ton.org/v3/guidelines/nodes/running-nodes/archive-node
- Unichain: https://docs.unichain.org/

---

*Last updated: January 2026*

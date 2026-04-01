# Hyper-Plantir: Hyperliquid Historical State Reconstruction

Reconstruct any wallet's full state (positions, PnL, balances) at any block height using publicly available S3 data.

---

## Data Sources

All data lives in the **requester-pays** S3 bucket `s3://hl-mainnet-node-data`. AWS credentials required.

### node_fills_by_block

Every executed trade on the Hyperliquid DEX, indexed by block.

- **Path:** `s3://hl-mainnet-node-data/node_fills_by_block/hourly/{YYYYMMDD}/{hour}.lz4`
- **Coverage:** 2025-07-27 → present (continuously updated, hourly)
- **Total size:** ~136 GB (LZ4 compressed)
- **Format:** Newline-delimited JSON, one line per block, LZ4 compressed

Each line:

```json
{
  "local_time": "2026-04-01T00:00:00.065621324",
  "block_time": "2026-03-31T23:59:59.923939163",
  "block_number": 941773150,
  "events": [
    ["0x010461c14e146ac35fe42271bdc1134ee31c703a", {
      "coin": "S",
      "px": "0.040883",
      "sz": "481.0",
      "side": "B",
      "dir": "Open Long",
      "startPosition": "2423569.0",
      "closedPnl": "0.0",
      "fee": "0.0",
      "feeToken": "USDC",
      "time": 1775001599923,
      "hash": "0xf1fb1393...",
      "oid": 366968521024,
      "tid": 843853381927238,
      "crossed": true,
      "twapId": null
    }],
    ["0x26f68941...", { ... }]
  ]
}
```

**Key fields per fill:**

| Field | Description |
|-------|------------|
| `events[0]` | Wallet address |
| `coin` | Market (e.g. "BTC", "ETH", "S") |
| `px` | Execution price |
| `sz` | Fill size |
| `side` | "B" (buy) or "A" (sell/ask) |
| `dir` | "Open Long", "Open Short", "Close Long", "Close Short" |
| `startPosition` | Wallet's position size **before** this fill (consistency check) |
| `closedPnl` | Realized PnL on this fill (non-zero only on closes) |
| `fee` | Fee charged (negative = rebate) |
| `feeToken` | Fee denomination (usually "USDC") |
| `builderFee` | Builder fee if applicable (HIP-3) |
| `crossed` | Whether this was a taker (true) or maker (false) order |
| `oid` | Order ID |
| `tid` | Trade ID (shared between both sides of a match) |
| `twapId` | TWAP order ID if part of a TWAP execution |
| `cloid` | Client order ID if provided |

### misc_events_by_block

Non-fill events that affect wallet state: funding, deposits, withdrawals, ledger updates.

- **Path:** `s3://hl-mainnet-node-data/misc_events_by_block/hourly/{YYYYMMDD}/{hour}.lz4`
- **Coverage:** Full history → present (continuously updated, hourly)
- **Total size:** ~31 GB (LZ4 compressed)
- **Format:** Same as fills — newline-delimited JSON, one line per block, LZ4 compressed

Each line:

```json
{
  "block_time": "2026-04-01T00:00:00.068000768",
  "block_number": 941773152,
  "events": [
    {
      "time": "2026-04-01T00:00:00.068000768",
      "hash": "0x...",
      "inner": { "<EventType>": { ... } }
    }
  ]
}
```

**Event types:**

| Type | Description | Example |
|------|------------|---------|
| `Funding` | Periodic funding payments between longs and shorts. Contains `deltas` array with `user`, `coin`, `funding_amount` per affected wallet. | Affects unrealized PnL and margin balance |
| `LedgerUpdate` | Balance changes from fee rebates, margin transfers, liquidation penalties, etc. Lists affected `users`. | Catch-all for non-trade balance changes |
| `CDeposit` | USDC deposit into the exchange. Contains `user` and `amount`. | Capital inflow |
| `CWithdrawal` | USDC withdrawal from the exchange. Contains `user`, `amount`, `is_finalized`. | Capital outflow |
| `Delegation` | Staking delegation. Contains `user`, `validator`, `amount`. | HYPE staking |
| `ValidatorRewards` | Validator reward distributions. Contains `validator_to_reward` mapping. | Staking rewards |

---

## Downloading the Data

### Prerequisites

```bash
# AWS CLI with credentials configured
aws configure
# LZ4 for decompression
apt-get install lz4
```

### Using the download script

```bash
cd RPC_nodes

# Download everything (~167 GB compressed, ~$15 AWS transfer cost)
./hyperliquid/download-historical.sh

# Just fills (~136 GB, ~$12)
./hyperliquid/download-historical.sh -t fills

# Just misc events (~31 GB, ~$3)
./hyperliquid/download-historical.sh -t misc

# Custom data directory
./hyperliquid/download-historical.sh -d /path/to/data
```

The script uses `aws s3 sync` — rerun it to pick up new data without re-downloading existing files.

### Manual download

```bash
# Single file
aws s3 cp s3://hl-mainnet-node-data/node_fills_by_block/hourly/20260401/0.lz4 \
  ./fills/20260401/0.lz4 --request-payer requester

# Full sync
aws s3 sync s3://hl-mainnet-node-data/node_fills_by_block/ ./fills/ --request-payer requester
aws s3 sync s3://hl-mainnet-node-data/misc_events_by_block/ ./misc/ --request-payer requester
```

### Decompressing

```bash
# Single file
unlz4 file.lz4

# All files in a directory
find ./fills -name "*.lz4" -exec unlz4 --rm {} \;
```

### AWS cost estimate

S3 requester-pays data transfer: $0.09/GB

| Dataset | Size | Cost |
|---------|------|------|
| node_fills_by_block | ~136 GB | ~$12 |
| misc_events_by_block | ~31 GB | ~$3 |
| **Total** | **~167 GB** | **~$15** |

---

## Reconstructing Wallet State at Any Block

### Approach

1. Load fills and misc events chronologically
2. Maintain a running state per wallet: positions (per coin) and USDC balance
3. Apply each event in block order
4. Stop at the target block to read state

### Position tracking (from fills)

For each fill event:

```
wallet = event[0]  (address)
fill   = event[1]  (fill object)

# Verify consistency
assert wallet_positions[wallet][fill.coin] == fill.startPosition

# Update position
if fill.dir in ("Open Long", "Close Short"):
    wallet_positions[wallet][fill.coin] += fill.sz
elif fill.dir in ("Open Short", "Close Long"):
    wallet_positions[wallet][fill.coin] -= fill.sz

# Update balance
wallet_balance[wallet] += fill.closedPnl  # realized PnL
wallet_balance[wallet] -= fill.fee         # fees paid
```

The `startPosition` field is a built-in consistency check — it tells you what Hyperliquid thinks the wallet's position was before this fill. Use it to verify your running tally.

### Balance tracking (from misc events)

For each misc event, check `event.inner`:

```
Funding:
  for delta in event.inner.Funding.deltas:
    wallet_balance[delta.user] += delta.funding_amount

CDeposit:
  wallet_balance[event.inner.CDeposit.user] += amount

CWithdrawal:
  wallet_balance[event.inner.CWithdrawal.user] -= amount

LedgerUpdate:
  # Affects listed users, exact amounts may need to be
  # inferred from context or tracked via balance diffs
```

### Merging fills and misc events

Both datasets are indexed by `block_number`. To reconstruct state at block N:

1. Read both fills and misc events files in chronological order
2. For each block from genesis to N:
   - Apply all fill events (position changes, realized PnL, fees)
   - Apply all misc events (funding, deposits, withdrawals, ledger updates)
3. At block N, the running state is your answer

### Using periodic ABCI state snapshots (alternative)

If the Hyperliquid node is running with data retention, it saves state snapshots every 10,000 blocks to:

```
/data/rpc_nodes/hyperliquid-data/periodic_abci_states/{date}/{height}.rmp
```

These can be converted to readable format:

```bash
# Full L4 snapshot with all user positions
docker exec hyperliquid-node /home/hluser/hl-node --chain Mainnet \
  compute-l4-snapshots \
  /home/hluser/hl/data/periodic_abci_states/{date}/{height}.rmp \
  /tmp/snapshot.json --include-users

# Or translate raw ABCI state
docker exec hyperliquid-node /home/hluser/hl-node --chain Mainnet \
  translate-abci-state \
  /home/hluser/hl/data/periodic_abci_states/{date}/{height}.rmp \
  /tmp/state.json
```

This gives you a complete snapshot of every wallet's state at that block height (~10,000 block resolution, ~80 minutes). To get exact block precision, use the nearest snapshot as a starting point and replay fills/misc events forward.

### Hybrid approach (recommended)

For arbitrary block precision with minimal computation:

1. Find the nearest `periodic_abci_state` snapshot at or before target block
2. Load it with `compute-l4-snapshots --include-users` to get all wallet states
3. Replay `node_fills_by_block` and `misc_events_by_block` from snapshot block to target block
4. Result: exact state at any block, replaying at most ~10,000 blocks of data

---

## Data File Layout

After downloading:

```
/data/rpc_nodes/hyperliquid-data/historical/
├── fills/
│   └── hourly/
│       ├── 20250727/
│       │   ├── 0.lz4    # hour 0 (00:00-01:00 UTC)
│       │   ├── 1.lz4    # hour 1
│       │   └── ...
│       ├── 20250728/
│       └── ...through 20260401/
└── misc/
    └── hourly/
        ├── 20250727/
        └── ...through 20260401/
```

Each `.lz4` file contains one hour of blocks. Files are ~20-40 MB compressed (fills) and ~8 MB compressed (misc).

---

## Key Facts

- **Fills cover every position change.** Every open, close, liquidation fill, and ADL event produces a fill record.
- **`startPosition` is your consistency check.** If your running position doesn't match `startPosition`, you missed an event.
- **Funding is the biggest balance factor outside of fills.** Without it, position sizes are accurate but PnL will drift.
- **Liquidations appear as fills** with forced close directions. The margin penalty appears in `LedgerUpdate`.
- **Data goes back to July 27, 2025** for fills and misc events.
- **No WebSocket or historical query API** on the local node. This offline replay approach is the only way to get historical state.
- **Fills + misc events together are ~167 GB** — small enough to store on any machine and query locally.

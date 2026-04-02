# Hyperliquid Event Server API

Real-time and historical access to Hyperliquid fills and misc events.

**Base URL:** `http://localhost:3002`

---

## HTTP Endpoints

### GET /health

Health check.

```bash
curl http://localhost:3002/health
```

```json
{
  "status": "ok",
  "current_date": "20260402",
  "current_hour": "12",
  "fills_file_exists": true,
  "misc_file_exists": true
}
```

---

### GET /fills?date={YYYYMMDD}&hour={H}

Returns all fills for a specific hour. Each entry is one block.

```bash
curl "http://localhost:3002/fills?date=20260402&hour=10"
```

**Response:** JSON array of block objects.

```json
[
  {
    "block_number": 943400000,
    "block_time": "2026-04-02T10:00:01.123Z",
    "events": [
      ["0xWALLET...", {
        "coin": "BTC",
        "px": "68244.0",
        "sz": "0.001",
        "side": "B",
        "dir": "Open Long",
        "startPosition": "0.0",
        "closedPnl": "0.0",
        "fee": "0.05",
        "feeToken": "USDC",
        "oid": 123456,
        "tid": 789012,
        "crossed": true
      }]
    ]
  }
]
```

---

### GET /fills/latest?n={N}

Returns the last N block lines from the current hour's fill file. Default: 100.

```bash
curl "http://localhost:3002/fills/latest?n=10"
```

---

### GET /misc?date={YYYYMMDD}&hour={H}

Returns all misc events for a specific hour.

```bash
curl "http://localhost:3002/misc?date=20260402&hour=10"
```

**Response:** JSON array of block objects. Each block's events have an `inner` field with the event type:

```json
[
  {
    "block_number": 943400000,
    "events": [
      {
        "time": "2026-04-02T10:00:00.068Z",
        "hash": "0x...",
        "inner": {
          "Funding": {
            "deltas": [
              {"user": "0x...", "coin": "BTC", "funding_amount": "-0.05"}
            ]
          }
        }
      }
    ]
  }
]
```

**Misc event types:** `Funding`, `LedgerUpdate`, `CDeposit`, `CWithdrawal`, `Delegation`, `ValidatorRewards`

---

### GET /misc/latest?n={N}

Returns the last N block lines from the current hour's misc event file. Default: 100.

```bash
curl "http://localhost:3002/misc/latest?n=10"
```

---

## WebSocket Endpoints

All WebSocket endpoints stream new data in real-time as blocks are produced (~2 blocks/sec).

### WS /ws/fills

Stream fills only.

```javascript
const ws = new WebSocket("ws://localhost:3002/ws/fills");
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  // msg.type = "fills"
  // msg.data = { block_number, block_time, events: [...] }
};
```

### WS /ws/misc

Stream misc events only.

```javascript
const ws = new WebSocket("ws://localhost:3002/ws/misc");
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  // msg.type = "misc"
  // msg.data = { block_number, block_time, events: [...] }
};
```

### WS /ws/all

Stream both fills and misc events. Use `msg.type` to distinguish.

```javascript
const ws = new WebSocket("ws://localhost:3002/ws/all");
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  if (msg.type === "fills") { /* handle fill */ }
  if (msg.type === "misc") { /* handle misc event */ }
};
```

### WebSocket message format

```json
{
  "type": "fills",
  "data": {
    "block_number": 943438283,
    "block_time": "2026-04-02T12:15:55.274941059",
    "local_time": "2026-04-02T12:15:55.598165759",
    "events": [
      ["0x6ba889db...", {
        "coin": "XPL",
        "px": "0.10853",
        "sz": "1564.0",
        "side": "B",
        "dir": "Close Short",
        "startPosition": "-18826.0",
        "closedPnl": "0.802332",
        "fee": "0.013568",
        "feeToken": "USDC"
      }]
    ]
  }
}
```

---

## Fill Event Fields

| Field | Type | Description |
|-------|------|------------|
| `coin` | string | Market symbol (e.g. "BTC", "ETH") |
| `px` | string | Execution price |
| `sz` | string | Fill size |
| `side` | string | "B" (buy) or "A" (sell) |
| `dir` | string | "Open Long", "Open Short", "Close Long", "Close Short" |
| `startPosition` | string | Position size before this fill |
| `closedPnl` | string | Realized PnL (non-zero on closes) |
| `fee` | string | Fee charged (negative = rebate) |
| `feeToken` | string | Fee denomination |
| `crossed` | bool | Taker (true) or maker (false) |
| `oid` | int | Order ID |
| `tid` | int | Trade ID (shared between both sides) |
| `hash` | string | Transaction hash |
| `cloid` | string? | Client order ID (if provided) |
| `builderFee` | string? | Builder fee (HIP-3) |
| `twapId` | int? | TWAP order ID |

## Misc Event Types

| Type | Key Fields | Description |
|------|-----------|------------|
| `Funding` | `deltas[].user`, `deltas[].coin`, `deltas[].funding_amount` | Funding payments |
| `LedgerUpdate` | `users[]` | Balance changes (fees, transfers, liquidation penalties) |
| `CDeposit` | `user`, `amount` | USDC deposit |
| `CWithdrawal` | `user`, `amount`, `is_finalized` | USDC withdrawal |
| `Delegation` | `user`, `validator`, `amount` | Staking delegation |
| `ValidatorRewards` | `validator_to_reward[]` | Validator rewards |

#!/usr/bin/env python3
"""
Hyperliquid event server — serves node fills and misc events over HTTP and WebSocket.

Reads from the hl-node's local files:
  {DATA_ROOT}/node_fills_by_block/hourly/{YYYYMMDD}/{hour}
  {DATA_ROOT}/misc_events_by_block/hourly/{YYYYMMDD}/{hour}

HTTP endpoints:
  GET /fills?date=YYYYMMDD&hour=H          — returns all fills for that hour
  GET /fills/latest?n=100                   — returns the last N fill lines from current file
  GET /fills/since?block=N                  — returns blocks with block_number >= N from last 12h
  GET /misc?date=YYYYMMDD&hour=H           — returns all misc events for that hour
  GET /misc/latest?n=100                    — returns the last N misc event lines from current file
  GET /misc/since?block=N                   — returns blocks with block_number >= N from last 12h
  GET /health                               — health check

WebSocket endpoints:
  WS /ws/fills                              — stream fills in real-time
  WS /ws/misc                               — stream misc events in real-time
  WS /ws/all                                — stream both fills and misc events

Usage:
  python event-server.py [--data-root /path] [--host 0.0.0.0] [--port 3002]

Env vars:
  HL_DATA_ROOT  — override data root (default: /data/rpc_nodes/hyperliquid-data)
  HL_EVENT_PORT — override port (default: 3002)
"""

import asyncio
import json
import os
import sys
from collections import deque
from datetime import datetime, timedelta, timezone
from pathlib import Path

from sanic import Sanic, response
from sanic.log import logger

app = Sanic("hl-event-server")

DATA_ROOT = os.environ.get("HL_DATA_ROOT", "/data/rpc_nodes/hyperliquid-data")
FILLS_DIR = "node_fills_by_block/hourly"
MISC_DIR = "misc_events_by_block/hourly"
SINCE_WINDOW_HOURS = 12


# ─── helpers ─────────────────────────────────────────────────────────────────

def current_date_hour():
    now = datetime.now(timezone.utc)
    return now.strftime("%Y%m%d"), str(now.hour)


def event_file_path(event_type: str, date: str, hour: str) -> Path:
    subdir = FILLS_DIR if event_type == "fills" else MISC_DIR
    return Path(DATA_ROOT) / subdir / date / hour


def read_file_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    with open(path) as f:
        return f.readlines()


def _line_obj(line):
    """Parse one JSONL line -> (block_number, obj), or (None, None) if unusable."""
    try:
        obj = json.loads(line)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None, None
    bn = obj.get("block_number")
    return (bn, obj) if isinstance(bn, int) else (None, None)


def _tail_chunk(path: Path, size: int, want: int = 65536) -> bytes:
    with open(path, "rb") as f:
        f.seek(max(0, size - want))
        return f.read()


# Completed hour-files never change again, so their block range is memoised on
# (size, mtime). Only the current hour is re-read, and only when it has grown.
_range_cache: dict[str, tuple[int, float, int | None, int | None]] = {}


def _file_bn_range(path: Path) -> tuple[int | None, int | None]:
    """(first, last) block_number in a file, read from its head and tail only.

    Never reads the body — a 400 MB hour-file costs two small reads, not a full parse.
    """
    try:
        st = path.stat()
    except OSError:
        return None, None
    key = str(path)
    hit = _range_cache.get(key)
    if hit is not None and hit[0] == st.st_size and hit[1] == st.st_mtime:
        return hit[2], hit[3]

    first = last = None
    with open(path, "rb") as f:
        for line in f:
            first, _ = _line_obj(line)
            if first is not None:
                break
    if first is not None:
        # Last complete line wins; a partial trailing line simply fails to parse.
        for line in reversed(_tail_chunk(path, st.st_size).split(b"\n")):
            last, _ = _line_obj(line)
            if last is not None:
                break
    _range_cache[key] = (st.st_size, st.st_mtime, first, last)
    return first, last


def _scan_start_offset(path: Path, size: int, target: int) -> int:
    """A line-aligned offset at or before the first line with block_number >= target.

    block_number is append-ordered, so this binary-searches the file by byte offset
    instead of parsing from the start. Only ever advances past lines it has proven
    are below `target`, so the answer is never skipped.
    """
    lo, hi, best = 0, size, 0
    with open(path, "rb") as f:
        while lo < hi:
            mid = (lo + hi) // 2
            f.seek(mid)
            if mid:
                f.readline()          # discard the partial line we landed inside
            start = f.tell()
            line = f.readline()
            if not line:
                hi = mid
                continue
            bn, _ = _line_obj(line)
            if bn is not None and bn < target:
                best = start + len(line)
                lo = best
            else:
                hi = mid
    return best


def _collect_since(event_type: str, block: int, hours: int) -> tuple[list[dict], int | None, dict | None]:
    """Walk the last `hours` hour-files and return blocks with block_number >= block.

    Returns (events, oldest_block_in_window, error).
    - events: contiguous list of block objects, block.. <= max_in_window, in order
    - oldest_block_in_window: smallest block_number observed in the window (None if window empty)
    - error: None on success; otherwise a dict describing why the request can't be honored:
        {"kind": "predates_window", "oldest_block": N}
        {"kind": "gap", "missing_block": N, "next_available_block": M | None, "oldest_block": N}

    Blocking and CPU-bound — callers must run it off the event loop (see _since_response).
    """
    now = datetime.now(timezone.utc)
    paths = []
    for i in range(hours - 1, -1, -1):
        t = now - timedelta(hours=i)
        paths.append(event_file_path(event_type, t.strftime("%Y%m%d"), str(t.hour)))

    # Cheap pass: every file's block range from its head and tail, so the window
    # bounds are known without parsing gigabytes.
    ranges = []
    for path in paths:
        if not path.exists():
            continue
        first_bn, last_bn = _file_bn_range(path)
        if first_bn is None or last_bn is None:
            continue
        ranges.append((path, first_bn, last_bn))

    if not ranges:
        # Window is completely empty (no files exist or all were unparseable).
        return [], None, None

    min_bn = min(r[1] for r in ranges)
    max_bn = max(r[2] for r in ranges)

    if block < min_bn:
        return [], min_bn, {"kind": "predates_window", "oldest_block": min_bn}

    if block > max_bn:
        # Caller is ahead of our data (normal polling steady state).
        return [], min_bn, None

    # Expensive pass: read only the files that can hold blocks >= `block`, and only
    # the tail of the first such file. Oldest -> newest so that on an overlap
    # (adjacent files can repeat blocks after a node restart) the newest file wins.
    matching: dict[int, dict] = {}
    for path, first_bn, last_bn in ranges:
        if last_bn < block:
            continue
        try:
            size = path.stat().st_size
        except OSError:
            continue
        start = _scan_start_offset(path, size, block) if first_bn < block else 0
        file_map: dict[int, dict] = {}
        with open(path, "rb") as f:
            f.seek(start)
            for line in f:
                bn, obj = _line_obj(line)
                if bn is not None and bn >= block:
                    file_map[bn] = obj
        matching.update(file_map)

    # Verify contiguous coverage from `block` to `max_bn` — any missing block_number
    # means our data has a gap and we can't honor the >= block contract.
    out: list[dict] = []
    expected = block
    while expected <= max_bn:
        obj = matching.get(expected)
        if obj is None:
            # Find the next available block after the gap so the caller can resume.
            next_available = min((k for k in matching if k > expected), default=None)
            return [], min_bn, {
                "kind": "gap",
                "missing_block": expected,
                "next_available_block": next_available,
                "oldest_block": min_bn,
            }
        out.append(obj)
        expected += 1

    return out, min_bn, None


def tail_lines(path: Path, n: int) -> list[str]:
    if not path.exists():
        return []
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        if size == 0:
            return []
        buf = bytearray()
        pos = size
        lines_found = 0
        while pos > 0 and lines_found <= n:
            chunk = min(8192, pos)
            pos -= chunk
            f.seek(pos)
            buf[0:0] = f.read(chunk)
            lines_found = buf.count(b"\n")
        return buf.decode().splitlines()[-n:]


# ─── HTTP routes ─────────────────────────────────────────────────────────────

@app.get("/health")
async def health(_):
    date, hour = current_date_hour()
    fills_path = event_file_path("fills", date, hour)
    misc_path = event_file_path("misc", date, hour)
    return response.json({
        "status": "ok",
        "current_date": date,
        "current_hour": hour,
        "fills_file_exists": fills_path.exists(),
        "misc_file_exists": misc_path.exists(),
    })


@app.get("/fills")
async def get_fills(request):
    date = request.args.get("date")
    hour = request.args.get("hour")
    if not date or hour is None:
        return response.json({"error": "date and hour params required"}, status=400)
    path = event_file_path("fills", date, hour)
    if not path.exists():
        return response.json({"error": f"no data for {date}/{hour}"}, status=404)
    lines = read_file_lines(path)
    events = [json.loads(line) for line in lines if line.strip()]
    return response.json(events)


@app.get("/fills/latest")
async def get_fills_latest(request):
    n = int(request.args.get("n", 100))
    date, hour = current_date_hour()
    path = event_file_path("fills", date, hour)
    lines = tail_lines(path, n)
    events = [json.loads(line) for line in lines if line.strip()]
    return response.json(events)


async def _since_response(event_type: str, request):
    raw = request.args.get("block")
    if raw is None:
        return response.json({"error": "block param required (integer)"}, status=400)
    try:
        block = int(raw)
    except ValueError:
        return response.json({"error": "block param must be an integer"}, status=400)
    # _collect_since is blocking and CPU-bound. Sanic runs single_process, so calling
    # it inline froze the whole server for the length of a multi-GB scan — /health and
    # every other route hung and the process sat at 100% CPU until restarted.
    loop = asyncio.get_running_loop()
    events, oldest, error = await loop.run_in_executor(
        None, _collect_since, event_type, block, SINCE_WINDOW_HOURS
    )
    if error is not None:
        if error["kind"] == "predates_window":
            return response.json(
                {"error": f"block {block} predates {SINCE_WINDOW_HOURS}h retention window",
                 "oldest_block": error["oldest_block"]},
                status=404,
            )
        if error["kind"] == "gap":
            return response.json(
                {"error": f"block {error['missing_block']} is missing from on-disk data (gap)",
                 "missing_block": error["missing_block"],
                 "next_available_block": error["next_available_block"],
                 "oldest_block": error["oldest_block"]},
                status=404,
            )
    return response.json(events)


@app.get("/fills/since")
async def get_fills_since(request):
    return await _since_response("fills", request)


@app.get("/misc")
async def get_misc(request):
    date = request.args.get("date")
    hour = request.args.get("hour")
    if not date or hour is None:
        return response.json({"error": "date and hour params required"}, status=400)
    path = event_file_path("misc", date, hour)
    if not path.exists():
        return response.json({"error": f"no data for {date}/{hour}"}, status=404)
    lines = read_file_lines(path)
    events = [json.loads(line) for line in lines if line.strip()]
    return response.json(events)


@app.get("/misc/latest")
async def get_misc_latest(request):
    n = int(request.args.get("n", 100))
    date, hour = current_date_hour()
    path = event_file_path("misc", date, hour)
    lines = tail_lines(path, n)
    events = [json.loads(line) for line in lines if line.strip()]
    return response.json(events)


@app.get("/misc/since")
async def get_misc_since(request):
    return await _since_response("misc", request)


# ─── WebSocket tail ──────────────────────────────────────────────────────────

class FileTailer:
    """Watches an event file and broadcasts new lines to subscribers."""

    def __init__(self, event_type: str):
        self.event_type = event_type
        self.subscribers: set[asyncio.Queue] = set()
        self._task = None

    def start(self):
        self._task = asyncio.ensure_future(self._run())

    async def _run(self):
        current_path = None
        pos = 0
        while True:
            try:
                date, hour = current_date_hour()
                path = event_file_path(self.event_type, date, hour)

                if path != current_path:
                    current_path = path
                    pos = path.stat().st_size if path.exists() else 0
                    logger.info(f"[{self.event_type}] watching {path} from pos {pos}")

                if not path.exists():
                    await asyncio.sleep(1)
                    continue

                size = path.stat().st_size
                if size > pos:
                    with open(path, "rb") as f:
                        f.seek(pos)
                        new_data = f.read(size - pos)
                    # Only advance past complete lines; partial trailing data
                    # is left for the next read so hl-node can finish writing it.
                    last_nl = new_data.rfind(b"\n")
                    if last_nl == -1:
                        await asyncio.sleep(0.1)
                        continue
                    complete = new_data[: last_nl + 1]
                    pos += len(complete)
                    for line in complete.decode("utf-8", errors="replace").splitlines():
                        if not line.strip():
                            continue
                        try:
                            data = json.loads(line)
                        except json.JSONDecodeError as e:
                            logger.warning(
                                f"[{self.event_type}] skipping malformed line: {e}"
                            )
                            continue
                        msg = json.dumps({"type": self.event_type, "data": data})
                        dead = set()
                        for q in self.subscribers:
                            try:
                                q.put_nowait(msg)
                            except asyncio.QueueFull:
                                dead.add(q)
                        self.subscribers -= dead
                elif size < pos:
                    pos = 0

                await asyncio.sleep(0.1)
            except Exception as e:
                logger.error(f"[{self.event_type}] tailer error: {e}")
                await asyncio.sleep(1)

    def subscribe(self) -> asyncio.Queue:
        q = asyncio.Queue(maxsize=1000)
        self.subscribers.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue):
        self.subscribers.discard(q)


fills_tailer = FileTailer("fills")
misc_tailer = FileTailer("misc")


@app.listener("after_server_start")
async def start_tailers(app, loop):
    fills_tailer.start()
    misc_tailer.start()
    logger.info("File tailers started")


async def ws_stream(request, ws, tailers: list[FileTailer]):
    queues = [(t, t.subscribe()) for t in tailers]
    try:
        while True:
            for tailer, q in queues:
                try:
                    msg = q.get_nowait()
                    await ws.send(msg)
                except asyncio.QueueEmpty:
                    pass
            await asyncio.sleep(0.05)
    finally:
        for tailer, q in queues:
            tailer.unsubscribe(q)


@app.websocket("/ws/fills")
async def ws_fills(request, ws):
    await ws_stream(request, ws, [fills_tailer])


@app.websocket("/ws/misc")
async def ws_misc(request, ws):
    await ws_stream(request, ws, [misc_tailer])


@app.websocket("/ws/all")
async def ws_all(request, ws):
    await ws_stream(request, ws, [fills_tailer, misc_tailer])


# ─── main ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Hyperliquid event server")
    parser.add_argument("--data-root", default=DATA_ROOT)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=int(os.environ.get("HL_EVENT_PORT", 3002)))
    args = parser.parse_args()

    DATA_ROOT = args.data_root

    app.run(host=args.host, port=args.port, single_process=True)

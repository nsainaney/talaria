#!/usr/bin/env python3
"""Turn the phone's `bench` log marks into a per-turn timing table.

    docs/benchmarks/voice-bench.py tyche.logarchive            # one table, one row per spoken turn
    docs/benchmarks/voice-bench.py --collect Tyche --last 30m  # collect from the phone first (asks for sudo)
    docs/benchmarks/voice-bench.py tyche.logarchive --csv      # machine-readable

Marks come from talaria/Voice/Bench.swift. One turn runs from `utterance_end` to `reply_end`.
Columns, in seconds:

    endpoint  last partial -> utterance_end     (how long the phone waited after your last word)
    start     submit -> message_start           (Hermes taking the turn)
    tools     count and summed tool time        (lookups)
    token     message_start -> first_delta      (first token, includes the tools)
    tts       first_sentence -> first_audio     (synthesis to speaker)
    hear      last partial -> first_audio       (what you feel: silence after speaking)
    speak     first_audio -> reply_end          (reply length)

Timestamps come from the device log, so marks written by the app on different threads are
ordered as they were written. Hermes-side times (tool durations) are the server's own.
"""

import argparse
import json
import re
import statistics
import subprocess
import sys
from datetime import datetime

PREDICATE = 'subsystem == "com.sainaney.talaria" AND category == "bench"'


def collect(device: str, last: str) -> str:
    out = f"{device.lower()}-{datetime.now():%H%M}.logarchive"
    cmd = ["sudo", "/usr/bin/log", "collect", "--device-name", device, "--last", last, "--output", out]
    print("+", " ".join(cmd), file=sys.stderr)
    subprocess.run(cmd, check=True)
    return out


def marks(archive: str):
    cmd = ["/usr/bin/log", "show", "--info", "--style", "ndjson", "--predicate", PREDICATE, archive]
    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    for line in proc.stdout.splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = row.get("eventMessage", "")
        if not msg:
            continue
        name, _, detail = msg.strip().partition(" ")
        ts = datetime.strptime(row["timestamp"][:26], "%Y-%m-%d %H:%M:%S.%f")
        yield ts, name, dict(kv.split("=", 1) for kv in detail.split() if "=" in kv)


def turns(rows):
    """Split the stream of marks into turns: each starts at utterance_end and ends at reply_end
    (or at the next utterance_end when the reply was cut off)."""
    out, cur, last_partial = [], None, None
    for ts, name, kv in rows:
        if name == "partial":
            last_partial = ts
            continue
        if name == "utterance_end":
            if cur:
                out.append(cur)
            cur = {"t0": last_partial, "utterance_end": ts, "tools": [], "answering": kv.get("answering") == "true"}
            continue
        if cur is None:
            continue
        if name == "tool_start":
            cur["tools"].append({"name": kv.get("name", "?"), "start": ts})
        elif name == "tool_end":
            if cur["tools"] and "end" not in cur["tools"][-1]:
                cur["tools"][-1]["end"] = ts
                cur["tools"][-1]["dur"] = float(kv["dur"]) if kv.get("dur", "?") != "?" else None
        elif name not in cur:
            cur[name] = ts
            if name == "first_audio":
                cur["audio_path"] = kv.get("path", "")
            if name == "message_complete":
                cur["status"] = kv.get("status", "")
        if name == "reply_end":
            out.append(cur)
            cur = None
    if cur:
        out.append(cur)
    return out


def delta(t, a, b):
    if a in t and b in t and t[a] and t[b]:
        return (t[b] - t[a]).total_seconds()
    return None


def fmt(x):
    return "-" if x is None else f"{x:5.2f}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("archive", nargs="?", help="a .logarchive pulled from the phone")
    ap.add_argument("--collect", metavar="DEVICE", help="collect from this device first (e.g. Tyche)")
    ap.add_argument("--last", default="30m", help="how far back to collect (default 30m)")
    ap.add_argument("--csv", action="store_true")
    args = ap.parse_args()
    archive = collect(args.collect, args.last) if args.collect else args.archive
    if not archive:
        ap.error("give a .logarchive or --collect DEVICE")

    rows = []
    for t in turns(marks(archive)):
        if t["answering"]:
            continue  # a spoken allow/deny is not a question
        tools = [x for x in t["tools"] if x.get("dur") is not None]
        rows.append({
            "at": t["utterance_end"].strftime("%H:%M:%S"),
            "endpoint": delta(t, "t0", "utterance_end"),
            "start": delta(t, "submit", "message_start"),
            "n_tools": len(t["tools"]),
            "tools": sum(x["dur"] for x in tools) if tools else (0.0 if not t["tools"] else None),
            "token": delta(t, "message_start", "first_delta"),
            "tts": delta(t, "first_sentence", "first_audio"),
            "hear": delta(t, "t0", "first_audio"),
            "speak": delta(t, "first_audio", "reply_end"),
            "path": t.get("audio_path", ""),
            "status": t.get("status", ""),
        })

    cols = ["endpoint", "start", "tools", "token", "tts", "hear", "speak"]
    if args.csv:
        print("at,endpoint,start,n_tools,tools,token,tts,hear,speak,path,status")
        for r in rows:
            print(",".join(str(r[k]) if r[k] is not None else "" for k in ["at", "endpoint", "start", "n_tools", "tools", "token", "tts", "hear", "speak", "path", "status"]))
        return

    if not rows:
        print("no turns found (is the bench category in the archive? was voice mode used?)")
        return
    print(f"{'at':8} {'endpt':>5} {'start':>5} {'tools':>9} {'token':>5} {'tts':>5} {'hear':>5} {'speak':>5}  path    status")
    for r in rows:
        tools = f"{r['n_tools']}x {fmt(r['tools'])}" if r["n_tools"] else "   0    -"
        print(f"{r['at']:8} {fmt(r['endpoint']):>5} {fmt(r['start']):>5} {tools:>9} {fmt(r['token']):>5} {fmt(r['tts']):>5} {fmt(r['hear']):>5} {fmt(r['speak']):>5}  {r['path']:7} {r['status']}")
    print()
    med = {c: statistics.median([r[c] for r in rows if r[c] is not None]) for c in cols if any(r[c] is not None for r in rows)}
    print(f"{'median':8} " + " ".join(f"{fmt(med.get(c)):>5}" if c != "tools" else f"{'':3}{fmt(med.get(c)):>6}" for c in cols) + f"   n={len(rows)}")


if __name__ == "__main__":
    main()

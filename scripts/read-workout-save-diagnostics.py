"""Summarize copied app-owned diagnostic files; never needs device/root access."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("files", nargs="+", type=Path)
args = parser.parse_args()
operations = {}
skipped = 0
dropped = 0
for file in args.files:
    for line in file.read_text().splitlines():
        try:
            row = json.loads(line)
            if not isinstance(row, dict) or row.get("version") != 1:
                skipped += 1
                continue
            if row["event"] not in {"begin", "running", "end"}:
                raise ValueError("unknown event")
            for field in ["phase", "timestamp", "elapsedMs"]:
                row[field]
            key = (row["run"], row["operation"])
            operations.setdefault(key, {})[row["event"]] = row
            dropped += row.get("droppedBefore", 0)
        except (ValueError, KeyError, TypeError):
            skipped += 1  # A terminated process may leave an incomplete final line.
summary = []
for (run, operation), events in operations.items():
    first = events.get("begin") or events.get("running") or events["end"]
    end = events.get("end")
    running = events.get("running")
    total = end["elapsedMs"] if end else None
    wait = running["elapsedMs"] if running else None
    summary.append({"run": run, "operation": operation, "timestamp": first["timestamp"],
        "phase": first["phase"], "totalMs": total, "queueWaitMs": wait,
        "executionMs": max(0, total - wait) if total is not None and wait is not None else None,
        "outcome": end.get("outcome") if end else "no_end_record",
        "errorDomain": end.get("errorDomain") if end else None,
        "errorCode": end.get("errorCode") if end else None})
print(json.dumps({"operations": sorted(summary, key=lambda r: r["timestamp"]),
    "skippedLines": skipped, "reportedDroppedEntries": dropped}, indent=2))

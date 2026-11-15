"""Owner-private, fixed-vocabulary diagnostics for the *running* P3/P4 worker.

The producer is invoked by the existing Owner agent loop. The CLI is a
read-only, owner-local observer; it never opens LAN, selects media, reads a
pairing key or performs a provider request. Runner ACLs are not modified.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import time

from p3_ingress_telemetry import EVENTS as _INGRESS_FIELDS
from p3_ingress_telemetry import MAX_COUNT as _MAX_INGRESS_COUNT


SCHEMA = "TTV-OWNER-P3P4-DIAGNOSTIC-V2"
RUNTIME_VERSION = "P3P4-INTEGRATED-DIAGNOSTIC-V2"
_NAME = "p3-p4-runtime-diagnostic.json"
_MODES = frozenset({"INTEGRATED_P3_P4"})
_STATES = frozenset({"READY", "STARTING", "STOPPED", "BLOCKED"})
_P3 = frozenset({"FRESH_ON", "FRESH_REQUESTED", "FRESH_OFF",
                 "FRESH_OTHER", "FRESH_INACTIVE", "STALE", "MISSING",
                 "UNKNOWN"})
_TS = frozenset({"TCP_REACHABLE_METADATA_UNTESTED", "TCP_UNREACHABLE",
                 "CONFIG_INVALID", "UNTESTED"})
_FIELDS = frozenset({"schema", "mode", "version", "state", "p3", "torrserver",
                     "p3_remaining_seconds", "observed_utc_epoch", "pid",
                     "p3_ingress"})


def _root(owner_root: Path) -> Path:
    if (not isinstance(owner_root, Path) or not owner_root.is_absolute()
            or owner_root.is_symlink()):
        raise ValueError("P3P4_DIAG_PRIVATE_ROOT_INVALID")
    return owner_root


def _tcp_only_probe(reader: object) -> str:
    """TCP connect to pinned loopback only; no HTTP, hash or file metadata."""
    cfg = getattr(reader, "_config", None)
    port = getattr(cfg, "localhost_port", None)
    if type(port) is not int or not 1024 <= port <= 65535:
        return "CONFIG_INVALID"
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.25):
            return "TCP_REACHABLE_METADATA_UNTESTED"
    except (OSError, TimeoutError):
        return "TCP_UNREACHABLE"


def _p3_only_snapshot(cache: object) -> tuple[str, int]:
    """Read only a non-identifying cache enum; never enumerate TV state."""
    try:
        value, remaining = cache.diagnostic_freshness()
    except Exception:
        return "UNKNOWN", 0
    if (type(value) is not str or value not in _P3
            or type(remaining) is not int or not 0 <= remaining <= 8):
        return "UNKNOWN", 0
    return value, remaining


def _ingress_only_snapshot(ingress: object) -> dict[str, object]:
    """Never persist a user-supplied message or raw HTTP rejection reason."""
    empty: dict[str, object] = {
        "instrumented": False,
        **{key: 0 for key in sorted(_INGRESS_FIELDS)},
    }
    try:
        counts = ingress.snapshot()
    except Exception:
        return empty
    if (not isinstance(counts, dict) or set(counts) != _INGRESS_FIELDS
            or any(type(value) is not int or not 0 <= value <= _MAX_INGRESS_COUNT
                   for value in counts.values())):
        return empty
    return {"instrumented": True, **counts}


def write_diagnostic(*, owner_root: Path, wiring: object, state: str) -> None:
    """Atomic owner-private status; callback runs inside actual Owner process."""
    root = _root(owner_root)
    if state not in _STATES or type(state) is not str:
        raise ValueError("P3P4_DIAG_STATE_INVALID")
    if not root.is_dir():
        raise ValueError("P3P4_DIAG_PRIVATE_ROOT_MISSING")
    target = root / _NAME
    if target.is_symlink():
        raise ValueError("P3P4_DIAG_SYMLINK")
    if state == "READY":
        p3, remaining = _p3_only_snapshot(getattr(wiring, "cache", None))
        reader = getattr(getattr(wiring, "current", None), "_ts", None)
        ts = _tcp_only_probe(reader)
        ingress = _ingress_only_snapshot(getattr(wiring, "ingress", None))
    else:
        p3, ts, remaining = "UNKNOWN", "UNTESTED", 0
        ingress = _ingress_only_snapshot(None)
    doc = {"schema": SCHEMA, "mode": "INTEGRATED_P3_P4",
           "version": RUNTIME_VERSION, "state": state,
           "p3": p3, "torrserver": ts,
           "p3_remaining_seconds": remaining,
           "p3_ingress": ingress,
           "pid": os.getpid(),
           "observed_utc_epoch": int(time.time())}
    payload = json.dumps(doc, separators=(",", ":"), sort_keys=True).encode("ascii")
    temporary = root / ("p3-p4-diag-" + secrets.token_hex(8) + ".tmp")
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def read_diagnostic(*, owner_root: Path, now: float | None = None
                    ) -> dict[str, str]:
    """Reject forged/stale records; never declare live from a file alone."""
    root = _root(owner_root)
    result = {"OWNER_RUNTIME_MODE": "NOT_OBSERVED",
              "OWNER_RUNTIME_VERSION": "NOT_OBSERVED",
              "P3_STATE_FRESH": "UNKNOWN",
              "TORRSERVER_READER_READY": "UNTESTED",
              "OWNER_HEARTBEAT": "NOT_OBSERVED",
              "P3_HTTPS_INSTRUMENTED": "NOT_OBSERVED",
              **{"P3_HTTPS_" + name.upper(): "NOT_OBSERVED"
                 for name in sorted(_INGRESS_FIELDS)}}
    heartbeat = root / "agent-health.json"
    diagnosis = root / _NAME
    try:
        if (heartbeat.is_symlink() or diagnosis.is_symlink()
                or not heartbeat.is_file() or not diagnosis.is_file()
                or heartbeat.stat().st_size > 512
                or diagnosis.stat().st_size > 512):
            return result
        a = json.loads(heartbeat.read_text(encoding="utf-8"))
        d = json.loads(diagnosis.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError, RecursionError):
        return result
    now_sec = time.time() if now is None else now
    if (not isinstance(a, dict) or set(a) != {
            "schema", "state", "observed_utc_epoch", "pid"}
            or a["schema"] != "TTV-OWNER-AGENT-HEALTH-V1"
            or a["state"] != "READY"
            or type(a["pid"]) is not int or a["pid"] <= 0
            or type(a["observed_utc_epoch"]) is not int
            or not isinstance(d, dict) or set(d) != _FIELDS
            or d["schema"] != SCHEMA or type(d["mode"]) is not str
            or d["mode"] not in _MODES
            or d["version"] != RUNTIME_VERSION
            or d["state"] != "READY"
            or type(d["p3"]) is not str or d["p3"] not in _P3
            or type(d["torrserver"]) is not str
            or d["torrserver"] not in _TS
            or type(d["p3_remaining_seconds"]) is not int
            or not 0 <= d["p3_remaining_seconds"] <= 8
            or type(d["pid"]) is not int or d["pid"] != a["pid"]
            or not isinstance(d["p3_ingress"], dict)
            or set(d["p3_ingress"]) != _INGRESS_FIELDS | {"instrumented"}
            or type(d["p3_ingress"]["instrumented"]) is not bool
            or any(type(d["p3_ingress"][name]) is not int
                   or not 0 <= d["p3_ingress"][name] <= _MAX_INGRESS_COUNT
                   for name in _INGRESS_FIELDS)
            or type(d["observed_utc_epoch"]) is not int
            or type(now_sec) not in (int, float)
            or not 0 <= now_sec - a["observed_utc_epoch"] <= 30
            or not 0 <= now_sec - d["observed_utc_epoch"] <= 5
            or abs(a["observed_utc_epoch"] - d["observed_utc_epoch"]) > 20):
        return result
    # Snapshot freshness is never extended by reading an old file. Remaining
    # lifetime was rounded DOWN by the in-memory cache; be conservative.
    p3 = d["p3"]
    if p3.startswith("FRESH_") and (
            now_sec - d["observed_utc_epoch"] >=
            d["p3_remaining_seconds"]):
        p3 = "STALE"
    result.update(OWNER_RUNTIME_MODE=d["mode"],
                  OWNER_RUNTIME_VERSION=d["version"],
                  P3_STATE_FRESH=p3,
                  TORRSERVER_READER_READY=d["torrserver"],
                  OWNER_HEARTBEAT="READY_FRESH",
                  P3_HTTPS_INSTRUMENTED=(
                      "YES" if d["p3_ingress"]["instrumented"] else "NO"))
    result.update({"P3_HTTPS_" + name.upper(): str(d["p3_ingress"][name])
                   for name in sorted(_INGRESS_FIELDS)})
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Owner-local read-only P3/P4 diagnostic")
    parser.add_argument("--owner-root", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        status = read_diagnostic(owner_root=args.owner_root)
    except ValueError:
        print("TTV_P3P4_DIAG=PRIVATE_OWNER_ROOT_INVALID")
        return 2
    for key, value in status.items():
        print(key + "=" + value)
    print("TTV_P3P4_DIAG=READ_ONLY_COMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""One-way, fixed-schema Owner -> HostOps diagnostic receipt.

The Owner's existing P3/P4 diagnostic tick invokes this module. No private
file, movie title, key, claim, provider state or raw HTTP data crosses into
ProgramData. The destination must be pre-enrolled by an interactive owner;
this module never creates/changes ACLs or opens a Windows service.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets
import time

from owner_p3_p4_diagnostics import (
    SCHEMA as PRIVATE_SCHEMA, _FIELDS as PRIVATE_FIELDS, read_diagnostic,
)
from p3_ingress_telemetry import EVENTS as INGRESS_FIELDS


SCHEMA = "TTV-HOSTOPS-OWNER-SNAPSHOT-V1"
_MAX_BYTES = 3072
_DIR_PARTS = ("TorrentTVVietsub", "OwnerBridge", "Diagnostics")
_FILENAME = "owner-snapshot.json"
_OBSERVATIONS = frozenset({"MISSING", "STALE", "PID_MISMATCH",
                           "INVALID_SCHEMA", "OWNER_NOT_RUNNING", "READY_FRESH"})


def _is_link(path: Path) -> bool:
    return path.is_symlink() or getattr(path, "is_junction", lambda: False)()


def _classify(owner_root: Path, tick: int,
              normalized: dict[str, str]) -> tuple[str, int, int]:
    """Classify the OLD fixed private schema without changing pinned V2 bytes.

    Existing V2 staging scripts hash-pin owner_p3_p4_diagnostics.py. Keep that
    artifact immutable; add richer observability here, not by silently
    invalidating an already staged/installed Owner bundle.
    """
    health = owner_root / "agent-health.json"
    diag = owner_root / "p3-p4-runtime-diagnostic.json"
    try:
        if not health.exists() or not diag.exists():
            return "MISSING", -1, -1
        if (_is_link(health) or _is_link(diag) or not health.is_file()
                or not diag.is_file()
                or not 0 < health.stat().st_size <= 512
                or not 0 < diag.stat().st_size <= 1536):
            return "INVALID_SCHEMA", -1, -1
        a = json.loads(health.read_text(encoding="utf-8"))
        d = json.loads(diag.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError, RecursionError):
        return "INVALID_SCHEMA", -1, -1
    if (not isinstance(a, dict) or not isinstance(d, dict)
            or set(a) != {"schema", "state", "observed_utc_epoch", "pid"}
            or set(d) != PRIVATE_FIELDS
            or a["schema"] != "TTV-OWNER-AGENT-HEALTH-V1"
            or d["schema"] != PRIVATE_SCHEMA
            or type(a["pid"]) is not int or a["pid"] <= 0
            or type(d["pid"]) is not int or d["pid"] <= 0
            or type(a["observed_utc_epoch"]) is not int
            or type(d["observed_utc_epoch"]) is not int
            or a["state"] not in ("READY", "STARTING", "STOPPED", "BLOCKED")
            or d["state"] not in ("READY", "STARTING", "STOPPED", "BLOCKED")):
        return "INVALID_SCHEMA", -1, -1
    if a["state"] != "READY" or d["state"] != "READY":
        return "OWNER_NOT_RUNNING", -1, -1
    if a["pid"] != d["pid"]:
        return "PID_MISMATCH", -1, -1
    age = tick - d["observed_utc_epoch"]
    if (not 0 <= age <= 5
            or not 0 <= tick - a["observed_utc_epoch"] <= 30
            or abs(a["observed_utc_epoch"] - d["observed_utc_epoch"]) > 20):
        return "STALE", -1, -1
    if normalized["OWNER_RUNTIME_MODE"] != "INTEGRATED_P3_P4":
        return "INVALID_SCHEMA", -1, -1
    return "READY_FRESH", d["observed_utc_epoch"], age


def build_snapshot(*, owner_root: Path, now: int | None = None) -> dict:
    """Read existing normalized diagnostics; transmit fixed enums/counts only."""
    tick = int(time.time()) if now is None else now
    if type(tick) is not int or tick < 0:
        raise ValueError("HOSTOPS_SNAPSHOT_TIMESTAMP_INVALID")
    observed = read_diagnostic(owner_root=owner_root, now=tick)
    status, owner_epoch, owner_age = _classify(owner_root, tick, observed)
    if status not in _OBSERVATIONS:
        raise ValueError("HOSTOPS_SNAPSHOT_STATUS_INVALID")
    ready = status == "READY_FRESH"
    counts = {}
    for field in sorted(INGRESS_FIELDS):
        value = observed["P3_HTTPS_" + field.upper()]
        counts[field] = int(value) if ready else -1
    return {
        "schema": SCHEMA,
        "status": status,
        "snapshot_utc_epoch": tick,
        "owner_observed_utc_epoch": owner_epoch,
        "owner_snapshot_age_seconds": owner_age,
        "mode": observed["OWNER_RUNTIME_MODE"] if ready else "NOT_OBSERVED",
        "version": observed["OWNER_RUNTIME_VERSION"] if ready else "NOT_OBSERVED",
        "heartbeat": observed["OWNER_HEARTBEAT"] if ready else "NOT_OBSERVED",
        "p3_state": observed["P3_STATE_FRESH"] if ready else "UNKNOWN",
        "torrserver": (observed["TORRSERVER_READER_READY"]
                       if ready else "UNTESTED"),
        "ingress_instrumented": (
            observed["P3_HTTPS_INSTRUMENTED"] if ready else "NOT_OBSERVED"),
        "ingress": counts,
    }


def publish_owner_snapshot(*, owner_root: Path,
                           shared_dir: Path | None = None) -> bool:
    """Atomic best-effort export, only to an already enrolled fixed spool.

    ``shared_dir`` is a test injection seam. In production the path is fixed
    beneath PROGRAMDATA and this function runs in the Owner session, not CI.
    """
    if shared_dir is None:
        if (os.name != "nt" or os.environ.get("CI", "").lower() == "true"
                or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"):
            return False
        programdata = os.environ.get("PROGRAMDATA")
        if not programdata or not Path(programdata).is_absolute():
            return False
        shared_dir = Path(programdata).joinpath(*_DIR_PARTS)
    if (not isinstance(shared_dir, Path) or not shared_dir.is_absolute()
            or _is_link(shared_dir) or not shared_dir.is_dir()):
        return False
    target = shared_dir / _FILENAME
    if _is_link(target):
        return False
    receipt = build_snapshot(owner_root=owner_root)
    contents = json.dumps(receipt, sort_keys=True,
                          separators=(",", ":"), ensure_ascii=True).encode("ascii")
    if len(contents) > _MAX_BYTES:
        raise ValueError("HOSTOPS_SNAPSHOT_TOO_LARGE")
    temporary = shared_dir / ("owner-snapshot-" + secrets.token_hex(8) + ".tmp")
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return True

"""One-way, fixed-schema Owner -> HostOps diagnostic receipt.

The Owner's existing P3/P4 tick reads private diagnostics and P2 marker
metadata. Only sanitized counts, fixed enums and marker-byte hashes cross
into ProgramData: never media, claims, secrets or provider payloads. The
destination must be pre-enrolled; this module never changes ACLs or tasks.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import time

from owner_p3_p4_diagnostics import (
    SCHEMA as PRIVATE_SCHEMA, _FIELDS as PRIVATE_FIELDS, read_diagnostic,
)
from p3_ingress_telemetry import EVENTS as INGRESS_FIELDS


SCHEMA = "TTV-HOSTOPS-OWNER-SNAPSHOT-V2"
_MAX_BYTES = 4096
_DIR_PARTS = ("TorrentTVVietsub", "OwnerBridge", "Diagnostics")
_FILENAME = "owner-snapshot.json"
_OBSERVATIONS = frozenset({"MISSING", "STALE", "PID_MISMATCH",
                           "INVALID_SCHEMA", "OWNER_NOT_RUNNING", "READY_FRESH"})
# Reviewed no-retry worker Git blob on PR #175 (fa44cdbb). Comparing bytes,
# rather than a version string, keeps any old installed worker fail-closed.
_P2_NO_RETRY_WORKER_BLOB = "69245ba65db167a63643ddcd6a4ce4a81a38a1e2"
_P2_JOB = re.compile(r"[0-9a-f]{64}\Z")
_P2_BATCH = re.compile(r"batch-([0-9]{4})\.inflight\Z")


def _is_link(path: Path) -> bool:
    return path.is_symlink() or getattr(path, "is_junction", lambda: False)()


def _p2_observation(owner_root: Path) -> dict:
    """Inspect Owner-private P2 metadata; never read cues, secrets or provider.

    Export only bounded aggregate counts, marker-byte SHA and fixed enums.
    An uncertain call is always HOLD; this observer never changes its marker.
    """
    result = {
        "status": "READ_UNAVAILABLE", "pending_events": -1,
        "inflight_count": -1, "batch": "NOT_OBSERVED",
        "marker_sha256": "NOT_OBSERVED", "checkpoint_present": "NOT_OBSERVED",
        "active_lock_present": "NOT_OBSERVED",
        "installed_no_retry_worker_match": "NOT_OBSERVED",
    }
    try:
        if _is_link(owner_root) or _is_link(owner_root.parent):
            return result
        inbox = owner_root / "inbox"
        if inbox.is_dir() and not _is_link(inbox):
            pending = 0
            for event in inbox.glob("event-*.json"):
                if event.is_file():
                    pending += 1
                if pending > 10000:
                    break
            result["pending_events"] = pending
        worker = (owner_root / "app" / "poc" / "p2-aisub" /
                  "automatic_lean120_worker.py")
        if (worker.is_file() and not _is_link(worker)
                and 0 < worker.stat().st_size <= 262144):
            payload = worker.read_bytes()
            # Windows Git checkouts may copy CRLF source to the Owner app;
            # compare the reviewed LF Git blob after strict newline folding.
            # Any lone CR, BOM or semantic source edit still fails closed.
            if not payload.startswith(b"\xef\xbb\xbf"):
                payload = payload.replace(b"\r\n", b"\n")
            if b"\r" in payload:
                payload = b""
            blob = hashlib.sha1(
                b"blob " + str(len(payload)).encode("ascii") + b"\0" +
                payload).hexdigest()
            result["installed_no_retry_worker_match"] = (
                "YES" if blob == _P2_NO_RETRY_WORKER_BLOB else "NO")
        state = owner_root.parent / "P2" / "auto-lean120-state"
        if not state.exists():
            result["status"] = "STATE_MISSING"
            return result
        if not state.is_dir() or _is_link(state):
            return result
        # Worker state has one 64-hex job directory per source/model profile.
        # Reject unexpected nested paths rather than reporting a false CLEAR.
        markers = []
        for job in state.iterdir():
            if _is_link(job):
                return result
            if not job.is_dir():
                continue
            if not _P2_JOB.fullmatch(job.name):
                return result
            for child in job.iterdir():
                if _is_link(child):
                    return result
                if child.is_dir():
                    return result
                if child.name.endswith(".inflight"):
                    markers.append(child)
                    if len(markers) > 10000:
                        return result
        result["inflight_count"] = len(markers)
        if not markers:
            result["status"] = "CLEAR"
            return result
        if len(markers) > 1:
            result["status"] = "MULTIPLE_HOLD"
            return result
        marker = markers[0]
        matched = _P2_BATCH.fullmatch(marker.name)
        if not matched or marker.stat().st_size > 4096:
            result["status"] = "INVALID_MARKER"
            return result
        raw = marker.read_bytes()
        try:
            doc = json.loads(raw)
        except (ValueError, UnicodeError):
            result["status"] = "INVALID_MARKER"
            return result
        if (not isinstance(doc, dict) or set(doc) != {"schema", "job", "version"}
                or doc["schema"] != "TTV-P2-INFLIGHT-V1"
                or doc["job"] != marker.parent.name
                or type(doc["version"]) is not int
                or doc["version"] != int(matched.group(1))
                or doc["version"] < 1):
            result["status"] = "INVALID_MARKER"
            return result
        checkpoint = marker.with_suffix(".json")
        lock = marker.parent / "active.lock"
        if _is_link(checkpoint) or _is_link(lock):
            return result
        result.update({
            "status": "UNKNOWN_EFFECT_HOLD", "batch": marker.stem,
            "marker_sha256": hashlib.sha256(raw).hexdigest(),
            "checkpoint_present": "YES" if checkpoint.is_file() else "NO",
            "active_lock_present": "YES" if lock.is_file() else "NO",
        })
    except (OSError, ValueError, UnicodeError, RecursionError):
        result.update({"status": "READ_UNAVAILABLE", "inflight_count": -1,
                       "batch": "NOT_OBSERVED",
                       "marker_sha256": "NOT_OBSERVED",
                       "checkpoint_present": "NOT_OBSERVED",
                       "active_lock_present": "NOT_OBSERVED"})
    return result


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
        "p2": _p2_observation(owner_root),
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

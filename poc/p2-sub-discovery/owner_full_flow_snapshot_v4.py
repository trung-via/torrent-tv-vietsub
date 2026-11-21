"""Single read-only Owner flight recorder for P3 -> P2 -> P4.

Only bounded counters and fixed reason codes leave the private Owner session.
No subtitle bytes, media keys, torrent identities, API content or log lines are
published. In particular, a live ``.inflight`` file is NOT called a failure.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import secrets
import time

from owner_hostops_snapshot import _DIR_PARTS, _FILENAME, _MAX_BYTES, _is_link
from owner_hostops_snapshot_v3 import build_snapshot_v3

SCHEMA = "TTV-HOSTOPS-OWNER-SNAPSHOT-V4"
_LOG_TAIL = 192 * 1024
_START = re.compile(rb"^OWNER_FULL_DIAGNOSTICS_STARTED pid=([0-9]{1,10}) epoch=[0-9]{1,12}$")
_CHECKPOINT = re.compile(r"batch-([0-9]{4})\.json\Z")
_JOB = re.compile(r"[0-9a-f]{64}\Z")

_P4_CODES = {
    "P4_ACTIVATE_HTTP_200": "ACTIVATE_OK",
    "P4_REVISION_HTTP_200": "REVISION_READY",
    "P4_REVISION_HTTP_204": "REVISION_EMPTY",
    "P4_REVISION_CURRENT_SOURCE_HOLD": "CURRENT_SOURCE_HOLD",
    "P4_ACTIVATE_REJECTED_P3_READY_NO_CURRENT_ACCEPTED_SOURCE": "SOURCE_NOT_ACCEPTED",
    "P4_ACTIVATE_REJECTED_P4_ROLLING_CURRENT_TV_UNAVAILABLE": "TV_UNAVAILABLE",
    "P4_ACTIVATE_REJECTED_P4_ACTIVATE_AUTH_INVALID": "ACTIVATE_AUTH_FAILED",
    "P4_ACTIVATE_REJECTED_P4_ACTIVATE_REPLAY": "ACTIVATE_REPLAY",
}
_R2_CODES = frozenset({
    "FLOW_UNBOUND", "MEDIA_KEY_MISMATCH", "EN_INDEX_NOT_READY",
    "P2_CHECKPOINT_PENDING", "P2_CHECKPOINT_READY", "ROLLING_FEED_MISSING",
})
_P4_LINE = re.compile(
    r"OWNER_FULL_TRACE 'P4_DELIVERY_STATUS' \{'code': '([A-Z0-9_]+)'\}")
_R2_LINE = re.compile(
    r"OWNER_FULL_TRACE 'P4_ROLLING_STATUS' \{'code': '([A-Z0-9_]+)'\}")


def _p2_commits(owner_root: Path, now: int) -> dict[str, int | str]:
    result: dict[str, int | str] = {
        "committed_prefix": -1, "inflight_age_seconds": -1,
        "final_present": "NOT_OBSERVED",
    }
    state = owner_root.parent / "P2" / "auto-lean120-state"
    try:
        if _is_link(state) or not state.is_dir():
            return result
        jobs = []
        for folder in state.iterdir():
            if _is_link(folder) or not folder.is_dir() or not _JOB.fullmatch(folder.name):
                return result
            inflights = [p for p in folder.glob("batch-*.inflight") if p.is_file()]
            if inflights:
                jobs.append((folder, inflights))
        if len(jobs) != 1 or len(jobs[0][1]) != 1:
            return result
        folder, markers = jobs[0]
        if _is_link(markers[0]):
            return result
        versions = set()
        for file in folder.glob("batch-*.json"):
            if _is_link(file) or not file.is_file():
                return result
            match = _CHECKPOINT.fullmatch(file.name)
            if not match:
                return result
            versions.add(int(match.group(1)))
            if len(versions) > 10000:
                return result
        prefix = 0
        while prefix + 1 in versions:
            prefix += 1
        if len(versions) != prefix:
            return result
        age = now - int(markers[0].stat().st_mtime)
        result.update({
            "committed_prefix": prefix,
            "inflight_age_seconds": age if 0 <= age <= 86400 else -1,
            "final_present": "YES" if any(
                (folder / ("vi-final." + fmt)).is_file()
                for fmt in ("srt", "vtt")) else "NO",
        })
    except (OSError, ValueError, RecursionError):
        pass
    return result


def _p4_from_private_log(owner_root: Path) -> dict[str, int | str]:
    result: dict[str, int | str] = {
        "status": "NOT_OBSERVED", "dispatches": 0,
        "activate_ok": 0, "activate_rejected": 0,
        "revision_ready": 0, "revision_empty": 0,
        "revision_hold": 0, "source_not_accepted": 0,
        "rolling_status": "NOT_OBSERVED", "last_delivery": "NOT_OBSERVED",
    }
    path = owner_root / "diagnostics" / "owner-full.log"
    try:
        if _is_link(owner_root) or _is_link(path) or not path.is_file():
            return result
        size = path.stat().st_size
        if size <= 0:
            return result
        with path.open("rb") as stream:
            stream.seek(max(0, size - _LOG_TAIL))
            raw = stream.read(_LOG_TAIL)
        # Drop the first partial line if a large logfile was read from tail.
        if size > _LOG_TAIL:
            raw = raw.partition(b"\n")[2]
        lines = raw.splitlines()
        starts = [(i, m) for i, line in enumerate(lines)
                  if (m := _START.fullmatch(line)) is not None]
        # A previous Owner's log must never be mistaken for this process.
        health = owner_root / "agent-health.json"
        if _is_link(health) or not health.is_file() or health.stat().st_size > 512:
            return result
        pid = json.loads(health.read_text(encoding="utf-8")).get("pid")
        if type(pid) is not int or pid <= 0:
            return result
        if starts:
            begin, marker = starts[-1]
            if pid != int(marker.group(1)):
                return result
            current = lines[begin + 1:]
        elif size > _LOG_TAIL and pid == os.getpid():
            # The process header has aged out of the bounded tail after a
            # long film. Only the *same live Owner process* may trust the
            # tail; a stand-alone diagnostic must fail closed instead.
            current = lines
        else:
            return result
        last_request = max((i for i, line in enumerate(current)
                            if b"OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'" in line
                            and b"'status': 'DISPATCH'" in line), default=-1)
        if last_request < 0:
            result["status"] = "NO_REQUEST_IN_TAIL"
            return result
        result["status"] = "CURRENT_REQUEST_OBSERVED"
        result["dispatches"] = sum(
            1 for line in current if b"OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'" in line
            and b"'status': 'DISPATCH'" in line)
        for raw_line in current[last_request + 1:]:
            # Lines are used ONLY for exact literal matching. Never export text.
            line = raw_line.decode("utf-8", "replace")
            p4 = _P4_LINE.search(line)
            if p4:
                code = p4.group(1)
                category = _P4_CODES.get(code, "OTHER_REJECTED" if
                                         code.startswith("P4_ACTIVATE_REJECTED_")
                                         else "OTHER_DELIVERY")
                result["last_delivery"] = category
                if category == "ACTIVATE_OK":
                    result["activate_ok"] += 1
                elif category == "REVISION_READY":
                    result["revision_ready"] += 1
                elif category == "REVISION_EMPTY":
                    result["revision_empty"] += 1
                elif category == "CURRENT_SOURCE_HOLD":
                    result["revision_hold"] += 1
                elif code.startswith("P4_ACTIVATE_REJECTED_"):
                    result["activate_rejected"] += 1
                    if category == "SOURCE_NOT_ACCEPTED":
                        result["source_not_accepted"] += 1
            r2 = _R2_LINE.search(line)
            if r2 and r2.group(1) in _R2_CODES:
                result["rolling_status"] = r2.group(1)
        # No identity, dialogue, key or URL is ever included in this result.
    except (OSError, ValueError, UnicodeError, RecursionError, TypeError):
        return {**result, "status": "READ_UNAVAILABLE"}
    return result


def build_snapshot_v4(*, owner_root: Path, now: int | None = None) -> dict:
    tick = int(time.time()) if now is None else now
    doc = build_snapshot_v3(owner_root=owner_root, now=tick)
    doc["schema"] = SCHEMA
    doc["p2"].update(_p2_commits(owner_root, tick))
    doc["p4"] = _p4_from_private_log(owner_root)
    return doc


def publish_owner_snapshot_v4(*, owner_root: Path,
                              shared_dir: Path | None = None) -> bool:
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
    raw = json.dumps(build_snapshot_v4(owner_root=owner_root), sort_keys=True,
                     separators=(",", ":"), ensure_ascii=True).encode("ascii")
    if len(raw) > _MAX_BYTES:
        raise ValueError("HOSTOPS_V4_SNAPSHOT_TOO_LARGE")
    temporary = shared_dir / ("owner-snapshot-" + secrets.token_hex(8) + ".tmp")
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return True

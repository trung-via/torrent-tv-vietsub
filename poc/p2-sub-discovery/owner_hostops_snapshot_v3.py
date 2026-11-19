"""Additive Owner-only event counts over the immutable V2 HostOps writer.

The already enrolled V2 one-shot task and its exact SHA pin remain unchanged.
Only a newly staged Owner runtime invokes this V3 writer. A NETWORK_SERVICE
reader sees aggregate numbers, never filenames, IDs, payloads or claim data.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import secrets

from owner_hostops_snapshot import (
    _DIR_PARTS, _FILENAME, _MAX_BYTES, _is_link, build_snapshot,
)

SCHEMA = "TTV-HOSTOPS-OWNER-SNAPSHOT-V3"
_EVENT_CLASSES = {
    "event-*.blocked": "blocked_events",
    "event-*.review": "review_events",
    "preprovider-retry-*.json": "deferred_events",
}


def _safe_event_counts(owner_root: Path) -> dict[str, int]:
    counts = {name: -1 for name in _EVENT_CLASSES.values()}
    inbox = owner_root / "inbox"
    try:
        if _is_link(owner_root) or _is_link(inbox):
            return counts
        if not inbox.exists():
            return counts
        if not inbox.is_dir():
            return counts
        for pattern, name in _EVENT_CLASSES.items():
            count = 0
            for file in inbox.glob(pattern):
                if _is_link(file):
                    return {key: -1 for key in counts}
                if file.is_file():
                    count += 1
                if count > 10000:
                    return {key: -1 for key in counts}
            counts[name] = count
    except (OSError, ValueError):
        return {key: -1 for key in counts}
    return counts


def build_snapshot_v3(*, owner_root: Path, now: int | None = None) -> dict:
    receipt = build_snapshot(owner_root=owner_root, now=now)
    if receipt["schema"] != "TTV-HOSTOPS-OWNER-SNAPSHOT-V2":
        raise ValueError("HOSTOPS_V3_LEGACY_SNAPSHOT_UNEXPECTED")
    receipt["schema"] = SCHEMA
    receipt["p2"].update(_safe_event_counts(owner_root))
    return receipt


def publish_owner_snapshot_v3(*, owner_root: Path,
                              shared_dir: Path | None = None) -> bool:
    """Publish only to the existing enrolled spool. No task/ACL mutations."""
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
    raw = json.dumps(build_snapshot_v3(owner_root=owner_root),
                     sort_keys=True, separators=(",", ":"),
                     ensure_ascii=True).encode("ascii")
    if len(raw) > _MAX_BYTES:
        raise ValueError("HOSTOPS_V3_SNAPSHOT_TOO_LARGE")
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

"""Owner-session event queue for automatic Vietsub; no GitHub payload execution.

SECURITY BOUNDARY:
  - Only owner-local OMP/TorrServer integration writes selected-media events
    inside LOCALAPPDATA; filename never appears in GitHub or ProgramData.
  - GitHub runner may write only an inert WAKE marker to a separate,
    owner-provisioned ProgramData spool. It cannot submit a movie, script,
    model prompt, provider key or command through this bridge.
  - The owner process consumes private events and invokes the existing
    AutomaticVietsubFlow; secrets stay in the logged-in owner's process.
  - An exclusive claim persists on interruption: fail closed instead of
    potentially repeating quota-bearing OpenSubtitles/Gemini calls.

This module can be imported by OMP's trusted local selected-media adapter;
it does not itself pretend to discover currently playing TV media.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import secrets
import sys
import time
from typing import Callable, Protocol

_SCHEMA = "TTV-OWNER-VIDEO-EVENT-V1"
_BOUND_SCHEMA = "TTV-OWNER-VIDEO-EVENT-V2"
_ID = re.compile(r"[a-f0-9]{32}\Z")
_FINGERPRINT = re.compile(r"[0-9a-f]{64}\Z")
_MAX_EVENT_BYTES = 768
_MAX_EVENTS_PER_POLL = 3
_HEALTH_STATES = frozenset({"STARTING", "READY", "STOPPED", "BLOCKED"})
_HEALTH_SCHEMA = "TTV-OWNER-AGENT-HEALTH-V1"


@dataclass(frozen=True)
class LocalEvent:
    event_id: str
    selected_video_filename: str
    source_fingerprint: str | None = None


class _Processor(Protocol):
    def selected_media(self, filename: str) -> object: ...


def _private_dir(root: Path) -> Path:
    if not isinstance(root, Path) or not root.is_absolute() or root.is_symlink():
        raise ValueError("OWNER_BRIDGE_PRIVATE_ROOT_INVALID")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    folder = root / "inbox"
    if folder.is_symlink():
        raise ValueError("OWNER_BRIDGE_PRIVATE_INBOX_SYMLINK")
    folder.mkdir(mode=0o700, exist_ok=True)
    return folder


def enqueue_selected_media(
    video_filename: str, *, owner_root: Path,
    source_fingerprint: str | None = None,
) -> str:
    """Trusted OMP-local callback. Never invoke from untrusted runner inputs."""
    if (not isinstance(video_filename, str) or not video_filename.strip()
            or len(video_filename) > 255 or "/" in video_filename
            or "\\" in video_filename
            or any(ord(ch) < 32 for ch in video_filename)):
        raise ValueError("OWNER_BRIDGE_BAD_VIDEO_NAME")
    if source_fingerprint is not None and (
            not isinstance(source_fingerprint, str)
            or _FINGERPRINT.fullmatch(source_fingerprint) is None):
        raise ValueError("OWNER_BRIDGE_SOURCE_FINGERPRINT_INVALID")
    inbox = _private_dir(owner_root)
    event_id = secrets.token_hex(16)
    payload = {
        "schema": _BOUND_SCHEMA if source_fingerprint is not None else _SCHEMA,
        "event_id": event_id,
        "selected_video_filename": video_filename,
    }
    if source_fingerprint is not None:
        payload["source_fingerprint"] = source_fingerprint
    body = json.dumps(
        payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(body) > _MAX_EVENT_BYTES:
        raise ValueError("OWNER_BRIDGE_EVENT_TOO_LARGE")
    # Atomic create: no queue overwrite or untrusted GitHub-provided path.
    filepath = inbox / ("event-" + event_id + ".json")
    fd = os.open(filepath, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(body)
        stream.flush()
        os.fsync(stream.fileno())
    return event_id


def _parse_event(path: Path) -> LocalEvent:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > _MAX_EVENT_BYTES:
        raise ValueError("OWNER_BRIDGE_EVENT_UNTRUSTED")
    try:
        event = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError):
        raise ValueError("OWNER_BRIDGE_EVENT_CORRUPT") from None
    expected = {"schema", "event_id", "selected_video_filename"}
    if not isinstance(event, dict):
        raise ValueError("OWNER_BRIDGE_EVENT_BAD_SCHEMA")
    version = event.get("schema")
    if version == _BOUND_SCHEMA:
        expected.add("source_fingerprint")
    elif version != _SCHEMA:
        raise ValueError("OWNER_BRIDGE_EVENT_BAD_SCHEMA")
    if set(event) != expected:
        raise ValueError("OWNER_BRIDGE_EVENT_BAD_SCHEMA")
    fp = event.get("source_fingerprint")
    if version == _BOUND_SCHEMA and (
            not isinstance(fp, str) or _FINGERPRINT.fullmatch(fp) is None):
        raise ValueError("OWNER_BRIDGE_SOURCE_FINGERPRINT_INVALID")
    video = event["selected_video_filename"]
    expected_id = path.name.removeprefix("event-").removesuffix(".json")
    if (not isinstance(event["event_id"], str)
            or not _ID.fullmatch(event["event_id"])
            or expected_id != event["event_id"]
            or not isinstance(video, str)
            or not video.strip()
            or len(video) > 255
            or "/" in video or "\\" in video
            or any(ord(ch) < 32 for ch in video)):
        raise ValueError("OWNER_BRIDGE_EVENT_INVALID")
    return LocalEvent(event["event_id"], video, fp)


def poll_private_events(
    *, owner_root: Path, processor: _Processor, emit: Callable[[str], object] = print,
    max_events: int = _MAX_EVENTS_PER_POLL,
) -> int:
    """Process only owner-private events, at most once automatically.

    A .claim is created exclusively BEFORE the first provider call. If the
    process crashes, the claim persists. A supervisor cannot silently repeat
    an uncertain API operation; exact owner reconciliation is required.
    """
    if (type(max_events) is not int or not 1 <= max_events <= _MAX_EVENTS_PER_POLL
            or not callable(getattr(processor, "selected_media", None))):
        raise ValueError("OWNER_BRIDGE_BAD_PROCESSOR")
    inbox = _private_dir(owner_root)
    processed = 0
    for path in sorted(inbox.glob("event-*.json")):
        if processed >= max_events:
            break
        # Never follow symlinks, including on malformed events.
        if path.is_symlink():
            emit("OWNER_BRIDGE_EVENT_REJECTED_SYMLINK")
            continue
        try:
            event = _parse_event(path)
        except ValueError:
            emit("OWNER_BRIDGE_EVENT_REJECTED")
            continue
        claim = inbox / ("claim-" + event.event_id)
        try:
            fd = os.open(claim, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            # Prior run (possibly interrupted) owns this work, no replay.
            continue
        with os.fdopen(fd, "wb") as stream:
            stream.write(b"CLAIMED_DO_NOT_AUTO_REPLAY\n")
        processed += 1
        try:
            if event.source_fingerprint is not None:
                result = processor.selected_media(
                    event.selected_video_filename,
                    source_fingerprint=event.source_fingerprint)
            else:
                # Preserve compatibility with legacy local-only D2 events.
                result = processor.selected_media(event.selected_video_filename)
            status = getattr(result, "status", None)
            if status not in ("VI_READY", "VIETSUB_READY", "REVIEW_REQUIRED"):
                raise ValueError("OWNER_BRIDGE_INVALID_RESULT")
            suffix = ".done" if status != "REVIEW_REQUIRED" else ".review"
            os.replace(path, inbox / ("event-" + event.event_id + suffix))
            emit("OWNER_BRIDGE_EVENT_" + (
                "COMPLETE" if suffix == ".done" else "NEEDS_REVIEW"))
        except Exception:
            # Error text may include private file paths/API material; do not
            # print it, or attempt a second quota-bearing provider request.
            os.replace(path, inbox / ("event-" + event.event_id + ".blocked"))
            emit("OWNER_BRIDGE_EVENT_BLOCKED_NO_RETRY")
    return processed


def write_owner_agent_health(*, owner_root: Path, state: str) -> None:
    """Owner-private heartbeat, no API keys, dialogue, media IDs or paths.

    A READY line only means the owner Python loop is alive. It cannot prove
    model availability, signed TV pairing, movie identity or TV subtitles.
    Owner-local observers must check freshness (e.g. within 30 seconds).
    """
    if state not in _HEALTH_STATES or not isinstance(state, str):
        raise ValueError("OWNER_BRIDGE_HEALTH_STATE_INVALID")
    root = _private_dir(owner_root).parent
    target = root / "agent-health.json"
    if target.is_symlink():
        raise ValueError("OWNER_BRIDGE_HEALTH_SYMLINK")
    doc = {
        "schema": _HEALTH_SCHEMA,
        "state": state,
        "observed_utc_epoch": int(time.time()),
        "pid": os.getpid(),
    }
    contents = json.dumps(doc, separators=(",", ":"), sort_keys=True).encode()
    temporary = root / ("agent-health-" + secrets.token_hex(8) + ".tmp")
    try:
        fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def read_owner_agent_health(*, owner_root: Path, now: float | None = None
                            ) -> str:
    """Owner-only read-only status: READY / STALE / BLOCKED / NOT_INSTALLED.

    This function never reads keys, cache entries or subtitle text.
    """
    if (not isinstance(owner_root, Path) or not owner_root.is_absolute()
            or owner_root.is_symlink()):
        raise ValueError("OWNER_BRIDGE_PRIVATE_ROOT_INVALID")
    path = owner_root / "agent-health.json"
    if not path.exists():
        return "NOT_INSTALLED"
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 512:
        return "INVALID"
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError):
        return "INVALID"
    if (not isinstance(doc, dict) or set(doc) != {
            "schema", "state", "observed_utc_epoch", "pid"}
            or doc["schema"] != _HEALTH_SCHEMA
            or not isinstance(doc["state"], str)
            or doc["state"] not in _HEALTH_STATES
            or type(doc["observed_utc_epoch"]) is not int
            or type(doc["pid"]) is not int):
        return "INVALID"
    if doc["state"] != "READY":
        return doc["state"]
    checked_at = time.time() if now is None else now
    if (not isinstance(checked_at, (int, float))
            or checked_at < doc["observed_utc_epoch"]
            or checked_at - doc["observed_utc_epoch"] > 30):
        return "STALE"
    return "READY"


def consume_inert_runner_wakes(*, shared_wake_root: Path | None = None) -> int:
    """Read only a fixed no-payload wake marker, NEVER a runner command.

    The owner agent already polls its private inbox; this is supplemental
    evidence of a runner signal and intentionally grants the runner no power
    to select a video, access secrets or choose script/command arguments.
    """
    if shared_wake_root is None:
        programdata = os.environ.get("PROGRAMDATA")
        if not programdata:
            return 0
        shared_wake_root = Path(programdata) / "TorrentTVVietsub" / "OwnerBridge" / "Wake"
    if (shared_wake_root.is_symlink() or not shared_wake_root.is_dir()):
        return 0
    consumed = 0
    for item in sorted(shared_wake_root.glob("wake-*.txt"))[:32]:
        if item.is_symlink() or not item.is_file():
            continue
        try:
            if item.stat().st_size != len(b"WAKE_V1\n"):
                continue
            if item.read_bytes() != b"WAKE_V1\n":
                continue
            item.unlink()
            consumed += 1
        except OSError:
            continue
    return consumed


@contextmanager
def _owner_process_lock(private_root: Path):
    """OS-held singleton: RELEASED by Windows/kernel when process exits.

    Unlike permanent O_EXCL PID markers, a crashed agent cannot strand a
    stale lock that forces Human to delete it on every subsequent logon.
    The existing per-event and provider .inflight claims remain persistent
    and fail-closed, even after this *process* lock is released.
    """
    root = _private_dir(private_root).parent
    lock = root / "owner-agent-active.lock"
    if lock.is_symlink():
        raise ValueError("OWNER_BRIDGE_AGENT_LOCK_SYMLINK")
    try:
        fd = os.open(lock, os.O_RDWR | os.O_CREAT, 0o600)
    except OSError:
        raise ValueError("OWNER_BRIDGE_AGENT_LOCK_OPEN_FAILED") from None
    handle = os.fdopen(fd, "r+b", buffering=0)
    try:
        if os.name == "nt":
            import msvcrt
            # Windows msvcrt.locking locks a byte at the file cursor.
            if handle.read(1) == b"":
                handle.write(b"\x00")
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        raise ValueError("OWNER_BRIDGE_ALREADY_RUNNING") from None
    try:
        yield
    finally:
        try:
            if os.name == "nt":
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        finally:
            handle.close()


def run_owner_agent(*, private_root: Path, cache_root: Path, state_root: Path,
                    interval_seconds: float = 2.0,
                    emit: Callable[[str], object] = print) -> None:
    if not 0.5 <= interval_seconds <= 60:
        raise ValueError("OWNER_BRIDGE_BAD_POLL_INTERVAL")
    if (os.environ.get("CI", "").lower() == "true"
            or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"):
        raise ValueError("OWNER_BRIDGE_NO_OWNER_RUNTIME_IN_CI")
    # OS releases the process mutex on Windows logoff/crash; durable
    # D2/Gemini one-post/inflight claims are never automatically deleted.
    with _owner_process_lock(private_root):
        write_owner_agent_health(owner_root=private_root, state="STARTING")
        try:
            from automatic_vietsub_flow import build_owner_auto_flow
            # Never call Gemini at startup: VI-only work remains usable.
            flow = build_owner_auto_flow(
                enabled=True, cache_root=cache_root, state_root=state_root)
        except Exception:
            write_owner_agent_health(owner_root=private_root, state="BLOCKED")
            raise
        emit("OWNER_BRIDGE_STARTED")
        last_health = 0.0
        try:
            while True:
                if time.monotonic() - last_health > 10.0:
                    write_owner_agent_health(owner_root=private_root,
                                             state="READY")
                    last_health = time.monotonic()
                consume_inert_runner_wakes()
                poll_private_events(owner_root=private_root,
                                    processor=flow, emit=emit)
                time.sleep(interval_seconds)
        finally:
            write_owner_agent_health(owner_root=private_root,
                                     state="STOPPED")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Logged-in owner-only automatic Vietsub event consumer")
    parser.add_argument("--owner-root", required=True)
    parser.add_argument("--cache-root", required=True)
    parser.add_argument("--state-root", required=True)
    args = parser.parse_args(argv)
    try:
        run_owner_agent(
            private_root=Path(args.owner_root),
            cache_root=Path(args.cache_root),
            state_root=Path(args.state_root),
        )
    except (ValueError, OSError):
        # Fixed-only output, never leak any provider exception to GitHub logs.
        print("OWNER_BRIDGE_STARTUP_BLOCKED_PRIVATE_REVIEW")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

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
_ID = re.compile(r"[a-f0-9]{32}\Z")
_MAX_EVENT_BYTES = 768
_MAX_EVENTS_PER_POLL = 3


@dataclass(frozen=True)
class LocalEvent:
    event_id: str
    selected_video_filename: str


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


def enqueue_selected_media(video_filename: str, *, owner_root: Path) -> str:
    """Trusted OMP-local callback. Never invoke from untrusted runner inputs."""
    if (not isinstance(video_filename, str) or not video_filename.strip()
            or len(video_filename) > 255 or "/" in video_filename
            or "\\" in video_filename
            or any(ord(ch) < 32 for ch in video_filename)):
        raise ValueError("OWNER_BRIDGE_BAD_VIDEO_NAME")
    inbox = _private_dir(owner_root)
    event_id = secrets.token_hex(16)
    body = json.dumps({
        "schema": _SCHEMA,
        "event_id": event_id,
        "selected_video_filename": video_filename,
    }, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
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
    if not isinstance(event, dict) or set(event) != {
        "schema", "event_id", "selected_video_filename",
    } or event.get("schema") != _SCHEMA:
        raise ValueError("OWNER_BRIDGE_EVENT_BAD_SCHEMA")
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
    return LocalEvent(event["event_id"], video)


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


def run_owner_agent(*, private_root: Path, cache_root: Path, state_root: Path,
                    interval_seconds: float = 2.0,
                    emit: Callable[[str], object] = print) -> None:
    if not 0.5 <= interval_seconds <= 60:
        raise ValueError("OWNER_BRIDGE_BAD_POLL_INTERVAL")
    if (os.environ.get("CI", "").lower() == "true"
            or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"):
        raise ValueError("OWNER_BRIDGE_NO_OWNER_RUNTIME_IN_CI")
    # A process-level lock prevents duplicate startup tasks from running
    # simultaneously. Last forced interruption requires owner reconciliation.
    root = _private_dir(private_root).parent
    lock = root / "owner-agent-active.lock"
    try:
        fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise ValueError("OWNER_BRIDGE_ALREADY_RUNNING_OR_UNCERTAIN") from None
    with os.fdopen(fd, "wb") as stream:
        stream.write(str(os.getpid()).encode("ascii"))
    try:
        from automatic_vietsub_flow import build_owner_auto_flow
        flow = build_owner_auto_flow(
            enabled=True, cache_root=cache_root, state_root=state_root)
        emit("OWNER_BRIDGE_STARTED")
        while True:
            # Runner wake contains no user data or command; private OMP-local
            # events remain the only accepted source of actual film work.
            consume_inert_runner_wakes()
            poll_private_events(owner_root=private_root, processor=flow, emit=emit)
            time.sleep(interval_seconds)
    finally:
        # No lock removal while a worker is still running.
        lock.unlink(missing_ok=True)


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

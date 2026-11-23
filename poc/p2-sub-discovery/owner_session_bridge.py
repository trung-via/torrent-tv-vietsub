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
from concurrent.futures import Future, ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sys
import threading
import time
import traceback
from typing import Callable, Protocol

_SCHEMA = "TTV-OWNER-VIDEO-EVENT-V1"
_BOUND_SCHEMA = "TTV-OWNER-VIDEO-EVENT-V2"
_SESSION_SCHEMA = "TTV-OWNER-VIDEO-EVENT-V3"
_BACKGROUND_SCHEMA = "TTV-OWNER-VIDEO-EVENT-V4"
_SESSION_ID = re.compile(r"[A-Za-z0-9_-]{1,128}\Z")
_ID = re.compile(r"[a-f0-9]{32}\Z")
_FINGERPRINT = re.compile(r"[0-9a-f]{64}\Z")
_MAX_EVENT_BYTES = 768
_MAX_EVENTS_PER_POLL = 3
_HEALTH_STATES = frozenset({"STARTING", "READY", "STOPPED", "BLOCKED"})
_HEALTH_SCHEMA = "TTV-OWNER-AGENT-HEALTH-V1"
_HEALTH_TICK_SECONDS = 3.0
_RETRY_SCHEMA = "TTV-OWNER-PREPROVIDER-RETRY-V1"
_RETRY_DELAYS = (5, 15, 30)
_FULL_LOG = None
_FULL_LOG_LOCK = threading.RLock()
_ENQUEUE_LOCK = threading.RLock()


class _OwnerLogTee:
    """Preserve the Owner console while appending its *unmodified* text."""

    def __init__(self, original, log):
        self.original = original
        self.log = log

    def write(self, data):
        with _FULL_LOG_LOCK:
            result = self.original.write(data)
            self.log.write(data)
            self.log.flush()
            return result

    def flush(self):
        with _FULL_LOG_LOCK:
            self.original.flush()
            self.log.flush()

    def __getattr__(self, name):
        return getattr(self.original, name)


def install_owner_full_diagnostics(owner_root: Path) -> Path:
    """Owner-local full stdout/stderr/traceback, with no redaction or upload.

    This is run ONCE in the interactive Owner process, never by HostOps CI.
    The same file captures P3 HTTPS server output, P2 stages and P4 errors.
    """
    global _FULL_LOG
    if (not isinstance(owner_root, Path) or not owner_root.is_absolute()
            or owner_root.is_symlink() or not owner_root.is_dir()):
        raise ValueError("OWNER_FULL_DIAGNOSTICS_OWNER_ROOT_REQUIRED")
    directory = owner_root / "diagnostics"
    if directory.is_symlink():
        raise ValueError("OWNER_FULL_DIAGNOSTICS_SYMLINK")
    directory.mkdir(mode=0o700, exist_ok=True)
    path = directory / "owner-full.log"
    if path.is_symlink():
        raise ValueError("OWNER_FULL_DIAGNOSTICS_SYMLINK")
    with _FULL_LOG_LOCK:
        if _FULL_LOG is not None:
            if Path(_FULL_LOG.name) != path:
                raise ValueError("OWNER_FULL_DIAGNOSTICS_ALREADY_ACTIVE")
            return path
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        stream = os.fdopen(fd, "a", encoding="utf-8", buffering=1)
        _FULL_LOG = stream
        sys.stdout = _OwnerLogTee(sys.stdout, stream)
        sys.stderr = _OwnerLogTee(sys.stderr, stream)
        stream.write("\nOWNER_FULL_DIAGNOSTICS_STARTED pid=" + str(os.getpid())
                     + " epoch=" + str(int(time.time())) + "\n")
        stream.flush()
    return path


def owner_full_trace(stage: str, *, error: BaseException | None = None,
                     **context: object) -> None:
    """Unfiltered Owner-only stage/context and complete traceback (if any)."""
    if _FULL_LOG is None:
        return
    with _FULL_LOG_LOCK:
        print("OWNER_FULL_TRACE", repr(stage), repr(context), file=sys.stderr)
        if error is not None:
            traceback.print_exception(type(error), error, error.__traceback__,
                                      file=sys.stderr)
# Only literal, source-owned error codes may appear in the Owner console.
# Exception text can contain a private path, subtitle or provider credential.
_SAFE_BLOCK_REASONS = frozenset({
    "V3_EPISODE_METADATA_CONFLICT", "V3_SESSION_AND_FINGERPRINT_REQUIRED",
    "V3_CURRENT_SOURCE_MISMATCH", "V3_TV_SELECTION_CHANGED",
    "RESOLVER_TRUSTED_SNAPSHOT_REQUIRED", "RESOLVER_SERVER_PATH_INVALID",
    "RESOLVER_NOT_ACTIVE_AUTHENTICATED_PLAY", "RESOLVER_TV_SESSION_MISMATCH",
    "RESOLVER_OWNER_OR_VIEWER_GATE_BLOCKED",
    "RESOLVER_SELECTED_MEDIA_MISMATCH",
    "RESOLVER_SOURCE_FINGERPRINT_MISMATCH",
    "RESOLVER_PLAYBACK_READER_UNAVAILABLE",
    "RESOLVER_TORRSERVER_READER_UNAVAILABLE",
    "RESOLVER_SERVER_FILE_MISMATCH", "RESOLVER_OWNER_MAPPING_UNAVAILABLE",
    "RESOLVER_OWNER_MAPPING_INVALID", "RESOLVER_OWNER_MEDIA_ROOT_INVALID",
    "RESOLVER_UNTRUSTED_PRIVATE_PATH",
    "RESOLVER_LOCAL_VIDEO_NAME_MISMATCH",
    "RESOLVER_LOCAL_VIDEO_SIZE_MISMATCH", "RESOLVER_SIDECAR_NAME_MISMATCH",
    "RESOLVER_SIDECAR_DIRECTORY_MISMATCH",
    "RESOLVER_AMBIGUOUS_LOCAL_EN", "RESOLVER_SIDECAR_SYMLINK_REFUSED",
    "P4_ROLLING_TV_SESSION_CHANGED", "P4_ROLLING_TORRSERVER_FILE_CHANGED",
    "P4_ROLLING_SELECTED_MEDIA_CHANGED",
    "AUTO_VIETSUB_PERMISSIONS_NOT_ENABLED", "AUTO_VIETSUB_INVALID_MEDIA_NAME",
    "AUTO_V3_VERIFIED_MEDIA_REQUIRED", "AUTO_V3_SOURCE_FINGERPRINT_MISMATCH",
    "AUTO_V3_LOCAL_SOURCE_IDENTITY_MISMATCH",
    "AUTO_VIETSUB_INCOMPLETE_TRANSLATION",
    "OWNER_BRIDGE_INVALID_RESULT", "BAD_SUBTITLE_TIMELINE",
    "AUTO_SOURCE_CACHE_INDEX_INVALID",
    "AUTO_SOURCE_CACHE_DIGEST_MISMATCH", "EN_DOWNLOAD_ALREADY_ATTEMPTED",
    "AGY_TRANSLATION_TEXT_EMPTY", "AGY_TRANSLATION_TEXT_TOO_LONG",
    "AGY_TRANSLATION_TEXT_NUL", "AGY_TRANSLATION_TEXT_UTF8_INVALID",
    "AGY_TRANSLATION_TEXT_MARKUP_UNSUPPORTED",
    "PLAIN_UTF8_TRANSLATION_REQUIRED",
    # OpenSubtitles 406 may mean a stale file ID OR an exhausted allowance.
    # Both are post-attempt holds; an error label is never retry permission.
    "API_DOWNLOAD_INVALID_FILE_ID_406", "API_DOWNLOAD_QUOTA_406",
    "API_DOWNLOAD_REJECTED_406", "API_HTTP_406",
    # These are explicit P2 no-replay gates, not an unidentified exception.
    # In particular, an acknowledged unknown-effect batch must remain
    # quarantined; exposing the fixed reason never authorizes a retry.
    "AUTO_LEAN120_ABANDONED_JOB_HOLD",
    "AUTO_LEAN120_PRIOR_PROVIDER_INFLIGHT_HOLD",
    "AUTO_LEAN120_UNCERTAIN_BATCH_MANUAL_RECONCILE",
    # Brain source/receipt errors stay distinguishable from model effects.
    "BRAIN_EN_NOT_STAGED", "BRAIN_EN_STAGE_CONFLICT",
    "BRAIN_EN_CACHE_CONFLICT", "BRAIN_EN_RELEASE_MISMATCH",
    "BRAIN_EN_SRT_CHANGED", "BRAIN_EN_SRT_QA_FAILED",
    "BRAIN_EN_RECEIPT_INVALID", "BRAIN_EN_STAGE_UNTRUSTED",
    "BRAIN_EN_SRT_SIZE_INVALID", "BRAIN_EN_INPUT_UNREADABLE",
})


def _safe_block_reason(error: Exception) -> str:
    """One actionable allowlisted reason; never echo arbitrary exception text."""
    if len(error.args) == 1 and type(error.args[0]) is str:
        reason = error.args[0]
        if reason in _SAFE_BLOCK_REASONS:
            return reason
    return "UNCLASSIFIED"


class PreProviderTransient(RuntimeError):
    """Only a verified V3 preflight may raise this before ANY provider call.

    Do not use this exception for discovery, download, translation, the P4
    ready callback, or any operation with an uncertain external effect.
    """

    _REASONS = frozenset({
        "V3_TV_READER_UNAVAILABLE", "V3_CURRENT_MEDIA_UNAVAILABLE",
        "V3_SERVER_READER_UNAVAILABLE", "V3_TV_REFRESH_UNAVAILABLE",
        "AGY_OWNER_PREFLIGHT_UNAVAILABLE",
    })

    def __init__(self, reason: str):
        if reason not in self._REASONS:
            raise ValueError("OWNER_BRIDGE_PREPROVIDER_REASON_INVALID")
        super().__init__(reason)


def _retry_file(inbox: Path, event_id: str) -> Path:
    return inbox / ("preprovider-retry-" + event_id + ".json")


def _retry_state(file: Path) -> tuple[int, int]:
    if not file.exists() and not file.is_symlink():
        return 0, 0
    if file.is_symlink() or not file.is_file() or file.stat().st_size > 256:
        raise ValueError("OWNER_BRIDGE_RETRY_STATE_INVALID")
    try:
        state = json.loads(file.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        raise ValueError("OWNER_BRIDGE_RETRY_STATE_INVALID") from None
    if (not isinstance(state, dict)
            or set(state) != {"schema", "attempts", "not_before_epoch"}
            or state["schema"] != _RETRY_SCHEMA
            or type(state["attempts"]) is not int
            or not 1 <= state["attempts"] <= len(_RETRY_DELAYS)
            or type(state["not_before_epoch"]) is not int
            or state["not_before_epoch"] < 0):
        raise ValueError("OWNER_BRIDGE_RETRY_STATE_INVALID")
    return state["attempts"], state["not_before_epoch"]


def _record_preprovider_retry(file: Path, attempts: int, now: int) -> None:
    """Durably record a bounded retry BEFORE releasing the provider claim."""
    record = {"schema": _RETRY_SCHEMA, "attempts": attempts,
              "not_before_epoch": now + _RETRY_DELAYS[attempts - 1]}
    temporary = file.parent / ("preprovider-retry-" + secrets.token_hex(8) + ".tmp")
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(json.dumps(record, sort_keys=True,
                                    separators=(",", ":")).encode("ascii"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, file)
    finally:
        temporary.unlink(missing_ok=True)


def _remove_finished_retry(file: Path) -> None:
    """Best effort: the terminal event + preserved claim are authoritative."""
    try:
        file.unlink(missing_ok=True)
    except OSError:
        pass


@dataclass(frozen=True)
class LocalEvent:
    event_id: str
    selected_video_filename: str
    source_fingerprint: str | None = None
    tv_session_id: str | None = None
    authorized_selection: dict[str, object] | None = None


def _authorized_selection(value: object, fingerprint: str | None,
                          session: str | None) -> dict[str, object]:
    """Persist exact Owner-verified coordinates at the signed viewer tap.

    This is an owner-private job snapshot, never a TV/P4 attestation. It
    permits translation after the TV closes; delivery still checks live TV.
    """
    if not isinstance(value, dict) or set(value) != {
            "server_id", "torrent_hash", "file_index"}:
        raise ValueError("OWNER_BRIDGE_BACKGROUND_SELECTION_INVALID")
    server, torrent, index = (value["server_id"], value["torrent_hash"],
                              value["file_index"])
    if (not isinstance(server, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", server)
            or not isinstance(torrent, str)
            or not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", torrent)
            or type(index) is not int or index < 0
            or session is None or fingerprint is None or
            hashlib.sha256("\x00".join((server, torrent, str(index)))
                           .encode("utf-8")).hexdigest() != fingerprint):
        raise ValueError("OWNER_BRIDGE_BACKGROUND_SELECTION_INVALID")
    return {"server_id": server, "torrent_hash": torrent, "file_index": index}


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
    tv_session_id: str | None = None,
    authorized_selection: dict[str, object] | None = None,
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
    if tv_session_id is not None and (
            source_fingerprint is None
            or not isinstance(tv_session_id, str)
            or _SESSION_ID.fullmatch(tv_session_id) is None):
        raise ValueError("OWNER_BRIDGE_V3_SESSION_INVALID")
    if authorized_selection is not None:
        authorized_selection = _authorized_selection(
            authorized_selection, source_fingerprint, tv_session_id)
    inbox = _private_dir(owner_root)
    with _ENQUEUE_LOCK:
        if source_fingerprint is not None:
            for prior in inbox.glob("event-*.json"):
                try:
                    existing = _parse_event(prior)
                except ValueError:
                    continue
                if (existing.source_fingerprint == source_fingerprint
                        and existing.selected_video_filename == video_filename
                        and (authorized_selection is None
                             or existing.authorized_selection is not None)):
                    # A reopened while its original provider job is pending.
                    # Attach to the durable checkpoints through P4, not a
                    # duplicate AGY job. A new trusted background request
                    # must not be swallowed by a legacy V3 (TV-bound) event.
                    # Finished A can enqueue anew later.
                    return existing.event_id
        event_id = secrets.token_hex(16)
        payload = {
            "schema": (_BACKGROUND_SCHEMA if authorized_selection is not None
                       else _SESSION_SCHEMA if tv_session_id is not None
                       else (_BOUND_SCHEMA if source_fingerprint is not None
                             else _SCHEMA)),
            "event_id": event_id,
            "selected_video_filename": video_filename,
        }
        if source_fingerprint is not None:
            payload["source_fingerprint"] = source_fingerprint
        if tv_session_id is not None:
            payload["tv_session_id"] = tv_session_id
        if authorized_selection is not None:
            payload["authorized_selection"] = authorized_selection
        body = json.dumps(
            payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if len(body) > _MAX_EVENT_BYTES:
            raise ValueError("OWNER_BRIDGE_EVENT_TOO_LARGE")
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
    if version in (_SESSION_SCHEMA, _BACKGROUND_SCHEMA):
        expected.update(("source_fingerprint", "tv_session_id"))
        if version == _BACKGROUND_SCHEMA:
            expected.add("authorized_selection")
    elif version == _BOUND_SCHEMA:
        expected.add("source_fingerprint")
    elif version != _SCHEMA:
        raise ValueError("OWNER_BRIDGE_EVENT_BAD_SCHEMA")
    if set(event) != expected:
        raise ValueError("OWNER_BRIDGE_EVENT_BAD_SCHEMA")
    fp = event.get("source_fingerprint")
    if version in (_BOUND_SCHEMA, _SESSION_SCHEMA, _BACKGROUND_SCHEMA) and (
            not isinstance(fp, str) or _FINGERPRINT.fullmatch(fp) is None):
        raise ValueError("OWNER_BRIDGE_SOURCE_FINGERPRINT_INVALID")
    session = event.get("tv_session_id")
    if version in (_SESSION_SCHEMA, _BACKGROUND_SCHEMA) and (
            not isinstance(session, str)
            or _SESSION_ID.fullmatch(session) is None):
        raise ValueError("OWNER_BRIDGE_V3_SESSION_INVALID")
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
    coordinates = (_authorized_selection(event["authorized_selection"], fp, session)
                   if version == _BACKGROUND_SCHEMA else None)
    return LocalEvent(event["event_id"], video, fp, session, coordinates)


def poll_private_events(
    *, owner_root: Path, processor: _Processor, emit: Callable[[str], object] = print,
    max_events: int = _MAX_EVENTS_PER_POLL,
    submit: Callable[[Callable[[], None]], object] | None = None,
) -> int:
    """Process only owner-private events, at most once automatically.

    A .claim is created exclusively BEFORE the first provider call. If the
    process crashes, the claim persists. A supervisor cannot silently repeat
    an uncertain API operation; exact owner reconciliation is required.
    """
    if (type(max_events) is not int or not 1 <= max_events <= _MAX_EVENTS_PER_POLL
            or (submit is not None and not callable(submit))
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
        except ValueError as exc:
            owner_full_trace("P2_EVENT_INVALID", error=exc,
                             event_path=str(path))
            emit("OWNER_BRIDGE_EVENT_REJECTED")
            continue
        retry = _retry_file(inbox, event.event_id)
        try:
            retry_attempts, retry_at = _retry_state(retry)
        except (OSError, ValueError) as exc:
            owner_full_trace("P2_RETRY_RECEIPT_INVALID", error=exc,
                             event_id=event.event_id)
            # An untrusted/inconsistent retry receipt must NEVER trigger a
            # new provider operation. Preserve the event for Owner review.
            os.replace(path, inbox / ("event-" + event.event_id + ".blocked"))
            emit("OWNER_BRIDGE_EVENT_BLOCKED_NO_RETRY")
            continue
        if int(time.time()) < retry_at:
            continue
        claim = inbox / ("claim-" + event.event_id)
        try:
            fd = os.open(claim, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            # A running background film owns this exact request. Do not
            # resubmit it or fill the Owner log on every 2-second tick.
            continue
        with os.fdopen(fd, "wb") as stream:
            stream.write(b"CLAIMED_DO_NOT_AUTO_REPLAY\n")
        processed += 1
        owner_full_trace("P2_EVENT_CLAIMED", event_id=event.event_id,
                         video=event.selected_video_filename,
                         source_fingerprint=event.source_fingerprint,
                         tv_session_id=event.tv_session_id)

        def run_claimed(event: LocalEvent = event, path: Path = path,
                        retry: Path = retry, claim: Path = claim,
                        retry_attempts: int = retry_attempts) -> None:
            try:
                if event.tv_session_id is not None:
                    result = processor.selected_media(
                        event.selected_video_filename,
                        source_fingerprint=event.source_fingerprint,
                        tv_session_id=event.tv_session_id,
                        **({"authorized_selection": event.authorized_selection}
                           if event.authorized_selection is not None else {}))
                elif event.source_fingerprint is not None:
                    result = processor.selected_media(
                        event.selected_video_filename,
                        source_fingerprint=event.source_fingerprint)
                else:
                    result = processor.selected_media(event.selected_video_filename)
                status = getattr(result, "status", None)
                if status not in ("VI_READY", "VIETSUB_READY", "REVIEW_REQUIRED"):
                    raise ValueError("OWNER_BRIDGE_INVALID_RESULT")
                suffix = ".done" if status != "REVIEW_REQUIRED" else ".review"
                os.replace(path, inbox / ("event-" + event.event_id + suffix))
                _remove_finished_retry(retry)
                owner_full_trace("P2_EVENT_FINISHED", event_id=event.event_id,
                                 result=status)
                emit("OWNER_BRIDGE_EVENT_" + (
                    "COMPLETE" if suffix == ".done" else "NEEDS_REVIEW"))
            except PreProviderTransient as exc:
                owner_full_trace("P2_PREPROVIDER_TRANSIENT", error=exc,
                                 event_id=event.event_id)
                # Only errors proven BEFORE a provider call are retried.
                if event.tv_session_id is None:
                    os.replace(path, inbox / ("event-" + event.event_id + ".blocked"))
                    _remove_finished_retry(retry)
                    emit("OWNER_BRIDGE_EVENT_BLOCKED_NO_RETRY")
                else:
                    try:
                        _record_preprovider_retry(
                            retry, min(retry_attempts + 1, len(_RETRY_DELAYS)),
                            int(time.time()))
                        claim.unlink()
                    except (OSError, ValueError):
                        emit("OWNER_BRIDGE_EVENT_PREPROVIDER_DEFER_HOLD")
                    else:
                        emit("OWNER_BRIDGE_EVENT_PREPROVIDER_DEFERRED")
                        emit("OWNER_BRIDGE_PREPROVIDER_REASON=" + exc.args[0])
            except Exception as exc:
                owner_full_trace("P2_EVENT_BLOCKED", error=exc,
                                 event_id=event.event_id,
                                 video=event.selected_video_filename,
                                 source_fingerprint=event.source_fingerprint,
                                 tv_session_id=event.tv_session_id)
                # Unknown provider effect: preserve claim and block retries.
                os.replace(path, inbox / ("event-" + event.event_id + ".blocked"))
                _remove_finished_retry(retry)
                emit("OWNER_BRIDGE_EVENT_BLOCKED_NO_RETRY")
                emit("OWNER_BRIDGE_BLOCK_REASON=" + _safe_block_reason(exc))
        if submit is None:
            run_claimed()
        else:
            # The same Owner process retains claims, isolated P2 per-film
            # state and the existing model adapter; only scheduling changes.
            submit(run_claimed)
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
                    emit: Callable[[str], object] = print,
                    trusted_v3_factory: Callable[[object], object] | None = None,
                    diagnostic_tick: Callable[[str], object] | None = None) -> None:
    if not 0.5 <= interval_seconds <= 60:
        raise ValueError("OWNER_BRIDGE_BAD_POLL_INTERVAL")
    if (os.environ.get("CI", "").lower() == "true"
            or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"):
        raise ValueError("OWNER_BRIDGE_NO_OWNER_RUNTIME_IN_CI")
    if diagnostic_tick is not None and not callable(diagnostic_tick):
        raise ValueError("OWNER_BRIDGE_DIAGNOSTIC_CALLBACK_INVALID")

    def safe_diagnostic_tick(state: str) -> None:
        if diagnostic_tick is not None:
            try:
                diagnostic_tick(state)
            except Exception as exc:
                owner_full_trace("OWNER_DIAGNOSTIC_TICK_FAILED", error=exc)
                # A diagnostic failure must never stop playback or provoke a
                # second potentially billable provider operation.
                pass

    # OS releases the process mutex on Windows logoff/crash; durable
    # D2/Gemini one-post/inflight claims are never automatically deleted.
    with _owner_process_lock(private_root):
        write_owner_agent_health(owner_root=private_root, state="STARTING")
        safe_diagnostic_tick("STARTING")
        try:
            from automatic_vietsub_flow import build_owner_auto_flow
            # Never call Gemini at startup: VI-only work remains usable.
            flow = build_owner_auto_flow(
                enabled=True, cache_root=cache_root, state_root=state_root)
        except Exception as exc:
            owner_full_trace("OWNER_PROVIDER_BOOTSTRAP_FAILED", error=exc)
            write_owner_agent_health(owner_root=private_root, state="BLOCKED")
            raise
        # The F6 provider source remains SHA-pinned. Observe its existing
        # stages from this single Owner entrypoint instead of modifying F6.
        flow.emit = emit
        # Native OMP/TorrServer authenticated readers are NOT installed by
        # this CLI. An owner-controlled host may supply a V3 processor factory
        # only after establishing the live trust boundary. Without one, V3
        # events fail closed (unexpected TV session kwarg) before any provider.
        processor = flow
        if trusted_v3_factory is not None:
            if not callable(trusted_v3_factory):
                raise ValueError("OWNER_BRIDGE_TRUSTED_V3_FACTORY_INVALID")
            processor = trusted_v3_factory(flow)
            if not callable(getattr(processor, "selected_media", None)):
                raise ValueError("OWNER_BRIDGE_TRUSTED_V3_PROCESSOR_INVALID")
        emit("OWNER_BRIDGE_STARTED")
        # A whole-film LEAN120 call occupies the event-consumer thread for
        # minutes. Keep Owner/P3/P4 health and the fixed HostOps snapshot fresh
        # independently; this ticker never polls events or calls a provider.
        ticker_stop = threading.Event()

        def owner_health_ticker() -> None:
            while not ticker_stop.is_set():
                try:
                    write_owner_agent_health(owner_root=private_root,
                                             state="READY")
                    safe_diagnostic_tick("READY")
                except Exception as exc:
                    owner_full_trace("OWNER_HEALTH_TICK_FAILED", error=exc)
                if ticker_stop.wait(_HEALTH_TICK_SECONDS):
                    return

        ticker = threading.Thread(
            target=owner_health_ticker, name="torrent-tv-owner-health",
            daemon=True)
        ticker.start()
        try:
            # Three simultaneous film jobs, one Owner process, no duplicate
            # translator stack. A TV close only removes its active P4 feed.
            with ThreadPoolExecutor(max_workers=3,
                                    thread_name_prefix="ttv-film") as pool:
                active: set[Future] = set()
                while True:
                    consume_inert_runner_wakes()
                    finished = {future for future in active if future.done()}
                    for future in finished:
                        try:
                            future.result()
                        except Exception as exc:
                            # A claim already exists: never blindly rerun an
                            # unexpected provider-effect or callback failure.
                            owner_full_trace("P2_BACKGROUND_WORKER_FAILED", error=exc)
                    active.difference_update(finished)
                    available = 3 - len(active)
                    if available:
                        poll_private_events(
                            owner_root=private_root, processor=processor,
                            emit=emit, max_events=available,
                            submit=lambda work: active.add(pool.submit(work)))
                    time.sleep(interval_seconds)
        finally:
            ticker_stop.set()
            ticker.join(timeout=5.0)
            write_owner_agent_health(owner_root=private_root,
                                     state="STOPPED")
            safe_diagnostic_tick("STOPPED")


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

"""Owner-local, resumable EN SRT/VTT -> LEAN120 Gemini -> VI SRT/VTT.

This is a library worker, NOT an implicit service. A previously matched and
authorized source is required. It is started only by an explicitly opted-in
P2/P4 owner gateway or by an authorized local caller. Each completed batch
is persisted before delivery; uncertain provider calls NEVER auto-retry.

Private state can contain translated dialogue; it MUST be placed outside the
public repository in an owner-ACL-protected directory. No secrets are logged.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import secrets
from typing import Callable, Mapping

from assumed_source_handoff import AssumedEnglishSubtitle
from cue_pipeline import parse_cues
from lean120_api import ModelProfile, Transport, _https_post, make_gemini_payload, translate_window
from progressive_handoff import ProgressiveSubtitleSession, SubtitleRevision

_SAFE_JOB = re.compile(r"[0-9a-f]{64}\Z")


def _json_bytes(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")


def _write_new_synced(path: Path, payload: bytes) -> None:
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(payload)
        f.flush()
        os.fsync(f.fileno())


def _commit_new(path: Path, data: bytes) -> None:
    """Never replace another artifact or a previously committed batch."""
    temporary = path.with_name(path.name + "." + secrets.token_hex(8) + ".tmp")
    try:
        _write_new_synced(temporary, data)
        # With the per-job exclusive lock, destination cannot be created by
        # another cooperative worker. Use hard link to enforce no-clobber even
        # against a second process; the same directory is one filesystem.
        os.link(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _job_fingerprint(handoff: AssumedEnglishSubtitle,
                     profile: ModelProfile, glossary: Mapping[str, str]) -> str:
    descriptor = {
        "schema": "TTV-P2-AUTO-LEAN120-JOB-V1",
        "media_key": handoff.media_key,
        "source_sha256": handoff.source_sha256,
        "fmt": handoff.fmt,
        "provider": profile.provider,
        "model": profile.model,
        "thinking_level": profile.thinking_level,
        "glossary": dict(glossary),
    }
    return hashlib.sha256(_json_bytes(descriptor)).hexdigest()


class AutomaticLean120Worker:
    """Close EN -> verified progressive VI -> private output + P4 callback.

    No implicit source discovery, network, model call or service startup.
    Inject a fake transport for CI; the real HTTPS transport is used ONLY
    when a caller explicitly runs this worker with an API key.
    """

    def __init__(self, *, state_root: Path, profile: ModelProfile,
                 glossary: Mapping[str, str], api_key: str,
                 transport: Transport = _https_post) -> None:
        if not isinstance(state_root, Path) or not state_root.is_absolute():
            raise ValueError("AUTO_LEAN120_ABSOLUTE_PRIVATE_STATE_REQUIRED")
        if not isinstance(api_key, str) or not api_key.strip():
            raise ValueError("GEMINI_API_KEY_REQUIRED")
        if not isinstance(glossary, Mapping):
            raise ValueError("LEAN120_GLOSSARY_INVALID")
        if not callable(transport):
            raise ValueError("AUTO_LEAN120_TRANSPORT_INVALID")
        self.state_root = state_root
        self.profile = profile
        self.glossary = dict(glossary)
        self.api_key = api_key
        self.transport = transport

    def run(self, handoff: AssumedEnglishSubtitle, *,
            on_revision: Callable[[SubtitleRevision], object] | None = None,
            max_new_windows: int | None = None
            ) -> SubtitleRevision:
        # Explicit one-new-call pilot mode; default behavior still completes
        # the entire film. Old checkpoints are replayed without quota spend.
        if max_new_windows is not None and (
                type(max_new_windows) is not int or max_new_windows != 1):
            raise ValueError("AUTO_LEAN120_PILOT_WINDOW_LIMIT_INVALID")
        if (not isinstance(handoff, AssumedEnglishSubtitle) or
            handoff.source_status != "ASSUMED_MATCHED_EN_TIMED_TEXT"):
            raise ValueError("AUTO_LEAN120_AUTHORIZED_EN_HANDOFF_REQUIRED")
        source = AssumedEnglishSubtitle.from_supplied(
            media_key=handoff.media_key, fmt=handoff.fmt,
            source_bytes=handoff.source_bytes)
        if (source.source_sha256 != handoff.source_sha256 or
            source.cue_count != handoff.cue_count):
            raise ValueError("AUTO_LEAN120_SOURCE_CHANGED")
        session = ProgressiveSubtitleSession(
            source.source_bytes, source.fmt, source.media_key)
        # Validate ALL windows and the configured glossary BEFORE any on-disk
        # in-flight marker or potentially billable call.
        for window in session.windows:
            make_gemini_payload(window, self.profile, self.glossary)
        digest = _job_fingerprint(source, self.profile, self.glossary)
        if not _SAFE_JOB.fullmatch(digest):
            raise ValueError("AUTO_LEAN120_JOB_KEY_INVALID")
        self.state_root.mkdir(mode=0o700, parents=True, exist_ok=True)
        folder = self.state_root / digest
        folder.mkdir(mode=0o700, exist_ok=True)
        lock = folder / "active.lock"
        # An existing/stale lock is deliberately NOT broken or auto-replayed.
        _write_new_synced(lock, b"TTV-P2-LOCK-V1\n")
        try:
            newly_called = 0
            for window in session.windows:
                version = window.number
                checkpoint = folder / f"batch-{version:04d}.json"
                inflight = folder / f"batch-{version:04d}.inflight"
                if checkpoint.is_file():
                    data = json.loads(checkpoint.read_bytes())
                    if (not isinstance(data, dict) or
                        set(data) != {"schema", "job", "version", "translations", "payload_sha256"} or
                        data["schema"] != "TTV-P2-LEAN120-CHECKPOINT-V1" or
                        data["job"] != digest or type(data["version"]) is not int or
                        data["version"] != version or
                        not isinstance(data["translations"], list) or
                        len(data["translations"]) != len(window.ids)):
                        raise ValueError("AUTO_LEAN120_CHECKPOINT_INVALID")
                    translations: dict[int, str] = {}
                    for item, expected in zip(data["translations"], window.ids):
                        if (not isinstance(item, dict) or set(item) != {"id", "vi"} or
                            type(item["id"]) is not int or item["id"] != expected or
                            not isinstance(item["vi"], str)):
                            raise ValueError("AUTO_LEAN120_CHECKPOINT_INVALID")
                        translations[expected] = item["vi"]
                    revision = session.commit(
                        window, translations, expected_version=version - 1,
                        source_sha256=source.source_sha256, media_key=source.media_key)
                    if revision.sha256 != data["payload_sha256"]:
                        raise ValueError("AUTO_LEAN120_CHECKPOINT_DIGEST_MISMATCH")
                    # A crash after committing the checkpoint but before
                    # deleting its in-flight marker is fully recoverable.
                    inflight.unlink(missing_ok=True)
                else:
                    if inflight.exists():
                        raise ValueError("AUTO_LEAN120_UNCERTAIN_BATCH_MANUAL_RECONCILE")
                    if max_new_windows is not None and newly_called >= max_new_windows:
                        # Clean pause: do NOT create an in-flight marker for the
                        # next window, do not send the next paid request.
                        break
                    _write_new_synced(inflight, _json_bytes({
                        "schema": "TTV-P2-INFLIGHT-V1", "job": digest,
                        "version": version}))
                    # If transport errors, process dies, output is invalid or
                    # checkpoint commit fails, keep marker. Unknown provider
                    # effects must never be blindly replayed or charged twice.
                    translations = translate_window(
                        window, self.profile, glossary=self.glossary,
                        api_key=self.api_key, transport=self.transport)
                    newly_called += 1
                    revision = session.commit(
                        window, translations, expected_version=version - 1,
                        source_sha256=source.source_sha256, media_key=source.media_key)
                    _commit_new(checkpoint, _json_bytes({
                        "schema": "TTV-P2-LEAN120-CHECKPOINT-V1",
                        "job": digest, "version": version,
                        "translations": [
                            {"id": i, "vi": translations[i]} for i in window.ids
                        ],
                        "payload_sha256": revision.sha256,
                    }))
                    inflight.unlink()
                # Replayed versions also reach a freshly authenticated P4
                # session; nothing is resent to Gemini for cached windows.
                if on_revision is not None:
                    on_revision(revision)
            final = session.revision
            if final is None:
                raise ValueError("AUTO_LEAN120_INCOMPLETE")
            if not final.complete:
                if max_new_windows is None:
                    raise ValueError("AUTO_LEAN120_INCOMPLETE")
                # Partial cumulative SRT has already passed strict commit QA.
                # No vi-final.srt is written until the full film is complete.
                return final
            # Independent strict parser/timeline check of the final artifact.
            out = parse_cues(final.payload, final.fmt)
            inp = parse_cues(source.source_bytes, source.fmt)
            if len(inp) != len(out) or any(
                (a.number, a.start_ms, a.end_ms, a.identifier, a.settings) !=
                (b.number, b.start_ms, b.end_ms, b.identifier, b.settings)
                for a, b in zip(inp, out)
            ):
                raise ValueError("AUTO_LEAN120_FINAL_TIMELINE_INVALID")
            result = folder / ("vi-final." + final.fmt)
            if result.exists():
                if hashlib.sha256(result.read_bytes()).hexdigest() != final.sha256:
                    raise ValueError("AUTO_LEAN120_FINAL_FILE_COLLISION")
            else:
                _commit_new(result, final.payload)
            return final
        finally:
            lock.unlink(missing_ok=True)

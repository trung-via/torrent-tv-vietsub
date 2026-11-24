"""Owner-local, resumable EN SRT/VTT -> provider gateway -> VI SRT/VTT.

This is a library worker, NOT an implicit service. A previously matched and
authorized source is required. It is started only by an explicitly opted-in
P2/P4 owner gateway or by an authorized local caller. Each completed batch
is persisted before delivery; uncertain provider calls NEVER auto-retry.

Private state can contain translated dialogue; it MUST be placed outside the
public repository in an owner-ACL-protected directory. No secrets are logged.
"""
from __future__ import annotations

from concurrent.futures import Future, ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
from typing import Callable, Mapping

from assumed_source_handoff import AssumedEnglishSubtitle
from cue_pipeline import apply_translations, parse_cues
from lean120_api import ModelProfile
from translator_gateway import Runner, _prompt, preflight_provider, provider_enabled, translate_window
from progressive_handoff import ProgressiveSubtitleSession, SubtitleRevision, TranslationWindow

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
    Inject a fake provider runner for CI; no direct model HTTP transport.
    """

    def __init__(self, *, state_root: Path, profile: ModelProfile,
                 glossary: Mapping[str, str],
                 runner: Runner | None = None,
                 first_window_cues: int | None = None,
                 parallel_batches: int = 1,
                 preserve_hydrogen_jobs: bool = False) -> None:
        if not isinstance(state_root, Path) or not state_root.is_absolute():
            raise ValueError("AUTO_LEAN120_ABSOLUTE_PRIVATE_STATE_REQUIRED")
        if not provider_enabled(profile.provider):
            raise ValueError("AUTO_LEAN120_PROVIDER_NOT_ENABLED")
        if not isinstance(glossary, Mapping):
            raise ValueError("LEAN120_GLOSSARY_INVALID")
        if runner is not None and not callable(runner):
            raise ValueError("AUTO_LEAN120_RUNNER_INVALID")
        if first_window_cues is not None and (
                type(first_window_cues) is not int
                or not 1 <= first_window_cues <= 120):
            raise ValueError("AUTO_LEAN120_FIRST_WINDOW_CUE_LIMIT_INVALID")
        if type(parallel_batches) is not int or not 1 <= parallel_batches <= 3:
            raise ValueError("AUTO_LEAN120_PARALLEL_LIMIT_INVALID")
        if type(preserve_hydrogen_jobs) is not bool:
            raise ValueError("AUTO_LEAN120_PROFILE_REUSE_FLAG_INVALID")
        self.preserve_hydrogen_jobs = preserve_hydrogen_jobs
        self.parallel_batches = parallel_batches
        self.state_root = state_root
        self.profile = profile
        self.glossary = dict(glossary)
        self.runner = runner
        self.first_window_cues = first_window_cues

    def profile_for_source(self, source: AssumedEnglishSubtitle) -> ModelProfile:
        """Keep the original profile for an existing exact-source job.

        No migration, copying, mixing models or replay of uncertain work.
        The Owner opts into compatibility for the High/Low transition; other
        callers retain deliberate isolated-profile benchmarking semantics.
        """
        high = ModelProfile("antigravity", "gemini-4-hydrogen-high", "high")
        low = ModelProfile("antigravity", "gemini-4-hydrogen-low", "low")
        if not self.preserve_hydrogen_jobs or self.profile not in (high, low):
            return self.profile
        existing = []
        for profile in (high, low):
            folder = self.state_root / _job_fingerprint(source, profile, self.glossary)
            if folder.is_symlink() or (folder.exists() and not folder.is_dir()):
                raise ValueError("AUTO_LEAN120_PROFILE_STATE_INVALID")
            if folder.is_dir():
                existing.append(profile)
        if len(existing) > 1:
            raise ValueError("AUTO_LEAN120_PROFILE_STATE_AMBIGUOUS")
        return existing[0] if existing else self.profile

    def job_fingerprint(self, source: AssumedEnglishSubtitle) -> str:
        return _job_fingerprint(source, self.profile_for_source(source), self.glossary)

    def progressive_session(self, source: AssumedEnglishSubtitle
                            ) -> ProgressiveSubtitleSession:
        """Use 50-first for new jobs; continue an existing 120-first job.

        The fingerprint stays unchanged, so old completed/uncertain work is
        never treated as an unrelated job eligible for a second provider call.
        A committed first batch identifies its original window layout. A
        pre-commit inflight marker leaves the prior plan unknown: HOLD it.
        """
        session = ProgressiveSubtitleSession(
            source.source_bytes, source.fmt, source.media_key,
            first_window_cues=self.first_window_cues)
        if self.first_window_cues is None:
            return session
        legacy = ProgressiveSubtitleSession(
            source.source_bytes, source.fmt, source.media_key)
        if session.windows[0].ids == legacy.windows[0].ids:
            return session
        folder = self.state_root / self.job_fingerprint(source)
        first = folder / "batch-0001.json"
        inflight = folder / "batch-0001.inflight"
        if first.is_symlink() or inflight.is_symlink():
            raise ValueError("AUTO_LEAN120_WINDOW_PLAN_UNVERIFIED")
        if not first.exists():
            if inflight.exists():
                raise ValueError("AUTO_LEAN120_WINDOW_PLAN_UNCERTAIN")
            return session
        try:
            if not first.is_file() or first.stat().st_size > 256 * 1024:
                raise ValueError("INVALID")
            record = json.loads(first.read_bytes())
            if not isinstance(record, dict) or not isinstance(
                    record.get("translations"), list):
                raise ValueError("INVALID")
            count = len(record["translations"])
        except (OSError, ValueError, UnicodeError):
            raise ValueError("AUTO_LEAN120_WINDOW_PLAN_UNVERIFIED") from None
        if count == len(legacy.windows[0].ids):
            return legacy
        if count == len(session.windows[0].ids):
            return session
        raise ValueError("AUTO_LEAN120_WINDOW_PLAN_UNVERIFIED")

    def run(self, handoff: AssumedEnglishSubtitle, *,
            on_revision: Callable[[SubtitleRevision], object] | None = None,
            max_new_windows: int | None = None
            ) -> SubtitleRevision:
        # Explicit first-window-only pilot mode; default behavior still
        # completes the entire film. Rerunning this pilot never advances
        # beyond batch one, even when its checkpoint already exists.
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
        selected_profile = self.profile_for_source(source)
        session = self.progressive_session(source)
        # Validate ALL windows and the configured glossary BEFORE any on-disk
        # in-flight marker or potentially billable call.
        for window in session.windows:
            _prompt(window, self.glossary)
        if self.runner is None:
            # Account/config/CI gate MUST run before a new in-flight marker is
            # recorded, even for the first window of a new source.
            preflight_provider(selected_profile)
        digest = _job_fingerprint(source, selected_profile, self.glossary)
        if self.job_fingerprint(source) != digest:
            raise ValueError("AUTO_LEAN120_PROFILE_STATE_CHANGED")
        if not _SAFE_JOB.fullmatch(digest):
            raise ValueError("AUTO_LEAN120_JOB_KEY_INVALID")
        # Other films own independent checkpoint/lock namespaces. Their
        # active or uncertain batches must never prevent B from starting.
        # This EXACT job remains protected by its own active.lock and
        # batch-XXXX.inflight checks below, so no ambiguous batch is replayed.
        self.state_root.mkdir(mode=0o700, parents=True, exist_ok=True)
        folder = self.state_root / digest
        folder.mkdir(mode=0o700, exist_ok=True)
        # An owner-acknowledged, unknown-effect batch is never silently
        # recreated. A separate, explicitly authorized job may proceed after
        # the old marker is preserved in owner-private quarantine.
        if any(folder.glob("batch-*.abandoned.json")):
            raise ValueError("AUTO_LEAN120_ABANDONED_JOB_HOLD")
        lock = folder / "active.lock"
        # An existing/stale lock is deliberately NOT broken or auto-replayed.
        _write_new_synced(lock, b"TTV-P2-LOCK-V1\n")
        # First cue window is always prioritized alone. Later windows may run
        # concurrently; each independently durable result is stored before
        # returning to the ordered commit loop. P4 sees only contiguous revisions.
        futures: dict[int, Future[dict[int, str]]] = {}
        pool = None

        def provider(window: TranslationWindow) -> dict[int, str]:
            if self.runner is None:
                return translate_window(window, selected_profile, glossary=self.glossary)
            return translate_window(window, selected_profile, glossary=self.glossary,
                                    runner=self.runner)

        def translated_result(window: TranslationWindow) -> dict[int, str]:
            version = window.number
            inflight = folder / f"batch-{version:04d}.inflight"
            ready = folder / f"result-{version:04d}.json"
            if ready.exists():
                if not inflight.is_file() or ready.is_symlink() or not ready.is_file() or not 0 < ready.stat().st_size <= 256 * 1024:
                    raise ValueError("AUTO_LEAN120_PARALLEL_RESULT_INVALID")
                data = json.loads(ready.read_bytes())
                if (not isinstance(data, dict) or
                        set(data) != {"schema", "job", "version", "translations", "sha256"} or
                        data["schema"] != "TTV-P2-LEAN120-RESULT-V1" or
                        data["job"] != digest or type(data["version"]) is not int or
                        data["version"] != version or
                        not isinstance(data["translations"], list) or
                        len(data["translations"]) != len(window.ids) or
                        hashlib.sha256(_json_bytes(data["translations"])).hexdigest() != data["sha256"]):
                    raise ValueError("AUTO_LEAN120_PARALLEL_RESULT_INVALID")
                translations = {}
                for row, expected in zip(data["translations"], window.ids):
                    if (not isinstance(row, dict) or set(row) != {"id", "vi"} or
                            type(row["id"]) is not int or row["id"] != expected or
                            not isinstance(row["vi"], str)):
                        raise ValueError("AUTO_LEAN120_PARALLEL_RESULT_INVALID")
                    translations[expected] = row["vi"]
                apply_translations(window.target, {str(k): v for k, v in translations.items()})
                return translations
            if inflight.exists():
                raise ValueError("AUTO_LEAN120_UNCERTAIN_BATCH_MANUAL_RECONCILE")
            _write_new_synced(inflight, _json_bytes({
                "schema": "TTV-P2-INFLIGHT-V1", "job": digest, "version": version}))
            translations = provider(window)
            rows = [{"id": i, "vi": translations[i]} for i in window.ids]
            _commit_new(ready, _json_bytes({
                "schema": "TTV-P2-LEAN120-RESULT-V1", "job": digest, "version": version,
                "translations": rows, "sha256": hashlib.sha256(_json_bytes(rows)).hexdigest(),
            }))
            return translations

        try:
            if self.parallel_batches > 1 and max_new_windows is None:
                pool = ThreadPoolExecutor(max_workers=self.parallel_batches)
            for window in session.windows:
                # Pilot means the FIRST window of this source across ALL
                # invocations, not one fresh API call on every rerun.
                # Re-running the same pilot must never advance to batch 2.
                if max_new_windows is not None and window.number > max_new_windows:
                    break
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
                    if version == 1:
                        # Keep existing first-window recovery and pilot semantics.
                        if inflight.exists():
                            raise ValueError("AUTO_LEAN120_UNCERTAIN_BATCH_MANUAL_RECONCILE")
                        _write_new_synced(inflight, _json_bytes({
                            "schema": "TTV-P2-INFLIGHT-V1", "job": digest, "version": version}))
                        translations = provider(window)
                    elif pool is None:
                        translations = translated_result(window)
                    else:
                        if version not in futures:
                            # Submit at most one bounded group. Stop admission
                            # at any pre-existing ambiguous effect or checkpoint.
                            for planned in session.windows[version - 1:version - 1 + self.parallel_batches]:
                                n = planned.number
                                cp = folder / f"batch-{n:04d}.json"
                                marker = folder / f"batch-{n:04d}.inflight"
                                ready = folder / f"result-{n:04d}.json"
                                if cp.exists() or (marker.exists() and not ready.is_file()):
                                    break
                                futures[n] = pool.submit(translated_result, planned)
                            if version not in futures:
                                raise ValueError("AUTO_LEAN120_UNCERTAIN_BATCH_MANUAL_RECONCILE")
                        translations = futures.pop(version).result()
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
                # A committed checkpoint is authoritative even if cleanup
                # was interrupted. Results are NOT part of the P4 checkpoint glob.
                (folder / f"result-{version:04d}.json").unlink(missing_ok=True)
                # Replayed versions also reach a freshly authenticated P4
                # session; nothing is resent to the provider for cached windows.
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
            # Cancel unstarted work; drain already-started calls so their
            # result/unknown-effect marker is preserved before releasing lock.
            if pool is not None:
                pool.shutdown(wait=True, cancel_futures=True)
            lock.unlink(missing_ok=True)

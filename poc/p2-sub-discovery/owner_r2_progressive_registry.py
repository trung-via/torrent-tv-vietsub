"""Exact signed-TV EN→P2 checkpoint→existing P4 rolling revision bridge.

This extends the verified-final registry; no second translator, event queue,
network listener, provider call or persisted private subtitle payload.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Callable

_POC = Path(__file__).resolve().parent.parent
for _sibling in ("p2-aisub", "p3-vietsub-trigger"):
    _path = str((_POC / _sibling).resolve())
    if _path not in sys.path:
        sys.path.insert(0, _path)

from assumed_source_handoff import AssumedEnglishSubtitle
from cached_en_direct_handoff import CachedEnReceipt, prepare_local_translation_source
from cue_pipeline import parse_cues
from lan_revision_feed import SessionRevisionFeed
from paired_activation import AuthenticatedProgressiveSource
from progressive_handoff import ProgressiveSubtitleSession, SubtitleRevision
from automatic_lean120_worker import AutomaticLean120Worker, _job_fingerprint
from owner_selected_file_resolver import CurrentPlaying, _fingerprint
from matcher import Media
from p3_p4_media_key import p4_key_from_verified_current
from p3_p4_ready_registry import P3OwnerReadyRegistry, P3ReadyRejected
from dual_subtitle_catalog import DualSubtitleCatalog
from verified_vietsub_ready import VerifiedVietsubReady


@dataclass
class _RollingReceipt:
    media: Media
    tv_session: str
    fingerprint: str
    media_key: str
    source_file: Path
    source_root: Path
    source_sha256: str
    source_cues: int
    worker_media_key: str
    latest: SubtitleRevision | None
    feeds: list[SessionRevisionFeed] = field(default_factory=list)


class R2OwnerProgressiveRegistry(P3OwnerReadyRegistry):
    def __init__(self, *, read_verified_current_playback: Callable,
                 on_status: Callable[[str], None] | None = None):
        super().__init__(
            read_verified_current_playback=read_verified_current_playback)
        if on_status is not None and not callable(on_status):
            raise P3ReadyRejected("P4_ROLLING_STATUS_SINK_INVALID")
        self._rolling: dict[str, _RollingReceipt] = {}
        self._flow: object | None = None
        self._on_status = on_status

    def _status(self, code: str) -> None:
        """Only source-owned enum; status reporting cannot affect delivery."""
        if self._on_status is not None:
            try:
                self._on_status(code)
            except Exception:
                pass

    def bind_existing_flow(self, flow: object) -> None:
        """Bind the ONE already-running P2 worker for read-only checkpoint reuse.

        P4 activation may be served on a different HTTPS thread while P2 is
        doing a paid window. Never call worker.run() from this path.
        """
        if (not isinstance(getattr(flow, "worker", None), AutomaticLean120Worker)
                or not isinstance(getattr(flow, "cache_root", None), Path)):
            raise P3ReadyRejected("P4_ROLLING_EXISTING_P2_REQUIRED")
        with self._lock:
            if self._flow is not None and self._flow is not flow:
                raise P3ReadyRejected("P4_ROLLING_FLOW_CHANGED")
            self._flow = flow

    def resolve_variant(self, media_key: str, variant: str) -> VerifiedVietsubReady | None:
        """Explicitly selected VI option; never auto-replace the AI P4 feed.

        This is invoked only after V2's variant-specific device HMAC. A
        cached Vietnamese candidate stays labelled unverified for sync, but
        its bytes and exact media ownership are independently verified.
        """
        if variant != "downloaded_vi":
            raise P3ReadyRejected("P4_VARIANT_NOT_SUPPORTED")
        with self._lock:
            flow = self._flow
        if flow is None:
            raise P3ReadyRejected("P4_VARIANT_FLOW_UNBOUND")
        try:
            current = self._read()
        except Exception:
            raise P3ReadyRejected("P4_VARIANT_CURRENT_TV_MISSING") from None
        if not isinstance(current, CurrentPlaying):
            raise P3ReadyRejected("P4_VARIANT_CURRENT_TV_MISSING")
        media = Media(current.server_id, current.torrent_hash,
                      current.file_index, current.video_name)
        fingerprint = _fingerprint(media.server_profile_id,
                                   media.torrent_hash, media.file_index)
        self._current(media, current.tv_session_id, fingerprint)
        if p4_key_from_verified_current(media, current) != media_key:
            raise P3ReadyRejected("P4_VARIANT_MEDIA_KEY_CHANGED")
        receipt = DualSubtitleCatalog(self._root(flow.cache_root)).read(
            media, fingerprint, "downloaded_vi")
        if receipt is None:
            return None
        payload = self._file(self._root(flow.cache_root), receipt.file,
                             sha=receipt.sha256, cues=receipt.cues)
        latest = self._current(media, current.tv_session_id, fingerprint)
        if p4_key_from_verified_current(media, latest) != media_key:
            raise P3ReadyRejected("P4_VARIANT_MEDIA_KEY_CHANGED")
        return VerifiedVietsubReady.from_verified_bytes(
            media_key=media_key, source_language="vi",
            source_bytes=payload, vietsub_bytes=payload)

    @classmethod
    def _recover_handoff(cls, flow: object, fingerprint: str,
                         media: Media | None = None
                         ) -> AssumedEnglishSubtitle | None:
        """Trust only the existing private source receipt and its EN bytes."""
        root = cls._root(getattr(flow, "cache_root", None))
        if media is not None:
            dual = DualSubtitleCatalog(root).read(media, fingerprint, "ai_en")
            if dual is not None:
                handoff = prepare_local_translation_source(
                    CachedEnReceipt(dual.file, dual.sha256, dual.cues),
                    private_root=root)
                cls._cached_en(flow, fingerprint, handoff, media)
                return handoff
        index = root / (".auto-source-" + fingerprint + ".json")
        if not index.is_file():
            return None  # A first P2 checkpoint has not been prepared yet.
        try:
            if index.is_symlink() or index.stat().st_size > 512:
                raise P3ReadyRejected("P4_ROLLING_SOURCE_INDEX_INVALID")
            row = json.loads(index.read_text(encoding="utf-8"))
            if (not isinstance(row, dict)
                    or set(row) != {"schema", "file", "language", "sha256", "cues"}
                    or row["schema"] != "TTV-LOCAL-AUTO-SOURCE-V1"
                    or row["language"] not in ("en", "vi")
                    or not isinstance(row["file"], str)
                    or re.fullmatch(r"[0-9a-f]{64}\.srt", row["file"]) is None
                    or not isinstance(row["sha256"], str)
                    or re.fullmatch(r"[0-9a-f]{64}", row["sha256"]) is None
                    or type(row["cues"]) is not int or row["cues"] < 1):
                raise P3ReadyRejected("P4_ROLLING_SOURCE_RECEIPT_INVALID")
            # The same durable source index also describes an already-ready
            # Vietnamese SRT. It is not an EN translation checkpoint: leave
            # it to the verified-VI factory instead of rejecting activation.
            if row["language"] == "vi":
                return None
            handoff = prepare_local_translation_source(
                CachedEnReceipt(root / row["file"], row["sha256"], row["cues"]),
                private_root=root)
            cls._cached_en(flow, fingerprint, handoff)
            return handoff
        except P3ReadyRejected:
            raise
        except Exception:
            raise P3ReadyRejected("P4_ROLLING_SOURCE_NOT_VERIFIED") from None

    @staticmethod
    def _committed_revision(worker: AutomaticLean120Worker,
                            handoff: AssumedEnglishSubtitle
                            ) -> SubtitleRevision | None:
        """Reconstruct contiguous, hash-verified P2 checkpoints, never run P2.

        A currently in-flight paid window is intentionally ignored: the prior
        committed cumulative prefix can be delivered without waiting for it.
        """
        state = worker.state_root
        if state.is_symlink() or not state.is_dir():
            return None
        job = _job_fingerprint(handoff, worker.profile, worker.glossary)
        folder = state / job
        if folder.is_symlink() or not folder.is_dir():
            return None
        if any(folder.glob("batch-*.abandoned.json")):
            raise P3ReadyRejected("P4_ROLLING_ABANDONED_JOB_HOLD")
        session = ProgressiveSubtitleSession(
            handoff.source_bytes, handoff.fmt, handoff.media_key)
        latest = None
        try:
            for window in session.windows:
                checkpoint = folder / f"batch-{window.number:04d}.json"
                if not checkpoint.exists():
                    break
                if (checkpoint.is_symlink() or not checkpoint.is_file()
                        or not 0 < checkpoint.stat().st_size <= 256 * 1024):
                    raise P3ReadyRejected("P4_ROLLING_CHECKPOINT_INVALID")
                row = json.loads(checkpoint.read_bytes())
                if (not isinstance(row, dict)
                        or set(row) != {"schema", "job", "version",
                                            "translations", "payload_sha256"}
                        or row["schema"] != "TTV-P2-LEAN120-CHECKPOINT-V1"
                        or row["job"] != job
                        or type(row["version"]) is not int
                        or row["version"] != window.number
                        or not isinstance(row["translations"], list)
                        or len(row["translations"]) != len(window.ids)):
                    raise P3ReadyRejected("P4_ROLLING_CHECKPOINT_INVALID")
                translations = {}
                for item, expected in zip(row["translations"], window.ids):
                    if (not isinstance(item, dict) or set(item) != {"id", "vi"}
                            or type(item["id"]) is not int or item["id"] != expected
                            or not isinstance(item["vi"], str)):
                        raise P3ReadyRejected("P4_ROLLING_CHECKPOINT_INVALID")
                    translations[expected] = item["vi"]
                latest = session.commit(
                    window, translations, expected_version=window.number - 1,
                    source_sha256=handoff.source_sha256,
                    media_key=handoff.media_key)
                if latest.sha256 != row["payload_sha256"]:
                    raise P3ReadyRejected("P4_ROLLING_CHECKPOINT_HASH_CHANGED")
            # Fail closed on a gap: do not conceal an inconsistent P2 job.
            if latest is not None and any(
                    path.name > f"batch-{latest.version:04d}.json"
                    for path in folder.glob("batch-*.json")):
                raise P3ReadyRejected("P4_ROLLING_CHECKPOINT_GAP")
            return latest
        except P3ReadyRejected:
            raise
        except Exception:
            raise P3ReadyRejected("P4_ROLLING_CHECKPOINT_NOT_VERIFIED") from None

    def _restore_current_checkpoint(self, media_key: str) -> str | None:
        with self._lock:
            flow = self._flow
        if flow is None:
            self._status("FLOW_UNBOUND")
            return "FLOW_UNBOUND"
        # Even a live registry can lag after a failed P4 callback. Reconcile
        # the newest durable batch on EVERY new authenticated activation.
        try:
            current = self._read()
        except Exception:
            raise P3ReadyRejected("P4_ROLLING_CURRENT_TV_UNAVAILABLE") from None
        if not isinstance(current, CurrentPlaying):
            raise P3ReadyRejected("P4_ROLLING_CURRENT_TV_UNAVAILABLE")
        media = Media(current.server_id, current.torrent_hash,
                      current.file_index, current.video_name)
        if p4_key_from_verified_current(media, current) != media_key:
            self._status("MEDIA_KEY_MISMATCH")
            return "MEDIA_KEY_MISMATCH"
        with self._lock:
            prior = self._rolling.get(media_key)
            if prior is not None and prior.tv_session != current.tv_session_id:
                # A→B→A with the same native media key starts a NEW TV
                # subscription. Discard only the stale in-memory feed;
                # source checkpoints/final SRT belong to A and stay intact.
                del self._rolling[media_key]
        fingerprint = _fingerprint(current.server_id, current.torrent_hash,
                                   current.file_index)
        self._current(media, current.tv_session_id, fingerprint)
        handoff = self._recover_handoff(flow, fingerprint, media)
        if handoff is None:
            # May be a VI source or an early request before EN cache exists.
            # The original completed-VI factory is still allowed to resolve.
            self._status("EN_INDEX_NOT_READY")
            return "EN_INDEX_NOT_READY"
        revision = self._committed_revision(flow.worker, handoff)
        if revision is None:
            self._status("P2_CHECKPOINT_PENDING")
            # The TV may activate BEFORE the first paid window has committed.
            # Establish an empty authenticated feed now (GET returns 204),
            # then the original worker callback fills it with 120 cues.
            root, file, _ = self._cached_en(flow, fingerprint, handoff, media)
            self._current(media, current.tv_session_id, fingerprint)
            with self._lock:
                if media_key not in self._rolling:
                    if len(self._rolling) >= 16:
                        raise P3ReadyRejected("P4_ROLLING_REGISTRY_FULL")
                    self._rolling[media_key] = _RollingReceipt(
                        media, current.tv_session_id, fingerprint, media_key,
                        file, root, handoff.source_sha256, handoff.cue_count,
                        handoff.media_key, None)
            return "P2_CHECKPOINT_PENDING"
        try:
            self.publish_worker_revision(
                media=media, source_fingerprint=fingerprint,
                tv_session_id=current.tv_session_id, flow=flow,
                handoff=handoff, revision=revision)
            self._status("P2_CHECKPOINT_READY")
        except P3ReadyRejected as exc:
            # A live producer may have published a newer batch concurrently.
            if exc.args != ("P4_ROLLING_OLDER_REVISION",):
                raise

    @classmethod
    def _cached_en(cls, flow: object, fingerprint: str,
                   handoff: AssumedEnglishSubtitle,
                   media: Media | None = None) -> tuple[Path, Path, bytes]:
        root = cls._root(getattr(flow, "cache_root", None))
        if media is not None:
            dual = DualSubtitleCatalog(root).read(media, fingerprint, "ai_en")
            if dual is not None:
                raw = cls._file(root, dual.file,
                                sha=handoff.source_sha256, cues=handoff.cue_count)
                expected = prepare_local_translation_source(
                    CachedEnReceipt(dual.file, dual.sha256, dual.cues),
                    private_root=root)
                if (dual.sha256 != handoff.source_sha256
                        or dual.cues != handoff.cue_count
                        or expected.media_key != handoff.media_key
                        or expected.source_bytes != handoff.source_bytes):
                    raise P3ReadyRejected("P4_ROLLING_P2_SOURCE_MISMATCH")
                return root, dual.file, raw
        index = root / (".auto-source-" + fingerprint + ".json")
        try:
            if index.is_symlink() or not index.is_file() or index.stat().st_size > 512:
                raise P3ReadyRejected("P4_ROLLING_SOURCE_INDEX_MISSING")
            row = json.loads(index.read_text(encoding="utf-8"))
            if (not isinstance(row, dict)
                    or set(row) != {"schema", "file", "language", "sha256", "cues"}
                    or row["schema"] != "TTV-LOCAL-AUTO-SOURCE-V1"
                    or row["language"] != "en"
                    or not isinstance(row["file"], str)
                    or re.fullmatch(r"[0-9a-f]{64}\.srt", row["file"]) is None
                    or row["sha256"] != handoff.source_sha256
                    or row["cues"] != handoff.cue_count):
                raise P3ReadyRejected("P4_ROLLING_SOURCE_RECEIPT_INVALID")
            file = root / row["file"]
            raw = cls._file(
                root, file, sha=handoff.source_sha256,
                cues=handoff.cue_count)
            expected = prepare_local_translation_source(
                CachedEnReceipt(file, handoff.source_sha256, handoff.cue_count),
                private_root=root)
            if (expected.media_key != handoff.media_key
                    or expected.source_bytes != handoff.source_bytes
                    or raw != handoff.source_bytes):
                raise P3ReadyRejected("P4_ROLLING_P2_SOURCE_MISMATCH")
            return root, file, raw
        except P3ReadyRejected:
            raise
        except Exception:
            raise P3ReadyRejected("P4_ROLLING_SOURCE_NOT_VERIFIED") from None

    @staticmethod
    def _verified_revision(handoff: AssumedEnglishSubtitle,
                           revision: SubtitleRevision, media_key: str
                           ) -> SubtitleRevision:
        if (not isinstance(revision, SubtitleRevision)
                or revision.media_key != handoff.media_key
                or revision.source_sha256 != handoff.source_sha256
                or revision.fmt != handoff.fmt
                or revision.total_count != handoff.cue_count
                or type(revision.version) is not int or revision.version < 1
                or type(revision.translated_count) is not int
                or not 1 <= revision.translated_count <= handoff.cue_count
                or not isinstance(revision.payload, bytes)
                or hashlib.sha256(revision.payload).hexdigest() != revision.sha256):
            raise P3ReadyRejected("P4_ROLLING_REVISION_IDENTITY_INVALID")
        try:
            source = parse_cues(handoff.source_bytes, handoff.fmt)
            output = parse_cues(revision.payload, revision.fmt)
        except (ValueError, UnicodeError):
            raise P3ReadyRejected("P4_ROLLING_REVISION_PARSE_INVALID") from None
        if (not output or len(output) != revision.translated_count
                or output[-1].end_ms != revision.last_end_ms
                or any((a.number, a.start_ms, a.end_ms,
                         a.identifier, a.settings) !=
                        (b.number, b.start_ms, b.end_ms,
                         b.identifier, b.settings)
                       for a, b in zip(source, output))):
            raise P3ReadyRejected("P4_ROLLING_REVISION_TIMELINE_MISMATCH")
        return replace(revision, media_key=media_key)

    def publish_worker_revision(self, *, media: Media, source_fingerprint: str,
                                tv_session_id: str, flow: object,
                                handoff: AssumedEnglishSubtitle,
                                revision: SubtitleRevision) -> None:
        if not isinstance(media, Media) or not isinstance(handoff, AssumedEnglishSubtitle):
            raise P3ReadyRejected("P4_ROLLING_VERIFIED_MEDIA_REQUIRED")
        current = self._current(media, tv_session_id, source_fingerprint)
        key = p4_key_from_verified_current(media, current)
        root, file, _ = self._cached_en(flow, source_fingerprint, handoff, media)
        mapped = self._verified_revision(handoff, revision, key)
        # Do not register an old film after a long P2 provider call or I/O.
        latest = self._current(media, tv_session_id, source_fingerprint)
        if p4_key_from_verified_current(media, latest) != key:
            raise P3ReadyRejected("P4_ROLLING_NATIVE_MEDIA_KEY_CHANGED")
        with self._lock:
            receipt = self._rolling.get(key)
            if (receipt is None or receipt.tv_session != tv_session_id):
                if receipt is None and len(self._rolling) >= 16:
                    raise P3ReadyRejected("P4_ROLLING_REGISTRY_FULL")
                receipt = _RollingReceipt(
                    media, tv_session_id, source_fingerprint, key,
                    file, root, handoff.source_sha256, handoff.cue_count,
                    handoff.media_key, mapped)
                self._rolling[key] = receipt
            else:
                if (receipt.fingerprint != source_fingerprint
                        or receipt.source_sha256 != handoff.source_sha256
                        or receipt.worker_media_key != handoff.media_key):
                    raise P3ReadyRejected("P4_ROLLING_SOURCE_CHANGED")
                if receipt.latest is not None and mapped.version < receipt.latest.version:
                    raise P3ReadyRejected("P4_ROLLING_OLDER_REVISION")
                if (receipt.latest is not None and
                        mapped.version == receipt.latest.version
                        and mapped.sha256 != receipt.latest.sha256):
                    raise P3ReadyRejected("P4_ROLLING_REVISION_COLLISION")
                receipt.latest = mapped
            live_feeds: list[SessionRevisionFeed] = []
            for feed in receipt.feeds:
                try:
                    feed.publish(mapped)
                    live_feeds.append(feed)
                except ValueError:
                    # A stale/invalid per-TV feed does not poison the P2 job.
                    pass
            receipt.feeds = live_feeds

    def resolve_progressive(self, media_key: str
                            ) -> AuthenticatedProgressiveSource | None:
        status = self._restore_current_checkpoint(media_key)
        with self._lock:
            receipt = self._rolling.get(media_key)
        if receipt is None or receipt.media_key != media_key:
            # A generic fallthrough must not overwrite the *actual* reason
            # (e.g. TV/Owner media-key mismatch) in the flight recorder.
            if status not in ("FLOW_UNBOUND", "MEDIA_KEY_MISMATCH",
                              "EN_INDEX_NOT_READY"):
                self._status("ROLLING_FEED_MISSING")
            return None
        current = self._current(receipt.media, receipt.tv_session, receipt.fingerprint)
        if p4_key_from_verified_current(receipt.media, current) != media_key:
            raise P3ReadyRejected("P4_ROLLING_NATIVE_MEDIA_KEY_CHANGED")
        self._file(receipt.source_root, receipt.source_file,
                   sha=receipt.source_sha256, cues=receipt.source_cues)

        def subscribe(feed: SessionRevisionFeed) -> None:
            if (not isinstance(feed, SessionRevisionFeed)
                    or feed.media_key != media_key
                    or feed.source_sha256 != receipt.source_sha256):
                raise P3ReadyRejected("P4_ROLLING_FEED_IDENTITY_INVALID")
            current = self._current(receipt.media, receipt.tv_session, receipt.fingerprint)
            if p4_key_from_verified_current(receipt.media, current) != media_key:
                raise P3ReadyRejected("P4_ROLLING_NATIVE_MEDIA_KEY_CHANGED")
            with self._lock:
                live = self._rolling.get(media_key)
                if live is not receipt or len(live.feeds) >= 8:
                    raise P3ReadyRejected("P4_ROLLING_SUBSCRIBER_CHANGED")
                if live.latest is not None:
                    feed.publish(live.latest)
                live.feeds.append(feed)

        def refresh() -> None:
            # This runs only for an authenticated P4 GET. Revalidate current
            # film/consent and feed only pre-existing P2 checkpoints; a
            # missing callback must never strand the TV on an older revision.
            current = self._current(receipt.media, receipt.tv_session, receipt.fingerprint)
            if p4_key_from_verified_current(receipt.media, current) != media_key:
                raise P3ReadyRejected("P4_ROLLING_NATIVE_MEDIA_KEY_CHANGED")
            self._file(receipt.source_root, receipt.source_file,
                       sha=receipt.source_sha256, cues=receipt.source_cues)
            self._restore_current_checkpoint(media_key)
            latest = self._current(receipt.media, receipt.tv_session,
                                   receipt.fingerprint)
            if p4_key_from_verified_current(receipt.media, latest) != media_key:
                raise P3ReadyRejected("P4_ROLLING_NATIVE_MEDIA_KEY_CHANGED")

        return AuthenticatedProgressiveSource(
            media_key=media_key, source_sha256=receipt.source_sha256,
            subscribe=subscribe, refresh=refresh)

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
from progressive_handoff import SubtitleRevision
from matcher import Media
from p3_p4_media_key import p4_media_key
from p3_p4_ready_registry import P3OwnerReadyRegistry, P3ReadyRejected


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
    latest: SubtitleRevision
    feeds: list[SessionRevisionFeed] = field(default_factory=list)


class R2OwnerProgressiveRegistry(P3OwnerReadyRegistry):
    def __init__(self, *, read_verified_current_playback: Callable):
        super().__init__(
            read_verified_current_playback=read_verified_current_playback)
        self._rolling: dict[str, _RollingReceipt] = {}

    @classmethod
    def _cached_en(cls, flow: object, fingerprint: str,
                   handoff: AssumedEnglishSubtitle) -> tuple[Path, Path, bytes]:
        root = cls._root(getattr(flow, "cache_root", None))
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
        key = p4_media_key(media, vlc_selected=True)
        self._current(media, tv_session_id, source_fingerprint)
        root, file, _ = self._cached_en(flow, source_fingerprint, handoff)
        mapped = self._verified_revision(handoff, revision, key)
        # Do not register an old film after a long P2 provider call or I/O.
        self._current(media, tv_session_id, source_fingerprint)
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
                if mapped.version < receipt.latest.version:
                    raise P3ReadyRejected("P4_ROLLING_OLDER_REVISION")
                if (mapped.version == receipt.latest.version
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
        with self._lock:
            receipt = self._rolling.get(media_key)
        if receipt is None or receipt.media_key != media_key:
            return None
        self._current(receipt.media, receipt.tv_session, receipt.fingerprint)
        self._file(receipt.source_root, receipt.source_file,
                   sha=receipt.source_sha256, cues=receipt.source_cues)

        def subscribe(feed: SessionRevisionFeed) -> None:
            if (not isinstance(feed, SessionRevisionFeed)
                    or feed.media_key != media_key
                    or feed.source_sha256 != receipt.source_sha256):
                raise P3ReadyRejected("P4_ROLLING_FEED_IDENTITY_INVALID")
            self._current(receipt.media, receipt.tv_session, receipt.fingerprint)
            with self._lock:
                live = self._rolling.get(media_key)
                if live is not receipt or len(live.feeds) >= 8:
                    raise P3ReadyRejected("P4_ROLLING_SUBSCRIBER_CHANGED")
                feed.publish(live.latest)
                live.feeds.append(feed)

        return AuthenticatedProgressiveSource(
            media_key=media_key, source_sha256=receipt.source_sha256,
            subscribe=subscribe)

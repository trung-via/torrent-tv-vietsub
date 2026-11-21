"""Verified completed VI/EN->VI artifact -> EXISTING P4 signed receiver.

This registry is a consumer of the original owner V3→D1/D2→LEAN120 worker.
It never searches, downloads, translates, starts a server or accepts a wire
claim of subtitle readiness. A private, exact current TV snapshot authorizes
both registration AFTER the original worker returns and P4 activation LATER.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import sys
from threading import RLock
from typing import Callable

_POC = Path(__file__).resolve().parent.parent
for _sibling in ("p2-aisub", "p3-vietsub-trigger"):
    _path = str((_POC / _sibling).resolve())
    if _path not in sys.path:
        sys.path.insert(0, _path)

from automatic_vietsub_flow import AutoResult
from owner_selected_file_resolver import CurrentPlaying, _fingerprint
from p3_p4_media_key import p4_media_key
from matcher import Media
from verified_vietsub_ready import VerifiedVietsubReady
from automatic_lean120_worker import AutomaticLean120Worker, _job_fingerprint
from cached_en_direct_handoff import CachedEnReceipt, prepare_local_translation_source
from cue_pipeline import parse_cues

_SHA = re.compile(r"[a-f0-9]{64}\Z")
_SOURCE = re.compile(r"[a-f0-9]{64}\.srt\Z")
_ALLOWED = frozenset(("REQUESTED", "ON"))


class P3ReadyRejected(ValueError):
    """Owner-private sanitized HOLD; no media names or paths in error text."""


@dataclass(frozen=True)
class _Receipt:
    media: Media
    tv_session: str
    fingerprint: str
    media_key: str
    origin: str  # vi or en
    cache_root: Path
    finished_root: Path
    source_file: Path
    source_sha256: str
    total_cues: int
    finished_file: Path
    finished_sha256: str


class P3OwnerReadyRegistry:
    """Bounded in-process ready pointers; subtitle bytes remain owner-private.

    After owner restart a new verified viewer request must re-register source.
    This is NOT an independent persistent event queue or a second translator.
    """

    def __init__(self, *, read_verified_current_playback: Callable[[], CurrentPlaying]):
        if not callable(read_verified_current_playback):
            raise P3ReadyRejected("P3_READY_CURRENT_TV_SOURCE_REQUIRED")
        self._read = read_verified_current_playback
        self._lock = RLock()
        self._ready: dict[str, _Receipt] = {}

    def _current(self, media: Media, tv_session_id: str,
                 fingerprint: str) -> CurrentPlaying:
        try:
            current = self._read()
        except Exception:
            raise P3ReadyRejected("P3_READY_CURRENT_TV_MISSING") from None
        if (not isinstance(current, CurrentPlaying)
                or current.attested is not True or current.active is not True
                or current.kind not in ("PLAY_REQUEST_ACCEPTED",
                                        "NEXT_QUEUE_ITEM_ACCEPTED")
                or current.owner_auto_enabled is not True
                or current.media_rights_approved is not True
                or current.viewer_choice not in _ALLOWED
                or current.local_vi_state != "ABSENT"
                or current.tv_session_id != tv_session_id
                or current.server_id != media.server_profile_id
                or current.torrent_hash.lower() != media.torrent_hash.lower()
                or current.file_index != media.file_index
                or current.video_name != media.filename
                or _fingerprint(current.server_id,
                                current.torrent_hash, current.file_index)
                   != fingerprint):
            raise P3ReadyRejected("P3_READY_CURRENT_MEDIA_OR_CONSENT_CHANGED")
        return current

    @staticmethod
    def _root(root: Path) -> Path:
        if (not isinstance(root, Path) or not root.is_absolute()
                or root.is_symlink() or not root.is_dir()):
            raise P3ReadyRejected("P3_READY_PRIVATE_ROOT_REQUIRED")
        return root

    @classmethod
    def _file(cls, root: Path, file: Path, *, sha: str, cues: int) -> bytes:
        base = cls._root(root)
        if (not isinstance(file, Path) or not file.is_absolute()
                or file.is_symlink() or file.suffix.lower() != ".srt"
                or not _SHA.fullmatch(sha)
                or type(cues) is not int or cues < 1):
            raise P3ReadyRejected("P3_READY_FILE_IDENTITY_INVALID")
        try:
            canonical = file.resolve(strict=True)
            if (not canonical.is_relative_to(base.resolve(strict=True))
                    or not canonical.is_file()
                    or not 0 < canonical.stat().st_size <= 256 * 1024):
                raise P3ReadyRejected("P3_READY_FILE_OUTSIDE_ROOT")
            raw = canonical.read_bytes()
            if hashlib.sha256(raw).hexdigest() != sha:
                raise P3ReadyRejected("P3_READY_FILE_HASH_CHANGED")
            if len(parse_cues(raw, "srt")) != cues:
                raise P3ReadyRejected("P3_READY_CUE_COUNT_CHANGED")
            return raw
        except P3ReadyRejected:
            raise
        except Exception:
            raise P3ReadyRejected("P3_READY_PRIVATE_SOURCE_NOT_READY") from None

    @classmethod
    def _source(cls, *, flow: object, fingerprint: str,
                result: AutoResult) -> tuple[Path, str, str, int, bytes]:
        cache = cls._root(getattr(flow, "cache_root", None))
        index = cache / (".auto-source-" + fingerprint + ".json")
        try:
            if (index.is_symlink() or not index.is_file()
                    or not 0 < index.stat().st_size <= 512):
                raise P3ReadyRejected("P3_READY_SOURCE_INDEX_MISSING")
            row = json.loads(index.read_text("utf-8"))
        except P3ReadyRejected:
            raise
        except Exception:
            raise P3ReadyRejected("P3_READY_SOURCE_INDEX_INVALID") from None
        if (not isinstance(row, dict)
                or set(row) != {"schema","file","language","sha256","cues"}
                or row["schema"] != "TTV-LOCAL-AUTO-SOURCE-V1"
                or row["language"] not in ("vi", "en")
                or not isinstance(row["file"], str)
                or _SOURCE.fullmatch(row["file"]) is None
                or not isinstance(row["sha256"], str)
                or _SHA.fullmatch(row["sha256"]) is None
                or type(row["cues"]) is not int or row["cues"] < 1
                or row["cues"] != result.cue_count):
            raise P3ReadyRejected("P3_READY_SOURCE_RECEIPT_MISMATCH")
        if (row["language"] == "vi" and result.status != "VI_READY"
                or row["language"] == "en"
                   and (result.status != "VIETSUB_READY"
                        or result.translated_cues != row["cues"])):
            raise P3ReadyRejected("P3_READY_STATUS_LANGUAGE_MISMATCH")
        path = cache / row["file"]
        raw = cls._file(cache, path, sha=row["sha256"], cues=row["cues"])
        return path, row["language"], row["sha256"], row["cues"], raw

    @classmethod
    def _finished(cls, flow: object, *, source_file: Path, source_sha: str,
                  source_cues: int, source: bytes) -> tuple[Path, str]:
        worker = getattr(flow, "worker", None)
        if not isinstance(worker, AutomaticLean120Worker):
            raise P3ReadyRejected("P3_READY_EXISTING_LEAN120_WORKER_REQUIRED")
        cache = cls._root(getattr(flow, "cache_root", None))
        state = cls._root(worker.state_root)
        try:
            handoff = prepare_local_translation_source(
                CachedEnReceipt(source_file, source_sha, source_cues),
                private_root=cache)
            if handoff.source_bytes != source:
                raise P3ReadyRejected("P3_READY_EN_CHANGED")
            job = _job_fingerprint(handoff, worker.profile, worker.glossary)
            if not _SHA.fullmatch(job):
                raise P3ReadyRejected("P3_READY_P2_JOB_ID_INVALID")
            folder = state / job
            if folder.is_symlink() or not folder.is_dir():
                raise P3ReadyRejected("P3_READY_P2_COMPLETE_OUTPUT_MISSING")
            file = folder / "vi-final.srt"
            if not file.is_file() or file.is_symlink():
                raise P3ReadyRejected("P3_READY_P2_COMPLETE_OUTPUT_MISSING")
            payload = file.read_bytes()
            if (not 0 < len(payload) <= 256*1024
                    or len(parse_cues(payload, "srt")) != source_cues):
                raise P3ReadyRejected("P3_READY_P2_OUTPUT_INVALID")
            # Ensures full-film LEAN120 kept source IDs and timecodes; no
            # semantic language claim is made solely by this structural QA.
            original = parse_cues(source, "srt")
            translated = parse_cues(payload, "srt")
            if any((a.number, a.start_ms, a.end_ms, a.identifier, a.settings)
                   != (b.number, b.start_ms, b.end_ms, b.identifier, b.settings)
                   for a, b in zip(original, translated)):
                raise P3ReadyRejected("P3_READY_P2_TIMELINE_MISMATCH")
            return file, hashlib.sha256(payload).hexdigest()
        except P3ReadyRejected:
            raise
        except Exception:
            raise P3ReadyRejected("P3_READY_P2_OUTPUT_UNAVAILABLE") from None

    def register(self, *, media: Media, source_fingerprint: str,
                 tv_session_id: str, flow: object,
                 result: AutoResult) -> str | None:
        """Called ONLY after V3 original flow returns ready (not REVIEW)."""
        if not isinstance(result, AutoResult):
            raise P3ReadyRejected("P3_READY_ORIGINAL_RESULT_REQUIRED")
        if result.status not in ("VI_READY", "VIETSUB_READY"):
            return None
        if (not isinstance(media, Media)
                or type(source_fingerprint) is not str
                or not _SHA.fullmatch(source_fingerprint)
                or type(tv_session_id) is not str or not tv_session_id):
            raise P3ReadyRejected("P3_READY_V3_MEDIA_ID_REQUIRED")
        media_key = p4_media_key(media, vlc_selected=True)
        self._current(media, tv_session_id, source_fingerprint)
        source_file, origin, source_sha, cues, source = self._source(
            flow=flow, fingerprint=source_fingerprint, result=result)
        if origin == "vi":
            finished, sha = source_file, source_sha
        else:
            finished, sha = self._finished(
                flow, source_file=source_file, source_sha=source_sha,
                source_cues=cues, source=source)
        # Re-evaluate TV after potentially long private I/O. A→B after the
        # original AI call must NOT register a ready artifact for old A.
        self._current(media, tv_session_id, source_fingerprint)
        receipt = _Receipt(
            media=media, tv_session=tv_session_id,
            fingerprint=source_fingerprint, media_key=media_key,
            origin=origin,
            cache_root=self._root(getattr(flow, "cache_root", None)),
            finished_root=self._root(
                flow.worker.state_root if origin == "en"
                else getattr(flow, "cache_root", None)),
            source_file=source_file,
            source_sha256=source_sha, total_cues=cues,
            finished_file=finished, finished_sha256=sha)
        with self._lock:
            if media_key not in self._ready and len(self._ready) >= 16:
                raise P3ReadyRejected("P3_READY_REGISTRY_FULL")
            self._ready[media_key] = receipt
        return media_key

    def resolve(self, media_key: str) -> VerifiedVietsubReady:
        """Used as P4 authenticated_vietsub_factory, after device HMAC.

        Must re-read fresh paired Redmi status and owner TorrServer exact
        identity even when the finished VI artifact was cached previously.
        """
        with self._lock:
            receipt = self._ready.get(media_key)
        if receipt is None or receipt.media_key != media_key:
            raise P3ReadyRejected("P3_READY_NO_CURRENT_ACCEPTED_SOURCE")
        self._current(receipt.media, receipt.tv_session, receipt.fingerprint)
        source = self._file(receipt.cache_root, receipt.source_file,
                            sha=receipt.source_sha256, cues=receipt.total_cues)
        # The LEAN120 output is inside an owner-private P2 fingerprint
        # folder, never a provider reply or untrusted file URL.
        finished = self._file(receipt.finished_root,
                              receipt.finished_file,
                              sha=receipt.finished_sha256,
                              cues=receipt.total_cues)
        ready = VerifiedVietsubReady.from_verified_bytes(
            media_key=media_key, source_language=receipt.origin,
            source_bytes=source, vietsub_bytes=finished)
        self._current(receipt.media, receipt.tv_session, receipt.fingerprint)
        return ready

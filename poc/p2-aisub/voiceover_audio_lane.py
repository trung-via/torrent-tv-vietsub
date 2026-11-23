"""Opt-in audio catalog for the EXISTING paired P4 HTTPS listener.

Owner's one VieNeu consumer registers only committed 48-kHz cue WAV receipts.
Authenticated TV sessions may list signed cue offers and fetch verified WAVs;
neither operation calls AGY, TTS or creates another HTTP listener.
"""
from __future__ import annotations

import hashlib
import json
import re
from threading import Lock

from lan_revision_feed import SessionRevisionFeed
from voiceover_audio_store import AudioReceipt, VoiceoverWavStore
from voiceover_revision import NarrationCue, TranslationRevision, plan_voiceover
from voiceover_vieneu import DEFAULT_VOICE_CACHE_ID

_KEY = re.compile(r"[0-9a-f]{64}\Z")
_PAGE = 32
_MAX_ENTRIES = 8192
_MAX_WAV_BYTES = 3_000_000


class VoiceoverAudioLane:
    def __init__(self, *, store: VoiceoverWavStore,
                 voice_id: str = DEFAULT_VOICE_CACHE_ID) -> None:
        if not isinstance(store, VoiceoverWavStore):
            raise ValueError("P4_VOICE_STORE_REQUIRED")
        # Validate the local voice/cache identity before any model is loaded.
        if not isinstance(voice_id, str) or not re.fullmatch(
                r"[A-Za-z0-9_-]{1,64}", voice_id):
            raise ValueError("P4_VOICE_ID_INVALID")
        self.store = store
        self.voice_id = voice_id
        self._lock = Lock()
        # Native P4 media key and P2 worker media key differ in the R2 flow.
        # Bind only an already-verified film/source mapping, never by SHA alone.
        self._aliases: dict[tuple[str, str], str] = {}
        # TV session is deliberately NOT part of cache identity. Revisit A
        # reuses its WAV, but a stale session can never obtain its bytes.
        self._entries: dict[tuple[str, str, int],
                            tuple[TranslationRevision, NarrationCue, AudioReceipt]] = {}

    def bind_verified_media(self, *, worker_media_key: str,
                            tv_media_key: str, source_sha256: str) -> None:
        """Bind an R2-verified P2 film to the native P4 media identity.

        TTS WAV cache stays keyed by the worker's original media identity,
        preserving A→B→A reuse. TV offers are re-signed to the native key.
        """
        if (not isinstance(worker_media_key, str)
                or not re.fullmatch(r"media\.[0-9a-f]{64}", worker_media_key)
                or not isinstance(tv_media_key, str)
                or not re.fullmatch(r"media\.[0-9a-f]{64}", tv_media_key)
                or not isinstance(source_sha256, str)
                or not _KEY.fullmatch(source_sha256)):
            raise ValueError("P4_VOICE_MEDIA_BINDING_INVALID")
        key = (tv_media_key, source_sha256)
        with self._lock:
            old = self._aliases.get(key)
            if old is not None and old != worker_media_key:
                raise ValueError("P4_VOICE_MEDIA_BINDING_COLLISION")
            self._aliases[key] = worker_media_key

    def on_audio_ready(self, revision: TranslationRevision,
                       cue: NarrationCue, receipt: AudioReceipt) -> None:
        """Owner-only callback after TTS WAV has committed; no network I/O."""
        if not isinstance(cue, NarrationCue) or not isinstance(receipt, AudioReceipt):
            raise ValueError("P4_VOICE_RECEIPT_INVALID")
        plan = plan_voiceover(revision, voice_id=self.voice_id)
        if cue not in plan.new_cues or receipt.tts_key != cue.tts_key:
            raise ValueError("P4_VOICE_REVISION_CUE_MISMATCH")
        if self.store.read(cue) != receipt:
            raise ValueError("P4_VOICE_UNVERIFIED_RECEIPT")
        key = (revision.media_key, revision.source_sha256, cue.number)
        with self._lock:
            previous = self._entries.get(key)
            if previous is not None:
                prior_rev, prior_cue, prior_receipt = previous
                if revision.version < prior_rev.version:
                    return  # Older cumulative revision cannot replace the latest.
                if revision.version == prior_rev.version:
                    if cue != prior_cue or receipt != prior_receipt:
                        raise ValueError("P4_VOICE_REVISION_COLLISION")
                    return
            if previous is None and len(self._entries) >= _MAX_ENTRIES:
                raise ValueError("P4_VOICE_CATALOG_FULL")
            self._entries[key] = (revision, cue, receipt)

    def manifest(self, feed: SessionRevisionFeed, *, signer,
                 after_cue: int = 0) -> bytes:
        if not isinstance(feed, SessionRevisionFeed) or not callable(signer) \
                or type(after_cue) is not int or not 0 <= after_cue <= 100_000:
            raise ValueError("P4_VOICE_MANIFEST_REQUEST_INVALID")
        with self._lock:
            worker_key = self._aliases.get(
                (feed.media_key, feed.source_sha256), feed.media_key)
            rows = sorted(
                (number, entry)
                for (media, source, number), entry in self._entries.items()
                if media == worker_key and source == feed.source_sha256
                and number > after_cue
            )
            page = rows[:_PAGE]
        # Signed per-cue envelopes use exactly the EXISTING paired secret.
        offers = [
            vars(signer(feed, rev, receipt, self.voice_id))
            for _number, (rev, _cue, receipt) in page
        ]
        document = {
            "schema": "TTV-P4-VOICEOVER-MANIFEST-V1",
            "session_id": feed.session_id,
            "media_key": feed.media_key,
            "source_sha256": feed.source_sha256,
            "after_cue": after_cue,
            "more": len(rows) > len(page),
            "offers": offers,
        }
        return json.dumps(document, sort_keys=True,
                          separators=(",", ":")).encode("ascii")

    def audio_bytes(self, feed: SessionRevisionFeed,
                    tts_key: str) -> tuple[bytes, str] | None:
        """Return WAV and digest only for an exact registered media/source/key.

        The file is verified again on EVERY read; no arbitrary filename from
        the LAN request is used as a filesystem path.
        """
        if not isinstance(feed, SessionRevisionFeed) or not isinstance(tts_key, str) \
                or not _KEY.fullmatch(tts_key):
            return None
        with self._lock:
            worker_key = self._aliases.get(
                (feed.media_key, feed.source_sha256), feed.media_key)
            selected = next(
                (entry for (media, source, _n), entry in self._entries.items()
                 if media == worker_key and source == feed.source_sha256
                 and entry[1].tts_key == tts_key),
                None
            )
        if selected is None:
            return None
        _rev, cue, receipt = selected
        if self.store.read(cue) != receipt:
            raise ValueError("P4_VOICE_WAV_NO_LONGER_VERIFIED")
        path = self.store.root / receipt.filename
        if path.is_symlink() or not path.is_file() \
                or not 44 <= path.stat().st_size <= _MAX_WAV_BYTES:
            raise ValueError("P4_VOICE_WAV_INVALID")
        payload = path.read_bytes()
        if hashlib.sha256(payload).hexdigest() != receipt.wav_sha256:
            raise ValueError("P4_VOICE_WAV_CHANGED")
        return payload, receipt.wav_sha256

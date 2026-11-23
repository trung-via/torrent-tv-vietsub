"""Optional two-consumer handoff for the EXISTING R2 worker callback.

P4 is called synchronously first. A single optional non-blocking TTS slot
coalesces obsolete cumulative revisions; it never launches AGY or a listener.
Importing this module does not start threads, models or host work.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from threading import Lock
from typing import Callable

from voiceover_revision import TranslationRevision, plan_voiceover


class DualSubtitleVoiceConsumer:
    def __init__(
        self, *, subtitle_sink: Callable[[object, TranslationRevision], object],
        voice_sink: Callable[[TranslationRevision], object] | None = None,
        voice_id: str = "v3turbo_onnx_default",
        max_waiting_films: int = 4,
        status: Callable[[str], object] | None = None,
    ) -> None:
        if not callable(subtitle_sink) or (voice_sink is not None and not callable(voice_sink)):
            raise ValueError("VOICEOVER_SINK_INVALID")
        if type(max_waiting_films) is not int or not 1 <= max_waiting_films <= 8:
            raise ValueError("VOICEOVER_WAITING_FILMS_INVALID")
        self.subtitle_sink = subtitle_sink
        self.voice_sink = voice_sink
        self.voice_id = voice_id
        self.max_waiting_films = max_waiting_films
        self.status = status
        self._lock = Lock()
        self._pending: dict[tuple[str, str], TranslationRevision] = {}
        self._seen: dict[tuple[str, str], tuple[int, str]] = {}
        self._running = False
        self._closed = False
        self._executor: ThreadPoolExecutor | None = None

    def _note(self, code: str) -> None:
        if self.status is not None:
            try:
                self.status(code)
            except Exception:
                pass

    def callback(self, handoff: object, revision: TranslationRevision) -> object:
        """Use as `R2ProgressiveWorker.bind(consumer.callback)` on one Owner."""
        # Reject cross-film work before either consumer sees it.
        if getattr(handoff, "media_key", None) != getattr(revision, "media_key", None):
            raise ValueError("VOICEOVER_HANDOFF_MEDIA_MISMATCH")
        if getattr(handoff, "source_sha256", None) != getattr(revision, "source_sha256", None):
            raise ValueError("VOICEOVER_HANDOFF_SOURCE_MISMATCH")
        plan_voiceover(revision, voice_id=self.voice_id)
        # Even if P4 is unavailable, a committed P2 batch remains usable for
        # audio; do not treat P4 failure as a request to retranslate.
        try:
            return self.subtitle_sink(handoff, revision)
        finally:
            self.offer(revision)

    def offer(self, revision: TranslationRevision) -> None:
        """Queue a committed revision after an already-attempted P4 callback.

        This separate method lets the existing R2 processor keep its verified
        session gate without re-registering a second subtitle sink.
        """
        plan_voiceover(revision, voice_id=self.voice_id)
        if self.voice_sink is not None:
            self._offer(revision)

    def _offer(self, revision: TranslationRevision) -> None:
        key = revision.media_key, revision.source_sha256
        with self._lock:
            if self._closed:
                self._note("VOICEOVER_CLOSED_NO_SCHEDULE")
                return
            prior = self._seen.get(key)
            if prior is not None:
                version, digest = prior
                if revision.version < version:
                    self._note("VOICEOVER_STALE_REVISION_NOOP")
                    return
                if revision.version == version:
                    if revision.sha256 == digest:
                        return
                    self._note("VOICEOVER_REVISION_COLLISION_HOLD")
                    return
            if key not in self._pending and len(self._pending) >= self.max_waiting_films:
                self._note("VOICEOVER_BACKLOG_FULL_SUBTITLE_UNAFFECTED")
                return
            self._seen[key] = (revision.version, revision.sha256)
            self._pending[key] = revision
            if self._running:
                return
            self._running = True
            if self._executor is None:
                self._executor = ThreadPoolExecutor(max_workers=1,
                                                    thread_name_prefix="ttv-voice")
            self._executor.submit(self._drain)

    def _drain(self) -> None:
        while True:
            with self._lock:
                if not self._pending:
                    self._running = False
                    return
                key, revision = next(iter(self._pending.items()))
                del self._pending[key]
            try:
                if self.voice_sink is not None:
                    self.voice_sink(revision)
            except Exception:
                # TTS is lower priority and cannot invalidate committed P2/P4.
                self._note("VOICEOVER_TTS_HOLD_SUBTITLE_UNAFFECTED")

    def close(self, *, wait: bool = True) -> None:
        with self._lock:
            self._closed = True
            pool = self._executor
        if pool is not None:
            pool.shutdown(wait=wait)


class VieNeuBatchConsumer:
    """Owner-local sink: resume committed WAV cues and synthesize only missing."""

    def __init__(self, *, wav_store: object, tts: object, voice_id: str):
        self.wav_store = wav_store
        self.tts = tts
        self.voice_id = voice_id

    def __call__(self, revision: TranslationRevision) -> tuple[object, ...]:
        full = plan_voiceover(revision, voice_id=self.voice_id)
        keys = []
        receipts = []
        for cue in full.new_cues:
            present = self.wav_store.read(cue)
            if present is None:
                # Real VieNeu is optional: this method is only invoked by an
                # explicitly wired Owner, never by import or a TV GET.
                present, _ = self.wav_store.synthesize(cue, self.tts.stream(cue))
            receipts.append(present)
            keys.append(cue.tts_key)
        # Verification of all receipts is mandatory before claiming coverage.
        done = plan_voiceover(revision, voice_id=self.voice_id,
                              completed_keys=tuple(keys))
        if not done.is_caught_up:
            raise ValueError("VOICEOVER_COVERAGE_INCOMPLETE")
        return tuple(receipts)

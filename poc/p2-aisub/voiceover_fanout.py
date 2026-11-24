"""Optional two-consumer handoff for the EXISTING R2 worker callback.

P4 is called synchronously first. A single optional non-blocking TTS slot
coalesces obsolete cumulative revisions; it never launches AGY or a listener.
Importing this module does not start threads, models or host work.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from threading import Lock
from typing import Callable

from voiceover_revision import TranslationRevision, plan_voiceover, assess_voice_fit
from voiceover_vieneu import DEFAULT_VOICE_CACHE_ID


class DualSubtitleVoiceConsumer:
    def __init__(
        self, *, subtitle_sink: Callable[[object, TranslationRevision], object],
        voice_sink: Callable[[TranslationRevision], object] | None = None,
        voice_id: str = DEFAULT_VOICE_CACHE_ID,
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
        self._active_key: tuple[str, str] | None = None
        self._preferred: tuple[str, str] | None = None
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

    def prioritize(self, media_key: str, source_sha256: str) -> None:
        """Called only after verifying the currently selected TV film."""
        with self._lock:
            self._preferred = (media_key, source_sha256)

    def _should_yield(self, key: tuple[str, str]) -> bool:
        with self._lock:
            return self._preferred != key and self._preferred in self._pending

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
                    if revision.sha256 != digest:
                        self._note("VOICEOVER_REVISION_COLLISION_HOLD")
                        return
                    # Reoffering an unchanged revision after an earlier TTS
                    # failure must be possible. The WAV receipt/inflight
                    # check (not _seen) decides whether a provider call is safe.
                    if key in self._pending or key == self._active_key:
                        return
            if key not in self._pending and len(self._pending) >= self.max_waiting_films:
                if key != self._preferred:
                    self._note("VOICEOVER_BACKLOG_FULL_SUBTITLE_UNAFFECTED")
                    return
                # A new current film may displace only an in-memory pending
                # revision; its durable VI and WAVs remain recoverable.
                del self._pending[next(iter(self._pending))]
                self._note("VOICEOVER_BACKGROUND_DEFERRED")
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
                    self._active_key = None
                    return
                key = self._preferred if self._preferred in self._pending else next(iter(self._pending))
                revision = self._pending.pop(key)
                self._active_key = key
            try:
                if isinstance(self.voice_sink, VieNeuBatchConsumer):
                    _, interrupted = self.voice_sink.consume(
                        revision, should_yield=lambda: self._should_yield(key))
                    if interrupted:
                        with self._lock:
                            if key not in self._pending and len(self._pending) < self.max_waiting_films:
                                self._pending[key] = revision
                        self._note("VOICEOVER_YIELD_TO_CURRENT_FILM")
                elif self.voice_sink is not None:
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

    def __init__(self, *, wav_store: object, tts: object,
                 voice_id: str = DEFAULT_VOICE_CACHE_ID,
                 on_audio_ready: Callable[[TranslationRevision, object, object],
                                          object] | None = None,
                 status: Callable[[str], object] | None = None):
        if on_audio_ready is not None and not callable(on_audio_ready):
            raise ValueError("VOICEOVER_AUDIO_SINK_INVALID")
        self.wav_store = wav_store
        self.tts = tts
        self.voice_id = voice_id
        # Optional *already session-gated* consumer; no LAN or TV listener
        # is installed by this class.
        self.on_audio_ready = on_audio_ready
        self.status = status
        self._failures: dict[str, int] = {}

    def __call__(self, revision: TranslationRevision) -> tuple[object, ...]:
        receipts, _ = self.consume(revision)
        return receipts

    def consume(self, revision: TranslationRevision, *,
                should_yield: Callable[[], bool] = lambda: False
                ) -> tuple[tuple[object, ...], bool]:
        full = plan_voiceover(revision, voice_id=self.voice_id)
        receipts = []
        for cue in full.new_cues:
            if should_yield():
                return tuple(receipts), True
            try:
                present = self.wav_store.recover_local_attempt(cue)
                if present is None:
                    if self._failures.get(cue.tts_key, 0) >= 2:
                        continue
                    present, _ = self.wav_store.synthesize(cue, self.tts.stream(cue))
                self._failures.pop(cue.tts_key, None)
            except Exception as exc:
                self._failures[cue.tts_key] = self._failures.get(cue.tts_key, 0) + 1
                self._note("VOICEOVER_CUE_FAILED_" + type(exc).__name__.upper())
                continue
            receipts.append(present)
            # Release each verified cue as soon as its WAV is committed,
            # without waiting for the complete 50/120-cue batch.
            # Sink failures never discard successful audio or rerun AGY.
            if (self.on_audio_ready is not None
                    and assess_voice_fit(
                        cue_duration_ms=cue.end_ms - cue.start_ms,
                        audio_duration_ms=present.duration_ms) in ("PLAY_AS_IS", "TIME_STRETCH")):
                try:
                    self.on_audio_ready(revision, cue, present)
                except Exception:
                    self._note("VOICEOVER_AUDIO_REGISTRATION_FAILED")
            elif self.on_audio_ready is not None:
                self._note("VOICEOVER_CUE_TOO_LONG_ORIGINAL_AUDIO")
        if len(receipts) != full.translated_count:
            self._note("VOICEOVER_COVERAGE_PARTIAL")
        return tuple(receipts), False

    def _note(self, code: str) -> None:
        if self.status is not None:
            try:
                self.status(code)
            except Exception:
                pass

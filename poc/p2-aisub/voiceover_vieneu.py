"""Opt-in VieNeu ONNX/CPU adapter; no model is initialized on import.

A call to stream() may fetch SDK model weights on first use if they are not
already cached. This module is NOT the TV audio renderer or LAN publisher.
"""
from __future__ import annotations

from typing import Callable, Iterable

from voiceover_revision import NarrationCue


class VieNeuOnnxSession:
    """One reusable local TTS object, rather than one model load per cue."""

    def __init__(self, *, voice: str,
                 factory: Callable[[], object] | None = None) -> None:
        if not isinstance(voice, str) or not voice.strip():
            raise ValueError("VIENEU_VOICE_REQUIRED")
        if factory is not None and not callable(factory):
            raise ValueError("VIENEU_FACTORY_INVALID")
        self.voice = voice
        self._factory = factory
        self._engine: object | None = None

    def _open(self) -> object:
        if self._engine is None:
            if self._factory is not None:
                self._engine = self._factory()
            else:
                # Optional dependency: do not import, download or allocate GPU
                # in normal Owner startup, subtitle pipeline or offline CI.
                from vieneu import Vieneu
                self._engine = Vieneu(backend="onnx")
        return self._engine

    def stream(self, cue: NarrationCue) -> Iterable[object]:
        """Yield float32 PCM-like chunks per SDK; caller owns WAV encoding."""
        if (not isinstance(cue, NarrationCue) or not cue.text.strip()
                or cue.start_ms < 0 or cue.end_ms <= cue.start_ms):
            raise ValueError("VIENEU_TIMED_VI_CUE_REQUIRED")
        backend = self._open()
        produced = False
        for chunk in backend.infer_stream(cue.text, voice=self.voice):
            if chunk is None:
                raise ValueError("VIENEU_EMPTY_AUDIO_CHUNK")
            produced = True
            yield chunk
        if not produced:
            raise ValueError("VIENEU_EMPTY_STREAM")

    def close(self) -> None:
        if self._engine is not None:
            cleanup = getattr(self._engine, "close", None)
            if callable(cleanup):
                cleanup()
            self._engine = None

"""Private, crash-conscious WAV cache for approved Vietnamese narration cues.

No model import, provider calls, LAN listener or player side effects. The
caller invokes the approved VieNeu stream and supplies its sample chunks.
Only a complete validated waveform receives a success receipt.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import tempfile
import wave
from uuid import uuid4
from typing import Iterable

from voiceover_revision import NarrationCue

_KEY = re.compile(r"[0-9a-f]{64}\Z")
_SCHEMA = "TTV-VOICEOVER-WAV-RECEIPT-V1"
_MAX_SAMPLES = 1_440_000  # 30 seconds at 48 kHz
_MAX_BYTES = 3_000_000


@dataclass(frozen=True)
class AudioReceipt:
    tts_key: str
    wav_sha256: str
    sample_rate: int
    samples: int
    duration_ms: int
    start_ms: int
    end_ms: int
    filename: str


class VoiceoverWavStore:
    """Store one verified 48 kHz mono PCM16 WAV per cue, in a private root."""

    def __init__(self, root: Path, *, sample_rate: int = 48_000):
        if not isinstance(root, Path) or not root.is_absolute():
            raise ValueError("VOICEOVER_PRIVATE_ABSOLUTE_ROOT_REQUIRED")
        if type(sample_rate) is not int or sample_rate != 48_000:
            raise ValueError("VOICEOVER_V3_TURBO_SAMPLE_RATE_REQUIRED")
        if root.is_symlink():
            raise ValueError("VOICEOVER_ROOT_SYMLINK")
        self.root = root
        self.rate = sample_rate

    def _paths(self, cue: NarrationCue) -> tuple[Path, Path, Path]:
        if (not isinstance(cue, NarrationCue)
                or not isinstance(cue.tts_key, str)
                or not _KEY.fullmatch(cue.tts_key)
                or type(cue.number) is not int or cue.number < 1
                or cue.start_ms < 0 or cue.end_ms <= cue.start_ms):
            raise ValueError("VOICEOVER_CUE_INVALID")
        base = self.root / cue.tts_key
        return base.with_suffix(".wav"), base.with_suffix(".json"), base.with_suffix(".inflight")

    def _checked_file(self, path: Path) -> bool:
        if path.is_symlink():
            raise ValueError("VOICEOVER_CACHE_SYMLINK")
        return path.is_file()

    def read(self, cue: NarrationCue) -> AudioReceipt | None:
        wav, receipt, _ = self._paths(cue)
        w, r = self._checked_file(wav), self._checked_file(receipt)
        if not w and not r:
            return None
        if not w or not r or receipt.stat().st_size > 2048:
            raise ValueError("VOICEOVER_INCOMPLETE_CACHE_HOLD")
        try:
            row = json.loads(receipt.read_text("utf-8"))
            if (not isinstance(row, dict) or set(row) != {
                    "schema", "tts_key", "wav_sha256", "sample_rate",
                    "samples", "duration_ms", "start_ms", "end_ms", "filename"
            } or row["schema"] != _SCHEMA
                    or row["tts_key"] != cue.tts_key
                    or row["filename"] != wav.name
                    or row["sample_rate"] != self.rate
                    or type(row["samples"]) is not int
                    or not 0 < row["samples"] <= _MAX_SAMPLES
                    or row["duration_ms"] != max(1, (row["samples"] * 1000 + self.rate // 2) // self.rate)
                    or row["start_ms"] != cue.start_ms
                    or row["end_ms"] != cue.end_ms
                    or not isinstance(row["wav_sha256"], str)
                    or not _KEY.fullmatch(row["wav_sha256"])
                    or not 44 <= wav.stat().st_size <= _MAX_BYTES):
                raise ValueError("VOICEOVER_RECEIPT_MISMATCH")
            with wave.open(str(wav), "rb") as wf:
                if (wf.getnchannels() != 1 or wf.getsampwidth() != 2
                        or wf.getframerate() != self.rate
                        or wf.getnframes() != row["samples"]
                        or wf.getcomptype() != "NONE"):
                    raise ValueError("VOICEOVER_WAV_FORMAT_MISMATCH")
            if hashlib.sha256(wav.read_bytes()).hexdigest() != row["wav_sha256"]:
                raise ValueError("VOICEOVER_WAV_HASH_MISMATCH")
            return AudioReceipt(
                row["tts_key"], row["wav_sha256"], row["sample_rate"],
                row["samples"], row["duration_ms"], row["start_ms"],
                row["end_ms"], row["filename"]
            )
        except (OSError, UnicodeError, KeyError, TypeError, ValueError,
                wave.Error, json.JSONDecodeError):
            raise ValueError("VOICEOVER_CACHE_VERIFY_FAILED") from None

    def recover_local_attempt(self, cue: NarrationCue) -> AudioReceipt | None:
        """Single Owner TTS worker only; no concurrent synthesis of this cue.

        Unlike an uncertain paid AGY call, local PCM can be regenerated.
        Keep a verified success, quarantine only incomplete/invalid artifacts.
        The caller must bound retries and never invoke this from an HTTP read.
        """
        wav, receipt, marker = self._paths(cue)
        if self.root.is_symlink() or any(p.is_symlink() for p in (wav, receipt, marker)):
            raise ValueError("VOICEOVER_CACHE_SYMLINK")
        try:
            old = self.read(cue)
        except ValueError:
            old = None
        if old is not None:
            marker.unlink(missing_ok=True)
            return old
        suffix = ".invalid-" + uuid4().hex
        for path in (wav, receipt, marker):
            if path.is_file():
                path.rename(path.with_name(path.name + suffix))
        return None

    def synthesize(self, cue: NarrationCue, chunks: Iterable[Iterable[float]]
                   ) -> tuple[AudioReceipt, bool]:
        """Finalize stream chunks once. bool=True only when newly generated.

        A failed or interrupted stream retains .inflight; retry must be an
        explicit audited operation, not a duplicate model call on replay.
        """
        wav_path, json_path, marker = self._paths(cue)
        if self.root.is_symlink():
            raise ValueError("VOICEOVER_ROOT_SYMLINK")
        old = self.read(cue)
        if old is not None:
            return old, False
        if self._checked_file(marker):
            raise ValueError("VOICEOVER_INFLIGHT_UNKNOWN_HOLD")
        self.root.mkdir(parents=True, mode=0o700, exist_ok=True)
        if self.root.is_symlink():
            raise ValueError("VOICEOVER_ROOT_SYMLINK")
        with marker.open("x", encoding="ascii") as f:
            f.write("TTV-VOICEOVER-TTS-INFLIGHT-V1\n")
            f.flush()
            os.fsync(f.fileno())
        temp_name = None
        try:
            with tempfile.NamedTemporaryFile(mode="wb", suffix=".tmp",
                                             prefix=".voice-", dir=self.root,
                                             delete=False) as f:
                temp_name = f.name
                samples = 0
                with wave.open(f, "wb") as wf:
                    wf.setnchannels(1)
                    wf.setsampwidth(2)
                    wf.setframerate(self.rate)
                    for chunk in chunks:
                        if isinstance(chunk, (str, bytes, bytearray)):
                            raise ValueError("VOICEOVER_PCM_CHUNK_INVALID")
                        packet = bytearray()
                        for value in chunk:
                            if isinstance(value, (str, bytes, bool)):
                                raise ValueError("VOICEOVER_PCM_SAMPLE_INVALID")
                            v = float(value)
                            if not math.isfinite(v) or abs(v) > 1.0:
                                raise ValueError("VOICEOVER_PCM_RANGE_INVALID")
                            samples += 1
                            if samples > _MAX_SAMPLES:
                                raise ValueError("VOICEOVER_AUDIO_TOO_LONG")
                            packet.extend(struct.pack("<h", max(-32768, min(32767,
                                                    int(round(v * 32767))))))
                        wf.writeframesraw(packet)
                    if samples == 0:
                        raise ValueError("VOICEOVER_EMPTY_AUDIO")
                f.flush()
                os.fsync(f.fileno())
            payload = Path(temp_name).read_bytes()
            if len(payload) > _MAX_BYTES:
                raise ValueError("VOICEOVER_AUDIO_TOO_LARGE")
            digest = hashlib.sha256(payload).hexdigest()
            os.link(temp_name, wav_path)  # never overwrite an earlier success
            duration = max(1, (samples * 1000 + self.rate // 2) // self.rate)
            row = {
                "schema": _SCHEMA, "tts_key": cue.tts_key,
                "wav_sha256": digest, "sample_rate": self.rate,
                "samples": samples, "duration_ms": duration,
                "start_ms": cue.start_ms, "end_ms": cue.end_ms,
                "filename": wav_path.name
            }
            with json_path.open("x", encoding="utf-8") as f:
                json.dump(row, f, sort_keys=True, separators=(",", ":"))
                f.flush()
                os.fsync(f.fileno())
            # Do not declare TTS success until both committed files verify.
            outcome = self.read(cue)
            if outcome is None:
                raise ValueError("VOICEOVER_COMMIT_NOT_VERIFIED")
            marker.unlink()
            return outcome, True
        finally:
            if temp_name is not None:
                Path(temp_name).unlink(missing_ok=True)
            # On ANY unknown outcome, keep .inflight to prevent auto-replay.

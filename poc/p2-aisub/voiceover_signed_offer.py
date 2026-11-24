"""Typed signed narration *manifest* for the existing P4 paired session.

This is a metadata control contract only. WAV bytes are NOT embedded in
subtitle JSON, and this module never opens an HTTP listener or player.
The existing owner-only HTTPS handler and OMP must implement authenticated
audio GET + native playback separately before any audible-TV PASS.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
import hashlib
import hmac
import json
import re
from typing import Callable

from voiceover_audio_store import AudioReceipt
from voiceover_revision import TranslationRevision, plan_voiceover

_MEDIA = re.compile(r"media\.[0-9a-f]{64}\Z")
_SHA = re.compile(r"[0-9a-f]{64}\Z")
_SESSION = re.compile(r"[A-Za-z0-9_-]{16,80}\Z")
_SCHEMA = "TTV-P4-VOICEOVER-OFFER-V1"


@dataclass(frozen=True)
class SignedVoiceoverOffer:
    schema: str
    session_id: str
    media_key: str
    source_sha256: str
    subtitle_version: int
    voice_id: str
    cue_number: int
    start_ms: int
    end_ms: int
    tts_key: str
    wav_sha256: str
    sample_rate: int
    duration_ms: int
    signature: str


def _canonical(offer: SignedVoiceoverOffer) -> bytes:
    fields = vars(offer).copy()
    fields.pop("signature")
    return json.dumps(fields, ensure_ascii=True, sort_keys=True,
                      separators=(",", ":")).encode("ascii")


def _validate(offer: SignedVoiceoverOffer, secret: bytes) -> None:
    if (not isinstance(offer, SignedVoiceoverOffer)
            or offer.schema != _SCHEMA
            or not isinstance(offer.session_id, str)
            or not _SESSION.fullmatch(offer.session_id)
            or not isinstance(offer.media_key, str)
            or not _MEDIA.fullmatch(offer.media_key)
            or not isinstance(offer.source_sha256, str)
            or not _SHA.fullmatch(offer.source_sha256)
            or not isinstance(offer.tts_key, str)
            or not _SHA.fullmatch(offer.tts_key)
            or not isinstance(offer.wav_sha256, str)
            or not _SHA.fullmatch(offer.wav_sha256)
            or not isinstance(offer.signature, str)
            or not _SHA.fullmatch(offer.signature)
            or not isinstance(offer.voice_id, str)
            or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", offer.voice_id)
            or type(offer.subtitle_version) is not int
            or offer.subtitle_version < 1
            or type(offer.cue_number) is not int
            or offer.cue_number < 1
            or type(offer.start_ms) is not int
            or offer.start_ms < 0
            or type(offer.end_ms) is not int
            or offer.end_ms <= offer.start_ms
            or offer.sample_rate != 48_000
            or type(offer.duration_ms) is not int
            or offer.duration_ms <= 0
            or not isinstance(secret, bytes)
            or len(secret) < 16):
        raise ValueError("P4_VOICE_OFFER_INVALID")


def _sign(offer: SignedVoiceoverOffer, secret: bytes) -> str:
    return hmac.new(secret, b"TTV-P4-VOICEOVER-V1\n" + _canonical(offer),
                    hashlib.sha256).hexdigest()


def sign_voiceover_offer(
    *, revision: TranslationRevision, receipt: AudioReceipt,
    voice_id: str, session_id: str, pairing_secret: bytes,
    delivery_media_key: str | None = None,
) -> SignedVoiceoverOffer:
    """The source is a real committed subtitle revision and matching WAV."""
    if not isinstance(receipt, AudioReceipt):
        raise ValueError("P4_VOICE_COMMITTED_RECEIPT_REQUIRED")
    plan = plan_voiceover(revision, voice_id=voice_id)
    cue = next((c for c in plan.new_cues if c.tts_key == receipt.tts_key), None)
    if (cue is None or receipt.start_ms != cue.start_ms
            or receipt.end_ms != cue.end_ms
            or receipt.sample_rate != 48_000):
        raise ValueError("P4_VOICE_CUE_OR_SOURCE_MISMATCH")
    delivered = revision.media_key if delivery_media_key is None else delivery_media_key
    if not isinstance(delivered, str) or not _MEDIA.fullmatch(delivered):
        raise ValueError("P4_VOICE_DELIVERY_MEDIA_KEY_INVALID")
    unsigned = SignedVoiceoverOffer(
        schema=_SCHEMA, session_id=session_id, media_key=delivered,
        source_sha256=revision.source_sha256, subtitle_version=revision.version,
        voice_id=voice_id, cue_number=cue.number, start_ms=cue.start_ms,
        end_ms=cue.end_ms, tts_key=cue.tts_key,
        wav_sha256=receipt.wav_sha256, sample_rate=receipt.sample_rate,
        duration_ms=receipt.duration_ms, signature="0" * 64)
    _validate(unsigned, pairing_secret)
    return replace(unsigned, signature=_sign(unsigned, pairing_secret))


class PairedVoiceoverReceiver:
    """Pure proof that a TV receiver can reject stale/off/other-film offers."""

    def __init__(self, *, session_id: str, media_key: str,
                 source_sha256: str, pairing_secret: bytes):
        self._session = session_id
        self._media = media_key
        self._source = source_sha256
        self._secret = pairing_secret
        self._seen: dict[str, str] = {}

    def reset_for_seek(self, *, active_session: str,
                       active_media_key: str) -> None:
        """Only the same active paired player may re-arm already heard cues."""
        if active_session != self._session or active_media_key != self._media:
            raise ValueError("P4_VOICE_SEEK_WRONG_SESSION_OR_MEDIA")
        self._seen.clear()

    def receive(self, offer: SignedVoiceoverOffer, *,
                active_session: str, active_media_key: str,
                presentation_mode: str, on_native_audio: Callable[
                    [SignedVoiceoverOffer], bool]) -> str:
        _validate(offer, self._secret)
        if not hmac.compare_digest(_sign(offer, self._secret), offer.signature):
            raise ValueError("P4_VOICE_SIGNATURE_INVALID")
        if (offer.session_id != self._session
                or offer.media_key != self._media
                or offer.source_sha256 != self._source
                or active_session != self._session
                or active_media_key != self._media):
            raise ValueError("P4_VOICE_STALE_SESSION_OR_MEDIA")
        if presentation_mode not in ("VOICE", "BOTH"):
            return "DEFERRED_USER_AUDIO_CHOICE"
        if offer.tts_key in self._seen:
            if self._seen[offer.tts_key] == offer.wav_sha256:
                return "DUPLICATE_NOOP"
            raise ValueError("P4_VOICE_KEY_COLLISION")
        try:
            applied = on_native_audio(offer)
        except Exception:
            applied = False
        if applied is not True:
            return "AUDIO_APPLY_FAILED_NO_ACK"
        self._seen[offer.tts_key] = offer.wav_sha256
        return "AUDIO_MANIFEST_ACCEPTED"

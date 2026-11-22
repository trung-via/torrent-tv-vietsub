"""Pure P2→P4/G2 delivery contract, no network or Android side effects.

A publisher creates a signed revision offer for a separately paired TV session.
A receiver validates the offer and invokes an injected, trusted *G2 apply*
callback only for the currently playing media when the viewer selected ON.

This is an in-memory contract test seam. Pairing/key storage, network transport,
native Android receiver and PlayerActivity/VLC reload are NOT implemented.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import hmac
import json
import re
from typing import Callable

from cue_pipeline import parse_cues
from progressive_handoff import MAX_TV_BYTES, SubtitleRevision

_SESSION = re.compile(r"[A-Za-z0-9_-]{16,80}\Z")
_MEDIA = re.compile(r"media\.[0-9a-f]{64}\Z")
_SHA = re.compile(r"[0-9a-f]{64}\Z")
MAX_VERSION = 1_000_000
MIN_PAIRING_SECRET_BYTES = 16


@dataclass(frozen=True)
class SignedSubtitleOffer:
    session_id: str
    media_key: str
    source_sha256: str
    version: int
    fmt: str
    translated_count: int
    total_count: int
    last_end_ms: int
    payload_sha256: str
    payload: bytes
    signature: str


def _validated_offer(offer: SignedSubtitleOffer) -> None:
    if not isinstance(offer, SignedSubtitleOffer):
        raise ValueError("P4_OFFER_SHAPE_INVALID")
    if not isinstance(offer.session_id, str) or not _SESSION.fullmatch(offer.session_id):
        raise ValueError("P4_SESSION_ID_INVALID")
    if not isinstance(offer.media_key, str) or not _MEDIA.fullmatch(offer.media_key):
        raise ValueError("P4_MEDIA_KEY_INVALID")
    if not isinstance(offer.source_sha256, str) or not _SHA.fullmatch(offer.source_sha256):
        raise ValueError("P4_SOURCE_HASH_INVALID")
    if not isinstance(offer.payload_sha256, str) or not _SHA.fullmatch(offer.payload_sha256):
        raise ValueError("P4_PAYLOAD_HASH_INVALID")
    if not isinstance(offer.signature, str) or not _SHA.fullmatch(offer.signature):
        raise ValueError("P4_SIGNATURE_INVALID")
    if type(offer.version) is not int or not 1 <= offer.version <= MAX_VERSION:
        raise ValueError("P4_VERSION_INVALID")
    if offer.fmt not in ("srt", "vtt"):
        raise ValueError("P4_FORMAT_INVALID")
    if (type(offer.translated_count) is not int
        or type(offer.total_count) is not int
        or offer.translated_count < 1
        or offer.translated_count > offer.total_count
        or offer.total_count > 2000):
        raise ValueError("P4_CUE_COUNT_INVALID")
    if type(offer.last_end_ms) is not int or offer.last_end_ms <= 0:
        raise ValueError("P4_HORIZON_INVALID")
    if not isinstance(offer.payload, bytes) or not 0 < len(offer.payload) <= MAX_TV_BYTES:
        raise ValueError("P4_SIZE_INVALID")
    if hashlib.sha256(offer.payload).hexdigest() != offer.payload_sha256:
        raise ValueError("P4_PAYLOAD_HASH_MISMATCH")
    try:
        parsed = parse_cues(offer.payload, offer.fmt)
    except (ValueError, UnicodeError) as exc:
        raise ValueError("P4_SUBTITLE_PARSE_INVALID") from None
    if len(parsed) != offer.translated_count or parsed[-1].end_ms != offer.last_end_ms:
        raise ValueError("P4_SUBTITLE_METADATA_MISMATCH")


def _key(secret: bytes) -> bytes:
    if not isinstance(secret, bytes) or len(secret) < MIN_PAIRING_SECRET_BYTES:
        raise ValueError("P4_PAIRING_SECRET_REQUIRED")
    return secret


def _signature(offer: SignedSubtitleOffer, secret: bytes) -> str:
    fields = {
        "v": "TTV-P4-SUBTITLE-V1",
        "session_id": offer.session_id,
        "media_key": offer.media_key,
        "source_sha256": offer.source_sha256,
        "version": offer.version,
        "fmt": offer.fmt,
        "translated_count": offer.translated_count,
        "total_count": offer.total_count,
        "last_end_ms": offer.last_end_ms,
        "payload_sha256": offer.payload_sha256,
    }
    canon = json.dumps(fields, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hmac.new(_key(secret), canon.encode("ascii"), hashlib.sha256).hexdigest()


def sign_revision(revision: SubtitleRevision, session_id: str, secret: bytes) -> SignedSubtitleOffer:
    """Build one immutable, content-bound candidate for a locally paired TV."""
    if not isinstance(revision, SubtitleRevision):
        raise ValueError("P4_REVISION_REQUIRED")
    unsigned = SignedSubtitleOffer(
        session_id=session_id,
        media_key=revision.media_key,
        source_sha256=revision.source_sha256,
        version=revision.version,
        fmt=revision.fmt,
        translated_count=revision.translated_count,
        total_count=revision.total_count,
        last_end_ms=revision.last_end_ms,
        payload_sha256=revision.sha256,
        payload=revision.payload,
        signature="0" * 64,
    )
    _validated_offer(unsigned)
    return SignedSubtitleOffer(**{**vars(unsigned), "signature": _signature(unsigned, secret)})


class PairedSubtitleReceiver:
    """Simulate the authorization gate in front of future G2 native refresh.

    No background task, file writes, download, socket, Android/TV call, or
    manual picker is implemented. Any real native implementation must retain
    these checks and must not bypass the viewer's OFF/OTHER choice.
    """

    def __init__(
        self, *, session_id: str, media_key: str, source_sha256: str, pairing_secret: bytes
    ) -> None:
        if not isinstance(session_id, str) or not _SESSION.fullmatch(session_id):
            raise ValueError("P4_SESSION_ID_INVALID")
        if not isinstance(media_key, str) or not _MEDIA.fullmatch(media_key):
            raise ValueError("P4_MEDIA_KEY_INVALID")
        if not isinstance(source_sha256, str) or not _SHA.fullmatch(source_sha256):
            raise ValueError("P4_SOURCE_HASH_INVALID")
        self.session_id = session_id
        self.media_key = media_key
        self.source_sha256 = source_sha256
        self._secret = _key(pairing_secret)
        self.last_version = 0
        self.last_digest: str | None = None

    def receive(
        self,
        offer: SignedSubtitleOffer, *, active_session: str,
        active_media_key: str, subtitles_choice: str, engine: str,
        on_g2_apply: Callable[[bytes, str], bool],
    ) -> str:
        _validated_offer(offer)
        if (offer.session_id != self.session_id
            or offer.media_key != self.media_key
            or offer.source_sha256 != self.source_sha256
            or active_session != self.session_id
            or active_media_key != self.media_key):
            raise ValueError("P4_SESSION_OR_MEDIA_MISMATCH")
        if not hmac.compare_digest(_signature(offer, self._secret), offer.signature):
            raise ValueError("P4_AUTHENTICATION_FAILED")
        if type(offer.version) is not int or offer.version < self.last_version:
            raise ValueError("P4_STALE_REVISION")
        if offer.version == self.last_version:
            if self.last_digest == offer.payload_sha256:
                return "DUPLICATE_NOOP"
            raise ValueError("P4_REVISION_COLLISION")
        if engine != "VLC":
            return "DEFERRED_UNSUPPORTED_ENGINE"
        if subtitles_choice != "ON":
            return "DEFERRED_USER_SUBTITLE_CHOICE"
        try:
            ok = on_g2_apply(offer.payload, offer.fmt)
        except Exception:
            ok = False
        if ok is not True:
            return "G2_APPLY_FAILED_RETAIN_LAST_VALID"
        self.last_version = offer.version
        self.last_digest = offer.payload_sha256
        return "APPLIED_TO_G2"

"""P3-TRIGGER source-only playback activation gate.

A deterministic policy layer between an ALREADY authenticated OMP TV playback
selection and Draft #140 AutomaticVietsubFlow.selected_media(video_name).

This is NOT a TV event subscriber, host service, credential provider, network
client, D3 media-binding attestation or P4 receiver. Its 'attested' argument
is a caller-provided assertion, never cryptographic verification by itself.
It does not call OpenSubtitles/Gemini or any network/file APIs.
"""
from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import re

_TRIGGER_EVENTS = frozenset({"PLAY_REQUEST_ACCEPTED", "NEXT_QUEUE_ITEM_ACCEPTED"})
_HASH = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", re.ASCII)
_OPAQUE = re.compile(r"[A-Za-z0-9_-]{1,128}", re.ASCII)


@dataclass(frozen=True)
class PlaybackSelected:
    # All values must originate from the same authenticated, current TV
    # PlayRequest + selected QueueItem and an attested TorrServer metadata read.
    kind: str
    attested: bool
    active: bool
    server_id: str
    tv_session_id: str
    torrent_hash: str
    file_index: int
    video_name: str
    owner_auto_enabled: bool
    subtitle_choice: str  # ON | OFF | OTHER
    media_rights_approved: bool
    local_vi_state: str  # PRESENT | ABSENT | UNKNOWN


@dataclass(frozen=True)
class TriggerDecision:
    status: str  # DISPATCH | SKIP | HOLD | WAIT
    reason: str
    # Local correlation only; never valid as a D3/P4 authenticated media key.
    local_fingerprint: str | None = None


def evaluate_playback(event: PlaybackSelected) -> TriggerDecision:
    """A PLAY selection, not a library-add or pause/seek, is authoritative.

    This pure decision *cannot verify* TV pairing/HMAC, server ownership or
    media bytes. All those checks belong to the trusted runtime adapter.
    """
    if not isinstance(event, PlaybackSelected):
        return TriggerDecision("HOLD", "MALFORMED_EVENT")
    if event.kind not in _TRIGGER_EVENTS:
        return TriggerDecision("SKIP", "NOT_A_PLAYBACK_SELECTION")
    if event.attested is not True or event.active is not True:
        return TriggerDecision("HOLD", "UNATTESTED_OR_STALE_SELECTION")
    if (not isinstance(event.server_id, str)
            or _OPAQUE.fullmatch(event.server_id) is None
            or not isinstance(event.tv_session_id, str)
            or _OPAQUE.fullmatch(event.tv_session_id) is None
            or not isinstance(event.torrent_hash, str)
            or _HASH.fullmatch(event.torrent_hash.lower()) is None
            or type(event.file_index) is not int or event.file_index < 0
            or not isinstance(event.video_name, str)
            or len(event.video_name) > 255 or not event.video_name.strip()
            or "/" in event.video_name or "\\" in event.video_name
            or any(ord(ch) < 32 or ord(ch) == 127 for ch in event.video_name)):
        return TriggerDecision("HOLD", "MEDIA_IDENTITY_UNVERIFIED")
    if event.owner_auto_enabled is not True:
        return TriggerDecision("SKIP", "OWNER_AUTO_DISABLED")
    if event.subtitle_choice not in ("ON", "OFF", "OTHER"):
        return TriggerDecision("HOLD", "SUBTITLE_CHOICE_UNKNOWN")
    if event.subtitle_choice != "ON":
        return TriggerDecision("SKIP", "VIEWER_OFF_OR_OTHER")
    if event.media_rights_approved is not True:
        return TriggerDecision("HOLD", "MEDIA_POLICY_NOT_APPROVED")
    if event.local_vi_state == "UNKNOWN":
        return TriggerDecision("WAIT", "CHECK_LOCAL_VI_TRACKS")
    if event.local_vi_state == "PRESENT":
        return TriggerDecision("SKIP", "REUSE_EXISTING_VI")
    if event.local_vi_state != "ABSENT":
        return TriggerDecision("HOLD", "VI_TRACK_STATUS_INVALID")
    # Correlation key includes server+infohash+exact selected file. Deliberately
    # NOT derived solely from filename as in Draft #140's local cache index.
    parts = (
        event.server_id,
        event.torrent_hash.lower(),
        str(event.file_index),
    )
    fingerprint = sha256("\x00".join(parts).encode("utf-8")).hexdigest()
    return TriggerDecision("DISPATCH", "SEARCH_VI_FAST_THEN_EN", fingerprint)


class ActivationDeduplicator:
    """One in-process last-seen event token; no second worker/queue/cache.

    After a process restart, Draft #140's persistent source+LEAN120 checkpoints
    remain the authoritative protection against duplicate provider/model calls.
    """
    def __init__(self) -> None:
        self._last: tuple[str, str] | None = None

    def consider(self, event: PlaybackSelected) -> TriggerDecision:
        decision = evaluate_playback(event)
        if decision.status != "DISPATCH":
            return decision
        token = (event.tv_session_id, decision.local_fingerprint or "")
        if token == self._last:
            return TriggerDecision("SKIP", "DUPLICATE_CURRENT_PLAY_EVENT",
                                   decision.local_fingerprint)
        self._last = token
        return decision

    def on_session_closed(self) -> None:
        self._last = None

"""Pure P3 signed signal → existing authenticated P3-TRIGGER owner queue.

The signer proves only paired-device origin of the signal. The configured
owner-local read_current callback MUST independently inspect CURRENT OMP/P4
TV state, viewer setting and selected TorrServer file. No server/TV APIs are
implemented here; this class cannot mint attestation or bypass OFF/OTHER.

No HTTP listener, port binding, background service, credential storage,
download or provider calls. An existing owner HTTPS endpoint calls on_wire().
"""
from __future__ import annotations

from pathlib import Path
from typing import Callable

from activation_gate import PlaybackSelected, TriggerDecision
from trusted_playback_to_owner import TrustedPlaybackToOwner
from p3_signed_playback_signal import (
    SignedPlaybackError, SignedPlaybackVerifier,
)


class SignedP3ToOwner:
    def __init__(
        self, *,
        verifier: SignedPlaybackVerifier, owner_root: Path,
        read_verified_current_selection: Callable[[], PlaybackSelected],
        emit: Callable[[str], object] | None = None,
    ) -> None:
        if (not isinstance(verifier, SignedPlaybackVerifier)
                or not callable(read_verified_current_selection)):
            raise ValueError("P3_TRUSTED_OWNER_SOURCE_REQUIRED")
        self._verifier = verifier
        self._read = read_verified_current_selection
        self._bridge = TrustedPlaybackToOwner(
            owner_root=owner_root,
            read_verified_current_playback=self._read,
            emit=emit)

    def on_wire(self, body: bytes, *, now_ms: int | None = None) -> TriggerDecision:
        """A single already scoped HTTPS request from paired TV.

        HMAC is verified BEFORE any owner event or provider action. An event
        does not carry title/video filename; owner trusted source resolves
        it from exact current server/hash/fileIndex metadata.
        """
        try:
            signal = self._verifier.verify(body, now_ms=now_ms)
        except SignedPlaybackError:
            return TriggerDecision("HOLD", "SIGNED_TV_MESSAGE_INVALID")
        if signal.kind == "PLAYBACK_CLOSED":
            # A close does not enqueue source work. Last authenticated TV state
            # and D3/P4 delivery checks still independently enforce OFF/stale.
            self._bridge.on_session_closed()
            return TriggerDecision("SKIP", "TV_PLAYBACK_CLOSED")
        try:
            current = self._read()
        except Exception:
            return TriggerDecision("HOLD", "OWNER_CURRENT_TV_READ_FAILED")
        if (not isinstance(current, PlaybackSelected)
                or current.attested is not True
                or current.active is not True
                or current.kind != signal.kind
                or current.tv_session_id != signal.tv_session_id
                or current.torrent_hash.lower() != signal.torrent_hash
                or current.file_index != signal.file_index):
            return TriggerDecision("HOLD", "TV_SIGNAL_CURRENT_SELECTION_MISMATCH")
        # The existing P3 gate still enforces owner consent, viewer ON,
        # rights, local VI and exact media. It will read the source again;
        # no trust/filename from the signed event is injected into gate.
        return self._bridge.on_current_selection_accepted()

    def on_session_closed(self) -> None:
        self._bridge.on_session_closed()

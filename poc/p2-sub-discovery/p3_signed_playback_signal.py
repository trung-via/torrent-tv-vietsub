"""P3 signed OMP TV selection request: authenticated DATA, never a command.

An owner-controlled HTTPS handler may call SignedPlaybackVerifier.verify(raw),
then independently read the paired Windows TorrServer selected-file metadata and
the CURRENT viewer/P4 mode before scheduling an existing V3 owner event.

This module has NO socket/listener or route registrations, opens NO network,
starts NO owner process, and sends NO provider/translation/TV commands.
Signatures reuse a *separately approved P4 device pairing secret*, but use a
domain-separated HMAC input so P3 auth cannot impersonate P4 requests.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import hmac
import json
import re
import time

from p3_owner_replay_journal import OwnerReplayJournal, ReplayJournalRejected

SCHEMA = "TTV-P3-TV-SELECTION-V1"
VALID_KINDS = frozenset({
    "PLAY_REQUEST_ACCEPTED", "NEXT_QUEUE_ITEM_ACCEPTED",
    "PLAYBACK_CLOSED", "VIEWER_VIETSUB_REQUESTED",
})
_KEYS = frozenset({
    "schema", "kind", "tv_session_id", "torrent_hash", "file_index",
    "sent_at_ms", "nonce", "signature",
})
_SESSION = re.compile(r"[a-f0-9]{32}\Z")
_HASH = re.compile(r"(?:[a-f0-9]{40}|[a-f0-9]{64})\Z")
_AUTH = re.compile(r"[a-f0-9]{64}\Z")
MAX_WIRE_BYTES = 1024
MAX_CLOCK_SKEW_MS = 15000


class SignedPlaybackError(ValueError):
    """Public-safe failure reason; never contains movie or key bytes."""


@dataclass(frozen=True)
class AuthenticatedSelectionSignal:
    kind: str
    tv_session_id: str
    torrent_hash: str
    file_index: int
    sent_at_ms: int
    nonce: str
    signature: str


def signing_message(*, kind: str, tv_session_id: str,
                    torrent_hash: str, file_index: int,
                    sent_at_ms: int, nonce: str) -> bytes:
    # Fixed ASCII fields, no filename, URL, unbounded user string or secret.
    return ("TTV-P3-TV-SELECTION-V1\n" + kind + "\n" +
            tv_session_id + "\n" + torrent_hash + "\n" +
            str(file_index) + "\n" + str(sent_at_ms) + "\n" +
            nonce).encode("ascii")


def _strict_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result = {}
    for k, v in pairs:
        if k in result:
            raise SignedPlaybackError("P3_DUPLICATE_JSON_FIELD")
        result[k] = v
    return result


class SignedPlaybackVerifier:
    """Pure request validator + bounded in-process replay guard.

    It authenticates only that a paired device *sent* the signal, not that
    the current session remains active. It intentionally doesn't construct
    CurrentPlaying(attested=True) and can't authorize model/provider calls.
    """

    def __init__(self, paired_secret: bytes, *,
                 max_skew_ms: int = MAX_CLOCK_SKEW_MS,
                 journal: OwnerReplayJournal | None = None):
        if (not isinstance(paired_secret, bytes)
                or len(paired_secret) != 32
                or type(max_skew_ms) is not int
                or max_skew_ms < 1000 or max_skew_ms > 30000):
            raise SignedPlaybackError("P3_PAIRING_SECRET_OR_CLOCK_POLICY_INVALID")
        if journal is not None and not isinstance(journal, OwnerReplayJournal):
            raise SignedPlaybackError("P3_DURABLE_JOURNAL_INVALID")
        self._journal = journal
        self._key = paired_secret
        self._skew = max_skew_ms
        self._seen: dict[str, int] = {}
        self._last_sent = 0

    def verify(self, raw: bytes, *, now_ms: int | None = None) -> AuthenticatedSelectionSignal:
        if not isinstance(raw, bytes) or not 0 < len(raw) <= MAX_WIRE_BYTES:
            raise SignedPlaybackError("P3_WIRE_SIZE_INVALID")
        try:
            request = json.loads(raw.decode("utf-8", errors="strict"),
                                 object_pairs_hook=_strict_object,
                                 parse_constant=lambda _: (_ for _ in ()).throw(
                                     SignedPlaybackError("P3_JSON_NONFINITE")))
        except (UnicodeError, ValueError, TypeError, RecursionError):
            raise SignedPlaybackError("P3_JSON_INVALID") from None
        if not isinstance(request, dict) or set(request) != _KEYS:
            raise SignedPlaybackError("P3_SCHEMA_FIELDS_INVALID")
        kind = request["kind"]
        sess = request["tv_session_id"]
        infohash = request["torrent_hash"]
        idx = request["file_index"]
        sent = request["sent_at_ms"]
        nonce = request["nonce"]
        signature = request["signature"]
        if (request["schema"] != SCHEMA
                or not isinstance(kind, str) or kind not in VALID_KINDS
                or not isinstance(sess, str) or _SESSION.fullmatch(sess) is None
                or not isinstance(infohash, str) or _HASH.fullmatch(infohash) is None
                or type(idx) is not int or not 0 <= idx <= 65535
                or type(sent) is not int or not 0 < sent < 10**15
                or not isinstance(nonce, str) or _SESSION.fullmatch(nonce) is None
                or not isinstance(signature, str) or _AUTH.fullmatch(signature) is None):
            raise SignedPlaybackError("P3_SCHEMA_VALUE_INVALID")
        now = int(time.time() * 1000) if now_ms is None else now_ms
        if type(now) is not int or abs(sent - now) > self._skew:
            raise SignedPlaybackError("P3_SIGNAL_EXPIRED_OR_CLOCK_SKEW")
        body = signing_message(
            kind=kind, tv_session_id=sess, torrent_hash=infohash,
            file_index=idx, sent_at_ms=sent, nonce=nonce)
        expected = hmac.new(self._key, body, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, signature):
            raise SignedPlaybackError("P3_SIGNAL_AUTH_FAILED")
        # A small in-process replay guard. Restart-proof persistent acceptance
        # still depends on owner V3 source/cache claims and re-reading real
        # TV state. Never claim this provides a durable event journal.
        expired = [n for n, t in self._seen.items()
                   if t < now - 2 * self._skew]
        for n in expired:
            del self._seen[n]
        if nonce in self._seen:
            raise SignedPlaybackError("P3_SIGNAL_REPLAY")
        if len(self._seen) >= 512:
            raise SignedPlaybackError("P3_REPLAY_WINDOW_FULL")
        if sent + 1000 < self._last_sent:
            raise SignedPlaybackError("P3_OUT_OF_ORDER_SELECTION")
        if self._journal is not None:
            try:
                self._journal.accept_selection(
                    nonce=nonce, sent_ms=sent, now_ms=now)
            except ReplayJournalRejected:
                raise SignedPlaybackError("P3_SIGNAL_DURABLE_REPLAY_REJECTED") from None
        self._seen[nonce] = sent
        self._last_sent = max(self._last_sent, sent)
        return AuthenticatedSelectionSignal(
            kind=kind, tv_session_id=sess, torrent_hash=infohash,
            file_index=idx, sent_at_ms=sent, nonce=nonce,
            signature=signature)


def sign_synthetic_event(secret: bytes, *, kind: str, tv_session_id: str,
                         torrent_hash: str, file_index: int,
                         sent_at_ms: int, nonce: str) -> bytes:
    """Offline/test-vector utility only; don't build production TV auth in Python."""
    body = signing_message(
        kind=kind, tv_session_id=tv_session_id, torrent_hash=torrent_hash,
        file_index=file_index, sent_at_ms=sent_at_ms, nonce=nonce)
    tag = hmac.new(secret, body, hashlib.sha256).hexdigest()
    return json.dumps(dict(
        schema=SCHEMA, kind=kind, tv_session_id=tv_session_id,
        torrent_hash=torrent_hash, file_index=file_index,
        sent_at_ms=sent_at_ms, nonce=nonce, signature=tag),
        separators=(",", ":"), sort_keys=True).encode("utf-8")

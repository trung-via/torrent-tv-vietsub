"""Authenticated *current* Redmi OMP state, independent of Play signal.

TV-native P3 companion samples real PlayerSession/request/index and G1/P4
automaticChoice on the UI thread every 3s. This module verifies a distinct
HMAC domain and keeps the latest signed sample for <=8 seconds (monotonic PC
receive time), refusing stale, out-of-order, closed, OFF/OTHER or wrong media.

A signed status is evidence of the PAIRED DEVICE'S last reported state, not
proof of unmodified hardware/bytes. The trusted owner reader must additionally
bind a preconfigured localhost TorrServer and owner consent, rights and track
inventory. This module never starts a server, provider, or worker.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import hmac
import json
import re
import time

SCHEMA = "TTV-P3-TV-STATE-V1"
KIND = frozenset(("PLAY_REQUEST_ACCEPTED", "NEXT_QUEUE_ITEM_ACCEPTED"))
CHOICES = frozenset(("ON", "OFF", "OTHER"))
HEX32 = re.compile(r"[0-9a-f]{32}\Z")
HEX40 = re.compile(r"[0-9a-f]{40}\Z")
HEX64 = re.compile(r"[0-9a-f]{64}\Z")
WIRE_MAX = 1024
MAX_CLOCK_SKEW_MS = 15_000
FRESH_SECONDS = 8.0
FIELDS = frozenset(("schema", "boot_id", "sequence", "kind",
                    "tv_session_id", "torrent_hash", "file_index",
                    "active", "subtitle_choice", "sent_at_ms", "nonce",
                    "signature"))


class RedmiStateRejected(ValueError):
    """Safe reason code without session, media, key or network address."""


@dataclass(frozen=True)
class RedmiNow:
    boot_id: str
    sequence: int
    kind: str
    tv_session_id: str
    torrent_hash: str
    file_index: int
    active: bool
    subtitle_choice: str
    sent_at_ms: int
    received_monotonic: float


def mac_body(obj: dict[str, object]) -> bytes:
    """Canonical ASCII wire shared verbatim with the native Kotlin sender."""
    parts = (SCHEMA, obj["boot_id"], str(obj["sequence"]), obj["kind"],
             obj["tv_session_id"], obj["torrent_hash"], str(obj["file_index"]),
             "1" if obj["active"] is True else "0", obj["subtitle_choice"],
             str(obj["sent_at_ms"]), obj["nonce"])
    return "\n".join(parts).encode("ascii")


def _unique(pairs):
    v = {}
    for k, x in pairs:
        if k in v:
            raise RedmiStateRejected("P3_STATE_DUPLICATE_JSON_FIELD")
        v[k] = x
    return v


class SignedRedmiStateCache:
    def __init__(self, key: bytes, *, freshness_seconds: float = FRESH_SECONDS):
        if (not isinstance(key, bytes) or len(key) != 32
                or type(freshness_seconds) not in (int, float)
                or not 1.0 <= freshness_seconds <= FRESH_SECONDS):
            raise RedmiStateRejected("P3_STATE_KEY_OR_TTL_INVALID")
        self._key = bytes(key)
        self._ttl = freshness_seconds
        self._current: RedmiNow | None = None
        self._nonces: dict[str, float] = {}
        # A production owner runtime must persist boot/sequence/nonce high
        # water marks across process restart before claiming durable replay.
        self._boot_id: str | None = None
        self._sequence = -1

    def receive(self, raw: bytes, *, now_ms: int | None = None,
                monotonic_s: float | None = None) -> RedmiNow:
        if not isinstance(raw, bytes) or not 0 < len(raw) <= WIRE_MAX:
            raise RedmiStateRejected("P3_STATE_WIRE_SIZE_INVALID")
        try:
            v = json.loads(raw.decode("utf-8", "strict"),
                           object_pairs_hook=_unique)
        except (ValueError, UnicodeError, TypeError, RecursionError):
            raise RedmiStateRejected("P3_STATE_JSON_INVALID") from None
        if not isinstance(v, dict) or set(v) != FIELDS or v["schema"] != SCHEMA:
            raise RedmiStateRejected("P3_STATE_FIELDS_INVALID")
        if (type(v["boot_id"]) is not str or not HEX32.fullmatch(v["boot_id"])
                or type(v["sequence"]) is not int
                or not 1 <= v["sequence"] < 2**63
                or type(v["kind"]) is not str or v["kind"] not in KIND
                or type(v["tv_session_id"]) is not str
                or not HEX32.fullmatch(v["tv_session_id"])
                or type(v["torrent_hash"]) is not str
                or not HEX40.fullmatch(v["torrent_hash"])
                or type(v["file_index"]) is not int
                or not 0 <= v["file_index"] <= 65535
                or type(v["active"]) is not bool
                or type(v["subtitle_choice"]) is not str
                or v["subtitle_choice"] not in CHOICES
                or type(v["sent_at_ms"]) is not int
                or not 0 < v["sent_at_ms"] < 10**15
                or type(v["nonce"]) is not str
                or not HEX32.fullmatch(v["nonce"])
                or type(v["signature"]) is not str
                or not HEX64.fullmatch(v["signature"])):
            raise RedmiStateRejected("P3_STATE_VALUE_INVALID")
        now = int(time.time()*1000) if now_ms is None else now_ms
        local = time.monotonic() if monotonic_s is None else monotonic_s
        if type(now) is not int or type(local) not in (float, int):
            raise RedmiStateRejected("P3_STATE_CLOCK_INVALID")
        if abs(v["sent_at_ms"] - now) > MAX_CLOCK_SKEW_MS:
            raise RedmiStateRejected("P3_STATE_CLOCK_SKEW")
        expected = hmac.new(self._key, mac_body(v), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, v["signature"]):
            raise RedmiStateRejected("P3_STATE_AUTH_FAILED")
        self._nonces = {k:t for k,t in self._nonces.items() if local-t < 30.0}
        if v["nonce"] in self._nonces or len(self._nonces) >= 256:
            raise RedmiStateRejected("P3_STATE_REPLAY")
        if v["boot_id"] != self._boot_id:
            # A new process boot cannot take over a still-fresh active
            # session merely by resetting sequence to 1.
            if self._current is not None and local-self._current.received_monotonic <= self._ttl:
                raise RedmiStateRejected("P3_STATE_BOOT_CHANGE_WHILE_FRESH")
            self._boot_id = v["boot_id"]
            self._sequence = -1
        if v["sequence"] <= self._sequence:
            raise RedmiStateRejected("P3_STATE_OUT_OF_ORDER")
        self._sequence = v["sequence"]
        self._nonces[v["nonce"]] = local
        self._current = RedmiNow(
            v["boot_id"], v["sequence"], v["kind"], v["tv_session_id"],
            v["torrent_hash"], v["file_index"], v["active"],
            v["subtitle_choice"], v["sent_at_ms"], float(local))
        return self._current

    def read_fresh(self, *, monotonic_s: float | None = None) -> RedmiNow:
        now = time.monotonic() if monotonic_s is None else monotonic_s
        state = self._current
        if state is None or now < state.received_monotonic or (
                now - state.received_monotonic > self._ttl):
            raise RedmiStateRejected("P3_STATE_STALE_OR_MISSING")
        if not state.active or state.subtitle_choice != "ON":
            raise RedmiStateRejected("P3_STATE_TV_OFF_OR_INACTIVE")
        return state


def sign_synthetic_state(key: bytes, *, boot_id: str, sequence: int,
                         kind: str, tv_session_id: str, torrent_hash: str,
                         file_index: int, active: bool, subtitle_choice: str,
                         sent_at_ms: int, nonce: str) -> bytes:
    """Synthetic fixed-vector producer; never used for real TV identity."""
    v = dict(schema=SCHEMA, boot_id=boot_id, sequence=sequence, kind=kind,
             tv_session_id=tv_session_id, torrent_hash=torrent_hash,
             file_index=file_index, active=active,
             subtitle_choice=subtitle_choice, sent_at_ms=sent_at_ms, nonce=nonce)
    v["signature"] = hmac.new(key, mac_body(v), hashlib.sha256).hexdigest()
    return json.dumps(v, separators=(",", ":"), sort_keys=True).encode("ascii")

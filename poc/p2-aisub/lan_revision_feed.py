"""Opt-in, LAN-only immutable P2→P4 subtitle revision feed.

The host publishes ONLY the latest cumulative revision. A TV can poll the
session-specific endpoint. Each response is signed by the existing P4 HMAC
contract, so packets cannot authorize wrong-media subtitles or bypass the
native OFF/OTHER choice.

No listener is started on import. No app, TV, firewall, TorrServer or WAN
configuration is touched. Plain HTTP on a trusted LAN gives integrity via
HMAC but does NOT encrypt the subtitles in transit.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import re
import secrets
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, HTTPServer
import ipaddress
import json
from threading import Lock
from typing import Type

from progressive_handoff import SubtitleRevision
from revision_delivery import SignedSubtitleOffer, sign_revision

_SESSION = re.compile(r"[A-Za-z0-9_-]{16,80}\Z")
MAX_WIRE_BYTES = 400_000
_RFC1918 = tuple(ipaddress.IPv4Network(x) for x in (
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
))


def private_lan_ip(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("P4_LAN_IP_REQUIRED")
    try:
        ip = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError:
        raise ValueError("P4_LAN_IPV4_LITERAL_REQUIRED") from None
    if str(ip) != value or not any(ip in subnet for subnet in _RFC1918):
        raise ValueError("P4_RFC1918_BIND_REQUIRED")
    return value


def offer_wire(offer: SignedSubtitleOffer) -> bytes:
    """Transport envelope. Signature covers all fields except Base64 encoding."""
    fields = {
        "schema": "TTV-P4-LAN-REVISION-V1",
        "session_id": offer.session_id,
        "media_key": offer.media_key,
        "source_sha256": offer.source_sha256,
        "version": offer.version,
        "fmt": offer.fmt,
        "translated_count": offer.translated_count,
        "total_count": offer.total_count,
        "last_end_ms": offer.last_end_ms,
        "payload_sha256": offer.payload_sha256,
        "payload_b64": base64.b64encode(offer.payload).decode("ascii"),
        "signature": offer.signature,
    }
    encoded = json.dumps(fields, sort_keys=True, separators=(",", ":")).encode("ascii")
    if len(encoded) > MAX_WIRE_BYTES:
        raise ValueError("P4_WIRE_BYTES_TOO_LARGE")
    return encoded


@dataclass(frozen=True)
class FeedSnapshot:
    version: int
    digest: str
    wire: bytes


class SessionRevisionFeed:
    """One private paired TV session and one immutable subtitle source."""

    def __init__(
        self, *, session_id: str, media_key: str,
        source_sha256: str, pairing_secret: bytes,
    ) -> None:
        if not isinstance(session_id, str) or not _SESSION.fullmatch(session_id):
            raise ValueError("P4_SESSION_ID_INVALID")
        if (not isinstance(pairing_secret, bytes) or
            len(pairing_secret) < 16):
            raise ValueError("P4_SECRET_REQUIRED")
        if not isinstance(media_key, str) or not re.fullmatch(r"media\.[0-9a-f]{64}",media_key):
            raise ValueError("P4_MEDIA_ID_INVALID")
        if not isinstance(source_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}",source_sha256):
            raise ValueError("P4_SOURCE_ID_INVALID")
        self.session_id = session_id
        self.media_key = media_key
        self.source_sha256 = source_sha256
        self.__secret = bytes(pairing_secret)
        self.__current: FeedSnapshot | None = None
        self.__lock = Lock()
        self.__used_read_nonces: dict[str, float] = {}

    def publish(self, revision: SubtitleRevision) -> str:
        if (revision.media_key != self.media_key or
            revision.source_sha256 != self.source_sha256):
            raise ValueError("P4_FEED_SOURCE_OR_MEDIA_MISMATCH")
        offer = sign_revision(revision,self.session_id,self.__secret)
        candidate = FeedSnapshot(offer.version,offer.payload_sha256,offer_wire(offer))
        with self.__lock:
            current = self.__current
            if current is not None:
                if candidate.version < current.version:
                    raise ValueError("P4_FEED_STALE_VERSION")
                if candidate.version == current.version:
                    if candidate.digest != current.digest:
                        raise ValueError("P4_FEED_REVISION_COLLISION")
                    return "DUPLICATE_NOOP"
            self.__current = candidate
        return "PUBLISHED"

    def latest(self) -> bytes | None:
        with self.__lock:
            return None if self.__current is None else self.__current.wire

    def authorize_read(self, nonce: str | None, signature: str | None) -> bool:
        """Authenticated, unique GET request; no reply to unpaired LAN clients."""
        if (not isinstance(nonce, str) or not re.fullmatch(r"[0-9a-f]{32}",nonce) or
            not isinstance(signature, str) or not re.fullmatch(r"[0-9a-f]{64}",signature)):
            return False
        expected = hmac.new(
            self.__secret,
            ("TTV-P4-LAN-READ-V1\n"+self.session_id+"\n"+nonce).encode("ascii"),
            hashlib.sha256,
        ).hexdigest()
        if not hmac.compare_digest(expected,signature):
            return False
        now = time.monotonic()
        with self.__lock:
            self.__used_read_nonces = {
                n:ts for n,ts in self.__used_read_nonces.items() if now-ts < 600.0
            }
            if nonce in self.__used_read_nonces or len(self.__used_read_nonces)>=1024:
                return False
            self.__used_read_nonces[nonce]=now
        return True


def make_handler(feed: SessionRevisionFeed) -> Type[BaseHTTPRequestHandler]:
    """Fixed non-discoverable route; no user-controlled paths or directories."""
    endpoint = "/p4/revision/" + feed.session_id

    class RevisionHandler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: object) -> None:
            # Never write session IDs, LAN addresses, subtitle content or keys to logs.
            return

        def do_GET(self) -> None:
            if self.path != endpoint:
                self.send_error(404)
                return
            if not feed.authorize_read(
                self.headers.get("X-P4-Nonce"), self.headers.get("X-P4-Authorization")
            ):
                self.send_error(401)
                return
            wire = feed.latest()
            if wire is None:
                self.send_response(204)
                self.send_header("Cache-Control","no-store")
                self.end_headers()
                return
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.send_header("Cache-Control","no-store")
            self.send_header("X-Content-Type-Options","nosniff")
            self.send_header("Content-Length",str(len(wire)))
            self.end_headers()
            self.wfile.write(wire)

        def do_POST(self) -> None:
            self.send_error(405)

    return RevisionHandler


def create_server(feed: SessionRevisionFeed, *, host: str, port: int) -> HTTPServer:
    """Explicit RFC1918 bind only; never call this at module import."""
    private_lan_ip(host)
    if type(port) is not int or port not in range(1024,65536):
        raise ValueError("P4_PORT_INVALID")
    return HTTPServer((host,port), make_handler(feed))


def translate_into_feed(
    source: bytes, fmt: str, media_key: str, profile: object,
    *, feed: SessionRevisionFeed, glossary: dict[str, str],
    api_key: str, transport: object,
) -> tuple[SubtitleRevision, ...]:
    """Lean120 API→cumulative signed feed, one callback per validated batch.

    Fail BEFORE the first provider request if this feed was paired for a
    different source or film. Transport is injectable for entirely offline CI.
    No server/socket is started; a separate explicit owner action must run it.
    """
    if not isinstance(source, bytes) or hashlib.sha256(source).hexdigest() != feed.source_sha256:
        raise ValueError("P4_FEED_SOURCE_SHA_MISMATCH")
    if media_key != feed.media_key:
        raise ValueError("P4_FEED_MEDIA_MISMATCH")
    from lean120_api import translate_all
    return translate_all(
        source, fmt, media_key, profile,
        glossary=glossary, api_key=api_key, transport=transport,
        on_revision=feed.publish,
    )


# No CLI or automatic service startup is provided yet. A future trusted
# process must hold the publisher object and pass SessionRevisionFeed.publish
# to LEAN120 translate_all(on_revision=...) after one opt-in pairing.

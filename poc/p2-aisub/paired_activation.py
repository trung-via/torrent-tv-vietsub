"""P4 PC-side authenticated activation for a *pre-supplied* timed subtitle.

The user has explicitly deferred Brain source discovery. The caller preloads
an assumed matching English SRT/VTT for each opaque OMP media key. TV asks the
paired PC to create an exact film/source session. Actual Gemini processing is
invoked by a separate owner-controlled worker after the activation callback.

No sockets on import, no automatic Windows service, no provider calls and no
TorrServer control. One trusted PC/TV pairing key per device.
"""
from __future__ import annotations

import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import re
import secrets
from threading import Lock
import time
from typing import Callable, Type

from assumed_source_handoff import AssumedEnglishSubtitle
from lan_revision_feed import SessionRevisionFeed, private_lan_ip

MEDIA_RX = re.compile(r"media\.[0-9a-f]{64}\Z")
NONCE_RX = re.compile(r"[0-9a-f]{32}\Z")
MAC_RX = re.compile(r"[0-9a-f]{64}\Z")
SESSION_RX = re.compile(r"[A-Za-z0-9_-]{16,80}\Z")
ACTIVATE_ROUTE = "/p4/activate"
MAX_ACTIVATE_BYTES = 800


def derive_session_secret(device_secret: bytes, session_id: str,
                          media_key: str, source_sha256: str) -> bytes:
    if (not isinstance(device_secret, bytes) or len(device_secret) != 32 or
        not SESSION_RX.fullmatch(session_id) or
        not MEDIA_RX.fullmatch(media_key) or
        not re.fullmatch(r"[0-9a-f]{64}", source_sha256)):
        raise ValueError("P4_DERIVATION_SCOPE_INVALID")
    message = ("TTV-P4-SESSION-KEY-V1\n"+session_id+"\n"+
               media_key+"\n"+source_sha256).encode("ascii")
    return hmac.new(device_secret, message, hashlib.sha256).digest()


def activation_request_mac(device_secret: bytes, media_key: str, nonce: str) -> str:
    if (not MEDIA_RX.fullmatch(media_key) or not NONCE_RX.fullmatch(nonce) or
        not isinstance(device_secret, bytes) or len(device_secret) != 32):
        raise ValueError("P4_ACTIVATION_REQUEST_INVALID")
    return hmac.new(device_secret,
                    ("TTV-P4-ACTIVATE-V1\n"+media_key+"\n"+nonce).encode("ascii"),
                    hashlib.sha256).hexdigest()


def activation_response_mac(device_secret: bytes, media_key: str, nonce: str,
                            session_id: str, source_sha256: str) -> str:
    derive_session_secret(device_secret, session_id,media_key,source_sha256)
    return hmac.new(device_secret,
                    ("TTV-P4-ACTIVATED-V1\n"+media_key+"\n"+nonce+"\n"+
                     session_id+"\n"+source_sha256).encode("ascii"),
                    hashlib.sha256).hexdigest()


class PairedActivation:
    """Bounded per-media gateway, no subtitle discovery and no live provider.

    activate() is pure object work. An optional on_activate callback may queue
    an authorized translation job; errors fail closed and do not expose key
    or source bytes in HTTP errors.
    """
    def __init__(self, *, device_secret: bytes,
                 supplied: dict[str, AssumedEnglishSubtitle],
                 on_activate: Callable[[SessionRevisionFeed, AssumedEnglishSubtitle], None] | None = None):
        if not isinstance(device_secret, bytes) or len(device_secret) != 32:
            raise ValueError("P4_DEVICE_SECRET_INVALID")
        if len(supplied) > 32 or any(
            k != x.media_key or not isinstance(x,AssumedEnglishSubtitle)
            for k,x in supplied.items()
        ):
            raise ValueError("P4_ASSUMED_SOURCE_MAP_INVALID")
        self.__key = bytes(device_secret)
        self.__sources = dict(supplied)
        self.__on_activate = on_activate
        self.__feeds: dict[str, SessionRevisionFeed] = {}
        self.__seen: dict[str,float] = {}
        self.__lock = Lock()

    def activate(self, request: dict[str, object]) -> dict[str, object]:
        if not isinstance(request,dict) or set(request)!={"schema","media_key","nonce","auth"}:
            raise ValueError("P4_ACTIVATE_SCHEMA_INVALID")
        media,nonce,tag = (request[x] for x in ("media_key","nonce","auth"))
        if (request["schema"]!="TTV-P4-ACTIVATE-V1" or
            not isinstance(media,str) or not MEDIA_RX.fullmatch(media) or
            not isinstance(nonce,str) or not NONCE_RX.fullmatch(nonce) or
            not isinstance(tag,str) or not MAC_RX.fullmatch(tag)):
            raise ValueError("P4_ACTIVATE_SCHEMA_INVALID")
        expected = activation_request_mac(self.__key,media,nonce)
        if not hmac.compare_digest(expected,tag):
            raise ValueError("P4_ACTIVATE_AUTH_INVALID")
        source = self.__sources.get(media)
        if source is None:
            raise ValueError("P4_ASSUMED_SOURCE_MISSING")
        now = time.monotonic()
        with self.__lock:
            self.__seen={n:t for n,t in self.__seen.items() if now-t<600.0}
            if nonce in self.__seen or len(self.__seen)>=1024:
                raise ValueError("P4_ACTIVATE_REPLAY")
            if len(self.__feeds)>=16:
                raise ValueError("P4_TOO_MANY_SESSIONS")
            self.__seen[nonce]=now
            sid=secrets.token_urlsafe(24)
            session_key=derive_session_secret(self.__key,sid,media,source.source_sha256)
            feed=SessionRevisionFeed(
                session_id=sid,media_key=media,
                source_sha256=source.source_sha256,pairing_secret=session_key)
            self.__feeds[sid]=feed
        if self.__on_activate is not None:
            try: self.__on_activate(feed,source)
            except Exception:
                with self.__lock:self.__feeds.pop(sid,None)
                raise ValueError("P4_TRANSLATION_START_FAILED") from None
        return {
            "schema":"TTV-P4-ACTIVATED-V1",
            "media_key":media,"nonce":nonce,
            "session_id":sid,"source_sha256":source.source_sha256,
            "auth":activation_response_mac(self.__key,media,nonce,sid,source.source_sha256),
        }

    def feed_for(self, session_id: str) -> SessionRevisionFeed | None:
        with self.__lock:return self.__feeds.get(session_id)


def make_paired_handler(controller: PairedActivation) -> Type[BaseHTTPRequestHandler]:
    class PairedHandler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: object) -> None:
            # Never log device key, subtitle bytes, opaque film identifiers.
            return

        def do_POST(self) -> None:
            if self.path != ACTIVATE_ROUTE:
                self.send_error(404);return
            if self.headers.get("Content-Type","").split(";")[0]!="application/json":
                self.send_error(415);return
            try: length=int(self.headers.get("Content-Length","-1"))
            except (TypeError,ValueError):length=-1
            if not 1<=length<=MAX_ACTIVATE_BYTES:
                self.send_error(413);return
            try:
                raw=self.rfile.read(length)
                if len(raw)!=length:raise ValueError("SHORT_REQUEST")
                body=json.loads(raw)
                result=controller.activate(body)
                data=json.dumps(result,sort_keys=True,separators=(",",":")).encode("ascii")
            except Exception:
                self.send_error(403);return
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.send_header("Cache-Control","no-store")
            self.send_header("Content-Length",str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self) -> None:
            prefix="/p4/revision/"
            if not self.path.startswith(prefix):
                self.send_error(404);return
            sid=self.path[len(prefix):]
            if not SESSION_RX.fullmatch(sid):
                self.send_error(404);return
            feed=controller.feed_for(sid)
            if feed is None:
                self.send_error(404);return
            if not feed.authorize_read(
                self.headers.get("X-P4-Nonce"),self.headers.get("X-P4-Authorization")):
                self.send_error(401);return
            body=feed.latest()
            if body is None:
                self.send_response(204)
                self.send_header("Cache-Control","no-store")
                self.end_headers()
                return
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.send_header("Cache-Control","no-store")
            self.send_header("X-Content-Type-Options","nosniff")
            self.send_header("Content-Length",str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return PairedHandler


def create_paired_server(controller:PairedActivation,*,host:str,port:int)->HTTPServer:
    private_lan_ip(host)
    if type(port) is not int or port not in range(1024,65536):
        raise ValueError("P4_PAIRED_PORT_INVALID")
    return HTTPServer((host,port),make_paired_handler(controller))


# Future configured owner-only runtime supplies a real authorized source and
# on_activate worker; no server or paid provider starts from imports or CI.

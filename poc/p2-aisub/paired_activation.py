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
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import re
import secrets
import ssl
from threading import Lock
import time
from typing import Callable, Type

from assumed_source_handoff import AssumedEnglishSubtitle
from verified_vietsub_ready import VerifiedVietsubReady
from lan_revision_feed import SessionRevisionFeed, private_lan_ip

MEDIA_RX = re.compile(r"media\.[0-9a-f]{64}\Z")
NONCE_RX = re.compile(r"[0-9a-f]{32}\Z")
MAC_RX = re.compile(r"[0-9a-f]{64}\Z")
SESSION_RX = re.compile(r"[A-Za-z0-9_-]{16,80}\Z")
ACTIVATE_ROUTE = "/p4/activate"
MAX_ACTIVATE_BYTES = 800
_SAFE_ACTIVATION_REASONS = frozenset({
    "P4_ACTIVATE_SCHEMA_INVALID", "P4_ACTIVATE_AUTH_INVALID",
    "P4_ACTIVATE_REPLAY", "P4_TOO_MANY_SESSIONS",
    "P4_ASSUMED_SOURCE_MISSING", "P4_PROGRESSIVE_FEED_BIND_FAILED",
    "P4_READY_FEED_PUBLISH_FAILED", "P4_TRANSLATION_START_FAILED",
    "P3_READY_NO_CURRENT_ACCEPTED_SOURCE",
    "P3_READY_CURRENT_MEDIA_OR_CONSENT_CHANGED",
    "P3_READY_PRIVATE_SOURCE_NOT_READY",
    "P4_ROLLING_CURRENT_TV_UNAVAILABLE",
    "P4_ROLLING_TV_SESSION_CHANGED",
    "P4_ROLLING_CHECKPOINT_INVALID",
    "P4_ROLLING_CHECKPOINT_NOT_VERIFIED",
    "P4_ROLLING_CHECKPOINT_HASH_CHANGED",
    "P4_ROLLING_CHECKPOINT_GAP",
    "P4_ROLLING_SOURCE_NOT_VERIFIED",
    "P4_ROLLING_SOURCE_RECEIPT_INVALID",
    "P4_ROLLING_SOURCE_INDEX_INVALID",
    "P4_ROLLING_ABANDONED_JOB_HOLD",
    "P4_ROLLING_SOURCE_CHANGED",
    "P4_ROLLING_REVISION_IDENTITY_INVALID",
})


@dataclass(frozen=True)
class AuthenticatedProgressiveSource:
    """Owner-verified EN source with already-checkpointed rolling VI output.

    The callback only attaches an existing P2 producer to the original P4
    session; it must NEVER start translation, download or another provider.
    """
    media_key: str
    source_sha256: str
    subscribe: Callable[[SessionRevisionFeed], None]
    refresh: Callable[[], None] | None = None


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


def variant_activation_request_mac(device_secret: bytes, media_key: str,
                                   nonce: str, variant: str) -> str:
    """V2 MAC binds the chosen subtitle source, not just the film."""
    if variant != "downloaded_vi":
        raise ValueError("P4_VARIANT_UNSUPPORTED")
    if (not MEDIA_RX.fullmatch(media_key) or not NONCE_RX.fullmatch(nonce)
            or not isinstance(device_secret, bytes) or len(device_secret) != 32):
        raise ValueError("P4_ACTIVATION_REQUEST_INVALID")
    return hmac.new(device_secret,
                    ("TTV-P4-ACTIVATE-V2\n" + media_key + "\n" + nonce + "\n" + variant).encode("ascii"),
                    hashlib.sha256).hexdigest()


def variant_activation_response_mac(device_secret: bytes, media_key: str,
                                    nonce: str, session_id: str,
                                    source_sha256: str, variant: str) -> str:
    derive_session_secret(device_secret, session_id, media_key, source_sha256)
    if variant != "downloaded_vi":
        raise ValueError("P4_VARIANT_UNSUPPORTED")
    return hmac.new(device_secret,
                    ("TTV-P4-ACTIVATED-V2\n" + media_key + "\n" + nonce + "\n"
                     + session_id + "\n" + source_sha256 + "\n" + variant).encode("ascii"),
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
                 on_activate: Callable[[SessionRevisionFeed, AssumedEnglishSubtitle], None] | None = None,
                 authenticated_mock_source_factory: Callable[[str], AssumedEnglishSubtitle] | None = None,
                 authenticated_source_factory: Callable[[str], AssumedEnglishSubtitle] | None = None,
                 authenticated_vietsub_factory: Callable[[str], VerifiedVietsubReady] | None = None,
                 authenticated_progressive_factory: Callable[[str], AuthenticatedProgressiveSource | None] | None = None,
                 authenticated_variant_factory: Callable[[str, str], VerifiedVietsubReady | None] | None = None):
        if not isinstance(device_secret, bytes) or len(device_secret) != 32:
            raise ValueError("P4_DEVICE_SECRET_INVALID")
        if len(supplied) > 32 or any(
            k != x.media_key or not isinstance(x,AssumedEnglishSubtitle)
            for k,x in supplied.items()
        ):
            raise ValueError("P4_ASSUMED_SOURCE_MAP_INVALID")
        # Optional DEV-only factory. Never enabled for real subtitle/API mode.
        # The FIRST correctly authenticated TV media is bound for the entire
        # process; different media is always refused, even with a valid key.
        if authenticated_mock_source_factory is not None and (
            not callable(authenticated_mock_source_factory) or supplied or
            authenticated_source_factory is not None or
            authenticated_vietsub_factory is not None or
            authenticated_progressive_factory is not None or
            authenticated_variant_factory is not None
        ):
            raise ValueError("P4_MOCK_SOURCE_FACTORY_SCOPE_INVALID")
        if authenticated_source_factory is not None and not callable(authenticated_source_factory):
            raise ValueError("P4_SOURCE_FACTORY_INVALID")
        if (authenticated_vietsub_factory is not None and
                (not callable(authenticated_vietsub_factory) or supplied or
                 authenticated_source_factory is not None or
                 on_activate is not None)):
            raise ValueError("P4_VERIFIED_VI_FACTORY_SCOPE_INVALID")
        if (authenticated_progressive_factory is not None and
                (not callable(authenticated_progressive_factory) or supplied or
                 authenticated_source_factory is not None or
                 on_activate is not None)):
            raise ValueError("P4_PROGRESSIVE_FACTORY_SCOPE_INVALID")
        if (authenticated_variant_factory is not None and
                (not callable(authenticated_variant_factory) or supplied
                 or authenticated_source_factory is not None or on_activate is not None)):
            raise ValueError("P4_VARIANT_FACTORY_SCOPE_INVALID")
        self.__vietsub_factory = authenticated_vietsub_factory
        self.__progressive_factory = authenticated_progressive_factory
        self.__variant_factory = authenticated_variant_factory
        self.__mock_factory = authenticated_mock_source_factory
        self.__source_factory = authenticated_source_factory
        self.__locked_mock_media: str | None = None
        self.__key = bytes(device_secret)
        self.__sources = dict(supplied)
        self.__on_activate = on_activate
        self.__feeds: dict[str, SessionRevisionFeed] = {}
        self.__refreshers: dict[str, Callable[[], None]] = {}
        self.__seen: dict[str,float] = {}
        self.__lock = Lock()

    def activate(self, request: dict[str, object]) -> dict[str, object]:
        if not isinstance(request, dict):
            raise ValueError("P4_ACTIVATE_SCHEMA_INVALID")
        variant_mode = request.get("schema") == "TTV-P4-ACTIVATE-V2"
        if set(request) != ({"schema", "media_key", "nonce", "auth", "variant"}
                            if variant_mode else {"schema", "media_key", "nonce", "auth"}):
            raise ValueError("P4_ACTIVATE_SCHEMA_INVALID")
        media,nonce,tag = (request[x] for x in ("media_key","nonce","auth"))
        if (request["schema"] not in ("TTV-P4-ACTIVATE-V1", "TTV-P4-ACTIVATE-V2") or
            not isinstance(media,str) or not MEDIA_RX.fullmatch(media) or
            not isinstance(nonce,str) or not NONCE_RX.fullmatch(nonce) or
            not isinstance(tag,str) or not MAC_RX.fullmatch(tag)):
            raise ValueError("P4_ACTIVATE_SCHEMA_INVALID")
        variant = request.get("variant") if variant_mode else None
        if variant_mode and variant != "downloaded_vi":
            raise ValueError("P4_ACTIVATE_SCHEMA_INVALID")
        expected = (variant_activation_request_mac(self.__key, media, nonce, variant)
                    if variant_mode else activation_request_mac(self.__key, media, nonce))
        if not hmac.compare_digest(expected,tag):
            raise ValueError("P4_ACTIVATE_AUTH_INVALID")
        now = time.monotonic()
        with self.__lock:
            self.__seen={n:t for n,t in self.__seen.items() if now-t<600.0}
            if nonce in self.__seen or len(self.__seen)>=1024:
                raise ValueError("P4_ACTIVATE_REPLAY")
            source = None if variant_mode else self.__sources.get(media)
            if source is None and not variant_mode and self.__mock_factory is not None:
                # Only happens AFTER a valid per-device HMAC was checked.
                # A wrong MAC, malformed input or other PC cannot register
                # any media. Never discover or accept real subtitle content.
                if self.__locked_mock_media is not None:
                    raise ValueError("P4_MOCK_ONE_MEDIA_ONLY")
                candidate = self.__mock_factory(media)
                if (not isinstance(candidate, AssumedEnglishSubtitle) or
                    candidate.media_key != media):
                    raise ValueError("P4_MOCK_FACTORY_MEDIA_MISMATCH")
                source = candidate
                self.__sources[media] = source
                self.__locked_mock_media = media
            if source is None and not variant_mode and self.__source_factory is not None:
                # After HMAC validation only: resolve an exact local, owner-
                # approved EN handoff. No blind first-film fallback for real
                # subtitles or paid AI calls.
                if len(self.__sources) >= 32:
                    raise ValueError("P4_TOO_MANY_SOURCES")
                candidate = self.__source_factory(media)
                if (not isinstance(candidate, AssumedEnglishSubtitle) or
                    candidate.media_key != media or
                    candidate.source_status != "ASSUMED_MATCHED_EN_TIMED_TEXT"):
                    raise ValueError("P4_SOURCE_FACTORY_MEDIA_MISMATCH")
                source = candidate
                self.__sources[media] = source
            progressive = None
            if source is None and not variant_mode and self.__progressive_factory is not None:
                candidate = self.__progressive_factory(media)
                if candidate is not None:
                    if (not isinstance(candidate, AuthenticatedProgressiveSource)
                            or candidate.media_key != media
                            or not re.fullmatch(r"[0-9a-f]{64}",
                                                candidate.source_sha256)
                            or not callable(candidate.subscribe)
                            or (candidate.refresh is not None
                                and not callable(candidate.refresh))):
                        raise ValueError("P4_PROGRESSIVE_SOURCE_MISMATCH")
                    progressive = candidate
            ready = None
            if (source is None and progressive is None and not variant_mode
                    and self.__vietsub_factory is not None):
                # The ready registry is populated ONLY by the existing owner
                # VI_FAST or EN→LEAN120 completion, never by a bare Play.
                # It independently rechecks the CURRENT signed TV session.
                candidate = self.__vietsub_factory(media)
                if (not isinstance(candidate, VerifiedVietsubReady)
                        or candidate.media_key != media):
                    raise ValueError("P4_READY_FACTORY_MEDIA_MISMATCH")
                candidate.as_final_revision()  # strict hash/cues/timeline
                ready = candidate
            if variant_mode and self.__variant_factory is not None:
                candidate = self.__variant_factory(media, variant)
                if candidate is not None:
                    if (not isinstance(candidate, VerifiedVietsubReady)
                            or candidate.media_key != media):
                        raise ValueError("P4_VARIANT_SOURCE_MISMATCH")
                    candidate.as_final_revision()
                    ready = candidate
            if source is None and ready is None and progressive is None:
                raise ValueError("P4_ASSUMED_SOURCE_MISSING")
            if len(self.__feeds)>=16:
                raise ValueError("P4_TOO_MANY_SESSIONS")
            self.__seen[nonce]=now
            sid=secrets.token_urlsafe(24)
            source_sha = (ready.source_sha256 if ready is not None else
                          progressive.source_sha256 if progressive is not None
                          else source.source_sha256)
            session_key=derive_session_secret(self.__key,sid,media,source_sha)
            feed=SessionRevisionFeed(
                session_id=sid,media_key=media,
                source_sha256=source_sha,pairing_secret=session_key)
            self.__feeds[sid]=feed
        if ready is not None:
            try:
                # Existing P4 signed feed; no Gemini/OpenSubtitles repeat.
                feed.publish(ready.as_final_revision())
            except Exception:
                with self.__lock: self.__feeds.pop(sid,None)
                raise ValueError("P4_READY_FEED_PUBLISH_FAILED") from None
        if progressive is not None:
            try:
                progressive.subscribe(feed)
            except Exception:
                with self.__lock: self.__feeds.pop(sid,None)
                raise ValueError("P4_PROGRESSIVE_FEED_BIND_FAILED") from None
            if progressive.refresh is not None:
                with self.__lock:
                    self.__refreshers[sid] = progressive.refresh
        if source is not None and self.__on_activate is not None:
            try: self.__on_activate(feed,source)
            except Exception:
                with self.__lock:self.__feeds.pop(sid,None)
                raise ValueError("P4_TRANSLATION_START_FAILED") from None
        response = {
            "schema":"TTV-P4-ACTIVATED-V2" if variant_mode else "TTV-P4-ACTIVATED-V1",
            "media_key":media,"nonce":nonce,
            "session_id":sid,"source_sha256":source_sha,
            "auth":(variant_activation_response_mac(
                self.__key, media, nonce, sid, source_sha, variant)
                if variant_mode else activation_response_mac(
                    self.__key, media, nonce, sid, source_sha)),
        }
        if variant_mode:
            response["variant"] = variant
        return response

    def feed_for(self, session_id: str) -> SessionRevisionFeed | None:
        with self.__lock:return self.__feeds.get(session_id)

    def refresh_for(self, session_id: str) -> bool:
        """Replay already committed checkpoints only; no worker/provider call.

        A progressive GET must also be denied when the live TV has switched
        to OFF, another session, or another TorrServer file.
        """
        with self.__lock:
            if session_id not in self.__feeds:
                return False
            refresh = self.__refreshers.get(session_id)
        if refresh is None:
            return True
        try:
            refresh()
            return True
        except Exception:
            return False


def make_paired_handler(
        controller: PairedActivation, *,
        on_event: Callable[[str], object] | None = None
        ) -> Type[BaseHTTPRequestHandler]:
    """Optional owner-private fixed-code telemetry; never echo errors to TV."""
    if on_event is not None and not callable(on_event):
        raise ValueError("P4_EVENT_CALLBACK_INVALID")

    def report(code: str) -> None:
        if on_event is not None:
            try:
                on_event(code)
            except Exception:
                pass

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
            except Exception as exc:
                reason = (exc.args[0] if isinstance(exc, ValueError)
                          and len(exc.args) == 1
                          and type(exc.args[0]) is str
                          and exc.args[0] in _SAFE_ACTIVATION_REASONS
                          else "UNCLASSIFIED")
                report("P4_ACTIVATE_REJECTED_" + reason)
                self.send_error(403);return
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.send_header("Cache-Control","no-store")
            self.send_header("Content-Length",str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            report("P4_ACTIVATE_HTTP_200")

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
            if not controller.refresh_for(sid):
                report("P4_REVISION_CURRENT_SOURCE_HOLD")
                self.send_error(403);return
            body=feed.latest()
            if body is None:
                self.send_response(204)
                self.send_header("Cache-Control","no-store")
                self.end_headers()
                report("P4_REVISION_HTTP_204")
                return
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.send_header("Cache-Control","no-store")
            self.send_header("X-Content-Type-Options","nosniff")
            self.send_header("Content-Length",str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            report("P4_REVISION_HTTP_200")

    return PairedHandler


def create_paired_server(
    controller:PairedActivation,*,host:str,port:int,
    tls_context:ssl.SSLContext,
)->HTTPServer:
    private_lan_ip(host)
    if type(port) is not int or port not in range(1024,65536):
        raise ValueError("P4_PAIRED_PORT_INVALID")
    minimum=getattr(tls_context,"minimum_version",None)
    if (tls_context is None or
        getattr(tls_context,"protocol",None) != ssl.PROTOCOL_TLS_SERVER or
        minimum is None or minimum < ssl.TLSVersion.TLSv1_2):
        raise ValueError("P4_HTTPS_TLS_CONTEXT_REQUIRED")
    server=HTTPServer((host,port),make_paired_handler(controller))
    try:
        server.socket=tls_context.wrap_socket(server.socket,server_side=True)
    except Exception:
        server.server_close()
        raise
    return server


# Future configured owner-only runtime supplies a real authorized source and
# on_activate worker; no server or paid provider starts from imports or CI.

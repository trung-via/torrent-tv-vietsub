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
from voiceover_audio_lane import VoiceoverAudioLane

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
    validate_voice: Callable[[], None] | None = None


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
                 authenticated_variant_factory: Callable[[str, str], VerifiedVietsubReady | None] | None = None,
                 recycle_sessions: bool = False):
        if type(recycle_sessions) is not bool:
            raise ValueError("P4_SESSION_RECYCLE_FLAG_INVALID")
        self.__recycle_sessions = recycle_sessions
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
        self.__voice_nonces: dict[tuple[str, str], float] = {}
        self.__refreshers: dict[str, Callable[[], None]] = {}
        self.__voice_refreshers: dict[str, Callable[[], None]] = {}
        self.__last_used: dict[str, float] = {}
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
                                and not callable(candidate.refresh))
                            or (candidate.validate_voice is not None
                                and not callable(candidate.validate_voice))):
                        raise ValueError("P4_PROGRESSIVE_SOURCE_MISMATCH")
                    progressive = candidate
            ready = None
            if (source is None and progressive is None and not variant_mode
                    and self.__vietsub_factory is not None):
                # The ready registry is populated ONLY by the existing owner
                # VI_FAST or EN→LEAN120 completion, never by a bare Play.
                # It independently rechecks the CURRENT signed TV session.
                candidate = self.__vietsub_factory(media)
                if candidate is not None:
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
                if not self.__recycle_sessions:
                    raise ValueError("P4_TOO_MANY_SESSIONS")
                # Only the one-TV Owner recycles an old memory session.
                victim = min(self.__feeds, key=lambda sid: self.__last_used.get(sid, 0.0))
                self.__feeds.pop(victim, None)
                self.__refreshers.pop(victim, None)
                self.__voice_refreshers.pop(victim, None)
                self.__last_used.pop(victim, None)
                self.__voice_nonces = {k: v for k, v in self.__voice_nonces.items()
                                      if k[0] != victim}
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
            self.__last_used[sid] = now
        if ready is not None:
            try:
                # Existing P4 signed feed; no Gemini/OpenSubtitles repeat.
                feed.publish(ready.as_final_revision())
            except Exception:
                with self.__lock:
                    self.__feeds.pop(sid, None)
                    self.__last_used.pop(sid, None)
                raise ValueError("P4_READY_FEED_PUBLISH_FAILED") from None
        if progressive is not None:
            try:
                progressive.subscribe(feed)
            except Exception:
                with self.__lock:
                    self.__feeds.pop(sid, None)
                    self.__last_used.pop(sid, None)
                raise ValueError("P4_PROGRESSIVE_FEED_BIND_FAILED") from None
            with self.__lock:
                if sid not in self.__feeds:
                    raise ValueError("P4_PROGRESSIVE_FEED_BIND_FAILED")
                if progressive.refresh is not None:
                    self.__refreshers[sid] = progressive.refresh
                if progressive.validate_voice is not None:
                    self.__voice_refreshers[sid] = progressive.validate_voice
        if source is not None and self.__on_activate is not None:
            try: self.__on_activate(feed,source)
            except Exception:
                with self.__lock:
                    self.__feeds.pop(sid, None)
                    self.__last_used.pop(sid, None)
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

    def authorize_voice_read(self, session_id: str, nonce: str | None,
                             signature: str | None, scope: str) -> bool:
        """An independent HMAC domain for the existing paired audio routes.

        The historical SessionRevisionFeed and P2 offline bundle are unchanged.
        This controller owns the key, nonce-replay ledger and source identity.
        """
        if (not isinstance(session_id, str)
                or not SESSION_RX.fullmatch(session_id)
                or not isinstance(scope, str)
                or not re.fullmatch(r"(manifest:[0-9]{1,6}|audio:[0-9a-f]{64})", scope)
                or not isinstance(nonce, str)
                or not NONCE_RX.fullmatch(nonce)
                or not isinstance(signature, str)
                or not MAC_RX.fullmatch(signature)):
            return False
        with self.__lock:
            feed = self.__feeds.get(session_id)
            if feed is None:
                return False
            key = derive_session_secret(
                self.__key, session_id, feed.media_key, feed.source_sha256)
            expected = hmac.new(
                key,
                ("TTV-P4-VOICE-READ-V1\n" + session_id + "\n"
                 + scope + "\n" + nonce).encode("ascii"),
                hashlib.sha256).hexdigest()
            if not hmac.compare_digest(expected, signature):
                return False
            now = time.monotonic()
            self.__voice_nonces = {
                k: ts for k, ts in self.__voice_nonces.items()
                if now - ts < 600.0
            }
            token = (session_id, nonce)
            if token in self.__voice_nonces or len(self.__voice_nonces) >= 8192:
                return False
            self.__voice_nonces[token] = now
            self.__last_used[session_id] = now
        return True

    def sign_voiceover(self, feed: SessionRevisionFeed, revision: object,
                       receipt: object, voice_id: str) -> object:
        """Sign a verified cue for this controller's original active P4 key."""
        from voiceover_signed_offer import sign_voiceover_offer
        if not isinstance(feed, SessionRevisionFeed):
            raise ValueError("P4_VOICE_SESSION_NOT_PAIRED")
        with self.__lock:
            if self.__feeds.get(feed.session_id) is not feed:
                raise ValueError("P4_VOICE_SESSION_NOT_PAIRED")
            key = derive_session_secret(
                self.__key, feed.session_id, feed.media_key, feed.source_sha256)
        if getattr(revision, "source_sha256", None) != feed.source_sha256:
            raise ValueError("P4_VOICE_DELIVERY_SOURCE_MISMATCH")
        return sign_voiceover_offer(
            revision=revision, receipt=receipt, voice_id=voice_id,
            session_id=feed.session_id, pairing_secret=key,
            delivery_media_key=feed.media_key)

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
        try:
            if refresh is not None:
                refresh()
            with self.__lock:
                if session_id not in self.__feeds:
                    return False
                self.__last_used[session_id] = time.monotonic()
            return True
        except Exception:
            return False

    def validate_voice_for(self, session_id: str) -> bool:
        """Check live scope, not every P2 checkpoint for each WAV."""
        with self.__lock:
            if session_id not in self.__feeds:
                return False
            check = self.__voice_refreshers.get(session_id) or self.__refreshers.get(session_id)
        if check is None:
            return False
        try:
            check()
            with self.__lock:
                return session_id in self.__feeds
        except Exception:
            return False


def make_paired_handler(
        controller: PairedActivation, *,
        on_event: Callable[[str], object] | None = None,
        voiceover_lane: VoiceoverAudioLane | None = None,
        ) -> Type[BaseHTTPRequestHandler]:
    """Optional owner-private fixed-code telemetry; never echo errors to TV."""
    if on_event is not None and not callable(on_event):
        raise ValueError("P4_EVENT_CALLBACK_INVALID")
    if voiceover_lane is not None and not isinstance(voiceover_lane, VoiceoverAudioLane):
        raise ValueError("P4_VOICE_LANE_INVALID")

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

        def _voice_get(self) -> None:
            # The original authenticated P4 listener handles metadata and WAV.
            # Never call a model or accept a filesystem path from the client.
            if voiceover_lane is None:
                self.send_error(404); return
            is_manifest = self.path.startswith("/p4/voice/")
            is_audio = self.path.startswith("/p4/audio/")
            if not is_manifest and not is_audio:
                self.send_error(404); return
            parts = self.path.strip("/").split("/")
            if (len(parts) != (3 if is_manifest else 4)
                    or parts[:2] != ["p4", "voice" if is_manifest else "audio"]):
                self.send_error(404); return
            sid = parts[2]
            if not SESSION_RX.fullmatch(sid):
                self.send_error(404); return
            feed = controller.feed_for(sid)
            if feed is None:
                self.send_error(404); return
            if is_manifest:
                raw_cursor = self.headers.get("X-P4-After-Cue", "0")
                if (not re.fullmatch(r"(0|[1-9][0-9]{0,5})", raw_cursor)
                        or int(raw_cursor) > 100_000):
                    self.send_error(400); return
                after_cue = int(raw_cursor)
                scope = "manifest:" + raw_cursor
            else:
                tts_key = parts[3]
                if not re.fullmatch(r"[0-9a-f]{64}", tts_key):
                    self.send_error(404); return
                scope = "audio:" + tts_key
            if not controller.authorize_voice_read(
                    sid, self.headers.get("X-P4-Nonce"),
                    self.headers.get("X-P4-Authorization"), scope):
                self.send_error(401); return
            if not controller.validate_voice_for(sid):
                report("P4_VOICE_CURRENT_SOURCE_HOLD")
                self.send_error(403); return
            try:
                if is_manifest:
                    payload = voiceover_lane.manifest(
                        feed, signer=controller.sign_voiceover, after_cue=after_cue)
                    has_offers = bool(json.loads(payload)["offers"])
                    if not has_offers:
                        self.send_response(204)
                        self.send_header("Cache-Control", "no-store")
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                    kind = "application/json"
                    digest = None
                else:
                    result = voiceover_lane.audio_bytes(feed, tts_key)
                    if result is None:
                        self.send_error(404); return
                    payload, digest = result
                    kind = "audio/wav"
            except Exception:
                report("P4_VOICE_VERIFICATION_HOLD")
                self.send_error(403); return
            self.send_response(200)
            self.send_header("Content-Type", kind)
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            if digest is not None:
                self.send_header("X-P4-Audio-Sha256", digest)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            report("P4_VOICE_MANIFEST_HTTP_200" if is_manifest
                   else "P4_VOICE_WAV_HTTP_200")

        def do_GET(self) -> None:
            if self.path.startswith(("/p4/voice/", "/p4/audio/")):
                return self._voice_get()
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

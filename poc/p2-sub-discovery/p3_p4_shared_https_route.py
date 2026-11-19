"""Opt-in P3 route on the EXISTING P4 paired HTTPS handler.

Do not start a second server or expose a new unauthenticated endpoint.
The caller must explicitly construct a SignedP3ToOwner with an independently
trusted current-TV reader and the SAME P4 pairing secret used by the TV.
Then construct this handler instead of make_paired_handler(controller) on an
already approved owner-local P4 HTTPS server.

Merely constructing/importing this module opens NO socket, does NOT start
Windows Task Scheduler/service and never invokes Gemini or OpenSubtitles.
This is a route composition seam; real device/session attestation is a
separate required source. The handler cannot manufacture that evidence.
"""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler
from typing import Type

from paired_activation import PairedActivation, make_paired_handler
from p3_signed_signal_to_owner import SignedP3ToOwner
from p3_signed_playback_signal import MAX_WIRE_BYTES
from p3_redmi_current_state import (
    RedmiStateRejected, SignedRedmiStateCache, WIRE_MAX,
)
from p3_ingress_telemetry import P3IngressTelemetry

P3_POST_ROUTE = "/p3/selection"
P3_STATE_ROUTE = "/p3/state"

# Map only the typed, source-defined decision vocabulary. These classifications
# are internal counters, never sent in HTTP errors, logs or persisted payloads.
_SELECTION_REASONS = {
    "SIGNED_TV_MESSAGE_INVALID": "bad_wire",
    "OWNER_CURRENT_TV_READ_FAILED": "current_tv_or_torrserver_unavailable",
    "TRUSTED_SOURCE_UNAVAILABLE": "current_tv_or_torrserver_unavailable",
    "MALFORMED_EVENT": "current_tv_or_torrserver_unavailable",
    "UNATTESTED_OR_STALE_SELECTION": "current_tv_or_torrserver_unavailable",
    "TV_VIEWER_REQUEST_CURRENT_MEDIA_MISMATCH": "media_mismatch",
    "VIEWER_REQUEST_SOURCE_CHANGED": "media_mismatch",
    "MEDIA_IDENTITY_UNVERIFIED": "media_mismatch",
    "OWNER_AUTO_DISABLED": "owner_policy",
    "SUBTITLE_CHOICE_UNKNOWN": "owner_policy",
    "VIEWER_OFF_OR_OTHER": "owner_policy",
    "MEDIA_POLICY_NOT_APPROVED": "owner_policy",
    "NO_VERIFIED_VIEWER_REQUEST": "owner_policy",
    "VI_TRACK_STATUS_INVALID": "owner_policy",
    "OWNER_PLAYBACK_PRIVATE_ENQUEUE_FAILED": "enqueue",
}


def _selection_reason_bucket(reason: object) -> str:
    """Conservatively classify a known rejection, never inspect raw details."""
    if type(reason) is not str:
        return "unknown"
    return _SELECTION_REASONS.get(reason, "unknown")


def make_p3_p4_handler(
    controller: PairedActivation, p3: SignedP3ToOwner,
    state_cache: SignedRedmiStateCache | None = None,
    ingress: P3IngressTelemetry | None = None,
) -> Type[BaseHTTPRequestHandler]:
    """Compose one private TLS listener; preserve P4 GET and /p4/activate."""

    if not isinstance(controller, PairedActivation):
        raise ValueError("P3_P4_PAIRED_GATEWAY_REQUIRED")
    if not isinstance(p3, SignedP3ToOwner):
        raise ValueError("P3_OWNER_VERIFIED_SOURCE_REQUIRED")

    if state_cache is not None and not isinstance(state_cache, SignedRedmiStateCache):
        raise ValueError("P3_PAIRED_REDMI_STATUS_REQUIRED")
    if ingress is not None and not isinstance(ingress, P3IngressTelemetry):
        raise ValueError("P3_INGRESS_COUNTER_REQUIRED")

    P4Handler = make_paired_handler(controller)

    class PairedP3P4Handler(P4Handler):
        def do_POST(self) -> None:
            if self.path not in (P3_POST_ROUTE, P3_STATE_ROUTE):
                # Existing P4 route owns all other POSTs, with its own auth.
                return super().do_POST()
            is_state = self.path == P3_STATE_ROUTE

            def rejected(http_status: int, reason: str = "format") -> None:
                if ingress is not None:
                    ingress.record("state_rejected" if is_state
                                   else "selection_rejected")
                    if is_state:
                        # Only known, fixed private categories survive. Never
                        # persist raw exception text or return the category to TV.
                        ingress.record("state_rejected_" + reason)
                    else:
                        # HTTP framing uses the original `format` default.
                        # Other selection causes are fixed vocabulary only.
                        bucket = "http_format" if reason == "format" else reason
                        if bucket not in _SELECTION_REASONS.values() and bucket not in (
                                "http_format", "unknown"):
                            bucket = "unknown"
                        ingress.record("selection_rejected_" + bucket)
                try:
                    self.send_error(http_status)
                except (BrokenPipeError, ConnectionResetError,
                        ConnectionAbortedError):
                    # A TV that closes before receiving our rejection must
                    # not make the outer handler reject/count a second time.
                    pass

            if self.path == P3_STATE_ROUTE and state_cache is None:
                # State ingress must be explicitly configured by the owner.
                rejected(404)
                return
            if (self.headers.get("Content-Type", "").split(";", 1)[0].strip()
                    != "application/json"):
                rejected(415)
                return
            raw_length = self.headers.get("Content-Length")
            # Multiple Content-Length values and HTTP transfer encoding are
            # not supported. Never consume unbounded or chunked request bodies.
            if (self.headers.get("Transfer-Encoding") is not None
                    or raw_length is None
                    or self.headers.get_all("Content-Length") != [raw_length]
                    or not raw_length.isascii() or not raw_length.isdigit()
                    or len(raw_length) > 4):
                rejected(413)
                return
            length = int(raw_length)
            if not 1 <= length <= (WIRE_MAX if self.path == P3_STATE_ROUTE else MAX_WIRE_BYTES):
                rejected(413)
                return
            try:
                body = self.rfile.read(length)
                if len(body) != length:
                    rejected(400)
                    return
                if self.path == P3_STATE_ROUTE:
                    # A distinct authenticated status does NOT itself trigger
                    # an OpenSubtitles/Gemini request or owner-V3 enqueue.
                    state_cache.receive(body)
                    status_ok = True
                else:
                    decision = p3.on_wire(body)
                    status_ok = decision.status in ("DISPATCH", "SKIP")
                if status_ok:
                    if ingress is not None:
                        ingress.record("state_accepted" if is_state else (
                            "selection_dispatched" if decision.status == "DISPATCH"
                            else "selection_skipped"))
                    try:
                        self.send_response(204)
                        self.send_header("Cache-Control", "no-store")
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                    except (BrokenPipeError, ConnectionResetError,
                            ConnectionAbortedError):
                        # The accepted/skip decision remains authoritative;
                        # an abandoned HTTP response is not a new 403.
                        return
                else:
                    # Do not disclose which gate failed to the HTTP caller.
                    rejected(403, _selection_reason_bucket(decision.reason))
            except RedmiStateRejected as exc:
                code = exc.args[0] if exc.args else None
                if code == "P3_STATE_AUTH_FAILED":
                    category = "auth"
                elif code == "P3_STATE_CLOCK_SKEW":
                    category = "clock"
                elif code in (
                    "P3_STATE_REPLAY", "P3_STATE_BOOT_CHANGE_WHILE_FRESH",
                    "P3_STATE_OUT_OF_ORDER",
                    "P3_STATE_DURABLE_REPLAY_REJECTED",
                ):
                    category = "replay"
                else:
                    category = "format"
                rejected(403, category)
            except ValueError as exc:
                if is_state:
                    rejected(403, "other")
                else:
                    rejected(403, _selection_reason_bucket(
                        "OWNER_PLAYBACK_PRIVATE_ENQUEUE_FAILED"
                        if exc.args == ("OWNER_PLAYBACK_PRIVATE_ENQUEUE_FAILED",)
                        else None))
            except Exception:
                # No media filename/hash/path/secret or provider error in
                # HTTP response, stdout or BaseHTTPRequestHandler logs.
                rejected(403, "other" if is_state else "unknown")

    return PairedP3P4Handler

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
from p3_redmi_current_state import SignedRedmiStateCache, WIRE_MAX

P3_POST_ROUTE = "/p3/selection"
P3_STATE_ROUTE = "/p3/state"


def make_p3_p4_handler(
    controller: PairedActivation, p3: SignedP3ToOwner,
    state_cache: SignedRedmiStateCache | None = None,
) -> Type[BaseHTTPRequestHandler]:
    """Compose one private TLS listener; preserve P4 GET and /p4/activate."""

    if not isinstance(controller, PairedActivation):
        raise ValueError("P3_P4_PAIRED_GATEWAY_REQUIRED")
    if not isinstance(p3, SignedP3ToOwner):
        raise ValueError("P3_OWNER_VERIFIED_SOURCE_REQUIRED")

    if state_cache is not None and not isinstance(state_cache, SignedRedmiStateCache):
        raise ValueError("P3_PAIRED_REDMI_STATUS_REQUIRED")

    P4Handler = make_paired_handler(controller)

    class PairedP3P4Handler(P4Handler):
        def do_POST(self) -> None:
            if self.path not in (P3_POST_ROUTE, P3_STATE_ROUTE):
                # Existing P4 route owns all other POSTs, with its own auth.
                return super().do_POST()
            if self.path == P3_STATE_ROUTE and state_cache is None:
                # State ingress must be explicitly configured by the owner.
                self.send_error(404)
                return
            if (self.headers.get("Content-Type", "").split(";", 1)[0].strip()
                    != "application/json"):
                self.send_error(415)
                return
            raw_length = self.headers.get("Content-Length")
            # Multiple Content-Length values and HTTP transfer encoding are
            # not supported. Never consume unbounded or chunked request bodies.
            if (self.headers.get("Transfer-Encoding") is not None
                    or raw_length is None
                    or self.headers.get_all("Content-Length") != [raw_length]
                    or not raw_length.isascii() or not raw_length.isdigit()
                    or len(raw_length) > 4):
                self.send_error(413)
                return
            length = int(raw_length)
            if not 1 <= length <= (WIRE_MAX if self.path == P3_STATE_ROUTE else MAX_WIRE_BYTES):
                self.send_error(413)
                return
            try:
                body = self.rfile.read(length)
                if len(body) != length:
                    self.send_error(400)
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
                    self.send_response(204)
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                else:
                    # Do not disclose which gate failed to the HTTP caller.
                    self.send_error(403)
            except Exception:
                # No media filename/hash/path/secret or provider error in
                # HTTP response, stdout or BaseHTTPRequestHandler logs.
                self.send_error(403)

    return PairedP3P4Handler

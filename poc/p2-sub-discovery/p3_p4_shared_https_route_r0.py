"""R0 Owner P3 HTTPS handler while the installed V2 route stays SHA-pinned.

No extra listener, pairing secret, queue or provider. This is selected only by
the next controlled Owner entrypoint upgrade. Existing V2 remains immutable.
"""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler
from threading import Lock
from typing import Type

from paired_activation import PairedActivation, make_paired_handler
from p3_signed_signal_to_owner import SignedP3ToOwner
from p3_signed_playback_signal import MAX_WIRE_BYTES
from p3_redmi_current_state import RedmiStateRejected, SignedRedmiStateCache, WIRE_MAX
from p3_ingress_telemetry import P3IngressTelemetry
from p3_p4_shared_https_route import (
    P3_POST_ROUTE, P3_STATE_ROUTE, _selection_reason_bucket,
)
from owner_session_bridge import owner_full_trace


def make_p3_p4_handler_r0(
    controller: PairedActivation, p3: SignedP3ToOwner,
    state_cache: SignedRedmiStateCache | None = None,
    ingress: P3IngressTelemetry | None = None,
) -> Type[BaseHTTPRequestHandler]:
    if (not isinstance(controller, PairedActivation)
            or not isinstance(p3, SignedP3ToOwner)
            or (state_cache is not None
                and not isinstance(state_cache, SignedRedmiStateCache))
            or (ingress is not None
                and not isinstance(ingress, P3IngressTelemetry))):
        raise ValueError("P3_R0_VERIFIED_COMPOSITION_REQUIRED")
    P4Handler = make_paired_handler(
        controller,
        on_event=lambda code: owner_full_trace("P4_DELIVERY_STATUS", code=code))
    # ThreadingHTTPServer must not weaken the old single-threaded replay and
    # enqueue contract. Serialize selections separately from signed status:
    # a slow TorrServer probe may hold selection, but never TV heartbeats.
    selection_lock = Lock()
    state_lock = Lock()

    class R0PairedHandler(P4Handler):
        def send_error(self, code, message=None, explain=None):
            # Record errors on the shared P3/P4 listener, including responses
            # handled internally by the pre-existing P4 paired endpoint.
            owner_full_trace("P3_P4_HTTP_ERROR", status=code,
                             path=self.path, message=message,
                             explain=explain)
            return super().send_error(code, message, explain)

        def do_POST(self) -> None:
            if self.path not in (P3_POST_ROUTE, P3_STATE_ROUTE):
                return super().do_POST()
            is_state = self.path == P3_STATE_ROUTE
            if not is_state:
                owner_full_trace("P3_SELECTION_RECEIVED", path=self.path,
                                 length=self.headers.get("Content-Length"))

            def rejected(code: int, category: str = "format") -> None:
                if not is_state:
                    owner_full_trace("P3_SELECTION_REJECTED", status=code,
                                     category=category)
                if ingress is not None:
                    ingress.record("state_rejected" if is_state
                                   else "selection_rejected")
                    if is_state:
                        ingress.record("state_rejected_" + category)
                    else:
                        bucket = "http_format" if category == "format" else category
                        ingress.record("selection_rejected_" + bucket)
                # A disconnected TV must not trigger a second rejection,
                # traceback or bogus telemetry event.
                try:
                    self.send_error(code)
                except (BrokenPipeError, ConnectionAbortedError,
                        ConnectionResetError):
                    pass

            if is_state and state_cache is None:
                rejected(404)
                return
            if (self.headers.get("Content-Type", "").split(";", 1)[0].strip()
                    != "application/json"):
                rejected(415)
                return
            raw_length = self.headers.get("Content-Length")
            if (self.headers.get("Transfer-Encoding") is not None
                    or raw_length is None
                    or self.headers.get_all("Content-Length") != [raw_length]
                    or not raw_length.isascii() or not raw_length.isdigit()
                    or len(raw_length) > 4):
                rejected(413)
                return
            length = int(raw_length)
            if not 1 <= length <= (WIRE_MAX if is_state else MAX_WIRE_BYTES):
                rejected(413)
                return

            try:
                body = self.rfile.read(length)
                if len(body) != length:
                    rejected(400)
                    return
                if is_state:
                    with state_lock:
                        state_cache.receive(body)
                    status = "STATE_ACCEPTED"
                    reason = ""
                else:
                    with selection_lock:
                        decision = p3.on_wire(body)
                    status = decision.status
                    reason = decision.reason
            except RedmiStateRejected as exc:
                owner_full_trace("P3_SIGNED_STATE_REJECTED", error=exc)
                code = exc.args[0] if exc.args else None
                category = ("auth" if code == "P3_STATE_AUTH_FAILED"
                            else "clock" if code == "P3_STATE_CLOCK_SKEW"
                            else "replay" if code in (
                                "P3_STATE_REPLAY", "P3_STATE_BOOT_CHANGE_WHILE_FRESH",
                                "P3_STATE_OUT_OF_ORDER",
                                "P3_STATE_DURABLE_REPLAY_REJECTED")
                            else "format")
                rejected(403, category)
                return
            except ValueError as exc:
                owner_full_trace("P3_PROCESSING_REJECTED", error=exc,
                                 is_state=is_state)
                category = ("other" if is_state else (
                    "enqueue" if exc.args == (
                        "OWNER_PLAYBACK_PRIVATE_ENQUEUE_FAILED",) else "unknown"))
                rejected(403, category)
                return
            except Exception as exc:
                owner_full_trace("P3_PROCESSING_FAILED", error=exc,
                                 is_state=is_state)
                rejected(403, "other" if is_state else "unknown")
                return

            if not is_state and status not in ("DISPATCH", "SKIP"):
                # WAIT/CHECK_LOCAL_VI_TRACKS is a real reader/probe HOLD,
                # never an unexplained rejection or an Owner policy refusal.
                reason_bucket = (
                    "current_tv_or_torrserver_unavailable"
                    if status == "WAIT" and reason == "CHECK_LOCAL_VI_TRACKS"
                    else _selection_reason_bucket(reason))
                rejected(403, reason_bucket)
                return
            if ingress is not None:
                ingress.record("state_accepted" if is_state else (
                    "selection_dispatched" if status == "DISPATCH"
                    else "selection_skipped"))
            if not is_state:
                owner_full_trace("P3_SELECTION_ACCEPTED", status=status,
                                 reason=reason)
            # A successful queue write remains successful even when the TV
            # has disconnected before receipt delivery.
            try:
                self.send_response(204)
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", "0")
                self.end_headers()
            except (BrokenPipeError, ConnectionAbortedError,
                    ConnectionResetError):
                pass

    return R0PairedHandler

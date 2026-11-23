"""Bounded, non-identifying counters for P3 traffic on the original P4 HTTPS port.

The counters are process-local and contain no raw request, client address,
token, exception, selected media identifier, or provider information. They
do not authenticate requests; the original P3 handlers remain responsible.
"""
from __future__ import annotations

from threading import Lock

EVENTS = frozenset((
    "state_accepted", "state_rejected", "selection_dispatched",
    "selection_skipped", "selection_rejected",
    "selection_rejected_bad_wire",
    "selection_rejected_current_tv_or_torrserver_unavailable",
    "selection_rejected_media_mismatch",
    "selection_rejected_owner_policy",
    "selection_rejected_enqueue",
    "selection_rejected_http_format",
    "selection_rejected_unknown",
    "selection_rejected_brain_source_pending",
    "state_rejected_auth", "state_rejected_clock",
    "state_rejected_replay", "state_rejected_format",
    "state_rejected_other",
))
MAX_COUNT = 1_000_000


class P3IngressTelemetry:
    """The same instance is shared by the HTTPS handler and Owner diagnostic."""

    def __init__(self) -> None:
        self._lock = Lock()
        self._counts = {name: 0 for name in sorted(EVENTS)}

    def record(self, event: str) -> None:
        if type(event) is not str or event not in EVENTS:
            raise ValueError("P3_INGRESS_EVENT_INVALID")
        with self._lock:
            self._counts[event] = min(MAX_COUNT, self._counts[event] + 1)

    def snapshot(self) -> dict[str, int]:
        with self._lock:
            return self._counts.copy()

"""Opt-in ONE-process owner V3 + original P4 HTTPS runtime.

This is NOT an installed service, an alternate player, a new model worker or
permission to contact a real TV. The logged-in owner must supply real,
independently authenticated readers to compose_owner_redmi_status() FIRST.
Importing this module does not bind a port, read a secret or call a provider.

Only run_owner_p3_p4_runtime() explicitly starts the already-composed HTTPS
handler alongside the EXISTING run_owner_agent + trusted_v3_factory. The same
verified-ready registry and PairedActivation serve the original P4 revision.
"""
from __future__ import annotations

import os
from http.server import HTTPServer
from pathlib import Path
import ssl
from threading import Thread
from typing import Callable

from owner_session_bridge import run_owner_agent
# p3_owner_state_wiring installs this repository's two pinned sibling paths.
from p3_owner_state_wiring import OwnerP3StatusComposition
from lan_revision_feed import private_lan_ip
from p4_tls import create_tls_context


class OwnerRuntimeBlocked(ValueError):
    """Fixed, non-sensitive failure reason; never report media or key."""


def _validate_wiring(wiring: OwnerP3StatusComposition) -> None:
    if (not isinstance(wiring, OwnerP3StatusComposition)
            or wiring.ready_registry is None
            or wiring.p4_gateway is None
            or not callable(wiring.handler)
            or not callable(wiring.trusted_v3_factory)):
        raise OwnerRuntimeBlocked("P3_P4_VERIFIED_READY_WIRING_REQUIRED")


def make_integrated_https_server(*, wiring: OwnerP3StatusComposition,
                                 host: str, port: int,
                                 tls_context: ssl.SSLContext) -> HTTPServer:
    """Make ONE P3+P4 server, explicitly; never use a separate P3 listener.

    Equivalent TLS/IP/port gates to paired_activation.create_paired_server,
    but uses the existing composed handler instead of a P4-only handler.
    """
    _validate_wiring(wiring)
    private_lan_ip(host)
    if type(port) is not int or not 1024 <= port <= 65535:
        raise OwnerRuntimeBlocked("P3_P4_PORT_INVALID")
    if (not isinstance(tls_context, ssl.SSLContext)
            or tls_context.protocol != ssl.PROTOCOL_TLS_SERVER
            or tls_context.minimum_version < ssl.TLSVersion.TLSv1_2):
        raise OwnerRuntimeBlocked("P3_P4_TLS_CONTEXT_REQUIRED")
    server = HTTPServer((host, port), wiring.handler)
    try:
        server.socket = tls_context.wrap_socket(server.socket, server_side=True)
    except Exception:
        server.server_close()
        raise OwnerRuntimeBlocked("P3_P4_TLS_BIND_FAILED") from None
    return server


def _serve_and_consume(*, server: HTTPServer, wiring: OwnerP3StatusComposition,
                       owner_root: Path, cache_root: Path, state_root: Path,
                       interval_seconds: float,
                       agent: Callable[..., object]) -> None:
    """Lifecycle seam tested with fake server/agent; no extra queue/worker."""
    _validate_wiring(wiring)
    listener = Thread(target=server.serve_forever,
                      kwargs={"poll_interval": 0.2},
                      name="torrent-tv-owner-p3-p4-https", daemon=True)
    try:
        listener.start()
        agent(private_root=owner_root, cache_root=cache_root,
              state_root=state_root, interval_seconds=interval_seconds,
              trusted_v3_factory=wiring.trusted_v3_factory)
    finally:
        try:
            if listener.is_alive():
                server.shutdown()
        finally:
            server.server_close()
            if listener.is_alive():
                listener.join(timeout=5.0)


def run_owner_p3_p4_runtime(*, wiring: OwnerP3StatusComposition,
                            owner_root: Path, cache_root: Path,
                            state_root: Path, host: str, port: int,
                            tls_cert: Path, tls_key: Path,
                            explicit_start_lan: bool = False,
                            interval_seconds: float = 2.0) -> None:
    """Owner-only foreground entrypoint; requires separate real-host approval.

    Never invoked by GitHub, the existing Task Scheduler launcher or import.
    The private reader/rights/VI-inventory callbacks are mandatory upstream;
    this function neither invents consent nor reads a filename from TV wire.
    """
    _validate_wiring(wiring)
    if (explicit_start_lan is not True
            or os.name != "nt"
            or os.environ.get("CI", "").lower() == "true"
            or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"):
        raise OwnerRuntimeBlocked("P3_P4_EXPLICIT_INTERACTIVE_OWNER_START_REQUIRED")
    for root in (owner_root, cache_root, state_root):
        if (not isinstance(root, Path) or not root.is_absolute()
                or root.is_symlink()):
            raise OwnerRuntimeBlocked("P3_P4_PRIVATE_ROOT_INVALID")
    if not owner_root.is_dir():
        raise OwnerRuntimeBlocked("P3_P4_OWNER_ROOT_NOT_ENROLLED")
    # Pairing material must stay in this owner's private enrolled tree.
    for pem in (tls_cert, tls_key):
        if (not isinstance(pem, Path) or not pem.is_absolute()
                or pem.is_symlink() or not pem.is_file()
                or not pem.is_relative_to(owner_root)):
            raise OwnerRuntimeBlocked("P3_P4_PRIVATE_TLS_FILES_REQUIRED")
    if not 0.5 <= interval_seconds <= 60.0:
        raise OwnerRuntimeBlocked("P3_P4_POLL_INTERVAL_INVALID")
    private_lan_ip(host)
    context = create_tls_context(tls_cert, tls_key)
    server = make_integrated_https_server(
        wiring=wiring, host=host, port=port, tls_context=context)
    _serve_and_consume(
        server=server, wiring=wiring,
        owner_root=owner_root, cache_root=cache_root, state_root=state_root,
        interval_seconds=interval_seconds, agent=run_owner_agent)

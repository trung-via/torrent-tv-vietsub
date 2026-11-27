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
from http.server import HTTPServer, ThreadingHTTPServer
from pathlib import Path
import ssl
from threading import Thread
from typing import Callable

from owner_session_bridge import run_owner_agent
from owner_p3_p4_diagnostics import write_diagnostic
from owner_full_flow_snapshot_v4 import publish_owner_snapshot_v4
# p3_owner_state_wiring installs this repository's two pinned sibling paths.
from p3_owner_state_wiring import OwnerP3StatusComposition
from lan_revision_feed import private_lan_ip
from p4_tls import create_tls_context


class OwnerRuntimeBlocked(ValueError):
    """Fixed, non-sensitive failure reason; never report media or key."""


def _diagnostic_tick(*, owner_root: Path, wiring: OwnerP3StatusComposition,
                     state: str) -> None:
    """Keep old installed diagnostic pins, optionally publish sanitized copy."""
    write_diagnostic(owner_root=owner_root, wiring=wiring, state=state)
    try:
        publish_owner_snapshot_v4(owner_root=owner_root)
    except (OSError, ValueError):
        # A missing/locked HostOps reader is not a reason to stop the Owner.
        pass


def _interactive_windows_session() -> bool:
    """Kernel-sourced Windows session ID, never trust a caller assertion.

    Session 0 (including the GitHub NETWORK_SERVICE runner) is forbidden.
    The owner-only PowerShell launcher also checks WindowsIdentity SID.
    """
    if os.name != "nt":
        return False
    try:
        import ctypes
        from ctypes import wintypes
        session = wintypes.DWORD()
        ok = ctypes.windll.kernel32.ProcessIdToSessionId(
            os.getpid(), ctypes.byref(session))
        return bool(ok) and session.value > 0
    except Exception:
        return False


def _validate_wiring(wiring: OwnerP3StatusComposition) -> None:
    if (not isinstance(wiring, OwnerP3StatusComposition)
            or wiring.ready_registry is None
            or wiring.p4_gateway is None
            or not callable(wiring.handler)
            or not callable(wiring.trusted_v3_factory)):
        raise OwnerRuntimeBlocked("P3_P4_VERIFIED_READY_WIRING_REQUIRED")


def _validate_owner_root(wiring: OwnerP3StatusComposition,
                         owner_root: Path) -> None:
    """P3 producer and existing owner V3 consumer MUST use one inbox root."""
    _validate_wiring(wiring)
    if (not isinstance(owner_root, Path) or not owner_root.is_absolute()
            or owner_root.is_symlink()
            or not isinstance(wiring.owner_root, Path)
            or not wiring.owner_root.is_absolute()
            or wiring.owner_root.is_symlink()
            or owner_root.resolve(strict=False) !=
               wiring.owner_root.resolve(strict=False)):
        raise OwnerRuntimeBlocked("P3_P4_PRIVATE_INBOX_ROOT_MISMATCH")


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
    # P3 /p3/state arrives every three seconds. A metadata/ffprobe read for
    # /p3/selection must not hold that heartbeat behind a single HTTP worker
    # until the authenticated eight-second TV snapshot expires.
    server = ThreadingHTTPServer((host, port), wiring.handler)
    server.daemon_threads = True
    try:
        server.socket = tls_context.wrap_socket(server.socket, server_side=True)
    except Exception:
        server.server_close()
        raise OwnerRuntimeBlocked("P3_P4_TLS_BIND_FAILED") from None
    return server


def _native_owner_factory(wiring):
    """Opt-in source candidate; no provider or Chrome operation at startup."""
    from p3_owner_state_wiring_r2 import R2OwnerP3StatusComposition
    from agy_v13_native_producer import owner_native_runner
    from agy_v13_browser_evidence import make_v13_acquirer
    if not isinstance(wiring, R2OwnerP3StatusComposition):
        raise OwnerRuntimeBlocked("P3_P4_NATIVE_R2_REQUIRED")
    runner = owner_native_runner(wiring.current._ts)
    def factory(flow):
        flow.source_acquirer = make_v13_acquirer(runner)
        return wiring.trusted_v3_factory(flow)
    if os.environ.get("TTV_G2_WARM") == "1":
        factory.g2_discover = runner.discover_movies
    return factory


def _serve_and_consume(*, server: HTTPServer, wiring: OwnerP3StatusComposition,
                       owner_root: Path, cache_root: Path, state_root: Path,
                       interval_seconds: float,
                       agent: Callable[..., object]) -> None:
    """Lifecycle seam tested with fake server/agent; no extra queue/worker."""
    _validate_wiring(wiring)
    # Wire the exact Owner cache before listening: a missing Brain SRT
    # must not be consumed into a terminal REVIEW_REQUIRED event.
    from p3_signed_signal_to_owner import SignedP3ToOwner
    native = os.environ.get("TTV_NATIVE_V13") == "1"
    listener = Thread(target=server.serve_forever,
                      kwargs={"poll_interval": 0.2},
                      name="torrent-tv-owner-p3-p4-https", daemon=True)
    try:
        factory = _native_owner_factory(wiring) if native else wiring.trusted_v3_factory
        if not native and isinstance(getattr(wiring, "signal", None), SignedP3ToOwner):
            wiring.signal.bind_brain_english_inbox(cache_root)
        listener.start()
        agent(private_root=owner_root, cache_root=cache_root,
              state_root=state_root, interval_seconds=interval_seconds,
              trusted_v3_factory=factory,
              diagnostic_tick=lambda state: _diagnostic_tick(
                  owner_root=owner_root, wiring=wiring, state=state))
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
    _validate_owner_root(wiring, owner_root)
    if (explicit_start_lan is not True
            or not _interactive_windows_session()
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
                or not pem.resolve(strict=True).is_relative_to(
                    owner_root.resolve(strict=True))):
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

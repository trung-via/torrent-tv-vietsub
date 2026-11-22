"""Opt-in logged-in owner bootstrap for ONE P3 status/selection + P4 HTTPS.

Reuses the already-enrolled owner's P4 pairing/cert identity, existing owner
V3 event loop, and the signed-in Owner Antigravity CLI. An enabled, empty
owner media list selects personal single-owner stream mode with exact local
TorrServer metadata and independent VI probing; nonempty lists retain legacy
per-film pins. Missing policy/pairing/bootstrap -> HOLD before opening port.

No auto pairing, TV install, secret logging, external upload, or Windows task
installation. Importing this module has no side effects.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import ssl
import sys

# The installed Windows owner task runs this file directly, without PYTHONPATH.
# Bootstrap ONLY our two adjacent, source-pinned plugin directories *before*
# importing modules that themselves import paired_activation / matcher / P2.
# This same layout is copied by install-owner-session-bridge.ps1.
_POC_ROOT = Path(__file__).resolve().parent.parent
for _sibling in ("p2-aisub", "p3-vietsub-trigger"):
    _path = _POC_ROOT / _sibling
    if not _path.is_dir():
        raise RuntimeError("P3_P4_OWNER_PINNED_DEPENDENCY_NOT_INSTALLED")
    _text = str(_path)
    if _text not in sys.path:
        sys.path.insert(0, _text)

from owner_p3_p4_policy_r0 import R0PrivateP3P4Policy
from owner_p3_p4_runtime import (
    _interactive_windows_session, run_owner_p3_p4_runtime,
)
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader
from owner_session_bridge import (
    install_owner_full_diagnostics, owner_full_trace,
)
from p3_owner_state_wiring_r2 import compose_owner_redmi_status
from lan_revision_feed import private_lan_ip


class OwnerEntrypointBlocked(ValueError):
    """Safe reason code without host IP, film, path or credential."""


def _read_private_file(path: Path, max_size: int) -> str:
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= max_size:
        raise OwnerEntrypointBlocked("P3_P4_PRIVATE_FILE_MISSING_OR_INVALID")
    try:
        return path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        raise OwnerEntrypointBlocked("P3_P4_PRIVATE_FILE_UNREADABLE") from None


def _pair_and_stage_identity(owner_root: Path) -> tuple[bytes, str, int, Path, Path]:
    """Retain same P4 pinned leaf: copying PEM doesn't rotate TV certificate."""
    if (not owner_root.is_absolute() or owner_root.is_symlink()
            or not owner_root.is_dir()
            or owner_root.name != "OwnerBridge"):
        raise OwnerEntrypointBlocked("P3_P4_OWNER_ENROLLMENT_REQUIRED")
    home = owner_root.parent
    p4 = home / "P4"
    if (p4.is_symlink() or not p4.is_dir()
            or p4.resolve(strict=True).parent != home.resolve(strict=True)):
        raise OwnerEntrypointBlocked("P3_P4_OWNER_PAIRING_NOT_ENROLLED")
    # Existing P4 owner-only bootstrap receipt confirms a prior explicit
    # ADB stage. It is NOT evidence of current live Redmi pairing/handshake.
    if not (p4 / "adb-staged-v1.receipt").is_file():
        raise OwnerEntrypointBlocked("P3_P4_TV_PAIRING_NOT_STAGED")
    key_hex = _read_private_file(p4 / "pairing-key.hex", 96)
    bind = _read_private_file(p4 / "gateway-bind.txt", 64)
    token = _read_private_file(p4 / "pairing-token.txt", 256)
    if not re.fullmatch(r"[0-9a-f]{64}", key_hex):
        raise OwnerEntrypointBlocked("P3_P4_PAIRING_KEY_INVALID")
    pair_parts = token.split("|")
    if (len(pair_parts) != 3 or pair_parts[0] != bind
            or pair_parts[1] != key_hex
            or not re.fullmatch(r"[0-9a-f]{64}", pair_parts[2])):
        raise OwnerEntrypointBlocked("P3_P4_PAIRING_TOKEN_MISMATCH")
    if not re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}:\d{4,5}", bind):
        raise OwnerEntrypointBlocked("P3_P4_PRIVATE_BIND_INVALID")
    host, port_text = bind.rsplit(":", 1)
    try:
        private_lan_ip(host)
        port = int(port_text)
    except ValueError:
        raise OwnerEntrypointBlocked("P3_P4_PRIVATE_BIND_INVALID") from None
    if not 1024 <= port <= 65535:
        raise OwnerEntrypointBlocked("P3_P4_PRIVATE_PORT_INVALID")
    source_cert = p4 / "pc-cert.pem"
    source_key = p4 / "pc-key.pem"
    cert_text = _read_private_file(source_cert, 8192)
    key_text = _read_private_file(source_key, 16384)
    try:
        digest = hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert_text)).hexdigest()
    except ValueError:
        raise OwnerEntrypointBlocked("P3_P4_TLS_CERT_INVALID") from None
    if digest != pair_parts[2]:
        raise OwnerEntrypointBlocked("P3_P4_EXISTING_TV_TLS_PIN_MISMATCH")
    # Existing enrolled OwnerBridge root has its owner-only Windows ACL.
    # A previous staged identity must MATCH byte-for-byte; no implicit
    # overwrite/rotation (which would silently break the TV pin).
    private = owner_root / "p4-identity"
    if private.is_symlink():
        raise OwnerEntrypointBlocked("P3_P4_PRIVATE_STAGE_SYMLINK")
    private.mkdir(mode=0o700, exist_ok=True)
    for name, source in (("pc-cert.pem", source_cert), ("pc-key.pem", source_key)):
        destination = private / name
        if destination.is_symlink():
            raise OwnerEntrypointBlocked("P3_P4_PRIVATE_STAGE_SYMLINK")
        data = source.read_bytes()
        if destination.exists():
            if not destination.is_file() or destination.read_bytes() != data:
                raise OwnerEntrypointBlocked("P3_P4_PREVIOUS_PINNED_IDENTITY_CHANGED")
        else:
            fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
    return (bytes.fromhex(key_hex), host, port,
            private / "pc-cert.pem", private / "pc-key.pem")


def build_private_composition(*, owner_root: Path,
                              policy_file: Path,
                              private_media_root: Path,
                              key: bytes, torrserver_profile: str,
                              torrserver_port: int):
    reader = OwnerTorrServerReader(
        OwnerLocalTorrServer(torrserver_profile, torrserver_port))
    policy = R0PrivateP3P4Policy(
        manifest=policy_file, owner_root=owner_root,
        private_media_root=private_media_root,
        torrserver=reader)
    if policy.owner_auto_allowed() is not True:
        raise OwnerEntrypointBlocked("P3_P4_OWNER_AUTO_DISABLED")
    return compose_owner_redmi_status(
        p4_gateway=None, paired_device_secret=key,
        torrserver_reader=reader,
        owner_root=owner_root, private_media_root=private_media_root,
        owner_auto_allowed=policy.owner_auto_allowed,
        media_rights_allowed=policy.media_rights_allowed,
        verified_local_vi_state=policy.verified_local_vi_state,
        locate_owner_pinned_files=policy.locate_owner_pinned_files,
        selected_file_inspector=policy.inspect_verified_file,
        enable_verified_vietsub_ready=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Owner-only integrated P3/P4")
    parser.add_argument("--owner-root", required=True)
    parser.add_argument("--cache-root", required=True)
    parser.add_argument("--state-root", required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--start-lan", action="store_true")
    mode.add_argument("--preflight-only", action="store_true")
    args = parser.parse_args(argv)
    if (os.name != "nt"
            or not _interactive_windows_session()
            or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"
            or os.environ.get("CI", "").lower() == "true"):
        print("P3_P4_OWNER_INTERACTIVE_EXPLICIT_START_REQUIRED")
        return 1
    try:
        owner = Path(args.owner_root).resolve(strict=True)
        if args.start_lan:
            # One complete private Owner diagnostic file for P3, P2 and P4.
            # The Owner session retains every exception and original console
            # line. Nothing in this path is copied to public CI/HostOps logs.
            install_owner_full_diagnostics(owner)
        cache = Path(args.cache_root).resolve(strict=False)
        state = Path(args.state_root).resolve(strict=False)
        policy_path = owner / "p3-p4-policy.json"
        if (not policy_path.is_file() or policy_path.is_symlink()
                or policy_path.stat().st_size > 32768):
            raise OwnerEntrypointBlocked("P3_P4_OWNER_POLICY_NOT_CONFIGURED")
        policy_doc = json.loads(policy_path.read_text(encoding="utf-8"))
        if not isinstance(policy_doc, dict):
            raise OwnerEntrypointBlocked("P3_P4_POLICY_INVALID")
        media_root = Path(policy_doc.get("private_media_root", ""))
        # A dedicated absolute media root is REQUIRED. Never broaden to C:\
        # or the user's whole profile as a fallback.
        if not media_root.is_absolute() or media_root.is_symlink():
            raise OwnerEntrypointBlocked("P3_P4_PINNED_MEDIA_ROOT_REQUIRED")
        profile = policy_doc.get("profile_id")
        port_ts = policy_doc.get("torrserver_port")
        if type(port_ts) is not int:
            raise OwnerEntrypointBlocked("P3_P4_OWNER_TS_PROFILE_REQUIRED")
        # Validate policy before copying private PEM into the agent root.
        reader = OwnerTorrServerReader(OwnerLocalTorrServer(profile, port_ts))
        verified = R0PrivateP3P4Policy(
            manifest=policy_path, owner_root=owner,
            private_media_root=media_root, torrserver=reader)
        if not verified.owner_auto_allowed():
            raise OwnerEntrypointBlocked("P3_P4_OWNER_AUTO_DISABLED")
        key, host, port, cert, pem = _pair_and_stage_identity(owner)
        wiring = compose_owner_redmi_status(
            p4_gateway=None, paired_device_secret=key,
            torrserver_reader=reader,
            owner_root=owner, private_media_root=media_root,
            owner_auto_allowed=verified.owner_auto_allowed,
            media_rights_allowed=verified.media_rights_allowed,
            verified_local_vi_state=verified.verified_local_vi_state,
            locate_owner_pinned_files=verified.locate_owner_pinned_files,
            selected_file_inspector=verified.inspect_verified_file,
            enable_verified_vietsub_ready=True)
        print("P3_P4_PRIVATE_OWNER_POLICY_PAIRING_VERIFIED")
        if args.preflight_only:
            # Owner-only deployment gate: verify genuine private policy and
            # reuse identical paired PEM bytes without opening LAN, enqueueing
            # media, contacting providers or starting a background worker.
            print("P3_P4_OWNER_PREFLIGHT=PASS_NO_LAN_NO_PROVIDER")
            return 0
        run_owner_p3_p4_runtime(
            wiring=wiring, owner_root=owner, cache_root=cache,
            state_root=state, host=host, port=port,
            tls_cert=cert, tls_key=pem, explicit_start_lan=True)
    except (ValueError, OSError, RuntimeError, TypeError, KeyError,
            json.JSONDecodeError) as exc:
        owner_full_trace("OWNER_P3_P4_STARTUP_FAILED", error=exc)
        # Never print original private path, hostname, media, key or provider.
        print("P3_P4_OWNER_STARTUP_HOLD_PRIVATE_REVIEW")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

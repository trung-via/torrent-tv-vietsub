"""Explicit PC-only prototype entrypoint: assumed EN source -> API -> paired TV.

DOES NOT execute on import or in GitHub CI. No source discovery, no
TorrServer/admin operations, no Windows service/firewall/UPnP modifications.
One permitted PC LAN interface, one pre-supplied timed SRT/VTT and media key.

PC only serves HTTPS with an explicit certificate/key outside the repository.
The TV must pin the PC leaf certificate's SHA256 and verify its IP-SAN.
No listener starts without --start-lan, --tls-cert and --tls-key.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import threading

from assumed_source_handoff import (
    AssumedEnglishSubtitle, translate_supplied_to_feed,
)
from lean120_api import load_profile
from paired_activation import PairedActivation, create_paired_server
from p4_tls import certificate_fingerprint_sha256, create_tls_context
from synthetic_mock_feed import (
    publish_synthetic_revisions, synthetic_source_srt,
)

HEX_32 = re.compile(r"[0-9a-fA-F]{64}\Z")


def build_controller(
    *, media_key: str, source_file: Path | None, master_hex: str,
    execute_api: bool, profile_file: Path, api_key: str,
    glossary: dict[str,str] | None = None,
    mock_revisions: bool = False,
) -> PairedActivation:
    if not isinstance(master_hex,str) or not HEX_32.fullmatch(master_hex):
        raise ValueError("P4_DEVICE_PAIRING_KEY_REQUIRED")
    if mock_revisions and execute_api:
        raise ValueError("P4_MOCK_CANNOT_CALL_API")
    if mock_revisions:
        if source_file is not None:
            raise ValueError("P4_MOCK_REJECTS_REAL_SOURCE_FILE")
        source=AssumedEnglishSubtitle.from_supplied(
            media_key=media_key,fmt="srt",source_bytes=synthetic_source_srt())
    else:
        if (source_file is None or not source_file.is_file() or
                source_file.suffix.lower() not in (".srt",".vtt")):
            raise ValueError("P4_TIMED_SOURCE_FILE_REQUIRED")
        source=AssumedEnglishSubtitle.from_supplied(
            media_key=media_key,fmt=source_file.suffix.lower()[1:],
            source_bytes=source_file.read_bytes())
    profile=load_profile(profile_file)
    if execute_api and not api_key:
        raise ValueError("GEMINI_API_KEY_ENV_REQUIRED")
    # The user-supplied file is assumed to be a correct English match.
    # No finder/ASR or semantic match claim from this function.
    if glossary is None:glossary={}
    def on_activate(feed,handoff):
        if mock_revisions:
            def run_mock():
                try:
                    publish_synthetic_revisions(handoff.media_key,feed)
                    print("P4_SYNTHETIC_120_240_PUBLISHED_NOT_REAL_TV_PASS")
                except Exception:
                    print("P4_SYNTHETIC_PUBLISH_FAILED")
            threading.Thread(target=run_mock,daemon=True,
                             name="p4-synthetic-feed").start()
            return
        if not execute_api:
            # Local activation dry-run; no paid API request and no fake captions.
            return
        def run():
            try:
                translate_supplied_to_feed(
                    handoff,profile,feed=feed,glossary=glossary,
                    api_key=api_key,transport=__import__("lean120_api")._https_post)
                print("P4_LOCAL_LEAN120_COMPLETE_CUES_RECEIVER_NOT_VERIFIED")
            except Exception:
                # Never include provider replies, API keys, subtitle text.
                print("P4_LOCAL_LEAN120_FAILED_CHECK_PRIVATE_HOST_LOG")
        threading.Thread(target=run,daemon=True,name="p4-lean120").start()
    return PairedActivation(
        device_secret=bytes.fromhex(master_hex),
        supplied={media_key:source},on_activate=on_activate)


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind",required=True,help="Explicit RFC1918 IPv4 PC LAN interface")
    parser.add_argument("--port",required=True,type=int)
    parser.add_argument("--media-key",required=True)
    parser.add_argument("--source",type=Path,
                        help="PRE-SUPPLIED and authorized EN SRT/VTT (not in mock mode)")
    parser.add_argument("--mock-revisions",action="store_true",
                        help="Dev-only synthetic 120→240; no source file or Gemini API")
    parser.add_argument("--profile",type=Path,
        default=Path(__file__).with_name("translator_profile.json"))
    parser.add_argument("--glossary-json",type=Path)
    parser.add_argument("--execute-api",action="store_true")
    parser.add_argument("--start-lan",action="store_true")
    parser.add_argument("--tls-cert",type=Path,
                        help="Explicit owner-generated PEM with IP-SAN for --bind")
    parser.add_argument("--tls-key",type=Path,
                        help="Matching owner-held private key outside repository")
    args=parser.parse_args()
    if not args.start_lan:
        parser.error("EXPLICIT_START_LAN_REQUIRED")
    if args.tls_cert is None or args.tls_key is None:
        parser.error("P4_TLS_CERT_AND_KEY_REQUIRED")
    key=os.environ.get("P4_PAIRING_MASTER_HEX","")
    api_key=os.environ.get("GEMINI_API_KEY","")
    glossary=(json.loads(args.glossary_json.read_text(encoding="utf-8"))
              if args.glossary_json else {})
    controller=build_controller(
        media_key=args.media_key,source_file=args.source,
        master_hex=key,execute_api=args.execute_api,
        profile_file=args.profile,api_key=api_key,glossary=glossary,
        mock_revisions=args.mock_revisions)
    tls_context=create_tls_context(args.tls_cert,args.tls_key)
    fingerprint=certificate_fingerprint_sha256(args.tls_cert)
    server=create_paired_server(
        controller,host=args.bind,port=args.port,tls_context=tls_context)
    print("P4_TLS_CERT_SHA256="+fingerprint)
    print("P4_PC_PAIRED_GATEWAY_START_EXPLICIT_TLS_LAN_ONLY")
    try:server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:pass
    finally:server.server_close()
    return 0


if __name__=="__main__":
    raise SystemExit(main())

"""Offline, fixed-vocabulary reading of an already pinned Owner V2 diagnosis.

Standalone companion intentionally outside the exact-byte Owner V2 activation
package: no changes to staged runtime modules, no new listener or provider.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from owner_p3_p4_diagnostics import read_diagnostic


def triage_next_gate(status: dict[str, str]) -> str:
    """Classify a *next measurement*, not a guessed network root cause.

    Zero accepted statuses cannot distinguish absent pairing, disabled TV,
    failed TLS or unavailable PC. Return only invariant, non-identifying codes.
    """
    if status.get("OWNER_HEARTBEAT") != "READY_FRESH":
        return "VERIFY_OWNER_PROCESS_FIRST"
    if status.get("P3_HTTPS_INSTRUMENTED") != "YES":
        return "VERIFY_OWNER_HTTPS_INSTRUMENTATION"
    if status.get("P3_HTTPS_STATE_REJECTED_AUTH", "0") != "0":
        return "INVESTIGATE_SIGNED_STATUS_AUTH"
    if status.get("P3_HTTPS_STATE_REJECTED_CLOCK", "0") != "0":
        return "INVESTIGATE_TV_PC_CLOCK_SKEW"
    if status.get("P3_HTTPS_STATE_REJECTED_REPLAY", "0") != "0":
        return "INVESTIGATE_SIGNED_STATUS_REPLAY"
    if (status.get("P3_STATE_FRESH") in ("MISSING", "STALE", "UNKNOWN")
            and status.get("P3_HTTPS_STATE_ACCEPTED") == "0"):
        return "MEASURE_TV_PAIRING_TLS_AND_SIGNAL_PATH"
    if status.get("P3_STATE_FRESH") in ("FRESH_OFF", "FRESH_OTHER", "FRESH_INACTIVE"):
        return "WAIT_FOR_EXPLICIT_CURRENT_FILM_REQUEST"
    if status.get("P3_STATE_FRESH") in ("FRESH_ON", "FRESH_REQUESTED"):
        if status.get("TORRSERVER_READER_READY") == "TCP_REACHABLE_METADATA_UNTESTED":
            return "VERIFY_EXACT_TORRSERVER_SELECTED_FILE_METADATA"
        return "VERIFY_OWNER_TORRSERVER_LOOPBACK"
    return "COLLECT_FRESH_PRIVATE_ENDPOINT_RECEIPTS"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Owner V2 read-only next gate")
    parser.add_argument("--owner-root", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        status = read_diagnostic(owner_root=args.owner_root)
    except ValueError:
        print("TTV_P3P4_NEXT_GATE=OWNER_ROOT_INVALID")
        return 2
    print("TTV_P3P4_NEXT_GATE=" + triage_next_gate(status))
    print("TTV_P3P4_TRIAGE=READ_ONLY_COMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

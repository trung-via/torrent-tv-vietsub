"""Owner-local G2 metadata or authorized release selection handoff for the existing HostOps interactive task.

Input is an owner-private JSON file; no film name, URL, or payload is printed.
This command only writes the existing inbox, never launches AGY or changes TV.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from owner_g2_inbox import enqueue_g2_metadata


def submit_private_file(owner_root: Path, request_file: Path) -> str:
    if (not request_file.is_absolute() or request_file.is_symlink()
            or not request_file.is_file() or not 0 < request_file.stat().st_size <= 8192):
        raise ValueError("G2_PRIVATE_INPUT_INVALID")
    return enqueue_g2_metadata(owner_root=owner_root,
                               request=json.loads(request_file.read_text(encoding="utf-8-sig")))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Owner-local G2 private request submission only")
    parser.add_argument("--owner-root", required=True)
    parser.add_argument("--request-file", required=True)
    args = parser.parse_args(argv)
    from owner_g2_support import _interactive_windows_session
    if (os.name != "nt" or not _interactive_windows_session()
            or any(os.environ.get(k, "").lower() == "true" for k in ("CI", "GITHUB_ACTIONS"))):
        print("OWNER_G2_SUBMIT_OWNER_CONTEXT_REQUIRED")
        return 1
    try:
        submit_private_file(Path(args.owner_root), Path(args.request_file))
    except (ValueError, OSError, TypeError, KeyError, AttributeError):
        print("OWNER_G2_SUBMIT_REVIEW_REQUIRED")
        return 1
    print("OWNER_G2_SUBMIT_ACCEPTED_NOT_RESULT")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

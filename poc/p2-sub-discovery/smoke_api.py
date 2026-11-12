"""Owner-only OpenSubtitles API key smoke: GET only, no subtitle search/download.

Run from an authorized laptop with API key set privately:
    python smoke_api.py
Never pass the key as a command-line argument or save it in the repository.
"""
from __future__ import annotations

import json
import os
import sys
from typing import Callable

from opensubtitles import BASE_URL, MAX_JSON_BYTES, SubtitleApiError, urllib_transport

Transport = Callable[[str, str, dict[str, str], bytes | None, int], bytes]
USER_AGENT = "TorrentTVVietsub/0.1 (personal-local-client)"


def check_api_key(key: str | None, *, transport: Transport = urllib_transport) -> str:
    """One safe GET to the provider language-list endpoint. No quota-bearing POST."""
    if not isinstance(key, str) or not key.strip() or "\n" in key or "\r" in key:
        return "API_KEY_NOT_CONFIGURED"
    headers = {"Api-Key": key, "User-Agent": USER_AGENT, "Accept": "application/json"}
    try:
        raw = transport("GET", BASE_URL + "/infos/languages", headers, None, MAX_JSON_BYTES)
        result = json.loads(raw.decode("utf-8"))
        if not isinstance(result, (dict, list)):
            return "API_RESPONSE_INVALID"
    except SubtitleApiError as exc:
        return str(exc)
    except (UnicodeError, ValueError):
        return "API_RESPONSE_INVALID"
    return "API_READONLY_SMOKE_PASS"


def main() -> int:
    outcome = check_api_key(os.environ.get("OPENSUBTITLES_API_KEY"))
    print(outcome)
    # Exact user-visible output has no key, username, IP, movie or bearer.
    return 0 if outcome == "API_READONLY_SMOKE_PASS" else 1


if __name__ == "__main__":
    sys.exit(main())

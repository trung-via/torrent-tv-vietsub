"""Pure command-to-Owner handoff. No provider, TV, or network actions."""
from __future__ import annotations
import hashlib
import json
import re
from urllib.parse import urlsplit

PREFIX = "/tv-hostops movie "


def build_request(command: str, comment_id: str) -> dict:
    if not re.fullmatch(r"[1-9][0-9]{0,19}", comment_id):
        raise ValueError("FLOW3_COMMENT_ID")
    if not command.startswith(PREFIX) or len(command) > 2048:
        raise ValueError("FLOW3_COMMAND")
    def unique(pairs):
        obj = {}
        for k, v in pairs:
            if k in obj:
                raise ValueError("FLOW3_DUPLICATE_FIELD")
            obj[k] = v
        return obj
    p = json.loads(command[len(PREFIX):], object_pairs_hook=unique)
    if not isinstance(p, dict) or not {"title", "year", "source_url"} <= set(p) <= {
            "title", "year", "source_url", "resolution", "mode", "media_authorized"}:
        raise ValueError("FLOW3_FIELDS")
    title = p["title"]
    year = p["year"]
    source = p["source_url"]
    quality = p.get("resolution", "1080p")
    mode = p.get("mode", "search")
    authority = p.get("media_authorized", False)
    if (not isinstance(title, str) or not title.strip() or len(title) > 200
            or any(ord(ch) < 32 for ch in title)
            or type(year) is not int or not 1900 <= year <= 2100
            or quality not in ("720p", "1080p", "2160p")
            or mode not in ("search", "play")
            or type(authority) is not bool or authority != (mode == "play")):
        raise ValueError("FLOW3_QUERY")
    # This comment route is public. No private locators, tokens, query
    # strings or credentials. Caller must name an authorized public origin.
    if not isinstance(source, str) or len(source) > 250:
        raise ValueError("FLOW3_SOURCE")
    u = urlsplit(source)
    if (u.scheme != "https" or not u.hostname or "." not in u.hostname
            or u.username or u.password or u.port not in (None, 443)
            or u.path not in ("", "/") or u.query or u.fragment
            or not re.fullmatch(r"[a-zA-Z0-9.-]+", u.hostname)):
        raise ValueError("FLOW3_SOURCE")
    from ipaddress import ip_address
    try:
        ip_address(u.hostname)
    except ValueError:
        pass
    else:
        raise ValueError("FLOW3_SOURCE")
    if u.hostname.endswith((".local", ".localhost", ".internal")):
        raise ValueError("FLOW3_SOURCE")
    rid = hashlib.sha256(("trung-via/torrent-tv-vietsub:movie:" + comment_id).encode()).hexdigest()[:32]
    play = mode == "play"
    return {
        "schema": "TTV-OWNER-G2-CONCIERGE-V1" if play else "TTV-OWNER-G2-METADATA-V1",
        "request_id": rid, "source_url": source, "authorized_source": True,
        "queries": [{"title": title.strip(), "year": year, "resolution": quality,
                     "select_release": play, "media_authorized": play, "play": play}],
    }

"""G2.2: local handoff of one already-selected, authorized release.

No discovery, provider, worker, TV launch, subtitle activation or remote ingress.
The trusted Owner/HostOps caller establishes source/media rights and release
match before calling. OMP contract: src/api/torrserver.ts at
52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f (list/add/get).
The return value is private and is suitable for the existing remote-play path.
"""
from __future__ import annotations

import base64
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
from urllib.parse import parse_qs, urlsplit
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler

_HASH = re.compile(r"[0-9a-f]{40}")
_VIDEO = re.compile(r"\.(mp4|mkv|webm|avi|mov|m4v|ts|m2ts)$", re.I)
_EXTRA = re.compile(r"(?:^|[\\/\s._-])(sample|trailer|extras?|bonus)(?:[\\/\s._-]|$)", re.I)


class HandoffHold(RuntimeError):
    """A fixed local reason, never echo private link, hash or server response."""


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _post(payload, timeout):
    request = Request("http://127.0.0.1:8090/torrents",
                      data=json.dumps(payload).encode("utf-8"), method="POST",
                      headers={"Content-Type": "application/json", "Accept": "application/json"})
    try:
        with build_opener(ProxyHandler({}), _NoRedirect()).open(request, timeout=timeout) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
            if response.status != 200 or len(raw) > 2 * 1024 * 1024:
                raise HandoffHold("TS_RESPONSE_INVALID")
            return json.loads(raw)
    except Exception:
        raise HandoffHold("TS_RESPONSE_UNVERIFIED") from None


def _hash(link):
    if not isinstance(link, str) or len(link) > 16384:
        raise HandoffHold("G2_LINK_INVALID")
    try:
        u = urlsplit(link)
        xt = parse_qs(u.query).get("xt", [])
        if u.scheme != "magnet" or u.netloc or u.path or u.fragment or len(xt) != 1:
            raise ValueError
        prefix, value = xt[0][:9], xt[0][9:]
        if prefix.lower() != "urn:btih:":
            raise ValueError
        if re.fullmatch(r"[a-fA-F0-9]{40}", value):
            return value.lower()
        if re.fullmatch(r"[A-Z2-7]{32}", value.upper()):
            return base64.b32decode(value.upper()).hex()
    except (ValueError, TypeError):
        pass
    raise HandoffHold("G2_LINK_INVALID")


@dataclass(frozen=True)
class SelectedRelease:
    link: str
    expected_hash: str
    title: str
    source_authorized: bool
    media_authorized: bool
    # The existing Brain selection supplies this only if independently matched.
    release_matched: bool
    file_id: int | None = None


@dataclass(frozen=True)
class LibraryResult:
    status: str
    torrent_hash: str
    file_id: int | None
    added_now: bool


def _listed(rows, target):
    if rows is None:
        rows = []
    if not isinstance(rows, list) or any(not isinstance(x, dict) or
            not isinstance(x.get("hash"), str) for x in rows):
        raise HandoffHold("TS_LIBRARY_SCHEMA")
    matches = [x for x in rows if x["hash"].lower() == target]
    if len(matches) > 1:
        raise HandoffHold("TS_DUPLICATE_HASH")
    return bool(matches)


def _file(meta, target, expected_file):
    if not isinstance(meta, dict) or str(meta.get("hash", "")).lower() != target:
        raise HandoffHold("TS_METADATA_HASH_MISMATCH")
    rows = meta.get("file_stats")
    if not isinstance(rows, list) or not rows:
        try:
            rows = json.loads(meta.get("data") or "{}")["TorrServer"]["Files"]
        except (ValueError, KeyError, TypeError):
            return None
    if not isinstance(rows, list) or len(rows) > 4096:
        raise HandoffHold("TS_FILE_SCHEMA")
    ids = set()
    primary = []
    for row in rows:
        if not isinstance(row, dict) or type(row.get("id")) is not int or row["id"] < 0 or not isinstance(row.get("path"), str):
            raise HandoffHold("TS_FILE_SCHEMA")
        i, path = row["id"], row["path"]
        if i in ids:
            raise HandoffHold("TS_FILE_ID_DUPLICATE")
        ids.add(i)
        if _VIDEO.search(path) and not _EXTRA.search(path):
            primary.append(i)
    if expected_file is not None:
        if expected_file not in primary:
            raise HandoffHold("TS_SELECTED_FILE_MISMATCH")
        return expected_file
    return primary[0] if len(primary) == 1 else None


def add_selected_release(selection: SelectedRelease, private_root: Path, *, post=_post):
    """One add at most for a selected hash; reconcile by list/get, never replay uncertain add.

    A missing file list is pending, not permission to pick the largest video.
    The durable hash claim is retained across calls. No automatic play.
    The live caller supplies a private Owner-owned directory, never Git/CI.
    """
    if (not isinstance(selection, SelectedRelease) or
            selection.source_authorized is not True or selection.media_authorized is not True or
            selection.release_matched is not True):
        raise HandoffHold("G2_SELECTION_AUTHORITY_REQUIRED")
    target = _hash(selection.link)
    if (not isinstance(selection.expected_hash, str) or
            not _HASH.fullmatch(selection.expected_hash.lower()) or target != selection.expected_hash.lower()):
        raise HandoffHold("G2_SELECTED_HASH_MISMATCH")
    if (not isinstance(selection.title, str) or not selection.title.strip() or len(selection.title) > 200 or
            (selection.file_id is not None and (type(selection.file_id) is not int or selection.file_id < 0))):
        raise HandoffHold("G2_SELECTION_INVALID")
    # Fake transports are for offline unit tests only.
    if post is _post and (os.name != "nt" or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"):
        raise HandoffHold("G2_OWNER_WINDOWS_REQUIRED")
    root = Path(private_root)
    if not root.is_absolute() or not root.is_dir() or root.is_symlink():
        raise HandoffHold("G2_PRIVATE_ROOT_REQUIRED")
    exists = _listed(post({"action": "list"}, 5), target)
    added = False
    if not exists:
        claim = root / ("g22-" + target + ".claim")
        try:
            with claim.open("x", encoding="ascii") as stream:
                stream.write("ADD_STARTED_DO_NOT_REPLAY\n")
                stream.flush()
                os.fsync(stream.fileno())
        except FileExistsError:
            raise HandoffHold("TS_PRIOR_ADD_REVIEW_REQUIRED") from None
        # Reconcile concurrent library changes before the sole add call.
        if not _listed(post({"action": "list"}, 5), target):
            try:
                result = post({"action": "add", "link": selection.link,
                               "title": selection.title, "poster": "", "category": "",
                               "save_to_db": True}, 30)
            except Exception:
                raise HandoffHold("TS_ADD_EFFECT_UNVERIFIED") from None
            if not isinstance(result, dict) or str(result.get("hash", "")).lower() != target:
                raise HandoffHold("TS_ADD_EFFECT_UNVERIFIED")
            added = True
        if not _listed(post({"action": "list"}, 5), target):
            raise HandoffHold("TS_LIBRARY_READBACK_PENDING")
    meta = post({"action": "get", "hash": target}, 5)
    file_id = _file(meta, target, selection.file_id)
    return LibraryResult("LIBRARY_READY" if file_id is not None else "FILE_SELECTION_PENDING",
                         target, file_id, added)

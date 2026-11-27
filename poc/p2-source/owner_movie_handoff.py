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


def handoff_private_request(private_root: Path, request_id: str, *, post=_post):
    """Trusted local caller supplies authorization, never AGY/web text."""
    import hashlib
    if not isinstance(request_id, str) or not re.fullmatch(r"[a-f0-9]{32}", request_id):
        raise HandoffHold("G2_REQUEST_ID_INVALID")
    root = Path(private_root)
    if not root.is_absolute() or not root.is_dir() or root.is_symlink():
        raise HandoffHold("G2_PRIVATE_ROOT_REQUIRED")
    source = root / ("g2-" + request_id + ".selected.json")
    receipt = root / ("g2-" + request_id + ".library.json")
    if source.is_symlink() or not source.is_file() or not 0 < source.stat().st_size <= 32768:
        raise HandoffHold("G2_SELECTED_REQUEST_MISSING")
    try:
        payload = json.loads(source.read_text(encoding="utf-8"))
        if (payload["schema"] != "TTV-G2-SELECTED-RELEASE-V1" or
                payload["request_id"] != request_id or type(payload["play"]) is not bool):
            raise ValueError
        selection = SelectedRelease(**payload["selection"])
    except (OSError, ValueError, TypeError, KeyError):
        raise HandoffHold("G2_SELECTED_REQUEST_INVALID") from None
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True,
                                      separators=(",", ":")).encode("utf-8")).hexdigest()
    if receipt.is_symlink():
        raise HandoffHold("G2_LIBRARY_RECEIPT_INVALID")
    if receipt.exists():
        try:
            prior = json.loads(receipt.read_text(encoding="utf-8"))
            if prior.get("selection_digest") != digest:
                raise ValueError
            if prior.get("status") == "LIBRARY_READY":
                return prior["status"]
        except (OSError, ValueError, TypeError, AttributeError):
            raise HandoffHold("G2_LIBRARY_RECEIPT_CONFLICT") from None
    result = add_selected_release(selection, root, post=post)
    row = {"schema": "TTV-G2-LIBRARY-RECEIPT-V1", "request_id": request_id,
           "selection_digest": digest, "status": result.status,
           "torrent_hash": result.torrent_hash, "file_id": result.file_id,
           "play": payload["play"]}
    tmp = receipt.with_suffix(".json.tmp")
    with tmp.open("x", encoding="utf-8") as stream:
        json.dump(row, stream, separators=(",", ":"))
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, receipt)
    return result.status


def publish_library_receipt(private_root: Path, request_id: str, *, post=_post, outbox=None):
    """Reuse enrolled HostOps Receipts. Owner writes; the paired runner reads.

    No locator or credential crosses the account boundary. A ready receipt is
    immutable per request, and only a trusted, already authorized selection is
    accepted by handoff_private_request. No ACL or service changes.
    """
    if outbox is None:
        program_data = os.environ.get("ProgramData")
        if os.name != "nt" or not program_data:
            raise HandoffHold("G2_OWNER_WINDOWS_REQUIRED")
        outbox = Path(program_data)/"TorrentTVVietsub"/"LaptopHostOps"/"Receipts"
    dest = Path(outbox)
    if not dest.is_absolute() or not dest.is_dir() or dest.is_symlink():
        raise HandoffHold("G2_HOSTOPS_RECEIPTS_UNAVAILABLE")
    status = handoff_private_request(private_root, request_id, post=post)
    if status != "LIBRARY_READY":
        return status
    name = "g2-" + request_id + ".library.json"
    source = Path(private_root)/name
    raw = source.read_bytes()
    if not 0 < len(raw) <= 8192:
        raise HandoffHold("G2_LIBRARY_RECEIPT_INVALID")
    target = dest/name
    if target.is_symlink():
        raise HandoffHold("G2_HOSTOPS_RECEIPT_CONFLICT")
    if target.exists():
        if target.read_bytes() != raw:
            raise HandoffHold("G2_HOSTOPS_RECEIPT_CONFLICT")
        return status
    # Windows rename without replacement prevents overwriting another result.
    # Unique temporary file means a prior interrupted copy does not block reads.
    import tempfile
    fd, temp = tempfile.mkstemp(prefix="g2-publish-", suffix=".tmp", dir=dest)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        if os.name == "nt":
            try:
                os.rename(temp, target)
            except FileExistsError:
                if target.is_symlink() or target.read_bytes() != raw:
                    raise HandoffHold("G2_HOSTOPS_RECEIPT_CONFLICT") from None
        else:
            # Offline test transport only; hard link publishes without replace.
            try:
                os.link(temp, target)
            except FileExistsError:
                if target.is_symlink() or target.read_bytes() != raw:
                    raise HandoffHold("G2_HOSTOPS_RECEIPT_CONFLICT") from None
    finally:
        Path(temp).unlink(missing_ok=True)
    return status


if __name__ == "__main__":
    import sys
    try:
        if len(sys.argv) != 3:
            raise HandoffHold("G2_ARGUMENTS_INVALID")
        print(publish_library_receipt(Path(sys.argv[1]), sys.argv[2]))
    except Exception:
        print("G2_LIBRARY_HANDOFF_REVIEW_REQUIRED")
        sys.exit(1)

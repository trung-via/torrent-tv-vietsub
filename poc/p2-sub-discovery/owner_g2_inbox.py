"""Existing Owner private G2 inbox; extracted from #195, no worker or loop."""
from __future__ import annotations
import json
import os
from pathlib import Path
import re
import secrets
import time
from owner_g2_support import _write

_ID = re.compile(r"[a-f0-9]{32}\Z")

def _no_trace(stage, **context):
    pass

def _private_dir(root: Path) -> Path:
    if not isinstance(root, Path) or not root.is_absolute() or root.is_symlink():
        raise ValueError("OWNER_BRIDGE_PRIVATE_ROOT_INVALID")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    folder = root / "inbox"
    if folder.is_symlink():
        raise ValueError("OWNER_BRIDGE_PRIVATE_INBOX_SYMLINK")
    folder.mkdir(mode=0o700, exist_ok=True)
    return folder

def _g2_request(payload, request_id):
    """Same request contract at producer and consumer; owner-local authority only."""
    from owner_g2_discovery import MovieQuery, MAX_BATCH, _source, _query
    if (not isinstance(payload, dict)
            or set(payload) != {"schema", "request_id", "source_url", "authorized_source", "queries"}
            or payload["schema"] not in ("TTV-OWNER-G2-METADATA-V1", "TTV-OWNER-G2-SELECTION-V1",
                                         "TTV-OWNER-G2-CONCIERGE-V1")
            or not isinstance(request_id, str) or not _ID.fullmatch(request_id)
            or payload["request_id"] != request_id
            or payload["authorized_source"] is not True
            or not isinstance(payload["source_url"], str)
            or not isinstance(payload["queries"], list)
            or not 1 <= len(payload["queries"]) <= MAX_BATCH):
        raise ValueError("G2_REQUEST_INVALID")
    _source(payload["source_url"])
    queries = tuple(_query(MovieQuery(**q)) for q in payload["queries"])
    concierge = payload["schema"] == "TTV-OWNER-G2-CONCIERGE-V1"
    selected = concierge or payload["schema"] == "TTV-OWNER-G2-SELECTION-V1"
    if (selected and (len(queries) != 1 or not queries[0].select_release)
            or concierge and not queries[0].play
            or not selected and any(q.select_release for q in queries)):
        raise ValueError("G2_REQUEST_MODE_MISMATCH")
    return queries


def enqueue_g2_metadata(*, owner_root: Path, request: dict) -> str:
    """Trusted local writer; publish a complete file once, never overwrite.

    A repeated identical request ID returns its existing receipt/claim identity,
    not another provider call. Input stays owner-private; no public GitHub payload.
    """
    request_id = request.get("request_id") if isinstance(request, dict) else None
    _g2_request(request, request_id)
    body = json.dumps(request, ensure_ascii=False, separators=(",", ":"),
                      sort_keys=True, allow_nan=False).encode("utf-8")
    if len(body) > 8192:
        raise ValueError("G2_REQUEST_SIZE")
    inbox = _private_dir(owner_root)
    path = inbox / ("g2-" + request_id + ".json")
    claim = inbox / ("g2-" + request_id + ".claim")
    receipt = inbox / ("g2-" + request_id + ".receipt.json")

    def existing():
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 8192:
            raise ValueError("G2_REQUEST_ID_CONFLICT")
        try:
            prior = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError, UnicodeError):
            raise ValueError("G2_REQUEST_ID_CONFLICT") from None
        if prior != request:
            raise ValueError("G2_REQUEST_ID_CONFLICT")
        return request_id

    if path.exists() or path.is_symlink():
        return existing()
    if claim.exists() or claim.is_symlink() or receipt.exists() or receipt.is_symlink():
        raise ValueError("G2_REQUEST_PRIOR_EFFECT_REVIEW")
    tmp = inbox / (".g2-" + request_id + "-" + secrets.token_hex(8) + ".tmp")
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(body)
            stream.flush()
            os.fsync(stream.fileno())
        # NTFS/local filesystem atomic exclusive publication; no replace fallback.
        try:
            os.link(tmp, path)
        except FileExistsError:
            return existing()
        return request_id
    finally:
        tmp.unlink(missing_ok=True)


def _publish_g2_selection(inbox, request_id, query, rows, *, auto_vietsub=False):
    """Publish the actual G2.2 request only after the complete selection returns.

    No provider, torrent add or launch in this function. Existing claims and
    receipts prevent replay; never publish a partial/failed browser result.
    """
    if len(rows) != 1 or rows[0].get("status") != "SELECTION_READY":
        return False
    row = rows[0]
    from dataclasses import asdict
    if (row.get("owner_request_id") != request_id or row.get("query") != asdict(query)
            or query.media_authorized is not True or not query.select_release):
        raise ValueError("G2_SELECTION_BINDING_INVALID")
    selection = row.get("selection")
    if not isinstance(selection, dict) or set(selection) != {
            "link", "expected_hash", "title", "source_authorized",
            "media_authorized", "release_matched", "file_id"}:
        raise ValueError("G2_SELECTION_BINDING_INVALID")
    from owner_g2_discovery import _link_hash
    if (_link_hash(selection["link"]) != selection["expected_hash"]
            or not selection["expected_hash"] or selection["title"] != query.title
            or any(selection[k] is not True for k in
                   ("source_authorized", "media_authorized", "release_matched"))
            or selection["file_id"] is not None):
        raise ValueError("G2_SELECTION_BINDING_INVALID")
    path = inbox / ("g2-" + request_id + ".selected.json")
    body = {"schema": "TTV-G2-SELECTED-RELEASE-V1", "request_id": request_id,
            "selection": selection, "play": query.play}
    if auto_vietsub:
        if not query.play:
            raise ValueError("G2_CONCIERGE_PLAY_REQUIRED")
        body["auto_vietsub"] = True
    data = json.dumps(body, ensure_ascii=True, separators=(",", ":"),
                      sort_keys=True).encode("utf-8")
    tmp = inbox / (".g2-selected-" + request_id + "-" + secrets.token_hex(8) + ".tmp")
    try:
        with tmp.open("xb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(tmp, path)
        except FileExistsError:
            if path.is_symlink() or not path.is_file() or path.read_bytes() != data:
                raise ValueError("G2_SELECTION_RECEIPT_CONFLICT") from None
    finally:
        tmp.unlink(missing_ok=True)
    return True


def poll_private_g2(*, owner_root: Path, cache_root: Path, discover, submit, emit=print,
                    handoff=None, trace=_no_trace) -> int:
    """One bounded, explicitly authorized Owner-local metadata request.
    
    The existing private inbox is the handoff; the runner wake is inert.
    A durable claim prevents automatic replay after an uncertain effect.
    """
    inbox = _private_dir(owner_root)
    for path in sorted(inbox.glob("g2-*.json")):
        match = re.fullmatch(r"g2-([a-f0-9]{32})\.json", path.name)
        if match is None or path.is_symlink() or not path.is_file():
            continue
        request_id = match[1]
        claim = inbox / ("g2-" + request_id + ".claim")
        receipt = inbox / ("g2-" + request_id + ".receipt.json")
        if claim.exists() or claim.is_symlink() or receipt.exists() or receipt.is_symlink():
            continue
        try:
            if not 0 < path.stat().st_size <= 8192:
                raise ValueError("G2_REQUEST_SIZE")
            request = json.loads(path.read_text(encoding="utf-8"))
            queries = _g2_request(request, request_id)
        except (OSError, ValueError, TypeError, KeyError, AttributeError):
            emit("OWNER_G2_REQUEST_REJECTED")
            continue
        try:
            with claim.open("x", encoding="utf-8") as stream:
                stream.write("CLAIMED_DO_NOT_AUTO_REPLAY\n")
                stream.flush()
                os.fsync(stream.fileno())
        except FileExistsError:
            continue
        def run_claimed():
            try:
                detail = {}
                try:
                    rows = discover(queries, cache_root, source_url=request["source_url"],
                                    authorized_source=True, owner_request_id=request_id)
                except Exception as exc:
                    from owner_g2_discovery import G2BatchReview
                    # A completed, verified single-film selection must not be lost
                    # solely because the independent browser cleanup failed.
                    # Keep the producer's terminal journal and browser.pending;
                    # do not retry AGY or claim browser readiness.
                    if not (isinstance(exc, G2BatchReview)
                            and exc.reason == exc.cleanup_reason == "G2_BROWSER_EFFECT_REVIEW_REQUIRED"
                            and exc.browser_restored is False
                            and len(queries) == len(exc.rows) == 1
                            and queries[0].select_release
                            and exc.rows[0].get("status") == "SELECTION_READY"):
                        raise
                    rows = list(exc.rows)
                    detail.update(browser_restored=False, cleanup_reason=exc.cleanup_reason)
                status = "COMPLETE" if len(rows) == len(queries) else "PARTIAL"
                if queries[0].select_release:
                    published = _publish_g2_selection(
                        inbox, request_id, queries[0], rows,
                        auto_vietsub=request["schema"] == "TTV-OWNER-G2-CONCIERGE-V1")
                    detail["selection_published"] = published
                    if published and handoff is not None:
                        try:
                            detail["library_status"] = handoff(inbox, request_id)
                            # Only a known pending file list is reconciled. The
                            # existing hash claim prevents replay of an add.
                            for _ in range(6):
                                if detail["library_status"] != "FILE_SELECTION_PENDING":
                                    break
                                time.sleep(5)
                                detail["library_status"] = handoff(inbox, request_id)
                        except Exception as exc:
                            trace("OWNER_G2_LIBRARY_REVIEW_REQUIRED", error=exc)
                            detail["library_status"] = "LIBRARY_REVIEW_REQUIRED"
                _write(receipt, {"schema": "TTV-OWNER-G2-RECEIPT-V1",
                                 "request_id": request_id, "status": status, "results": rows, **detail})
                emit("OWNER_G2_" + status)
            except Exception as exc:
                from agy_owner_warm_session import warm_reason
                from owner_g2_discovery import G2BatchReview
                trace("OWNER_G2_REVIEW_REQUIRED", error=exc)
                detail = {"reason": warm_reason(exc), "results": []}
                if isinstance(exc, G2BatchReview):
                    detail.update(reason=exc.reason, results=list(exc.rows),
                                  browser_restored=exc.browser_restored,
                                  cleanup_reason=exc.cleanup_reason)
                _write(receipt, {"schema": "TTV-OWNER-G2-RECEIPT-V1",
                                 "request_id": request_id, "status": "REVIEW_REQUIRED",
                                 **detail})
                emit("OWNER_G2_REVIEW_REQUIRED")
        submit(run_claimed)
        return 1
    return 0


def bind_owner_g2(factory, runner):
    """Same Owner, separate movie-search browser resource and checkpoint lane."""
    from threading import Lock
    from owner_g2_discovery import discover_movie_batch

    movie_profile = runner.profile.parent / "CDP9556MovieProfile"
    movie_lock = Lock()

    def discover(queries, cache_root, *, source_url, authorized_source,
                 model="gemini-4-hydrogen-low", thinking_level="low", owner_request_id=None):
        # G1's browser, lock, priority counters and pending marker are not
        # dependencies of G2. Missing G2 profile blocks only this request.
        with movie_lock:
            return discover_movie_batch(
                movie_profile, queries, cache_root / "movie-discovery",
                source_url=source_url, authorized_source=authorized_source,
                model=model, thinking_level=thinking_level, browser_port=9556,
                owner_request_id=owner_request_id)
    factory.g2_discover = discover
    return factory


def poll_owner_g2_idle(*, active, factory, owner_root, cache_root, submit, handoff,
                       emit=print, trace=_no_trace):
    """Call from existing Owner tick with ONLY the G2 active set, not G1.

    Handoff must be the canonical p2-source publish_library_receipt function,
    resolved by the Owner composition. No extra queue or scheduler is created.
    """
    discover = getattr(factory, "g2_discover", None)
    if active or not callable(discover):
        return 0
    if not callable(handoff):
        raise ValueError("G2_HANDOFF_REQUIRED")
    return poll_private_g2(owner_root=owner_root, cache_root=cache_root,
                           discover=discover, submit=submit, emit=emit,
                           handoff=handoff, trace=trace)

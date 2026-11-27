"""G2.1 metadata and authorized release selection in the existing Owner AGY session.

The trusted Owner caller establishes C1.5/C5 source and content authority.
Selection mode returns an Owner-private locator for permitted media only.
No download, torrent add, play, network ingress or scheduler here.
The G1 producer's in-process lock and existing browser.pending claim are shared.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import uuid
import time
from itertools import islice
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, ProxyHandler

from agy_owner_warm_session import OwnerAgyWarmSession, WarmSessionError, warm_reason
from translator_gateway import preflight_antigravity, _validated_antigravity_alias


@dataclass(frozen=True)
class MovieQuery:
    title: str
    year: int
    resolution: str = "1080p"
    select_release: bool = False
    media_authorized: bool = False
    play: bool = False
    codec: str | None = None
    release_contains: str | None = None
    # Optional independently verified release identity from the trusted caller.
    # Never taken from AGY output; only used if the source omits the year.
    verified_release_hash: str | None = None


MAX_BATCH = 2
# Independent budgets, at most two turns, no automatic retries.
TURN_SECONDS = 120


class G2BatchReview(WarmSessionError):
    """A failed batch retains verified completed rows, not a success verdict."""

    def __init__(self, reason, rows, *, browser_restored, cleanup_reason=None):
        super().__init__(reason)
        self.reason = reason
        self.rows = tuple(rows)
        self.browser_restored = browser_restored
        self.cleanup_reason = cleanup_reason


def _source(url):
    u = urlsplit(url)
    if (u.scheme != "https" or not u.hostname or "." not in u.hostname
            or u.username or u.password or u.port not in (None, 443)
            or u.fragment or u.hostname.endswith((".local", ".localhost", ".internal"))):
        raise ValueError("G2_SOURCE_NOT_PUBLIC_HTTPS")
    try:
        ipaddress.ip_address(u.hostname)
    except ValueError:
        return u.hostname.lower()
    raise ValueError("G2_SOURCE_NOT_PUBLIC_HTTPS")


def _query(q):
    if (not isinstance(q, MovieQuery) or not isinstance(q.title, str)
            or not q.title.strip() or len(q.title) > 200
            or type(q.year) is not int or not 1900 <= q.year <= 2100
            or q.resolution not in ("720p", "1080p", "2160p")
            or any(type(v) is not bool for v in (q.select_release, q.media_authorized, q.play))
            or (q.select_release and not q.media_authorized)
            or (not q.select_release and (q.media_authorized or q.play or q.codec is not None or q.release_contains is not None))
            or (q.verified_release_hash is not None and (not q.select_release
                or not isinstance(q.verified_release_hash, str)
                or not re.fullmatch(r"[a-f0-9]{40}", q.verified_release_hash)))
            or (q.codec is not None and q.codec not in ("H264", "H265", "AV1", "VP9"))
            or (q.release_contains is not None and (not isinstance(q.release_contains, str)
                or not q.release_contains.strip() or len(q.release_contains) > 160))):
        raise ValueError("G2_QUERY_INVALID")
    return q


def _normalized(s):
    return " ".join(s.casefold().split())


def _identity_matches(row, query, picked=None):
    title, year = row.get("title"), row.get("year")
    if not isinstance(title, str) or _normalized(title) != _normalized(query.title):
        return False
    if type(year) is int and year == query.year:
        return True
    # Null year is missing metadata, not evidence of another film. Allow
    # independently bound exact release only; never override a conflicting year.
    if year is not None or not query.select_release or not query.verified_release_hash:
        return False
    link = row.get("link")
    if link is None and isinstance(picked, dict) and picked.get("release_name") == row.get("release_name"):
        link = picked.get("link")
    return _link_hash(link) == query.verified_release_hash


def _metadata(payload, query, request_id):
    if payload.get("request_id") != request_id:
        raise WarmSessionError("G2_RESULT_REQUEST_MISMATCH")
    status = payload.get("status")
    if status not in ("MATCH_FOUND", "NO_MATCH", "ACCESS_BLOCKED", "UNKNOWN"):
        raise WarmSessionError("G2_RESULT_STATUS_INVALID")
    candidates = payload.get("candidates")
    if not isinstance(candidates, list) or len(candidates) > 100:
        raise WarmSessionError("G2_RESULT_CANDIDATES_INVALID")
    rows = []
    for row in candidates:
        if not isinstance(row, dict):
            raise WarmSessionError("G2_RESULT_ROW_INVALID")
        if not _identity_matches(row, query, payload.get("selected")):
            continue
        def number(key):
            value = row.get(key)
            return value if type(value) is int and value >= 0 else None
        resolution = row.get("resolution")
        resolution = resolution if resolution in ("720p", "1080p", "2160p") else None
        codec = row.get("codec")
        codec = codec if codec in ("H264", "H265", "AV1", "VP9") else None
        size, seeds = number("size_mb"), number("seeds")
        rows.append({"title": query.title, "year": query.year, "resolution": resolution,
                     "size_mb": size, "seeds": seeds, "codec": codec,
                     "requested_resolution": resolution == query.resolution,
                     "preferred_size": size is not None and 5000 <= size <= 12000})
    rows.sort(key=lambda r: _release_rank(r, query), reverse=True)
    if status != "MATCH_FOUND":
        rows = []
    if status == "MATCH_FOUND" and not rows:
        status = "NO_EXACT_MATCH_REPORTED"
    return {"status": status, "candidates": rows, "evidence": "MODEL_REPORTED_METADATA"}


def _link_hash(link):
    """Validate the same v1 BTIH magnet representation accepted by G2.2."""
    import base64
    from urllib.parse import parse_qs
    if not isinstance(link, str) or len(link) > 16384 or any(ord(c) <= 32 for c in link):
        return None
    try:
        u = urlsplit(link)
        xt = parse_qs(u.query).get("xt", [])
        if u.scheme != "magnet" or u.netloc or u.path or u.fragment or len(xt) != 1:
            return None
        prefix, value = xt[0][:9], xt[0][9:]
        if prefix.lower() != "urn:btih:":
            return None
        if re.fullmatch(r"[a-fA-F0-9]{40}", value):
            return value.lower()
        if re.fullmatch(r"[A-Z2-7]{32}", value.upper()):
            return base64.b32decode(value.upper()).hex()
    except (ValueError, TypeError):
        pass
    return None


def _observed_locator(trace, source_host, release_name, link):
    """Check the actual same-turn, page-bound browser output, not AGY's final prose.

    This attests that the locator and release label were reported in a fresh
    source read. It does not establish media rights, actual bytes or peer rate.
    """
    from agy_owner_warm_session import _page_argument, _source_page
    from html import unescape
    pending = None
    page = None
    if not trace.is_file() or trace.is_symlink() or trace.stat().st_size > 16 * 1024 * 1024:
        return False
    with trace.open(encoding="utf-8") as stream:
        for line in stream:
            try:
                st = json.loads(line).get("step_update")
            except (ValueError, AttributeError):
                continue
            if not isinstance(st, dict) or st.get("tool_name") != "call_mcp_tool":
                continue
            info = st.get("tool_info")
            if not isinstance(info, dict):
                continue
            params = info.get("parameters")
            if isinstance(params, dict) and params.get("ToolName"):
                server = next((params[k] for k in ("ServerName", "Server", "serverName", "server")
                               if isinstance(params.get(k), str)), None)
                pending = (params["ToolName"], server, _page_argument(params))
            if "output" not in info and not info.get("error"):
                continue
            if pending and pending[1] == "ttv-browser" and not (info.get("error") or st.get("error")):
                output = info.get("output")
                if pending[0] == "list_pages":
                    page = _source_page(output, source_host)
                elif (pending[0] in ("evaluate_script", "take_snapshot") and page is not None
                      and pending[2] == page and isinstance(output, str)):
                    # Require a single observed release object containing both
                    # fields, not a page containing unrelated labels and links.
                    # MCP tools may wrap JSON in a text/code-fence envelope.
                    decoder = json.JSONDecoder()
                    for start in re.finditer(r"\{", output):
                        try:
                            observed, _ = decoder.raw_decode(output, start.start())
                        except ValueError:
                            continue
                        if (isinstance(observed, dict)
                                and isinstance(observed.get("release_name"), str)
                                and isinstance(observed.get("link"), str)
                                and _normalized(observed["release_name"]) == _normalized(release_name)
                                and unescape(observed["link"]) == link):
                            return True
            pending = None
    return False


def _release_rank(row, query):
    # Lexicographic priority: quality, then reported seeds, then soft size.
    # Exact resolution wins; otherwise nearest known height, then unknown.
    # At an equal distance prefer the lower height for easier playback.
    heights = {"720p": 720, "1080p": 1080, "2160p": 2160}
    requested = heights[query.resolution]
    height = heights.get(row.get("resolution")) if isinstance(row.get("resolution"), str) else None
    quality = (height is not None, -abs(height-requested) if height is not None else -9999,
               height is not None and height <= requested,
               query.codec is None or row.get("codec") == query.codec)
    seeds = row.get("seeds")
    seeds = seeds if type(seeds) is int and seeds >= 0 else -1
    size = row.get("size_mb")
    preferred = type(size) is int and 5000 <= size <= 12000
    return (quality, seeds, preferred)


def _selected_metadata(payload, query, request_id, source_host, trace):
    """Choose the best available, authorized, source-observed exact-film release.

    Quality and size are preferences, never elimination conditions.
    If AGY's nominated winner is unusable, select the next observed release
    from this same turn rather than discard a viable exact-film candidate.
    """
    meta = _metadata(payload, query, request_id)
    if not query.select_release or query.media_authorized is not True:
        raise WarmSessionError("G2_MEDIA_AUTHORITY_REQUIRED")
    if meta["status"] in ("ACCESS_BLOCKED", "UNKNOWN"):
        return meta
    picked = payload.get("selected")
    ranked = []
    for row in payload["candidates"]:
        name = row.get("release_name")
        if (not _identity_matches(row, query, picked)
                or not isinstance(name, str) or not name.strip() or len(name) > 300):
            continue
        # Explicit release marker identifies the requested release, if supplied.
        if (query.release_contains is not None and
                _normalized(query.release_contains) not in _normalized(name)):
            continue
        link = row.get("link")
        if link is None and isinstance(picked, dict) and picked.get("release_name") == name:
            link = picked.get("link")
        target = _link_hash(link)
        if target is not None:
            ranked.append((_release_rank(row, query), name, link, target, row))
    # Stable source-independent tie break; no extra provider request.
    ranked.sort(key=lambda x: (x[1].casefold(), x[3]))
    ranked.sort(key=lambda x: x[0], reverse=True)
    for _, name, link, target, row in ranked:
        if not _observed_locator(trace, source_host, name, link):
            continue
        resolution = row.get("resolution")
        if resolution not in ("720p", "1080p", "2160p"):
            resolution = None
        return {**meta, "status": "SELECTION_READY", "release_name": name,
                "evidence": "MODEL_REPORTED_METADATA_BOUND_LOCATOR",
                "identity_evidence": ("TRUSTED_RELEASE_HASH" if row.get("year") is None
                                      else "REPORTED_TITLE_YEAR"),
                "selected_resolution": resolution,
                "quality_fallback": resolution != query.resolution,
                "selection": {"link": link, "expected_hash": target,
                              "title": query.title, "source_authorized": True,
                              "media_authorized": True, "release_matched": True,
                              "file_id": None}}
    # No usable locator is fundamentally different from a quality compromise.
    if meta["status"] == "MATCH_FOUND" or ranked:
        return {**meta, "status": "SELECTED_LOCATOR_UNVERIFIED"}
    return meta


def _prompt(query, source_url, request_id):
    if query.select_release:
        return (
            "Torrent TV G2.1: one job, find and choose the best matching release of "
            "the specifically authorized media on the approved legal source. "
            "Use the existing ttv-browser task tab and ordinary visible controls. "
            "List pages and bind every fresh source read to the numeric pageId. "
            "Do not use a different source, bypass restrictions, log in, download media, "
            "add to TorrServer, play, or run shell. Stop if access or distribution rights "
            "are unclear; never infer rights from the mere presence of a link. "
            "Query: " + json.dumps({k: v for k, v in asdict(query).items() if k != "verified_release_hash"}, ensure_ascii=False) + ". Source: " +
            json.dumps(source_url) + ". Request ID: " + request_id + ". "
            "Exact film title/year: use the actual year when present; if absent return null, never invent it. "
            "Still return the matching title and observed locator for independent identity verification. "
            "Match an explicit release_contains if supplied. "
            "Select one best available exact-film release whenever an authorized observed locator exists. "
            "Rank first by requested quality (exact resolution, otherwise nearest known resolution, "
            "unknown quality last; prefer requested codec at equivalent resolution), then higher "
            "reported seeds, then soft size preference 5000-12000 MB. "
            "Never reject an exact-film release solely for quality, seed or size; "
            "unknown seed/size are allowed. Seeds do not prove throughput. "
            "Compare only observed eligible releases. Use current source read evidence, "
            "not previous turns. For a permitted release, read its exact release label "
            "and direct magnet link from the same visible release row in a fresh page-bound browser result. "
            "For that read, emit a JSON object with release_name and link taken from the source row, "
            "not copied from your own final answer. "
            "Return compact JSON with request_id, status (MATCH_FOUND, NO_MATCH, "
            "ACCESS_BLOCKED, UNKNOWN), candidates (title, year, resolution, codec, "
            "size_mb, seeds, release_name, link; unknown numeric data null). Include observed "
            "links for usable alternatives so Owner can choose the best verified release even if "
            "your first choice is unusable. Return selected (release_name, link) for your best "
            "available release; use NO_MATCH only if no correct permitted film is available. "
            "Do not fabricate candidates or locators. The locator stays local to Owner."
        )
    return (
        "Torrent TV G2.1 authorized read-only metadata request. "
        "Use only ttv-browser MCP on the dedicated task tab for this approved HTTPS source. "
        "Every turn list_pages, select the one matching source tab, and pass its numeric pageId explicitly to evaluate_script or take_snapshot. Use ordinary visible search controls and compact DOM reads. "
        "Read current page evidence each turn; prior conversation is not evidence. "
        "Stop on access restrictions; no login, bypass, download, magnet, add, playback, shell, "
        "private tabs, or other sources. Return immediately with compact JSON, no prose. "
        "Query: " + json.dumps(asdict(query), ensure_ascii=False) + ". Source: " +
        json.dumps(source_url) + ". Request ID: " + request_id + ". "
        'JSON keys: request_id, status (MATCH_FOUND, NO_MATCH, ACCESS_BLOCKED, UNKNOWN), candidates. '
        'Each candidate has canonical title, year, resolution (720p/1080p/2160p or null), '
        'size_mb and seeds (nonnegative integer or null), codec (H264/H265/AV1/VP9 or null). '
        'Only include observed data; unknown is null. No URLs or identifiers in candidates. '
        'Prefer exact requested resolution, then highest reported seeds, then soft 5000-12000 MB. '
        'Do not imply seed count guarantees speed.'
    )


def discover_movie_batch(profile, queries, cache_root, *, source_url, authorized_source,
                         model="gemini-4-hydrogen-low", thinking_level="low",
                         session_factory=OwnerAgyWarmSession, should_yield=lambda: False,
                         owner_request_id=None):
    """Call under NativeBrowserProducer._browser_lock; no runtime startup effect."""
    from agy_v13_native_producer import _ensure_browser_listener, _session_settings, _write
    if authorized_source is not True:
        raise ValueError("G2_SOURCE_AUTHORITY_REQUIRED")
    source_host = _source(source_url)
    queries = tuple(_query(q) for q in islice(queries, MAX_BATCH + 1))
    if len(queries) > MAX_BATCH:
        raise ValueError("G2_BATCH_LIMIT")
    if any(q.select_release for q in queries) and len(queries) != 1:
        raise ValueError("G2_SINGLE_SELECTION_REQUIRED")
    if not queries:
        return []
    if os.name != "nt" or any(os.environ.get(k, "").lower() == "true" for k in ("CI", "GITHUB_ACTIONS")):
        raise WarmSessionError("G2_WINDOWS_OWNER_REQUIRED")
    ps = shutil.which("pwsh")
    profile = Path(profile)
    if not ps or not profile.is_dir() or profile.is_symlink():
        raise WarmSessionError("G2_BROWSER_PROFILE_REQUIRED")
    parent = Path(cache_root) / ".native-v13"
    parent.mkdir(parents=True, exist_ok=True)
    if parent.is_symlink():
        raise WarmSessionError("G2_PRIVATE_ROOT_INVALID")
    # The inbox request determines the durable directory even if the process
    # crashes before the consumer receipt. Direct callers get a fresh identity.
    if owner_request_id is None:
        owner_request_id = uuid.uuid4().hex
    if not isinstance(owner_request_id, str) or not re.fullmatch(r"[a-f0-9]{32}", owner_request_id):
        raise WarmSessionError("G2_OWNER_REQUEST_ID_INVALID")
    run = parent / ("g2-" + owner_request_id)
    if run.exists() or run.is_symlink():
        raise WarmSessionError("G2_PRIOR_BATCH_REVIEW_REQUIRED")
    pending = parent / "browser.pending"
    try:
        with pending.open("x", encoding="utf-8") as f:
            f.write(run.name)
            f.flush()
            os.fsync(f.fileno())
    except FileExistsError:
        raise WarmSessionError("G2_BROWSER_BUSY_OR_UNKNOWN") from None
    target = None
    initial_ids = set()
    baseline = {}
    browser_identity = None
    session = None
    effects_started = False
    restored = False
    finished = False
    rows = []
    failure = None
    cleanup_reason = None
    started_at = time.monotonic()
    opener = build_opener(ProxyHandler({}))

    def cdp(path, method="GET"):
        with opener.open(Request("http://127.0.0.1:9555" + path, method=method), timeout=5) as f:
            return f.read(262144)

    def pages():
        return [p for p in json.loads(cdp("/json/list")) if p.get("type") == "page"]

    def browser_id():
        version = json.loads(cdp("/json/version"))
        identity = version.get("webSocketDebuggerUrl", "")
        if (not str(version.get("Browser", "")).startswith("Chrome/")
                or not isinstance(identity, str)
                or not identity.startswith("ws://127.0.0.1:9555/devtools/browser/")):
            raise WarmSessionError("G2_BROWSER_IDENTITY")
        return identity

    def snapshot():
        result = {}
        for page in pages():
            i, url = page.get("id"), page.get("url")
            if (not isinstance(i, str) or not re.fullmatch(r"[A-Fa-f0-9]{32}", i)
                    or i in result or not isinstance(url, str)):
                raise WarmSessionError("G2_PAGE_IDENTITY")
            result[i] = url
        return result

    def task_page():
        current = snapshot()
        if (set(current) != initial_ids | {target}
                or any(current.get(i) != url for i, url in baseline.items())
                or urlsplit(current[target]).scheme != "https"
                or urlsplit(current[target]).hostname != source_host):
            raise WarmSessionError("G2_TASK_SOURCE_CHANGED")

    try:
        run.mkdir()
        _write(run / "request.json", {"owner_request_id": owner_request_id,
               "queries": [asdict(q) for q in queries], "source_url": source_url})
        cli = preflight_antigravity()
        # Reuse the enrolled Chrome, not G1's page-specific precondition.
        # An idle blank/new-tab or existing OpenSubtitles tab is sufficient;
        # do not navigate it, read its content or change G1's rules.
        _ensure_browser_listener(ps, profile)
        browser_identity = browser_id()
        baseline = snapshot()
        initial_ids = set(baseline)
        if len(initial_ids) != 1:
            raise WarmSessionError("G2_BASE_TAB_AMBIGUOUS")
        base_url = next(iter(baseline.values()))
        base = urlsplit(base_url)
        if (base_url not in ("about:blank", "chrome://newtab/", "chrome://new-tab-page/")
                and not (base.scheme == "https" and base.hostname in
                         ("opensubtitles.org", "www.opensubtitles.org"))):
            raise WarmSessionError("G2_BASE_TAB_UNRELATED")
        if base.hostname == source_host:
            raise WarmSessionError("G2_BASE_SOURCE_AMBIGUOUS")
        override = _session_settings(run, Path.home())
        env = dict(os.environ)
        for k in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GEMINI_BASE_URL",
                  "AGY_ADC_AUTH", "GOOGLE_CLOUD_PROJECT", "GOOGLE_CLOUD_QUOTA_PROJECT"):
            env.pop(k, None)
        env.update(TTV_AGY_CLI=str(cli),
                   TTV_AGY_MODEL=_validated_antigravity_alias(model, thinking_level),
                   TTV_SESSION_SETTINGS=str(override))
        _write(run / "browser.started.json", {"operation": "G2_METADATA"})
        effects_started = True
        tab = json.loads(cdp("/json/new?" + source_url, "PUT"))
        tab_id = tab.get("id")
        if (not isinstance(tab_id, str) or not re.fullmatch(r"[A-Fa-f0-9]{32}", tab_id)
                or tab_id in initial_ids):
            raise WarmSessionError("G2_TASK_TAB_UNVERIFIED")
        target = tab_id
        if urlsplit(tab.get("url", "")).hostname != source_host:
            # Chrome can report about:blank while the new tab starts; require a verified page.
            current = next((p for p in pages() if p.get("id") == target), {})
            if urlsplit(current.get("url", "")).hostname != source_host:
                raise WarmSessionError("G2_TASK_SOURCE_UNVERIFIED")
        session = session_factory(ps=ps, env=env, root=run)
        with session:
            for index, q in enumerate(queries):
                if rows and should_yield():
                    break
                session.timeout = TURN_SECONDS
                task_page()
                request_id = uuid.uuid4().hex
                result = session.turn(_prompt(q, source_url, request_id), run / request_id,
                                      source_host=source_host)
                task_page()
                row = (_selected_metadata(result.response, q, request_id, source_host,
                                          run / request_id / "agy-stdout.jsonl")
                       if q.select_release else _metadata(result.response, q, request_id))
                row["timing"] = {"first_mcp_ms": result.first_mcp_ms,
                                 "final_ms": result.final_ms,
                                 "mcp_outcomes": result.mcp_outcomes,
                                 "mcp_errors": result.mcp_errors}
                row["owner_request_id"] = owner_request_id
                row["turn_index"] = index
                row["turn_request_id"] = request_id
                row["query"] = asdict(q)
                _write(run / request_id / "result.json", row)
                rows.append(row)
                _write(run / "checkpoint.json", {"status": "IN_PROGRESS", "owner_request_id": owner_request_id,
                       "results": rows, "requested_count": len(queries)})
                if row["status"] in ("ACCESS_BLOCKED", "UNKNOWN"):
                    break
        finished = True
    except Exception as exc:
        failure = warm_reason(exc)
    finally:
        # Only close this job's temporary tab after the owned CLI is known exited.
        if target is not None and (session is None or not session.started or session.clean_exit):
            try:
                if browser_id() == browser_identity:
                    current = snapshot()
                    if (set(current) == initial_ids | {target}
                            and all(current.get(i) == url for i, url in baseline.items())):
                        cdp("/json/close/" + target)
                    restored = snapshot() == baseline and browser_id() == browser_identity
            except Exception:
                restored = False
        if effects_started and not restored:
            cleanup_reason = "G2_BROWSER_EFFECT_REVIEW_REQUIRED"
            failure = failure or cleanup_reason
        try:
            if finished and restored and failure is None:
                _write(run / "completed.json", {"owner_request_id": owner_request_id, "results": rows, "clean_exit": session.clean_exit,
                      "status": "COMPLETE" if len(rows) == len(queries) else "PARTIAL"})
            elif failure is not None and run.is_dir():
                _write(run / "terminal.json", {"status": "REVIEW_REQUIRED", "reason": failure,
                       "cleanup_reason": cleanup_reason, "owner_request_id": owner_request_id,
                       "results": rows, "requested_count": len(queries), "browser_restored": restored,
                       "elapsed_ms": round((time.monotonic() - started_at) * 1000)})
            if (not effects_started or restored) and pending.is_file() and not pending.is_symlink():
                if pending.read_text("utf-8") == run.name:
                    pending.unlink()
        except Exception as exc:
            failure = failure or warm_reason(exc)
    if failure is not None:
        raise G2BatchReview(failure, rows, browser_restored=restored,
                            cleanup_reason=cleanup_reason)
    return rows

"""G2.1 metadata-only consumer of the existing Owner browser and AGY session.

The trusted Owner caller establishes C1.5/C5 source and content authority.
No acquisition, magnet handoff, add, play, network ingress or scheduler here.
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


MAX_BATCH = 2
# Independent budgets, at most two turns, no automatic retries.
TURN_SECONDS = 120


class G2BatchReview(WarmSessionError):
    """A failed batch retains verified completed rows, not a success verdict."""

    def __init__(self, reason, rows, *, browser_restored):
        super().__init__(reason)
        self.reason = reason
        self.rows = tuple(rows)
        self.browser_restored = browser_restored


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
            or q.resolution not in ("720p", "1080p", "2160p")):
        raise ValueError("G2_QUERY_INVALID")
    return q


def _normalized(s):
    return " ".join(s.casefold().split())


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
        title = row.get("title")
        if not isinstance(title, str) or _normalized(title) != _normalized(query.title):
            continue
        if type(row.get("year")) is not int or row["year"] != query.year:
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
    rows.sort(key=lambda r: (r["requested_resolution"], r["preferred_size"],
                            r["seeds"] if r["seeds"] is not None else -1), reverse=True)
    if status != "MATCH_FOUND":
        rows = []
    if status == "MATCH_FOUND" and not rows:
        status = "NO_EXACT_MATCH_REPORTED"
    return {"status": status, "candidates": rows, "evidence": "MODEL_REPORTED_METADATA"}


def _prompt(query, source_url, request_id):
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
        'Prefer exact requested resolution, soft 5000-12000 MB and highest reported seeds. '
        'Do not imply seed count guarantees speed.'
    )


def discover_movie_batch(profile, queries, cache_root, *, source_url, authorized_source,
                         model="gemini-4-hydrogen-low", thinking_level="low",
                         session_factory=OwnerAgyWarmSession, should_yield=lambda: False):
    """Call under NativeBrowserProducer._browser_lock; no runtime startup effect."""
    from agy_v13_native_producer import _ensure_browser_listener, _session_settings, _write
    if authorized_source is not True:
        raise ValueError("G2_SOURCE_AUTHORITY_REQUIRED")
    source_host = _source(source_url)
    queries = tuple(_query(q) for q in islice(queries, MAX_BATCH + 1))
    if len(queries) > MAX_BATCH:
        raise ValueError("G2_BATCH_LIMIT")
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
    run = parent / ("g2-" + uuid.uuid4().hex)
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
                row = _metadata(result.response, q, request_id)
                row["timing"] = {"first_mcp_ms": result.first_mcp_ms,
                                 "final_ms": result.final_ms,
                                 "mcp_outcomes": result.mcp_outcomes,
                                 "mcp_errors": result.mcp_errors}
                row["turn_index"] = index
                row["turn_request_id"] = request_id
                row["query"] = asdict(q)
                _write(run / request_id / "result.json", row)
                rows.append(row)
                _write(run / "checkpoint.json", {"status": "IN_PROGRESS",
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
            failure = "G2_BROWSER_EFFECT_REVIEW_REQUIRED"
        try:
            if finished and restored and failure is None:
                _write(run / "completed.json", {"results": rows, "clean_exit": session.clean_exit,
                      "status": "COMPLETE" if len(rows) == len(queries) else "PARTIAL"})
            elif failure is not None and run.is_dir():
                _write(run / "terminal.json", {"status": "REVIEW_REQUIRED", "reason": failure,
                       "results": rows, "requested_count": len(queries), "browser_restored": restored,
                       "elapsed_ms": round((time.monotonic() - started_at) * 1000)})
            if (not effects_started or restored) and pending.is_file() and not pending.is_symlink():
                if pending.read_text("utf-8") == run.name:
                    pending.unlink()
        except Exception as exc:
            failure = failure or warm_reason(exc)
    if failure is not None:
        raise G2BatchReview(failure, rows, browser_restored=restored)
    return rows

"""Native V13.1 producer, adapted from BT26 f42af2a2 (no fixture IDs).
No startup effects: constructed only for the explicit Owner native candidate.
One dedicated existing Chrome 9555 profile, one AGY call, no fallback.
"""
from __future__ import annotations

from dataclasses import asdict
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
from contextlib import closing
import subprocess
from threading import Lock
import time
import uuid
from urllib.parse import urlsplit
from urllib.request import build_opener, ProxyHandler

from agy_opensubtitles_acquisition import AgyEnglishUnavailable
from agy_v13_browser_evidence import (
    BrowserEvidence, BrowserRequest, MAX_DOWNLOAD_BYTES, _valid_probe,
    verify_evidence, timeline_observation, VERIFICATION_REVISION,
)
from matcher import Media
from owner_selected_file_resolver import _one_basename
from owner_torrserver_readonly import OwnerTorrServerReadError
from owner_torrserver_ffp_tracks import TorrServerProbeBlocked, _read_local_ffp
from translator_gateway import preflight_antigravity, _validated_antigravity_alias

SITE = {"opensubtitles.org", "www.opensubtitles.org"}
TOOLS = ("list_pages", "select_page", "navigate_page", "take_snapshot",
         "click", "fill", "press_key", "wait_for", "evaluate_script")
MAX_JSON = 16 * 1024 * 1024


class NativeNoCall(AgyEnglishUnavailable):
    """Only a proven pre-provider failure may be retried by Owner."""


class NativeTerminalNoSource(AgyEnglishUnavailable):
    """Known finished CLI and proven absence of a download-capable action."""


def _hold(code):
    raise AgyEnglishUnavailable("AGY_EN_NATIVE_" + code)


def _json(path, limit=MAX_JSON):
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= limit:
        _hold("PRIVATE_RECORD_INVALID")
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _write(path, obj):
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("x", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=True, separators=(",", ":"))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def _job(root, media):
    key = hashlib.sha256("\0".join((
        media.server_profile_id, media.torrent_hash.lower(),
        str(media.file_index))).encode()).hexdigest()
    return root / ".native-v13" / key


def _digest(data):
    return hashlib.sha256(data).hexdigest()


def _receipt(media, asset):
    return {"filename": media.filename, "sha256": asset.sha256,
            "cues": asset.cues, "verification_revision": VERIFICATION_REVISION}


def _receipt_matches(row, media, asset):
    if not isinstance(row, dict):
        return False
    # Accept old receipt shape only AFTER revalidating original bytes/evidence.
    expected = _receipt(media, asset)
    return (row == expected or
            {k: v for k, v in row.items() if k != "verification_revision"} ==
            {k: v for k, v in expected.items() if k != "verification_revision"})


def _retained_proof(run, media):
    evidence = _json(run / "evidence.json")
    original = Media(**evidence["media"])
    # P4 may only have exact file coordinates, not the optional release hint.
    if (original.key != media.key or original.filename != media.filename
            or (media.torrent_title is not None and original.torrent_title != media.torrent_title)
            or (media.movie_hash is not None and original.movie_hash != media.movie_hash)):
        _hold("RETAINED_MEDIA_MISMATCH")
    artifact = run / "download.bin"
    if artifact.is_symlink() or not artifact.is_file() or not 0 < artifact.stat().st_size <= MAX_DOWNLOAD_BYTES:
        _hold("RETAINED_ARTIFACT_INVALID")
    proof = BrowserEvidence(original, evidence["duration"], evidence["fps"],
        tuple(evidence["outcomes"]), tuple(evidence["artifacts"]), artifact.read_bytes(), True)
    return proof, verify_evidence(BrowserRequest(original), proof)


def _retained_verified(run, media):
    proof, asset = _retained_proof(run, media)
    if not _receipt_matches(_json(run / "verified.json", 4096), proof.media, asset):
        _hold("RETAINED_RECEIPT_MISMATCH")
    return proof, asset


def recover_comparison_rejected(run, media):
    """Owner maintenance: revalidate completed, retained release-policy rejection.

    No browser/provider call; preserve terminal evidence and original ZIP.
    Caller must stop Owner and bind the exact event/media before requeue.
    """
    if run.is_symlink() or run.parent.is_symlink() or (run.parent / "browser.pending").exists():
        _hold("BROWSER_BUSY_OR_UNKNOWN")
    terminal = _json(run / "terminal.json", 4096)
    if (terminal.get("status") != "SOURCE_REJECTED"
            or terminal.get("reason") not in {"AGY_EN_RELEASE_COMPARISON_MISSING",
                                              "AGY_EN_MEDIA_RELEASE_MISMATCH",
                                              "AGY_EN_LIST_COVERAGE_UNVERIFIED",
                                              "AGY_EN_DOWNLOAD_BOUND_LIST_COVERAGE_HOLD"}
            or not (run / "provider.started.json").is_file()):
        _hold("PRIOR_ATTEMPT_REVIEW_REQUIRED")
    proof, asset = _retained_proof(run, media)
    receipt = run / "verified.json"
    if receipt.exists():
        if not _receipt_matches(_json(receipt, 4096), proof.media, asset):
            _hold("RETAINED_RECEIPT_MISMATCH")
    else:
        _write(receipt, _receipt(proof.media, asset))
    return asset


def native_cache_verified(root, media, sha, cues):
    """A V13 receipt or a previously independently staged exact EN source."""
    try:
        job = _job(root, media)
        if root.is_symlink() or job.parent.is_symlink() or job.is_symlink():
            return False
        row = _json(job / "verified.json", 4096)
        expected = {"filename": media.filename, "sha256": sha, "cues": cues,
                    "verification_revision": VERIFICATION_REVISION}
        if row == expected:
            return True
        if isinstance(row, dict) and all(row.get(k) == expected[k] for k in ("filename", "sha256", "cues")):
            _, asset = _retained_verified(job, media)
            return (asset.sha256, asset.cues) == (sha, cues)
    except (OSError, ValueError, TypeError, KeyError, AgyEnglishUnavailable):
        pass
    from brain_english_inbox import acquire_brain_english
    try:
        staged = acquire_brain_english(media, root)
        return staged.sha256 == sha and staged.cues == cues
    except (OSError, ValueError):
        return False


def measured_metadata(raw):
    """Use actual container duration and a single real video stream's FPS."""
    try:
        doc = json.loads(raw)
        tracks = [v for v in doc["streams"] if v["codec_type"] == "video"
                  and not v.get("disposition", {}).get("attached_pic")]
        if len(tracks) != 1:
            _hold("VIDEO_PROBE_AMBIGUOUS")
        duration = float(doc["format"]["duration"])
        fps = float(Fraction(tracks[0]["avg_frame_rate"]))
    except (TypeError, ValueError, KeyError, ZeroDivisionError, OverflowError):
        _hold("VIDEO_PROBE_REQUIRED")
    if not _valid_probe(duration, fps):
        _hold("VIDEO_PROBE_REQUIRED")
    return duration, fps


def _probe_local_stream(url):
    """BT24H bounded ffprobe on the already-authorized exact local /play URL.

    Metadata only; no subtitle extraction, transcode, or provider. This read
    may fetch torrent pieces, so it is only used inside the explicit native
    Owner request after the verified /ffp metadata path fails.
    """
    executable = shutil.which("ffprobe")
    if not executable:
        _hold("FFPROBE_REQUIRED")
    env = {k: v for k, v in os.environ.items()
           if k.lower() not in {"http_proxy", "https_proxy", "all_proxy", "no_proxy"}}
    env["NO_PROXY"] = "127.0.0.1"
    try:
        q = subprocess.run([executable, "-v", "error", "-rw_timeout", "12000000",
            "-protocol_whitelist", "http,tcp", "-show_entries",
            "format=duration:stream=codec_type,avg_frame_rate:stream_disposition=attached_pic",
            "-of", "json", url], env=env, capture_output=True, timeout=45, check=False)
    except (OSError, subprocess.TimeoutExpired):
        _hold("FFPROBE_UNAVAILABLE")
    if q.returncode or not 0 < len(q.stdout) <= 65536:
        _hold("FFPROBE_UNAVAILABLE")
    return q.stdout


def probe_selected(reader, media, transport=_read_local_ffp, stream_probe=_probe_local_stream):
    """Exact P3 identity, preferred /ffp, one local metadata fallback."""
    if (not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", media.torrent_hash)
            or type(media.file_index) is not int or not 0 <= media.file_index < 4096):
        _hold("MEDIA_ID_INVALID")
    record = reader(*media.key)
    if (_one_basename(record.path) != media.filename
            or record.id != media.file_index or record.length <= 0
            or record.torrent_title != media.torrent_title):
        _hold("MEDIA_CHANGED")
    port = reader.config.localhost_port
    try:
        result = measured_metadata(transport(
            f"http://127.0.0.1:{port}/ffp/{media.torrent_hash}/{media.file_index}", 8.0))
    except (TorrServerProbeBlocked, AgyEnglishUnavailable, OSError, TimeoutError):
        # Recheck before reading a stream; no provider or alternative subtitle
        # source is involved. Never probe a different hash/index.
        if reader(*media.key) != record:
            _hold("MEDIA_CHANGED")
        result = measured_metadata(stream_probe(
            f"http://127.0.0.1:{port}/play/{media.torrent_hash}/{media.file_index}"))
    if reader(*media.key) != record:
        _hold("MEDIA_CHANGED")
    return result


def _load_settings(path):
    return _json(path, 4194304) if path.exists() else {}


def _session_settings(run, home):
    """BT26 session-local config, never edit global settings or permissions."""
    primary = home / ".gemini/antigravity-cli/settings.json"
    shared = home / ".gemini/config/config.json"
    global_mcp = home / ".gemini/config/mcp_config.json"
    config = _load_settings(primary)
    other = _load_settings(shared)
    servers = _load_settings(global_mcp).get("mcpServers", {})
    if not isinstance(servers, dict) or "ttv-browser" in servers:
        _hold("GLOBAL_MCP_CONFLICT")
    if not isinstance(config, dict) or not isinstance(other, dict):
        _hold("CONFIG_INVALID")
    relative = re.compile(r"(?:read_file|write_file)\(\.git[/\\]aios[/\\]?\)")
    # Shared AI Commerce rules belong to AGY's own config loader. Do not
    # reject a Torrent TV session merely because a relative rule exists.
    # Preserve the shared config byte-for-byte and let the CLI report errors.
    permissions = config.setdefault("permissions", {})
    if not isinstance(permissions, dict):
        _hold("CONFIG_INVALID")
    # Keep unfamiliar/absolute/glob rules unchanged. The CLI owns rule
    # parsing and enforcement; no guessed syntax error is a Torrent TV HOLD.
    restricted_browser = False
    for key in ("allow", "deny", "ask"):
        rules = permissions.setdefault(key, [])
        if not isinstance(rules, list):
            _hold("CONFIG_INVALID")
        for i, rule in enumerate(rules):
            if not isinstance(rule, str):
                continue
            if key != "allow" and (rule.startswith("mcp(ttv-browser") or rule == "mcp(*)"):
                restricted_browser = True
            if relative.fullmatch(rule):
                rules[i] = rule.split("(")[0] + "(" + (run / ".git/aios").as_posix() + ")"
    # Respect existing deny/ask rules; do not add competing allow entries
    # for this browser if the owner already configured a restriction.
    if not restricted_browser:
        for tool in TOOLS:
            grant = "mcp(ttv-browser/" + tool + ")"
            if grant not in permissions["allow"]:
                permissions["allow"].append(grant)
    config.pop("agentMode", None)
    agents = run / ".agents"
    agents.mkdir()
    _write(agents / "mcp_config.json", {"mcpServers": {"ttv-browser": {
        "command": "cmd.exe", "args": ["/d", "/c", "npx", "-y",
        "chrome-devtools-mcp@1.14.0", "--browser-url=http://127.0.0.1:9555",
        "--no-usage-statistics"]}}})
    override = run / "session-settings.json"
    _write(override, config)
    return override


def _ensure_browser_listener(ps, profile):
    """BT26 recovery: start only the enrolled profile if it is absent.

    Never kill a process, reset a profile, change ports, or touch 9444. Run
    only inside the native acquisition request, not Owner startup.
    """
    env = dict(os.environ, TTV_NATIVE_PROFILE=str(profile))
    cmd = r"""
$ErrorActionPreference='Stop'
$profile=$env:TTV_NATIVE_PROFILE
function Listeners { @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {$_.LocalPort -eq 9555}) }
$l=@(Listeners)
if($l.Count -eq 0){
  $roots=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object {
    $_.CommandLine -and $_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0
  })
  if($roots.Count -ne 0){exit 4}
  $chrome=Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
  if(-not (Test-Path -LiteralPath $profile -PathType Container) -or -not (Test-Path -LiteralPath $chrome -PathType Leaf)){exit 5}
  Start-Process -FilePath $chrome -ArgumentList @('--user-data-dir="'+$profile+'"','--remote-debugging-port=9555','--remote-debugging-address=127.0.0.1','--no-first-run','--no-default-browser-check','--new-window','https://www.opensubtitles.org/')
  for($i=0;$i -lt 30;$i++){
    Start-Sleep -Milliseconds 500
    $l=@(Listeners)
    if($l.Count -gt 0){break}
  }
}
$pids=@($l | Select-Object -ExpandProperty OwningProcess -Unique)
if($pids.Count -ne 1 -or @($l|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count){exit 2}
$p=Get-CimInstance Win32_Process -Filter ("ProcessId="+$pids[0])
if($p.Name -ne 'chrome.exe' -or !$p.CommandLine -or $p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $p.CommandLine -notmatch '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|\z)'){exit 3}
exit 0
"""
    try:
        code = subprocess.run([ps, "-NoProfile", "-NonInteractive", "-Command", cmd],
                              env=env, capture_output=True, timeout=40).returncode
    except (OSError, subprocess.TimeoutExpired):
        _hold("BROWSER_START_UNVERIFIED")
    if code:
        _hold({4: "BROWSER_PROFILE_RUNNING_NO_LISTENER",
               5: "BROWSER_PROFILE_OR_EXECUTABLE_MISSING"}.get(code, "BROWSER_IDENTITY"))


def _verify_browser(ps, profile):
    _ensure_browser_listener(ps, profile)
    opener = build_opener(ProxyHandler({}))
    def local(path):
        with opener.open("http://127.0.0.1:9555" + path, timeout=3) as f:
            return json.loads(f.read(65536))
    version = local("/json/version")
    if (not str(version.get("Browser", "")).startswith("Chrome/")
            or not str(version.get("webSocketDebuggerUrl", "")).startswith("ws://127.0.0.1:9555/")):
        _hold("CDP_IDENTITY")
    tabs = [p for p in local("/json/list") if p.get("type") == "page"]
    if len(tabs) != 1:
        _hold("TASK_TAB_AMBIGUOUS")
    tab = tabs[0]
    u = urlsplit(tab.get("url", ""))
    if u.scheme != "https" or u.hostname not in SITE or re.search(
            r"captcha|access denied|just a moment|making sure you.re not a bot",
            tab.get("title", "") + " " + tab.get("url", ""), re.I):
        _hold("TASK_TAB_UNAVAILABLE")
    return u.hostname


def _observed_outcomes(stdout, host):
    outcomes = []
    names = set()
    first = None
    for i, line in enumerate(stdout.splitlines()):
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        step = event.get("step_update")
        if not isinstance(step, dict) or step.get("tool_name") != "call_mcp_tool":
            continue
        info = step.get("tool_info", {})
        params = info.get("parameters", {})
        name = params.get("ToolName")
        for key in ("ServerName", "Server", "serverName", "server"):
            if isinstance(params.get(key), str):
                names.add(params[key])
        if name in TOOLS and ("output" in info or "error" in info):
            row = {"event": i, "tool": name, "output": info.get("output", ""),
                   "error": info.get("error")}
            outcomes.append(row)
            if name == "list_pages" and first is None:
                first = row["output"]
    pages = re.findall(r"(?m)^\s*\d+:\s*(.+)$", str(first or ""))
    if (names != {"ttv-browser"} or len(pages) != 1
            or not re.search(r"https://" + re.escape(host) + r"(?:/|[)\s]|$)", pages[0], re.I)):
        _hold("MCP_TAB_UNBOUND")
    if re.search(r"making sure you.re not a bot|/\.within\.website/|anti.bot challenge|captcha",
                 "\n".join(str(row["output"]) for row in outcomes), re.I):
        _hold("ACCESS_BLOCKED")
    return tuple(outcomes)


def _terminal_no_source(stdout):
    """Completed V13.1 trace without explicit download initiation.

    This is necessary, not sufficient: the browser/download observations
    in _finish_no_source independently decide whether to release the claim.
    """
    terminal = []
    seen = False
    pending = {}
    try:
        for line in stdout.splitlines():
            if not line.strip():
                continue
            event = json.loads(line)
            if not isinstance(event, dict):
                return False
            if event.get("event") == "result":
                terminal.append(event.get("result"))
            step = event.get("step_update")
            if not isinstance(step, dict):
                continue
            name = step.get("tool_name")
            if not name:
                continue
            if terminal or name != "call_mcp_tool":
                return False
            info = step.get("tool_info")
            if not isinstance(info, dict):
                return False
            params = info.get("parameters")
            if not isinstance(params, dict) or params.get("ToolName") not in TOOLS:
                return False
            tool = params["ToolName"]
            if not ("output" in info or "error" in info):
                pending[tool] = pending.get(tool, 0) + 1
                continue
            if info.get("error"):
                return False
            output = info.get("output", "")
            encoded = json.dumps(output) if not isinstance(output, str) else output
            if re.search(r'"clicked"\s*:\s*true|\bDOWNLOAD_INITIATED\b', encoded, re.I):
                return False
            if pending.get(tool, 0):
                pending[tool] -= 1
            seen = True
        if any(pending.values()) or len(terminal) != 1 or not isinstance(terminal[0], dict):
            return False
        result = terminal[0]
        if result.get("status") != "SUCCESS":
            return False
        payload = result.get("structured_output")
        if not isinstance(payload, dict):
            response = result.get("response")
            payload = json.loads(response) if isinstance(response, str) else None
        return seen and isinstance(payload, dict) and payload.get("status") == "NO_PLAUSIBLE_CANDIDATE"
    except (ValueError, TypeError, AttributeError):
        return False


def _download_destination(profile):
    prefs = _load_settings(profile / "Default/Preferences")
    dest = Path(os.path.expandvars(prefs.get("download", {}).get("default_directory") or str(Path.home() / "Downloads")))
    if not dest.is_absolute() or not dest.is_dir() or dest.is_symlink():
        _hold("DOWNLOAD_DIR_UNVERIFIED")
    return dest


def _browser_identity():
    """Read the existing CDP identity only; never navigate/start it here."""
    opener = build_opener(ProxyHandler({}))
    def local(path):
        with opener.open("http://127.0.0.1:9555" + path, timeout=3) as f:
            return json.loads(f.read(65536))
    version = local("/json/version")
    ws = version.get("webSocketDebuggerUrl", "")
    if not str(version.get("Browser", "")).startswith("Chrome/") or not ws.startswith("ws://127.0.0.1:9555/"):
        return None
    tabs = [p for p in local("/json/list") if p.get("type") == "page"]
    if len(tabs) != 1 or not tabs[0].get("id"):
        return None
    url = urlsplit(tabs[0].get("url", ""))
    if url.scheme != "https" or url.hostname not in SITE:
        return None
    return ws, tabs[0]["id"]


def _download_observation(profile, dest):
    """Bounded read-only observation of the same browser, history and files.

    Missing/locked History, active/unknown download rows, partial files,
    changed destination or browser identity are uncertainty, never 'zero'.
    Fingerprint actual records, including cancelled/interrupted downloads.
    """
    try:
        identity = _browser_identity()
        if identity is None or _download_destination(profile).resolve() != dest.resolve():
            return None
        history = profile / "Default/History"
        if history.is_symlink() or not history.is_file():
            return None
        with closing(sqlite3.connect(history.resolve().as_uri() + "?mode=ro", uri=True, timeout=3)) as con:
            rows = con.execute("select id,state,start_time,received_bytes,total_bytes,target_path,current_path from downloads order by id limit 10001").fetchall()
        if len(rows)>10000 or any(row[1] not in (1,2,3) for row in rows):
            return None
        files = []
        for i, path in enumerate(dest.iterdir()):
            if i>=10000 or path.is_symlink() or path.suffix.lower() in (".crdownload", ".part", ".tmp", ".download"):
                return None
            st = path.stat()
            if path.is_file():
                files.append((path.name, st.st_size, st.st_mtime_ns, st.st_ctime_ns))
        if _browser_identity() != identity:
            return None
        return {"browser": _digest(repr(identity).encode()),
                "history": _digest(repr(rows).encode()),
                "files": _digest(repr(sorted(files)).encode())}
    except (OSError, ValueError, TypeError, AttributeError, sqlite3.Error, AgyEnglishUnavailable):
        return None


def _finish_no_source(stdout, profile, dest, before, run, *, observe=None, wait=None):
    """Reconcile the real search path, not just the model's final message.

    Two unchanged post-CLI observations separated by a quiet interval are
    bounded local evidence, not a guarantee about future asynchronous JS.
    Any observed mutation/download/partial/unknown state retains the claim.
    """
    if before is None or not _terminal_no_source(stdout):
        return False
    observe = observe or _download_observation
    wait = wait or time.sleep
    first = observe(profile, dest)
    if first != before:
        return False
    wait(2)
    second = observe(profile, dest)
    if second != before:
        return False
    _write(run / "no-source-observation.json", {"schema": "TTV-NATIVE-NO-SOURCE-V1",
        "basis": "CLI_TERMINAL_AND_STABLE_BROWSER_HISTORY_DIRECTORY",
        "before": before, "after": [first, second], "quiet_seconds": 2})
    return True


def _download_refs(urls):
    result = []
    for url in urls:
        u = urlsplit(str(url).strip("\0"))
        if u.scheme == "https" and u.hostname in SITE | {"dl.opensubtitles.org"}:
            result.append(u.path)
    return list(dict.fromkeys(result))


def _fresh_downloads(profile, dest, before, wall):
    """Actual Chrome completion history or first-party Windows ADS, as BT26."""
    found = {}
    history = profile / "Default/History"
    if history.is_file():
        try:
            with closing(sqlite3.connect(history.resolve().as_uri() + "?mode=ro", uri=True, timeout=3)) as con:
                cutoff = int((wall + 11644473600) * 1000000)
                for row in con.execute("select id,target_path,state,received_bytes from downloads where start_time>=?", (cutoff,)):
                    if row[2] != 1 or row[3] <= 0:
                        continue
                    f = Path(row[1])
                    if f.is_symlink() or f.parent.resolve() != dest.resolve():
                        continue
                    refs = _download_refs(x[0] for x in con.execute(
                        "select url from downloads_url_chains where id=? order by chain_index", (row[0],)))
                    if refs:
                        found[f.resolve()] = (refs, "ChromeHistory")
        except (OSError, sqlite3.Error):
            pass
    for f in dest.iterdir():
        if f.suffix.lower() not in (".zip", ".srt") or f.is_symlink() or not f.is_file():
            continue
        if f.resolve() in before or f.stat().st_mtime < wall - 1:
            continue
        if f.resolve() not in found:
            try:
                with open(str(f) + ":Zone.Identifier", encoding="utf-8", errors="replace") as z:
                    ads = dict(v.split("=", 1) for v in z.read(8192).splitlines() if "=" in v)
                refs = _download_refs([ads.get("HostUrl", "")])
                if refs:
                    found[f.resolve()] = (refs, "Zone.Identifier")
            except (OSError, ValueError):
                pass
    fresh = []
    for f, (refs, provenance) in found.items():
        if (f in before or f.parent != dest.resolve() or f.is_symlink() or not f.is_file()
                or f.suffix.lower() not in (".zip", ".srt")
                or f.stat().st_mtime < wall - 1 or not 0 < f.stat().st_size <= MAX_DOWNLOAD_BYTES):
            continue
        blob = f.read_bytes()
        fresh.append((blob, {"candidate_refs": refs, "provenance": provenance,
                             "sha256": _digest(blob), "bytes": len(blob), "copied_to_job": True}))
    return fresh


def run_windows(request, run, profile, duration, fps):
    """Execute one bounded CLI call; never retry or infer file from final JSON."""
    if os.name != "nt" or any(os.environ.get(k, "").lower() == "true" for k in ("CI", "GITHUB_ACTIONS")):
        _hold("WINDOWS_OWNER_REQUIRED")
    ps = shutil.which("pwsh")
    if not ps or not profile.is_dir() or profile.is_symlink():
        _hold("PROFILE_REQUIRED")
    cli = preflight_antigravity()
    host = _verify_browser(ps, profile)
    env = dict(os.environ)
    for k in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GEMINI_BASE_URL",
              "AGY_ADC_AUTH", "GOOGLE_CLOUD_PROJECT", "GOOGLE_CLOUD_QUOTA_PROJECT"):
        env.pop(k, None)
    env.update(TTV_AGY_CLI=str(cli), TTV_AGY_MODEL=_validated_antigravity_alias(request.model, request.thinking_level))
    # Do not parse human-oriented help output for each film: AGY 1.5.17
    # writes --settings to stderr (HostOps 45833062581). Keep the actual
    # session-local settings argument and existing unknown-effect handling.
    override = _session_settings(run, Path.home())
    try:
        dest = _download_destination(profile)
        before = {f.resolve() for f in dest.iterdir()}
        baseline = _download_observation(profile, dest)
        prompt = run / "prompt.txt"
        prompt.write_text(request.prompt(duration_seconds=duration, fps=fps), encoding="utf-8")
        env.update(TTV_AGY_PROMPT=str(prompt), TTV_SESSION_SETTINGS=str(override))
        cmd = "$ErrorActionPreference='Stop'; $p=Get-Content -LiteralPath $env:TTV_AGY_PROMPT -Raw; & $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --output-format stream-json -p $p; exit $LASTEXITCODE"
        wall = time.time()
        _write(run / "provider.started.json", {"started": wall})
        with (run / "agy-stdout.jsonl").open("xb") as out, (run / "agy-stderr.txt").open("xb") as err:
            completed = subprocess.run([ps, "-NoProfile", "-NonInteractive", "-Command", cmd],
                env=env, cwd=run, stdout=out, stderr=err, timeout=420)
        if completed.returncode:
            _hold("CLI_RESULT_UNKNOWN")
        stream = run / "agy-stdout.jsonl"
        if not 0 < stream.stat().st_size <= MAX_JSON:
            _hold("STREAM_INVALID")
        stdout = stream.read_text(encoding="utf-8", errors="strict")
        outcomes = _observed_outcomes(stdout, host)
        fresh = []
        for attempt in range(12):
            fresh = _fresh_downloads(profile, dest, before, wall)
            if fresh:
                break
            time.sleep(1)
        if not fresh and _finish_no_source(stdout, profile, dest, baseline, run):
            raise NativeTerminalNoSource("AGY_EN_NATIVE_NO_SOURCE")
        if len(fresh) != 1:
            _hold("DOWNLOAD_UNVERIFIED")
        data, artifact = fresh[0]
        # Private copy is independently read back by the durable producer.
        return BrowserEvidence(request.media, duration, fps, outcomes, (artifact,), data, True)
    finally:
        override.unlink(missing_ok=True)


class NativeBrowserProducer:
    """Existing Owner callback. Durable unknown-effect marker blocks replay.

    On success the exact job evidence is retained, so a crash after acquisition
    but before catalog/checkpoint creation does not trigger another AGY request.
    Browser serialization does not serialize the separate LEAN120 workers.
    """
    def __init__(self, *, profile, probe, execute=run_windows):
        self.profile = profile
        self.probe = probe
        self.execute = execute
        self._browser_lock = Lock()
        self._priority_lock = Lock()
        self._g1_waiting = 0

    def __call__(self, request, cache_root):
        # Announce G1 before waiting for the single browser.
        with self._priority_lock:
            self._g1_waiting += 1
        try:
            with self._browser_lock:
                return self._acquire(request, cache_root)
        finally:
            with self._priority_lock:
                self._g1_waiting -= 1

    def _g1_pending(self):
        with self._priority_lock:
            return self._g1_waiting > 0

    def discover_movies(self, queries, cache_root, *, source_url, authorized_source,
                        model="gemini-4-hydrogen-low", thinking_level="low"):
        """G2 caller uses the same Owner instance and browser lock as G1."""
        from owner_g2_discovery import discover_movie_batch
        with self._browser_lock:
            return discover_movie_batch(
                self.profile, queries, cache_root, source_url=source_url,
                authorized_source=authorized_source, model=model,
                thinking_level=thinking_level, should_yield=self._g1_pending)

    def _acquire(self, request, cache_root):
        run = _job(cache_root, request.media)
        parent = run.parent
        parent.mkdir(parents=True, exist_ok=True)
        if parent.is_symlink() or run.is_symlink():
            _hold("PRIVATE_ROOT_INVALID")
        pending = parent / "browser.pending"
        if run.is_dir() and (run / "verified.json").is_file():
            proof, asset = _retained_verified(run, request.media)
            if proof.media != request.media:
                _hold("RETAINED_MEDIA_MISMATCH")
            # Recover the narrow crash window after a verified receipt but
            # before releasing this job\'s browser claim. Never clear another job.
            if pending.is_file() and not pending.is_symlink() and pending.read_text("utf-8") == run.name:
                pending.unlink()
            return proof
        # Recover only a known no-call attempt and preserve its audit.
        recover = False
        if run.exists():
            terminal = _json(run / "terminal.json", 4096)
            recover = (terminal.get("status") == "PRE_PROVIDER_BLOCKED"
                       and not (run / "provider.started.json").exists()
                       and not (run / "provider.started.json").is_symlink()
                       and not pending.exists() and not pending.is_symlink())
            if not recover:
                _hold("PRIOR_ATTEMPT_REVIEW_REQUIRED")
        try:
            duration, fps = self.probe(request.media)
            if not _valid_probe(duration, fps):
                raise AgyEnglishUnavailable("AGY_EN_NATIVE_VIDEO_PROBE_REQUIRED")
        except (AgyEnglishUnavailable, OwnerTorrServerReadError, OSError, TimeoutError) as exc:
            if str(exc) in ("AGY_EN_NATIVE_MEDIA_CHANGED", "AGY_EN_NATIVE_MEDIA_ID_INVALID"):
                raise
            raise NativeNoCall("AGY_EN_NATIVE_PRE_PROVIDER_BLOCKED") from None
        # One cross-process browser claim. Do not automatically remove a stale
        # marker: PowerShell timeout may leave a native descendant alive.
        try:
            with pending.open("x", encoding="utf-8") as f:
                f.write(run.name)
                f.flush()
                os.fsync(f.fileno())
        except FileExistsError:
            _hold("BROWSER_BUSY_OR_UNKNOWN")
        completed_artifact = False
        try:
            if recover:
                run.rename(parent / (run.name + ".preprovider-" + uuid.uuid4().hex))
            run.mkdir()
            proof = self.execute(request, run, self.profile, duration, fps)
            # A returned synchronous browser receipt proves the invocation
            # finished. A later source-quality rejection is not an uncertain
            # browser effect. Keep the raw evidence even if the gate rejects.
            completed_artifact = isinstance(proof, BrowserEvidence)
            if not completed_artifact or (proof.duration_seconds, proof.fps) != (duration, fps):
                _hold("PROBE_BINDING_MISMATCH")
            with (run / "download.bin").open("xb") as f:
                f.write(proof.download_bytes)
                f.flush()
                os.fsync(f.fileno())
            if (run / "download.bin").read_bytes() != proof.download_bytes:
                _hold("ARTIFACT_READBACK_MISMATCH")
            evidence = {"media": asdict(request.media), "duration": duration,
                "fps": fps, "outcomes": proof.outcomes, "artifacts": proof.artifacts}
            _write(run / "evidence.json", evidence)
            asset = verify_evidence(request, proof)
            evidence["timeline_observation"] = timeline_observation(asset.contents, duration)
            _write(run / "evidence.json", evidence)
            _write(run / "verified.json", _receipt(request.media, asset))
            pending.unlink()
            return proof
        except Exception as exc:
            pre_provider = self.execute is run_windows and not (run / "provider.started.json").exists()
            terminal_no_source = isinstance(exc, NativeTerminalNoSource)
            known = completed_artifact or pre_provider or terminal_no_source
            status = ("PRE_PROVIDER_BLOCKED" if pre_provider else
                      "NO_SOURCE" if terminal_no_source else
                      "SOURCE_REJECTED" if completed_artifact else "RESULT_UNKNOWN_REVIEW_REQUIRED")
            if run.is_dir():
                code = str(exc) if isinstance(exc, AgyEnglishUnavailable) and re.fullmatch(r"AGY_EN_[A-Z0-9_]+", str(exc)) else None
                _write(run / "terminal.json", {"status": status,
                    "error_type": type(exc).__name__, "reason": code})
            if known:
                pending.unlink()
                if pre_provider:
                    raise NativeNoCall("AGY_EN_NATIVE_PRE_PROVIDER_BLOCKED") from None
                if terminal_no_source:
                    raise NativeTerminalNoSource("AGY_EN_NATIVE_NO_SOURCE") from None
                raise AgyEnglishUnavailable("AGY_EN_NATIVE_" + status) from None
            raise AgyEnglishUnavailable("AGY_EN_NATIVE_RESULT_UNKNOWN") from None


def owner_native_runner(reader):
    """BT26's dedicated enrolled profile; no new browser or scheduled task."""
    root = Path(os.environ["LOCALAPPDATA"]) / "TorrentTVVietsub/NativeBrowserTest/CDP9555Profile"
    return NativeBrowserProducer(profile=root, probe=lambda media: probe_selected(reader, media))

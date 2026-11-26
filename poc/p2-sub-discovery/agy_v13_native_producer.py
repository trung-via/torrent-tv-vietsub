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
import subprocess
import time
from urllib.parse import urlsplit
from urllib.request import build_opener, ProxyHandler

from agy_opensubtitles_acquisition import AgyEnglishUnavailable
from agy_v13_browser_evidence import (
    BrowserEvidence, BrowserRequest, MAX_DOWNLOAD_BYTES, _valid_probe,
    verify_evidence,
)
from owner_selected_file_resolver import _one_basename
from owner_torrserver_ffp_tracks import _read_local_ffp
from translator_gateway import preflight_antigravity, _validated_antigravity_alias

SITE = {"opensubtitles.org", "www.opensubtitles.org"}
TOOLS = ("list_pages", "select_page", "navigate_page", "take_snapshot",
         "click", "fill", "press_key", "wait_for", "evaluate_script")
MAX_JSON = 16 * 1024 * 1024


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


def native_cache_verified(root, media, sha, cues):
    """A V13 receipt or a previously independently staged exact EN source."""
    try:
        row = _json(_job(root, media) / "verified.json", 4096)
        if row == {"filename": media.filename, "sha256": sha, "cues": cues}:
            return True
    except (OSError, ValueError, TypeError):
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


def probe_selected(reader, media, transport=_read_local_ffp):
    """Recheck exact P3 coordinates and use the existing loopback /ffp path."""
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", media.torrent_hash):
        _hold("MEDIA_ID_INVALID")
    record = reader(*media.key)
    if (_one_basename(record.path) != media.filename
            or record.id != media.file_index
            or record.torrent_title != media.torrent_title):
        _hold("MEDIA_CHANGED")
    port = reader.config.localhost_port
    return measured_metadata(transport(
        f"http://127.0.0.1:{port}/ffp/{media.torrent_hash}/{media.file_index}", 3.0))


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
    if re.search(r"\.git[/\\]aios", json.dumps(other).replace("\\\\", "\\")):
        _hold("SHARED_RELATIVE_RULE")
    permissions = config.setdefault("permissions", {})
    if not isinstance(permissions, dict):
        _hold("CONFIG_INVALID")
    for key in ("allow", "deny", "ask"):
        rules = permissions.setdefault(key, [])
        if not isinstance(rules, list):
            _hold("CONFIG_INVALID")
        for i, rule in enumerate(rules):
            if not isinstance(rule, str):
                continue
            if key != "allow" and (rule.startswith("mcp(ttv-browser") or rule == "mcp(*)"):
                _hold("EXISTING_RESTRICTION")
            if relative.fullmatch(rule):
                rules[i] = rule.split("(")[0] + "(" + (run / ".git/aios").as_posix() + ")"
            elif re.search(r"\.git[/\\]aios", rule):
                _hold("RELATIVE_RULE_UNKNOWN")
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


def _verify_browser(ps, profile):
    # Verify the already-enrolled dedicated Chrome, never start/kill Chrome.
    env = dict(os.environ, TTV_NATIVE_PROFILE=str(profile))
    cmd = r"""
$l=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction Stop)
$pids=@($l | Select-Object -ExpandProperty OwningProcess -Unique)
if($pids.Count -ne 1 -or @($l|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count){exit 2}
$p=Get-CimInstance Win32_Process -Filter ("ProcessId="+$pids[0])
if($p.Name -ne 'chrome.exe' -or !$p.CommandLine -or $p.CommandLine.IndexOf($env:TTV_NATIVE_PROFILE,[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $p.CommandLine -notmatch '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|\z)'){exit 3}
exit 0
"""
    if subprocess.run([ps, "-NoProfile", "-NonInteractive", "-Command", cmd],
                      env=env, capture_output=True, timeout=15).returncode:
        _hold("BROWSER_IDENTITY")
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
            with sqlite3.connect(history.resolve().as_uri() + "?mode=ro", uri=True, timeout=3) as con:
                cutoff = int((wall + 11644473600) * 1000000)
                for row in con.execute("select id,target_path,state,received_bytes from downloads where start_time>=?", (cutoff,)):
                    if row[2] != 1 or row[3] <= 0:
                        continue
                    f = Path(row[1])
                    if f.parent.resolve() != dest.resolve():
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
    host = _verify_browser(ps, profile)
    cli = preflight_antigravity()
    env = dict(os.environ)
    for k in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GEMINI_BASE_URL",
              "AGY_ADC_AUTH", "GOOGLE_CLOUD_PROJECT", "GOOGLE_CLOUD_QUOTA_PROJECT"):
        env.pop(k, None)
    env.update(TTV_AGY_CLI=str(cli), TTV_AGY_MODEL=_validated_antigravity_alias(request.model, request.thinking_level))
    help_result = subprocess.run([ps, "-NoProfile", "-NonInteractive", "-Command",
        "& $env:TTV_AGY_CLI --help; exit $LASTEXITCODE"], env=env,
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20)
    if help_result.returncode or not re.search(r"(?m)^\s*--?settings(?:[ =\t]|$)", help_result.stdout):
        _hold("SESSION_SETTINGS_UNAVAILABLE")
    override = _session_settings(run, Path.home())
    try:
        prefs = _load_settings(profile / "Default/Preferences")
        dest = Path(os.path.expandvars(prefs.get("download", {}).get("default_directory") or str(Path.home() / "Downloads")))
        if not dest.is_absolute() or not dest.is_dir() or dest.is_symlink():
            _hold("DOWNLOAD_DIR_UNVERIFIED")
        before = {f.resolve() for f in dest.iterdir()}
        prompt = run / "prompt.txt"
        prompt.write_text(request.prompt(duration_seconds=duration, fps=fps), encoding="utf-8")
        env.update(TTV_AGY_PROMPT=str(prompt), TTV_SESSION_SETTINGS=str(override))
        cmd = "$ErrorActionPreference='Stop'; $p=Get-Content -LiteralPath $env:TTV_AGY_PROMPT -Raw; & $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox --settings $env:TTV_SESSION_SETTINGS --output-format stream-json -p $p; exit $LASTEXITCODE"
        wall = time.time()
        with (run / "agy-stdout.jsonl").open("xb") as out, (run / "agy-stderr.txt").open("xb") as err:
            completed = subprocess.run([ps, "-NoProfile", "-NonInteractive", "-Command", cmd],
                env=env, cwd=run, stdout=out, stderr=err, timeout=420)
        if completed.returncode:
            _hold("CLI_RESULT_UNKNOWN")
        stream = run / "agy-stdout.jsonl"
        if not 0 < stream.stat().st_size <= MAX_JSON:
            _hold("STREAM_INVALID")
        outcomes = _observed_outcomes(stream.read_text(encoding="utf-8", errors="replace"), host)
        fresh = []
        for attempt in range(12):
            fresh = _fresh_downloads(profile, dest, before, wall)
            if fresh:
                break
            time.sleep(1)
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

    def __call__(self, request, cache_root):
        run = _job(cache_root, request.media)
        parent = run.parent
        parent.mkdir(parents=True, exist_ok=True)
        if parent.is_symlink() or run.is_symlink():
            _hold("PRIVATE_ROOT_INVALID")
        pending = parent / "browser.pending"
        if run.is_dir() and (run / "verified.json").is_file():
            evidence = _json(run / "evidence.json")
            if evidence["media"] != asdict(request.media):
                _hold("RETAINED_MEDIA_MISMATCH")
            raw = (run / "download.bin").read_bytes()
            proof = BrowserEvidence(request.media, evidence["duration"], evidence["fps"],
                tuple(evidence["outcomes"]), tuple(evidence["artifacts"]), raw, True)
            asset = verify_evidence(request, proof)
            if _json(run / "verified.json") != {"filename": request.media.filename,
                    "sha256": asset.sha256, "cues": asset.cues}:
                _hold("RETAINED_RECEIPT_MISMATCH")
            return proof
        if run.exists():
            _hold("PRIOR_ATTEMPT_REVIEW_REQUIRED")
        # Fail before claiming a provider attempt if metadata isn't measured.
        duration, fps = self.probe(request.media)
        if not _valid_probe(duration, fps):
            _hold("VIDEO_PROBE_REQUIRED")
        # One cross-process browser claim. Do not automatically remove a stale
        # marker: PowerShell timeout may leave a native descendant alive.
        try:
            with pending.open("x", encoding="utf-8") as f:
                f.write(run.name)
                f.flush()
                os.fsync(f.fileno())
        except FileExistsError:
            _hold("BROWSER_BUSY_OR_UNKNOWN")
        try:
            run.mkdir()
            proof = self.execute(request, run, self.profile, duration, fps)
            asset = verify_evidence(request, proof)
            if (proof.duration_seconds, proof.fps) != (duration, fps):
                _hold("PROBE_BINDING_MISMATCH")
            with (run / "download.bin").open("xb") as f:
                f.write(proof.download_bytes)
                f.flush()
                os.fsync(f.fileno())
            _write(run / "evidence.json", {"media": asdict(request.media),
                "duration": duration, "fps": fps, "outcomes": proof.outcomes,
                "artifacts": proof.artifacts})
            _write(run / "verified.json", {"filename": request.media.filename,
                "sha256": asset.sha256, "cues": asset.cues})
            pending.unlink()
            return proof
        except Exception as exc:
            if run.is_dir():
                _write(run / "terminal.json", {"status": "RESULT_UNKNOWN_REVIEW_REQUIRED",
                    "error_type": type(exc).__name__})
            raise AgyEnglishUnavailable("AGY_EN_NATIVE_RESULT_UNKNOWN") from None


def owner_native_runner(reader):
    """BT26's dedicated enrolled profile; no new browser or scheduled task."""
    root = Path(os.environ["LOCALAPPDATA"]) / "TorrentTVVietsub/NativeBrowserTest/CDP9555Profile"
    return NativeBrowserProducer(profile=root, probe=lambda media: probe_selected(reader, media))

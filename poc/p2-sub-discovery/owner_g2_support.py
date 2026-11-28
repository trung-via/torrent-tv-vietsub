"""G2.1 shared native primitives, extracted from #195.

No startup side effects. Called only by the existing Owner under its browser
lock. The G1 producer may reuse these primitives when its source is reconciled;
do not install or start another runtime from this module.
"""
from __future__ import annotations
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from typing import Mapping
from agy_owner_warm_session import WarmSessionError

TOOLS = ("list_pages", "select_page", "navigate_page", "take_snapshot",
         "click", "fill", "press_key", "wait_for", "evaluate_script")
MAX_JSON = 16 * 1024 * 1024
_MODEL_SLUG = re.compile(r"[a-z0-9][a-z0-9._-]{0,127}\Z")
_THINKING_LEVELS = frozenset({"low", "medium", "high"})

def _hold(code):
    raise WarmSessionError("G2_NATIVE_" + code)

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

def _load_settings(path):
    return _json(path, 4194304) if path.exists() else {}

def _ensure_browser_listener(ps, profile, browser_port=9555):
    """BT26 recovery: start only the enrolled profile if it is absent.

    Never kill a process, reset a profile, change ports, or touch 9444. Run
    only inside the native acquisition request, not Owner startup.
    """
    if browser_port not in (9555, 9556):
        raise ValueError("G2_BROWSER_PORT")
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
    cmd = cmd.replace("9555", str(browser_port))
    if browser_port == 9556:
        cmd = cmd.replace("https://www.opensubtitles.org/", "about:blank")
    try:
        code = subprocess.run([ps, "-NoProfile", "-NonInteractive", "-Command", cmd],
                              env=env, capture_output=True, timeout=40).returncode
    except (OSError, subprocess.TimeoutExpired):
        _hold("BROWSER_START_UNVERIFIED")
    if code:
        _hold({4: "BROWSER_PROFILE_RUNNING_NO_LISTENER",
               5: "BROWSER_PROFILE_OR_EXECUTABLE_MISSING"}.get(code, "BROWSER_IDENTITY"))

def _session_settings(run, home, browser_port=9555):
    """BT26 session-local config, never edit global settings or permissions."""
    if browser_port not in (9555, 9556):
        raise ValueError("G2_BROWSER_PORT")
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
        "chrome-devtools-mcp@1.14.0", f"--browser-url=http://127.0.0.1:{browser_port}",
        "--no-usage-statistics"]}}})
    override = run / "session-settings.json"
    _write(override, config)
    return override

def _check_owner_account_settings(home: Path) -> None:
    """Reject key-backed/Cloud billing mode, without reading or logging tokens."""
    settings = home / ".gemini" / "antigravity-cli" / "settings.json"
    if settings.is_file():
        try:
            config = json.loads(settings.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError):
            raise ValueError("AGY_ACCOUNT_SETTINGS_UNREADABLE") from None
        if not isinstance(config, dict):
            raise ValueError("AGY_ACCOUNT_SETTINGS_INVALID")
        if config.get("modelProvider") == "gemini":
            raise ValueError("AGY_ACCOUNT_REQUIRED_API_KEY_MODE_REFUSED")
        auth = config.get("auth", {})
        if isinstance(auth, dict) and auth.get("type") not in (None, "oauth-personal"):
            raise ValueError("AGY_PERSONAL_ACCOUNT_MODE_REQUIRED")
    app_config = home / ".gemini" / "config" / "config.json"
    if app_config.is_file():
        try:
            app = json.loads(app_config.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError):
            raise ValueError("AGY_APP_ACCOUNT_SETTINGS_UNREADABLE") from None
        if not isinstance(app, dict):
            raise ValueError("AGY_APP_ACCOUNT_SETTINGS_INVALID")
        user_settings = app.get("userSettings", {})
        if isinstance(user_settings, dict) and user_settings.get("enableAdc") is True:
            raise ValueError("AGY_ACCOUNT_REQUIRED_ADC_MODE_REFUSED")

def preflight_antigravity(*, executable: str = "agy",
                          env: Mapping[str, str] | None = None) -> str:
    """No model call; verify local CLI availability and owner-account mode."""
    environment = dict(os.environ if env is None else env)
    if environment.get("CI", "").lower() == "true" or (
            environment.get("GITHUB_ACTIONS", "").lower() == "true"):
        raise ValueError("AGY_LIVE_PROVIDER_FORBIDDEN_IN_CI")
    home = environment.get("USERPROFILE") or environment.get("HOME")
    if not home:
        raise ValueError("AGY_OWNER_HOME_UNAVAILABLE")
    _check_owner_account_settings(Path(home))
    resolved = shutil.which(executable, path=environment.get("PATH"))
    if not resolved:
        raise ValueError("AGY_CLI_NOT_INSTALLED_FOR_OWNER")
    return resolved

def _validated_antigravity_alias(model: object, thinking_level: object) -> str:
    """Require an explicit level-bearing CLI model alias, not an ignored knob.

    This checks internal consistency only. The real CLI's advertised model
    aliases still need a read-only Windows verification before a provider call.
    """
    if not isinstance(model, str) or not _MODEL_SLUG.fullmatch(model):
        raise ValueError("AGY_MODEL_SLUG_INVALID")
    if (not isinstance(thinking_level, str) or
            thinking_level not in _THINKING_LEVELS or
            not model.endswith("-" + thinking_level)):
        raise ValueError("AGY_MODEL_THINKING_LEVEL_MISMATCH")
    return model

def _interactive_windows_session() -> bool:
    """Kernel-sourced Windows session ID, never trust a caller assertion.

    Session 0 (including the GitHub NETWORK_SERVICE runner) is forbidden.
    The owner-only PowerShell launcher also checks WindowsIdentity SID.
    """
    if os.name != "nt":
        return False
    try:
        import ctypes
        from ctypes import wintypes
        session = wintypes.DWORD()
        ok = ctypes.windll.kernel32.ProcessIdToSessionId(
            os.getpid(), ctypes.byref(session))
        return bool(ok) and session.value > 0
    except Exception:
        return False


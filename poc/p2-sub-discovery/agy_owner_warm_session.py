"""Owner-local, bounded AGY stream-json session (V3.1 proof: 45988083997).

One existing CLI process, sequential turns. No daemon, provider fallback,
automatic retry, browser access or global configuration change.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import queue
import re
import subprocess
from threading import Thread
import time
from urllib.parse import urlsplit


class WarmSessionError(RuntimeError):
    """An incomplete or unverified turn must not be silently replayed."""


def warm_reason(error):
    if isinstance(error, WarmSessionError) and len(error.args) == 1:
        value = error.args[0]
        if isinstance(value, str) and re.fullmatch(r"(?:AGY_STREAM|G2)_[A-Z0-9_]{1,70}", value):
            return value
    return "G2_UNCLASSIFIED_" + (type(error).__name__.upper()
                                if type(error).__name__ in ("OSError", "TimeoutError", "JSONDecodeError", "BrokenPipeError", "ValueError") else "ERROR")


@dataclass(frozen=True)
class WarmTurn:
    response: dict
    conversation_id: str
    first_mcp_ms: int
    final_ms: int
    mcp_outcomes: int
    mcp_errors: int


def _page_argument(params):
    """AGY emits MCP args either as objects or JSON strings."""
    if not isinstance(params, dict):
        return None
    values = [params]
    for key in ("Arguments", "arguments", "ToolArguments", "toolArguments", "Args", "args", "Parameters", "parameters"):
        value = params.get(key)
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except ValueError:
                continue
        if isinstance(value, dict):
            values.append(value)
    for value in values:
        p = value.get("pageId")
        if type(p) is int and p >= 0:
            return p
    return None


def _source_page(output, host):
    """Native list_pages has optional label/title text before the URL."""
    if not isinstance(output, str):
        return None
    matches = []
    for line in output.splitlines():
        row = re.match(r"^\s*(\d+):\s*(.*)$", line)
        if not row:
            continue
        # Require exactly one HTTP(S) URL in the numbered row; a title
        # containing a second URL is ambiguous, not additional evidence.
        urls = re.findall(r"https?://[^\s\]\)<>\"']+", row[2], re.I)
        if len(urls) != 1:
            continue
        try:
            u = urlsplit(urls[0])
            if (u.scheme == "https" and u.hostname == host
                    and not u.username and not u.password and u.port in (None, 443)):
                matches.append(int(row[1]))
        except ValueError:
            continue
    return matches[0] if len(matches) == 1 else None


_DENIAL = re.compile(r"access denied|403 forbidden|verify (?:you are|that you are) human|"
                     r"making sure you.re not a bot|anti.bot challenge|just a moment|captcha", re.I)


# Only explicit, source-bound page evidence confirms an access denial.
# A weak keyword or an unbound tool outcome is inconclusive: HOLD, never
# continue through a possible challenge or silently replay the turn.
_DENIAL_PAGE_HEADER = re.compile(
    r"(?im)^\s*(?:title\s*[:=]\s*|(?:\d+\s+)?heading\s+)?[\"']?"
    r"(?:access denied|403 forbidden|verify (?:you are|that you are) human|"
    r"making sure you.re not a bot|just a moment)[.!…]?[\"']?\s*$"
)


def _denial_reason(output, *, source_bound=False):
    text = str(output)
    if not _DENIAL.search(text):
        return None
    if source_bound and isinstance(output, str) and _DENIAL_PAGE_HEADER.search(text):
        return "AGY_STREAM_ACCESS_BLOCKED"
    return "AGY_STREAM_ACCESS_UNCONFIRMED"


class OwnerAgyWarmSession:
    def __init__(self, *, ps, env, root, timeout=120, popen=subprocess.Popen):
        self.root = Path(root)
        self.timeout = timeout
        self._popen = popen
        self._ps = ps
        self._env = env
        self._queue = queue.Queue()
        self.process = None
        self.conversation_id = None
        self.clean_exit = False
        self.started = False
        self._failed = False

    def __enter__(self):
        cmd = ("& $env:TTV_AGY_CLI --model $env:TTV_AGY_MODEL --sandbox "
               "--settings $env:TTV_SESSION_SETTINGS --print= "
               "--input-format stream-json --output-format stream-json; exit $LASTEXITCODE")
        self._stderr = (self.root / "agy-stderr.txt").open("x", encoding="utf-8")
        try:
            self.process = self._popen(
                [self._ps, "-NoProfile", "-NonInteractive", "-Command", cmd],
                env=self._env, cwd=self.root, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=self._stderr, text=True,
                encoding="utf-8", errors="replace", bufsize=1)
        except BaseException:
            self._stderr.close()
            raise
        self.started = True
        Thread(target=self._read, daemon=True, name="ttv-agy-stream-reader").start()
        return self

    def _read(self):
        try:
            for line in self.process.stdout:
                self._queue.put((time.monotonic(), line))
        finally:
            self._queue.put((time.monotonic(), None))

    def turn(self, prompt, run, *, source_host=None):
        if self._failed or self.process is None or self.process.poll() is not None:
            raise WarmSessionError("AGY_STREAM_NOT_READY")
        run = Path(run)
        run.mkdir()
        sent = time.monotonic()
        first = None
        count = errors = 0
        pending = None
        observed = set()
        selected_page = None
        bound_read = False
        try:
            with (run / "agy-stdout.jsonl").open("x", encoding="utf-8") as raw, \
                 (run / "event-arrivals.jsonl").open("x", encoding="utf-8") as timing:
                message = {"event": "user", "message": {"content": [
                    {"type": "text", "text": prompt}]}}
                self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
                self.process.stdin.flush()
                total = 0
                while True:
                    left = self.timeout - (time.monotonic() - sent)
                    if left <= 0:
                        raise WarmSessionError("AGY_STREAM_TURN_TIMEOUT")
                    try:
                        at, line = self._queue.get(timeout=min(left, .25))
                    except queue.Empty:
                        if self.process.poll() is not None:
                            raise WarmSessionError("AGY_STREAM_EXITED_EARLY")
                        continue
                    if line is None:
                        raise WarmSessionError("AGY_STREAM_EOF")
                    total += len(line.encode("utf-8"))
                    if total > 16 * 1024 * 1024:
                        raise WarmSessionError("AGY_STREAM_OUTPUT_LIMIT")
                    raw.write(line)
                    raw.flush()
                    try:
                        e = json.loads(line)
                    except ValueError:
                        continue
                    if not isinstance(e, dict):
                        continue
                    ms = max(0, round((at - sent) * 1000))
                    timing.write(json.dumps({"elapsed_ms": ms, "event": e.get("event")}) + "\n")
                    timing.flush()
                    st = e.get("step_update")
                    if isinstance(st, dict) and st.get("tool_name") == "call_mcp_tool":
                        if first is None:
                            first = ms
                        info = st.get("tool_info")
                        if isinstance(info, dict):
                            params = info.get("parameters")
                            if isinstance(params, dict) and params.get("ToolName"):
                                pending = (params.get("ToolName"), next(
                                    (params[k] for k in ("ServerName", "Server", "serverName", "server")
                                     if isinstance(params.get(k), str)), None), _page_argument(params))
                            if "output" in info or info.get("error"):
                                count += 1
                                err = bool(info.get("error") or st.get("error"))
                                errors += int(err)
                                if pending and pending[1] == "ttv-browser":
                                    output = info.get("output", "")
                                    if source_host is not None:
                                        reason = _denial_reason(
                                            output,
                                            source_bound=(not err and selected_page is not None
                                                          and pending[0] in ("evaluate_script", "take_snapshot")
                                                          and pending[2] == selected_page))
                                        if reason is not None:
                                            raise WarmSessionError(reason)
                                    if not err:
                                        observed.add(pending[0])
                                        if source_host is not None:
                                            if pending[0] == "list_pages":
                                                selected_page = _source_page(output, source_host)
                                            elif pending[0] in ("evaluate_script", "take_snapshot"):
                                                if selected_page is not None and pending[2] == selected_page:
                                                    bound_read = True
                                pending = None
                    r = e.get("result")
                    if e.get("event") != "result" or not isinstance(r, dict):
                        continue
                    sid = r.get("conversation_id")
                    if not isinstance(sid, str) or not sid:
                        raise WarmSessionError("AGY_STREAM_CONVERSATION_MISSING")
                    if self.conversation_id is not None and sid != self.conversation_id:
                        raise WarmSessionError("AGY_STREAM_CONVERSATION_CHANGED")
                    self.conversation_id = sid
                    response = r.get("response")
                    if not isinstance(response, str):
                        raise WarmSessionError("AGY_STREAM_RESULT_INVALID")
                    response = response.strip()
                    fence = re.fullmatch(r"\x60{3}(?:json)?\s*(.*?)\s*\x60{3}", response, re.S)
                    payload = json.loads(fence[1] if fence else response)
                    if not isinstance(payload, dict):
                        raise WarmSessionError("AGY_STREAM_RESULT_INVALID")
                    if first is None or not observed.intersection({"evaluate_script", "take_snapshot"}):
                        raise WarmSessionError("AGY_STREAM_FRESH_BROWSER_READ_MISSING")
                    if source_host is not None and not bound_read:
                        raise WarmSessionError("AGY_STREAM_SOURCE_PAGE_UNBOUND")
                    return WarmTurn(payload, sid, first, ms, count, errors)
        except BaseException as exc:
            self._failed = True
            if isinstance(exc, Exception):
                try:
                    with (run / "turn-terminal.json").open("x", encoding="utf-8") as f:
                        json.dump({"reason": warm_reason(exc),
                                   "elapsed_ms": round((time.monotonic() - sent) * 1000),
                                   "timeout_ms": round(self.timeout * 1000),
                                   "mcp_outcomes": count, "mcp_errors": errors}, f)
                        f.flush()
                        os.fsync(f.fileno())
                except OSError:
                    pass
            raise

    def __exit__(self, exc_type, exc, tb):
        p = self.process
        try:
            if p is None:
                return False
            try:
                p.stdin.close()
            except (OSError, ValueError):
                pass
            try:
                self.clean_exit = p.wait(timeout=10) == 0
            except subprocess.TimeoutExpired:
                # Only the PID created by this object, never unrelated Chrome/AGY.
                subprocess.run(["taskkill.exe", "/PID", str(p.pid), "/T", "/F"],
                               capture_output=True, timeout=10, check=False)
                p.wait(timeout=10)
            if not self.clean_exit and exc_type is None:
                raise WarmSessionError("AGY_STREAM_EXIT_UNVERIFIED")
        finally:
            self._stderr.close()
        return False

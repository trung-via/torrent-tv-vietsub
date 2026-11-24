# Install exact two-module SRT parser fix; preserve private SRT and all checkpoints.
# Owner-interactive only. No provider, TorrServer API call, cache deletion, or TV action.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app\poc\p2-sub-discovery'
$p2App = Join-Path $root 'app\poc\p2-aisub'
$stage = Join-Path $root ('staged-releases\srt-parser-f364c42-' + [Guid]::NewGuid().ToString('N'))
$p2 = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$cache = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\subtitle-trials'
$healthPath = Join-Path $root 'agent-health.json'
$backupRoot = Join-Path $root 'backups'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$baseline = [ordered]@{
    'cue_pipeline.py' = '96a569bcc5630f86db7e84a4c9df98442f946d7d3265d8ec2bab7d692365176a'
    'brain_english_inbox.py' = 'dab7cfe87bb134c6ee939b62e0ee2f14ca7cee1c3744317c52c12eef3dc1cf07'
}
$expected = [ordered]@{
    'cue_pipeline.py' = 'caa28afbdfacf9acf2b6298fe295fc2802999a736cfceb856814e3c4b01c726f'
    'brain_english_inbox.py' = 'dfa3f8cb7229885def3d88ab453dc4a7e1e90a474ff9b6c6f37b4ca5eb650ade'
}
$p2Names = @('cue_pipeline.py')
function StageFile([string]$name) {
    if ($name -in $p2Names) {
        return (Join-Path $stage ('poc\p2-aisub\' + $name))
    }
    return (Join-Path $stage ('poc\p2-sub-discovery\' + $name))
}
function InstalledFile([string]$name) {
    if ($name -in $p2Names) { return (Join-Path $p2App $name) }
    return (Join-Path $app $name)
}
function Hold([string]$reason) {
    try {
        $spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
        $rq = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
        if ($rq.nonce -cmatch '^[0-9a-f]{32}$' -and $reason -cmatch '^[A-Z0-9_]{3,80}$') {
            $diag = @{schema='TTV-SRT-INSTALL-HOLD-V1';nonce=$rq.nonce;reason=$reason}
            [IO.File]::WriteAllText((Join-Path $spool ('Receipts\srt-parser-hold-' + $rq.nonce + '.json')),($diag|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        }
    } catch {}

    Write-Output ('OWNER_BRAIN_R3=HOLD_' + $reason)
    throw 'OWNER_BRAIN_R3_INSTALL_HOLD'
}
function Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function RegularDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_INVALID'
    }
}
function RegularFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_INVALID'
    }
}
function CheckTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $taskSid = [string]$task.Principal.UserId
    if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($taskSid -cne $ownerSid -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function Workers {
    return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function NoOpenWork {
    $inbox = Join-Path $root 'inbox'
    RegularDirectory $inbox
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'PENDING_OWNER_EVENTS'
    }
    if (Test-Path -LiteralPath $p2) {
        RegularDirectory $p2
        foreach ($pattern in @('batch-*.inflight','active.lock')) {
            if (@(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter $pattern).Count -gt 0) {
                Hold 'P2_INFLIGHT_OR_ACTIVE_LOCK'
            }
        }
    }
}
function VerifiedHeartbeat([long]$rejectPid, [long]$freshSince) {
    if (-not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { return $false }
    try {
        RegularFile $healthPath
        if ((Get-Item -LiteralPath $healthPath).Length -gt 512) { return $false }
        $h = Get-Content -LiteralPath $healthPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
            $h.state -cne 'READY' -or $h.pid -isnot [ValueType] -or
            [long]$h.pid -le 0 -or [long]$h.pid -eq $rejectPid -or
            [long]$h.observed_utc_epoch -lt $freshSince) { return $false }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$h.observed_utc_epoch
        if ($age -lt 0 -or $age -gt 20) { return $false }
        $worker = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$h.pid)
        if (-not $worker -or
            [string]$worker.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
            return $false
        }
        $sid = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        return ($sid.ReturnValue -eq 0 -and $sid.Sid -ceq $ownerSid)
    } catch { return $false }
}
function StopOwner {
    NoOpenWork
    $task = CheckTask
    if ([string]$task.State -in @('Running','Ready')) {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    } elseif ([string]$task.State -cne 'Disabled') { Hold 'OWNER_TASK_STATE_UNKNOWN' }
    for ($n = 0; $n -lt 5; $n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    # Exactly scoped Owner-owned residual processes: never terminate other Python.
    $workers = @(Workers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_SET_UNEXPECTED' }
    $allowed = @((Join-Path $app 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'owner_session_bridge.py'))
    foreach ($w in $workers) {
        $hits = @($allowed | Where-Object {
            [string]$w.CommandLine -and
            $w.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $sid = Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid
        if ($hits.Count -ne 1 -or -not $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($w in $workers) {
        NoOpenWork
        if ([string](CheckTask).State -cne 'Disabled') { Hold 'RESIDUAL_TASK_REENABLED' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$w.ProcessId)
        if ($null -eq $live) { continue }
        $sid = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ([string]$live.CommandLine -cne [string]$w.CommandLine -or
            $live.CreationDate -ne $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_CHANGED'
        }
        Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
    }
    for ($n = 0; $n -lt 10; $n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'RESIDUAL_NOT_STOPPED'
}
function StartOwner([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 1
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($n = 0; $n -lt 30; $n++) {
        Start-Sleep -Seconds 1
        if ([string](CheckTask).State -cne 'Running') { continue }
        if (VerifiedHeartbeat $oldPid $since) { return $true }
    }
    return $false
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
foreach ($dir in @($root,$app,$p2App)) { RegularDirectory $dir }
$taskState = [string](CheckTask).State
if ($taskState -notin @('Running','Ready')) { Hold 'OWNER_TASK_NOT_RUNNING_OR_READY' }
NoOpenWork
$oldPid = 0L
if ($taskState -ceq 'Running') {
    if (-not (VerifiedHeartbeat -1 0)) { Hold 'OWNER_HEARTBEAT_NOT_VERIFIED' }
    $oldPid = [long](Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json).pid
} else {
    # Ready can coexist with orphaned Python children. Validate their exact
    # Owner SID, app script path and creation identity before touching the task.
    $residual = @(Workers)
    if ($residual.Count -gt 4) { Hold 'RESIDUAL_WORKER_SET_UNEXPECTED' }
    $allowed = @((Join-Path $app 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'owner_session_bridge.py'))
    foreach ($w in $residual) {
        $hits = @($allowed | Where-Object {
            [string]$w.CommandLine -and
            $w.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $sid = Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid
        if ($hits.Count -ne 1 -or -not $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_IDENTITY_UNVERIFIED'
        }
    }
    if ($residual.Count -gt 0) {
        Write-Output 'OWNER_BRAIN_R3_READY_RESIDUAL=VERIFIED_CLEANUP_PLANNED'
    }
    # The existing StopOwner transaction rechecks idle state, disables the
    # task and revalidates each PID before stopping only these app workers.
}
# Raw Windows SHA may differ solely because of line endings. Compare the
# actual parser against the exact reviewed baseline, allowing only AST equivalence.
# Preserve all actual original bytes for rollback.
foreach ($name in $baseline.Keys) {
    $file = InstalledFile $name
    RegularFile $file
    $actual = Hash $file
    if ($actual -ceq $baseline[$name] -or $actual -ceq $expected[$name]) { continue }
    if ($name -cne 'cue_pipeline.py') { Hold 'INSTALLED_R3_BASELINE_DRIFT' }
    $baselineProbe = @'
import ast, hashlib, pathlib, sys
p=pathlib.Path(sys.argv[1])
raw=p.read_bytes()
baseline="\"\"\"P2-AISUB.1: local-only timed SRT/VTT cue QA and translated-text import.\n\nNo model/provider call, ASR, network, background processing or APK/TV effects.\nA separate opt-in translator must create the cue-indexed JSON. This module\nvalidates and imports only, preserving exact source timestamps and ordering.\n\"\"\"\nfrom __future__ import annotations\nimport argparse\nfrom dataclasses import dataclass, replace\nimport json\nfrom pathlib import Path\nimport re\n\nMAX_CUES = 2000\nMAX_BYTES = 1_000_000\nSRT_TIME = re.compile(r\"^(\\d{2}):(\\d{2}):(\\d{2}),(\\d{3})$\")\nVTT_TIME = re.compile(r\"^(?:(\\d{2}):)?(\\d{2}):(\\d{2})\\.(\\d{3})$\")\nARROW = re.compile(r\"^(\\S+) --> (\\S+)(.*)$\")\n\n\n@dataclass(frozen=True)\nclass Cue:\n    number: int\n    start_ms: int\n    end_ms: int\n    text: str\n    identifier: str = \"\"\n    settings: str = \"\"\n\n\ndef _decode(data: bytes) -> str:\n    if len(data) > MAX_BYTES:\n        raise ValueError(\"INPUT_TOO_LARGE\")\n    try:\n        s = data.decode(\"utf-8-sig\")\n    except UnicodeDecodeError as e:\n        raise ValueError(\"UTF8_REQUIRED\") from e\n    if \"\\x00\" in s:\n        raise ValueError(\"BINARY_INPUT_NOT_ALLOWED\")\n    return s.replace(\"\\r\\n\", \"\\n\").replace(\"\\r\", \"\\n\")\n\n\ndef _time_ms(s: str, fmt: str) -> int:\n    m = (SRT_TIME if fmt == \"srt\" else VTT_TIME).fullmatch(s)\n    if not m:\n        raise ValueError(\"MALFORMED_TIMESTAMP\")\n    parts = m.groups()\n    if fmt == \"srt\":\n        h, minute, sec, ms = (int(v) for v in parts)\n    else:\n        h = int(parts[0] or 0)\n        minute, sec, ms = (int(x) for x in parts[1:])\n    if minute > 59 or sec > 59:\n        raise ValueError(\"INVALID_TIME_RANGE\")\n    return ((h * 60 + minute) * 60 + sec) * 1000 + ms\n\n\ndef _time_text(ms: int, fmt: str) -> str:\n    hours, rem = divmod(ms, 3600000)\n    minutes, rem = divmod(rem, 60000)\n    seconds, millis = divmod(rem, 1000)\n    if hours > 99:\n        raise ValueError(\"HOURS_OUT_OF_RANGE\")\n    separator = \",\" if fmt == \"srt\" else \".\"\n    return f\"{hours:02d}:{minutes:02d}:{seconds:02d}{separator}{millis:03d}\"\n\n\ndef parse_cues(data: bytes, fmt: str) -> tuple[Cue, ...]:\n    if fmt not in (\"srt\", \"vtt\"):\n        raise ValueError(\"UNSUPPORTED_FORMAT\")\n    s = _decode(data).strip(\"\\n\")\n    blocks = re.split(r\"\\n[ \\t]*\\n+\", s)\n    if fmt == \"vtt\":\n        if not blocks or not re.fullmatch(r\"WEBVTT[^\\n]*\", blocks[0]):\n            raise ValueError(\"VTT_HEADER_REQUIRED\")\n        blocks = blocks[1:]\n    if not blocks or not blocks[0] or len(blocks) > MAX_CUES:\n        raise ValueError(\"NO_CUES_OR_TOO_MANY\")\n    cues: list[Cue] = []\n    prev_start = -1\n    for i, block in enumerate(blocks, 1):\n        lines = block.split(\"\\n\")\n        identifier = \"\"\n        if fmt == \"srt\":\n            if len(lines) < 3 or lines[0] != str(i):\n                raise ValueError(\"SRT_SEQUENCE_REQUIRED\")\n            timing, content = lines[1], lines[2:]\n        else:\n            if lines[0].startswith((\"NOTE\", \"STYLE\", \"REGION\")):\n                raise ValueError(\"VTT_UNSUPPORTED_BLOCK\")\n            if \" --> \" in lines[0]:\n                timing, content = lines[0], lines[1:]\n            else:\n                if len(lines) < 3 or not lines[0].strip():\n                    raise ValueError(\"VTT_IDENTIFIER_OR_CUE_INVALID\")\n                identifier, timing, content = lines[0], lines[1], lines[2:]\n        if not content or not all(t.strip() for t in content):\n            raise ValueError(\"EMPTY_CUE_TEXT\")\n        m = ARROW.fullmatch(timing)\n        if not m:\n            raise ValueError(\"TIMING_ARROW_REQUIRED\")\n        start, end = _time_ms(m[1], fmt), _time_ms(m[2], fmt)\n        settings = m[3]\n        if fmt == \"srt\" and settings:\n            raise ValueError(\"SRT_SETTINGS_INVALID\")\n        if end <= start or start < prev_start:\n            raise ValueError(\"INVALID_CUE_DURATION_OR_ORDER\")\n        prev_start = start\n        cues.append(Cue(i, start, end, \"\\n\".join(content), identifier, settings))\n    return tuple(cues)\n\n\ndef apply_translations(cues: tuple[Cue, ...], translations: dict[str, str]) -> tuple[Cue, ...]:\n    if not isinstance(translations, dict):\n        raise ValueError(\"TRANSLATION_MAP_REQUIRED\")\n    wanted = {str(c.number) for c in cues}\n    if set(translations) != wanted:\n        raise ValueError(\"MISSING_OR_EXTRA_TRANSLATED_CUE\")\n    out: list[Cue] = []\n    for c in cues:\n        text = translations[str(c.number)]\n        if (not isinstance(text, str) or not text.strip()\n            or len(text) > 2000 or any(ch in text for ch in (\"\\x00\", \"<\", \">\"))\n            or \"\\r\" in text):\n            raise ValueError(\"PLAIN_UTF8_TRANSLATION_REQUIRED\")\n        out.append(replace(c, text=text.strip()))\n    return tuple(out)\n\n\ndef render(cues: tuple[Cue, ...], fmt: str) -> bytes:\n    if fmt not in (\"srt\", \"vtt\"):\n        raise ValueError(\"UNSUPPORTED_FORMAT\")\n    sections = []\n    for c in cues:\n        line = f\"{_time_text(c.start_ms, fmt)} --> {_time_text(c.end_ms, fmt)}\"\n        if fmt == \"vtt\":\n            line += c.settings\n            if c.identifier:\n                line = c.identifier + \"\\n\" + line\n        else:\n            line = str(c.number) + \"\\n\" + line\n        sections.append(line + \"\\n\" + c.text)\n    header = \"WEBVTT\\n\\n\" if fmt == \"vtt\" else \"\"\n    return (header + \"\\n\\n\".join(sections) + \"\\n\").encode(\"utf-8\")\n\n\ndef main() -> int:\n    p = argparse.ArgumentParser(description=\"Offline cue translation import; no AI calls\")\n    p.add_argument(\"--input\", type=Path, required=True)\n    p.add_argument(\"--translations\", type=Path, required=True)\n    p.add_argument(\"--output\", type=Path, required=True)\n    p.add_argument(\"--confirm\", required=True)\n    args = p.parse_args()\n    if args.confirm != \"LOCAL_OFFLINE_ONE_FILE\":\n        p.error(\"EXPLICIT_ONE_FILE_CONSENT_REQUIRED\")\n    if args.input.suffix.lower() not in (\".srt\", \".vtt\") or args.output.suffix.lower() != args.input.suffix.lower():\n        p.error(\"SAME_SRT_OR_VTT_FORMAT_REQUIRED\")\n    paths = [x.resolve() for x in (args.input, args.translations, args.output)]\n    if len(set(paths)) != 3 or args.output.exists():\n        p.error(\"OUTPUT_MUST_BE_NEW_AND_DISTINCT\")\n    fmt = args.input.suffix.lower()[1:]\n    cues = parse_cues(args.input.read_bytes(), fmt)\n    translations = json.loads(_decode(args.translations.read_bytes()))\n    data = render(apply_translations(cues, translations), fmt)\n    with args.output.open(\"xb\") as f:\n        f.write(data)\n    print(f\"LOCAL_CUE_QA_PASS format={fmt} cues={len(cues)} no_cloud_or_tv_effect\")\n    return 0\n\n\nif __name__ == \"__main__\":\n    raise SystemExit(main())\n"
expected='96a569bcc5630f86db7e84a4c9df98442f946d7d3265d8ec2bab7d692365176a'
assert hashlib.sha256(baseline.encode('utf-8')).hexdigest()==expected
actual=raw.decode('utf-8-sig').replace('\r\n','\n')
if actual==baseline:
    print('CANONICAL_BASELINE_MATCH')
elif ast.dump(ast.parse(actual),include_attributes=False)==ast.dump(ast.parse(baseline),include_attributes=False):
    print('AST_BASELINE_MATCH')
else:
    print('BASELINE_SEMANTIC_DRIFT')
'@
    $comparison=@(& py -3 -I -B -c $baselineProbe $file 2>&1)
    if ($LASTEXITCODE -ne 0 -or $comparison.Count -ne 1 -or [string]$comparison[0] -cnotin @('CANONICAL_BASELINE_MATCH','AST_BASELINE_MATCH')) {
        Hold 'PARSER_BASELINE_SEMANTIC_DRIFT'
    }
    Write-Output ('OWNER_SRT_BASELINE=' + [string]$comparison[0])
}
$stageParent = Split-Path -Parent $stage
RegularDirectory $stageParent
[IO.Directory]::CreateDirectory((Join-Path $stage 'poc\p2-sub-discovery')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $stage 'poc\p2-aisub')) | Out-Null
RegularDirectory $stage
# Source-only transfer, pinned to the exact successful CI candidate.
foreach ($name in $expected.Keys) {
    $subdir = if ($name -in $p2Names) { 'p2-aisub' } else { 'p2-sub-discovery' }
    $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/f364c424f51cf1c8fe282cc7cac3812aab0f1d82/poc/' + $subdir + '/' + $name
    $target = StageFile $name
    Invoke-WebRequest -Uri $uri -OutFile $target -TimeoutSec 30 -ErrorAction Stop
    RegularFile $target
    if ((Hash $target) -cne $expected[$name]) { Hold 'PINNED_DOWNLOAD_HASH_DRIFT' }
}
Write-Output 'OWNER_BRAIN_SOURCE_NEUTRAL_STAGE=2_FILES_VERIFIED'

# Entrypoint is intentionally NOT part of the 16-file patch; the exact
# installed version is already the reviewed candidate and must stay so.
$entry = Join-Path $app 'owner_p3_p4_entrypoint.py'
RegularFile $entry
if ((Hash $entry) -cne 'acaa545be25d397b4ab85276516e92fdc99316f58063f69fcd620b8af0198c2c') {
    Hold 'INSTALLED_ENTRYPOINT_SHA_DRIFT'
}
foreach ($name in $expected.Keys) {
    $src = StageFile $name
    RegularFile $src
    if ((Hash $src) -cne $expected[$name]) { Hold 'STAGED_SOURCE_SHA_DRIFT' }
}
# Fail before touching the running Owner if staged modules cannot import
# against existing Owner dependencies. This is a smoke, not real provider/TV.
$overlay = @'
import importlib, pathlib, sys, json, hashlib
stage, app, cache = (pathlib.Path(p) for p in sys.argv[1:4])
sys.path[:0] = [str(stage / "poc/p2-sub-discovery"), str(stage / "poc/p2-aisub"),
                str(app / "poc/p2-sub-discovery"), str(app / "poc/p2-aisub"),
                str(app / "poc/p3-vietsub-trigger")]
for name in ("brain_english_inbox", "cue_pipeline", "owner_p3_p4_entrypoint"):
    module = importlib.import_module(name)
    expected_root = app if name == "owner_p3_p4_entrypoint" else stage
    assert pathlib.Path(module.__file__).resolve().is_relative_to(expected_root.resolve()), name
from cue_pipeline import parse_cues, render
from brain_english_inbox import _content
rows=[]
for receipt in (cache/".brain-en-inbox").glob("*/receipt.json"):
    if receipt.is_symlink() or receipt.stat().st_size>4096: continue
    record=json.loads(receipt.read_text("utf-8"))
    if record.get("source_page")!="https://www.opensubtitles.org/en/subtitles/14097898/spider-man-brand-new-day-en": continue
    payload=(receipt.parent/"english.srt").read_bytes()
    assert (hashlib.sha256(payload).hexdigest(),len(payload))==(record["sha256"],134873)
    cues=parse_cues(payload,"srt")
    assert len(cues)==record["cues"]==1856
    assert _content(payload)==(record["sha256"],1856)
    assert parse_cues(render(cues,"srt"),"srt")==cues
    rows.append(receipt)
assert len(rows)==1
print("OWNER_BRAIN_R3_STAGED_OVERLAY=PASS")
'@
$import = @(& py -3 -I -B -c $overlay $stage (Join-Path $root 'app') $cache $p2 2>&1)
if ($LASTEXITCODE -ne 0 -or
    @($import | Where-Object { [string]$_ -ceq 'OWNER_BRAIN_R3_STAGED_OVERLAY=PASS' }).Count -ne 1) {
    Hold 'STAGED_OVERLAY_IMPORT_FAILED_OWNER_UNCHANGED'
}
Write-Output 'OWNER_BRAIN_R3_PREFLIGHT=PASS_OWNER_IDLE_STAGED_IMPORT'

if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
}
RegularDirectory $backupRoot
$backup = Join-Path $backupRoot ('owner-srt-parser-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($backup) | Out-Null
$previous = [ordered]@{}
foreach ($name in $expected.Keys) {
    $file = InstalledFile $name
    if (Test-Path -LiteralPath $file) {
        RegularFile $file
        $previous[$name] = Hash $file
        $saved = Join-Path $backup $name
        [IO.File]::Copy($file,$saved,$false)
        if ((Hash $saved) -cne $previous[$name]) { Hold 'BACKUP_HASH_INVALID' }
    } else { $previous[$name] = 'MISSING' }
}
$ledger = [ordered]@{
    schema = 'TTV-OWNER-BRAIN-R3-BACKUP-V1'
    candidate_sha = 'f364c424f51cf1c8fe282cc7cac3812aab0f1d82'
    stage_sha = 'f364c424f51cf1c8fe282cc7cac3812aab0f1d82'
    previous = $previous
    target = $expected
}
[IO.File]::WriteAllText((Join-Path $backup 'ledger.json'),
    ($ledger | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output 'OWNER_BRAIN_R3_BACKUP=2_ORIGINALS_RECORDED'
$stopped = $false
try {
    NoOpenWork
    StopOwner
    $stopped = $true
    NoOpenWork
    foreach ($name in $expected.Keys) {
        if ([string](CheckTask).State -cne 'Disabled' -or @(Workers).Count -ne 0) {
            Hold 'OWNER_NOT_STOPPED_DURING_APPLY'
        }
        $src = StageFile $name
        $file = InstalledFile $name
        if ((Hash $src) -cne $expected[$name]) { Hold 'SOURCE_CHANGED_DURING_APPLY' }
        if ($previous[$name] -ceq 'MISSING') {
            if (Test-Path -LiteralPath $file) { Hold 'NEW_MODULE_PATH_CONFLICT' }
        } elseif ((Hash $file) -cne $previous[$name]) {
            Hold 'INSTALLED_BASELINE_CHANGED'
        }
        if ($previous[$name] -ceq $expected[$name]) { continue }
        $temp = Join-Path (Split-Path -Parent $file) ('.brain-r3-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy($src,$temp,$false)
        if ((Hash $temp) -cne $expected[$name]) { Hold 'TEMP_COPY_DRIFT' }
        if ($previous[$name] -ceq 'MISSING') {
            [IO.File]::Move($temp,$file)
        } else {
            $displaced = Join-Path $backup ('displaced-' + $name)
            [IO.File]::Replace($temp,$file,$displaced)
        }
        if ((Hash $file) -cne $expected[$name]) { Hold 'POST_REPLACE_HASH_CHANGED' }
    }
    Push-Location -LiteralPath $app
    try {
        $installedCheck = 'import sys;sys.path[:0]=sys.argv[1:];import owner_p3_p4_entrypoint,brain_english_inbox,cue_pipeline;print("OWNER_BRAIN_R3_IMPORT_PASS")'
        $verify = @(& py -3 -I -B -c $installedCheck $app $p2App (Join-Path $root 'app\poc\p3-vietsub-trigger') 2>&1)
        if ($LASTEXITCODE -ne 0 -or
            @($verify | Where-Object { [string]$_ -ceq 'OWNER_BRAIN_R3_IMPORT_PASS' }).Count -ne 1) {
            Hold 'OFFLINE_IMPORT_FAILED'
        }
    } finally { Pop-Location }
    NoOpenWork
    if (-not (StartOwner $oldPid)) { Hold 'FRESH_OWNER_NOT_VERIFIED' }
    foreach ($name in $expected.Keys) {
        if ((Hash (InstalledFile $name)) -cne $expected[$name]) { Hold 'POST_START_HASH_DRIFT' }
    }
    $spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
    $request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
    if ($request.nonce -cnotmatch '^[0-9a-f]{32}$') { Hold 'RECEIPT_NONCE_INVALID' }
    $record = @{schema='TTV-SRT-PARSER-INSTALL-V1';nonce=$request.nonce;status='INSTALLED';modules=2;owner='READY_FRESH';source='UNCHANGED'}
    $dest = Join-Path $spool ('Receipts\srt-parser-' + $request.nonce + '.json')
    [IO.File]::WriteAllText($dest,($record | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    Write-Output 'OWNER_SRT_PARSER_INSTALL=2_FILES_HASH_VERIFIED_FRESH_OWNER_RUNNING'
    Write-Output 'OWNER_BRAIN_R3_PROVIDER_TV=NOT_RUN'
    Write-Output 'OWNER_BRAIN_R3_CACHE_CHECKPOINTS=UNCHANGED'
} catch {
    $failure = $_
    Write-Output 'OWNER_BRAIN_R3_RECOVERY=ATTEMPTING_PRIVATE_ROLLBACK'
    if (-not $stopped) {
        # No source files were changed. Restore availability only if the
        # previous owner worker has exited and the queue remains untouched.
        if (@(Workers).Count -eq 0 -and
            [string](CheckTask).State -ceq 'Disabled') {
            NoOpenWork
            if (StartOwner $oldPid) {
                Write-Output 'OWNER_BRAIN_R3_RECOVERY=NO_FILES_CHANGED_OLD_OWNER_RUNNING'
            }
        }
        throw
    }
    StopOwner
    foreach ($name in $expected.Keys) {
        $file = InstalledFile $name
        $old = [string]$previous[$name]
        $new = [string]$expected[$name]
        if ($old -ceq $new) { continue }
        if ($old -ceq 'MISSING') {
            if (Test-Path -LiteralPath $file) {
                if ((Hash $file) -cne $new) { Hold 'ROLLBACK_NEW_FILE_DRIFT' }
                [IO.File]::Delete($file)
            }
        } else {
            $saved = Join-Path $backup $name
            if ((Hash $saved) -cne $old) { Hold 'ROLLBACK_BACKUP_DRIFT' }
            if ((Hash $file) -cne $old) {
                if ((Hash $file) -cne $new) { Hold 'ROLLBACK_INSTALLED_DRIFT' }
                $temp = Join-Path (Split-Path -Parent $file) ('.brain-rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Copy($saved,$temp,$false)
                $displaced = Join-Path $backup ('failed-' + $name)
                [IO.File]::Replace($temp,$file,$displaced)
            }
            if ((Hash $file) -cne $old) { Hold 'ROLLBACK_ORIGINAL_HASH_CHANGED' }
        }
    }
    if (-not (StartOwner $oldPid)) { Hold 'ROLLBACK_OWNER_HEARTBEAT_FAILED_TASK_HOLD' }
    Write-Output 'OWNER_BRAIN_R3_RECOVERY=ORIGINAL_OWNER_RESTORED'
    throw 'OWNER_BRAIN_R3_INSTALL_FAILED_ROLLED_BACK'
}

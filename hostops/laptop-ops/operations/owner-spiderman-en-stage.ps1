# Read-only actual staged EN parser regression; no download, translation or mutation.
# No translation, cache deletion, torrent add, TV event, or playback change.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$cache = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\subtitle-trials'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'STAGE_REQUEST_INVALID' }
$code = @'
import json, pathlib, re, sys, hashlib, tempfile, io, zipfile
from html.parser import HTMLParser
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.parse import urljoin, urlsplit, unquote
from urllib.error import HTTPError, URLError
root, cache = map(pathlib.Path, sys.argv[1:3])
app = root / 'app'
sys.path[:0] = [str(app / 'poc/p2-sub-discovery'), str(app / 'poc/p2-aisub'), str(app / 'poc/p3-vietsub-trigger')]
from matcher import Media
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader, _local_post
from owner_selected_file_resolver import _fingerprint
from brain_english_inbox import stage_brain_english, acquire_brain_english, BrainEnglishUnavailable
from agy_opensubtitles_acquisition import _validate_source, AgyEnglishUnavailable
from opensubtitles import validate_timed_text
out = dict(schema='TTV-OWNER-EN-STAGE-V1', status='NOT_RUN', media='UNVERIFIED', cues=0, bytes=0, reason='NONE')
def finish(status, reason='NONE'):
    out.update(status=status, reason=reason)
    print(json.dumps(out, separators=(',', ':')))
    sys.exit(0)
def target(value):
    return 'spidermanbrandnewday' in re.sub(r'[^a-z0-9]', '', str(value).casefold())
def files(t):
    f = t.get('file_stats')
    if not f:
        try: f = json.loads(t.get('data','{}'))['TorrServer']['Files']
        except (ValueError, TypeError, KeyError): f = []
    return f if isinstance(f, list) and len(f)<=4096 else []
try:
    for name,expected in {'agy_opensubtitles_acquisition.py':'6ce182d5e9bd5de4b31827203cd967c752d97aea18bdce8a7630b8ed20950c84','brain_english_inbox.py':'dab7cfe87bb134c6ee939b62e0ee2f14ca7cee1c3744317c52c12eef3dc1cf07'}.items():
        if hashlib.sha256((app/'poc/p2-sub-discovery'/name).read_bytes()).hexdigest()!=expected:
            finish('HOLD','INSTALLED_SOURCE_DRIFT')
    policy=json.loads((root/'p3-p4-policy.json').read_text('utf-8'))
    if policy.get('enabled') is not True: finish('HOLD','OWNER_POLICY_DISABLED')
    config=OwnerLocalTorrServer(policy['profile_id'],policy['torrserver_port'])
    raw=_local_post(config.url,b'{"action":"list"}',6.0)
    listing=json.loads(raw.decode('utf-8'))
    if not isinstance(listing,list) or len(listing)>256: finish('HOLD','LIST_INVALID')
    candidates={}
    for t in listing:
        if not isinstance(t,dict): continue
        tor=t.get('hash')
        if not isinstance(tor,str) or not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}',tor): continue
        title=t.get('title','')
        for f in files(t):
            if not isinstance(f,dict): continue
            n=str(f.get('path','')).replace('\\','/').rsplit('/',1)[-1]
            idx=f.get('id')
            if type(idx) is not int or not 0<=idx<4096 or not re.search(r'\.(mkv|mp4|avi|mov|ts|m2ts)$',n,re.I): continue
            if not (target(n) or target(title)) or '2026' not in str(title)+' '+n: continue
            if type(f.get('length')) is not int or f['length']<100_000_000: continue
            candidates[(tor,idx)]=n
    if len(candidates)!=1:
        # Only a previously attested exact film selection may disambiguate.
        history=sorted((p for p in (root/'inbox').glob('event-*') if p.is_file() and not p.is_symlink() and p.stat().st_size<=4096),key=lambda p:p.stat().st_mtime,reverse=True)[:128]
        pinned=[]
        for p in history:
            try: ev=json.loads(p.read_text('utf-8'))
            except (ValueError,OSError): continue
            for (tor,idx),name in candidates.items():
                if ev.get('selected_video_filename')==name and ev.get('source_fingerprint')==_fingerprint(config.profile_id,tor,idx):
                    pinned.append((tor,idx))
            if pinned: break
        if len(set(pinned))!=1: finish('HOLD','EXACT_MEDIA_NOT_UNIQUE')
        candidates={pinned[0]:candidates[pinned[0]]}
    (tor,idx), name = next(iter(candidates.items()))
    actual=OwnerTorrServerReader(config)(config.profile_id,tor,idx)
    if actual.path.replace('\\','/').rsplit('/',1)[-1]!=name or not (target(name) or target(actual.torrent_title)):
        finish('HOLD','MEDIA_CHANGED')
    media=Media(config.profile_id,tor,idx,name,torrent_title=actual.torrent_title)
    out['media']='EXACT_METADATA'
    fp=_fingerprint(*media.key)
    # Read-only real-file regression. Load the exact patched module in memory.
    import types
    from cue_pipeline import parse_cues as installed_parse
    asset=acquire_brain_english(media,cache)
    out.update(cues=asset.cues,bytes=len(asset.contents))
    try:
        installed_parse(asset.contents,'srt')
    except ValueError as exc:
        if str(exc)!='SRT_SEQUENCE_REQUIRED': finish('HOLD','BASELINE_OTHER_PARSER_ERROR')
    else:
        finish('HOLD','BASELINE_NO_LONGER_REPRODUCES')
    module=types.ModuleType('_candidate_cue_pipeline')
    sys.modules[module.__name__]=module
    exec(compile("\"\"\"P2-AISUB.1: local-only timed SRT/VTT cue QA and translated-text import.\n\nNo model/provider call, ASR, network, background processing or APK/TV effects.\nA separate opt-in translator must create the cue-indexed JSON. This module\nvalidates and imports only, preserving exact source timestamps and ordering.\n\"\"\"\nfrom __future__ import annotations\nimport argparse\nfrom dataclasses import dataclass, replace\nimport json\nfrom pathlib import Path\nimport re\n\nMAX_CUES = 2000\nMAX_BYTES = 1_000_000\nSRT_TIME = re.compile(r\"^(\\d{2}):(\\d{2}):(\\d{2}),(\\d{3})$\")\nVTT_TIME = re.compile(r\"^(?:(\\d{2}):)?(\\d{2}):(\\d{2})\\.(\\d{3})$\")\nARROW = re.compile(r\"^(\\S+) --> (\\S+)(.*)$\")\n\n\n@dataclass(frozen=True)\nclass Cue:\n    number: int\n    start_ms: int\n    end_ms: int\n    text: str\n    identifier: str = \"\"\n    settings: str = \"\"\n\n\ndef _decode(data: bytes) -> str:\n    if len(data) > MAX_BYTES:\n        raise ValueError(\"INPUT_TOO_LARGE\")\n    try:\n        s = data.decode(\"utf-8-sig\")\n    except UnicodeDecodeError as e:\n        raise ValueError(\"UTF8_REQUIRED\") from e\n    if \"\\x00\" in s:\n        raise ValueError(\"BINARY_INPUT_NOT_ALLOWED\")\n    return s.replace(\"\\r\\n\", \"\\n\").replace(\"\\r\", \"\\n\")\n\n\ndef _time_ms(s: str, fmt: str) -> int:\n    m = (SRT_TIME if fmt == \"srt\" else VTT_TIME).fullmatch(s)\n    if not m:\n        raise ValueError(\"MALFORMED_TIMESTAMP\")\n    parts = m.groups()\n    if fmt == \"srt\":\n        h, minute, sec, ms = (int(v) for v in parts)\n    else:\n        h = int(parts[0] or 0)\n        minute, sec, ms = (int(x) for x in parts[1:])\n    if minute > 59 or sec > 59:\n        raise ValueError(\"INVALID_TIME_RANGE\")\n    return ((h * 60 + minute) * 60 + sec) * 1000 + ms\n\n\ndef _time_text(ms: int, fmt: str) -> str:\n    hours, rem = divmod(ms, 3600000)\n    minutes, rem = divmod(rem, 60000)\n    seconds, millis = divmod(rem, 1000)\n    if hours > 99:\n        raise ValueError(\"HOURS_OUT_OF_RANGE\")\n    separator = \",\" if fmt == \"srt\" else \".\"\n    return f\"{hours:02d}:{minutes:02d}:{seconds:02d}{separator}{millis:03d}\"\n\n\ndef parse_cues(data: bytes, fmt: str) -> tuple[Cue, ...]:\n    if fmt not in (\"srt\", \"vtt\"):\n        raise ValueError(\"UNSUPPORTED_FORMAT\")\n    s = _decode(data).strip(\"\\n\")\n    blocks = re.split(r\"\\n[ \\t]*\\n+\", s)\n    if fmt == \"vtt\":\n        if not blocks or not re.fullmatch(r\"WEBVTT[^\\n]*\", blocks[0]):\n            raise ValueError(\"VTT_HEADER_REQUIRED\")\n        blocks = blocks[1:]\n    if not blocks or not blocks[0] or len(blocks) > MAX_CUES:\n        raise ValueError(\"NO_CUES_OR_TOO_MANY\")\n    cues: list[Cue] = []\n    prev_start = -1\n    for i, block in enumerate(blocks, 1):\n        lines = block.split(\"\\n\")\n        identifier = \"\"\n        if fmt == \"srt\":\n            # External SRT indices are labels, not translation IDs. Real\n            # releases can start at zero, skip/duplicate numbers or omit\n            # labels entirely. Assign stable 1-based IDs by source order;\n            # never sort, remove cues or alter their timestamps/text.\n            if re.fullmatch(r\"[0-9]+\", lines[0].strip()):\n                if len(lines) < 3:\n                    raise ValueError(\"SRT_SEQUENCE_REQUIRED\")\n                timing, content = lines[1], lines[2:]\n            elif ARROW.fullmatch(lines[0]):\n                timing, content = lines[0], lines[1:]\n            else:\n                raise ValueError(\"SRT_SEQUENCE_REQUIRED\")\n        else:\n            if lines[0].startswith((\"NOTE\", \"STYLE\", \"REGION\")):\n                raise ValueError(\"VTT_UNSUPPORTED_BLOCK\")\n            if \" --> \" in lines[0]:\n                timing, content = lines[0], lines[1:]\n            else:\n                if len(lines) < 3 or not lines[0].strip():\n                    raise ValueError(\"VTT_IDENTIFIER_OR_CUE_INVALID\")\n                identifier, timing, content = lines[0], lines[1], lines[2:]\n        if not content or not all(t.strip() for t in content):\n            raise ValueError(\"EMPTY_CUE_TEXT\")\n        m = ARROW.fullmatch(timing)\n        if not m:\n            raise ValueError(\"TIMING_ARROW_REQUIRED\")\n        start, end = _time_ms(m[1], fmt), _time_ms(m[2], fmt)\n        settings = m[3]\n        if fmt == \"srt\" and settings:\n            raise ValueError(\"SRT_SETTINGS_INVALID\")\n        if end <= start or start < prev_start:\n            raise ValueError(\"INVALID_CUE_DURATION_OR_ORDER\")\n        prev_start = start\n        cues.append(Cue(i, start, end, \"\\n\".join(content), identifier, settings))\n    return tuple(cues)\n\n\ndef apply_translations(cues: tuple[Cue, ...], translations: dict[str, str]) -> tuple[Cue, ...]:\n    if not isinstance(translations, dict):\n        raise ValueError(\"TRANSLATION_MAP_REQUIRED\")\n    wanted = {str(c.number) for c in cues}\n    if set(translations) != wanted:\n        raise ValueError(\"MISSING_OR_EXTRA_TRANSLATED_CUE\")\n    out: list[Cue] = []\n    for c in cues:\n        text = translations[str(c.number)]\n        if (not isinstance(text, str) or not text.strip()\n            or len(text) > 2000 or any(ch in text for ch in (\"\\x00\", \"<\", \">\"))\n            or \"\\r\" in text):\n            raise ValueError(\"PLAIN_UTF8_TRANSLATION_REQUIRED\")\n        out.append(replace(c, text=text.strip()))\n    return tuple(out)\n\n\ndef render(cues: tuple[Cue, ...], fmt: str) -> bytes:\n    if fmt not in (\"srt\", \"vtt\"):\n        raise ValueError(\"UNSUPPORTED_FORMAT\")\n    sections = []\n    for c in cues:\n        line = f\"{_time_text(c.start_ms, fmt)} --> {_time_text(c.end_ms, fmt)}\"\n        if fmt == \"vtt\":\n            line += c.settings\n            if c.identifier:\n                line = c.identifier + \"\\n\" + line\n        else:\n            line = str(c.number) + \"\\n\" + line\n        sections.append(line + \"\\n\" + c.text)\n    header = \"WEBVTT\\n\\n\" if fmt == \"vtt\" else \"\"\n    return (header + \"\\n\\n\".join(sections) + \"\\n\").encode(\"utf-8\")\n\n\ndef main() -> int:\n    p = argparse.ArgumentParser(description=\"Offline cue translation import; no AI calls\")\n    p.add_argument(\"--input\", type=Path, required=True)\n    p.add_argument(\"--translations\", type=Path, required=True)\n    p.add_argument(\"--output\", type=Path, required=True)\n    p.add_argument(\"--confirm\", required=True)\n    args = p.parse_args()\n    if args.confirm != \"LOCAL_OFFLINE_ONE_FILE\":\n        p.error(\"EXPLICIT_ONE_FILE_CONSENT_REQUIRED\")\n    if args.input.suffix.lower() not in (\".srt\", \".vtt\") or args.output.suffix.lower() != args.input.suffix.lower():\n        p.error(\"SAME_SRT_OR_VTT_FORMAT_REQUIRED\")\n    paths = [x.resolve() for x in (args.input, args.translations, args.output)]\n    if len(set(paths)) != 3 or args.output.exists():\n        p.error(\"OUTPUT_MUST_BE_NEW_AND_DISTINCT\")\n    fmt = args.input.suffix.lower()[1:]\n    cues = parse_cues(args.input.read_bytes(), fmt)\n    translations = json.loads(_decode(args.translations.read_bytes()))\n    data = render(apply_translations(cues, translations), fmt)\n    with args.output.open(\"xb\") as f:\n        f.write(data)\n    print(f\"LOCAL_CUE_QA_PASS format={fmt} cues={len(cues)} no_cloud_or_tv_effect\")\n    return 0\n\n\nif __name__ == \"__main__\":\n    raise SystemExit(main())\n", 'candidate_cue_pipeline.py','exec'),module.__dict__)
    try:
        cues=module.parse_cues(asset.contents,'srt')
        roundtrip=module.parse_cues(module.render(cues,'srt'),'srt')
    except ValueError as exc:
        reason=str(exc)
        finish('HOLD',reason if re.fullmatch(r'[A-Z][A-Z0-9_]{2,90}',reason) else 'CANDIDATE_PARSER_ERROR')
    if len(cues)!=asset.cues or cues!=roundtrip: finish('HOLD','CANDIDATE_CUE_DRIFT')
    if tuple(c.number for c in cues)!=tuple(range(1,len(cues)+1)): finish('HOLD','CANDIDATE_ID_DRIFT')
    # Independent extract from original ordered timing lines, not rendered source.
    original=asset.contents.decode('utf-8-sig').replace('\r\n','\n').replace('\r','\n')
    pairs=[]
    for block in re.split(r'\n[ \t]*\n+', original.strip('\n')):
        lines=block.split('\n')
        for i,line in enumerate(lines[:2]):
            m=module.ARROW.fullmatch(line)
            if m:
                pairs.append((module._time_ms(m[1],'srt'),module._time_ms(m[2],'srt'),'\n'.join(lines[i+1:])))
                break
    if pairs!=[(c.start_ms,c.end_ms,c.text) for c in cues]: finish('HOLD','CANDIDATE_TIMELINE_OR_TEXT_DRIFT')
    verify=acquire_brain_english(media,cache)
    if verify.sha256!=asset.sha256: finish('HOLD','SOURCE_CHANGED_DURING_CHECK')
    finish('READY_EXISTING','PARSER_PATCH_PASS')
except (AgyEnglishUnavailable,BrainEnglishUnavailable) as exc:
    reason=str(exc)
    finish('HOLD',reason if re.fullmatch(r'(?:AGY_EN|BRAIN_EN)_[A-Z0-9_]{2,80}',reason) else 'ACQUISITION_UNCLASSIFIED')
except Exception:
    finish('HOLD','LOCAL_STAGE_ERROR')
'@
$rows = @(& py -3 -I -B -c $code $root $cache 2>$null)
if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1) { throw 'EN_STAGE_PROCESS_FAILED' }
$r = [string]$rows[0] | ConvertFrom-Json
if ($r.schema -cne 'TTV-OWNER-EN-STAGE-V1' -or $r.status -cnotin @('READY_EXISTING','READY_EXACT_MEDIA','HOLD') -or $r.media -cnotin @('EXACT_METADATA','UNVERIFIED') -or $r.reason -cnotmatch '^[A-Z][A-Z0-9_]{2,100}$' -or [int]$r.cues -lt 0 -or [int]$r.cues -gt 50000 -or [int]$r.bytes -lt 0 -or [int]$r.bytes -gt 10000000) { throw 'EN_STAGE_SUMMARY_INVALID' }
$report = @{schema=$r.schema;nonce=$request.nonce;status=$r.status;media=$r.media;cues=$r.cues;bytes=$r.bytes;reason=$r.reason}
$dest = Join-Path $spool ('Receipts\en-stage-' + $request.nonce + '.json')
[IO.File]::WriteAllText($dest,($report | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))

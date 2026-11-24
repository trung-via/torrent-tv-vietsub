# One explicitly requested Spider-Man subtitle acquisition, then existing EN Inbox.
# No translation, cache deletion, torrent add, TV event, or playback change.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$cache = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\subtitle-trials'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'STAGE_REQUEST_INVALID' }
$code = @'
import json, pathlib, re, sys, hashlib, subprocess, tempfile, os
root, cache = map(pathlib.Path, sys.argv[1:3])
app = root / 'app'
sys.path[:0] = [str(app / 'poc/p2-sub-discovery'), str(app / 'poc/p2-aisub'), str(app / 'poc/p3-vietsub-trigger')]
from matcher import Media
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader, _local_post
from owner_selected_file_resolver import _fingerprint
from brain_english_inbox import stage_brain_english, acquire_brain_english, BrainEnglishUnavailable
from agy_opensubtitles_acquisition import acquire_english, AgyEnglishUnavailable, _result
from translator_gateway import preflight_antigravity
from lean120_api import load_profile
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
    try:
        asset=acquire_brain_english(media,cache)
        out.update(cues=asset.cues, bytes=len(asset.contents))
        finish('READY_EXISTING')
    except BrainEnglishUnavailable as exc:
        if str(exc)!='BRAIN_EN_NOT_STAGED': finish('HOLD','EXISTING_INBOX_CONFLICT')
    profile=load_profile(app/'poc/p2-aisub/translator_profile.json')
    if profile.provider!='antigravity': finish('HOLD','PROFILE_NOT_AGY')
    exe=preflight_antigravity()
    captured={}
    def runner(cmd, **kw):
        # One acquisition attempt, no automatic retries. Use the existing agent
        # prompt + a user-selected candidate hint; never force a mismatched release.
        msg=json.loads(kw['input'])
        msg['message']['content'] += '\nOwner selected this candidate for a first check: https://subdl.com/es/s/info/Jl0rB5lBK4/spider-man-brand-new-day . Use another permitted source if it does not match or is not downloadable. Never invent source bytes.'
        kw['input']=json.dumps(msg,ensure_ascii=False)+'\n'
        kw['timeout']=240
        cmd=list(cmd)
        cmd[cmd.index('--print-timeout')+1]='3m'
        p=subprocess.run(cmd,**kw)
        if p.returncode==0: captured.update(_result(p.stdout))
        return p
    asset=acquire_english(media,cache_root=cache,model=profile.model,thinking_level=profile.thinking_level,runner=runner,executable=exe)
    with tempfile.TemporaryDirectory(prefix='.en-stage-',dir=cache) as folder:
        f=pathlib.Path(folder)/'english.srt'
        f.write_bytes(asset.contents)
        stage_brain_english(cache_root=cache,source_fingerprint=fp,video_name=name,release_name=captured['release_name'],source_page=captured['source_page'],srt_file=f)
    verify=acquire_brain_english(media,cache)
    if verify.sha256!=asset.sha256: finish('HOLD','STAGE_HASH_DRIFT')
    out.update(cues=verify.cues,bytes=len(verify.contents))
    finish('READY_EXACT_MEDIA')
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

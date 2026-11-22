# Owner-private forensic export of latest P2 block, sanitized to fixed enums.
# No network, provider POST, P2 replay, file/claim deletion or Owner restart.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'OWNER_P2_BLOCK_TRACE_REQUEST_INVALID'
}
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$code = @'
from pathlib import Path
import json, re, sys, time
root=Path(sys.argv[1])
out=dict(schema='TTV-OWNER-P2-BLOCK-TRACE-V1',scope='NOT_OBSERVED',
         p3='NOT_OBSERVED',route='NOT_OBSERVED',claimed='NO',
         blocked='NO',reason='NOT_OBSERVED',exception_type='NOT_OBSERVED',
         exception_code='NOT_OBSERVED',fault_site='NOT_OBSERVED',
         provider_claim='NO',cache='NO',p4='NOT_OBSERVED')
def finish(): print(json.dumps(out,separators=(',',':'),ensure_ascii=True))
try:
    hf=root/'agent-health.json'; log=root/'diagnostics'/'owner-full.log'
    if any(p.is_symlink() or not p.is_file() for p in (hf,log)):
        out['scope']='LOG_UNAVAILABLE'; finish(); sys.exit(0)
    health=json.loads(hf.read_text('utf-8'))
    age=time.time()-health.get('observed_utc_epoch',0)
    if health.get('schema')!='TTV-OWNER-AGENT-HEALTH-V1' or health.get('state')!='READY' or not 0<=age<=30 or type(health.get('pid')) is not int:
        out['scope']='HEALTH_STALE'; finish(); sys.exit(0)
    with log.open('rb') as f:
        size=f.seek(0,2); start=max(0,size-524288)
        f.seek(start); body=f.read(524288)
    if start: body=body.partition(b'\n')[2]
    lines=body.decode('utf-8','replace').splitlines()
    marks=[(i,int(m.group(1))) for i,line in enumerate(lines)
           if (m:=re.fullmatch(r'OWNER_FULL_DIAGNOSTICS_STARTED pid=(\d{1,10}) epoch=\d{1,12}',line))]
    if not marks or marks[-1][1]!=health['pid']:
        out['scope']='SESSION_NOT_IN_TAIL'; finish(); sys.exit(0)
    session=lines[marks[-1][0]+1:]
    dispatch=[i for i,line in enumerate(session) if "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'" in line and "'status': 'DISPATCH'" in line]
    if not dispatch:
        out['scope']='NO_DISPATCH'; finish(); sys.exit(0)
    out['scope']='CURRENT_OWNER_SESSION'; out['p3']='DISPATCHED'
    current=session[dispatch[-1]+1:]
    allowed_routes={'VI_READY','EN_TRANSLATE','REVIEW_REQUIRED','NO_MATCH'}
    for line in current:
        if line.startswith('AUTO_SOURCE_ROUTE='):
            v=line.partition('=')[2]
            if v in allowed_routes: out['route']=v
        if "OWNER_FULL_TRACE 'P2_EVENT_CLAIMED'" in line: out['claimed']='YES'
        if line=='AUTO_PROVIDER_DOWNLOAD=ATTEMPTED_ONCE': out['provider_claim']='YES'
        if line=='AUTO_SUBTITLE_CACHED=YES': out['cache']='YES'
        if 'P4_REVISION_HTTP_200' in line: out['p4']='REVISION_READY'
    blocks=[i for i,line in enumerate(current) if "OWNER_FULL_TRACE 'P2_EVENT_BLOCKED'" in line]
    if not blocks:
        finish(); sys.exit(0)
    out['blocked']='YES'
    after=current[blocks[-1]+1:blocks[-1]+101]
    known={'NO_APPROVED_DOWNLOAD','CANDIDATE_BINDING_MISMATCH',
           'BAD_DOWNLOAD_SCHEMA','BAD_SUBTITLE_TIMELINE','EMPTY_SUBTITLE',
           'INVALID_SUBTITLE_SIZE_OR_FORMAT','SUBTITLE_NOT_UTF8',
           'UNSAFE_SUBTITLE_TEXT','UNSAFE_CACHE_ROOT','CACHE_COLLISION',
           'BAD_API_JSON','RESPONSE_TOO_LARGE','RATE_LIMITED_429',
           'API_AUTH_DENIED','API_NETWORK_ERROR','UNTRUSTED_URL',
           'CROSS_HOST_AUTH_REDIRECT','MEDIA_BINDING_MISMATCH',
           'EN_DOWNLOAD_ALREADY_ATTEMPTED','MANUAL_DOWNLOAD_ALREADY_ATTEMPTED',
           'AUTO_SOURCE_CACHE_INDEX_INVALID','AUTO_SOURCE_CACHE_DIGEST_MISMATCH',
           'BAD_CONTENT_DIGEST','BAD_CUE_COUNT'}
    sites={'download_selected','download_manual_vi','download_manual_en',
           '_request','_claim_one_post','validate_timed_text',
           'write_private_cache','_remember_source','selected_media',
           'run_claimed','_safe_https','_json'}
    site='NOT_OBSERVED'
    for line in after:
        if "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'" in line: break
        m=re.search(r'File "[^"]+", line \d+, in ([a-zA-Z_]+)',line)
        if m and m.group(1) in sites: site=m.group(1)
        m=re.fullmatch(r'(?:[a-zA-Z_][a-zA-Z_0-9]*\.)?([A-Za-z]+Error):\s*([A-Z][A-Z0-9_]{3,100})',line.strip())
        if m:
            out['exception_type']=m.group(1) if m.group(1) in {'SubtitleApiError','ValueError','OSError','RuntimeError','FileNotFoundError','TimeoutError'} else 'OTHER'
            code=m.group(2)
            out['exception_code']=code if code in known or re.fullmatch(r'API_HTTP_[345]\d\d',code) else 'OTHER'
        if line.startswith('OWNER_BRIDGE_BLOCK_REASON='):
            code=line.partition('=')[2]
            out['reason']=code if code in known or code=='UNCLASSIFIED' else 'OTHER'
    out['fault_site']=site
except Exception:
    out['scope']='LOCAL_READ_ERROR'
finish()
'@
$rows = @(& py -3 -I -B -c $code $owner 2>$null)
if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1) { throw 'OWNER_BLOCK_TRACE_PROBE_FAILED' }
$summary = [string]$rows[0] | ConvertFrom-Json
$fields = @('schema','scope','p3','route','claimed','blocked','reason',
            'exception_type','exception_code','fault_site','provider_claim','cache','p4')
if ($summary.schema -cne 'TTV-OWNER-P2-BLOCK-TRACE-V1' -or
    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -cne
        (@($fields | Sort-Object) -join ',') -or
    $summary.scope -cnotin @('NOT_OBSERVED','LOG_UNAVAILABLE','HEALTH_STALE',
         'SESSION_NOT_IN_TAIL','NO_DISPATCH','CURRENT_OWNER_SESSION','LOCAL_READ_ERROR') -or
    $summary.p3 -cnotin @('NOT_OBSERVED','DISPATCHED') -or
    $summary.route -cnotin @('NOT_OBSERVED','VI_READY','EN_TRANSLATE','REVIEW_REQUIRED','NO_MATCH') -or
    $summary.claimed -cnotin @('YES','NO') -or
    $summary.blocked -cnotin @('YES','NO') -or
    $summary.provider_claim -cnotin @('YES','NO') -or
    $summary.cache -cnotin @('YES','NO') -or
    $summary.p4 -cnotin @('NOT_OBSERVED','REVISION_READY') -or
    $summary.exception_type -cnotmatch '^(NOT_OBSERVED|OTHER|SubtitleApiError|ValueError|OSError|RuntimeError|FileNotFoundError|TimeoutError)$' -or
    $summary.exception_code -cnotmatch '^[A-Z0-9_]{3,100}$' -or
    $summary.reason -cnotmatch '^[A-Z0-9_]{3,100}$' -or
    $summary.fault_site -cnotmatch '^[a-zA-Z0-9_]{3,80}$') {
    throw 'OWNER_BLOCK_TRACE_SUMMARY_INVALID'
}
$current = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($current.nonce -cne $request.nonce) { throw 'OWNER_BLOCK_TRACE_REQUEST_CHANGED' }
$summary | Add-Member -NotePropertyName nonce -NotePropertyValue $request.nonce
$payload = $summary | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 1024) { throw 'OWNER_BLOCK_TRACE_OVERSIZE' }
$target = Join-Path $spool 'Receipts\block-trace.json'
$temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp,$payload,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$target,$true)
Write-Output 'OWNER_BLOCK_TRACE=SANITIZED_EXPORT_COMPLETE'

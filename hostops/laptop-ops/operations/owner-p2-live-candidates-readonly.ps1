# One Owner-private post-TV-tap read of the existing P3/P2/P4 flight recorder.
# Never contact OpenSubtitles/Gemini, download content or replay P2 events.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'OWNER_LIVE_CANDIDATES_REQUEST_INVALID'
}
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$code = @'
from pathlib import Path
import json, re, sys, time

owner = Path(sys.argv[1]); result = dict(
    schema='TTV-OWNER-P2-LIVE-CANDIDATES-V1',scope='NOT_OBSERVED',
    p3='NOT_OBSERVED',route='NOT_OBSERVED',reason='NOT_OBSERVED',
    vi_rows=-1,vi_ranked=-1,vi_confident=-1,en_rows=-1,
    en_total=-1,en_ranked=-1,en_confident=-1,
    en_top_score=-1,en_top_confident='NOT_OBSERVED',
    en_top_source='NOT_OBSERVED',en_top_year='NOT_OBSERVED',
    en_top_group='NOT_OBSERVED',en_top_resolution='NOT_OBSERVED',
    en_top_codec='NOT_OBSERVED',
    download='NO',cached='NO',p2='NOT_OBSERVED',p4='NOT_OBSERVED')

def finish():
    print(json.dumps(result, separators=(',', ':'), ensure_ascii=True))

try:
    health_file = owner / 'agent-health.json'
    log_file = owner / 'diagnostics' / 'owner-full.log'
    if any(path.is_symlink() or not path.is_file() for path in (health_file, log_file)):
        result['scope']='PRIVATE_LOG_UNAVAILABLE'; finish(); sys.exit(0)
    health=json.loads(health_file.read_text(encoding='utf-8'))
    age=time.time()-health.get('observed_utc_epoch',0)
    if (health.get('schema')!='TTV-OWNER-AGENT-HEALTH-V1' or
        health.get('state')!='READY' or not 0<=age<=30 or
        type(health.get('pid')) is not int or health['pid']<=0):
        result['scope']='OWNER_HEALTH_NOT_FRESH'; finish(); sys.exit(0)
    length=log_file.stat().st_size
    with log_file.open('rb') as stream:
        start=max(0,length-524288)
        stream.seek(start)
        body=stream.read(524288)
    if start:
        body=body.partition(b'\n')[2]
    lines=body.decode('utf-8','replace').splitlines()
    sessions=[]
    for i,line in enumerate(lines):
        match=re.fullmatch(r'OWNER_FULL_DIAGNOSTICS_STARTED pid=(\d{1,10}) epoch=\d{1,12}',line)
        if match: sessions.append((i,int(match.group(1))))
    if not sessions or sessions[-1][1]!=health['pid']:
        result['scope']='SESSION_NOT_IN_TAIL'; finish(); sys.exit(0)
    events=lines[sessions[-1][0]+1:]
    accepted=[i for i,line in enumerate(events) if
              "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'" in line and
              "'status': 'DISPATCH'" in line]
    if not accepted:
        result['scope']='NO_DISPATCH_SINCE_RESTART'; finish(); sys.exit(0)
    result['scope']='CURRENT_OWNER_SESSION'
    result['p3']='DISPATCHED'
    fields={
        'AUTO_SOURCE_ROUTE':'route',
        'AUTO_SOURCE_ROUTE_REASON':'reason',
        'AUTO_VI_RAW_ROWS':'vi_rows',
        'AUTO_VI_RANKED':'vi_ranked',
        'AUTO_VI_CONFIDENT':'vi_confident',
        'AUTO_EN_RAW_ROWS':'en_rows',
        'AUTO_EN_API_TOTAL':'en_total',
        'AUTO_EN_RANKED':'en_ranked',
        'AUTO_EN_CONFIDENT':'en_confident',
        'AUTO_EN_TOP_SCORE':'en_top_score',
        'AUTO_EN_TOP_CONFIDENT':'en_top_confident',
        'AUTO_EN_TOP_SOURCE':'en_top_source',
        'AUTO_EN_TOP_YEAR':'en_top_year',
        'AUTO_EN_TOP_GROUP':'en_top_group',
        'AUTO_EN_TOP_RESOLUTION':'en_top_resolution',
        'AUTO_EN_TOP_CODEC':'en_top_codec',
    }
    allowed_route={'VI_READY','EN_TRANSLATE','REVIEW_REQUIRED','NO_MATCH'}
    allowed_reason={'CONFIDENT_VI_RELEASE','CONFIDENT_EN_RELEASE',
                    'EN_COVERAGE_INCOMPLETE','NO_CONFIDENT_UNAMBIGUOUS_RELEASE',
                    'NO_RANKABLE_SUBTITLES','VI_COVERAGE_INCOMPLETE'}
    for line in events[accepted[-1]+1:]:
        if line.startswith('AUTO_') and '=' in line:
            name,value=line.split('=',1)
            field=fields.get(name)
            if field:
                if field in {'vi_rows','vi_ranked','vi_confident','en_rows',
                             'en_total','en_ranked','en_confident'}:
                    if value.isdecimal() and 0<=int(value)<=10000000:
                        result[field]=int(value)
                elif field=='en_top_score':
                    if value.isdecimal() and 0<=int(value)<=10000000:
                        result[field]=int(value)
                elif field=='en_top_confident' and value in {'YES','NO'}:
                    result[field]=value
                elif field=='route' and value in allowed_route: result[field]=value
                elif field=='reason' and value in allowed_reason: result[field]=value
                elif value in {'MATCH','MISSING','CONFLICT'}: result[field]=value
        if line=='AUTO_PROVIDER_DOWNLOAD=ATTEMPTED_ONCE': result['download']='YES'
        if line=='AUTO_SUBTITLE_CACHED=YES': result['cached']='YES'
        if "OWNER_FULL_TRACE 'P2_EVENT_CLAIMED'" in line: result['p2']='CLAIMED'
        if "OWNER_FULL_TRACE 'P2_EVENT_BLOCKED'" in line: result['p2']='BLOCKED'
        if "OWNER_FULL_TRACE 'P2_EVENT_FINISHED'" in line:
            for status in ('VI_READY','VIETSUB_READY','REVIEW_REQUIRED'):
                if "'result': '"+status+"'" in line: result['p2']=status
        if 'P4_REVISION_HTTP_200' in line: result['p4']='REVISION_READY'
except Exception:
    result['scope']='LOCAL_READ_ERROR'
finish()
'@
$output = @(& py -3 -I -B -c $code $owner 2>$null)
if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) { throw 'OWNER_LIVE_CANDIDATES_PROBE_FAILED' }
$summary = [string]$output[0] | ConvertFrom-Json
$expected = @('schema','scope','p3','route','reason','vi_rows','vi_ranked',
    'vi_confident','en_rows','en_total','en_ranked','en_confident',
    'en_top_score','en_top_confident','en_top_source','en_top_year',
    'en_top_group','en_top_resolution','en_top_codec',
    'download','cached','p2','p4')
if ($summary.schema -cne 'TTV-OWNER-P2-LIVE-CANDIDATES-V1' -or
    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -cne
        (@($expected | Sort-Object) -join ',') -or
    $summary.scope -cnotin @('NOT_OBSERVED','PRIVATE_LOG_UNAVAILABLE',
        'OWNER_HEALTH_NOT_FRESH','SESSION_NOT_IN_TAIL',
        'NO_DISPATCH_SINCE_RESTART','CURRENT_OWNER_SESSION','LOCAL_READ_ERROR') -or
    $summary.p3 -cnotin @('NOT_OBSERVED','DISPATCHED') -or
    $summary.route -cnotin @('NOT_OBSERVED','VI_READY','EN_TRANSLATE','REVIEW_REQUIRED','NO_MATCH') -or
    $summary.reason -cnotin @('NOT_OBSERVED','CONFIDENT_VI_RELEASE',
        'CONFIDENT_EN_RELEASE','EN_COVERAGE_INCOMPLETE',
        'NO_CONFIDENT_UNAMBIGUOUS_RELEASE','NO_RANKABLE_SUBTITLES',
        'VI_COVERAGE_INCOMPLETE') -or
    $summary.en_top_confident -cnotin @('NOT_OBSERVED','YES','NO') -or
    $summary.en_top_source -cnotin @('NOT_OBSERVED','MATCH','MISSING','CONFLICT') -or
    $summary.en_top_year -cnotin @('NOT_OBSERVED','MATCH','MISSING','CONFLICT') -or
    $summary.en_top_group -cnotin @('NOT_OBSERVED','MATCH','MISSING','CONFLICT') -or
    $summary.en_top_resolution -cnotin @('NOT_OBSERVED','MATCH','MISSING','CONFLICT') -or
    $summary.en_top_codec -cnotin @('NOT_OBSERVED','MATCH','MISSING','CONFLICT') -or
    $summary.download -cnotin @('YES','NO') -or
    $summary.cached -cnotin @('YES','NO') -or
    $summary.p2 -cnotin @('NOT_OBSERVED','CLAIMED','BLOCKED',
        'VI_READY','VIETSUB_READY','REVIEW_REQUIRED') -or
    $summary.p4 -cnotin @('NOT_OBSERVED','REVISION_READY')) {
    throw 'OWNER_LIVE_CANDIDATES_SUMMARY_INVALID'
}
foreach ($field in @('vi_rows','vi_ranked','vi_confident','en_rows',
                     'en_total','en_ranked','en_confident','en_top_score')) {
    if ($summary.$field -isnot [ValueType] -or [int]$summary.$field -lt -1 -or
        [int]$summary.$field -gt 10000000) { throw 'OWNER_LIVE_CANDIDATES_COUNT_INVALID' }
}
$current = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($current.nonce -cne $request.nonce) { throw 'OWNER_LIVE_CANDIDATES_REQUEST_CHANGED' }
$summary | Add-Member -NotePropertyName nonce -NotePropertyValue $request.nonce
$json = $summary | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 1024) { throw 'OWNER_LIVE_CANDIDATES_TOO_LARGE' }
$target = Join-Path $spool 'Receipts\live-candidates.json'
$temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$target,$true)
Write-Output 'OWNER_LIVE_CANDIDATES=PRIVATE_AGGREGATES_COMPLETE'

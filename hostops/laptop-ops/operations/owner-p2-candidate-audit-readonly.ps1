# Audit the latest Owner-reviewed V4 selection against the live OpenSubtitles
# GET-only results. Never trigger a TV event, subtitle download or translation.
# Only bounded aggregate evidence may leave the Owner's private session.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'OWNER_CANDIDATE_AUDIT_REQUEST_INVALID'
}

$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installed = Join-Path $owner 'app\poc\p2-sub-discovery'
$expected = @('matcher.py','opensubtitles.py','vi_en_fallback.py',
              'owner_torrserver_readonly.py','owner_selected_file_resolver.py')
foreach ($file in $expected) {
    if (-not (Test-Path -LiteralPath (Join-Path $installed $file) -PathType Leaf)) {
        throw 'OWNER_CANDIDATE_AUDIT_INSTALLED_SOURCE_MISSING'
    }
}

# The Owner task may inherit a user-scoped key through its scheduled-task
# environment. Do not persist or display it; never ask the public runner.
if ([string]::IsNullOrWhiteSpace($env:OPENSUBTITLES_API_KEY)) {
    $env:OPENSUBTITLES_API_KEY = [Environment]::GetEnvironmentVariable(
        'OPENSUBTITLES_API_KEY', 'User')
}
$python = Get-Command python.exe -ErrorAction SilentlyContinue
if ($null -eq $python) { throw 'OWNER_CANDIDATE_AUDIT_PYTHON_NOT_FOUND' }

$code = @'
import hashlib, json, os, re, sys, time
from pathlib import Path

owner = Path(sys.argv[1]); installed = Path(sys.argv[2])
sys.path.insert(0, str(installed))
from matcher import Media, parse_release, preferred_media_release
from opensubtitles import OpenSubtitles, SubtitleApiError
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader
from vi_en_fallback import select_vi_then_en

def emit(**values):
    data = dict(schema='TTV-OWNER-CANDIDATE-AUDIT-V1', **values)
    print(json.dumps(data, separators=(',', ':'), ensure_ascii=True))

def failed(reason):
    emit(state=reason, route='UNKNOWN', reason='UNKNOWN', title='UNKNOWN',
         vi_rows=0, vi_ranked=0, vi_confident=0, en_rows=0,
         en_ranked=0, en_confident=0, en_total=-1,
         top_score=-1, top_source='UNKNOWN', top_year='UNKNOWN',
         top_group='UNKNOWN', top_resolution='UNKNOWN', gap=-1)

def comparison(reference, actual):
    if reference is None or actual is None: return 'MISSING'
    return 'MATCH' if reference == actual else 'CONFLICT'

try:
    key = os.environ.get('OPENSUBTITLES_API_KEY', '')
    if not key.strip() or '\r' in key or '\n' in key:
        failed('KEY_UNAVAILABLE'); sys.exit(0)
    inbox = owner / 'inbox'
    items = sorted((p for p in inbox.glob('event-*.review')
                    if not p.is_symlink() and p.is_file()
                    and 0 < p.stat().st_size <= 768),
                   key=lambda p: p.stat().st_mtime, reverse=True)
    if not items or time.time() - items[0].stat().st_mtime > 172800:
        failed('CURRENT_REVIEW_MISSING'); sys.exit(0)
    event = json.loads(items[0].read_text(encoding='utf-8'))
    if (event.get('schema') != 'TTV-OWNER-VIDEO-EVENT-V4'
        or set(event) != {'schema','event_id','selected_video_filename',
                          'source_fingerprint','tv_session_id','authorized_selection'}
        or not re.fullmatch('[0-9a-f]{32}', event['event_id'])
        or items[0].name != 'event-' + event['event_id'] + '.review'):
        failed('CURRENT_REVIEW_INVALID'); sys.exit(0)
    selection = event['authorized_selection']
    server, torrent, index = (selection['server_id'],
                               selection['torrent_hash'], selection['file_index'])
    if (hashlib.sha256('\0'.join((server,torrent,str(index))).encode()).hexdigest()
            != event['source_fingerprint']):
        failed('MEDIA_IDENTITY_INVALID'); sys.exit(0)
    policy = json.loads((owner / 'p3-p4-policy.json').read_text(encoding='utf-8'))
    if server != policy['profile_id']:
        failed('OWNER_PROFILE_MISMATCH'); sys.exit(0)
    file = OwnerTorrServerReader(OwnerLocalTorrServer(
        server, policy['torrserver_port']))(server, torrent, index)
    video = event['selected_video_filename']
    if re.split(r'[/\\]', file.path)[-1] != video:
        failed('MEDIA_FILENAME_MISMATCH'); sys.exit(0)
    media = Media(server, torrent, index, video, torrent_title=file.torrent_title)
    reference = preferred_media_release(media)
    if not reference.title or reference.year is None:
        failed('FILM_IDENTITY_INSUFFICIENT'); sys.exit(0)
    route = select_vi_then_en(OpenSubtitles(api_key=key), media, policy='VI_FAST')
    en = route.en
    ranked = en.decision.ranked if en is not None else ()
    lookup = {c.subtitle.subtitle_id: c.subtitle.release_name for c in en.candidates} if en else {}
    top = ranked[0] if ranked else None
    candidate = parse_release(lookup[top.subtitle_id]) if top else None
    gap = ranked[0].score - ranked[1].score if len(ranked) > 1 else -1
    emit(state='AUDITED_GET_ONLY', route=route.status, reason=route.reason,
         title='TORRENT_ALIAS' if reference.title != parse_release(video).title else 'FILENAME',
         vi_rows=route.vi.raw_rows, vi_ranked=len(route.vi.decision.ranked),
         vi_confident=sum(r.confident for r in route.vi.decision.ranked),
         en_rows=en.raw_rows if en else 0, en_ranked=len(ranked),
         en_confident=sum(r.confident for r in ranked),
         en_total=en.api_total if en and en.api_total is not None else -1,
         top_score=top.score if top else -1,
         top_source=comparison(reference.source, candidate.source) if top else 'UNKNOWN',
         top_year=comparison(reference.year, candidate.year) if top else 'UNKNOWN',
         top_group=comparison(reference.group, candidate.group) if top else 'UNKNOWN',
         top_resolution=comparison(reference.resolution, candidate.resolution) if top else 'UNKNOWN',
         gap=gap)
except SubtitleApiError as exc:
    # Never print provider errors unless they are literal codes.
    known = {'API_NETWORK_ERROR', 'RATE_LIMITED_429', 'API_AUTH_DENIED',
             'BAD_API_JSON', 'BAD_SEARCH_SCHEMA', 'RESPONSE_TOO_LARGE'}
    failed(str(exc) if str(exc) in known else 'PROVIDER_SEARCH_ERROR')
except Exception:
    failed('LOCAL_DIAGNOSTIC_ERROR')
'@

# The Python process emits *one* JSON line with fixed names, counts and enums;
# all original stdout/stderr stays in the Owner-private HostOps log.
$output = @(& $python.Source -c $code $owner $installed)
if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) {
    throw 'OWNER_CANDIDATE_AUDIT_RUNTIME_FAILED'
}
$summary = [string]$output[0] | ConvertFrom-Json
$states = @('AUDITED_GET_ONLY','KEY_UNAVAILABLE','CURRENT_REVIEW_MISSING',
    'CURRENT_REVIEW_INVALID','MEDIA_IDENTITY_INVALID','OWNER_PROFILE_MISMATCH',
    'MEDIA_FILENAME_MISMATCH','FILM_IDENTITY_INSUFFICIENT',
    'API_NETWORK_ERROR','RATE_LIMITED_429','API_AUTH_DENIED',
    'BAD_API_JSON','BAD_SEARCH_SCHEMA','RESPONSE_TOO_LARGE',
    'PROVIDER_SEARCH_ERROR','LOCAL_DIAGNOSTIC_ERROR')
$expectedNames = @('schema','state','route','reason','title','vi_rows','vi_ranked',
    'vi_confident','en_rows','en_ranked','en_confident','en_total','top_score',
    'top_source','top_year','top_group','top_resolution','gap')
if ((@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -cne
        (@($expectedNames | Sort-Object) -join ',') -or
    $summary.schema -cne 'TTV-OWNER-CANDIDATE-AUDIT-V1' -or
    $summary.state -cnotin $states -or
    $summary.route -cnotin @('UNKNOWN','VI_READY','EN_TRANSLATE','REVIEW_REQUIRED','NO_MATCH') -or
    $summary.reason -cnotin @('UNKNOWN','CONFIDENT_VI_RELEASE',
      'CONFIDENT_EN_RELEASE','EN_COVERAGE_INCOMPLETE',
      'NO_CONFIDENT_UNAMBIGUOUS_RELEASE','NO_RANKABLE_SUBTITLES') -or
    $summary.title -cnotin @('UNKNOWN','TORRENT_ALIAS','FILENAME')) {
    throw 'OWNER_CANDIDATE_AUDIT_SUMMARY_INVALID'
}
foreach ($field in @('vi_rows','vi_ranked','vi_confident','en_rows',
                     'en_ranked','en_confident','en_total','top_score','gap')) {
    if ($summary.$field -isnot [ValueType] -or
        [int]$summary.$field -lt -1 -or [int]$summary.$field -gt 10000000) {
        throw 'OWNER_CANDIDATE_AUDIT_COUNT_INVALID'
    }
}
foreach ($field in @('top_source','top_year','top_group','top_resolution')) {
    if ($summary.$field -cnotin @('UNKNOWN','MATCH','MISSING','CONFLICT')) {
        throw 'OWNER_CANDIDATE_AUDIT_MATCH_INVALID'
    }
}
$current = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($current.nonce -cne $request.nonce) { throw 'OWNER_CANDIDATE_AUDIT_REQUEST_CHANGED' }
$summary | Add-Member -NotePropertyName nonce -NotePropertyValue $request.nonce
$payload = $summary | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 1024) {
    throw 'OWNER_CANDIDATE_AUDIT_SUMMARY_TOO_LONG'
}
$target = Join-Path $spool 'Receipts\candidate-audit.json'
$temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp, $payload, [Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp, $target, $true)
Write-Output 'OWNER_CANDIDATE_AUDIT=READONLY_COMPLETE'

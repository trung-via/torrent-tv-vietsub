# Owner-interactive audit of a previously authorized selected torrent movie.
# Read-only /torrents + /subs; optional <=256 KiB EN sidecar fetch from peers.
# No torrent add, media stream, OpenSubtitles, Gemini, P2 replay or TV action.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'OWNER_TS_EN_REQUEST_INVALID'
}
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installed = Join-Path $owner 'app\poc\p2-sub-discovery'
$code = @'
import hashlib, json, re, sys, time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler

owner=Path(sys.argv[1]); installed=Path(sys.argv[2])
out=dict(schema='TTV-OWNER-TS-EN-SIDECAR-V1',state='NOT_OBSERVED',
         metadata='NOT_RUN',endpoint='NOT_RUN',en_tracks=0,
         installed_reader='NOT_RUN',download='NOT_RUN',cues=0,byte_count=0)
def finish():
    print(json.dumps(out, separators=(',',':'), ensure_ascii=True))
    sys.exit(0)
class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args): return None
opener=build_opener(ProxyHandler({}), NoRedirect())
def call(url, method='GET', body=None, cap=65536, timeout=6):
    req=Request(url,data=body,method=method,
                headers={'Accept':'application/json','Cache-Control':'no-store'})
    try:
        with opener.open(req,timeout=timeout) as response:
            if response.status!=200: return ('HTTP_OTHER',None)
            length=response.headers.get('Content-Length')
            if length is not None and (not length.isdecimal() or int(length)>cap):
                return ('TOO_LARGE',None)
            data=response.read(cap+1)
            if not 0<len(data)<=cap: return ('TOO_LARGE',None)
            return ('OK',data)
    except HTTPError as exc:
        return ('HTTP_'+str(exc.code) if exc.code in (400,401,403,404,422,500,504)
                else 'HTTP_OTHER',None)
    except (URLError,TimeoutError,OSError): return ('UNAVAILABLE',None)
try:
    policy_path=owner/'p3-p4-policy.json'
    if policy_path.is_symlink() or not policy_path.is_file():
        out['state']='POLICY_MISSING';finish()
    policy=json.loads(policy_path.read_text('utf-8'))
    profile=policy.get('profile_id'); port=policy.get('torrserver_port')
    if (policy.get('enabled') is not True or not isinstance(profile,str)
        or not re.fullmatch('[A-Za-z0-9_-]{1,80}',profile)
        or type(port) is not int or not 1024<=port<=65535):
        out['state']='POLICY_INVALID';finish()
    inbox=owner/'inbox'
    candidates=[]
    for ext in ('blocked','done','review','pending','json'):
        candidates.extend(p for p in inbox.glob('event-*.'+ext)
                          if not p.is_symlink() and p.is_file()
                          and 0<p.stat().st_size<=1024)
    candidates.sort(key=lambda p:p.stat().st_mtime,reverse=True)
    candidates=[p for p in candidates[:128]
                if time.time()-p.stat().st_mtime<=7*86400]
    if not candidates:
        out['state']='SELECTED_EVENT_MISSING';finish()
    base='http://127.0.0.1:'+str(port)
    chosen_event=None; historical=[]
    for path in candidates:
        try: event=json.loads(path.read_text('utf-8'))
        except (OSError,ValueError,UnicodeError): continue
        if not isinstance(event,dict): continue
        name=event.get('selected_video_filename');fp=event.get('source_fingerprint')
        event_id=event.get('event_id')
        if (not isinstance(name,str) or not name or len(name)>255
            or '/' in name or '\\' in name
            or not isinstance(fp,str) or not re.fullmatch('[0-9a-f]{64}',fp)
            or not isinstance(event_id,str)
            or not re.fullmatch('[0-9a-f]{32}',event_id)
            or path.name!='event-'+event_id+path.suffix): continue
        historical.append((name,fp))
        attested=event.get('authorized_selection')
        if not isinstance(attested,dict) or set(attested)!={'server_id','torrent_hash','file_index'}:
            continue
        server,tor,index=(attested['server_id'],attested['torrent_hash'],attested['file_index'])
        if (server==profile and isinstance(tor,str)
            and re.fullmatch('(?:[0-9a-f]{40}|[0-9a-f]{64})',tor)
            and type(index) is int and 0<=index<4096
            and hashlib.sha256('\0'.join((server,tor,str(index))).encode()).hexdigest()==fp):
            chosen_event=(tor,index,name);break
    if chosen_event is None and not historical:
        out['state']='SELECTED_EVENT_UNTRUSTED';finish()
    if chosen_event is None:
        # Old Owner event schemas carry only the server/hash/index fingerprint.
        # Recover exact coordinates using read-only metadata from THIS owner PC.
        state,raw=call(base+'/torrents','POST',b'{"action":"list"}',cap=524288)
        if state!='OK':
            out['state']='TORRENT_LIST_UNAVAILABLE';finish()
        listing=json.loads(raw.decode('utf-8'))
        if not isinstance(listing,list) or len(listing)>256:
            out['state']='TORRENT_LIST_INVALID';finish()
        recovered=[]
        for torrent in listing:
            if not isinstance(torrent,dict): continue
            th=torrent.get('hash')
            if not isinstance(th,str) or not re.fullmatch('(?:[0-9a-f]{40}|[0-9a-f]{64})',th):
                continue
            files=torrent.get('file_stats')
            if not isinstance(files,list) or not files:
                try: files=json.loads(torrent.get('data','{}'))['TorrServer']['Files']
                except (ValueError,TypeError,KeyError): continue
            if not isinstance(files,list) or len(files)>4096: continue
            for fil in files:
                if not isinstance(fil,dict): continue
                idx=fil.get('id');file_path=fil.get('path')
                if (type(idx) is not int or not 0<=idx<4096
                    or not isinstance(file_path,str)): continue
                digest=hashlib.sha256('\0'.join((profile,th,str(idx))).encode()).hexdigest()
                basename=file_path.replace('\\','/').rsplit('/',1)[-1]
                if any(n==basename and f==digest for n,f in historical):
                    recovered.append((th,idx,basename,digest))
        # Several playback events can legitimately point to different movies.
        # Select the latest event that has ONE exact match, not an arbitrary
        # torrent or the entire week's combined match set.
        for n,f in historical:
            matches={(th,idx,basename) for th,idx,basename,digest in recovered
                     if basename==n and digest==f}
            if len(matches)>1:
                out['state']='SELECTED_EVENT_AMBIGUOUS';finish()
            if len(matches)==1:
                chosen_event=next(iter(matches));break
        if chosen_event is None:
            out['state']='SELECTED_EVENT_NOT_IN_TORRSERVER';finish()
    tor,index,name=chosen_event
    state,raw=call(base+'/torrents','POST',
        json.dumps({'action':'get','hash':tor}).encode(),cap=524288)
    if state!='OK': out['metadata']='UNAVAILABLE';out['state']='TORRENT_METADATA_UNAVAILABLE';finish()
    record=json.loads(raw.decode('utf-8'))
    files=record.get('file_stats')
    if not isinstance(files,list) or not files:
        nested=json.loads(record.get('data','{}'))
        files=nested.get('TorrServer',{}).get('Files')
    if not isinstance(files,list) or record.get('hash')!=tor:
        out['metadata']='MISMATCH';out['state']='TORRENT_METADATA_INVALID';finish()
    selected=[f for f in files if isinstance(f,dict) and f.get('id')==index]
    if (len(selected)!=1 or not isinstance(selected[0].get('path'),str)
        or selected[0]['path'].rsplit('/',1)[-1]!=name):
        out['metadata']='MISMATCH';out['state']='TORRENT_METADATA_INVALID';finish()
    out['metadata']='MATCH'
    url=base+'/subs/'+tor+'/'+str(index)
    state,raw=call(url)
    if state!='OK':
        out['endpoint']=state;out['state']='TS_SUBS_ENDPOINT_UNAVAILABLE';finish()
    rows=json.loads(raw.decode('utf-8'))
    if not isinstance(rows,list) or len(rows)>64:
        out['endpoint']='BAD_SCHEMA';out['state']='TS_SUBS_LIST_INVALID';finish()
    out['endpoint']='HTTP_200'
    chosen=[r for r in rows if isinstance(r,dict)
        and type(r.get('index')) is int and 0<=r['index']<4096
        and r.get('format') in ('srt','vtt','ass','ssa')
        and (r.get('lang')=='en' or bool(re.search(
            r'(?i)(?:^|[^a-z])(en|eng|english)(?:[^a-z]|$)',str(r.get('name','')))))]
    out['en_tracks']=len(chosen)
    if len(chosen)!=1:
        out['state']='EN_SIDECAR_NOT_FOUND' if not chosen else 'EN_SIDECAR_AMBIGUOUS'
        finish()
    sys.path.insert(0,str(installed))
    try:
        from owner_torrserver_readonly import OwnerLocalTorrServer
        from owner_torrserver_subs import OwnerTorrServerSubtitleReader
        from matcher import Media
        from owner_torrserver_subs import TorrServerSubsUnavailable
    except (ImportError,OSError):
        out['installed_reader']='MISSING';out['state']='OWNER_READER_UNAVAILABLE';finish()
    reader=OwnerTorrServerSubtitleReader(OwnerLocalTorrServer(server,port))
    try:
        inventory=reader.list_for_media(Media(server,tor,index,name))
    except TorrServerSubsUnavailable:
        out['installed_reader']='FAILED';out['state']='OWNER_READER_LIST_FAILED';finish()
    out['installed_reader']='PRESENT'
    if inventory.en is None or inventory.en.index!=chosen[0]['index']:
        out['state']='OWNER_READER_EN_NOT_SELECTED';finish()
    try:
        asset=reader.download(inventory,inventory.en)
    except TorrServerSubsUnavailable:
        out['download']='FAILED';out['state']='OWNER_READER_DOWNLOAD_FAILED';finish()
    out['download']='VALID_SRT';out['cues']=asset.cues
    out['byte_count']=len(asset.contents);out['state']='REAL_EN_SIDECAR_VALIDATED'
except Exception:
    out['state']='LOCAL_DIAGNOSTIC_ERROR'
finish()
'@
$rows = @(& py -3 -I -B -c $code $owner $installed 2>$null)
if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1) { throw 'OWNER_TS_EN_PROBE_FAILED' }
$summary = [string]$rows[0] | ConvertFrom-Json
$fields = @('schema','state','metadata','endpoint','en_tracks',
            'installed_reader','download','cues','byte_count')
$states = @('NOT_OBSERVED','POLICY_MISSING','POLICY_INVALID',
            'SELECTED_EVENT_MISSING','SELECTED_EVENT_UNTRUSTED',
            'SELECTED_EVENT_NOT_IN_TORRSERVER','SELECTED_EVENT_AMBIGUOUS',
            'TORRENT_LIST_UNAVAILABLE','TORRENT_LIST_INVALID',
            'TORRENT_METADATA_UNAVAILABLE','TORRENT_METADATA_INVALID',
            'TS_SUBS_ENDPOINT_UNAVAILABLE','TS_SUBS_LIST_INVALID',
            'EN_SIDECAR_NOT_FOUND','EN_SIDECAR_AMBIGUOUS',
            'OWNER_READER_UNAVAILABLE','OWNER_READER_LIST_FAILED',
            'OWNER_READER_EN_NOT_SELECTED','OWNER_READER_DOWNLOAD_FAILED',
            'REAL_EN_SIDECAR_VALIDATED','LOCAL_DIAGNOSTIC_ERROR')
if ($summary.schema -cne 'TTV-OWNER-TS-EN-SIDECAR-V1' -or
    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -cne
        (@($fields | Sort-Object) -join ',') -or
    $summary.state -cnotin $states -or
    $summary.metadata -cnotin @('NOT_RUN','MATCH','MISMATCH','UNAVAILABLE') -or
    $summary.endpoint -cnotmatch '^(NOT_RUN|HTTP_(200|400|401|403|404|422|500|504|OTHER)|UNAVAILABLE|TOO_LARGE|BAD_SCHEMA)$' -or
    $summary.installed_reader -cnotin @('NOT_RUN','MISSING','FAILED','PRESENT') -or
    $summary.download -cnotin @('NOT_RUN','FAILED','VALID_SRT') -or
    $summary.en_tracks -isnot [ValueType] -or [int]$summary.en_tracks -lt 0 -or [int]$summary.en_tracks -gt 64 -or
    $summary.cues -isnot [ValueType] -or [int]$summary.cues -lt 0 -or [int]$summary.cues -gt 30000 -or
    $summary.byte_count -isnot [ValueType] -or [int]$summary.byte_count -lt 0 -or [int]$summary.byte_count -gt 262144) {
    throw 'OWNER_TS_EN_SUMMARY_INVALID'
}
$latest = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($latest.nonce -cne $request.nonce) { throw 'OWNER_TS_EN_REQUEST_CHANGED' }
$summary | Add-Member -NotePropertyName nonce -NotePropertyValue $request.nonce
$target = Join-Path $spool 'Receipts\owner-ts-en-sidecar.json'
$payload = $summary | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 1024) { throw 'OWNER_TS_EN_SUMMARY_TOO_LONG' }
$temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp,$payload,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$target,$true)
Write-Output 'OWNER_TS_EN=PRIVATE_SELECTED_MOVIE_AUDIT_COMPLETE'

# Read-only inventory of MKV-embedded subtitle streams for the latest
# previously selected Owner media. No /subs, /play, ffmpeg demux or provider.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'EMBEDDED_PROBE_REQUEST_INVALID' }
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$code = @'
import hashlib, json, re, shutil, sys, time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler

owner=Path(sys.argv[1])
result=dict(schema='TTV-OWNER-EMBEDDED-EN-V1',state='NOT_RUN',metadata='NOT_RUN',
            ffp='NOT_RUN',en_text=0,en_bitmap=0,unlabeled_text=0,
            other_subs=0,elapsed_ms=0,ffmpeg='NOT_CHECKED')
def finish():
    print(json.dumps(result,separators=(',',':'),ensure_ascii=True));sys.exit(0)
class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args): return None
opener=build_opener(ProxyHandler({}),NoRedirect())
def request(url,method='GET',body=None,cap=524288,timeout=8):
    req=Request(url,data=body,method=method,headers={'Cache-Control':'no-store'})
    try:
        with opener.open(req,timeout=timeout) as r:
            if r.status!=200: return ('HTTP_OTHER',None)
            n=r.headers.get('Content-Length')
            if n is not None and (not n.isdecimal() or int(n)>cap): return ('TOO_LARGE',None)
            b=r.read(cap+1)
            return ('OK',b) if 0<len(b)<=cap else ('TOO_LARGE',None)
    except HTTPError as e: return ('HTTP_'+str(e.code),None)
    except (URLError,OSError,TimeoutError): return ('UNAVAILABLE',None)
try:
    policy=json.loads((owner/'p3-p4-policy.json').read_text('utf-8'))
    port=policy.get('torrserver_port');profile=policy.get('profile_id')
    if (policy.get('enabled') is not True or type(port) is not int or
        not 1024<=port<=65535 or not isinstance(profile,str) or
        not re.fullmatch('[A-Za-z0-9_-]{1,80}',profile)):
        result['state']='POLICY_UNAVAILABLE';finish()
    base='http://127.0.0.1:'+str(port)
    events=[]
    for extension in ('blocked','done','review','pending','json'):
        events += [p for p in (owner/'inbox').glob('event-*.'+extension)
                   if p.is_file() and not p.is_symlink()
                   and 0<p.stat().st_size<=1024 and
                   time.time()-p.stat().st_mtime<7*86400]
    events.sort(key=lambda p:p.stat().st_mtime,reverse=True)
    selected=[]
    for path in events[:128]:
        try: row=json.loads(path.read_text('utf-8'))
        except (ValueError,OSError,UnicodeError): continue
        if not isinstance(row,dict): continue
        name=row.get('selected_video_filename');fp=row.get('source_fingerprint')
        event_id=row.get('event_id')
        if (not isinstance(name,str) or not 0<len(name)<=255 or
            '/' in name or '\\' in name or not isinstance(fp,str) or
            not re.fullmatch('[0-9a-f]{64}',fp) or
            not isinstance(event_id,str) or not re.fullmatch('[0-9a-f]{32}',event_id)
            or path.name!='event-'+event_id+path.suffix): continue
        selected.append((name,fp))
    if not selected: result['state']='SELECTION_UNAVAILABLE';finish()
    state,raw=request(base+'/torrents','POST',b'{"action":"list"}')
    if state!='OK': result['state']='TORRENT_LIST_UNAVAILABLE';finish()
    listing=json.loads(raw.decode('utf-8'))
    if not isinstance(listing,list) or len(listing)>256:
        result['state']='TORRENT_LIST_INVALID';finish()
    matches=[]
    for torrent in listing:
        if not isinstance(torrent,dict):continue
        tor=torrent.get('hash')
        if not isinstance(tor,str) or not re.fullmatch('(?:[0-9a-f]{40}|[0-9a-f]{64})',tor):continue
        files=torrent.get('file_stats')
        if not isinstance(files,list) or not files:
            try:files=json.loads(torrent.get('data','{}'))['TorrServer']['Files']
            except (TypeError,ValueError,KeyError):continue
        if not isinstance(files,list) or len(files)>4096:continue
        for f in files:
            if not isinstance(f,dict):continue
            idx=f.get('id');path=f.get('path')
            if type(idx) is not int or not 0<=idx<4096 or not isinstance(path,str):continue
            basename=path.replace('\\','/').rsplit('/',1)[-1]
            digest=hashlib.sha256('\0'.join((profile,tor,str(idx))).encode()).hexdigest()
            if any(n==basename and p==digest for n,p in selected):
                matches.append((tor,idx,basename,digest))
    chosen=None
    for n,fp in selected:
        options={(t,i,b) for t,i,b,d in matches if n==b and fp==d}
        if len(options)==1:chosen=next(iter(options));break
        if len(options)>1:result['state']='SELECTION_AMBIGUOUS';finish()
    if chosen is None:result['state']='SELECTION_NOT_FOUND';finish()
    tor,idx,name=chosen
    state,raw=request(base+'/torrents','POST',
                      json.dumps({'action':'get','hash':tor}).encode())
    if state!='OK':result['state']='METADATA_UNAVAILABLE';finish()
    doc=json.loads(raw.decode('utf-8'))
    files=doc.get('file_stats')
    if not isinstance(files,list) or not files:
        try:files=json.loads(doc.get('data','{}'))['TorrServer']['Files']
        except (TypeError,ValueError,KeyError):files=[]
    exact=[f for f in files if isinstance(f,dict) and f.get('id')==idx
           and isinstance(f.get('path'),str)
           and f['path'].replace('\\','/').rsplit('/',1)[-1]==name]
    if doc.get('hash')!=tor or len(exact)!=1:
        result['state']='METADATA_MISMATCH';finish()
    result['metadata']='MATCH'
    begin=time.monotonic()
    status,raw=request(base+'/ffp/'+tor+'/'+str(idx),cap=131072,timeout=12)
    result['elapsed_ms']=min(120000,int((time.monotonic()-begin)*1000))
    if status!='OK':
        result['ffp']=status if status in ('UNAVAILABLE','TOO_LARGE') else 'HTTP_ERROR'
        result['state']='FFP_UNAVAILABLE';finish()
    obj=json.loads(raw.decode('utf-8'))
    streams=obj.get('streams') if isinstance(obj,dict) else None
    if not isinstance(streams,list) or len(streams)>128:
        result['ffp']='BAD_SCHEMA';result['state']='FFP_INVALID';finish()
    result['ffp']='HTTP_200'
    text_codecs={'subrip','ass','ssa','webvtt','mov_text','text'}
    en_names={'eng','en','en-us','en-gb','english'}
    for s in streams:
        if not isinstance(s,dict) or s.get('codec_type')!='subtitle':continue
        tags=s.get('tags')
        lang=tags.get('language','').casefold() if isinstance(tags,dict) and isinstance(tags.get('language'),str) else ''
        text_codec=s.get('codec_name') in text_codecs
        if lang in en_names:
            result['en_text' if text_codec else 'en_bitmap']+=1
        elif text_codec and lang in ('','und'):
            result['unlabeled_text']+=1
        else:result['other_subs']+=1
    result['ffmpeg']='AVAILABLE' if shutil.which('ffmpeg') else 'MISSING'
    result['state']=('EN_TEXT_PRESENT' if result['en_text'] else
                     'EN_BITMAP_ONLY' if result['en_bitmap'] else
                     'UNLABELED_TEXT_PRESENT' if result['unlabeled_text'] else
                     'NO_EN_SUBTITLE_TRACK')
except Exception:
    result['state']='LOCAL_DIAGNOSTIC_ERROR'
finish()
'@
$rows = @(& py -3 -I -B -c $code $owner 2>$null)
if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1) { throw 'EMBEDDED_PROBE_FAILED' }
$summary = [string]$rows[0] | ConvertFrom-Json
$fields = @('schema','state','metadata','ffp','en_text','en_bitmap',
            'unlabeled_text','other_subs','elapsed_ms','ffmpeg')
if ($summary.schema -cne 'TTV-OWNER-EMBEDDED-EN-V1' -or
    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -cne
        (@($fields | Sort-Object) -join ',') -or
    [string]$summary.state -cnotmatch '^[A-Z0-9_]{3,60}$' -or
    $summary.metadata -cnotin @('NOT_RUN','MATCH') -or
    [string]$summary.ffp -cnotmatch '^[A-Z0-9_]{3,30}$' -or
    $summary.ffmpeg -cnotin @('NOT_CHECKED','AVAILABLE','MISSING')) {
    throw 'EMBEDDED_PROBE_SCHEMA_INVALID'
}
foreach ($field in @('en_text','en_bitmap','unlabeled_text','other_subs','elapsed_ms')) {
    $value = $summary.$field
    if ($value -isnot [ValueType] -or [int]$value -lt 0 -or
        [int]$value -gt $(if ($field -eq 'elapsed_ms') {120000} else {128})) {
        throw 'EMBEDDED_PROBE_COUNT_INVALID'
    }
}
$latest = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($latest.nonce -cne $request.nonce) { throw 'EMBEDDED_PROBE_REQUEST_CHANGED' }
$summary | Add-Member -NotePropertyName nonce -NotePropertyValue $request.nonce
$target = Join-Path $spool 'Receipts\owner-ts-embedded-en.json'
$payload = $summary | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 1024) { throw 'EMBEDDED_PROBE_TOO_LARGE' }
$tmp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($tmp,$payload,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($tmp,$target,$true)
Write-Output 'OWNER_TS_EMBEDDED_EN=PRIVATE_READONLY_INVENTORY_COMPLETE'

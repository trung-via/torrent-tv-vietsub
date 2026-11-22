# Read-only, bounded probe of embedded EN tracks and /play first-byte delivery
# for latest verified Owner media. No subtitle payload logging or provider.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'EMBEDDED_PROBE_REQUEST_INVALID' }
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$code = @'
import hashlib, json, queue, re, shutil, subprocess, sys, threading, time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler

owner=Path(sys.argv[1])
result=dict(schema='TTV-OWNER-EMBEDDED-EN-V1',state='NOT_RUN',metadata='NOT_RUN',
            ffp='NOT_RUN',en_text=0,en_bitmap=0,unlabeled_text=0,
            other_subs=0,elapsed_ms=0,ffmpeg='NOT_CHECKED',en_default=0,
            track_choice='NOT_RUN',prefix_result='NOT_RUN',
            prefix_cues=0,prefix_elapsed_ms=0,prefix_bytes=0,
            en_forced=0,gst_status='NOT_RUN',play_status='NOT_RUN',
            play_elapsed_ms=0,play_bytes=0,prefix_error='NONE',
            prefix_exit='NOT_RUN',prefix_progress_s=0)
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
    en_candidates=[]
    for s in streams:
        if not isinstance(s,dict) or s.get('codec_type')!='subtitle':continue
        tags=s.get('tags')
        lang=tags.get('language','').casefold() if isinstance(tags,dict) and isinstance(tags.get('language'),str) else ''
        text_codec=s.get('codec_name') in text_codecs
        if lang in en_names:
            result['en_text' if text_codec else 'en_bitmap']+=1
            stream_idx=s.get('index')
            if text_codec and type(stream_idx) is int and 0<=stream_idx<128:
                disp=s.get('disposition')
                default=(isinstance(disp,dict) and disp.get('default')==1)
                forced=(isinstance(disp,dict) and disp.get('forced')==1)
                en_candidates.append((stream_idx,default,forced))
                if default:result['en_default']+=1
                if forced:result['en_forced']+=1
        elif text_codec and lang in ('','und'):
            result['unlabeled_text']+=1
        else:result['other_subs']+=1
    result['ffmpeg']='AVAILABLE' if shutil.which('ffmpeg') else 'MISSING'
    result['state']=('EN_TEXT_PRESENT' if result['en_text'] else
                     'EN_BITMAP_ONLY' if result['en_bitmap'] else
                     'UNLABELED_TEXT_PRESENT' if result['unlabeled_text'] else
                     'NO_EN_SUBTITLE_TRACK')
    gst,raw=request(base+'/gst/settings',cap=16384,timeout=3)
    if gst=='OK':
        try:
            config=json.loads(raw.decode('utf-8'))
            result['gst_status']='BUILT_IN' if config.get('built_in') is True else 'STANDARD' if config.get('built_in') is False else 'UNKNOWN'
        except (ValueError,AttributeError,UnicodeError):result['gst_status']='UNKNOWN'
    else:result['gst_status']='NOT_AVAILABLE'
    if not en_candidates or result['ffmpeg']!='AVAILABLE':finish()
    defaults=[i for i,d,f in en_candidates if d]
    nonforced=[i for i,d,f in en_candidates if not f]
    if len(defaults)==1:
        stream_idx=defaults[0];result['track_choice']='UNIQUE_DEFAULT'
    elif len(nonforced)==1:
        stream_idx=nonforced[0];result['track_choice']='UNIQUE_NONFORCED'
    else:
        # Sampling one stream is NOT a production selection or translation.
        stream_idx=min(nonforced or [i for i,_,_ in en_candidates])
        result['track_choice']='SAMPLE_ONLY'
    play_url=base+'/play/'+tor+'/'+str(idx)
    started=time.monotonic()
    probe=Request(play_url,headers={'Cache-Control':'no-store',
                                    'Range':'bytes=0-4095','Connection':'close'})
    try:
        with opener.open(probe,timeout=9) as response:
            if response.status in (200,206):
                result['play_status']='HTTP_'+str(response.status)
                try:result['play_bytes']=min(4096,len(response.read(4096)))
                except (OSError,TimeoutError):result['play_status']='READ_TIMEOUT'
            else:result['play_status']='HTTP_OTHER'
    except HTTPError as e:
        result['play_status']='HTTP_'+str(e.code) if 400<=e.code<=599 else 'HTTP_OTHER'
    except (URLError,OSError,TimeoutError):
        result['play_status']='UNAVAILABLE'
    result['play_elapsed_ms']=min(120000,int((time.monotonic()-started)*1000))
    if result['play_bytes']==0:finish()
    args=['ffmpeg','-nostdin','-hide_banner','-loglevel','warning',
          '-stats_period','2','-progress','pipe:2','-rw_timeout','10000000',
          '-i',play_url,'-map','0:'+str(stream_idx),
          '-vn','-an','-dn','-c:s','srt','-t','1800',
          '-flush_packets','1','-f','srt','pipe:1']
    try:
        started=time.monotonic()
        proc=subprocess.Popen(args,stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    except OSError:
        result['prefix_result']='FFMPEG_LAUNCH_FAILED';finish()
    lines=queue.Queue(maxsize=256)
    def read_lines():
        try:
            for line in proc.stdout:
                lines.put(line,timeout=1)
        except (ValueError,OSError,queue.Full):pass
    threading.Thread(target=read_lines,daemon=True).start()
    def read_errors():
        try:
            for line in proc.stderr:
                msg=line.strip().lower()[:2048]
                if msg.startswith(b'out_time_us='):
                    try:result['prefix_progress_s']=min(86400,max(result['prefix_progress_s'],int(msg.split(b'=',1)[1])//1000000))
                    except ValueError:pass
                elif b'403' in msg or b'401' in msg:result['prefix_error']='HTTP_AUTH'
                elif b'404' in msg:result['prefix_error']='HTTP_NOT_FOUND'
                elif b'timed out' in msg:result['prefix_error']='TIMEOUT'
                elif b'matches no streams' in msg:result['prefix_error']='STREAM_MAP_INVALID'
                elif b'invalid data found' in msg:result['prefix_error']='INVALID_MEDIA'
                elif b'connection refused' in msg:result['prefix_error']='CONNECTION_REFUSED'
                elif b'error opening input' in msg and result['prefix_error']=='NONE':result['prefix_error']='INPUT_OPEN_FAILED'
                elif b'error' in msg and result['prefix_error']=='NONE':result['prefix_error']='OTHER_FFMPEG_ERROR'
        except (OSError,ValueError):pass
    stderr_reader=threading.Thread(target=read_errors,daemon=True)
    stderr_reader.start()
    limit=started+30.0
    total_bytes=0
    try:
        while time.monotonic()<limit and result['prefix_cues']<120:
            try:line=lines.get(timeout=min(0.25,max(0.01,limit-time.monotonic())))
            except queue.Empty:
                if proc.poll() is not None and lines.empty():break
                continue
            total_bytes+=len(line)
            if total_bytes>262144:
                result['prefix_result']='OUTPUT_CAP_REACHED';break
            if re.match(rb'^\d\d:\d\d:\d\d,\d{3} --> ',line.strip()):
                result['prefix_cues']+=1
        if result['prefix_result']=='NOT_RUN':
            result['prefix_result']=('CUES_120_REACHED' if result['prefix_cues']>=120
                                     else 'PARTIAL_CUES' if result['prefix_cues']>0
                                     else 'NO_CUES_BEFORE_DEADLINE')
    finally:
        result['prefix_elapsed_ms']=min(120000,int((time.monotonic()-started)*1000))
        result['prefix_bytes']=min(total_bytes,262144)
        if proc.poll() is None:
            result['prefix_exit']='KILLED_AT_LIMIT';proc.kill()
        try:proc.wait(timeout=3)
        except subprocess.TimeoutExpired:pass
        stderr_reader.join(timeout=1)
        if result['prefix_exit']=='NOT_RUN':
            result['prefix_exit']='ZERO' if proc.returncode==0 else 'NONZERO'
except Exception:
    result['state']='LOCAL_DIAGNOSTIC_ERROR'
finish()
'@
$rows = @(& py -3 -I -B -c $code $owner 2>$null)
if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1) { throw 'EMBEDDED_PROBE_FAILED' }
$summary = [string]$rows[0] | ConvertFrom-Json
$fields = @('schema','state','metadata','ffp','en_text','en_bitmap',
            'unlabeled_text','other_subs','elapsed_ms','ffmpeg','en_default',
            'track_choice','prefix_result','prefix_cues','prefix_elapsed_ms','prefix_bytes',
            'en_forced','gst_status','play_status','play_elapsed_ms','play_bytes',
            'prefix_error','prefix_exit','prefix_progress_s')
if ($summary.schema -cne 'TTV-OWNER-EMBEDDED-EN-V1' -or
    (@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -cne
        (@($fields | Sort-Object) -join ',') -or
    [string]$summary.state -cnotmatch '^[A-Z0-9_]{3,60}$' -or
    $summary.metadata -cnotin @('NOT_RUN','MATCH') -or
    [string]$summary.ffp -cnotmatch '^[A-Z0-9_]{3,30}$' -or
    $summary.ffmpeg -cnotin @('NOT_CHECKED','AVAILABLE','MISSING') -or
    $summary.track_choice -cnotin @('NOT_RUN','UNIQUE_DEFAULT','UNIQUE_NONFORCED','SAMPLE_ONLY') -or
    $summary.gst_status -cnotin @('NOT_RUN','BUILT_IN','STANDARD','UNKNOWN','NOT_AVAILABLE') -or
    [string]$summary.play_status -cnotmatch '^(NOT_RUN|HTTP_[0-9]{3}|HTTP_OTHER|READ_TIMEOUT|UNAVAILABLE)$' -or
    $summary.prefix_error -cnotin @('NONE','HTTP_AUTH','HTTP_NOT_FOUND','TIMEOUT',
                                    'STREAM_MAP_INVALID','INVALID_MEDIA','CONNECTION_REFUSED',
                                    'INPUT_OPEN_FAILED','OTHER_FFMPEG_ERROR') -or
    $summary.prefix_exit -cnotin @('NOT_RUN','KILLED_AT_LIMIT','ZERO','NONZERO') -or
    $summary.prefix_result -cnotin @('NOT_RUN','FFMPEG_LAUNCH_FAILED',
                                    'CUES_120_REACHED','PARTIAL_CUES',
                                    'NO_CUES_BEFORE_DEADLINE','OUTPUT_CAP_REACHED')) {
    throw 'EMBEDDED_PROBE_SCHEMA_INVALID'
}
foreach ($field in @('en_text','en_bitmap','unlabeled_text','other_subs','elapsed_ms',
                     'en_default','en_forced','play_elapsed_ms','play_bytes','prefix_progress_s',
                     'prefix_cues','prefix_elapsed_ms','prefix_bytes')) {
    $value = $summary.$field
    if ($value -isnot [ValueType] -or [int]$value -lt 0 -or
        [int]$value -gt $(if ($field -in @('elapsed_ms','prefix_elapsed_ms','play_elapsed_ms')) {120000}
                          elseif ($field -eq 'prefix_bytes') {262144}
                          elseif ($field -eq 'play_bytes') {4096}
                          elseif ($field -eq 'prefix_progress_s') {86400} else {128})) {
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

# One-shot, owner-authorized GStreamer subtitle feasibility probe.
# A SHA-pinned upstream binary runs only on 127.0.0.1 in an isolated directory.
# No changes to the existing TorrServer instance, TV, provider or Owner code.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'GST_TRIAL_REQUEST_INVALID' }
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$code = @'
import hashlib, json, os, re, shutil, socket, subprocess, sys, tempfile, time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, build_opener, ProxyHandler

owner=Path(sys.argv[1])
root=owner.parent
result=dict(schema='TTV-OWNER-GST-TRIAL-V1',state='NOT_RUN',
            identity='NOT_RUN',binary='NOT_RUN',sidecar='NOT_RUN',
            gst='NOT_RUN',echo='NOT_RUN',main_before='NOT_RUN',
            main_after='NOT_RUN',master='NOT_RUN',en_playlists=0,
            vtt='NOT_RUN',cues=0,first_cue_ms=0,probe_ms=0,
            cleanup='NOT_RUN')
binary_url=('https://github.com/YouROK/TorrServer/releases/download/'
            'MatriX.147.1/TorrServer-gst-windows-amd64.exe')
binary_sha='fe8542cf3ebbad4c8a612fda285c795a02abd7e4383b26df63e538d1c89d9ab8'
binary_size=99109888
sidecar_port=18191
sidecar_base='http://127.0.0.1:'+str(sidecar_port)
opener=build_opener(ProxyHandler({}))
trial_dir=None
proc=None
main_base=None

def get(url,cap=262144,timeout=8):
    req=Request(url,headers={'Cache-Control':'no-store'})
    try:
        with opener.open(req,timeout=timeout) as r:
            if r.status!=200:return ('HTTP_OTHER',None)
            length=r.headers.get('Content-Length')
            if length and (not length.isdecimal() or int(length)>cap):
                return ('TOO_LARGE',None)
            data=r.read(cap+1)
            if len(data)>cap:return ('TOO_LARGE',None)
            return ('OK',data)
    except HTTPError as e:return ('HTTP_'+str(e.code),None)
    except (OSError,URLError,TimeoutError):return ('UNAVAILABLE',None)

def post_torrents(base,body):
    req=Request(base+'/torrents',data=json.dumps(body).encode('utf-8'),
                headers={'Content-Type':'application/json'},method='POST')
    try:
        with opener.open(req,timeout=8) as r:
            if r.status!=200:return None
            data=r.read(524289)
            return json.loads(data) if len(data)<=524288 else None
    except (OSError,URLError,HTTPError,ValueError):return None

def select_media():
    policy=json.loads((owner/'p3-p4-policy.json').read_text('utf-8'))
    port=policy.get('torrserver_port');profile=policy.get('profile_id')
    if (policy.get('enabled') is not True or type(port) is not int or
        not 1024<=port<=65535 or not isinstance(profile,str) or
        not re.fullmatch('[A-Za-z0-9_-]{1,80}',profile)):
        return None
    global main_base
    main_base='http://127.0.0.1:'+str(port)
    events=[]
    for extension in ('blocked','done','review','pending','json'):
        for p in (owner/'inbox').glob('event-*.'+extension):
            if (p.is_file() and not p.is_symlink() and
                0<p.stat().st_size<=1024 and
                time.time()-p.stat().st_mtime<7*86400):
                events.append(p)
    events.sort(key=lambda p:p.stat().st_mtime,reverse=True)
    selected=[]
    for p in events[:128]:
        try:x=json.loads(p.read_text('utf-8'))
        except (ValueError,OSError,UnicodeError):continue
        if not isinstance(x,dict):continue
        name=x.get('selected_video_filename');fp=x.get('source_fingerprint')
        eid=x.get('event_id')
        if (isinstance(name,str) and 0<len(name)<=255 and
            '/' not in name and '\\' not in name and
            isinstance(fp,str) and re.fullmatch('[0-9a-f]{64}',fp) and
            isinstance(eid,str) and re.fullmatch('[0-9a-f]{32}',eid) and
            p.name=='event-'+eid+p.suffix):
            selected.append((name,fp))
    if not selected:return None
    listing=post_torrents(main_base,{'action':'list'})
    if not isinstance(listing,list) or len(listing)>256:return None
    found=[]
    for t in listing:
        if not isinstance(t,dict):continue
        hashval=t.get('hash')
        if not isinstance(hashval,str) or not re.fullmatch('(?:[0-9a-f]{40}|[0-9a-f]{64})',hashval):continue
        files=t.get('file_stats')
        if not isinstance(files,list) or not files:
            try:files=json.loads(t.get('data','{}'))['TorrServer']['Files']
            except (TypeError,ValueError,KeyError):continue
        if not isinstance(files,list) or len(files)>4096:continue
        for f in files:
            if not isinstance(f,dict):continue
            idx=f.get('id');path=f.get('path')
            if type(idx) is not int or not 0<=idx<4096 or not isinstance(path,str):continue
            basename=path.replace('\\','/').rsplit('/',1)[-1]
            fingerprint=hashlib.sha256('\0'.join((profile,hashval,str(idx))).encode()).hexdigest()
            if any(n==basename and fp==fingerprint for n,fp in selected):
                found.append((hashval,idx,basename,fingerprint))
    for name,fp in selected:
        choices={(h,i,b) for h,i,b,f in found if b==name and f==fp}
        if len(choices)>1:return None
        if len(choices)==1:
            h,i,b=next(iter(choices))
            doc=post_torrents(main_base,{'action':'get','hash':h})
            if not isinstance(doc,dict) or doc.get('hash')!=h:return None
            files=doc.get('file_stats')
            if not isinstance(files,list) or not files:
                try:files=json.loads(doc.get('data','{}'))['TorrServer']['Files']
                except (TypeError,ValueError,KeyError):return None
            matches=[f for f in files if isinstance(f,dict) and f.get('id')==i and
                     isinstance(f.get('path'),str) and
                     f['path'].replace('\\','/').rsplit('/',1)[-1]==b]
            return (h,i) if len(matches)==1 else None
    return None

def valid_local_uri(uri,hashval,kind,relative_to=None):
    candidate=urljoin(relative_to or sidecar_base+'/gst/'+hashval+'/',uri)
    parsed=urlparse(candidate)
    if parsed.scheme!='http' or parsed.hostname!='127.0.0.1' or parsed.port!=sidecar_port:
        return None
    if kind=='playlist':
        match=re.fullmatch('/gst/'+hashval+'/subs/[0-9]{1,3}[.]m3u8',parsed.path)
    else:
        match=re.fullmatch('/gst/'+hashval+'/subs/[0-9]{1,3}/[^/]{1,80}[.]vtt',parsed.path)
    if not match or parsed.query or parsed.fragment:return None
    return candidate

def find_en_playlists(master,hashval):
    urls=[]
    for line in master.splitlines():
        if not line.startswith('#EXT-X-MEDIA:') or 'TYPE=SUBTITLES' not in line:continue
        lang=re.search(r'LANGUAGE="([^"]{1,24})"',line)
        uri=re.search(r'URI="([^"]{1,200})"',line)
        if not uri or not lang or lang.group(1).lower() not in ('en','eng','english','en-us','en-gb'):
            continue
        resolved=valid_local_uri(uri.group(1),hashval,'playlist')
        if resolved and resolved not in urls:urls.append(resolved)
    return urls

def vtt_segments(playlist,hashval,playlist_url):
    out=[]
    for line in playlist.splitlines():
        if not line or line.startswith('#'):continue
        resolved=valid_local_uri(line.strip(),hashval,'segment',playlist_url)
        if not resolved:
            resolved=valid_local_uri(line.strip(),hashval,'segment')
        if resolved and resolved not in out:out.append(resolved)
    return out

def benchmark(hashval,idx):
    started=time.monotonic()
    deadline=started+65
    master_url=sidecar_base+'/gst/'+hashval+'/master.m3u8?index='+str(idx)
    playlists=[]
    while time.monotonic()<deadline and not playlists:
        state,raw=get(master_url,cap=131072,timeout=12)
        result['master']='HTTP_200' if state=='OK' else state
        if state=='OK':
            playlists=find_en_playlists(raw.decode('utf-8','replace'),hashval)
        if not playlists:time.sleep(2)
    result['en_playlists']=len(playlists)
    if not playlists:
        result['state']='EN_PLAYLIST_NOT_READY';return
    seen=set()
    result['vtt']='WAITING'
    while time.monotonic()<deadline and result['cues']<120:
        for playlist_url in playlists[:3]:
            state,raw=get(playlist_url,cap=131072,timeout=8)
            if state!='OK':result['vtt']=state;continue
            for segment_url in vtt_segments(raw.decode('utf-8','replace'),hashval,playlist_url):
                if segment_url in seen:continue
                seen.add(segment_url)
                status,segment=get(segment_url,cap=262144,timeout=8)
                if status!='OK':result['vtt']=status;continue
                result['vtt']='HTTP_200'
                for line in segment.splitlines():
                    if re.match(rb'^(?:\d\d:)?\d\d:\d\d[.]\d{3} --> ',line.strip()):
                        result['cues']+=1
                        if result['first_cue_ms']==0:
                            result['first_cue_ms']=int((time.monotonic()-started)*1000)
                        if result['cues']>=120:break
                if result['cues']>=120:break
        if result['cues']>=120:break
        time.sleep(2)
    result['probe_ms']=int((time.monotonic()-started)*1000)
    result['state']=('CUES_120_REACHED' if result['cues']>=120 else
                     'PARTIAL_CUES' if result['cues']>0 else
                     'NO_CUES_WITHIN_LIMIT')

try:
    selected=select_media()
    if selected is None:
        result['state']='SELECTION_UNAVAILABLE'
    else:
        result['identity']='MATCH'
        health,_=get(main_base+'/echo',cap=4096,timeout=5)
        result['main_before']='HTTP_200' if health=='OK' else health
        if health!='OK':
            result['state']='MAIN_UNAVAILABLE'
        else:
            with socket.socket() as sock:
                sock.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
                try:sock.bind(('127.0.0.1',sidecar_port))
                except OSError:result['state']='PORT_OCCUPIED'
            if result['state']=='NOT_RUN':
                root.mkdir(parents=True,exist_ok=True)
                trial_dir=Path(tempfile.mkdtemp(prefix='gsttrial-',dir=str(root)))
                exe=trial_dir/'TorrServer-gst-windows-amd64.exe'
                hashobj=hashlib.sha256();downloaded=0
                download_started=time.monotonic()
                try:
                    with opener.open(Request(binary_url),timeout=30) as source, exe.open('wb') as target:
                        while True:
                            chunk=source.read(262144)
                            if not chunk:break
                            downloaded+=len(chunk)
                            if downloaded>binary_size or time.monotonic()-download_started>125:
                                raise ValueError('DOWNLOAD_LIMIT')
                            target.write(chunk);hashobj.update(chunk)
                    result['binary']='VERIFIED' if (downloaded==binary_size and
                        hashobj.hexdigest()==binary_sha) else 'HASH_MISMATCH'
                except (ValueError,OSError,URLError,HTTPError,TimeoutError):
                    result['binary']='DOWNLOAD_FAILED'
                if result['binary']!='VERIFIED':
                    result['state']='BINARY_UNAVAILABLE'
                else:
                    settings=trial_dir/'config'
                    settings.mkdir()
                    args=[str(exe),'--port',str(sidecar_port),'--ip','127.0.0.1',
                          '--path',str(settings),'--logpath',str(trial_dir/'server.log'),
                          '--torrentaddr','127.0.0.1:0']
                    try:
                        proc=subprocess.Popen(args,stdin=subprocess.DEVNULL,
                                              stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,
                                              creationflags=subprocess.CREATE_NO_WINDOW)
                        for _ in range(35):
                            if proc.poll() is not None:break
                            st,_=get(sidecar_base+'/echo',cap=4096,timeout=1)
                            if st=='OK':
                                result['sidecar']='READY';break
                            time.sleep(1)
                        if result['sidecar']!='READY':
                            result['state']='SIDECAR_START_FAILED'
                        else:
                            gst_status,config=get(sidecar_base+'/gst/settings',cap=16384,timeout=5)
                            if gst_status=='OK':
                                try:
                                    conf=json.loads(config)
                                    result['gst']='BUILT_IN' if conf.get('built_in') is True else 'NOT_BUILT'
                                except (ValueError,AttributeError):result['gst']='SCHEMA_ERROR'
                            else:result['gst']=gst_status
                            echo,_=get(sidecar_base+'/gst/echo',cap=32768,timeout=8)
                            result['echo']='HTTP_200' if echo=='OK' else echo
                            if result['gst']!='BUILT_IN':
                                result['state']='GST_NOT_AVAILABLE'
                            elif echo!='OK':
                                result['state']='GST_RUNTIME_NOT_READY'
                            else:benchmark(*selected)
                    except (OSError,ValueError):
                        result['state']='SIDECAR_ERROR'
except Exception:
    result['state']='LOCAL_DIAGNOSTIC_ERROR'
finally:
    if proc is not None:
        if proc.poll() is None:
            try:proc.terminate();proc.wait(timeout=6)
            except (OSError,subprocess.TimeoutExpired):
                try:proc.kill();proc.wait(timeout=5)
                except (OSError,subprocess.TimeoutExpired):pass
        result['cleanup']='STOPPED' if proc.poll() is not None else 'STILL_RUNNING'
    else:result['cleanup']='NO_PROCESS'
    if trial_dir is not None and result['cleanup']!='STILL_RUNNING':
        try:shutil.rmtree(trial_dir)
        except OSError:result['cleanup']='FILES_LEFT'
    if main_base is not None:
        after,_=get(main_base+'/echo',cap=4096,timeout=5)
        result['main_after']='HTTP_200' if after=='OK' else after
    print(json.dumps(result,separators=(',',':'),ensure_ascii=True))
'@
# A private, one-shot Python subprocess carries film identity and text in memory.
# The only serialized result contains bounded enums and counts.
$rows = @(& py -3 -I -B -c $code $owner 2>$null)
if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1) { throw 'GST_TRIAL_PYTHON_FAILED' }
$row = [string]$rows[0] | ConvertFrom-Json
$fields = @('schema','state','identity','binary','sidecar','gst','echo',
            'main_before','main_after','master','en_playlists','vtt','cues',
            'first_cue_ms','probe_ms','cleanup')
if ($row.schema -cne 'TTV-OWNER-GST-TRIAL-V1' -or
    (@($row.PSObject.Properties.Name | Sort-Object) -join ',') -cne
        (@($fields | Sort-Object) -join ',') -or
    [string]$row.state -cnotmatch '^[A-Z0-9_]{3,50}$') { throw 'GST_TRIAL_SCHEMA_INVALID' }
foreach ($field in @('en_playlists','cues','first_cue_ms','probe_ms')) {
    $value=$row.$field
    if ($value -isnot [ValueType] -or [int]$value -lt 0 -or
        [int]$value -gt $(if ($field -eq 'en_playlists') {16}
                          elseif ($field -eq 'cues') {120} else {180000})) {
        throw 'GST_TRIAL_COUNTER_INVALID'
    }
}
$latest = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($latest.nonce -cne $request.nonce) { throw 'GST_TRIAL_REQUEST_CHANGED' }
$row | Add-Member -NotePropertyName nonce -NotePropertyValue $request.nonce
$target=Join-Path $spool 'Receipts\owner-ts-gst-trial.json'
$payload=$row | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 1024) { throw 'GST_TRIAL_RECEIPT_TOO_LARGE' }
$temp=$target+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
[IO.File]::WriteAllText($temp,$payload,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$target,$true)
Write-Output 'OWNER_TS_GST_TRIAL=PRIVATE_BOUNDED_TEST_COMPLETE'

# Brain-selected direct HTTP subtitle acquisition, then existing EN Inbox. NO AGY execution.
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
    try:
        asset=acquire_brain_english(media,cache)
        out.update(cues=asset.cues, bytes=len(asset.contents))
        finish('READY_EXISTING')
    except BrainEnglishUnavailable as exc:
        if str(exc)!='BRAIN_EN_NOT_STAGED': finish('HOLD','EXISTING_INBOX_CONFLICT')
    # Brain-selected public detail page. Follow only an actual exposed download URL.
    page='https://www.opensubtitles.org/en/subtitles/14097898/spider-man-brand-new-day-en'
    def allowed(url):
        p=urlsplit(url)
        return p.scheme=='https' and p.hostname in ('opensubtitles.org','www.opensubtitles.org','dl.opensubtitles.org','download.opensubtitles.org') and not p.username and not p.password and p.port in (None,443)
    class Redirect(HTTPRedirectHandler):
        def redirect_request(self,req,fp,code,msg,headers,newurl):
            if not allowed(newurl): raise ValueError('BRAIN_DOWNLOAD_REDIRECT_UNVERIFIED')
            return super().redirect_request(req,fp,code,msg,headers,newurl)
    opener=build_opener(Redirect())
    def get(url,cap):
        if not allowed(url): finish('HOLD','BRAIN_DOWNLOAD_URL_UNVERIFIED')
        try:
            with opener.open(Request(url,headers={'User-Agent':'TorrentTV-Brain/1.0','Accept':'*/*'}),timeout=15) as r:
                data=r.read(cap+1)
                if len(data)>cap: finish('HOLD','BRAIN_DOWNLOAD_TOO_LARGE')
                return data,r.geturl()
        except HTTPError as e:
            finish('HOLD','BRAIN_DOWNLOAD_HTTP_'+str(e.code))
        except (URLError,TimeoutError,OSError):
            finish('HOLD','BRAIN_DOWNLOAD_UNREACHABLE')
    raw,actual_page=get(page,3_000_000)
    html=raw.decode('utf-8','replace')
    class Links(HTMLParser):
        def __init__(self):
            super().__init__();self.links=[]
        def handle_starttag(self,tag,attrs):
            a=dict(attrs)
            if tag=='a' and a.get('href'):
                self.links.append(a['href'])
    parser=Links();parser.feed(html)
    links=set()
    for href in parser.links:
        u=urljoin(actual_page,href)
        if allowed(u) and (re.search(r'/download/(?:vrf-[a-f0-9]+/)?sub/14097898(?:/|$)',urlsplit(u).path) or re.search(r'/(?:download/file|downloadfile|subdownload)/[0-9]+(?:/|$)',urlsplit(u).path) or urlsplit(u).path.lower().endswith(('.zip','.srt'))):
            links.add(u)
    if not links:
        finish('HOLD','BRAIN_PUBLIC_DOWNLOAD_LINK_NOT_EXPOSED')
    if len(links)!=1:
        finish('HOLD','BRAIN_PUBLIC_DOWNLOAD_LINK_AMBIGUOUS')
    download=next(iter(links))
    data,actual_url=get(download,5_000_000)
    candidates=[]
    def consider(filename,content):
        release=pathlib.PurePosixPath(filename.replace('\\','/')).name
        if not target(release) or not release.lower().endswith('.srt'): return
        if re.search(r'(?i)(?:^|[. _-])(sdh|hi|forced)(?:[. _-]|$)',release): return
        try:
            # Do not fabricate a release name. Reuse the deployed match gate.
            _validate_source(media,{'release_name':release,'source_page':page})
            text=content.decode('utf-8-sig')
            content=text.encode('utf-8')
            cues=validate_timed_text(content,'srt')
            if cues<500: return
        except (ValueError,UnicodeError): return
        candidates.append((release,content,cues))
    if zipfile.is_zipfile(io.BytesIO(data)):
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            if len(z.infolist())>50: finish('HOLD','BRAIN_ARCHIVE_TOO_MANY_FILES')
            for entry in z.infolist():
                if not entry.is_dir() and entry.filename.lower().endswith('.srt') and 0<entry.file_size<=1_000_000:
                    consider(entry.filename,z.read(entry))
    else:
        consider(unquote(urlsplit(actual_url).path.rsplit('/',1)[-1]),data)
    if len(candidates)!=1:
        finish('HOLD','BRAIN_SRT_MATCH_NOT_UNIQUE')
    release,content,cues=candidates[0]
    digest=hashlib.sha256(content).hexdigest()
    with tempfile.TemporaryDirectory(prefix='.en-stage-',dir=cache) as folder:
        f=pathlib.Path(folder)/'english.srt'
        f.write_bytes(content)
        stage_brain_english(cache_root=cache,source_fingerprint=fp,video_name=name,release_name=release,source_page=page,srt_file=f)
    verify=acquire_brain_english(media,cache)
    if verify.sha256!=digest: finish('HOLD','STAGE_HASH_DRIFT')
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

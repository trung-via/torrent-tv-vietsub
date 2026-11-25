# Compare completed cached pieces only; no explicit remote seeks into missing pieces.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$py=@'
import sys,pathlib,json,re,hashlib,zipfile,urllib.parse
spool,root,owner=map(pathlib.Path,sys.argv[1:])
source="8570d25c3cc1d5f74774c5bd4703f278ef47a06f"
def main():
    receipts=[]
    for p in (spool/"History").glob("receipt-*.json"):
        try:
            if p.is_symlink() or not 0<p.stat().st_size<=2048:continue
            v=json.loads(p.read_text(encoding="utf-8-sig"))
            if v.get("source_commit")==source and v.get("operation")=="agy-native-browser-readout-1124" and v.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(v.get("nonce",""))):receipts.append(v)
        except (OSError,ValueError):pass
    if len(receipts)!=1:return "TR08QA_BIND"
    run=root/("tr-ttv-08-ironman2-subtitlecat-v4-"+receipts[0]["nonce"])
    p=run/"BRAIN_STUDENT_REPORT.json"
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=32000000:return "TR08QA_REPORT"
    r=json.loads(p.read_text(encoding="utf-8"))
    if r.get("source_commit")!=source or r.get("model")!="gemini-4-hydrogen-low" or r.get("recipe_version")!="V4" or r.get("provider")!="SubtitleCat" or r.get("video_input",{}).get("release")!="Iron Man 2 2010 REPACK 1080p BluRay x264-nikt0":return "TR08QA_DRIFT"
    arts=r.get("artifacts",[])
    if len(arts)!=1:return "TR08QA_ARTIFACT"
    a=arts[0];name=a["filename"]
    if pathlib.Path(name).name!=name:return "TR08QA_PATH"
    f=run/"browser-downloads"/name
    if not f.is_file() or f.is_symlink() or not 0<f.stat().st_size<=10000000:return "TR08QA_COPY"
    raw=f.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=a["sha256"]:return "TR08QA_HASH"
    if f.suffix.lower()==".srt":blobs=[(name,raw)]
    elif f.suffix.lower()==".zip":
        with zipfile.ZipFile(f) as z:
            blobs=[(i.filename,z.read(i)) for i in z.infolist()[:100] if i.filename.lower().endswith(".srt") and 0<i.file_size<=2000000 and not i.flag_bits&1]
    else:return "TR08QA_FORMAT"
    sys.path[:0]=[str(owner/"app/poc/p2-sub-discovery"),str(owner/"app/poc/p2-aisub")]
    from opensubtitles import validate_timed_text
    from cue_pipeline import parse_cues
    matches=[]
    for n,b in blobs:
        try:
            count=validate_timed_text(b,"srt")
            cues=parse_cues(b,"srt")
            if count!=len(cues) or count!=a["cues"]:continue
            t=re.findall(rb"(?m)^(\d{2}):(\d{2}):(\d{2})[,.]\d{3}\s+-->\s+(\d{2}):(\d{2}):(\d{2})[,.]\d{3}",b)
            if len(t)!=count:continue
            first=min(int(h)*3600+int(m)*60+int(s) for h,m,s,_,_,_ in t)
            last=max(int(h)*3600+int(m)*60+int(s) for _,_,_,h,m,s in t)
            matches.append((n,b,count,first,last))
        except Exception:pass
    if len(matches)!=1:return "TR08QA_PARSE_NOT_UNIQUE"
    n,b,count,first,last=matches[0]
    # Resolve only the owner-supplied exact release using installed localhost reader.
    from owner_torrserver_readonly import OwnerLocalTorrServer,OwnerTorrServerReader,_local_post,_NoRedirect
    from urllib.request import build_opener,ProxyHandler,Request
    from fractions import Fraction
    policy=json.loads((owner/"p3-p4-policy.json").read_text("utf-8"))
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    listing=json.loads(_local_post(cfg.url,b'{"action":"list"}',6.0))
    if not isinstance(listing,list) or len(listing)>256:return "TR08MEDIA_LIST_INVALID"
    def norm(x):return re.sub(r"[^a-z0-9]","",str(x).casefold())
    target="ironman22010repack1080pblurayx264nikt0"
    found={}
    for t in listing:
        if not isinstance(t,dict):continue
        tor=t.get("hash")
        if not isinstance(tor,str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}",tor):continue
        files=t.get("file_stats")
        if not files:
            try:files=json.loads(t.get("data","{}"))["TorrServer"]["Files"]
            except (TypeError,ValueError,KeyError):continue
        if not isinstance(files,list) or len(files)>4096:continue
        for x in files:
            if not isinstance(x,dict):continue
            name=str(x.get("path","")).replace("\\","/").rsplit("/",1)[-1]
            idx=x.get("id")
            if type(idx) is not int or not 0<=idx<4096 or not re.search(r"\.(mkv|mp4|avi|m4v|ts|m2ts)$",name,re.I):continue
            if norm(pathlib.PurePosixPath(name).stem)!=target and norm(t.get("title",""))!=target:continue
            if type(x.get("length")) is int and x["length"]>100000000:found[(tor,idx)]=(name,len(files))
    if len(found)!=1:return f"TR08MEDIA_MATCHES{len(found)}"
    (tor,idx),(name,file_count)=next(iter(found.items()))
    actual=OwnerTorrServerReader(cfg)(cfg.profile_id,tor,idx)
    if actual.path.replace("\\","/").rsplit("/",1)[-1]!=name:return "TR08MEDIA_DRIFT"
    exact=int(norm(pathlib.PurePosixPath(name).stem)==target)
    size=round(actual.length/1048576)
    if not exact:return "TR09CACHE_MEDIA_DRIFT"
    # Web IDs are sorted by path, not necessarily physical order. Do not sum by ID.
    # A complete v1 file list and total size bound every possible physical offset.
    if len(tor)!=40:return "TR09CACHE_NOT_V1"
    current=json.loads(_local_post(cfg.url,json.dumps({"action":"get","hash":tor}).encode(),6.0))
    if not isinstance(current,dict) or current.get("hash")!=tor:return "TR09CACHE_META_ID"
    fs=current.get("file_stats")
    if not isinstance(fs,list) or len(fs)!=file_count or not 1<=len(fs)<=64:return "TR09CACHE_FILELIST"
    if any(not isinstance(v,dict) or type(v.get("id")) is not int or type(v.get("length")) is not int or v["length"]<0 or not isinstance(v.get("path"),str) for v in fs):return "TR09CACHE_FILEFIELDS"
    if len({v["id"] for v in fs})!=len(fs) or len({v["path"] for v in fs})!=len(fs):return "TR09CACHE_FILEDUP"
    selected=[v for v in fs if v["id"]==idx and v["path"]==actual.path and v["length"]==actual.length]
    if len(selected)!=1:return "TR09CACHE_FILEDRIFT"
    whole=sum(v["length"] for v in fs)
    if type(current.get("torrent_size")) is not int or current["torrent_size"]!=whole:return "TR09CACHE_TOTAL_UNVERIFIED"
    # Conservative interval envelope: every possible offset is between 0 and
    # sum(other lengths), independent of ordering. All touched global pieces
    # across that envelope must be complete before reading a file-relative range.
    max_offset=whole-actual.length
    if not name.lower().endswith(".mkv"):return "TR09CACHE_NOT_MKV"
    import time,statistics,html
    from collections import defaultdict
    class DiagnosticStop(Exception):
        def __init__(self,code):self.code=code
    def vint(buf, offset, *, size):
        if offset >= len(buf):
            raise DiagnosticStop("TRUNCATED_EBML")
        first = buf[offset]
        if first == 0:
            raise DiagnosticStop("INVALID_VINT")
        width = 9 - first.bit_length()
        if width > (8 if size else 4) or offset + width > len(buf):
            raise DiagnosticStop("INVALID_VINT")
        raw = int.from_bytes(buf[offset:offset + width], "big")
        if size:
            raw &= (1 << (width * 7)) - 1
            if raw == (1 << (width * 7)) - 1:
                raise DiagnosticStop("UNKNOWN_ELEMENT_SIZE")
        return raw, width
    
    
    def children(data):
        position = 0
        while position < len(data):
            eid, ilen = vint(data, position, size=False)
            length, slen = vint(data, position + ilen, size=True)
            start = position + ilen + slen
            end = start + length
            if end > len(data):
                raise DiagnosticStop("TRUNCATED_EBML")
            yield eid, data[start:end], position
            position = end
    
    
    def fields(data):
        return {eid: value for eid, value, _ in children(data)}
    
    
    def number(data):
        return int.from_bytes(data, "big")
    opener=build_opener(ProxyHandler({}),_NoRedirect())
    base=f"http://127.0.0.1:{cfg.localhost_port}"
    deadline=time.monotonic()+60
    def cache():
        req=Request(base+"/cache",data=json.dumps({"action":"get","hash":tor}).encode(),headers={"Content-Type":"application/json","Cache-Control":"no-store"},method="POST")
        with opener.open(req,timeout=3) as resp:raw=resp.read(1048577)
        if len(raw)>1048576:raise DiagnosticStop("CACHE_CAP")
        row=json.loads(raw)
        if not isinstance(row,dict) or row.get("Hash")!=tor:raise DiagnosticStop("CACHE_ID")
        ps,n,items=row.get("PiecesLength"),row.get("PiecesCount"),row.get("Pieces")
        if type(ps) is not int or not 0<ps<=67108864 or type(n) is not int or n!=(whole+ps-1)//ps or not isinstance(items,dict):raise DiagnosticStop("CACHE_GEOMETRY")
        ready={int(k) for k,v in items.items() if isinstance(k,str) and k.isdecimal() and isinstance(v,dict) and v.get("Id")==int(k) and v.get("Completed") is True and 0<=int(k)<n}
        return ps,ready
    try:ps,ready=cache()
    except DiagnosticStop as exc:return "TR09CACHE_"+exc.code
    except Exception:return "TR09CACHE_UNAVAILABLE"
    if not ready:return "TR09CACHE_EMPTY"
    def covered(at,length,piece_size,complete):
        low=at//piece_size
        high=(at+length-1+max_offset)//piece_size
        return high-low+1<=len(complete) and all(i in complete for i in range(low,high+1))
    if not covered(0,min(ps,262144),ps,ready):return f"TR09CACHE_HEADER_MISS_P{len(ready)}O{max_offset}"
    reads=0;total=0
    def read(at,length):
        nonlocal reads,total
        if time.monotonic()>deadline or reads>=18 or total+length>33554432 or at<0 or length<=0 or at+length>actual.length:raise DiagnosticStop("BUDGET")
        ps2,now=cache()
        if ps2!=ps or not covered(at,length,ps,now):raise DiagnosticStop("CACHE_MISS")
        stop=at+length-1
        req=Request(base+f"/play/{tor}/{idx}",headers={"Range":f"bytes={at}-{stop}","Connection":"close","Cache-Control":"no-store"})
        reads+=1
        with opener.open(req,timeout=3) as resp:
            if resp.status!=206 or resp.headers.get("Content-Range")!=f"bytes {at}-{stop}/{actual.length}":raise DiagnosticStop("RANGE_ID")
            data=resp.read(length+1)
        if len(data)!=length:raise DiagnosticStop("RANGE_SHORT")
        total+=length
        return data
    def header(data,at):
        eid,w=vint(data,at,size=False)
        length,s=vint(data,at+w,size=True)
        return eid,at+w+s,length
    try:
        prefix=read(0,min(ps,262144))
        eid,off,n=header(prefix,0)
        if eid!=0x1A45DFA3:return "TR09CACHE_EBML"
        pos=off+n
        eid,w=vint(prefix,pos,size=False)
        if eid!=0x18538067:return "TR09CACHE_SEGMENT"
        segment=pos+w+9-prefix[pos+w].bit_length()
        seek={};info=None;tracks=None;pos=segment
        while pos<len(prefix)-16:
            eid,off,n=header(prefix,pos)
            if eid==0x1F43B675 or off+n>len(prefix):break
            body=prefix[off:off+n]
            if eid==0x1549A966:info=body
            elif eid==0x1654AE6B:tracks=body
            elif eid==0x114D9B74:
                for sid,sub,_ in children(body):
                    if sid==0x4DBB:
                        f=fields(sub)
                        if 0x53AB in f and 0x53AC in f:seek[number(f[0x53AB])]=segment+number(f[0x53AC])
            pos=off+n
        def element_at(pos,want):
            eid,off,n=header(read(pos,16),0)
            if eid!=want or n>262144:raise DiagnosticStop("HEADER_CAP")
            return read(pos+off,n)
        if info is None and 0x1549A966 in seek:info=element_at(seek[0x1549A966],0x1549A966)
        if tracks is None and 0x1654AE6B in seek:tracks=element_at(seek[0x1654AE6B],0x1654AE6B)
        if info is None or tracks is None:return "TR09CACHE_HEADER_INCOMPLETE"
        scale=number(fields(info).get(0x2AD7B1,b"\x0f\x42\x40"))
        if not 1<=scale<=1000000000:return "TR09CACHE_SCALE"
        tr={};num_sub=num_text=num_en=num_forced=num_conflict=0
        for ident,body,_ in children(tracks):
            if ident!=0xAE:continue
            f=fields(body)
            if number(f.get(0x83,b"\0"))!=17:continue
            num_sub+=1
            legacy=f.get(0x22B59C,b"eng").decode("utf-8","replace").strip("\x00 ").lower()
            ietf=f.get(0x22B59D,b"").decode("utf-8","replace").strip("\x00 ").lower()
            # IETF language overrides legacy; recognize all English regional tags.
            lang=ietf or legacy
            is_en=lang.replace("_","-").split("-")[0] in ("en","eng","english")
            codec=f.get(0x86,b"").decode("ascii","replace").strip("\x00 ").upper()
            is_text=codec in ("S_TEXT/UTF8","S_TEXT/ASS","S_TEXT/SSA")
            forced=bool(number(f.get(0x55AA,b"\0")))
            num_text+=is_text
            num_en+=is_en
            num_forced+=forced
            num_conflict+=bool(ietf and (legacy in ("en","eng","english"))!=is_en)
            # For a comparison sample even forced EN is evidence; never make it the production track.
            if is_en and is_text and 0xD7 in f:tr[number(f[0xD7])]=codec
        if not tr:return f"TR09TRACK_S{num_sub}T{num_text}E{num_en}F{num_forced}C{num_conflict}"
    except DiagnosticStop as exc:return "TR09CACHE_"+exc.code
    except Exception:return "TR09CACHE_HEADER_ERROR"
    def clean(s):
        s=re.sub(r"\{[^}]*\}|<[^>]*>","",html.unescape(str(s)))
        return " ".join(re.findall(r"[a-z0-9]+",s.casefold()))
    # Match distinctive full utterances or phrases spanning up to three cues.
    # Report exact and regrouped matches separately; never infer sync from text alone.
    def build_index(rows):
        exact=defaultdict(set);phrase=defaultdict(set)
        for i,(stamp,t) in enumerate(rows):
            if len(t.split())>=3 and len(t)>=12:exact[t].add(stamp)
            tokens=[]
            for j in range(i,min(i+3,len(rows))):
                if j>i and rows[j][0]-rows[j-1][0]>6500:break
                tokens.extend(rows[j][1].split())
                for n in (5,6,7,8):
                    if len(tokens)>=n:phrase[" ".join(tokens[:n])].add(stamp)
        return exact,phrase
    def match_text(t,exact,phrase):
        if len(exact.get(t,()))==1:return (next(iter(exact[t])),True)
        words=t.split()
        for n in (8,7,6,5):
            if len(words)<n:continue
            key=" ".join(words[:n])
            if len(phrase.get(key,()))==1:return (next(iter(phrase[key])),False)
        return None
    # Local deterministic regression: split line succeeds; repeated phrase is rejected.
    e0,p0=build_index([(1000,"the first small"),(1800,"test phrase here"),(9000,"unrelated words")])
    if match_text("the first small test phrase here",e0,p0)!=(1000,False):return "TR09R4_FIXTURE_SPLIT_FAIL"
    e0,p0=build_index([(1000,"this phrase repeats here now"),(9000,"this phrase repeats here now")])
    if match_text("this phrase repeats here now",e0,p0) is not None:return "TR09R4_FIXTURE_REPEAT_FAIL"
    candidate=sorted((c.start_ms,clean(c.text)) for c in parse_cues(b,"srt"))
    ix,px=build_index(candidate)
    runs=[]
    for i in sorted(ready):
        if runs and i==runs[-1][1]+1:runs[-1][1]=i
        else:runs.append([i,i])
    # Sample separate locations inside confirmed cached spans, not merely the first
    # 4 MiB of two spans. Every range still rechecks all potentially touched pieces.
    regions=[]
    for lo,hi in runs:
        at=lo*ps
        end=min((hi+1)*ps-max_offset,actual.length)
        if end-at<4096:continue
        step=4194304
        for pos in range(at,end,step):
            length=min(step,end-pos)
            if length>=4096:regions.append((pos,length))
    if len(regions)>8:
        regions=[regions[round(i*(len(regions)-1)/7)] for i in range(8)]
    seen=set();by_track=defaultdict(list);samples=0;clusters=0;errors=0
    for at,length in regions:
        if time.monotonic()>deadline or reads>=18:break
        length=min(length,33554432-total)
        if length<4096:break
        try:data=read(at,length)
        except Exception:errors+=1;continue
        samples+=1;search=0
        while search<len(data)-16:
            cp=data.find(b"\x1f\x43\xb6\x75",search)
            if cp<0:break
            search=cp+4
            try:
                eid,p,n=header(data,cp)
                stop=min(p+n,len(data));stamp=None;local=[]
                while p<stop-2:
                    eid,off,n=header(data,p)
                    if off+n>stop:break
                    body=data[off:off+n];p=off+n
                    if eid==0xE7:stamp=number(body)
                    elif eid in (0xA3,0xA0) and stamp is not None:
                        block=body if eid==0xA3 else fields(body).get(0xA1,b"")
                        if len(block)<4:continue
                        track,w=vint(block,0,size=True)
                        if track not in tr or len(block)<w+3 or block[w+2]&6:continue
                        ms=round((stamp+int.from_bytes(block[w:w+2],"big",signed=True))*scale/1000000)
                        if not 0<=ms<=7600000:continue
                        text=block[w+3:].decode("utf-8","strict")
                        if tr[track] in ("S_TEXT/ASS","S_TEXT/SSA"):text=text.split(",",8)[-1].replace("\\N"," ").replace("\\n"," ")
                        t=clean(text)
                        if len(t)>=12 and len(t.split())>=3:local.append((track,ms,t))
                if stamp is None or not 0<=stamp*scale/1000000<=7600000:continue
                clusters+=1
                for track,ms,t in local:
                    k=(track,ms,t)
                    if k in seen:continue
                    seen.add(k)
                    by_track[track].append((ms,t))
                search=max(search,stop)
            except (DiagnosticStop,ValueError,UnicodeError,IndexError):continue
    matched=[]
    for track,rows in by_track.items():
        rows.sort()
        used=set();pairs=[]
        for i,(ms,t) in enumerate(rows):
            hit=match_text(t,ix,px)
            if hit is None:
                # Adjacent embedded cues may be merged in the downloaded SRT.
                joined=t
                for j in range(i+1,min(i+3,len(rows))):
                    if rows[j][0]-rows[j-1][0]>6500:break
                    joined+=" "+rows[j][1]
                    hit=match_text(joined,ix,px)
                    if hit:break
            if hit and hit[0] not in used:
                used.add(hit[0]);pairs.append((ms,hit[0]-ms,hit[1]))
        matched.append((len(pairs),sum(v[2] for v in pairs),len(rows),pairs))
    _,_,n,best=max(matched,key=lambda x:(x[0],x[1]),default=(0,0,0,[]))
    exact=[d for _,d,e in best if e]
    near=sum(abs(d)<=750 for d in exact)
    med=round(statistics.median(exact)) if exact else 0
    span=round((max(t for t,_,_ in best)-min(t for t,_,_ in best))/1000) if best else 0
    # Exact cue starts only for offset. Regrouped phrase matches show content,
    # but may have different segmentation and are not exact timing evidence.
    return f"TR09R4_P{len(ready)}S{samples}N{n}M{len(best)}E{len(exact)}A{near}D{'P' if med>=0 else 'N'}{abs(med)}V{span}X{errors}KB{total//1024}"

try:print(main())
except Exception:print("TR08QA_PRIVATE_ERROR")
'@
$f=Join-Path $env:TEMP ('ttv-v4-qa-'+[Guid]::NewGuid().ToString('N')+'.py')
try{
 [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
 $out=@(& py -3 -I -B $f $spool $root $owner 2>$null)
 $code='TR08QA_READ_ERROR'
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}
}finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

# Reconcile exact trained attempt with Chrome download records and new subtitle artifacts.
# No browser interaction, network call, file removal or production change.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '2a439bf383842021ffdc6e5a9fc6fc221ed8c21e' -and $r.operation -ceq 'agy-browser-headless-control-1124' -and $r.result -ceq 'SUCCESS' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='ZIPQA_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $run=Join-Path $root ('agy-cdp9555-mcp-stdio-'+$prior[0].nonce)
 $py=@'
import sys,pathlib,json,re,sqlite3,zipfile,os,hashlib,datetime,urllib.parse
root,run=map(pathlib.Path,sys.argv[1:])
def read_json(p):
    try:
        if p.is_file() and not p.is_symlink() and p.stat().st_size<4194304:return json.loads(p.read_text(encoding="utf-8-sig"))
    except (OSError,ValueError):pass
    return {}
def movie(s):return bool(re.search(r"spider[\W_]*man|brand[\W_]*new[\W_]*day|14104608|14109322",s,re.I))
rr=read_json(run/"RESULT.json")
if not isinstance(rr,dict):rr={}
if not run.is_dir():
    print("ZIPQA_RUN_MISSING");sys.exit(0)
# Exact workflow interval (UTC), with 30 s completion tolerance.
start=datetime.datetime.fromisoformat("2026-11-24T14:27:39+00:00").timestamp()
end=datetime.datetime.fromisoformat("2026-11-24T14:32:23+00:00").timestamp()
profile=root/"CDP9555Profile"/"Default"
pref=read_json(profile/"Preferences")
default=pathlib.Path.home()/"Downloads"
dirs={default,run/"downloads"}
try:
    p=pathlib.Path(pref["download"]["default_directory"])
    if p.is_absolute() and p.is_dir():dirs.add(p)
except (KeyError,TypeError):pass
try:
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders") as k:
        p=pathlib.Path(os.path.expandvars(winreg.QueryValueEx(k,"{374DE290-123F-4565-9164-39C4925E467B}")[0]))
        if p.is_absolute() and p.is_dir():dirs.add(p)
except OSError:pass
files={}
def add(p,source,ident):
    try:
        if not p.is_file() or p.is_symlink() or p.suffix.lower() not in (".zip",".srt") or not 0<p.stat().st_size<=10000000:return
        k=str(p.resolve()).casefold()
        prev=files.get(k)
        files[k]=(p,max(source,prev[1] if prev else 0),max(ident,prev[2] if prev else 0))
    except OSError:pass
dbstate=0; records=0; dl=0; complete=0
try:
    db=profile/"History"
    if db.is_file():
        c=sqlite3.connect(db.as_uri()+"?mode=ro",uri=True,timeout=2)
        c.execute("PRAGMA query_only=ON")
        lo=int((start+11644473600)*1000000);hi=int((end+11644473600)*1000000)
        # Read only download entries within this exact test interval.
        for did,target,state,ref,tab,total,received in c.execute("SELECT id,target_path,state,referrer,tab_url,total_bytes,received_bytes FROM downloads WHERE start_time BETWEEN ? AND ?",(lo,hi)):
            urls=[x[0] for x in c.execute("SELECT url FROM downloads_url_chains WHERE id=? ORDER BY chain_index",(did,))]
            hosts=[urllib.parse.urlsplit(u).hostname for u in urls if u]
            if not any(h in ("dl.opensubtitles.org","www.opensubtitles.org","opensubtitles.org") for h in hosts):continue
            records+=1
            direct=int("dl.opensubtitles.org" in hosts);dl=max(dl,direct)
            ident=2 if any("14104608" in x for x in [str(ref),str(tab)]+urls) else 1 if movie(" ".join([str(target),str(ref),str(tab)]+urls)) else 0
            if state==1 and received>0 and (total<=0 or received==total):
                complete+=1;add(pathlib.Path(target),2 if direct else 1,ident)
        c.close();dbstate=1
except (OSError,sqlite3.Error,ValueError,TypeError):dbstate=2
name=rr.get("downloaded_filename")
for d in dirs:
    try:
        for p in d.iterdir():
            if not (movie(p.name) or isinstance(name,str) and p.name==name):continue
            st=p.stat()
            if start<=st.st_ctime<=end or start<=st.st_mtime<=end:add(p,0,1 if movie(p.name) else 0)
    except OSError:pass
count=0;best=0;last=0;identity=0;source=0;en=0;zipcount=0;ads=0;aid=0;ahost=0
for p,src,ident in files.values():
    try:
        blobs=[]
        # Read only Zone.Identifier of this already time/movie-filtered file.
        try:
            with open(str(p)+":Zone.Identifier","r",encoding="utf-8",errors="replace") as f:
                zone=f.read(8192)
            ads=1
            fields=dict(x.split("=",1) for x in zone.splitlines() if "=" in x)
            hosturl=fields.get("HostUrl","")
            refurl=fields.get("ReferrerUrl","")
            h=urllib.parse.urlsplit(hosturl).hostname
            ahost=max(ahost,2 if h=="dl.opensubtitles.org" else 1 if h in ("www.opensubtitles.org","opensubtitles.org") else 0)
            if re.search(r"(?<!\d)14104608(?!\d)",hosturl+" "+refurl):aid=2
            elif re.search(r"(?<!\d)14109322(?!\d)",hosturl+" "+refurl):aid=max(aid,1)
        except (OSError,ValueError):pass
        if p.suffix.lower()==".zip":
            with zipfile.ZipFile(p) as z:
                zipcount+=1
                for i in z.infolist()[:100]:
                    if i.filename.lower().endswith(".srt") and 0<i.file_size<=2000000 and not i.flag_bits&1:blobs.append((i.filename,z.read(i)))
        else:blobs=[(p.name,p.read_bytes())]
        for n,data in blobs:
            text=data.decode("utf-8-sig",errors="replace")
            ts=re.findall(r"(?m)^(\d{2}):(\d{2}):(\d{2})[,.]\d{3}\s+-->\s+(\d{2}):(\d{2}):(\d{2})[,.]\d{3}",text)
            if not ts:continue
            count+=1
            words=re.findall(r"[A-Za-z]+",re.sub(r"<[^>]*>"," ",text).lower())
            eng=sum(w in {"the","you","and","to","i","is","it","we","that","what","of","me","in","my","have","not","are"} for w in words)
            is_en=int(len(words)>30 and eng/len(words)>0.12)
            if (ident,src,len(ts))>(identity,source,best):
                identity=ident;source=src;best=len(ts);en=is_en
                t=ts[-1];last=int(t[3])*3600+int(t[4])*60+int(t[5])
    except (OSError,ValueError,RuntimeError,zipfile.BadZipFile):pass
print(f"ZIPORIGIN_ADS{ads}_HOST{ahost}_ID{aid}_F{min(len(files),9)}_C{min(best,99999)}_T{last}")
'@
 $out=@($py | & py -3 -I -B - $root $run 2>$null)
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='ZIPQA_PARSE_ERROR'}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

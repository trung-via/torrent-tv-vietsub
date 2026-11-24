# Read-only reconciliation of exact GEN2 attempt. No provider or browser calls.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '1c6600358d1bc30e9228c1ec2c0b8027f1d2e8c6' -and $r.operation -ceq 'agy-browser-headless-control-1124' -and $r.result -ceq 'SUCCESS' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='G2READ_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $run=Join-Path $root ('agy-cdp9555-mcp-stdio-'+$prior[0].nonce)
 $py=@'
import sys,pathlib,json,re,os,datetime,urllib.parse,zipfile
root,run=map(pathlib.Path,sys.argv[1:])
def read(p):
    try:
        if p.is_file() and not p.is_symlink() and p.stat().st_size<=4194304:return p.read_text(encoding="utf-8-sig",errors="replace")
    except OSError:pass
    return ""
def obj(p):
    try:
        x=json.loads(read(p))
        return x if isinstance(x,dict) else {}
    except ValueError:return {}
def rows(p):
    out=[]
    for l in read(p).splitlines():
        try:
            x=json.loads(l)
            if isinstance(x,dict):out.append(x)
        except ValueError:pass
    return out
if not run.is_dir():print("G2READ_RUN_MISSING");sys.exit(0)
trace=[x.get("tool") for x in rows(run/"mcp-trace.jsonl") if x.get("ok") is True]
ev=rows(run/"agy-stdout.jsonl")
term=[x for x in ev if x.get("event")=="result"]
rr=obj(run/"RESULT.json"); sel=obj(run/"SELECTION.json")
verified=obj(run/"verified-acquisition.json")
# Classify runtime logs only, not initial instructions.
logs=read(run/"agy-stderr.txt")+"\n"+read(run/"mcp-stderr.txt")+"\n"+json.dumps(term)
for x in ev:
    if str(x.get("event","")).lower() in ("tool_result","tool_error","error","assistant_error"):logs+="\n"+json.dumps(x)
calls=[x for x in ev if str(x.get("event","")).lower() in ("tool_use","tool_call","tool_start","tool_request")]
replies=[x for x in ev if str(x.get("event","")).lower() in ("tool_result","tool_error","tool_end","tool_response")]
# Classify actual terminal/assistant output without disclosing raw logs.
assistant=[x for x in ev if str(x.get("event","")).lower() in ("assistant","message") and x.get("role")!="user"]
logs+="\n"+json.dumps(assistant)
reason="UNSPEC"
for label,pat in [("QUOTA",r"resource.exhausted|quota.exceeded|rate.limit.exceeded|usage limit|capacity exhausted"),("SANDBOX",r"sandbox.{0,80}(?:denied|blocked|unavailable|failed)|approval required|tool permission|not in allowed|not permitted"),("SHELL",r"not recognized as (?:an internal|the name)|command not found|cannot find the path|unexpected token|invalid syntax|no such file"),("TIME",r"print.{0,10}timeout|timed out|deadline exceeded|timeout exceeded|execution timeout"),("SCOPE",r"PAGE_SCOPE_REQUIRED|TOOL_SCOPE|NO_PAGE_ID"),("PY",r"Traceback \(most recent call last\)|ModuleNotFoundError|SyntaxError|NameError|ImportError"),("DENIAL",r"access denied|captcha|403 forbidden|401 unauthorized|permission denied"),("MCP",r"TOOL_(?:ARG|PAGE|TIME|OTHER)|RPC_(?:ARG|PAGE|TIME|OTHER)|broken pipe|ECONNREFUSED")]:
    if re.search(pat,logs,re.I):reason=label;break
start=datetime.datetime.fromisoformat("2026-11-24T14:52:17+00:00").timestamp()
end=datetime.datetime.fromisoformat("2026-11-24T14:53:54+00:00").timestamp()
dirs={pathlib.Path.home()/"Downloads",run/"downloads"}
pref=obj(root/"CDP9555Profile"/"Default"/"Preferences")
try:
    d=pathlib.Path(pref["download"]["default_directory"])
    if d.is_absolute() and d.is_dir():dirs.add(d)
except (KeyError,TypeError):pass
try:
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders") as k:
        d=pathlib.Path(os.path.expandvars(winreg.QueryValueEx(k,"{374DE290-123F-4565-9164-39C4925E467B}")[0]))
        if d.is_absolute() and d.is_dir():dirs.add(d)
except OSError:pass
found=set();best=0
for d in dirs:
    try:
        for p in d.iterdir():
            if not re.search(r"odyssey",p.name,re.I) or p.suffix.lower() not in (".zip",".srt") or not p.is_file() or p.is_symlink():continue
            st=p.stat()
            if not 0<st.st_size<=10000000 or not(start<=st.st_ctime<=end or start<=st.st_mtime<=end):continue
            try:
                with open(str(p)+":Zone.Identifier","r",encoding="utf-8",errors="replace") as f:
                    fields=dict(x.split("=",1) for x in f.read(8192).splitlines() if "=" in x)
                if urllib.parse.urlsplit(fields.get("HostUrl","")).hostname!="dl.opensubtitles.org":continue
            except (OSError,ValueError):continue
            try:
                if p.suffix.lower()==".srt":blobs=[p.read_bytes()]
                else:
                    with zipfile.ZipFile(p) as z:blobs=[z.read(i) for i in z.infolist()[:100] if i.filename.lower().endswith(".srt") and 0<i.file_size<=2000000 and not i.flag_bits&1]
                c=max((len(re.findall(rb"(?m)^\d{2}:\d{2}:\d{2}[,.]\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}[,.]\d{3}",b)) for b in blobs),default=0)
                if c:found.add(str(p.resolve()).casefold());best=max(best,c)
            except (OSError,ValueError,RuntimeError,zipfile.BadZipFile):pass
    except OSError:pass
def n(*names):return min(99,sum(trace.count(x) for x in names))
print(f"G2READ_R{int(bool(rr))}_S{int(bool(sel))}_T{min(len(term),9)}_N{n('new_page')}_V{n('navigate_page')}_P{n('take_snapshot')}_C{n('click')}_E{n('close_page')}_F{min(len(found),9)}_Q{min(best,99999)}_A{min(len(calls),99)}_B{min(len(replies),99)}_{reason}")
'@
 $out=@($py | & py -3 -I -B - $root $run 2>$null)
 if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='G2READ_PARSE_ERROR'}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

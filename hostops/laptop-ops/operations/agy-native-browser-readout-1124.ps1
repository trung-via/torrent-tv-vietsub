# Ask AGY for a diagnosis of its exact failed local helper attempts.
# No shell/browser/provider actions requested; no settings or permission changes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-teacher-native-audit-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,os,json,re,subprocess,datetime,urllib.parse
owner,run=map(pathlib.Path,sys.argv[1:])
sys.path.insert(0,str(owner/"app/poc/p2-aisub"))
from translator_gateway import preflight_antigravity
def read(p):
    try:
        if p.is_file() and not p.is_symlink() and p.stat().st_size<=4194304:return p.read_text(encoding="utf-8-sig",errors="replace")
    except OSError:pass
    return ""
history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
matches=[]
for f in history.glob("receipt-*.json"):
    try:
        q=json.loads(read(f))
        if q.get("source_commit")=="98df81d855901176d5cf50a71c83876ce6e73885" and q.get("operation")=="agy-browser-headless-control-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):matches.append(q["nonce"])
    except (ValueError,TypeError):pass
if len(matches)!=1:
    print("TRN_PRIOR_HOLD");sys.exit(0)
p=run.parent/("agy-cdp9555-mcp-stdio-"+matches[0])
recipe=int(bool(read(p/"TEACHER_RECIPE.json")))
selection=int(bool(read(p/"SELECTION.json")))
result=int(bool(read(p/"RESULT.json")))
trace=read(p/"mcp-trace.jsonl")
calls=sum(1 for l in trace.splitlines() if '"ok": true' in l)
# Reconcile the exact run's possible download before a new provider attempt.
start=datetime.datetime.fromisoformat("2026-11-24T15:43:35+00:00").timestamp()
end=datetime.datetime.fromisoformat("2026-11-24T15:46:42+00:00").timestamp()
dirs={pathlib.Path.home()/"Downloads",p/"downloads"}
try:
    prefs=json.loads(read(run.parent/"CDP9555Profile"/"Default"/"Preferences"))
    d=pathlib.Path(prefs["download"]["default_directory"])
    if d.is_absolute():dirs.add(d)
except (KeyError,TypeError,ValueError):pass
try:
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders") as k:
        d=pathlib.Path(os.path.expandvars(winreg.QueryValueEx(k,"{374DE290-123F-4565-9164-39C4925E467B}")[0]))
        if d.is_absolute():dirs.add(d)
except OSError:pass
found=set()
for d in dirs:
    try:
        for f in d.iterdir():
            if not f.is_file() or f.is_symlink() or f.suffix.lower() not in (".zip",".srt"):continue
            st=f.stat()
            if not (start<=st.st_ctime<=end or start<=st.st_mtime<=end):continue
            try:
                with open(str(f)+":Zone.Identifier",encoding="utf-8",errors="replace") as fh:
                    ads=dict(x.split("=",1) for x in fh.read(8192).splitlines() if "=" in x)
                if urllib.parse.urlsplit(ads.get("HostUrl","")).hostname=="dl.opensubtitles.org":found.add(str(f.resolve()).casefold())
            except (OSError,ValueError):pass
    except OSError:pass
# Inspect only installed CLI documented flags and recognized MCP config structure.
cli=preflight_antigravity()
try:
    proc=subprocess.run([cli,"--help"],cwd=run,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=15,check=False)
    helptext=proc.stdout+"\n"+proc.stderr
except (OSError,subprocess.TimeoutExpired):helptext=""
(run/"cli-help.txt").write_text(helptext,encoding="utf-8")
opts=["--mcp-config","--strict-mcp-config","--allowed-tools","--disable-mcp","--mcp","--plugin","--plugins","--add-dir"]
bits="".join(str(int(bool(re.search(re.escape(x)+r"(?![\w-])",helptext)))) for x in opts)
home=pathlib.Path.home()
cfg=home/".gemini"/"config"/"mcp_config.json"
settings=home/".gemini"/"antigravity-cli"/"settings.json"
try:servers=json.loads(read(cfg)).get("mcpServers",{})
except (ValueError,AttributeError):servers={}
if not isinstance(servers,dict):servers={}
wake=0;ttv=0;ver=0;disabled=0
for k,v in servers.items():
    if not isinstance(v,dict):continue
    if v.get("disabled") is True:disabled+=1;continue
    args=v.get("args",[])
    if not isinstance(args,list):continue
    if any(isinstance(x,str) and "chrome-devtools-mcp" in x for x in args):
        if any(isinstance(x,str) and "127.0.0.1:9444" in x for x in args):wake+=1
        if any(isinstance(x,str) and "127.0.0.1:9555" in x for x in args):ttv+=1
        if any(isinstance(x,str) and "chrome-devtools-mcp@1.14.0"==x for x in args):ver+=1
print(f"TRN_Q{recipe}S{selection}R{result}C{min(calls,99)}D{min(len(found),99)}_H{bits}_G{min(len(servers),99)}W{wake}T{ttv}V{ver}X{disabled}")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
$code='AGYASK_LOCAL_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

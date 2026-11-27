Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('g21-warm-readout-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import pathlib,sys,json,re
root,spool,run=map(pathlib.Path,sys.argv[1:4])
source="08cb7c2a7494280ccaa050891708a579cf338417"
def read(p,limit=16777216):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>limit:return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
def obj(p):
    try:
        v=json.loads(read(p))
        return v if isinstance(v,dict) else {}
    except ValueError:return {}
prior=[]
for p in (spool/"History").glob("receipt-*.json"):
    v=obj(p);n=v.get("nonce","")
    if v.get("source_commit")!=source or v.get("result")!="SUCCESS" or not re.fullmatch("[a-f0-9]{32}",str(n)):continue
    q=obj(spool/"History"/("request-"+n+".json"))
    if q.get("nonce")==n and q.get("source_commit")==source:prior.append((q.get("requested_utc_epoch",0),n))
if len(prior)!=1:print("G21_READOUT_RECEIPT_COUNT_"+str(len(prior)));sys.exit(0)
import os,subprocess,shutil,time
_,n=prior[0]
student=root/("g21-student-v2-"+n)
r=obj(student/"BRAIN_HANDOFF.json")
if r.get("source_commit")!=source or r.get("process_state")!="EXITED":print("G21_WARM_STUDENT_DRIFT");sys.exit(0)
saved=read(student/"cli-help.txt")
owner=root.parent/"OwnerBridge"
sys.path.insert(0,str(owner/"app/poc/p2-aisub"))
try:
    from translator_gateway import preflight_antigravity
    cli=preflight_antigravity()
    ps=shutil.which("pwsh")
    if not ps:raise ValueError("NO_PWSH")
    env=dict(os.environ)
    env["TTV_AGY_CLI"]=str(cli)
    for k in ("GEMINI_API_KEY","GOOGLE_API_KEY","GOOGLE_GEMINI_BASE_URL","AGY_ADC_AUTH","GOOGLE_CLOUD_PROJECT","GOOGLE_CLOUD_QUOTA_PROJECT"):env.pop(k,None)
    def probe(arg):
        start=time.monotonic()
        p=subprocess.run([ps,"-NoProfile","-NonInteractive","-Command","& $env:TTV_AGY_CLI "+arg+"; exit $LASTEXITCODE"],env=env,cwd=run,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=20)
        return p.returncode,p.stdout+"\n"+p.stderr,round((time.monotonic()-start)*1000)
    hrc,helptext,hms=probe("--help")
    vrc,version,vms=probe("--version")
    (run/"cli-help-current.txt").write_text(helptext,encoding="utf-8")
    (run/"cli-version-current.txt").write_text(version,encoding="utf-8")
    # Only documented command-line flags, not arbitrary help prose.
    def flags(s):
        return set(re.findall(r"(?<![A-Za-z0-9_-])--[a-z][a-z0-9-]*",s))
    oldflags=flags(saved);current=flags(helptext)
    opts=[("R","--resume"),("S","--session"),("A","--acp"),("E","--experimental-acp"),("I","--interactive"),("P","--prompt-interactive"),("D","--daemon"),("N","--no-daemon"),("F","--input-format"),("L","--list-sessions"),("C","--continue"),("T","--stream-json"),("H","--headless"),("B","--server"),("X","--stdio"),("O","--output-format"),("M","--mcp")]
    code="".join(k for k,v in opts if v in current) or "NONE"
    ver=re.search(r"\b(\d{1,3}\.\d{1,3}\.\d{1,3})\b",version)
    ver=ver[1].replace(".","_") if ver and vrc==0 else "UNKNOWN"
    (run/"WARM_CAPABILITY.json").write_text(json.dumps({"version":ver,"help_exit":hrc,"version_exit":vrc,"help_ms":hms,"version_ms":vms,"known_flags":{v:v in current for _,v in opts},"saved_help_matches":oldflags==current,"help_flags":sorted(current)},indent=2),encoding="utf-8")
    print(f"G21_WARM_V{ver}_H{hrc if hrc>=0 else 999}_MS{hms}_VMS{vms}_F{code}_SAME{int(oldflags==current)}")
except subprocess.TimeoutExpired:print("G21_WARM_LOCAL_PROBE_TIMEOUT")
except Exception as e:
    (run/"probe-error.txt").write_text(type(e).__name__+":"+str(e),encoding="utf-8")
    print("G21_WARM_LOCAL_PROBE_ERROR")
'@
$f=Join-Path $run 'readout.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
$code=if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'G21_READOUT_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

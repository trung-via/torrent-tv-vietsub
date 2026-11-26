# Read-only AGY capability probe; no prompt, browser or provider invocation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\app'
$py=@'
import os,sys,pathlib,subprocess,shutil,re,tempfile
root=pathlib.Path(sys.argv[1])
sys.path[:0]=[str(root/"poc/p2-aisub"),str(root/"poc/p2-sub-discovery")]
try:
    from translator_gateway import preflight_antigravity
    cli=preflight_antigravity()
    ps=shutil.which("pwsh")
    env=dict(os.environ)
    for k in ("GEMINI_API_KEY","GOOGLE_API_KEY","GOOGLE_GEMINI_BASE_URL","AGY_ADC_AUTH","GOOGLE_CLOUD_PROJECT","GOOGLE_CLOUD_QUOTA_PROJECT"):
        env.pop(k,None)
    env["TTV_AGY_CLI"]=str(cli)
    args=[ps,"-NoProfile","-NonInteractive","-Command","& $env:TTV_AGY_CLI --help; exit $LASTEXITCODE"]
    def flags(q):
        ansi=re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
        o=ansi.sub("",q.stdout);e=ansi.sub("",q.stderr)
        pat=r"(?<![\w-])--settings(?![\w-])"
        return "E"+str(int(q.returncode==0))+"R"+str(int(bool(re.search(r"(?m)^\s*--?settings(?:[ =\t]|$)",q.stdout))))+"O"+str(int(bool(re.search(pat,o))))+"S"+str(int(bool(re.search(pat,e))))
    q=subprocess.run(args,env=env,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=20)
    with tempfile.TemporaryDirectory(prefix="ttv-help-") as tmp:
        t=subprocess.run(args,env=env,cwd=tmp,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=20)
    v=subprocess.run([ps,"-NoProfile","-NonInteractive","-Command","& $env:TTV_AGY_CLI --version; exit $LASTEXITCODE"],env=env,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=20)
    ver=re.search(r"(?<!\d)(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?!\d)",v.stdout+"\n"+v.stderr)
    print("HELP_"+flags(q)+"_JOB_"+flags(t)+"_V"+("_".join(ver.groups()) if v.returncode==0 and ver else "UNKNOWN"))
except Exception as e:
    print("HELP_PROBE_"+(type(e).__name__.upper() if type(e).__name__ in {"ValueError","TimeoutExpired","FileNotFoundError","OSError","ImportError","ModuleNotFoundError"} else "OTHER"))
'@
$lines=@(& py -3 -I -B -c $py $root 2>$null)
$code='HELP_PROBE_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^HELP_[A-Z0-9_]{3,80}$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

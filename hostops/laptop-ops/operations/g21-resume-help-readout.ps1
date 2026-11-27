Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('g21-resume-help-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import pathlib,sys,json,re
root,spool,run=map(pathlib.Path,sys.argv[1:4])
source="f124a8cfde6ddaa2978cc85468365786b3eac35a"
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
_,n=prior[0]
d=root/("g21-v31-resume-"+n)
helptext=read(d/"cli-help.txt",262144)
if not helptext:print("G21_HELP_MISSING");sys.exit(0)
helptext=re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]","",helptext)
lines=helptext.splitlines()
selected=[]
for i,line in enumerate(lines):
    if re.search(r"--(?:resume|continue|prompt-interactive|input-format|output-format)(?:[\s=,\[]|$)",line):
        selected.append(line.strip())
        for follow in lines[i+1:i+3]:
            if not follow.strip() or re.search(r"^\s*(?:-\w,?\s*)?--[a-z]",follow):break
            if follow.startswith(" "):selected.append(follow.strip())
            else:break
# Public CLI option descriptions only, bounded and stripped of unexpected paths/URLs.
safe=[]
for line in selected[:24]:
    if len(line)>240 or re.search(r"https?://|[A-Za-z]:\\|[A-Za-z0-9_-]{40,}",line):continue
    if re.fullmatch(r"[A-Za-z0-9 _.,:;()<>/\[\]=\"'|?+*-]+",line):safe.append(line)
if not safe:print("G21_HELP_EMPTY");sys.exit(0)
nonce=sys.argv[4]
if not re.fullmatch("[a-f0-9]{32}",nonce):raise ValueError("NONCE")
doc={"schema":"G21_AGY_HELP_V1","nonce":nonce,"lines":safe}
(run/"AGY_HELP.json").write_text(json.dumps(doc,indent=2),encoding="utf-8")
(spool/"Receipts"/("g21-agy-help-"+nonce+".json")).write_text(json.dumps(doc),encoding="utf-8")
print("G21_HELP_READY")
'@
$f=Join-Path $run 'readout.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run $rq.nonce 2> (Join-Path $run 'python-stderr.txt'))
$code=if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'G21_READOUT_LOCAL_ERROR'}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

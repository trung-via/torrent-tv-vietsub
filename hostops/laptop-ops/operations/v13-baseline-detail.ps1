# Read only the previous exact baseline report and historical claim correspondence.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$report=Join-Path $base ('NativeBrowserTest\v13-baseline-detail-'+$rq.nonce)
New-Item -ItemType Directory -Path $report -ErrorAction Stop|Out-Null
$py=@'
import json,pathlib,re,sys,time
base,spool,report=map(pathlib.Path,sys.argv[1:4])
receipts=[]
for p in (spool/"History").glob("receipt-*.json"):
    v=json.loads(p.read_text(encoding="utf-8-sig"))
    if v.get("source_commit")=="3b47d1bd3d91ac50278c551eeffbd20638d336e2" and v.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",str(v.get("nonce",""))):receipts.append(v["nonce"])
if len(receipts)!=1:raise ValueError("prior receipt")
p=base/"NativeBrowserTest"/("v13-installed-baseline-"+receipts[0])/"baseline.json"
d=json.loads(p.read_text(encoding="utf-8"))
if d["source"]!="e1749ae60515731168bd554fe12a05031f50d040" or d["base"]!="5e3ce11f76828daa2d5aa72cacc7514e74dc152e" or len(d["modules"])!=84:raise ValueError("baseline")
modules=sorted(d["modules"])
bad="".join(d["modules"][n]+str(i).zfill(2) for i,n in enumerate(modules) if d["modules"][n] in ("D","M"))
inbox=base/"OwnerBridge/inbox"
blocked={p.name[6:-8]:p for p in inbox.glob("event-*.blocked")}
claims={p.name[6:]:p for p in inbox.glob("claim-*") if not (inbox/("event-"+p.name[6:]+".done")).is_file() and not (inbox/("event-"+p.name[6:]+".review")).is_file()}
matched=set(blocked)&set(claims)
old=sum(time.time()-p.stat().st_mtime>86400 for p in blocked.values())
# Only ages and correspondence; no inference about provider effects.
(report/"detail.json").write_text(json.dumps({"baseline_report":d,"matched_blocked":len(matched),"unmatched_claims":len(set(claims)-set(blocked)),"older_than_day":old}),encoding="utf-8")
print("V13_DETAIL_"+bad+"_B"+str(len(blocked))+"C"+str(len(claims))+"P"+str(len(matched))+"U"+str(len(set(claims)-set(blocked)))+"A"+str(old))
'@
$file=Join-Path $report 'detail.py'
[IO.File]::WriteAllText($file,$py,[Text.UTF8Encoding]::new($false))
$lines=@(& py -3 -I -B $file $base $spool $report 2> (Join-Path $report 'stderr.txt'))
$code='V13_DETAIL_PRIVATE_ERROR'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^V13_DETAIL_([DM]\d{2})+_B\d+C\d+P\d+U\d+A\d+$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

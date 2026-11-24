# TR-TTV.04a exact prior smoke readout, no provider or browser actions.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-04b-readout-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,os,json,re
root,run=map(pathlib.Path,sys.argv[1:])
def read(p):
    if not p.is_file() or p.is_symlink() or p.stat().st_size>16777216:return ""
    return p.read_text(encoding="utf-8-sig",errors="replace")
def probe():
    history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
    hits=[]
    for f in history.glob("receipt-*.json"):
        try:
            q=json.loads(read(f))
            if q.get("source_commit")=="36856caeae0fc30ab8e09d5ecda97aff2a50791a" and q.get("operation")=="agy-native-browser-readout-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):hits.append(q["nonce"])
        except (ValueError,TypeError,OSError):pass
    if len(hits)!=1:return "TR04AR_PRIOR_HOLD"
    p=root/("tr-ttv-04b-teacher-"+hits[0])
    report=json.loads(read(p/"BRAIN_TEACHER_REPORT.json"))
    acq=report.get("verified_acquisition",{})
    rr=report.get("reported_result",{})
    sel=report.get("selection",{})
    recipe=report.get("teacher_recipe",{})
    final=report.get("final_response",[])
    raw=read(p/"agy-stdout.jsonl")
    err=read(p/"agy-stderr.txt")
    helptext=read(p/"cli-help.txt")
    status=acq.get("verified_status","UNCLASSIFIED")
    codes={"DOWNLOADED":"DL","ACCESS_DENIED":"DENY","AUTH_REQUIRED":"AUTH","NO_MATCH":"NM","DOWNLOAD_FAILED":"DF","CDP_FAILED":"CDP","OTHER":"OTHER","UNCLASSIFIED":"UNK"}
    if status not in codes:status="UNCLASSIFIED"
    # Only bounded status/counts go to public receipts. Full report stays private.
    files=int(acq.get("files",0));cues=int(acq.get("cues",0))
    recipeok=int(isinstance(recipe,dict) and bool(recipe))
    hasselection=int(isinstance(sel,dict) and bool(sel))
    resultok=int(isinstance(rr,dict) and bool(rr))
    finalok=int(isinstance(final,list) and any(isinstance(v,str) and v.strip() for v in final))
    ev=int(report.get("event_count",0));elapsed=int(report.get("elapsed_seconds",0))
    # Read only exact CLI help line and nearby descriptions; no provider call.
    ls=helptext.splitlines()
    opts=[]
    for n,line in enumerate(ls):
        if "--print-timeout" in line:
            opts.append("\n".join(ls[max(0,n-1):n+4]))
    opt="\n".join(opts)
    unlimited=int(bool(re.search(r"(?i)(?:0|zero|none|unlimited|infinite|disable|no timeout).{0,50}(?:timeout|disable|unlimited|infinite)|(?:timeout|disable).{0,50}(?:0|zero|none|unlimited|infinite)",opt)))
    deny=int(bool(re.search(r"permission check failed|user denied permission|auto-denied|permission denied",raw+"\n"+err,re.I)))
    timed=int(bool(acq.get("cli_timed_out")) or bool(re.search(r"print.timeout|response timeout|deadline exceeded",err,re.I)))
    # Report the actual prior run outcome even when shared-config drift suppressed it.
    (run/"result-summary.json").write_text(json.dumps({"status":status,"verified_acquisition":acq,"recipe_present":bool(recipeok),"selection_present":bool(hasselection),"result_present":bool(resultok),"final_present":bool(finalok),"cli_help_timeout":opts,"prior_global_config_drift":True,"permission_denial":bool(deny)},ensure_ascii=True,indent=2),encoding="utf-8")
    return f"TR04R_{codes[status]}_F{files}C{min(cues,99999)}R{recipeok}S{hasselection}J{resultok}A{finalok}N{min(ev,999)}T{elapsed}D{deny}X{timed}H{unlimited}"

try:print(probe())
except Exception as e:
    (run/"readout-error.txt").write_text(type(e).__name__+": "+str(e),encoding="utf-8")
    print("TR04AR_LOCAL_ERROR")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $run 2> (Join-Path $run 'python-stderr.txt'))
$code='TR04AR_LOCAL_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

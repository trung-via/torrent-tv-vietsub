# Read only the exact completed Student V2 report and copied artifact. No provider call.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File|ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
   if($r.source_commit -ceq 'c5f56e07dfc71b1f778e346a2ba6de16508810c0' -and $r.operation -ceq 'agy-native-browser-readout-1124' -and $r.result -ceq 'SUCCESS' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='TR05QA_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $run=Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\NativeBrowserTest\tr-ttv-05b-hailmary-v2-'+$prior[0].nonce)
 $owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
 $py=@'
import sys,pathlib,json,hashlib,re,zipfile
run,owner=map(pathlib.Path,sys.argv[1:])
def main():
    p=run/"BRAIN_STUDENT_REPORT.json"
    if not p.is_file() or p.is_symlink() or not 0<p.stat().st_size<=16000000:return "TR05QA_REPORT_MISSING"
    r=json.loads(p.read_text(encoding="utf-8"))
    # V2 writes the child-only TTV_SOURCE_SHA into its subprocess env, but reads the parent env for the report.
    # The archived exact-source SUCCESS receipt and nonce-specific directory are the primary binding.
    source=r.get("source_commit")
    if source not in ("","c5f56e07dfc71b1f778e346a2ba6de16508810c0"):return "TR05QA_SOURCE_FIELD_MISMATCH"
    if r.get("model")!="gemini-4-hydrogen-low":return "TR05QA_MODEL_MISMATCH"
    if r.get("recipe_version")!="V2":return "TR05QA_RECIPE_MISMATCH"
    arts=r.get("artifacts",[])
    if len(arts)!=1:return "TR06_PRIOR_ARTIFACT_NOT_UNIQUE"
    sid=str(arts[0].get("candidate_id",""))
    if not re.fullmatch(r"[1-9]\d{3,10}",sid):return "TR06_CANDIDATE_UNBOUND"
    names={"list_pages":"L","select_page":"P","navigate_page":"N","take_snapshot":"S","click":"C","fill":"F","press_key":"K","wait_for":"W","evaluate_script":"E"}
    seq="".join(names.get(x,"X") for x in r.get("tool_names",[]))[:20]
    outputs=r.get("tool_outcomes",[])
    linked=[str(v.get("output","")) for v in outputs if isinstance(v,dict) and re.search(r"(?<!\d)"+re.escape(sid)+r"(?!\d)",str(v.get("output","")))]
    text="\n".join(linked)
    # Conservative scalar evidence; no raw content, media ID or URL leaves the host.
    rel=int(bool(re.search(r"project[ ._-]+hail[ ._-]+mary[ ._-]+2026[ ._-]+webrip[ ._-]+720p[ ._-]+new[ ._-]+team",text,re.I)))
    group=int(bool(re.search(r"new[ ._-]+team",text,re.I)))
    web=int(bool(re.search(r"web[ ._-]*(?:rip|dl)",text,re.I)))
    fps=int(bool(re.search(r"\b(?:23\.976|24\.000|25\.000|29\.970|30\.000)\b|\b(?:fps|frame rate)\b",text,re.I)))
    final="\n".join(v for v in r.get("final_response",[]) if isinstance(v,str))
    claims=int(bool(re.search(r"\b(?:downloaded_reported|downloaded|download successful)\b",final,re.I)))
    uncertain=int(bool(re.search(r"not (?:verified|confirmed|available|provided|known)|unverified|unknown|not supplied|cannot confirm",final,re.I)))
    # Count model-event errors, not arbitrary words in webpage output.
    errors=sum(bool(v.get("error")) for v in outputs if isinstance(v,dict))
    return f"TR06_SEQ{seq}_L{len(linked)}E{rel}G{group}W{web}F{fps}C{claims}U{uncertain}X{errors}"

try: print(main())
except Exception: print("TR05QA_PRIVATE_ERROR")
'@
 $f=Join-Path $env:TEMP ('ttv-student-v2-qa-'+[Guid]::NewGuid().ToString('N')+'.py')
 try{
  [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
  $out=@(& py -3 -I -B $f $run $owner 2>$null)
  if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){$code=[string]$out[0]}else{$code='TR05QA_READ_ERROR'}
 }finally{Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

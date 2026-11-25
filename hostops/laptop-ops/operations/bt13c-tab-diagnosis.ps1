# BT13R: read-only last acquisition error and original CDP target state.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt13c-tab-diagnosis-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,json,re,hashlib,zipfile,html,collections,difflib,statistics
root,spool=map(pathlib.Path,sys.argv[1:3])
def obj(p):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size<16777216
    return json.loads(p.read_text(encoding="utf-8-sig"))
import urllib.request,urllib.parse
run=pathlib.Path(sys.argv[3])
def main():
    nonce="4b83a89c3eed4416bcdea0eba4b847df"
    source="76cf5a0c727dad4217ffca1fc82615cdd83ff2d2"
    prior=root/("bt13-hydrogen-subtitlecat-"+nonce)
    report=obj(prior/"BRAIN_TEACHER_REPORT.json")
    binding=obj(prior/"task-binding.json")
    assert report["source_commit"]==source and report["provider"]=="SubtitleCat" and report["artifacts"]==[]
    out=report["tool_outcomes"]
    errors=[x for x in out if x.get("error")]
    err=json.dumps(errors[-1],ensure_ascii=True) if errors else ""
    # Classify exact error without exposing private content.
    patterns=[("CLOSED",r"target closed|session closed|page (?:has been |was |is )?closed|target page, context or browser has been closed|no target with given id|page not found|no page with|detached target|target.*destroyed"),("CONTEXT",r"execution context.*destroyed|cannot find context|context.*lost"),("TIMEOUT",r"timed? ?out|timeout"),("DENIED",r"denied|forbidden|captcha"),("JS",r"TypeError|ReferenceError|SyntaxError|javascript|evaluation failed")]
    category=next((k for k,p in patterns if re.search(p,err,re.I)),"OTHER" if err else "NONE")
    browser=0;target=0;provider=0
    try:
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open("http://127.0.0.1:9555/json/list",timeout=3) as f: tabs=json.load(f)
        browser=1
        target=int(any(t.get("id")==binding["cdp_target_id"] for t in tabs if t.get("type")=="page"))
        provider=sum(urllib.parse.urlsplit(t.get("url","")).hostname in ("subtitlecat.com","www.subtitlecat.com") for t in tabs if t.get("type")=="page")
    except Exception:pass
    history=report.get("downloads",[])
    physical=report.get("physical_files",[])
    # Existing report only: no unrelated browser history or directory scan.
    result={"schema":"BT13C_TAB_DIAG_V1","prior_nonce":nonce,"source":source,"last_error_category":category,"last_error_private":errors[-1] if errors else None,"cdp_endpoint_reachable":bool(browser),"original_target_present":bool(target),"subtitlecat_tabs":provider,"original_report_download_rows":len(history),"original_report_physical_candidates":len(physical),"note":"Current target absence is not itself proof of time or cause of closure. No browser change or retry."}
    (run/"BRAIN_TAB_DIAG.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    print(f"BT13R_{category}_B{browser}_T{target}_P{provider}_D{len(history)}_F{len(physical)}")
try:main()
except Exception as e:
    (run/"private-error-type.txt").write_text(type(e).__name__,encoding="utf-8")
    print("BT13R_HOLD_READ_ERROR")
'@
$f=Join-Path $run 'compare.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT13R_HOLD_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT13R_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

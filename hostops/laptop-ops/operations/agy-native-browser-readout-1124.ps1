# TR-TTV.05b exact Student report recovery, no provider or browser actions.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('tr-ttv-05b-hailmary-recovery-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,os,json,re,sqlite3,zipfile,urllib.parse,hashlib
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
            if q.get("source_commit")=="9a78629a52f72b15db652c8948092301e313bee3" and q.get("operation")=="agy-native-browser-readout-1124" and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):hits.append(q["nonce"])
        except (ValueError,TypeError,OSError):pass
    if len(hits)!=1:return "TR04AR_PRIOR_HOLD"
    p=root/("tr-ttv-05b-hailmary-"+hits[0])
    report=json.loads(read(p/"BRAIN_STUDENT_REPORT.json"))
    raw=read(p/"agy-stdout.jsonl");err=read(p/"agy-stderr.txt")
    records=[]
    for line in raw.splitlines():
        try:
            x=json.loads(line)
            if isinstance(x,dict):records.append(x)
        except ValueError:pass
    finals=[];tools=[];readcalls=0;errors=0
    for i,e in enumerate(records):
        step=e.get("step_update",{})
        if isinstance(step,dict):
            info=step.get("tool_info",{})
            if isinstance(info,dict):
                params=info.get("parameters",{})
                if not isinstance(params,dict):params={}
                if step.get("tool_name")=="read_file" and "output" in info:readcalls+=1
                if step.get("tool_name")=="call_mcp_tool" and ("output" in info or "error" in info):
                    tools.append({"event":i,"name":params.get("ToolName"),"server":params.get("ServerName",params.get("Server")),"output":info.get("output"),"error":info.get("error")})
                    if info.get("error"):errors+=1
        res=e.get("result")
        if e.get("event")=="result" and isinstance(res,dict) and isinstance(res.get("response"),str):finals.append(res["response"])
    text="\n".join(finals)
    status="UNK"
    for match in re.finditer(r"\{",text):
        try:
            obj,_=json.JSONDecoder().raw_decode(text[match.start():])
            if not isinstance(obj,dict):continue
            v=obj.get("result",obj)
            if isinstance(v,dict) and isinstance(v.get("status"),str):
                label=v["status"].upper()
                code={"DOWNLOADED":"DL","SUCCESS":"OK","NO_MATCH":"NM","ACCESS_DENIED":"DENY","AUTH_REQUIRED":"AUTH","DOWNLOAD_FAILED":"DF","CDP_FAILED":"CDP","ISOLATION_UNVERIFIED":"ISO","OTHER":"OTHER","NOT_FOUND":"NF","NO_SUBTITLE_FOUND":"NF"}
                if label in code:status=code[label];break
        except ValueError:pass
    if status=="UNK":
        for pat,code in [(r"\bNO_MATCH\b","NM"),(r"\bDOWNLOAD_FAILED\b","DF"),(r"\bACCESS_DENIED\b","DENY"),(r"\bAUTH_REQUIRED\b","AUTH"),(r"\bCDP_FAILED\b","CDP"),(r"\bDOWNLOADED\b","DL"),(r"\bNOT_FOUND\b","NF")]:
            if re.search(pat,text,re.I):status=code;break
    local=p/"browser-downloads";physical=[]
    for f in local.iterdir() if local.is_dir() else []:
        if not f.is_file() or f.is_symlink() or f.suffix.lower() not in (".srt",".zip") or not 0<f.stat().st_size<=10000000:continue
        try:
            if f.suffix.lower()==".srt":blobs=[f.read_bytes()]
            else:
                with zipfile.ZipFile(f) as z:blobs=[z.read(v) for v in z.infolist()[:100] if v.filename.lower().endswith(".srt") and 0<v.file_size<=2000000 and not v.flag_bits&1]
            c=max((len(re.findall(rb"(?m)^\d{2}:\d{2}:\d{2}[,.]\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}[,.]\d{3}",v)) for v in blobs),default=0)
            physical.append({"filename":f.name,"bytes":f.stat().st_size,"cues":c})
        except (OSError,ValueError,RuntimeError,zipfile.BadZipFile):pass
    # Extract only public-facing response and tool outcomes; no private reasoning.
    summary={"source_commit":"9a78629a52f72b15db652c8948092301e313bee3","events":len(records),"final_response":finals,"tool_outcomes":tools,"read_file_calls":readcalls,"tool_errors":errors,"physical_files_now":physical,"original_report":report,"stderr":err}
    markdown="# Project Hail Mary - Hydrogen Low Student Report\n\n## Final response\n\n"+(text or "[No response]")+"\n\n## Tool outcomes and evidence\n\n"+json.dumps(summary,ensure_ascii=False,indent=2)
    (run/"BRAIN_STUDENT_RECOVERY.md").write_text(markdown,encoding="utf-8")
    target=pathlib.Path.home()/"Downloads"/("TTV_Project_Hail_Mary_Student_Report_"+hits[0][:8]+".md")
    exported=0
    try:
        with target.open("x",encoding="utf-8") as f:f.write(markdown)
        exported=1
    except OSError:pass
    n=sum(v["cues"]>0 for v in physical)
    c=max((v["cues"] for v in physical),default=0)
    snap=sum(x["name"]=="take_snapshot" for x in tools)
    dom=sum(x["name"]=="evaluate_script" for x in tools)
    return f"TR05R_{status}_N{len(records)}A{len(text)}F{n}C{c}K{len(tools)}L{readcalls}S{snap}J{dom}X{errors}E{exported}"

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
$listeners=@(Get-NetTCPConnection -LocalPort 9555 -State Listen -ErrorAction SilentlyContinue)
$pidset=@($listeners|Select-Object -ExpandProperty OwningProcess -Unique)
$ready=0
if($pidset.Count -eq 1){
 $p=Get-CimInstance Win32_Process -Filter ("ProcessId="+$pidset[0])
 $profile=Join-Path $root 'CDP9555Profile'
 if($p -and $p.Name -eq 'chrome.exe' -and $p.CommandLine -and $p.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $p.CommandLine -match '(?:^|\s|")--remote-debugging-port=9555(?:\s|"|\z)' -and @($listeners|Where-Object {$_.LocalAddress -notin @('127.0.0.1','::1')}).Count -eq 0){$ready=1}
}
$code=$code+'_B'+$ready
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

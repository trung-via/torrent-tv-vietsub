# Ask AGY for a diagnosis of its exact failed local helper attempts.
# No shell/browser/provider actions requested; no settings or permission changes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('agy-rule-audit-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import sys,pathlib,os,json,re,subprocess
owner,run=map(pathlib.Path,sys.argv[1:])
sys.path.insert(0,str(owner/"app/poc/p2-aisub"))
from translator_gateway import preflight_antigravity
def read(p):
    try:
        if p.is_file() and not p.is_symlink() and p.stat().st_size<=4194304:return p.read_text(encoding="utf-8-sig",errors="replace")
    except OSError:pass
    return ""
history=pathlib.Path(os.environ["ProgramData"])/"TorrentTVVietsub"/"LaptopHostOps"/"History"
targets=[("1c6600358d1bc30e9228c1ec2c0b8027f1d2e8c6","agy-browser-headless-control-1124","agy-cdp9555-mcp-stdio-"),("edc92c5fe50bdd5cc6da8fa9fd82b5325c795ec6","agy-native-browser-readout-1124","agy-helper-local-"),("1c3b7c3887a29cf83f33b84360da6cb6fbc2e9f1","agy-native-browser-readout-1124","agy-helper-absolute-")]
records=[]
for sha,op,prefix in targets:
    matches=[]
    for f in history.glob("receipt-*.json"):
        try:
            q=json.loads(read(f))
            if q.get("source_commit")==sha and q.get("operation")==op and q.get("result")=="SUCCESS" and re.fullmatch(r"[a-f0-9]{32}",q.get("nonce","")):matches.append(q["nonce"])
        except (ValueError,TypeError):pass
    if len(matches)==1:
        p=run.parent/(prefix+matches[0])
        raw=read(p/"agy-stdout.jsonl")
        # Inspect error events separately from prose and prompts; no raw content exported.
        errs=[read(p/"agy-stderr.txt"),read(p/"mcp-stderr.txt")]
        for line in raw.splitlines():
            try:x=json.loads(line)
            except ValueError:continue
            def scan(v,depth=0):
                if depth>12:return
                if isinstance(v,dict):
                    kind=str(v.get("event",v.get("type",""))).lower()
                    if kind in ("tool_error","error","assistant_error","tool_result","tool_response","function_response"):
                        for k in ("error","output","result","content","message"):
                            if k in v:errs.append(json.dumps(v[k]))
                    for k,val in v.items():
                        if k not in ("prompt","input","arguments","command","system_prompt"):scan(val,depth+1)
                elif isinstance(v,list):
                    for val in v:scan(val,depth+1)
            scan(x)
        records.append("\n".join(errs))
log="\n".join(records)
relative=int(bool(re.search(r"relative paths?.{0,100}(?:not supported|not allowed|invalid|absolute|required)|(?:invalid|unsupported).{0,70}relative paths?",log,re.I)))
denied=int(bool(re.search(r"permission denied|access denied|sandbox.{0,80}(?:denied|blocked)|approval required|not permitted",log,re.I)))
# Discover documented CLI options without starting a model.
cli=preflight_antigravity()
try:
    p=subprocess.run([cli,"--help"],cwd=run,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=15,check=False)
    helptext=p.stdout+"\n"+p.stderr
    (run/"cli-help.txt").write_text(helptext,encoding="utf-8")
except (OSError,subprocess.TimeoutExpired):helptext=""
help_sandbox=int(bool(re.search(r"--sandbox\b",helptext)))
help_config=int(bool(re.search(r"(?im)^\s*(?:config|settings|sandbox)\b",helptext)))
# Inspect only named application configuration files; never auth, cookies, tokens, or account data.
home=pathlib.Path.home()
app=pathlib.Path(os.environ.get("APPDATA",str(home)))
local=pathlib.Path(os.environ.get("LOCALAPPDATA",str(home)))
files=[home/".gemini"/"settings.json",home/".gemini"/"antigravity"/"settings.json",home/".gemini"/"antigravity-cli"/"settings.json",home/".antigravity"/"settings.json",home/".agy"/"settings.json",home/".config"/"agy"/"settings.json",home/".config"/"antigravity"/"settings.json",app/"Antigravity"/"User"/"settings.json",app/"agy"/"settings.json",local/"Antigravity"/"settings.json"]
count=0;rules=0;rel=0;private=[]
def walk(v,trail,active=False):
    global rules,rel
    if isinstance(v,dict):
        for k,x in v.items():
            if re.search(r"token|secret|password|credential|auth|cookie|account|api.?key",k,re.I):continue
            nxt=active or bool(re.search(r"sandbox|permissions|allowlist|denylist|allowedPaths|deniedPaths",k,re.I))
            if nxt and isinstance(x,(dict,list)):rules+=1
            walk(x,trail+[k],nxt)
    elif isinstance(v,list) and active:
        for x in v:
            if isinstance(x,str) and re.match(r"^(?:\.\.?[/\\]|~[/\\])",x):rel+=1
            elif isinstance(x,dict):walk(x,trail,active)
for i,f in enumerate(files):
    raw=read(f)
    if not raw:continue
    try:v=json.loads(raw)
    except ValueError:continue
    if not isinstance(v,dict):continue
    count+=1;before=(rules,rel);walk(v,[])
    private.append({"candidate_index":i,"sandbox_rule_nodes":rules-before[0],"relative_path_entries":rel-before[1]})
(run/"config-audit-private.json").write_text(json.dumps({"receipt_logs":len(records),"explicit_relative_error":relative,"explicit_denial":denied,"configs":private}),encoding="utf-8")
print(f"AGYRULE_L{len(records)}_D{denied}_R{relative}_H{help_sandbox}C{help_config}_J{count}_S{min(rules,99)}_P{min(rel,99)}")
'@
$f=Join-Path $run 'control.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $owner $run 2> (Join-Path $run 'python-stderr.txt'))
$code='AGYASK_LOCAL_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,65}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

# Approved G1 full-film size hotfix. Exact 12 Python modules, backups and one proven event requeue.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REQUEST_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$py=@'
import hashlib, json, pathlib, re, sys, time
root=pathlib.Path(sys.argv[1]); base=root.parent; inbox=root/"inbox"
sys.path[:0]=[str(root/"app/poc"/p) for p in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger")]
from owner_session_bridge import _authorized_selection, _BACKGROUND_SCHEMA, _SESSION_SCHEMA
from cached_en_direct_handoff import CachedEnReceipt,prepare_local_translation_source
from automatic_lean120_worker import AutomaticLean120Worker,_json_bytes
from lean120_api import load_profile
from progressive_handoff import ProgressiveSubtitleSession
from dual_subtitle_catalog import DualSubtitleCatalog
from cue_pipeline import apply_translations
def read(p,cap=2*1024*1024):
    if p.is_symlink() or not p.is_file() or not 0<p.stat().st_size<=cap:raise ValueError()
    return json.loads(p.read_bytes())
def require(ok):
    if not ok:raise ValueError()


try:
    install=1795735806
    candidates=[p for p in inbox.glob("event-*") if p.is_file() and not p.is_symlink() and p.suffix in (".json",".done",".blocked",".review",".deferred") and p.stat().st_mtime>=install]
    if not candidates:
        print("G1_BENCH_NO_NEW_EVENT");sys.exit(0)
    event=max(candidates,key=lambda p:p.stat().st_mtime)
    ev=read(event,4096);eid=ev["event_id"];fp=ev["source_fingerprint"]
    require(re.fullmatch(r"[a-f0-9]{32}",eid) and re.fullmatch(r"[a-f0-9]{64}",fp))
    require(event.stem=="event-"+eid)
    status=event.suffix[1:].upper()
    claim=inbox/("claim-"+eid)
    start=int(event.stat().st_mtime)
    claim_delta=int(claim.stat().st_mtime-start) if claim.is_file() else -1
    cache=base/"subtitle-trials";state=base/"P2/auto-lean120-state"
    indexes=[cache/(".dual-source-native-v13-"+fp+"-ai_en.json"),cache/(".dual-source-"+fp+"-ai_en.json")]
    index=next((p for p in indexes if p.is_file()),None)
    if index is None:
        print(f"G1_BENCH_{status}_T{start}_C{len(candidates)}_EN0");sys.exit(0)
    receipt=DualSubtitleCatalog(cache)._file(read(index,512),"ai_en")
    source=prepare_local_translation_source(CachedEnReceipt(receipt.file,receipt.sha256,receipt.cues),private_root=cache)
    worker=AutomaticLean120Worker(state_root=state,profile=load_profile(root/"app/poc/p2-aisub/translator_profile.json"),glossary={},first_window_cues=50,preserve_hydrogen_jobs=True)
    folder=state/worker.job_fingerprint(source)
    session=worker.progressive_session(source)
    n=0;rev=None
    for w in session.windows:
        p=folder/f"batch-{w.number:04d}.json"
        if not p.is_file():break
        d=read(p);require(d["job"]==folder.name and d["version"]==w.number)
        rev=session.commit(w,{v["id"]:v["vi"] for v in d["translations"]},expected_version=w.number-1,source_sha256=source.source_sha256,media_key=source.media_key)
        require(rev.sha256==d["payload_sha256"]);n+=1
    first=folder/"batch-0001.json"
    en=int(index.stat().st_mtime-start)
    b=int(first.stat().st_mtime-start) if first.is_file() else None
    final=folder/"vi-final.srt"
    f=int(bool(rev and rev.complete and final.is_file() and hashlib.sha256(final.read_bytes()).hexdigest()==rev.sha256))
    def delta(x):return "X" if x is None else ("N"+str(-x) if x<0 else str(x))
    print(f"G1_BENCH_{status}_T{start}_E{delta(en)}_V{delta(b)}_B{n}T{len(session.windows)}_C{source.cue_count}_F{f}")
except Exception:
    print("G1_BENCH_READ_HOLD")
'@
$lines=@(& py -3 -I -B -c $py $root 2>$null)
$code='G1_BENCH_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^G1_BENCH_[A-Z0-9_]{3,75}$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

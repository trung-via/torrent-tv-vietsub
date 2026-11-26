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
    health=read(root/"agent-health.json",512)
    age=int(time.time()-health["observed_utc_epoch"])
    fresh=health["state"]=="READY" and 0<=age<=30
    target="347fc1e23e9b0b24fa8609caf6b3f91eca0f65cca78a432bbd3fc49dfd899f4f"
    events=[p for p in inbox.glob("event-*") if hashlib.sha256(p.stem.removeprefix("event-").encode()).hexdigest()==target]
    backups=[]
    for p in (root/"staged-releases").glob("flat-limit-*/blocked-event.backup"):
        ev=read(p,4096)
        if hashlib.sha256(ev["event_id"].encode()).hexdigest()==target:backups.append(ev)
    require(len(backups)==1)
    ev=backups[0];eid=ev["event_id"];fp=ev["source_fingerprint"]
    status=events[0].suffix.removeprefix(".").upper() if len(events)==1 else "UNKNOWN"
    if status not in ("JSON","DONE","BLOCKED","REVIEW","DEFERRED","UNKNOWN"):status="OTHER"
    cache=base/"subtitle-trials";state=base/"P2/auto-lean120-state"
    indexes=[cache/(".dual-source-native-v13-"+fp+"-ai_en.json"),cache/(".dual-source-"+fp+"-ai_en.json")]
    receipt=DualSubtitleCatalog(cache)._file(read(next(p for p in indexes if p.is_file()),512),"ai_en")
    source=prepare_local_translation_source(CachedEnReceipt(receipt.file,receipt.sha256,receipt.cues),private_root=cache)
    worker=AutomaticLean120Worker(state_root=state,profile=load_profile(root/"app/poc/p2-aisub/translator_profile.json"),glossary={},first_window_cues=50,preserve_hydrogen_jobs=True)
    job=worker.job_fingerprint(source); folder=state/job;session=worker.progressive_session(source)
    n=0;rev=None
    for w in session.windows:
        p=folder/f"batch-{w.number:04d}.json"
        if not p.is_file():break
        d=read(p)
        require(d["job"]==job and d["version"]==w.number and [v["id"] for v in d["translations"]]==list(w.ids))
        rev=session.commit(w,{v["id"]:v["vi"] for v in d["translations"]},expected_version=w.number-1,source_sha256=source.source_sha256,media_key=source.media_key)
        require(rev.sha256==d["payload_sha256"]);n+=1
    final=folder/"vi-final.srt"
    complete=bool(rev and rev.complete and final.is_file() and not final.is_symlink() and final.stat().st_size<=4194304 and hashlib.sha256(final.read_bytes()).hexdigest()==rev.sha256)
    inflight=len(list(folder.glob("batch-*.inflight")))
    results=len(list(folder.glob("result-*.json")))
    log=root/"diagnostics/owner-full.log"
    reason="NONE"
    if log.is_file():
        with log.open("rb") as f:
            f.seek(max(0,log.stat().st_size-8*1024*1024));tail=f.read().decode("utf-8","replace")
        # Only return known constant error/status labels, not raw log or media.
        blocks=tail.split("OWNER_FULL_TRACE")
        relevant=[b for b in blocks if eid in b.splitlines()[0]]
        if relevant:
            last=relevant[-1]
            codes=re.findall(r"(?:ValueError|RuntimeError|P3ReadyRejected|SubtitleApiError|V3IdentityError|AgyEnglishUnavailable): ([A-Z][A-Z0-9_]{3,70})\b",last)
            if codes:reason=codes[-1]
        if reason=="NONE":
            for line in reversed(tail.splitlines()):
                if "OWNER_BRIDGE_BLOCK_REASON=" in line:
                    m=re.search(r"OWNER_BRIDGE_BLOCK_REASON=([A-Z][A-Z0-9_]{3,70})\b",line)
                    if m:reason=m[1];break
    print(f"LIMIT_LIVE_{status}_B{n}T{len(session.windows)}_F{int(complete)}_I{inflight}R{results}_H{int(fresh)}")
    print("LIMIT_REASON_"+reason)
except Exception:
    print("LIMIT_LIVE_HOLD")
    print("LIMIT_REASON_READ_FAILED")

'@
$lines=@(& py -3 -I -B -c $py $root 2>$null)
$code='LIMIT_LIVE_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 2 -and [string]$lines[0] -cmatch '^LIMIT_LIVE_[A-Z0-9_]{3,60}$' -and [string]$lines[1] -cmatch '^LIMIT_REASON_[A-Z0-9_]{3,74}$'){
 $code=[string]$lines[0]
 # Combine within registered receipt length; private reason can be obtained in second audit if needed.
 if($code.Length+1+([string]$lines[1]).Length-13 -le 90){$code+='_'+([string]$lines[1]).Substring(13)}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

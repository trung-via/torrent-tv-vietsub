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
    target=1795736867
    events=[p for p in inbox.glob("event-*") if p.is_file() and abs(p.stat().st_mtime-target)<1]
    require(len(events)==1)
    ev=read(events[0],4096);fp=ev["source_fingerprint"]
    coords=_authorized_selection(ev["authorized_selection"],fp,ev["tv_session_id"])
    from matcher import Media
    from agy_v13_native_producer import _job
    media=Media(coords["server_id"],coords["torrent_hash"],coords["file_index"],ev["selected_video_filename"])
    cache=base/"subtitle-trials";run=_job(cache,media)
    started=read(run/"provider.started.json",4096)["started"]
    index=cache/(".dual-source-native-v13-"+fp+"-ai_en.json")
    require(index.is_file() and (run/"verified.json").is_file())
    out=run/"agy-stdout.jsonl"
    require(out.is_file() and 0<out.stat().st_size<=16*1024*1024)
    outcomes=read(run/"evidence.json",16*1024*1024)["outcomes"]
    from collections import Counter
    count=Counter(row["tool"] for row in outcomes)
    # Report only timings and counts, not prompt, media, stdout or DOM.
    pre=round(started-events[0].stat().st_mtime)
    cli=round(out.stat().st_mtime-started)
    post=round(index.stat().st_mtime-out.stat().st_mtime)
    require(min(pre,cli,post)>=-1)
    print(f"G1_BENCH_PRE{max(0,pre)}_CLI{max(0,cli)}_POST{max(0,post)}_N{len(outcomes)}_E{count['evaluate_script']}_S{count['take_snapshot']}_NAV{count['navigate_page']}_L{count['list_pages']}")
except Exception:
    print("G1_BENCH_READ_HOLD")
'@
$lines=@(& py -3 -I -B -c $py $root 2>$null)
$code='G1_BENCH_READ_UNAVAILABLE'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^G1_BENCH_[A-Z0-9_]{3,75}$'){$code=[string]$lines[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

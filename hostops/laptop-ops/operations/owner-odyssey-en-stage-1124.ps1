# Owner approved one exact film EN staging, no provider, no VI reset or TV activation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'ODYSSEY_OWNER_CONTEXT_REQUIRED'}
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner=Join-Path $base 'OwnerBridge'
$cache=Join-Path $base 'subtitle-trials'
$state=Join-Path $base 'P2\auto-lean120-state'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$src='C:\TOOL\TorrentTV-Runner\_work\torrent-tv-vietsub\_omp-fast-cache\odyssey-english-2026\The.Odyssey.2026.1080p.AMZN.WEB-DL.DDP5.1.H.264-KyoGo.en.srt'
$py=@'
import pathlib, sys, json, hashlib, re
owner,cache,state,src=map(pathlib.Path,sys.argv[1:5])
app=owner/"app/poc"
sys.path[:0]=[str(app/"p2-sub-discovery"),str(app/"p2-aisub"),str(app/"p3-vietsub-trigger")]
from matcher import Media, parse_release
from owner_session_bridge import _authorized_selection
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader
from owner_selected_file_resolver import _one_basename
from brain_english_inbox import stage_brain_english, acquire_brain_english, _content
from agy_opensubtitles_acquisition import _validate_source
from assumed_source_handoff import AssumedEnglishSubtitle
from automatic_lean120_worker import _job_fingerprint
from lean120_api import ModelProfile
release="The.Odyssey.2026.1080p.AMZN.WEB-DL.DDP5.1.H.264-KyoGo"
page="https://www.opensubtitles.org/en/subtitles/14190981/the-odyssey-en"
expected="d04a47b307ef6618ad8c8de406ec0dfcfba8b495509c32a3b6fbf76b40185932"
def require(v,msg):
    if not v: raise ValueError(msg)
def read(p,limit=32768):
    require(p.is_file() and not p.is_symlink() and p.stat().st_size<=limit,"ODYSSEY_LOCAL_RECEIPT_INVALID")
    return json.loads(p.read_text("utf-8"))
def main():
    require(src.is_file() and not src.is_symlink() and src.stat().st_size<=500000,"ODYSSEY_RUNNER_STAGE_UNAVAILABLE")
    require(_content(src.read_bytes())==(expected,2009),"ODYSSEY_EN_QA_FAILED")
    policy=read(owner/"p3-p4-policy.json")
    cfg=OwnerLocalTorrServer(policy["profile_id"],policy["torrserver_port"])
    reader=OwnerTorrServerReader(cfg)
    found={}
    # Only existing authenticated V4 selections, never synthesize a TV event.
    for p in (owner/"inbox").iterdir():
        if not re.fullmatch(r"event-[a-f0-9]{32}\.(done|blocked|review)",p.name): continue
        row=read(p)
        if row.get("schema")!="TTV-OWNER-VIDEO-EVENT-V4": continue
        name=row.get("selected_video_filename","")
        r=parse_release(name)
        if r.title!="the odyssey" or r.year!=2026 or r.group!="kyogo": continue
        fp=row["source_fingerprint"]
        sel=_authorized_selection(row["authorized_selection"],fp,row["tv_session_id"])
        if sel["server_id"]!=cfg.profile_id: continue
        rec=reader(sel["server_id"],sel["torrent_hash"],sel["file_index"])
        require(_one_basename(rec.path)==name,"ODYSSEY_TS_FILENAME_MISMATCH")
        media=Media(sel["server_id"],sel["torrent_hash"],sel["file_index"],name,torrent_title=rec.torrent_title)
        _validate_source(media,{"release_name":release,"source_page":page})
        require(parse_release(name)==parse_release(release),"ODYSSEY_RELEASE_NOT_EXACT")
        found[fp]=media
    require(len(found)==1,"ODYSSEY_EXACT_SELECTION_NOT_UNIQUE")
    fp,media=next(iter(found.items()))
    # Existing source may be already staged. Never overwrite a conflicting EN.
    target=cache/".brain-en-inbox"/fp
    if target.exists():
        require(acquire_brain_english(media,cache).sha256==expected,"ODYSSEY_EXISTING_EN_CONFLICT")
        status="ALREADY_STAGED"
    else:
        stage_brain_english(cache_root=cache,source_fingerprint=fp,video_name=media.filename,release_name=release,source_page=page,srt_file=src)
        status="STAGED"
    asset=acquire_brain_english(media,cache)
    require(asset.sha256==expected and asset.cues==2009,"ODYSSEY_READBACK_FAILED")
    print("ODYSSEY_"+status+"_EXACT_MEDIA")
try: main()
except Exception as e:
    v=str(e)
    print(v if re.fullmatch(r"[A-Z0-9_]{3,90}",v) else "ODYSSEY_PRIVATE_ERROR")
    sys.exit(1)
'@
$f=Join-Path $env:TEMP ('ttv-odyssey-'+[Guid]::NewGuid().ToString('N')+'.py')
try {
    [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
    $out=@(& py -3 -I -B $f $owner $cache $state $src 2>$null)
    $code=$LASTEXITCODE
    $v=if($out.Count -eq 1 -and [string]$out[0] -cmatch '^[A-Z0-9_]{3,90}$'){[string]$out[0]}else{'ODYSSEY_PRIVATE_ERROR'}
    $doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$v}
    [IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    if($code -ne 0 -or $v -cnotin @('ODYSSEY_STAGED_EXACT_MEDIA','ODYSSEY_ALREADY_STAGED_EXACT_MEDIA')){throw 'ODYSSEY_STAGE_HOLD'}
    Write-Output $v
} finally {Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}

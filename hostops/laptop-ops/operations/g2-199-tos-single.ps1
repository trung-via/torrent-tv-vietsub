Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'NONCE_INVALID'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$run=Join-Path $root 'NativeBrowserTest\g2-199-tos-single-20261127'
$code='G2_FIXTURE_LOCAL_ERROR'
try {
    if(Test-Path -LiteralPath $run){$code='G2_FIXTURE_PRIOR_ATTEMPT_HOLD'}
    else {
        New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
        $py=@'
import pathlib,sys,json,os,re,urllib.request,hashlib,time
root=pathlib.Path(sys.argv[1]);nonce=sys.argv[2]
def fetch(url,limit):
    with urllib.request.urlopen(url,timeout=25) as f:
        if f.geturl()!=url:raise RuntimeError("UNEXPECTED_REDIRECT")
        data=f.read(limit+1)
    if not 0<len(data)<=limit:raise RuntimeError("SOURCE_BOUND")
    return data
def main():
    # Only public open-license fixture listed by WebTorrent; no AGY replay.
    # Blender Foundation, Tears of Steel (2012), CC BY 3.0, retain credits.
    url="https://raw.githubusercontent.com/webtorrent/webtorrent/2ea1dedaeef29a033209138ca0970e1e6c78f88f/docs/free-torrents.md"
    text=fetch(url,65536).decode("utf-8")
    rows=[line for line in text.splitlines() if line.startswith("- Tears of Steel ")]
    if len(rows)!=1:return "G2_FIXTURE_SOURCE_HOLD"
    m=re.search(r"\[\(magnet link\)\]\((magnet:\?[^)\r\n]+)\)",rows[0])
    if not m:return "G2_FIXTURE_SOURCE_HOLD"
    link=m.group(1)
    data=fetch("https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/9104e2fe8038c5f1b3f6595684483d6d735f3e0c/poc/p2-source/owner_movie_handoff.py",65536)
    if hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()!="0e5d351af58d089bd53d3fd78b4a6f46509ecbbb":
        return "G2_FIXTURE_SOURCE_DRIFT"
    (root/"owner_movie_handoff.py").write_bytes(data)
    sys.path.insert(0,str(root))
    from owner_movie_handoff import _hash,publish_library_receipt,HandoffHold
    expected="209c8226b299b308beaf2b9cd3fb49212dbd13ec"
    if _hash(link)!=expected:return "G2_FIXTURE_IDENTITY_HOLD"
    private=root/"private";private.mkdir()
    payload={"schema":"TTV-G2-SELECTED-RELEASE-V1","request_id":nonce,"play":True,
        "selection":{"link":link,"expected_hash":expected,"title":"Tears of Steel (2012) - Blender Foundation CC BY 3.0",
        "source_authorized":True,"media_authorized":True,"release_matched":True}}
    (private/("g2-"+nonce+".selected.json")).write_text(json.dumps(payload),encoding="utf-8")
    try:
        status=publish_library_receipt(private,nonce)
        # Only reconcile known pending metadata; never replay uncertain add.
        for _ in range(6):
            if status!="FILE_SELECTION_PENDING":break
            time.sleep(5)
            status=publish_library_receipt(private,nonce)
    except HandoffHold as e:
        reason=str(e)
        return "G2_FIXTURE_"+reason if re.fullmatch("[A-Z0-9_]{1,65}",reason) else "G2_FIXTURE_HANDOFF_HOLD"
    return "G2_FIXTURE_"+status
try:print(main())
except Exception:
    import traceback
    (root/"private-error.txt").write_text(traceback.format_exc(),encoding="utf-8")
    print("G2_FIXTURE_LOCAL_ERROR")
'@
        $f=Join-Path $run 'test.py'
        [IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
        $out=@(& py -3 -I -B $f $run $rq.nonce 2> (Join-Path $run 'private-stderr.txt'))
        if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^G2_FIXTURE_[A-Z0-9_]{1,75}$'){$code=[string]$out[0]}
    }
} catch {
    if(Test-Path -LiteralPath $run){[IO.File]::WriteAllText((Join-Path $run 'host-private-error.txt'),($_|Out-String),[Text.UTF8Encoding]::new($false))}
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

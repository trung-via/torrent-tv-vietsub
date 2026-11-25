# BT09A exact completed attempt: read-only extraction log classification.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
$run=Join-Path $root ('bt09a-extraction-readout-'+$rq.nonce)
New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
$py=@'
import pathlib,sys,json,re,wave
root,spool,run=map(pathlib.Path,sys.argv[1:4])
def obj(p):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size<16777216
    return json.loads(p.read_text(encoding="utf-8-sig"))
def main():
    source="bde31e100e13f9a238415e2a6addb3a512a651c0"
    matches=[]
    for f in (spool/"History").glob("receipt-*.json"):
        q=obj(f)
        if q.get("source_commit")==source and q.get("result")=="SUCCESS" and re.fullmatch("[a-f0-9]{32}",str(q.get("nonce",""))):matches.append(q["nonce"])
    assert len(matches)==1
    d=root/("bt09-movie-audio-qa-"+matches[0])
    report=obj(d/"BRAIN_AUDIO_QA.json")
    assert report["schema"]=="BT09_AUDIO_QA_V1" and report["sample_count"]==1 and report["speech_sample_count"]==1
    rows=[]
    for j in range(5):
        err=d/f"extract-{j}.err"
        raw=err.read_text(encoding="utf-8",errors="replace")[:200000].lower() if err.is_file() and err.stat().st_size<200000 else ""
        audio=d/f"audio-{j}.wav";dur=0
        try:
            with wave.open(str(audio),"rb") as w:dur=round(w.getnframes()/w.getframerate())
        except (OSError,EOFError,wave.Error):pass
        passed=any(x["sample"]==j for x in report["scores"]["H_OS"])
        if passed:kind="OK"
        elif re.search(r"timed? ?out|timeout|10060",raw):kind="TIMEOUT"
        elif re.search(r"seek|range|partial file",raw):kind="SEEK"
        elif re.search(r"invalid data|ebml|matroska|invalid as first byte",raw):kind="MEDIA"
        elif re.search(r"http error|server returned|connection|input/output error|i/o error",raw):kind="IO"
        elif dur>0:kind="SHORT"
        elif raw.strip():kind="OTHER"
        else:kind="EMPTY"
        rows.append({"sample":j,"seconds":dur,"classification":kind,"asr_success":passed})
    (run/"BRAIN_EXTRACTION_QA.json").write_text(json.dumps({"schema":"BT09A_EXTRACTION_QA_V1","original_nonce":matches[0],"rows":rows},indent=2),encoding="utf-8")
    print("BT09R_"+"_".join(f"{x['sample']}{x['classification']}{min(99,x['seconds'])}" for x in rows))
try:main()
except Exception:print("BT09R_READOUT_ERROR")
'@
$f=Join-Path $run 'readout.py'
[IO.File]::WriteAllText($f,$py,[Text.UTF8Encoding]::new($false))
$out=@(& py -3 -I -B $f $root $spool $run 2> (Join-Path $run 'stderr.txt'))
$code='BT09R_READOUT_ERROR'
if($LASTEXITCODE -eq 0 -and $out.Count -eq 1 -and [string]$out[0] -cmatch '^BT09R_[A-Z0-9_]{3,83}$'){$code=[string]$out[0]}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

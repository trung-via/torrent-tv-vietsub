# Read-only Owner-local P3 gate classification. Export only fixed enumerations.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0){throw 'OWNER_CONTEXT_REQUIRED'}
$owner=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$log=Join-Path $owner 'diagnostics\owner-full.log'
$item=Get-Item -LiteralPath $log
if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'P3_LOG_UNTRUSTED'}
$lines=@(Get-Content -LiteralPath $log -Tail 3000 -Encoding UTF8)
$lastStart=-1
for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -match '^OWNER_FULL_DIAGNOSTICS_STARTED pid='){$lastStart=$i}}
if($lastStart -ge 0){$lines=@($lines | Select-Object -Skip ($lastStart+1))}
$reason='P3_GATE_NOT_OBSERVED'
$latest=-1
for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i] -match "^OWNER_FULL_TRACE 'P3_SELECTION_RECEIVED'"){$latest=$i}
}
if($latest -ge 0){
    foreach($line in @($lines | Select-Object -Skip $latest)){
        if($line -match "^OWNER_FULL_TRACE 'P3_BRAIN_EN_GATE'.*'reason': '(BRAIN_EN_NOT_STAGED|BRAIN_EN_INVALID)'"){$reason=$Matches[1]}
        elseif($line -match "^OWNER_FULL_TRACE 'P3_PROCESSING_(REJECTED|FAILED)'"){$reason='P3_PROCESSING_EXCEPTION'}
        elseif($line -match '^((TypeError|ValueError|AttributeError|ImportError|ModuleNotFoundError|RuntimeError)): ' -and $reason -eq 'P3_PROCESSING_EXCEPTION'){$reason='P3_EXCEPTION_'+$Matches[1].ToUpperInvariant()}
        elseif($line -match "^OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED'.*'status': '(DISPATCH|SKIP)'"){$reason='P3_SELECTION_'+$Matches[1]}
    }
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$reason}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $reason

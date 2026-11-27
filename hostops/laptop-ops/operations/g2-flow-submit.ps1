# Fixed existing Owner helper operation. A trusted local input is required.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not [Environment]::UserInteractive -or $env:GITHUB_ACTIONS -eq 'true'){throw 'G2_OWNER_CONTEXT'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app=Join-Path $root 'app\poc\p2-sub-discovery'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$req=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($req.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'G2_HOSTOPS_NONCE'}
# Exact integrated source required. This is a read of installed source,
# not a claim that the running PID has loaded it; deployment remains separate.
$pins=@{
 'owner_g2_submit.py'='196da5a5e560faa9f780428073e67a75e956d73b'
 'owner_session_bridge.py'='3b6faaeb4481ea8c1a06b0bcd777dbdad336070e'
 'owner_g2_discovery.py'='2707298aaa10e38c79f44505a6853ed31336ff0d'
 'owner_movie_handoff.py'='0e5d351af58d089bd53d3fd78b4a6f46509ecbbb'
}
foreach($name in $pins.Keys){
 $file=Join-Path $app $name
 if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw 'G2_OWNER_INSTALL_REQUIRED'}
 $blob=(& git hash-object -- $file 2>$null | Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $blob -cne $pins[$name]){throw 'G2_OWNER_SOURCE_DRIFT'}
}
$inputFile=Join-Path $root 'g2-flow-request.json'
$item=Get-Item -LiteralPath $inputFile -ErrorAction Stop
if($item.Length -le 0 -or $item.Length -gt 8192 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'G2_PRIVATE_INPUT_INVALID'}
$movieRequest=Get-Content -LiteralPath $inputFile -Raw|ConvertFrom-Json -Depth 15
if($movieRequest.schema -cne 'TTV-OWNER-G2-SELECTION-V1' -or $movieRequest.request_id -cnotmatch '^[a-f0-9]{32}$' -or
 @($movieRequest.queries).Count -ne 1 -or $movieRequest.queries[0].play -isnot [bool] -or -not $movieRequest.queries[0].play){throw 'G2_PRIVATE_PLAY_REQUEST_REQUIRED'}
# Existing CLI checks request authority and atomically publishes the inbox file.
& py -3 (Join-Path $app 'owner_g2_submit.py') --owner-root $root --request-file $inputFile
if($LASTEXITCODE -ne 0){throw 'G2_OWNER_SUBMIT_FAILED'}
$receipt=Join-Path $spool ('Receipts\g2-flow-submit-'+$req.nonce+'.json')
$doc=@{schema='TTV-G2-HOSTOPS-SUBMIT-V1';nonce=$req.nonce;request_id=$movieRequest.request_id}
$stream=[IO.File]::Open($receipt,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($doc|ConvertTo-Json -Compress))
 $stream.Write($bytes,0,$bytes.Length)
 $stream.Flush($true)
}finally{$stream.Dispose()}
Write-Output 'G2_SUBMIT=ACCEPTED_NOT_RESULT'

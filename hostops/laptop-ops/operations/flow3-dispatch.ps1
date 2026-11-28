# Owner interactive: submit one typed G2 request, publish only its stage.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'FLOW3_OWNER_CONTEXT'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($rq.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $rq.nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'FLOW3_REQUEST'}
$nonce=$rq.nonce
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$inputFile=Join-Path $spool ('Requests\flow3-'+$nonce+'.json')
$stage='FLOW3_OWNER_HOLD'
try{
    $f=Get-Item -LiteralPath $inputFile -ErrorAction Stop
    if($f.Length -le 0 -or $f.Length -gt 8192 -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'FLOW3_PAYLOAD'}
    $p=Get-Content -LiteralPath $inputFile -Raw|ConvertFrom-Json
    if($p.request_id -cne $nonce -or $p.schema -cnotin @('TTV-OWNER-G2-CONCIERGE-V1','TTV-OWNER-G2-METADATA-V1')){throw 'FLOW3_PAYLOAD_BIND'}
    $submit=Join-Path $root 'app\poc\p2-sub-discovery\owner_g2_submit.py'
    $result=@(& py -3 -B $submit --owner-root $root --request-file $inputFile 2>$null)
    if($LASTEXITCODE -ne 0 -or $result -cnotcontains 'OWNER_G2_SUBMIT_ACCEPTED_NOT_RESULT'){throw 'FLOW3_SUBMIT_UNKNOWN_NO_REPLAY'}
    $stage='FLOW3_ACCEPTED_NOT_RESULT'
    $receipt=Join-Path $root ('inbox\g2-'+$nonce+'.receipt.json')
    $deadline=[DateTimeOffset]::UtcNow.AddMinutes(5)
    while([DateTimeOffset]::UtcNow -lt $deadline){
        if(Test-Path -LiteralPath $receipt -PathType Leaf){
            $v=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
            if($v.schema -cne 'TTV-OWNER-G2-RECEIPT-V1' -or $v.request_id -cne $nonce){throw 'FLOW3_RECEIPT_BIND'}
            if($v.status -ne 'COMPLETE'){
                $reason=if($v.PSObject.Properties['reason'] -and [string]$v.reason -cmatch '^[A-Z0-9_]{1,70}$'){[string]$v.reason}else{'UNKNOWN'}
                $stage='FLOW3_HOLD_'+$reason
                break
            }
            if($p.schema -ceq 'TTV-OWNER-G2-CONCIERGE-V1'){
                if($v.PSObject.Properties['library_status'] -and $v.library_status -ceq 'LIBRARY_READY'){$stage='FLOW3_LIBRARY_READY'}
                else{$stage='FLOW3_LIBRARY_NOT_READY_NO_REPLAY'}
            }else{$stage='FLOW3_METADATA_COMPLETE'}
            break
        }
        Start-Sleep -Seconds 1
    }
}catch{
    $stage='FLOW3_OWNER_HOLD_NO_REPLAY'
}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$nonce+'.json')),(@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$nonce;reason=$stage}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $stage

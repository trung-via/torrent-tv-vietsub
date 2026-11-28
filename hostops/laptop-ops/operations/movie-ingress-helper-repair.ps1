$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$r=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$nonce=[string]$r.nonce
if($nonce -cnotmatch '^[a-f0-9]{32}$'){throw 'REPAIR_REQUEST_INVALID'}
$original=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes('ttv-production-movie-v1:7235850295'))).ToLowerInvariant().Substring(0,32)
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$helper=Join-Path $root 'OwnerBridge\Maintenance\owner-laptop-ops-helper.ps1'
$code='MOVIE_HELPER_REPAIR_FAILED'
try {
    $prior=Get-Content -LiteralPath (Join-Path $spool ('History\receipt-'+$original+'.json')) -Raw|ConvertFrom-Json
    if($prior.nonce -cne $original -or $prior.source_commit -cne '7ec2eccfba633625d845b37264d44083173fb576' -or $prior.operation -cne 'NONE' -or $prior.result -cne 'FAILED_NO_RETRY'){throw 'MOVIE_PRIOR_RECEIPT_DRIFT'}
    if((Test-Path -LiteralPath (Join-Path $root ('LaptopHostOps\run-'+$original))) -or (Test-Path -LiteralPath (Join-Path $root ('OwnerBridge\backups\production-movie-'+$original)))){throw 'MOVIE_PRIOR_EFFECT_REVIEW'}
    $t=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\'
    if(@($t.Actions).Count -ne 1 -or [string]$t.Actions[0].Arguments -notlike ('*-File "'+$helper+'"')){throw 'MOVIE_HELPER_TASK_DRIFT'}
    $actual=(Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ceq 'e1ccd2463e20bb407d439b0582b927919bc3a936f9d00520d9d387641b396175'){$code='MOVIE_HELPER_ALREADY_CURRENT'}
    elseif($actual -cne 'f04ab8f2915194b1d3fcc5eb39e0970af6a54bb28ae563951ecac1afcf70ca33'){$code='MOVIE_HELPER_INSTALLED_HASH_DRIFT'}
    else {
        $temp=$helper+'.'+$nonce+'.staged'
        $backup=$helper+'.'+$nonce+'.rollback'
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/0bd1a1493ab7751d6b499aa1c3ab8ea00d19dbfd/hostops/setup/owner-laptop-ops-helper.ps1' -OutFile $temp -ErrorAction Stop
        if((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'e1ccd2463e20bb407d439b0582b927919bc3a936f9d00520d9d387641b396175'){throw 'MOVIE_HELPER_NEW_HASH'}
        $tokens=$null;$errors=$null
        [System.Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$errors)|Out-Null
        if(@($errors).Count -ne 0){throw 'MOVIE_HELPER_PARSE'}
        if((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'f04ab8f2915194b1d3fcc5eb39e0970af6a54bb28ae563951ecac1afcf70ca33'){throw 'MOVIE_HELPER_CONCURRENT_DRIFT'}
        [IO.File]::Replace($temp,$helper,$backup,$false)
        if((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'e1ccd2463e20bb407d439b0582b927919bc3a936f9d00520d9d387641b396175' -or (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'f04ab8f2915194b1d3fcc5eb39e0970af6a54bb28ae563951ecac1afcf70ca33'){throw 'MOVIE_HELPER_REPLACE_VERIFY'}
        $code='MOVIE_HELPER_REPAIR_PASS'
    }
} catch {
    if($_.Exception.Message -cmatch '^MOVIE_[A-Z0-9_]+$'){$code=$_.Exception.Message}
}
$doc=@{schema='TTV-MOVIE-HELPER-REPAIR-V1';nonce=$nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\movie-helper-'+$nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code
if($code -cnotin @('MOVIE_HELPER_REPAIR_PASS','MOVIE_HELPER_ALREADY_CURRENT')){throw 'MOVIE_HELPER_REPAIR_HOLD'}

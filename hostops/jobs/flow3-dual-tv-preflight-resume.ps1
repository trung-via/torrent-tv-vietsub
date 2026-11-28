# Resume only the failed APK signer/version checks, preserving Owner staging.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20'){throw 'WRONG_CONTEXT'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$r=Get-Content -LiteralPath (Join-Path $spool 'Receipts\receipt.json') -Raw|ConvertFrom-Json
$q=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
if($r.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or $r.source_commit -cne '5b7a6f98025474a679e0947c9400f8745efe8216' -or $r.operation -cne 'owner-flow3-dual-preflight' -or $r.result -cne 'SUCCESS' -or $r.nonce -cnotmatch '^[a-f0-9]{32}$' -or $q.nonce -cne $r.nonce -or $q.source_commit -cne $r.source_commit){throw 'ORIGINAL_OWNER_RECEIPT_DRIFT'}
$nonce=$r.nonce
$v=Get-Content -LiteralPath (Join-Path $spool ('Receipts\odyssey-stage-'+$nonce+'.json')) -Raw|ConvertFrom-Json
if($v.schema -cne 'TTV-ODYSSEY-STAGE-V1' -or $v.nonce -cne $nonce -or $v.reason -cne 'FLOW3_DUAL_PREFLIGHT_READY_HASH10_U5_R1_HB1'){throw 'ORIGINAL_OWNER_STAGE_DRIFT'}
$candidate='d93ca6bfaa25279402ee13a2bc8960d61992c6a4'
$sha='9d8ff2c9b34c105b1f74e2419790ff6b02520f92d6aae9fbaf7bea57170858fa'
$cache=Join-Path $env:RUNNER_WORKSPACE '_omp-fast-cache'
$stage=Join-Path $cache ('flow3-dual-staged\'+$candidate)
$apk=Join-Path $stage 'app-armeabi-v7a-debug.apk'
$meta=Get-Content -LiteralPath (Join-Path $stage 'stage-receipt.txt')
foreach($line in @('schema=TTV-FLOW3-DUAL-APK-STAGE-V1',('app_commit='+$candidate),'baseline_commit=a6bd7882054b2d942809502c34c25c5b9c682cd1','omp_commit=52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f','variant=app-armeabi-v7a-debug.apk',('sha256='+$sha),'device_installed=no')){
    if($meta -cnotcontains $line){throw 'FLOW3_DUAL_STAGE_RECEIPT_DRIFT'}
}
if((Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sha){throw 'FLOW3_DUAL_APK_DRIFT'}
Write-Output 'FLOW3_DUAL_STAGED_APK_SHA256_PASS'
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$devices=@(& $adb devices 2>$null)
$auth=@($devices|Where-Object{$_ -match '^\S+\s+device(\s|$)'})
if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or @($devices|Where-Object{$_ -match '^\S+\s+(offline|unauthorized)(\s|$)'}).Count){Write-Output 'FLOW3_DUAL_TV_HOLD_ADB_UNAVAILABLE';return}
$serial=($auth[0] -split '\s+')[0]
if(((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim() -cne 'MiTV-ASTR0'){throw 'FLOW3_DUAL_TV_MODEL'}
$abi=((& $adb -s $serial shell getprop ro.product.cpu.abilist 2>$null)|Out-String).Trim()
if($LASTEXITCODE -ne 0 -or ($abi -split ',') -cnotcontains 'armeabi-v7a'){throw 'FLOW3_DUAL_TV_ABI'}
$pkg='com.spacesarmat.omp.test'
$act=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
if($LASTEXITCODE -ne 0){throw 'FLOW3_DUAL_TV_ACTIVITY'}
$playing=@($act -split '\r?\n'|Where-Object{$_ -match 'mResumedActivity|topResumedActivity' -and $_ -match 'com\.spacesarmat\.omp\.test/' -and $_ -match 'PlayerActivity'}).Count -gt 0
$paths=@(& $adb -s $serial shell pm path $pkg 2>$null|ForEach-Object{([string]$_).Trim()})
if($LASTEXITCODE -ne 0 -or $paths.Count -ne 1 -or $paths[0] -notmatch '^package:(/data/app/[^ \r\n]+/base\.apk)$'){Write-Output 'FLOW3_DUAL_TV_HOLD_OLD_APK_LAYOUT';return}
$remote=$Matches[1]
# Reuse original rollback copy; confirm installed base still matches.
$rollback=Join-Path $cache ('flow3-dual-rollback\'+$nonce)
$old=Join-Path $rollback 'previous-base.apk'
if(-not (Test-Path -LiteralPath $old -PathType Leaf) -or ((Get-Item -LiteralPath $old).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'OLD_BACKUP_MISSING'}
$oldsha=(Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash.ToLowerInvariant()
$remoteHash=((& $adb -s $serial shell sha256sum $remote 2>$null)|Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $remoteHash -notmatch '^([0-9a-fA-F]{64})\s' -or $Matches[1].ToLowerInvariant() -cne $oldsha){throw 'INSTALLED_APK_DRIFT'}
$tool=@(Get-ChildItem -LiteralPath 'C:\TOOL\Android-SDK\build-tools' -Directory|Where-Object{(Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt2.exe'))}|Sort-Object Name -Descending|Select-Object -First 1)
if($tool.Count -ne 1){throw 'FLOW3_DUAL_SDK_TOOLS'}
$signer=Join-Path $tool[0].FullName 'apksigner.bat'
$aapt=Join-Path $tool[0].FullName 'aapt2.exe'
$jdk=@(Get-ChildItem -LiteralPath 'C:\Program Files\Eclipse Adoptium' -Directory|Where-Object{$_.Name -like 'jdk-21*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe'))}|Sort-Object Name -Descending|Select-Object -First 1)
if($jdk.Count -ne 1){throw 'FLOW3_DUAL_JAVA'}
$env:JAVA_HOME=$jdk[0].FullName
function Cert([string]$file,[string]$role){
    $lines=@(& $signer verify --verbose --print-certs $file 2>$null)
    if($LASTEXITCODE -ne 0){throw 'FLOW3_DUAL_APK_SIGNATURE'}
    $out=($lines -join "`n")
    $matchesCert=[regex]::Matches($out,'(?im)^\s*(?:(?:V[1-4](?:\.\d+)?\s+Signer(?:\s+#?\d+)?\s*:\s*)|(?:Signer\s+#?\d+\s+))?certificate\s+SHA-256\s+digest\s*:\s*([0-9a-f:]{64,95})[ \t\r]*$')
    $digests=@($matchesCert|ForEach-Object{$_.Groups[1].Value.Replace(':','').ToLowerInvariant()}|Sort-Object -Unique)
    $number=[regex]::Match($out,'(?im)^\s*Number of signers:\s*(\d+)\s*$')
    Write-Host ('FLOW3_DUAL_CERT_'+$role+'_DIGEST_COUNT='+$digests.Count)
    if($number.Success){Write-Host ('FLOW3_DUAL_CERT_'+$role+'_SIGNER_COUNT='+$number.Groups[1].Value)}
    if($digests.Count -ne 1 -or $digests[0] -cnotmatch '^[a-f0-9]{64}$' -or (-not $number.Success -or $number.Groups[1].Value -ne '1')){
        # Report field names only; never print certificate DN or device data.
        foreach($line in $lines){if($line -match '(?i)sha-?256|number of signers'){Write-Host ('FLOW3_DUAL_CERT_FORMAT='+(([string]$line -replace ':.*$',': [redacted]') -replace '[0-9a-fA-F]{32,}','[redacted]'))}}
        throw 'FLOW3_DUAL_APK_SIGNER_FORMAT'
    }
    return $digests[0]
}
function Version([string]$file){
    $lines=@(& $aapt dump badging $file 2>$null)
    if($LASTEXITCODE -ne 0){throw 'FLOW3_DUAL_APK_BADGING'}
    $p=@($lines|Where-Object{$_ -match "^package: name='com\.spacesarmat\.omp\.test' versionCode='\d+'"})
    if($p.Count -ne 1 -or $p[0] -notmatch "versionCode='(\d+)'"){throw 'FLOW3_DUAL_APK_PACKAGE'}
    return [long]$Matches[1]
}
$oldcert=Cert $old 'OLD';$newcert=Cert $apk 'NEW'
$oldver=Version $old;$newver=Version $apk
$proof=@{schema='TTV-FLOW3-DUAL-TV-PREFLIGHT-V1';nonce=$nonce;candidate=$candidate;new_sha256=$sha;old_sha256=$oldsha;old_version=$oldver;new_version=$newver;signer_match=($oldcert -ceq $newcert);player_foreground=$playing;observed_utc=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
[IO.File]::WriteAllText((Join-Path $rollback 'preflight.json'),($proof|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
if($oldcert -cne $newcert){Write-Output 'FLOW3_DUAL_TV_HOLD_SIGNER_MISMATCH';return}
if($newver -lt $oldver){Write-Output 'FLOW3_DUAL_TV_HOLD_VERSION_DOWNGRADE';return}
if($playing){Write-Output 'FLOW3_DUAL_TV_HOLD_ACTIVE_PLAYBACK';return}
Write-Output 'FLOW3_DUAL_TV_PREFLIGHT_PASS_ARM32_SIGNER_VERSION_ROLLBACK'
Write-Output ('FLOW3_DUAL_OLD_APK_SHA256='+$oldsha)


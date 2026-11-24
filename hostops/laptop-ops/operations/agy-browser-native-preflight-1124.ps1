# Read-only local capability inventory. No provider, browser launch, install or login.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$chrome=Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'
$c='CHROME_MISSING'
if(Test-Path -LiteralPath $chrome -PathType Leaf){
 $v=(Get-Item -LiteralPath $chrome).VersionInfo.ProductMajorPart
 $c='CHROME_'+[string]$v
}
$n=if(Get-Command npx -ErrorAction SilentlyContinue){'NPX_PRESENT'}else{'NPX_MISSING'}
$agy=Get-Command agy -ErrorAction SilentlyContinue
$a='AGY_MISSING'
$b='BROWSER_UNVERIFIED'
if($null -ne $agy){
 try{
  $ver=(& agy --version 2>&1 | Out-String)
  $m=[regex]::Match($ver,'(?<!\d)\d+\.\d+\.\d+(?!\d)')
  $a=if($m.Success){'AGY_'+($m.Value -replace '\.','_')}else{'AGY_VERSION_UNKNOWN'}
  $help=(& agy --help 2>&1 | Out-String)
  if($help -match '(?i)/browser|chrome.devtools|browser subagent'){$b='BROWSER_HELP_PRESENT'}
 }catch{$a='AGY_READ_ERROR'}
}
$code=$a+'_'+$c+'_'+$n+'_'+$b
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

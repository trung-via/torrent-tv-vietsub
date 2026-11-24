# Scoped read-only inventory of exact prior native-browser setup. Never attach CDP.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$prior=@(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -Filter 'receipt-*.json' -File | ForEach-Object {
 if($_.Length -le 2048 -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  try{$r=Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
   if($r.source_commit -ceq '0ce22e9b66d785b6cc8d1ec09990681b2337f54f' -and $r.operation -ceq 'agy-native-browser-interactive-1124' -and $r.nonce -cmatch '^[a-f0-9]{32}$'){$r}
  }catch{}
 }
})
$code='NATIVE_PRIOR_NOT_UNIQUE'
if($prior.Count -eq 1){
 $root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\NativeBrowserTest'
 $profile=Join-Path $root 'ChromeProfile'
 $run=Join-Path $root ('spiderman-'+$prior[0].nonce)
 $launch=Join-Path $run 'start-test.ps1'
 $all=@(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='pwsh.exe' OR Name='agy.exe' OR Name='node.exe' OR Name='cmd.exe'")
 $ch=@($all | Where-Object {$_.Name -eq 'chrome.exe' -and $_.CommandLine -and $_.CommandLine.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.CommandLine -notmatch '--type='})
 $shell=@($all | Where-Object {$_.Name -eq 'pwsh.exe' -and $_.CommandLine -and $_.CommandLine.IndexOf($launch,[StringComparison]::OrdinalIgnoreCase) -ge 0})
 $ids=@($shell | ForEach-Object {$_.ProcessId})
 $desc=@()
 for($i=0;$i -lt 6;$i++){
  $new=@($all | Where-Object {$_.ParentProcessId -in $ids -and $_.ProcessId -notin $ids})
  if($new.Count -eq 0){break}
  $desc+=$new
  $ids+=@($new|ForEach-Object{$_.ProcessId})
 }
 $agy=@($desc|Where-Object{$_.Name -eq 'agy.exe' -or ($_.CommandLine -and $_.CommandLine -match 'gemini-4-hydrogen-low|antigravity')})
 $browser=@($desc|Where-Object{$_.CommandLine -and $_.CommandLine -match 'chrome-devtools-mcp'})
 # Only inspect files within exact attempt directory, not user's general Downloads or Chrome history.
 $files=@(Get-ChildItem -LiteralPath $run -File -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in @('.srt','.zip','.vtt') -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)})
 $valid=0
 foreach($f in $files){
  if($f.Extension -eq '.srt' -and $f.Length -ge 1000 -and $f.Length -le 2000000){
   $s=[IO.File]::ReadAllText($f.FullName)
   $n=[regex]::Matches($s,'(?m)^\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}').Count
   if($n -ge 50){$valid=$n;break}
  }
 }
 $code='CHROME'+[int]($ch.Count -gt 0)+'_SHELL'+[int]($shell.Count -gt 0)+'_AGY'+[int]($agy.Count -gt 0)+'_MCP'+[int]($browser.Count -gt 0)+'_FILES'+$files.Count+'_CUES'+$valid
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

# Three independent public URL observations, no credentials, spoofing, retries or AI.
# Stop each probe on restriction or redirect. Never derive or guess download IDs.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$handler=[Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect=$false
$handler.UseCookies=$false
$handler.AutomaticDecompression=[Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
$client=[Net.Http.HttpClient]::new($handler)
$client.Timeout=[TimeSpan]::FromSeconds(15)
function Probe([string]$url,[bool]$download){
 $res=$null
 try{
  $res=$client.GetAsync($url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
  $status=[int]$res.StatusCode
  $tag='HTTP'+$status
  if($status -ge 300 -and $status -lt 400){
   $loc=$res.Headers.Location
   if($null -ne $loc){
    $dest=[Uri]::new([Uri]$url,$loc)
    $tag+=if($dest.AbsolutePath -match '(?i)login|signin|auth|challenge|captcha'){'_AUTH'}elseif($dest.Host -match '(^|\.)opensubtitles\.(org|com)$'){'_OSREDIR'}else{'_REDIR'}
   }
   return $tag
  }
  if($status -ne 200){return $tag}
  $length=$res.Content.Headers.ContentLength
  if($null -ne $length -and $length -gt 524288){return ($tag+'_LARGE')}
  $stream=$res.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
  $mem=[IO.MemoryStream]::new()
  try{
   $buf=New-Object byte[] 8192
   while(($n=$stream.Read($buf,0,$buf.Length)) -gt 0){
    if($mem.Length+$n -gt 524288){return ($tag+'_LARGE')}
    $mem.Write($buf,0,$n)
   }
   $data=$mem.ToArray()
   $body=[Text.Encoding]::UTF8.GetString($data)
   $head=$body.Substring(0,[Math]::Min(4096,$body.Length))
   if($head -match '(?i)<title[^>]*>[^<]*(just a moment|attention required|access denied|verify|captcha)|cf-chl-|challenge-platform'){return ($tag+'_CHALLENGE')}
   if($download){
    $c=[regex]::Matches($body,'(?m)^\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}').Count
    if($c -gt 50){return ($tag+'_SRT'+$c)}
    if($data.Length -gt 4 -and $data[0] -eq 80 -and $data[1] -eq 75){return ($tag+'_ZIP')}
    return ($tag+'_NOTSRT')
   }
   return ($tag+'_PAGE')
  }finally{$mem.Dispose();$stream.Dispose()}
 }catch [System.Threading.Tasks.TaskCanceledException]{return 'TIMEOUT'}
 catch [System.Net.Http.HttpRequestException]{return 'NETWORK'}
 catch{return 'LOCALERR'}
 finally{if($null -ne $res){$res.Dispose()}}
}
try{
 # Root catalog is the documented website entry point; not a completed search query.
 $s=Probe 'https://www.opensubtitles.org/en/search' $false
 $d=Probe 'https://www.opensubtitles.org/en/subtitles/14097898/spider-man-brand-new-day-en' $false
 # Independent known owner-approved download URL from the prior successful receipt.
 # Do not use it as a means of overcoming an access restriction.
 # If a catalog/detail request explicitly denies access, leave the download control historical.
 $l=if($s -match 'HTTP(401|403|429|503)|CHALLENGE|_AUTH' -or $d -match 'HTTP(401|403|429|503)|CHALLENGE|_AUTH'){'STOP_ACCESS'}else{Probe 'https://dl.opensubtitles.org/en/download/sub/14097898' $true}
 $code='S_'+$s+'_D_'+$d+'_L_'+$l
}finally{$client.Dispose();$handler.Dispose()}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

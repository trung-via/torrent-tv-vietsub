# P4 one-time local PC pairing preparation (never run from GitHub Actions).
# Writes 30-day IP-SAN TLS identity and 32-byte device key ONLY into an
# ACL-restricted directory belonging to the current Windows owner.
# Does NOT start a listener, install software or change firewall/services.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$BindIPv4,
  [Parameter(Mandatory=$true)][ValidateRange(1024,65535)][int]$Port
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true' -or $env:TF_BUILD) {
  throw 'P4_OWNER_SETUP_STOP_CI_NOT_ALLOWED'
}
function Test-PrivateIPv4([string]$ip) {
  if ($ip -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') {return $false}
  $parts=@($ip.Split('.'))
  foreach ($p in $parts) {
    if (($p.Length -gt 1 -and $p.StartsWith('0')) -or [int]$p -gt 255) {return $false}
  }
  $a=[int]$parts[0]; $b=[int]$parts[1]
  return ($a -eq 10 -or ($a -eq 172 -and $b -ge 16 -and $b -le 31) -or
    ($a -eq 192 -and $b -eq 168))
}
if (-not (Test-PrivateIPv4 $BindIPv4)) {throw 'P4_OWNER_SETUP_STOP_RFC1918_IPV4_REQUIRED'}
$ips=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
  Where-Object { $_.IPAddress -ceq $BindIPv4 -and $_.AddressState -eq 'Preferred' })
if ($ips.Count -ne 1) {throw 'P4_OWNER_SETUP_STOP_BIND_INTERFACE_NOT_FOUND'}
$opensslCmd=Get-Command 'openssl.exe' -ErrorAction SilentlyContinue
$openssl=if ($null -ne $opensslCmd) {$opensslCmd.Source}
  else {'C:\Program Files\Git\usr\bin\openssl.exe'}
if (-not (Test-Path -LiteralPath $openssl -PathType Leaf)) {
  throw 'P4_OWNER_SETUP_STOP_OPENSSL_NOT_AVAILABLE'
}
if (-not $env:LOCALAPPDATA) {throw 'P4_OWNER_SETUP_STOP_LOCALAPPDATA_MISSING'}
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P4'
if (Test-Path -LiteralPath $root) {throw 'P4_OWNER_SETUP_STOP_EXISTING_PAIRING_NO_ROTATION'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if ($null -eq $identity.User) {throw 'P4_OWNER_SETUP_STOP_OWNER_IDENTITY'}
$made=$false
$secret=New-Object byte[] 32
try {
  New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop | Out-Null
  $made=$true
  $acl=New-Object System.Security.AccessControl.DirectorySecurity
  $acl.SetOwner($identity.User)
  $acl.SetAccessRuleProtection($true,$false)
  $rights=[System.Security.AccessControl.FileSystemRights]::FullControl
  $inherit=[System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
  $propagate=[System.Security.AccessControl.PropagationFlags]::None
  $allow=[System.Security.AccessControl.AccessControlType]::Allow
  $rule=New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
    $identity.User,$rights,$inherit,$propagate,$allow)
  $acl.AddAccessRule($rule)
  Set-Acl -LiteralPath $root -AclObject $acl -ErrorAction Stop
  $cert=Join-Path $root 'pc-cert.pem'
  $key=Join-Path $root 'pc-key.pem'
  $stdout=Join-Path $root 'openssl-stdout.log'
  $stderr=Join-Path $root 'openssl-stderr.log'
  $argv=@('req','-x509','-newkey','rsa:3072','-sha256','-nodes','-days','30',
    '-subj','/CN=TorrentTV-P4-DEV','-addext',('subjectAltName=IP:'+$BindIPv4),
    '-keyout',$key,'-out',$cert)
  $quoted=@($argv | ForEach-Object { '"' + $_.Replace('"','') + '"' }) -join ' '
  $proc=Start-Process -FilePath $openssl -ArgumentList $quoted -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
  if ($proc.ExitCode -ne 0 -or
      -not (Test-Path -LiteralPath $cert -PathType Leaf) -or
      -not (Test-Path -LiteralPath $key -PathType Leaf)) {
    throw 'P4_OWNER_SETUP_STOP_GENERATE_CERT_FAILED'
  }
  $obj=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $cert
  if ($obj.NotBefore -gt (Get-Date) -or $obj.NotAfter -le (Get-Date).AddDays(1)) {
    throw 'P4_OWNER_SETUP_STOP_CERT_VALIDITY'
  }
  $sanOut=Join-Path $root 'openssl-san.log'
  $sanErr=Join-Path $root 'openssl-san-err.log'
  $argsSan='x509 -in "'+$cert+'" -noout -ext subjectAltName'
  $proc2=Start-Process -FilePath $openssl -ArgumentList $argsSan -NoNewWindow -Wait -PassThru -RedirectStandardOutput $sanOut -RedirectStandardError $sanErr -ErrorAction Stop
  $san=Get-Content -LiteralPath $sanOut -Raw
  if ($proc2.ExitCode -ne 0 -or
      $san -notmatch ('(?i)IP Address:\s*'+[regex]::Escape($BindIPv4)+'(?=[,\s]|$)')) {
    throw 'P4_OWNER_SETUP_STOP_CERT_IP_SAN_MISMATCH'
  }
  $sha=[Security.Cryptography.SHA256]::Create()
  try { $pin=[BitConverter]::ToString($sha.ComputeHash($obj.RawData)).Replace('-','').ToLowerInvariant() }
  finally { $sha.Dispose() }
  $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($secret) } finally { $rng.Dispose() }
  $hex=[BitConverter]::ToString($secret).Replace('-','').ToLowerInvariant()
  $utf8=New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText((Join-Path $root 'pairing-key.hex'),$hex,$utf8)
  [IO.File]::WriteAllText((Join-Path $root 'pairing-token.txt'),
    ($BindIPv4+':'+$Port+'|'+$hex+'|'+$pin),$utf8)
  [IO.File]::WriteAllText((Join-Path $root 'gateway-bind.txt'),
    ($BindIPv4+':'+$Port),$utf8)
  foreach ($p in @($stdout,$stderr,$sanOut,$sanErr)) {
    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  }
  Write-Host 'P4_OWNER_LOCAL_IP_SAN_TLS_PAIRING_PREPARED=true'
  Write-Host 'P4_OWNER_TOKEN_STORED_PRIVATELY_NO_SECRET_PRINT=true'
  Write-Host 'P4_OWNER_NO_LISTENER_NO_FIREWALL_NO_TV_CHANGE=true'
} catch {
  if ($made -and (Test-Path -LiteralPath $root)) {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
  throw
} finally {
  [Array]::Clear($secret,0,$secret.Length)
}
$global:LASTEXITCODE=0

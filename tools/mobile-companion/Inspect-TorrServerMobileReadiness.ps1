# P3-MOBILE - strictly local, read-only Windows TorrServer phone readiness snapshot.
# NEVER opens network connections or changes Windows Firewall/TorrServer/ADB.
# Running this does NOT prove the phone can connect.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 65535)]
    [int]$Port,

    # Display RFC1918 interface addresses ONLY in this local operator console.
    [switch]$ShowPrivateAddresses
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true') {
    throw 'MOBILE_PREFLIGHT_OWNER_LOCAL_ONLY_NO_CI'
}

foreach ($name in @('Get-NetTCPConnection', 'Get-NetIPAddress', 'Get-NetConnectionProfile')) {
    if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
        throw 'MOBILE_PREFLIGHT_WINDOWS_NETTCPIP_MODULE_REQUIRED'
    }
}

function Test-PrivateIPv4([string]$Address) {
    if ($Address -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
        return $false
    }
    $octets = @($Address.Split('.') | ForEach-Object { [int]$_ })
    if (@($octets | Where-Object { $_ -gt 255 -or $_ -lt 0 }).Count -gt 0) {
        return $false
    }
    return ($octets[0] -eq 10 -or
        ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
        ($octets[0] -eq 192 -and $octets[1] -eq 168))
}

# Kernel socket inventory ONLY. No HTTP request, URL, ping, DNS or scan.
try {
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
        Where-Object { $_.LocalPort -eq $Port })
} catch {
    Write-Output 'MOBILE_PREFLIGHT=LISTENER_INVENTORY_UNAVAILABLE'
    exit 2
}

Write-Output ('MOBILE_PREFLIGHT_PORT=' + $Port)
Write-Output ('MOBILE_PREFLIGHT_LISTENER_COUNT=' + $listeners.Count)

if ($listeners.Count -eq 0) {
    Write-Output 'MOBILE_PREFLIGHT=LOCAL_PORT_NOT_LISTENING'
    Write-Output 'NEXT=CHECK_EXISTING_TORRSERVER_UI_PORT_LOCALLY_NO_AUTO_START'
    exit 2
}

$lanBound = @($listeners | Where-Object {
    $_.LocalAddress -eq '0.0.0.0' -or
    (Test-PrivateIPv4 ([string]$_.LocalAddress))
})
$loopbackOnly = @($listeners | Where-Object {
    $_.LocalAddress -eq '127.0.0.1' -or $_.LocalAddress -eq '::1'
})
if ($lanBound.Count -gt 0) {
    Write-Output 'MOBILE_PREFLIGHT_BINDING=IPV4_LAN_CANDIDATE'
} elseif ($loopbackOnly.Count -eq $listeners.Count) {
    Write-Output 'MOBILE_PREFLIGHT_BINDING=LOOPBACK_ONLY'
} else {
    Write-Output 'MOBILE_PREFLIGHT_BINDING=IPV6_OR_OTHER_NEEDS_REVIEW'
}

# No network adapter names, Wi-Fi SSID, MACs or private IPs by default.
$privateIps = @()
try {
    $privateIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { Test-PrivateIPv4 ([string]$_.IPAddress) } |
        Select-Object -ExpandProperty IPAddress -Unique)
} catch {
    Write-Output 'MOBILE_PREFLIGHT_PRIVATE_INTERFACE_INVENTORY=UNKNOWN'
}
Write-Output ('MOBILE_PREFLIGHT_PRIVATE_IPV4_INTERFACE_COUNT=' + $privateIps.Count)
if ($ShowPrivateAddresses) {
    Write-Output 'LOCAL_ONLY_PRIVATE_IPV4_ADDRESSES_BEGIN'
    foreach ($ip in $privateIps) { Write-Output $ip }
    Write-Output 'LOCAL_ONLY_PRIVATE_IPV4_ADDRESSES_END'
    Write-Output 'CAUTION=NEVER_PASTE_THESE_ADDRESSES_IN_PUBLIC_GITHUB'
}

try {
    $profiles = @(Get-NetConnectionProfile -ErrorAction Stop)
    if (@($profiles | Where-Object { $_.NetworkCategory -eq 'Public' }).Count -gt 0) {
        Write-Output 'MOBILE_PREFLIGHT_NETWORK_PROFILE=PUBLIC_PRESENT_REVIEW_LOCALLY'
    } else {
        Write-Output 'MOBILE_PREFLIGHT_NETWORK_PROFILE=NO_PUBLIC_PROFILE_OBSERVED'
    }
} catch {
    Write-Output 'MOBILE_PREFLIGHT_NETWORK_PROFILE=UNKNOWN'
}

# A LAN socket candidate does not prove correct process/auth/firewall/routing.
Write-Output 'MOBILE_PREFLIGHT=LOCAL_LISTENER_OBSERVED_PHONE_NOT_VERIFIED'
Write-Output 'NEXT=CONNECT_PHONE_SAME_TRUSTED_LAN_AND_OPEN_EXISTING_TORRSERVER_LIBRARY'

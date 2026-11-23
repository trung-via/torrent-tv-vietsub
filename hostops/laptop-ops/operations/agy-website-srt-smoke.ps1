# One-shot AGY test of an English subtitle downloaded from the public website.
# Owner-interactive HostOps only. No OpenSubtitles API, TV, or OwnerAgent changes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command -Name agy -ErrorAction SilentlyContinue)) {
    throw 'AGY_WEBSITE_SMOKE_CLI_NOT_AVAILABLE'
}

$name = 'The.Odyssey.2026.1080p.AMZN.WEB-DL.DDP5.1.H.264-KyoGo.srt'
$expectedSha256 = 'fe793b7267170a016c01dcd597604afd9ce99414af374a95748f245acc0e7159'
$base = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\AGYWebsiteSmoke'
$run = Join-Path $base ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run -ErrorAction Stop | Out-Null

$prompt = @'
Bai test duy nhat tren laptop Windows nay:
1. Dung website https://www.opensubtitles.org/ (KHONG dung API OpenSubtitles,
   KHONG goi api.opensubtitles.com, KHONG dung SDK/OpenSubtitles API key).
2. Tim ban phu de EN cho phim The Odyssey (2026), release
   The.Odyssey.2026.1080p.AMZN.WEB-DL.DDP5.1.H.264-KyoGo.
   Trang tham chieu: https://www.opensubtitles.org/en/subtitles/14190981/the-odyssey-en
3. Tu trang website, tim lien ket tai file SRT va tai file ve thu muc lam viec
   hien tai, dung ten chinh xac:
   The.Odyssey.2026.1080p.AMZN.WEB-DL.DDP5.1.H.264-KyoGo.srt
4. Khong dung cache/file co san, khong tao file gia, khong dich phu de,
   khong tac dong TorrServer, OwnerAgent, TV hay cai dat he thong.
5. Neu website can CAPTCHA/dang nhap/chan bot, hay bao dung nguyen nhan;
   khong vuot qua kiem tra an ninh, khong doi proxy/fingerprint.
6. Chi ket luan THANH CONG neu file SRT thuc da duoc tai va luu.
   Ban co the su dung browser/HTTP GET tai link do website hien thi,
   nhung KHONG duoc goi endpoint OpenSubtitles API.
'@
[IO.File]::WriteAllText((Join-Path $run 'prompt.txt'), $prompt,
    [Text.UTF8Encoding]::new($false))

$child = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$promptText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'prompt.txt') -Raw -Encoding UTF8
& agy -p $promptText --output-format json --mode auto --sandbox *> (Join-Path $PSScriptRoot 'agy-private-output.txt')
if ($LASTEXITCODE -ne 0) { exit 1 }
exit 0
'@
$childFile = Join-Path $run 'invoke-agy.ps1'
[IO.File]::WriteAllText($childFile, $child, [Text.UTF8Encoding]::new($false))

$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'pwsh.exe'
$psi.UseShellExecute = $false
$psi.WorkingDirectory = $run
foreach ($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',$childFile)) {
    [void]$psi.ArgumentList.Add($arg)
}
$proc = [Diagnostics.Process]::new()
$proc.StartInfo = $psi
try {
    if (-not $proc.Start()) { throw 'AGY_WEBSITE_SMOKE_NOT_STARTED' }
    if (-not $proc.WaitForExit(240000)) {
        $proc.Kill($true)
        [void]$proc.WaitForExit(5000)
        throw 'AGY_WEBSITE_SMOKE_TIMEOUT'
    }
    if ($proc.ExitCode -ne 0) {
        throw 'AGY_WEBSITE_SMOKE_COMMAND_FAILED'
    }
} finally {
    $proc.Dispose()
}

$file = Join-Path $run $name
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    throw 'AGY_WEBSITE_SMOKE_SRT_NOT_SAVED'
}
$info = Get-Item -LiteralPath $file -Force
if ($info.Length -lt 100000 -or $info.Length -gt 500000 -or
    ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'AGY_WEBSITE_SMOKE_SRT_SIZE_INVALID'
}
$subtitleText = [IO.File]::ReadAllText($file)
$cueCount = [regex]::Matches($subtitleText,
    '(?m)^\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}').Count
if ($cueCount -lt 1000) {
    throw 'AGY_WEBSITE_SMOKE_NOT_SRT'
}
$actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -cne $expectedSha256) {
    throw 'AGY_WEBSITE_SMOKE_DIFFERENT_BYTES'
}
Write-Output 'AGY_WEBSITE_SMOKE=PASS_EXACT_SRT'
Write-Output ('AGY_WEBSITE_SMOKE_CUES=' + $cueCount)
Write-Output ('AGY_WEBSITE_SMOKE_BYTES=' + $info.Length)
Write-Output ('AGY_WEBSITE_SMOKE_SHA256=' + $actualHash)

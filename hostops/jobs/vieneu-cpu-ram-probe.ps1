# Read-only machine capability probe; runner context, no Owner profile access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows'){throw 'VIENEU_RUNNER_SCOPE_INVALID'}
$cpu=@(Get-CimInstance Win32_Processor)[0]
$os=Get-CimInstance Win32_OperatingSystem
$avx2=[System.Runtime.Intrinsics.X86.Avx2]::IsSupported
$avx512=[System.Runtime.Intrinsics.X86.Avx512F]::IsSupported
$vnni=$false
$vnni512=$false
$cpuid=[System.Runtime.Intrinsics.X86.X86Base]::IsSupported
if($cpuid){
    $root=[System.Runtime.Intrinsics.X86.X86Base]::CpuId(0,0)
    if($root.Item1 -ge 7){
        $l7=[System.Runtime.Intrinsics.X86.X86Base]::CpuId(7,0)
        $vnni512=($l7.Item3 -band (1 -shl 11)) -ne 0
        if($l7.Item1 -ge 1){
            $l71=[System.Runtime.Intrinsics.X86.X86Base]::CpuId(7,1)
            $vnni=($l71.Item1 -band (1 -shl 4)) -ne 0
        }
    }
}
$name=[string]$cpu.Name
if($name -cnotmatch '^[A-Za-z0-9 ()@.+_-]{1,120}$'){throw 'CPU_NAME_INVALID'}
Write-Output 'VIENEU_HW_SCOPE=MACHINE_RUNNER_READ_ONLY'
Write-Output ('VIENEU_HW_CPU='+$name)
Write-Output ('VIENEU_HW_PHYSICAL_CORES='+$cpu.NumberOfCores)
Write-Output ('VIENEU_HW_LOGICAL_CORES='+$cpu.NumberOfLogicalProcessors)
Write-Output ('VIENEU_HW_TOTAL_MIB='+[int]($os.TotalVisibleMemorySize/1024))
Write-Output ('VIENEU_HW_FREE_MIB='+[int]($os.FreePhysicalMemory/1024))
Write-Output ('VIENEU_HW_CPUID='+$cpuid)
Write-Output ('VIENEU_HW_AVX2_OS='+$avx2)
Write-Output ('VIENEU_HW_AVX512F_OS='+$avx512)
Write-Output ('VIENEU_HW_AVX_VNNI_CPUID='+$vnni)
Write-Output ('VIENEU_HW_AVX512_VNNI_CPUID='+$vnni512)
Write-Output ('VIENEU_HW_VNNI_USABLE='+(($vnni -and $avx2) -or ($vnni512 -and $avx512)))
Write-Output 'VIENEU_HW_MODEL_LOAD=NOT_ATTEMPTED'

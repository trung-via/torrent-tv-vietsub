# Synthetic INT8-only VieNeu CPU benchmark using verified AVX-VNNI machine. No Owner restart, AGY, film or TV.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem).UserName
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $id.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    -not $id.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) { throw 'VIENEU_OWNER_CONTEXT_REQUIRED' }
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'VIENEU_REQUEST_INVALID' }
$base = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\VieNeuBenchmark'
$root = Join-Path $base ('int8-benchmark-'+$request.nonce)
New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
$rec = [ordered]@{schema='TTV-VIENEU-BENCHMARK-V1';nonce=[string]$request.nonce;status='ENV_MISSING';stage='PREFLIGHT';sdk='NONE';precision='INT8';threads=8;model_sha='NONE';codec_sha='NONE';init_ms=0;first_ms=0;audio_ms=0;synth_ms=0;rtf_milli=0;cue_count=0;peak_mib=0;sample_rate=0;elapsed_s=0;prior_error='UNKNOWN';error_kind='NONE'}
$clock = [Diagnostics.Stopwatch]::StartNew()
$code = @'
import ctypes, json, os, sys, time, wave
from pathlib import Path
from importlib.metadata import version
from ctypes import wintypes

root = Path.cwd()
def write(d):
    tmp = root / "metrics.tmp"
    tmp.write_text(json.dumps(d), encoding="utf-8")
    tmp.replace(root / "metrics.json")
d = dict(status="RUNNING", stage="IMPORT", sdk="NONE", precision="INT8",
         threads=8, model_sha="NONE", codec_sha="NONE", init_ms=0,
         first_ms=0, audio_ms=0, synth_ms=0, rtf_milli=0, cue_count=0,
         peak_mib=0, sample_rate=0)
write(d)
try:
    import numpy as np
    import huggingface_hub as hf
    import onnxruntime as ort
    d["sdk"] = version("vieneu")
    assert d["sdk"] == "3.8.5"
    assert "CPUExecutionProvider" in ort.get_available_providers()
    d["stage"] = "MODEL_RESOLVE"
    write(d)
    model = "pnnbao-ump/VieNeu-TTS-v3-Turbo"
    codec = "OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX"
    # Reuse the exact weights already observed in the first benchmark.
    pins = {model: "61b85e3d937fbbacb387714180e8182823512523",
            codec: "ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae"}
    import re
    assert all(re.fullmatch(r"[0-9a-f]{40}", v or "") for v in pins.values())
    d["model_sha"], d["codec_sha"] = pins[model], pins[codec]
    # Freeze both model and codec for every download performed by SDK.
    original = hf.hf_hub_download
    def pinned(repo_id, *args, **kwargs):
        if repo_id in pins:
            kwargs["revision"] = pins[repo_id]
            kwargs["token"] = False
            kwargs["local_files_only"] = repo_id == codec
        return original(repo_id, *args, **kwargs)
    hf.hf_hub_download = pinned
    d["stage"] = "MODEL_INIT"
    write(d)
    from vieneu import Vieneu
    t = time.perf_counter()
    engine = Vieneu(mode="v3turbo", backend="onnx", device="cpu", precision="int8", threads=8)
    d["init_ms"] = int((time.perf_counter()-t)*1000)
    assert engine.backend == "onnx"
    d["sample_rate"] = int(engine.sample_rate)
    assert d["sample_rate"] == 48000
    voice = "Ng\u1ecdc Linh"
    engine.get_preset_voice(voice)
    d["stage"] = "SYNTHESIS"
    write(d)
    texts = [
        "Xin ch\u00e0o, t\u00f4i \u0111ang \u0111\u1ecdc th\u1eed gi\u1ecdng ti\u1ebfng Vi\u1ec7t.",
        "Ch\u00fang ta c\u00f9ng \u0111i ti\u1ebfp, \u0111\u1eebng d\u1eebng l\u1ea1i.",
        "T\u00f4i s\u1ebd quay l\u1ea1i ngay khi m\u1ecdi vi\u1ec7c \u0111\u00e3 \u0111\u01b0\u1ee3c gi\u1ea3i quy\u1ebft."
    ]
    for i, text in enumerate(texts):
        t = time.perf_counter()
        chunks = []
        first = None
        for chunk in engine.infer_stream(text, voice=voice):
            x = np.asarray(chunk, dtype=np.float32).reshape(-1)
            if not x.size: continue
            assert np.isfinite(x).all()
            if first is None: first = int((time.perf_counter()-t)*1000)
            chunks.append(x)
        elapsed = int((time.perf_counter()-t)*1000)
        assert chunks and first is not None
        audio = np.concatenate(chunks)
        assert float(np.max(np.abs(audio))) > 0.001
        pcm = (np.clip(audio,-1,1)*32767).astype("<i2")
        with wave.open(str(root / ("sample-%d.wav" % (i+1))), "wb") as out:
            out.setnchannels(1); out.setsampwidth(2); out.setframerate(48000)
            out.writeframes(pcm.tobytes())
        d["cue_count"] += 1
        d["audio_ms"] += round(len(audio)*1000/48000)
        d["synth_ms"] += elapsed
        if i == 0: d["first_ms"] = first
        d["rtf_milli"] = round(1000*d["synth_ms"]/max(1,d["audio_ms"]))
        class PMC(ctypes.Structure):
            _fields_ = [("cb",wintypes.DWORD),("PageFaultCount",wintypes.DWORD)] + [(n,ctypes.c_size_t) for n in ("PeakWorkingSetSize","WorkingSetSize","QuotaPeakPagedPoolUsage","QuotaPagedPoolUsage","QuotaPeakNonPagedPoolUsage","QuotaNonPagedPoolUsage","PagefileUsage","PeakPagefileUsage")]
        c=PMC(); c.cb=ctypes.sizeof(c)
        kernel=ctypes.windll.kernel32
        kernel.GetCurrentProcess.restype=wintypes.HANDLE
        # HANDLE is pointer-sized; default ctypes int arguments truncate it.
        # Telemetry must not abort a successfully synthesized cue.
        try:
            mem = ctypes.windll.psapi.GetProcessMemoryInfo
            mem.argtypes = [wintypes.HANDLE, ctypes.POINTER(PMC), wintypes.DWORD]
            mem.restype = wintypes.BOOL
            if mem(kernel.GetCurrentProcess(), ctypes.byref(c), c.cb):
                d["peak_mib"] = int(c.PeakWorkingSetSize/(1024*1024))
        except (OSError, OverflowError, ctypes.ArgumentError):
            pass
        write(d)
    d["status"] = "BENCHMARK_COMPLETE"
    d["stage"] = "DONE"
    write(d)
    close = getattr(engine, "close", None)
    if callable(close):
        try: close()
        except Exception: pass
except Exception:
    d["status"] = "BENCHMARK_FAILED"
    write(d)
    raise
'@
# Classify the prior run's traceback locally without emitting private paths.
# Match the exact failed receipt by its measured cue count and model pin.
try {
    $prior = @(Get-ChildItem -LiteralPath $base -Directory -Filter 'benchmark-*' | Where-Object { $_.FullName -ne $root } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 5)
    foreach ($dir in $prior) {
        $metrics = Join-Path $dir.FullName 'metrics.json'
        $err = Join-Path $dir.FullName 'stderr.txt'
        if (-not (Test-Path -LiteralPath $metrics -PathType Leaf) -or -not (Test-Path -LiteralPath $err -PathType Leaf)) { continue }
        $m = Get-Content -LiteralPath $metrics -Raw | ConvertFrom-Json
        if ($m.status -ceq 'BENCHMARK_FAILED' -and $m.cue_count -eq 1 -and $m.init_ms -eq 53285) {
            $tail = (Get-Content -LiteralPath $err -Tail 35 | Out-String)
            $rec.prior_error = if ($tail -match 'GetProcessMemoryInfo|ctypes\.ArgumentError|OverflowError') {'MEMORY_TELEMETRY'} elseif ($tail -match 'MemoryError|bad_alloc|out of memory') {'MEMORY_EXHAUSTED'} elseif ($tail -match 'AssertionError') {'ASSERTION'} else {'OTHER'}
            break
        }
    }
} catch {}
try {
    $pointer = Join-Path $base 'sdk385-ready.txt'
    if (Test-Path -LiteralPath $pointer -PathType Leaf) {
        $exe = [IO.File]::ReadAllText($pointer).Trim()
        $prefix = [IO.Path]::GetFullPath($base) + '\'
        if (-not [IO.Path]::GetFullPath($exe).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'VIENEU_VENV_POINTER_INVALID' }
        $free = [int][Math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024)
        if ($free -lt 3000) { $rec.status='RAM_LOW' }
        else {
            $file = Join-Path $root 'bench.py'
            [IO.File]::WriteAllText($file,$code,[Text.UTF8Encoding]::new($false))
            $si = [Diagnostics.ProcessStartInfo]::new()
            $si.FileName=$exe; $si.WorkingDirectory=$root; $si.UseShellExecute=$false
            $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
            $si.ArgumentList.Add($file)
            $si.Environment['PYTHONNOUSERSITE']='1'
            $si.Environment['HF_HOME']=(Join-Path $base 'hf')
            $si.Environment['HF_HUB_DISABLE_IMPLICIT_TOKEN']='1'
            $si.Environment['HF_HUB_DISABLE_TELEMETRY']='1'
            $si.Environment['HF_HUB_DOWNLOAD_TIMEOUT']='30'
            $si.Environment.Remove('HF_HUB_OFFLINE') | Out-Null
            $si.Environment.Remove('PYTHONPATH') | Out-Null
            $si.Environment.Remove('HF_TOKEN') | Out-Null
            $p=[Diagnostics.Process]::Start($si)
            try {
                $stdout=$p.StandardOutput.ReadToEndAsync()
                $stderr=$p.StandardError.ReadToEndAsync()
                $finished=$p.WaitForExit(450000)
                if(-not $finished){$p.Kill($true);$p.WaitForExit()}
                [IO.File]::WriteAllText((Join-Path $root 'stdout.txt'),$stdout.GetAwaiter().GetResult())
                [IO.File]::WriteAllText((Join-Path $root 'stderr.txt'),$stderr.GetAwaiter().GetResult())
                $metrics=Join-Path $root 'metrics.json'
                if(Test-Path -LiteralPath $metrics -PathType Leaf){
                    $m=Get-Content -LiteralPath $metrics -Raw | ConvertFrom-Json
                    foreach($field in @('status','stage','sdk','precision','threads','model_sha','codec_sha','init_ms','first_ms','audio_ms','synth_ms','rtf_milli','cue_count','peak_mib','sample_rate')){$rec[$field]=$m.$field}
                }
                $tail = (Get-Content -LiteralPath (Join-Path $root 'stderr.txt') -Tail 35 | Out-String)
                if ($p.ExitCode -ne 0) {
                    $rec.error_kind = if ($tail -match 'MemoryError|bad_alloc|out of memory') {'MEMORY_EXHAUSTED'} elseif ($tail -match 'LocalEntryNotFoundError|OfflineModeIsEnabled') {'CACHE_MISSING'} elseif ($tail -match 'AssertionError') {'ASSERTION'} elseif ($tail -match 'ctypes\.ArgumentError|OverflowError') {'MEMORY_TELEMETRY'} else {'OTHER'}
                }
                if(-not $finished){$rec.status='BENCHMARK_TIMEOUT'}
                elseif($p.ExitCode -ne 0){$rec.status='BENCHMARK_FAILED'}
                elseif($rec.status -cne 'BENCHMARK_COMPLETE'){$rec.status='BENCHMARK_FAILED'}
            } finally {$p.Dispose()}
        }
    }
} catch {$rec.status='PROBE_EXCEPTION'}
$rec.elapsed_s=[int]$clock.Elapsed.TotalSeconds
$out=Join-Path $spool ('Receipts\vieneu-benchmark-'+$request.nonce+'.json')
if(Test-Path -LiteralPath $out){throw 'VIENEU_RECEIPT_EXISTS'}
[IO.File]::WriteAllText($out+'.tmp',($rec|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
[IO.File]::Move($out+'.tmp',$out)
Write-Output 'VIENEU_BENCHMARK_RECEIPT_RECORDED'

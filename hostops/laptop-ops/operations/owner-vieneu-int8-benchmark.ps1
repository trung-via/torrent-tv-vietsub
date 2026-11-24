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
$root = Join-Path $base ('r43-mixed-'+$request.nonce)
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
            kwargs["local_files_only"] = True
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

    import threading, urllib.request, math
    q = dict(prior_wavs=0, prior_bad=0, prior_clip_ppm_max=0, prior_rms_min_milli=1000,
             baseline_ok=0, baseline_fail=0, baseline_max_ms=0, mixed_ok=0, mixed_fail=0, mixed_max_ms=0,
             mixed_min_free_mib=0, mixed_peak_cpu_pct=0, torr_pid=0, established_before=0, established_after=0)
    def quality(path):
        with wave.open(str(path), "rb") as f:
            assert f.getnchannels()==1 and f.getsampwidth()==2 and f.getframerate()==48000
            a=np.frombuffer(f.readframes(f.getnframes()),dtype="<i2").astype(np.float64)
        assert len(a)>0
        rms=float(np.sqrt(np.mean((a/32768)**2)))
        clip=round(1000000*np.mean(np.abs(a)>=32760))
        return rms,clip
    prior=os.environ.get("TTV_PRIOR_ROOT","")
    if prior:
        for i in range(1,4):
            try:
                rms,clip=quality(Path(prior)/f"sample-{i}.wav")
                q["prior_wavs"]+=1
                q["prior_clip_ppm_max"]=max(q["prior_clip_ppm_max"],clip)
                q["prior_rms_min_milli"]=min(q["prior_rms_min_milli"],round(1000*rms))
                if rms<0.005 or clip>1000: q["prior_bad"]+=1
            except Exception: q["prior_bad"]+=1
    if not q["prior_wavs"]: q["prior_rms_min_milli"]=0
    q["torr_pid"]=int(os.environ.get("TTV_TORR_PID","0"))
    q["established_before"]=int(os.environ.get("TTV_TORR_EST","0"))
    port=int(os.environ.get("TTV_TORR_PORT","0"))
    class MS(ctypes.Structure):
        _fields_=[("length",wintypes.DWORD),("load",wintypes.DWORD)]+[(n,ctypes.c_uint64) for n in ("totalPhys","availPhys","totalPageFile","availPageFile","totalVirtual","availVirtual","availExtendedVirtual")]
    def memfree():
        x=MS(); x.length=ctypes.sizeof(x)
        return int(x.availPhys//1048576) if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(x)) else 0
    def cpu_ticks():
        a,b,c=wintypes.FILETIME(),wintypes.FILETIME(),wintypes.FILETIME()
        if not ctypes.windll.kernel32.GetSystemTimes(ctypes.byref(a),ctypes.byref(b),ctypes.byref(c)): return None
        return tuple((x.dwHighDateTime<<32)|x.dwLowDateTime for x in (a,b,c))
    def health(prefix):
        if not port: return
        t=time.perf_counter()
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/echo",timeout=1) as res:
                res.read(128)
                assert res.status==200
            q[prefix+"_ok"]+=1
        except Exception: q[prefix+"_fail"]+=1
        q[prefix+"_max_ms"]=max(q[prefix+"_max_ms"],round(1000*(time.perf_counter()-t)))
    for _ in range(5):
        health("baseline"); time.sleep(.4)
    stop=threading.Event()
    def monitor():
        prev=cpu_ticks()
        while not stop.is_set():
            health("mixed")
            free=memfree()
            if free: q["mixed_min_free_mib"]=min(q["mixed_min_free_mib"] or free,free)
            now=cpu_ticks()
            if prev and now:
                idle,kernel,user=(now[i]-prev[i] for i in range(3))
                if kernel+user>0: q["mixed_peak_cpu_pct"]=max(q["mixed_peak_cpu_pct"],round(100*(1-idle/(kernel+user))))
            prev=now
            stop.wait(.5)
    def save_quality():
        (root/"r43-mixed.json").write_text(json.dumps(q),encoding="utf-8")
    save_quality()

    texts = texts + [
      "Hom nay troi dep, chung ta se bat dau mot hanh trinh moi.",
      "Hãy nói cho tôi biết chuyện gì đã xảy ra ở đây.",
      "Đừng lo lắng, chúng ta vẫn còn đủ thời gian để chuẩn bị.",
      "Một lát nữa tôi sẽ trở lại và giải thích mọi chuyện.",
      "Cảm ơn bạn đã giúp đỡ tôi trong suốt thời gian qua.",
      "Nếu có thay đổi, hãy báo ngay cho mọi người biết."
    ]
    texts = texts * 3
    worker=threading.Thread(target=monitor,daemon=True); worker.start()
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
    stop.set(); worker.join(3); save_quality()
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
            $si.Environment['HF_HUB_OFFLINE']='1'
            $si.Environment['TTV_PRIOR_ROOT']=''
            $priorMatches = @(Get-ChildItem -LiteralPath $base -Directory -Filter 'int8-benchmark-*' | Where-Object {
                try {
                    $mm = Get-Content -LiteralPath (Join-Path $_.FullName 'metrics.json') -Raw | ConvertFrom-Json
                    $mm.status -ceq 'BENCHMARK_COMPLETE' -and $mm.cue_count -eq 3 -and $mm.audio_ms -eq 7040 -and $mm.synth_ms -eq 2063 -and $mm.model_sha -ceq '61b85e3d937fbbacb387714180e8182823512523'
                } catch { $false }
            })
            if($priorMatches.Count -eq 1){$si.Environment['TTV_PRIOR_ROOT']=$priorMatches[0].FullName}
            $si.Environment['TTV_TORR_PID']='0';$si.Environment['TTV_TORR_PORT']='0';$si.Environment['TTV_TORR_EST']='0'
            $ts = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -like 'TorrServer*'})
            if($ts.Count -eq 1){
                $si.Environment['TTV_TORR_PID']=[string]$ts[0].Id
                $tcp = @(Get-NetTCPConnection -OwningProcess $ts[0].Id -ErrorAction SilentlyContinue)
                $ports = @($tcp | Where-Object {$_.State -eq 'Listen'} | Select-Object -ExpandProperty LocalPort -Unique)
                if($ports -contains 8090){$si.Environment['TTV_TORR_PORT']='8090'}
                elseif($ports.Count -eq 1){$si.Environment['TTV_TORR_PORT']=[string]$ports[0]}
                $si.Environment['TTV_TORR_EST']=[string]@($tcp | Where-Object {$_.State -eq 'Established' -and [string]$_.LocalPort -eq $si.Environment['TTV_TORR_PORT']}).Count
            }
            $si.Environment.Remove('PYTHONPATH') | Out-Null
            $si.Environment.Remove('HF_TOKEN') | Out-Null
            $p=[Diagnostics.Process]::Start($si)
            try {
                $stdout=$p.StandardOutput.ReadToEndAsync()
                $stderr=$p.StandardError.ReadToEndAsync()
                $finished=$p.WaitForExit(150000)
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
$mixed = Join-Path $root 'r43-mixed.json'
if(Test-Path -LiteralPath $mixed -PathType Leaf){
    $q=Get-Content -LiteralPath $mixed -Raw | ConvertFrom-Json
    if($q.torr_pid -gt 0){
        $connections=@(Get-NetTCPConnection -OwningProcess $q.torr_pid -ErrorAction SilentlyContinue | Where-Object {$_.State -eq 'Established' -and [string]$_.LocalPort -eq $si.Environment['TTV_TORR_PORT']})
        $q.established_after=$connections.Count
    }
    $q.torr_pid=if($q.torr_pid -gt 0){1}else{0}
    $q | Add-Member -NotePropertyName nonce -NotePropertyValue $request.nonce
    $dest=Join-Path $spool ('Receipts\r43-mixed-'+$request.nonce+'.json')
    [IO.File]::WriteAllText($dest+'.tmp',($q|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($dest+'.tmp',$dest)
}
$rec.elapsed_s=[int]$clock.Elapsed.TotalSeconds
$out=Join-Path $spool ('Receipts\vieneu-benchmark-'+$request.nonce+'.json')
if(Test-Path -LiteralPath $out){throw 'VIENEU_RECEIPT_EXISTS'}
[IO.File]::WriteAllText($out+'.tmp',($rec|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
[IO.File]::Move($out+'.tmp',$out)
Write-Output 'VIENEU_BENCHMARK_RECEIPT_RECORDED'

# Prepare private staged files and rollback copies. No installed-file write or restart.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw|ConvertFrom-Json
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner=Join-Path $base 'OwnerBridge'
$app=Join-Path $owner 'app'
$stage=Join-Path $owner ('staged-releases\v13-e1749ae-'+$rq.nonce)
New-Item -ItemType Directory -Path $stage -ErrorAction Stop|Out-Null
$manifest=@'
{"schema":"TTV-G1-V13-NATIVE-CANDIDATE-PACKAGE-V1","status":"SOURCE_PACKAGE_ONLY_NOT_INSTALL_AUTHORIZATION","repository":"trung-via/torrent-tv-vietsub","pr":188,"source_commit":"e1749ae60515731168bd554fe12a05031f50d040","expected_base":"5e3ce11f76828daa2d5aa72cacc7514e74dc152e","supersedes_manifest_commit":"0d952b5e7196dbf58e8b10c48ae8e2504ddcdf7e","activation":{"environment_variable":"TTV_NATIVE_V13","default":"unset","enable":"1","requires_explicit_native_acceptance":true},"files":[{"path":"poc/p2-sub-discovery/agy_v13_browser_evidence.py","expected_prior":{"state":"ABSENT"},"target":{"blob_sha":"26ebb2cc5c46e9b22f5b5e734bdd6031fa4b1b0f","sha256":"fbdabe6773bc44d490fd661dcd6845bf6746ee9c413cfb9ae75b2bd8193ec839","size":25580}},{"path":"poc/p2-sub-discovery/agy_v13_native_producer.py","expected_prior":{"state":"ABSENT"},"target":{"blob_sha":"d16a659b3ad1ddc51398109a03d7ee8f155327c3","sha256":"0b22620bfbb7dfe0ac107702a243cb2db2be1f234df8f0bcc21491170f95e8df","size":33639}},{"path":"poc/p2-sub-discovery/automatic_vietsub_flow.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"7f3da4c737fb7a3ffc5cc960d6fe7b981af261b9","sha256":"e3d1e6da2c8d08ae428f97fbae2d188e5817103dfc8bda7ed2c8a6e13f18792a","size":39082},"target":{"blob_sha":"5ae5b48da30e19192972b263a0844873500e185d","sha256":"e0edd420dccd5445481c84da36008842050e6ec61745a41b98f155136e0bccb7","size":40140}},{"path":"poc/p2-sub-discovery/dual_subtitle_catalog.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"27a0e36d2f19e19c47047aee11ad91033433d84b","sha256":"13ceb5859cfb1a9013177b373d81338a6492151983a90e07fbc761ad647d8206","size":7527},"target":{"blob_sha":"2e70090ff6bc2b252ebe8381acdf89a9edc31e0c","sha256":"c7f73ce7f1188384ca383d92de0447cada219ae33ba99b425646d2932f8fc10d","size":9802}},{"path":"poc/p2-sub-discovery/owner_p3_p4_runtime.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"40c653debe30499f280981ff194fe343729f0bc0","sha256":"a8af95433fc256082636440e74fa3343912f56b4a45b483948af00a9ce4898e3","size":8622},"target":{"blob_sha":"f8b6aa4b22647190e372d91f5bda045e7f17a326","sha256":"8f471755e5f7063e2dcc1aa672d355a132997d317f4b31c7437d6c5c903d3ad6","size":9384}},{"path":"poc/p2-sub-discovery/owner_r2_progressive_registry.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"23cbfb7d0a86a1f9542c4acef6ca7d9f793d943f","sha256":"c234749c1f9165d3436d344546b8b97089ff73c1e361aa225d0e0cb544320346","size":27620},"target":{"blob_sha":"7f9cf98e387f978f657217c517951c3dec506c99","sha256":"b600b3dcaf12fe4030c1e81967e65436256c6d259aa271fe0dd0ea0d2397952f","size":28970}},{"path":"poc/p2-sub-discovery/p3_p4_ready_registry.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"4a9bad66eadc93c072d17ad72f04425b6cbf6bcd","sha256":"7a11638820772d31e0ada488dc8c0410f94c294f1af469d45fc2beb72571a1e6","size":14027},"target":{"blob_sha":"e4eca0af41264dec07173018e3605c321a745f2b","sha256":"ff893fd4208bb644fef7c4b16558a0180bfd58ddd384411ec49ca297cc63fc72","size":14140}}],"requirements":["Verify installed full base before apply; mismatch holds. This manifest covers #188 runtime delta only, not uninstalled #186 or ancestors.","Stage exact source; verify SHA-256 and imports before apply.","Preserve legacy and native EN pointers, SRTs, checkpoints and unknown-effect claims; reconcile pending events and verify idle maintenance, rollback backup; no automatic restart/activation from this manifest.","Verify loaded PID-bound source and native opt-in at approved activation. Do not change 9444 or #187.","Retain prior verification receipts and raw evidence; old verification revisions revalidate locally, never trigger a download solely for revision drift."],"rollback":"Unset TTV_NATIVE_V13 and restore reviewed backup if needed. Native-only pointer is ignored in default mode; no cache/checkpoint deletion."}
'@|ConvertFrom-Json
$phase='STAGE'
$code='V13_PREP_PRIVATE_ERROR'
try {
 foreach($f in $manifest.files){
   $dst=Join-Path $stage ('candidate\'+$f.path)
   New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force|Out-Null
   Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/e1749ae60515731168bd554fe12a05031f50d040/'+$f.path) -OutFile $dst -TimeoutSec 30
   if((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLowerInvariant() -cne $f.target.sha256){throw 'STAGE_HASH'}
 }
 $gateRel='poc/p3-vietsub-trigger/activation_gate.py'
 $gateFile=Join-Path $stage ('comparison\'+$gateRel)
 New-Item -ItemType Directory -Path (Split-Path -Parent $gateFile) -Force|Out-Null
 Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/e1749ae60515731168bd554fe12a05031f50d040/'+$gateRel) -OutFile $gateFile -TimeoutSec 30
 $phase='COMPARE'
 $py=@'
import ast, dataclasses, hashlib, importlib.util, json, os, pathlib, shutil, sys
app, stage = map(pathlib.Path,sys.argv[1:3])
manifest=json.loads("{\"schema\":\"TTV-G1-V13-NATIVE-CANDIDATE-PACKAGE-V1\",\"status\":\"SOURCE_PACKAGE_ONLY_NOT_INSTALL_AUTHORIZATION\",\"repository\":\"trung-via/torrent-tv-vietsub\",\"pr\":188,\"source_commit\":\"e1749ae60515731168bd554fe12a05031f50d040\",\"expected_base\":\"5e3ce11f76828daa2d5aa72cacc7514e74dc152e\",\"supersedes_manifest_commit\":\"0d952b5e7196dbf58e8b10c48ae8e2504ddcdf7e\",\"activation\":{\"environment_variable\":\"TTV_NATIVE_V13\",\"default\":\"unset\",\"enable\":\"1\",\"requires_explicit_native_acceptance\":true},\"files\":[{\"path\":\"poc/p2-sub-discovery/agy_v13_browser_evidence.py\",\"expected_prior\":{\"state\":\"ABSENT\"},\"target\":{\"blob_sha\":\"26ebb2cc5c46e9b22f5b5e734bdd6031fa4b1b0f\",\"sha256\":\"fbdabe6773bc44d490fd661dcd6845bf6746ee9c413cfb9ae75b2bd8193ec839\",\"size\":25580}},{\"path\":\"poc/p2-sub-discovery/agy_v13_native_producer.py\",\"expected_prior\":{\"state\":\"ABSENT\"},\"target\":{\"blob_sha\":\"d16a659b3ad1ddc51398109a03d7ee8f155327c3\",\"sha256\":\"0b22620bfbb7dfe0ac107702a243cb2db2be1f234df8f0bcc21491170f95e8df\",\"size\":33639}},{\"path\":\"poc/p2-sub-discovery/automatic_vietsub_flow.py\",\"expected_prior\":{\"state\":\"EXACT_BASE_BYTES\",\"blob_sha\":\"7f3da4c737fb7a3ffc5cc960d6fe7b981af261b9\",\"sha256\":\"e3d1e6da2c8d08ae428f97fbae2d188e5817103dfc8bda7ed2c8a6e13f18792a\",\"size\":39082},\"target\":{\"blob_sha\":\"5ae5b48da30e19192972b263a0844873500e185d\",\"sha256\":\"e0edd420dccd5445481c84da36008842050e6ec61745a41b98f155136e0bccb7\",\"size\":40140}},{\"path\":\"poc/p2-sub-discovery/dual_subtitle_catalog.py\",\"expected_prior\":{\"state\":\"EXACT_BASE_BYTES\",\"blob_sha\":\"27a0e36d2f19e19c47047aee11ad91033433d84b\",\"sha256\":\"13ceb5859cfb1a9013177b373d81338a6492151983a90e07fbc761ad647d8206\",\"size\":7527},\"target\":{\"blob_sha\":\"2e70090ff6bc2b252ebe8381acdf89a9edc31e0c\",\"sha256\":\"c7f73ce7f1188384ca383d92de0447cada219ae33ba99b425646d2932f8fc10d\",\"size\":9802}},{\"path\":\"poc/p2-sub-discovery/owner_p3_p4_runtime.py\",\"expected_prior\":{\"state\":\"EXACT_BASE_BYTES\",\"blob_sha\":\"40c653debe30499f280981ff194fe343729f0bc0\",\"sha256\":\"a8af95433fc256082636440e74fa3343912f56b4a45b483948af00a9ce4898e3\",\"size\":8622},\"target\":{\"blob_sha\":\"f8b6aa4b22647190e372d91f5bda045e7f17a326\",\"sha256\":\"8f471755e5f7063e2dcc1aa672d355a132997d317f4b31c7437d6c5c903d3ad6\",\"size\":9384}},{\"path\":\"poc/p2-sub-discovery/owner_r2_progressive_registry.py\",\"expected_prior\":{\"state\":\"EXACT_BASE_BYTES\",\"blob_sha\":\"23cbfb7d0a86a1f9542c4acef6ca7d9f793d943f\",\"sha256\":\"c234749c1f9165d3436d344546b8b97089ff73c1e361aa225d0e0cb544320346\",\"size\":27620},\"target\":{\"blob_sha\":\"7f9cf98e387f978f657217c517951c3dec506c99\",\"sha256\":\"b600b3dcaf12fe4030c1e81967e65436256c6d259aa271fe0dd0ea0d2397952f\",\"size\":28970}},{\"path\":\"poc/p2-sub-discovery/p3_p4_ready_registry.py\",\"expected_prior\":{\"state\":\"EXACT_BASE_BYTES\",\"blob_sha\":\"4a9bad66eadc93c072d17ad72f04425b6cbf6bcd\",\"sha256\":\"7a11638820772d31e0ada488dc8c0410f94c294f1af469d45fc2beb72571a1e6\",\"size\":14027},\"target\":{\"blob_sha\":\"e4eca0af41264dec07173018e3605c321a745f2b\",\"sha256\":\"ff893fd4208bb644fef7c4b16558a0180bfd58ddd384411ec49ca297cc63fc72\",\"size\":14140}}],\"requirements\":[\"Verify installed full base before apply; mismatch holds. This manifest covers #188 runtime delta only, not uninstalled #186 or ancestors.\",\"Stage exact source; verify SHA-256 and imports before apply.\",\"Preserve legacy and native EN pointers, SRTs, checkpoints and unknown-effect claims; reconcile pending events and verify idle maintenance, rollback backup; no automatic restart/activation from this manifest.\",\"Verify loaded PID-bound source and native opt-in at approved activation. Do not change 9444 or #187.\",\"Retain prior verification receipts and raw evidence; old verification revisions revalidate locally, never trigger a download solely for revision drift.\"],\"rollback\":\"Unset TTV_NATIVE_V13 and restore reviewed backup if needed. Native-only pointer is ignored in default mode; no cache/checkpoint deletion.\"}")
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def blob(p):
    raw=p.read_bytes()
    return hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()
gate="poc/p3-vietsub-trigger/activation_gate.py"
candidate=stage/"comparison"/gate
if blob(candidate)!="22bbc578c9206290a072c7f2dcaca42e25c8a6a6":raise ValueError("candidate gate blob")
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec)
    sys.modules[name]=mod
    spec.loader.exec_module(mod)
    return mod
old=load("installed_gate",app/gate)
new=load("candidate_gate",candidate)
def cases(mod):
    common=dict(kind="PLAY_REQUEST_ACCEPTED",attested=True,active=True,server_id="owner",
       tv_session_id="session_a",torrent_hash="a"*40,file_index=2,video_name="Example.2017.mkv",
       owner_auto_enabled=True,subtitle_choice="REQUESTED",media_rights_approved=True,local_vi_state="ABSENT")
    overrides=[{},dict(local_vi_state="PRESENT"),dict(local_vi_state="UNKNOWN"),
       dict(subtitle_choice="ON"),dict(subtitle_choice="OFF"),dict(subtitle_choice="OTHER"),
       dict(active=False),dict(attested=False),dict(media_rights_approved=False),
       dict(owner_auto_enabled=False),dict(kind="SEEK"),dict(file_index=-1),
       dict(kind="NEXT_QUEUE_ITEM_ACCEPTED"),dict(local_vi_state="INVALID")]
    decisions=[mod.evaluate_playback(mod.PlaybackSelected(**(common|x))) for x in overrides]
    gate=mod.ActivationDeduplicator()
    a=mod.PlaybackSelected(**common); b=dataclasses.replace(a,torrent_hash="b"*40, tv_session_id="session_b")
    seq=[gate.consider(x) for x in (a,a,b,a)]
    gate.on_session_closed();seq.append(gate.consider(a))
    return [[x.status,x.reason,x.local_fingerprint] for x in decisions],[[x.status,x.reason,x.local_fingerprint] for x in seq]
oc,osq=cases(old);nc,nsq=cases(new)
def short(rows):return "".join(x[0][0] for x in rows)
def parts(path):
    t=ast.parse(path.read_bytes().decode("utf-8-sig"))
    return {n.name:ast.dump(n,include_attributes=False) for n in t.body if isinstance(n,(ast.ClassDef,ast.FunctionDef))}
a,b=parts(app/gate),parts(candidate)
changed=[k for k in sorted(set(a)|set(b)) if a.get(k)!=b.get(k)]
# Save exact local rollback copies of the target files and gate; this does not stop or replace Owner.
rollback=[]
for f in manifest["files"]:
    rel=f["path"];p=app/rel; prior=f["expected_prior"]; target=stage/"candidate"/rel
    if sha(target)!=f["target"]["sha256"]:raise ValueError("staged hash")
    if prior["state"]=="ABSENT":
        if p.exists() or p.is_symlink():raise ValueError("prior unexpected")
        rollback.append({"path":rel,"state":"ABSENT"})
    else:
        if p.is_symlink() or not p.is_file() or sha(p)!=prior["sha256"]:raise ValueError("prior mismatch")
        saved=stage/"rollback"/rel;saved.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,saved)
        if sha(saved)!=prior["sha256"]:raise ValueError("backup hash")
        rollback.append({"path":rel,"state":"PRESENT","sha256":sha(saved)})
p=app/gate;saved=stage/"rollback"/gate;saved.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,saved)
if sha(saved)!=sha(p):raise ValueError("gate backup")
rollback.append({"path":gate,"state":"PRESENT","sha256":sha(saved),"comparison_only":True})
(stage/"rollback.json").write_text(json.dumps(rollback,indent=2),encoding="utf-8")
(stage/"gate-comparison.json").write_text(json.dumps({"installed":oc,"candidate":nc,"installed_sequence":osq,"candidate_sequence":nsq,"changed_ast_definitions":changed,"installed_gate_sha256":sha(p),"candidate_gate_sha256":sha(candidate)},indent=2),encoding="utf-8")
# Actual native module overlay against existing dependencies and installed gate.
sys.path[:0]=[str(stage/"candidate/poc/p2-sub-discovery"),str(app/"poc/p2-sub-discovery"),str(app/"poc/p2-aisub"),str(app/"poc/p3-vietsub-trigger")]
import importlib
for name in ("activation_gate","agy_v13_native_producer","agy_v13_browser_evidence","owner_p3_p4_entrypoint","owner_p3_p4_runtime","owner_r2_progressive_registry","p3_p4_ready_registry","automatic_vietsub_flow"):
    importlib.import_module(name)
from automatic_vietsub_flow import build_owner_auto_flow
from agy_v13_browser_evidence import VERIFICATION_REVISION
def forbidden(*args,**kw):raise AssertionError("external effect forbidden in smoke")
os.environ["TTV_LEAN120_PARALLEL_BATCHES"]="3"
flow=build_owner_auto_flow(enabled=True,cache_root=stage/"smoke-cache",state_root=stage/"smoke-state",model_preflight=forbidden,native_browser_runner=forbidden)
assert flow.source_acquirer.native_v13 is True and flow.worker.first_window_cues==50 and flow.worker.parallel_batches==3 and flow.worker.profile.model=="gemini-4-hydrogen-low"
assert VERIFICATION_REVISION=="V13.1-BR03-1"
assert pathlib.Path(sys.modules["activation_gate"].__file__).resolve()==(app/gate).resolve()
print("V13_PREP_F7B6I1O"+short(oc)+"C"+short(nc)+"S"+short(osq)+"T"+short(nsq))
'@
 $file=Join-Path $stage 'prepare.py'
 [IO.File]::WriteAllText($file,$py,[Text.UTF8Encoding]::new($false))
 $lines=@(& py -3 -I -B $file $app $stage 2> (Join-Path $stage 'stderr.txt'))
 if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^V13_PREP_F7B6I1O[DSHW]{14}C[DSHW]{14}S[DSHW]{5}T[DSHW]{5}$'){$code=[string]$lines[0]}
 else{$code='V13_PREP_HOLD_COMPARE_OR_IMPORT'}
}catch{$code='V13_PREP_HOLD_'+$phase}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

# Owner baseline inventory only; no install, restart, provider, TV or cache write.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -eq 'true' -or -not [Environment]::UserInteractive){throw 'OWNER_CONTEXT_REQUIRED'}
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$rq=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$base=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner=Join-Path $base 'OwnerBridge'
$app=Join-Path $owner 'app'
$report=Join-Path $base ('NativeBrowserTest\v13-installed-baseline-'+$rq.nonce)
New-Item -ItemType Directory -Path $report -ErrorAction Stop|Out-Null
$taskOk=0;$pidOk=0;$launcher=0;$native=0;$profile=0;$parallel=0;$backup=0
$since=0
try {
 $task=Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $tsid=[string]$task.Principal.UserId
 if($tsid -notmatch '^S-\d'){$tsid=([Security.Principal.NTAccount]::new($tsid).Translate([Security.Principal.SecurityIdentifier])).Value}
 if($tsid -ceq $sid -and $task.Principal.LogonType -ieq 'Interactive' -and [string]$task.State -eq 'Running' -and @($task.Actions).Count -eq 1){$taskOk=1}
 $action=[string]$task.Actions[0].Arguments
 if($action -match '(?i)-File\s+"([^"]+start-owner-session-agent\.ps1)"'){
   $lp=$Matches[1]
   if($lp.StartsWith($owner+'\',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $lp -PathType Leaf)){
      $launcher=1
      $lt=[IO.File]::ReadAllText($lp)
      if($lt -match '(?im)^\s*\$env:TTV_NATIVE_V13\s*=\s*[''"]1[''"]'){$native=1}
      if($lt -match '(?im)^\s*\$env:TTV_LEAN120_PARALLEL_BATCHES\s*=\s*[''"]([123])[''"]'){$parallel=[int]$Matches[1]}
   }
 }
 $health=Get-Content -LiteralPath (Join-Path $owner 'agent-health.json') -Raw|ConvertFrom-Json
 $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]$health.observed_utc_epoch
 if($health.schema -ceq 'TTV-OWNER-AGENT-HEALTH-V1' -and $health.state -ceq 'READY' -and $age -ge 0 -and $age -le 30){
   $proc=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$health.pid)
   if($proc -and [string]$proc.CommandLine -match 'owner_p3_p4_entrypoint\.py'){
      $who=Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
      if($who.ReturnValue -eq 0 -and $who.Sid -ceq $sid){$pidOk=1;$since=([DateTimeOffset]$proc.CreationDate).ToUnixTimeSeconds()}
   }
 }
} catch {}
try {
 $pr=Get-Content -LiteralPath (Join-Path $app 'poc\p2-aisub\translator_profile.json') -Raw|ConvertFrom-Json
 if($pr.provider -ceq 'antigravity' -and $pr.model -ceq 'gemini-4-hydrogen-low' -and $pr.thinking_level -ceq 'low'){$profile=1}
}catch{}
try {
 $bd=Get-Item -LiteralPath (Join-Path $owner 'backups') -Force
 if($bd.PSIsContainer -and -not ($bd.Attributes -band [IO.FileAttributes]::ReparsePoint)){$backup=1}
}catch{}
$py=@'
import hashlib,json,pathlib,sys
base,owner,app,report=map(pathlib.Path,sys.argv[1:5]); since=int(sys.argv[5])
expected={"poc/p2-aisub/agy_handoff.py":"3badb560d8656eaff67bdcae406aed8b29177240","poc/p2-aisub/assumed_source_handoff.py":"386645aabba038139c0304aa46cd9e538eecdaf9","poc/p2-aisub/automatic_lean120_worker.py":"2d6c0a19d86f44b9e033b4fed59a6d778da9274b","poc/p2-aisub/benchmark36.py":"d8a3e9c40a54b73d2a9bdf02445859503696db13","poc/p2-aisub/benchmark36_human.py":"448ce8a4b7b9c84e6b972935a0a6f5547cf55256","poc/p2-aisub/blind_semantic_gate.py":"6bb32acfc497a43447d745869ddc664869f4c9d0","poc/p2-aisub/brain36_context_gate.py":"1921c698ec2cfa69b36902ff078d989da49ad328","poc/p2-aisub/brain_fastpath_v04_experiment.py":"b57082a32ec655ab51824c9e74e3eae76f83f076","poc/p2-aisub/brain_semantic_review_v2h.py":"0db7765fff38aafd044be98c188d364e2ae40c85","poc/p2-aisub/brain_v04_thor_replay.py":"eaaa0ebf49f7f5598829669c7a9d9901c635b899","poc/p2-aisub/cached_en_direct_handoff.py":"f2f38d58e998f8566b92fe55084576bfbfe2745b","poc/p2-aisub/cloud_contract.py":"7014dabc532801a47871b4f9a380ef4cd135c932","poc/p2-aisub/context_challenge_v2i.py":"82880f322c99eeb8bb4cfef994e293cc14a715e8","poc/p2-aisub/context_engine_v2.py":"04eb7bfbc9c057a374c6fde95166a59bad0688b3","poc/p2-aisub/context_memory_v2b.py":"8d77a2ba4091a847d6cdb58cc59bf2031d9b327e","poc/p2-aisub/context_review_v2c.py":"6a489222de72bfb10386c52cc61b9aa25df92605","poc/p2-aisub/cue_pipeline.py":"cf6e55625dc1dc7757f5971f6dfb2dd283175da9","poc/p2-aisub/full_srt_pair_qa.py":"45c7104585634ac834691542ebcd68a5e2c80a83","poc/p2-aisub/lan_revision_feed.py":"a7a81bcb18ede01d51fd6b0694d1073b9d9956a4","poc/p2-aisub/lean120_api.py":"03967f369ab5aca3308c7bb397b6702003c5cd30","poc/p2-aisub/p4_tls.py":"74a3b4290d60329261ea38bf5aab9ef0425bf2ac","poc/p2-aisub/paired_activation.py":"c950b087d04c844f93f6c19f8c5c885d36a59eb2","poc/p2-aisub/progressive_handoff.py":"fa160224953486e8edf9c662546ed6debb814c95","poc/p2-aisub/r32_existing_vi_rehydrate.py":"0f8831560a9649ea6c146100e487e620b6d6f777","poc/p2-aisub/r33_new_film_core.py":"639e43e5ab384cc3fd29d0efce5ecc2872191e07","poc/p2-aisub/r3_2_continuous_queue.py":"a70751f7b772fdeecec42c8d19c5c657eabfd94f","poc/p2-aisub/revision_delivery.py":"039805c06b6f38910ef650de49b345f39739539c","poc/p2-aisub/run_assumed_source_gateway.py":"4be58e2633fb73ed07ca2d74d627dcf72cb8c48f","poc/p2-aisub/subtitle_quality.py":"75e1ef223b72f646b35a6f7784faa1a2d5be69fe","poc/p2-aisub/synthetic_mock_feed.py":"99450521303cb5ff07039dd218ab982bdc7ac4a5","poc/p2-aisub/translator_gateway.py":"6f70fc25694c130f6fbd6f3047158c47ea36274d","poc/p2-aisub/verified_source_manifest.py":"f790b00aeeebc46ff27c65603f600e92615c4094","poc/p2-aisub/verified_vietsub_ready.py":"0e9fe95b64f14465d48b627e7b936fcba04bc793","poc/p2-sub-discovery/agy_opensubtitles_acquisition.py":"ed74ac2022afbdf86da50c0c68e8a3f009e3ea4e","poc/p2-sub-discovery/automatic_vietsub_flow.py":"7f3da4c737fb7a3ffc5cc960d6fe7b981af261b9","poc/p2-sub-discovery/brain_english_inbox.py":"f80bf0c0ce8ad32cb6daba3ecbf272f7fef99ef9","poc/p2-sub-discovery/dual_subtitle_catalog.py":"27a0e36d2f19e19c47047aee11ad91033433d84b","poc/p2-sub-discovery/local_en_direct.py":"df5974b9b572b57a06e0cf78c1e105f498780f86","poc/p2-sub-discovery/matcher.py":"6cf7020010c926931ab6a433fd9210e84fa24a43","poc/p2-sub-discovery/opensubtitles.py":"b6e4919170c09e306db65f631c1e65949768b297","poc/p2-sub-discovery/owner_en_single_trial.py":"e22478d839dbfcd9735d48f330cb8a4379823d6f","poc/p2-sub-discovery/owner_full_flow_snapshot_v4.py":"ccfac431c157e3c59fd32975897e6f2f28f30c7e","poc/p2-sub-discovery/owner_hostops_snapshot.py":"101dc9ae5e35824ed1a795bc30c49fc26e10a034","poc/p2-sub-discovery/owner_hostops_snapshot_v3.py":"90700a9fc767842e14d0ad1b395157e816c69666","poc/p2-sub-discovery/owner_p3_p4_diagnostics.py":"a26a753d3641f8e4aeddb713c534f50ddcb3d076","poc/p2-sub-discovery/owner_p3_p4_entrypoint.py":"989d947c1f75fe13ac28add4fa68db194bf3952f","poc/p2-sub-discovery/owner_p3_p4_policy_r0.py":"39a83a02dcffd3c60b36d74484ac6f2d41cbe42e","poc/p2-sub-discovery/owner_p3_p4_private_policy.py":"8eb45f20bc20fe57e59ca96ea3c1dbffd4b2adc3","poc/p2-sub-discovery/owner_p3_p4_runtime.py":"40c653debe30499f280981ff194fe343729f0bc0","poc/p2-sub-discovery/owner_r2_progressive_registry.py":"23cbfb7d0a86a1f9542c4acef6ca7d9f793d943f","poc/p2-sub-discovery/owner_r2_progressive_worker.py":"b363c58a0c882780065ec3f0b92150a5674884f9","poc/p2-sub-discovery/owner_r2_verified_processor.py":"223362ae784f247aa0271366f666f4a3c8f5fbec","poc/p2-sub-discovery/owner_search.py":"1927467eab708f2c05eb40f2246a284015a6edb5","poc/p2-sub-discovery/owner_search_probe.py":"c8ab5e53264c20b1a1408895893fc169b859e366","poc/p2-sub-discovery/owner_selected_file_resolver.py":"922736d788b1da4341cd35580f79fb34206e0dd9","poc/p2-sub-discovery/owner_session_bridge.py":"7154d2f32bb30fe3fa811a59cae812bcb4c67767","poc/p2-sub-discovery/owner_torrserver_embedded_en.py":"ca4e266ae7a51c4df15612f50d1dd2b7842ee829","poc/p2-sub-discovery/owner_torrserver_ffp_tracks.py":"ea73c65a7efe42d547f9412dbfee2f3e314c325c","poc/p2-sub-discovery/owner_torrserver_readonly.py":"48118229ad263faa8f707fd7a019db104a2d28b3","poc/p2-sub-discovery/owner_torrserver_subs.py":"daaa5481a8a8d396a545f9cadeba6289709a27d2","poc/p2-sub-discovery/owner_vi_en_trial.py":"6aca909296e86b915e78967c834ca9c11f0fe7dc","poc/p2-sub-discovery/owner_vi_trial.py":"8519e655f2778ee2bf24188b1521a92786ef5432","poc/p2-sub-discovery/owner_vietsub_pipeline.py":"c644c7c1988268738094c21e07a8faab92d24a50","poc/p2-sub-discovery/p3_ingress_telemetry.py":"f3545e391fcd47f281323f91020d16a863b372ad","poc/p2-sub-discovery/p3_owner_current_redmi.py":"911924447b50ff22c1940b4bd429ec4eb049c3ba","poc/p2-sub-discovery/p3_owner_replay_journal.py":"9baeb313237fe1353dd11f8fbfb7ad205903551f","poc/p2-sub-discovery/p3_owner_state_wiring.py":"0f9039523abf9a93a9a5297e10841356a2e7bf03","poc/p2-sub-discovery/p3_owner_state_wiring_r0.py":"b32cb5a39f5af3b45ee8669687d25d049032bd54","poc/p2-sub-discovery/p3_owner_state_wiring_r2.py":"80c0432c15a43bd4090aa611db466535d1874ae4","poc/p2-sub-discovery/p3_p4_media_key.py":"45d439eabb0e00299869e5c453ed1544802088eb","poc/p2-sub-discovery/p3_p4_ready_registry.py":"4a9bad66eadc93c072d17ad72f04425b6cbf6bcd","poc/p2-sub-discovery/p3_p4_shared_https_route.py":"5e53b12544695e7785c44852a689559fd4bb0e75","poc/p2-sub-discovery/p3_p4_shared_https_route_r0.py":"57c3f14556aa761a377c7b4c67e8fad50a860b51","poc/p2-sub-discovery/p3_p4_triage_readonly.py":"4dfcef4148ab93a63352161410ecafb2b049c761","poc/p2-sub-discovery/p3_redmi_current_state.py":"c9aa878668d7f01fbae0cfe94db5283e3beeb765","poc/p2-sub-discovery/p3_signed_playback_signal.py":"b20e6687f1e8052c342b7a022f21188ee5f41473","poc/p2-sub-discovery/p3_signed_signal_to_owner.py":"4d10729df04f21090d290fa5ae8840f898eaf28a","poc/p2-sub-discovery/smoke_api.py":"5d1f84ff652a013eea13076a303fc93de045b96f","poc/p2-sub-discovery/timed_translation.py":"a941cd956ac44de7ba8ed5604ece2da98218a977","poc/p2-sub-discovery/translation_api_contract.py":"c3fbae389390f909d371b66326c94ccfde9c2a7b","poc/p2-sub-discovery/trusted_playback_to_owner.py":"0f5a5301213e91003859ca7993e523d6ba77d384","poc/p2-sub-discovery/verified_v3_processor.py":"c7641c85374672c64fc2afe7b145a59207aaa2b4","poc/p2-sub-discovery/vi_en_fallback.py":"58036eeb24bd4b590403119675f0a2c4cf37fb8f","poc/p3-vietsub-trigger/activation_gate.py":"22bbc578c9206290a072c7f2dcaca42e25c8a6a6"}
delta=[{"path":"poc/p2-sub-discovery/agy_v13_browser_evidence.py","expected_prior":{"state":"ABSENT"},"target":{"blob_sha":"26ebb2cc5c46e9b22f5b5e734bdd6031fa4b1b0f","sha256":"fbdabe6773bc44d490fd661dcd6845bf6746ee9c413cfb9ae75b2bd8193ec839","size":25580}},{"path":"poc/p2-sub-discovery/agy_v13_native_producer.py","expected_prior":{"state":"ABSENT"},"target":{"blob_sha":"d16a659b3ad1ddc51398109a03d7ee8f155327c3","sha256":"0b22620bfbb7dfe0ac107702a243cb2db2be1f234df8f0bcc21491170f95e8df","size":33639}},{"path":"poc/p2-sub-discovery/automatic_vietsub_flow.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"7f3da4c737fb7a3ffc5cc960d6fe7b981af261b9","sha256":"e3d1e6da2c8d08ae428f97fbae2d188e5817103dfc8bda7ed2c8a6e13f18792a","size":39082},"target":{"blob_sha":"5ae5b48da30e19192972b263a0844873500e185d","sha256":"e0edd420dccd5445481c84da36008842050e6ec61745a41b98f155136e0bccb7","size":40140}},{"path":"poc/p2-sub-discovery/dual_subtitle_catalog.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"27a0e36d2f19e19c47047aee11ad91033433d84b","sha256":"13ceb5859cfb1a9013177b373d81338a6492151983a90e07fbc761ad647d8206","size":7527},"target":{"blob_sha":"2e70090ff6bc2b252ebe8381acdf89a9edc31e0c","sha256":"c7f73ce7f1188384ca383d92de0447cada219ae33ba99b425646d2932f8fc10d","size":9802}},{"path":"poc/p2-sub-discovery/owner_p3_p4_runtime.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"40c653debe30499f280981ff194fe343729f0bc0","sha256":"a8af95433fc256082636440e74fa3343912f56b4a45b483948af00a9ce4898e3","size":8622},"target":{"blob_sha":"f8b6aa4b22647190e372d91f5bda045e7f17a326","sha256":"8f471755e5f7063e2dcc1aa672d355a132997d317f4b31c7437d6c5c903d3ad6","size":9384}},{"path":"poc/p2-sub-discovery/owner_r2_progressive_registry.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"23cbfb7d0a86a1f9542c4acef6ca7d9f793d943f","sha256":"c234749c1f9165d3436d344546b8b97089ff73c1e361aa225d0e0cb544320346","size":27620},"target":{"blob_sha":"7f9cf98e387f978f657217c517951c3dec506c99","sha256":"b600b3dcaf12fe4030c1e81967e65436256c6d259aa271fe0dd0ea0d2397952f","size":28970}},{"path":"poc/p2-sub-discovery/p3_p4_ready_registry.py","expected_prior":{"state":"EXACT_BASE_BYTES","blob_sha":"4a9bad66eadc93c072d17ad72f04425b6cbf6bcd","sha256":"7a11638820772d31e0ada488dc8c0410f94c294f1af469d45fc2beb72571a1e6","size":14027},"target":{"blob_sha":"e4eca0af41264dec07173018e3605c321a745f2b","sha256":"ff893fd4208bb644fef7c4b16558a0180bfd58ddd384411ec49ca297cc63fc72","size":14140}}]
def file_status(rel,sha):
    p=app/rel
    if not p.exists():return "M"
    if p.is_symlink() or not p.is_file():return "D"
    raw=p.read_bytes()
    def blob(x):return hashlib.sha1(b"blob "+str(len(x)).encode()+b"\0"+x).hexdigest()
    if blob(raw)==sha:return "E"
    if blob(raw.replace(b"\r\n",b"\n"))==sha:return "L"
    return "D"
rows={rel:file_status(rel,sha) for rel,sha in expected.items()}
def delta_status(f):
    p=app/f["path"];prior=f["expected_prior"]
    if not p.exists() and not p.is_symlink():return "A" if prior["state"]=="ABSENT" else "M"
    if p.is_symlink() or not p.is_file():return "D"
    raw=p.read_bytes()
    sha=hashlib.sha256(raw).hexdigest()
    if sha==f["target"]["sha256"]:return "T"
    if prior["state"]=="ABSENT":return "D"
    if sha==prior["sha256"]:return "E"
    if hashlib.sha256(raw.replace(b"\r\n",b"\n")).hexdigest()==prior["sha256"]:return "L"
    return "D"
d="".join(delta_status(f) for f in delta)
extra=[];newer=0
for folder in ("p2-sub-discovery","p2-aisub","p3-vietsub-trigger"):
    for p in (app/"poc"/folder).glob("*.py"):
        rel=p.relative_to(app).as_posix()
        if p.name.startswith(("test_","fake_")):continue
        if rel not in expected:extra.append(rel)
        if since and p.stat().st_mtime>since+1:newer+=1
inbox=owner/"inbox";state=base/"P2/auto-lean120-state";cache=base/"subtitle-trials"
def activity():
    if any(not p.is_dir() or p.is_symlink() for p in (inbox,state,cache)):return None
    events=list(inbox.glob("event-*.json"))
    blocked=list(inbox.glob("event-*.blocked"))
    claims=[p for p in inbox.glob("claim-*") if not (inbox/("event-"+p.name[6:]+".done")).is_file() and not (inbox/("event-"+p.name[6:]+".review")).is_file()]
    locks=[p for p in state.rglob("*") if p.is_file() and (p.name=="active.lock" or p.name.endswith(".inflight"))]
    browser=(cache/".native-v13/browser.pending").exists()
    return [len(events),len(blocked),len(claims),len(locks),int(browser)]
first=activity()
import time
time.sleep(2)
second=activity()
stable=first is not None and first==second
v=second if second is not None else [999]*5
(report/"baseline.json").write_text(json.dumps({"source":"e1749ae60515731168bd554fe12a05031f50d040","base":"5e3ce11f76828daa2d5aa72cacc7514e74dc152e","modules":rows,"delta":d,"extra":extra,"newer_than_worker":newer,"activity_before":first,"activity_after":second},sort_keys=True),encoding="utf-8")
print("D"+d+"E"+str(list(rows.values()).count("E"))+"L"+str(list(rows.values()).count("L"))+"M"+str(list(rows.values()).count("M"))+"X"+str(list(rows.values()).count("D"))+"U"+str(len(extra))+"W"+str(newer)+"S"+str(int(stable))+"Q"+str(v[0])+"B"+str(v[1])+"C"+str(v[2])+"I"+str(v[3])+"N"+str(v[4]))
'@
$file=Join-Path $report 'baseline.py'
[IO.File]::WriteAllText($file,$py,[Text.UTF8Encoding]::new($false))
$lines=@(& py -3 -I -B $file $base $owner $app $report $since 2> (Join-Path $report 'stderr.txt'))
$code='V13_BASELINE_PRIVATE_ERROR'
if($LASTEXITCODE -eq 0 -and $lines.Count -eq 1 -and [string]$lines[0] -cmatch '^D[AEMLDT]{7}E\d+L\d+M\d+X\d+U\d+W\d+S[01]Q\d+B\d+C\d+I\d+N\d+$'){
 $code='V13_BASE_O'+$taskOk+'H'+$pidOk+'J'+$launcher+'V'+$native+'P'+$profile+'R'+$parallel+'K'+$backup+[string]$lines[0]
}
$doc=@{schema='TTV-ODYSSEY-STAGE-V1';nonce=$rq.nonce;reason=$code}
[IO.File]::WriteAllText((Join-Path $spool ('Receipts\odyssey-stage-'+$rq.nonce+'.json')),($doc|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output $code

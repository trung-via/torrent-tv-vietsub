# Owner-approved, bounded A/B: synthetic subtitle data only; no production mutation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\app\poc\p2-aisub'
$spool=Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$r=Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
$dest=Join-Path $spool ('Receipts\hydrogen-benchmark-'+$r.nonce+'.json')
$code=@'
import json, pathlib, sys, time, re, subprocess
root=pathlib.Path(sys.argv[1])
dest=pathlib.Path(sys.argv[2])
nonce=sys.argv[3]
sys.path.insert(0,str(root))
from lean120_api import ModelProfile, load_profile
from translator_gateway import translate_window, preflight_provider
from progressive_handoff import ProgressiveSubtitleSession
from cue_pipeline import parse_cues
rows=[
"I never said he stole the money.","Don't let the cat out of the bag.","I'll cover for you, but only this once.","If you had called me, I would have come.","The key is under the third flowerpot.",
"Did you say fifteen or fifty?","No, she didn't cancel the meeting.","Please turn the music down, not off.","He's my older brother, not my father.","Wait here until the lights come back on.",
"I owe you an apology.","You can count on me.","That was a close call.","Keep an eye on the children.","I'm running out of patience.",
"The train leaves at half past seven.","We have three minutes before the door locks.","Don't touch the red wire.","I thought you were joking.","She has never been to Hanoi.",
"I'd rather walk than take the bus.","Put the envelope on my desk.","The doctor told me to rest.","It costs twice as much as yesterday.","I wish I could stay longer.",
"You're pulling my leg, right?","We can't afford to lose another hour.","He isn't as brave as he looks.","The rain stopped just before dawn.","Please don't tell my mother.",
"Let me know when you get home.","The password is not written on the wall.","We need to leave before midnight.","She turned down the offer.","You didn't have to do that.",
"What's the point of arguing now?","He promised to be here by noon.","The second bus is going the wrong way.","Don't worry, I haven't forgotten.","I can't hear you over the wind.",
"This isn't your fault.","There are only two seats left.","I have a feeling we're being followed.","The old bridge is closed for repairs.","I will meet you outside the library.",
"That plan sounds too good to be true.","I'm not asking you to forgive him.","We should have brought a flashlight.","Just give me five more minutes.","Let's get out of here before it gets dark."
]
def ts(n):
    return f"00:{n//60:02d}:{n%60:02d},000"
source=("\n\n".join(f"{i+1}\n{ts(i*4)} --> {ts(i*4+3)}\n{v}" for i,v in enumerate(rows))+"\n").encode()
profile=load_profile(root/"translator_profile.json")
result={"schema":"TTV-HYDROGEN-BENCH-V1","nonce":nonce,"configured":profile.model if profile.model in ("gemini-4-hydrogen-high","gemini-4-hydrogen-medium") else "OTHER","rows":[]}
def save():
    dest.write_text(json.dumps(result,ensure_ascii=True,separators=(",",":")),"utf-8")
save()
for model in ("gemini-4-hydrogen-low","gemini-4-neon-low"):
    level=model.removeprefix("gemini-4-").removesuffix("-low")
    p=ModelProfile("antigravity",model,"low")
    row={"level":level,"status":"STARTED","ms":0,"cues":0,"examples":[]}
    result["rows"].append(row);save()
    begin=time.perf_counter()
    try:
        preflight_provider(p)
        session=ProgressiveSubtitleSession(source,"srt","media."+"d"*64,first_window_cues=50)
        window=session.next_window()
        assert len(window.ids)==50
        trans=translate_window(window,p,glossary={})
        rev=session.commit(window,trans,expected_version=0,source_sha256=session.source_sha256,media_key=session.media_key)
        en=parse_cues(source,"srt");vi=parse_cues(rev.payload,"srt")
        assert [(x.number,x.start_ms,x.end_ms) for x in en]==[(x.number,x.start_ms,x.end_ms) for x in vi]
        row.update(status="PASS",cues=len(vi),examples=[{"id":i,"vi":trans[i][:180]} for i in (1,2,3,4,6,7,26,49)])
    except Exception as exc:
        err=str(exc)
        row["status"]=err if re.fullmatch(r"[A-Z0-9_]{3,75}",err) else "OTHER_ERROR"
    finally:
        row["ms"]=round((time.perf_counter()-begin)*1000);save()

'@
& py -3 -I -B -c $code $root $dest $r.nonce
if ($LASTEXITCODE -ne 0) { throw 'HYDROGEN_BENCHMARK_FAILED' }

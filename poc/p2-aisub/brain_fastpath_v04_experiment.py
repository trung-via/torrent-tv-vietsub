"""Brain-first v0.4 experimental planner + real interactive wall-clock recorder.

OFFLINE ONLY. Does NOT call an LLM, provider API, ChatGPT UI, Gemini, or TV.
Private subtitle input & cue-bearing prompts must remain OUTSIDE PUBLIC repo.
Do not promote a variant to production based on synthetic tests.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
from typing import Any
import unicodedata

from cue_pipeline import Cue, parse_cues

SCHEMA = "torrent-tv-brain-fastpath-v04-experiment-v1"
ENGINES = {"CHATGPT_BRAIN_GPT6_INTERACTIVE"}
ARMS = ("BASE120", "LEAN120", "ADAPTIVE")
STAGES = ("translation", "ingest", "qa", "repair")
GLOBAL_RULES = (
    "Translate authorized English subtitle TARGET cues into natural Vietnamese. "
    "Maintain names, relationships, speakers, negation, humor, and style. "
    "Output exactly ID|Vietnamese text in TARGET order. Use literal \\n for line two. "
    "No explanations, timestamps, Markdown, or context IDs. Preserve markup and "
    "two-speaker dash boundaries, never move a question/answer between cue IDs. "
    "Prefer <=42 visible chars per line and <=17 CPS where faithful to meaning; "
    "do not delete important meaning to satisfy a readability warning."
)
TAG = re.compile(r"<[^<>]+>")
PRONOUN = re.compile(r"\b(you|he|she|they|him|her|his|hers|their|we|us|our)\b", re.I)
NEGATION = re.compile(r"\b(no|not|never|none|without|cannot|can't|don't|doesn't|didn't|won't|isn't|aren't)\b", re.I)


class ExperimentBlocked(Exception):
    """Sanitized error code only, no subtitle text, private paths, or OS messages."""


def _reject(code: str) -> None:
    raise ExperimentBlocked(code)


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _json(data: dict[str, Any]) -> bytes:
    return (json.dumps(data, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def _write_new(path: Path, data: bytes) -> None:
    # 'xb' prevents automatic overwrite of old evidence/results.
    with path.open("xb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())


def _update_atomic(path: Path, data: bytes) -> None:
    tmp = path.with_name(path.name + ".next")
    if tmp.exists():
        _reject("V04_STALE_UPDATE_FILE")
    _write_new(tmp, data)
    os.replace(tmp, path)


def _read_json(path: Path) -> dict[str, Any]:
    try:
        obj = json.loads(path.read_text("utf-8"))
    except (OSError, UnicodeError, ValueError):
        _reject("V04_PRIVATE_STATE_INVALID")
    if not isinstance(obj, dict):
        _reject("V04_PRIVATE_STATE_INVALID")
    return obj


def _ranges(raw: str, total: int) -> list[tuple[int, int]]:
    out = []
    for term in raw.split(","):
        m = re.fullmatch(r"(\d+)-(\d+)", term.strip())
        if not m:
            _reject("V04_WINDOW_FORMAT")
        a, b = int(m[1]), int(m[2])
        if not (1 <= a <= b <= total) or b - a + 1 != 160:
            _reject("V04_REQUIRES_160_CUE_WINDOWS")
        if any(not (b < x or a > y) for x, y in out):
            _reject("V04_WINDOWS_OVERLAP")
        out.append((a, b))
    if len(out) < 3 or len(out) > 8:
        _reject("V04_THREE_TO_EIGHT_WINDOWS_REQUIRED")
    return out


def _risk(c: Cue) -> int:
    text = c.text
    score = 0
    if "?" in text:
        score += 2
    if NEGATION.search(text):
        score += 2
    if PRONOUN.search(text):
        score += 1
    lines = text.split("\n")
    if len(lines) >= 2 and sum(bool(re.match(r"^\s*-\s+", l)) for l in lines) >= 2:
        score += 2
    if ((sum(len(s) for s in lines) * 1000) / (c.end_ms - c.start_ms)) > 17:
        score += 1
    return score


def _split(target: tuple[Cue, ...], arm: str) -> list[tuple[tuple[Cue, ...], int]]:
    if arm not in ARMS or not target:
        _reject("V04_INVALID_ARM")
    groups: list[tuple[tuple[Cue, ...], int]] = []
    pos = 0
    while pos < len(target):
        remaining = target[pos:]
        if arm == "ADAPTIVE":
            risk_density = sum(_risk(c) > 0 for c in remaining[:min(24,len(remaining))]) / min(24, len(remaining))
            cap = 72 if risk_density >= 0.50 else 100 if risk_density >= 0.25 else 160
            context = 8 if risk_density >= 0.25 else 4
        else:
            cap, context = 120, 4
        batch: list[Cue] = []
        budget = 0
        for c in remaining:
            cost = len(c.text) + len(str(c.number)) + 2
            if batch and (len(batch) >= cap or budget + cost > 6500):
                break
            # Prefer a large scene gap, but only after a substantial batch.
            if (arm == "ADAPTIVE" and len(batch) >= 60
                and c.start_ms - batch[-1].end_ms >= 4000):
                break
            batch.append(c)
            budget += cost
        if not batch:
            _reject("V04_EMPTY_BATCH")
        groups.append((tuple(batch), context))
        pos += len(batch)
    flat = [c.number for g,_ in groups for c in g]
    if flat != [c.number for c in target]:
        _reject("V04_BATCH_COVERAGE_FAILED")
    return groups


def _prompt(all_cues: tuple[Cue,...], batch: tuple[Cue,...], ctx: int, arm: str, glossary: str) -> bytes:
    before = all_cues[max(0, batch[0].number - 1 - ctx): batch[0].number - 1]
    after = all_cues[batch[-1].number: batch[-1].number + ctx]
    # Global rules are presented ONCE before each arm's session (same SHA).
    # BASE120 follows the v0.3.5 FastPath mode structure; LEAN reduces only
    # per-chunk overhead, not the shared requirements or supplied context.
    if arm == "BASE120":
        header = "MODE: FAST\nEXPECTED: one ID|VI per TARGET; no context IDs."
    elif arm == "LEAN120":
        header = "FAST | TARGET IDs only | ID|VI"
    else:
        header = "FAST ADAPTIVE | TARGET IDs only | ID|VI"
    # Glossary is user-private; use the SAME bytes for every arm of one experiment.
    lines = [header, "GLOSSARY:", glossary, "CONTEXT BEFORE (READ ONLY):"]
    lines.extend(f"{c.number}|{c.text.replace(chr(10), ' / ')}" for c in before)
    lines.append("TARGET:")
    lines.extend(f"{c.number}|{c.text.replace(chr(10), r'\n')}" for c in batch)
    lines.append("CONTEXT AFTER (READ ONLY):")
    lines.extend(f"{c.number}|{c.text.replace(chr(10), ' / ')}" for c in after)
    return ("\n".join(lines) + "\n").encode("utf-8")


def plan(source: Path, root: Path, ranges: str, glossary_file: Path | None = None) -> dict[str, Any]:
    if source.suffix.lower() != ".srt":
        _reject("V04_SRT_ONLY_EXPERIMENT")
    try:
        source_bytes = source.read_bytes()
        cues = parse_cues(source_bytes, "srt")
        glossary_bytes = glossary_file.read_bytes() if glossary_file else b""
        glossary = glossary_bytes.decode("utf-8-sig").strip()
    except (ValueError, OSError, UnicodeError):
        _reject("V04_SOURCE_OR_GLOSSARY_INVALID")
    if len(glossary_bytes) > 5000 or "\x00" in glossary:
        _reject("V04_GLOSSARY_INVALID")
    windows = _ranges(ranges, len(cues))
    # Do not permit private prompts/material inside the public source checkout.
    repo_root = Path(__file__).resolve().parents[2]
    if root.resolve() == repo_root or repo_root in root.resolve().parents:
        _reject("V04_PRIVATE_WORKDIR_MUST_BE_OUTSIDE_REPO")
    if root.exists():
        _reject("V04_WORKDIR_ALREADY_EXISTS")
    trials = []
    for wi,(a,b) in enumerate(windows):
        target = cues[a-1:b]
        for oi in range(3):
            arm = ARMS[(wi + oi) % 3]
            groups = _split(target, arm)
            prompts = []
            for j,(batch,ctx) in enumerate(groups,1):
                payload = _prompt(cues,batch,ctx,arm,glossary)
                prompts.append({"file":f"prompt_{j:02d}.txt","sha256":_sha(payload),
                                "first":batch[0].number,"last":batch[-1].number,
                                "count":len(batch),"context":ctx,"target_chars":sum(len(c.text) for c in batch)})
            trials.append({"id":f"W{wi+1:02d}-{arm}","window":[a,b],
                           "arm":arm,"order":oi+1,"prompts":prompts,
                           "risk_cues":sum(_risk(c)>0 for c in target)})
    manifest = {"schema":SCHEMA,"source_sha256":_sha(source_bytes),
                "glossary_sha256":_sha(glossary_bytes),"global_rules_sha256":_sha((GLOBAL_RULES+"\n").encode("utf-8")),
                "source_cues":len(cues),
                "engine_policy":"BRAIN_PRIMARY_CHATGPT_INTERACTIVE","mode":"RESEARCH_NOT_DEFAULT",
                "trials":trials}
    # Plan is fully computed before creating private directories; no overwrites.
    try:
        root.mkdir(parents=True, exist_ok=False)
        _write_new(root/"GLOBAL_INSTRUCTIONS.txt", (GLOBAL_RULES+"\n").encode("utf-8"))
        for trial in trials:
            sub = root/trial["id"]
            sub.mkdir()
            arm = trial["arm"]
            target = cues[trial["window"][0]-1:trial["window"][1]]
            for meta, (batch, ctx) in zip(trial["prompts"], _split(target, arm)):
                payload = _prompt(cues, batch, ctx, arm, glossary)
                _write_new(sub/meta["file"], payload)
        _write_new(root/"manifest.json",_json(manifest))
    except (OSError, ValueError):
        _reject("V04_PRIVATE_WRITE_FAILED")
    return {"status":"PLANNED_NO_TRANSLATION","source_sha256":manifest["source_sha256"],
            "windows":len(windows),"trials":len(trials),"private_only":True,"model_calls":0}


def _validate(root:Path, source:Path, trial_id:str) -> tuple[dict[str,Any],dict[str,Any],tuple[Cue,...]]:
    m = _read_json(root/"manifest.json")
    if m.get("schema") != SCHEMA:
        _reject("V04_SCHEMA_MISMATCH")
    try:
        global_bytes=(root/"GLOBAL_INSTRUCTIONS.txt").read_bytes()
    except OSError:
        _reject("V04_GLOBAL_RULES_CHANGED")
    if _sha(global_bytes)!=m.get("global_rules_sha256"):
        _reject("V04_GLOBAL_RULES_CHANGED")
    try:
        content=source.read_bytes()
        cues=parse_cues(content,"srt")
    except (OSError,ValueError):
        _reject("V04_SOURCE_INVALID")
    if _sha(content)!=m.get("source_sha256") or len(cues)!=m.get("source_cues"):
        _reject("V04_SOURCE_SHA_CHANGED")
    matches=[x for x in m.get("trials",[]) if x.get("id")==trial_id]
    if len(matches)!=1:
        _reject("V04_UNKNOWN_TRIAL")
    t=matches[0]
    for meta in t["prompts"]:
        try:
            data=(root/trial_id/meta["file"]).read_bytes()
        except OSError:
            _reject("V04_PROMPT_CHANGED")
        if _sha(data)!=meta["sha256"]:
            _reject("V04_PROMPT_CHANGED")
    return m,t,cues


def start(root:Path,source:Path,trial_id:str,engine:str) -> dict[str,Any]:
    _,t,_=_validate(root,source,trial_id)
    if engine not in ENGINES:
        _reject("V04_BRAIN_ONLY_EXPERIMENT")
    f=root/trial_id/"timer.json"
    if f.exists():
        _reject("V04_TRIAL_ALREADY_STARTED")
    now=time.monotonic_ns()
    data={"state":"RUNNING","started_utc":_now(),"started_ns":now,
          "engine_declared":engine,"last_ns":now,"phases":{},"active":None,
          "timing_scope":"INTERACTIVE_WALL_WITH_IDLE_UNLESS_TIMED_SEPARATELY"}
    _write_new(f,_json(data))
    return {"status":"STARTED","trial":t["id"],"engine_declared":engine}


def phase(root:Path,source:Path,trial_id:str,stage:str,event:str) -> dict[str,Any]:
    _validate(root,source,trial_id)
    if stage not in STAGES or event not in ("begin","end","skip"):
        _reject("V04_UNKNOWN_PHASE")
    f=root/trial_id/"timer.json"
    d=_read_json(f)
    if d.get("state")!="RUNNING":
        _reject("V04_TIMER_NOT_RUNNING")
    phases=d["phases"]
    now=time.monotonic_ns()
    if now<d.get("last_ns",now):
        _reject("V04_MONOTONIC_CLOCK_RESET")
    if event=="begin":
        if d["active"] is not None or stage in phases:
            _reject("V04_PHASE_ALREADY_OPEN_OR_RECORDED")
        preceding = STAGES[:STAGES.index(stage)]
        if any(x not in phases for x in preceding):
            _reject("V04_PHASE_ORDER_REQUIRED")
        d["active"]={"stage":stage,"at_ns":now}
    elif event=="end":
        active=d["active"]
        if not active or active.get("stage")!=stage or stage in phases:
            _reject("V04_PHASE_NOT_ACTIVE")
        phases[stage]=round((now-active["at_ns"])/1e9,3)
        d["active"]=None
    else:
        if (stage not in ("repair",) or d["active"] is not None or stage in phases
            or any(x not in phases for x in STAGES[:-1])):
            _reject("V04_ONLY_REPAIR_CAN_BE_EXPLICITLY_SKIPPED")
        phases[stage]=0.0
    d["last_ns"]=now
    _update_atomic(f,_json(d))
    return {"status":"PHASE_RECORDED","trial":trial_id,"stage":stage,"event":event}


def _translated(blob:bytes, target:tuple[Cue,...]) -> dict[int,str]:
    try:
        s=blob.decode("utf-8-sig")
    except UnicodeDecodeError:
        _reject("V04_TRANSLATED_UTF8_REQUIRED")
    if "\x00" in s or "\r" in s:
        _reject("V04_TRANSLATED_TEXT_INVALID")
    rows=[x for x in s.split("\n") if x]
    if len(rows)!=len(target):
        _reject("V04_TRANSLATED_CUE_COUNT_MISMATCH")
    out={}
    for row,c in zip(rows,target):
        if "|" not in row:
            _reject("V04_TRANSLATED_ID_FORMAT_INVALID")
        key,txt=row.split("|",1)
        if key!=str(c.number) or not txt.strip():
            _reject("V04_TRANSLATED_ID_MISMATCH_OR_EMPTY")
        if "\\n" in txt:
            txt=txt.replace("\\n","\n")
        if len(txt.split("\n"))>2 or len(txt)>2000:
            _reject("V04_TRANSLATED_LINE_LIMIT")
        if TAG.findall(c.text)!=TAG.findall(txt):
            _reject("V04_TRANSLATED_MARKUP_LOST")
        def speakers(v:str) -> int:
            return sum(bool(re.match(r"^\s*-\s+",TAG.sub("",x))) for x in v.split("\n"))
        if speakers(c.text)>=2 and speakers(txt)<2:
            _reject("V04_SPEAKER_BOUNDARY_LOST")
        out[c.number]=unicodedata.normalize("NFC",txt)
    return out


def finish(root:Path,source:Path,trial_id:str,translation:Path,repairs:int=0) -> dict[str,Any]:
    _,t,cues=_validate(root,source,trial_id)
    dfile=root/trial_id/"timer.json"
    d=_read_json(dfile)
    if d.get("state")!="RUNNING" or d["active"] is not None:
        _reject("V04_TIMER_NOT_READY_TO_STOP")
    if set(d["phases"])!=set(STAGES):
        _reject("V04_MISSING_MEASURED_PHASES")
    if type(repairs) is not int or repairs<0 or repairs>160:
        _reject("V04_INVALID_REPAIR_COUNT")
    try:
        raw=translation.read_bytes()
    except OSError:
        _reject("V04_TRANSLATION_FILE_MISSING")
    a,b=t["window"]
    matched=_translated(raw,cues[a-1:b])
    end=time.monotonic_ns()
    if end<d.get("last_ns",0) or end<d.get("started_ns",0):
        _reject("V04_MONOTONIC_CLOCK_RESET")
    wall=round((end-d["started_ns"])/1e9,3)
    measured=round(sum(d["phases"].values()),3)
    flags_42=sum(any(len(TAG.sub("",line))>42 for line in v.split("\n")) for v in matched.values())
    flags_17=sum((len(TAG.sub("",v).replace("\n",""))*1000)/(c.end_ms-c.start_ms)>17
                 for c in cues[a-1:b] for v in [matched[c.number]])
    d.update({"state":"STOPPED_STRUCTURAL_ONLY","finished_utc":_now(),
              "wall_s":wall,"measured_phase_s":measured,"unattributed_wall_s":round(max(0,wall-measured),3),
              "translated_sha256":_sha(raw),"translated_cues":len(matched),"over42_cues":flags_42,
              "over17_cps_cues":flags_17,"reported_repaired_cues":repairs,
              "semantic_review":"NOT_INDEPENDENTLY_REVIEWED","freshness":"DECLARED_NOT_ATTESTED",
              "default_change_authorized":False})
    _update_atomic(dfile,_json(d))
    return {"status":d["state"],"trial":trial_id,"wall_s":wall,
            "cues":len(matched),"semantic_review":d["semantic_review"],
            "default_change_authorized":False}


def summary(root:Path) -> dict[str,Any]:
    m=_read_json(root/"manifest.json")
    if m.get("schema")!=SCHEMA:
        _reject("V04_SCHEMA_MISMATCH")
    finished=[]
    for t in m["trials"]:
        f=root/t["id"]/"timer.json"
        if f.exists():
            d=_read_json(f)
            if d.get("state")=="STOPPED_STRUCTURAL_ONLY":
                finished.append({"trial":t["id"],"arm":t["arm"],"wall_s":d["wall_s"],
                                 "over42_cues":d["over42_cues"],"over17_cps_cues":d["over17_cps_cues"],
                                 "semantic_review":d["semantic_review"]})
    return {"status":"INCOMPLETE_NOT_COMPARABLE" if len(finished)<len(m["trials"]) else "TIMINGS_COLLECTED_INDEPENDENT_SEMANTIC_REVIEW_REQUIRED",
            "total_trials":len(m["trials"]),"finished_trials":len(finished),"results":finished,
            "winner":"NONE","brain_default":"FAST120_V035_UNCHANGED","model_calls":0}


def main(argv:list[str]|None=None) -> int:
    p=argparse.ArgumentParser(description="OFFLINE Brain FastPath v0.4 research (NO LLM calls)")
    subs=p.add_subparsers(dest="command",required=True)
    q=subs.add_parser("plan");q.add_argument("--source",type=Path,required=True);q.add_argument("--workdir",type=Path,required=True)
    q.add_argument("--ranges",required=True);q.add_argument("--glossary",type=Path)
    q=subs.add_parser("start");q.add_argument("--source",type=Path,required=True);q.add_argument("--workdir",type=Path,required=True)
    q.add_argument("--trial",required=True);q.add_argument("--engine",default="CHATGPT_BRAIN_GPT6_INTERACTIVE")
    q=subs.add_parser("phase");q.add_argument("--source",type=Path,required=True);q.add_argument("--workdir",type=Path,required=True)
    q.add_argument("--trial",required=True);q.add_argument("--stage",required=True);q.add_argument("--event",required=True)
    q=subs.add_parser("finish");q.add_argument("--source",type=Path,required=True);q.add_argument("--workdir",type=Path,required=True)
    q.add_argument("--trial",required=True);q.add_argument("--translations",type=Path,required=True);q.add_argument("--repairs",type=int,default=0)
    q=subs.add_parser("summary");q.add_argument("--workdir",type=Path,required=True)
    args=p.parse_args(argv)
    try:
        if args.command=="plan":out=plan(args.source,args.workdir,args.ranges,args.glossary)
        elif args.command=="start":out=start(args.workdir,args.source,args.trial,args.engine)
        elif args.command=="phase":out=phase(args.workdir,args.source,args.trial,args.stage,args.event)
        elif args.command=="finish":out=finish(args.workdir,args.source,args.trial,args.translations,args.repairs)
        else:out=summary(args.workdir)
        print(json.dumps(out,sort_keys=True,ensure_ascii=True))
        return 0
    except (ExperimentBlocked,OSError,ValueError,KeyError,TypeError) as err:
        code=str(err) if isinstance(err,ExperimentBlocked) else "V04_INPUT_OR_STATE_INVALID"
        print(json.dumps({"status":"BLOCKED","error_code":code},sort_keys=True))
        return 2


if __name__=="__main__":
    raise SystemExit(main())
